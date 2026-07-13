--- The service passes (DESIGN.md §1.1): collect outputs/burnt results (+chests
--- and ground items, opt-in), feed fuel, feed ingredients (smelt map for recipe-less
--- furnaces), feed ammo, drain trash slots into chests. One call to Raid.service
--- handles one player for one cycle; the scheduler decides when. Every transfer is
--- tallied into a per-cycle report that feeds the production-graph statistics item
--- and the optional flying-text summary (§4.4, §10.5).

local State = require('__lazy-bastards-friend__.scripts.state')
local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Distribution = require('__lazy-bastards-friend__.scripts.lib.distribution')
local Rendering = require('__lazy-bastards-friend__.scripts.rendering')

local Raid = {}

local AFK_TICKS = 5 * 60 * 60 -- after 5 min AFK, service at 1/4 rate
local CACHE_CYCLES = 10 -- re-scan at most every N update periods
local CACHE_MOVE_FRACTION = 0.25 -- re-scan when moved more than radius * this
local FEED_SECONDS = 30 -- top up ingredient inputs to ~this many seconds of crafting/research
local SUMMARY_INTERVAL_TICKS = 600 -- de-noise the flying text vs. the ~1s-per-player raid cycle

-- Everything any pass may want; each pass filters by capability at use time
-- (fuel inventory present, output map entry, turret ammo define).
local SCAN_TYPES = {
    'furnace',
    'assembling-machine',
    'rocket-silo',
    'mining-drill',
    'lab',
    'boiler',
    'inserter',
    'burner-generator',
    'agricultural-tower',
    'ammo-turret',
    'artillery-turret',
}
local CHEST_TYPES = { 'container', 'logistic-container' }

-- Explicit output map: get_output_inventory() on other types can return
-- inventories we must not raid (a turret's "output" is its ammo).
local OUTPUT_INVENTORY = {
    ['furnace'] = defines.inventory.crafter_output,
    ['assembling-machine'] = defines.inventory.crafter_output,
    ['rocket-silo'] = defines.inventory.crafter_output,
    ['agricultural-tower'] = defines.inventory.agricultural_tower_output,
}

local TURRET_AMMO_INVENTORY = {
    ['ammo-turret'] = defines.inventory.turret_ammo,
    ['artillery-turret'] = defines.inventory.artillery_turret_ammo,
}

local IS_CHEST = { ['container'] = true, ['logistic-container'] = true }

-- Crafter types the ingredient pass fills through defines.inventory.crafter_input.
local INGREDIENT_TYPES = { ['furnace'] = true, ['assembling-machine'] = true, ['rocket-silo'] = true }

-- Lookup set of every type a raid could ever touch (SCAN_TYPES + CHEST_TYPES),
-- for the exclusion-toggle hotkey (DESIGN.md §10.4) to validate what's hovered.
local TARGETABLE_TYPE = {}
for _, t in pairs(SCAN_TYPES) do
    TARGETABLE_TYPE[t] = true
end
for _, t in pairs(CHEST_TYPES) do
    TARGETABLE_TYPE[t] = true
end

--- Whether `entity` is a type any raid pass could act on — used by the
--- exclusion-toggle custom-input to validate the hovered entity.
--- @param entity LuaEntity?
--- @return boolean
function Raid.is_targetable(entity)
    return entity ~= nil and entity.valid and TARGETABLE_TYPE[entity.type] == true
end

--- Per-cycle transfer tally: item name -> count, split by direction.
--- @class LbfReport
--- @field collected table<string, integer> machines/ground -> player
--- @field fed table<string, integer> player -> machines/turrets/chests

-- == Smelt map (DESIGN.md §1.1 pass 4) ======================================

--- Rebuild storage.smelt_map: crafting category -> { ingredient item -> {amount,
--- energy} } (per-craft amount and the recipe's crafting time, §1.1's 30s-of-
--- crafting cap needs both), from visible single-item-ingredient recipes. Hidden
--- recipes are excluded on purpose — that keeps recycler-style categories (whose
--- hidden recipes accept nearly every item) out of the map. Call on_init/config_changed.
function Raid.rebuild_smelt_map()
    local map = {}
    for _, recipe in pairs(prototypes.recipe) do
        if not recipe.hidden and not recipe.parameter then
            local ingredients = recipe.ingredients
            local only = #ingredients == 1 and ingredients[1]
            if only and only.type == 'item' then
                for _, category in pairs(recipe.categories) do
                    local set = map[category]
                    if not set then
                        set = {}
                        map[category] = set
                    end
                    local existing = set[only.name]
                    if not existing or only.amount >= existing.amount then
                        set[only.name] = { amount = only.amount, energy = recipe.energy }
                    end
                end
            end
        end
    end
    storage.smelt_map = map
end

-- == Entity cache (DESIGN.md §7) ============================================

--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param anchor LuaEntity center of the service area — the player's character
--- @param include_chests boolean chest-take or trash-drain wants containers scanned
--- @param include_ground boolean ground-item pickup wants item-entities scanned
--- @return LuaEntity[]
local function get_entities(player, data, anchor, include_chests, include_ground)
    local position = anchor.position
    local surface = anchor.surface
    local radius = State.get_radius(player.index)
    local period = settings.global['lbf-update-period'].value --[[@as integer]]

    local key = table.concat(
        { surface.index, radius, data.shape, include_chests and 1 or 0, include_ground and 1 or 0 },
        ':'
    )
    local cache = data.cache
    if
        cache
        and cache.key == key
        and game.tick - cache.tick < CACHE_CYCLES * period
        and (position.x - cache.x) ^ 2 + (position.y - cache.y) ^ 2 < (radius * CACHE_MOVE_FRACTION) ^ 2
    then
        return cache.entities
    end

    local types = SCAN_TYPES
    if include_chests then
        types = {}
        for _, t in pairs(SCAN_TYPES) do
            types[#types + 1] = t
        end
        for _, t in pairs(CHEST_TYPES) do
            types[#types + 1] = t
        end
    end

    --- @type EntitySearchFilters
    local filter = { type = types, force = player.force, to_be_deconstructed = false }
    if data.shape == 'square' then
        -- The AoE shape is also the search shape (§5): what you see is what gets raided.
        filter.area = { { position.x - radius, position.y - radius }, { position.x + radius, position.y + radius } }
    else
        filter.position = position
        filter.radius = radius
    end
    local found = surface.find_entities_filtered(filter)

    if include_ground then
        -- Item-entities are force-neutral, so they need their own unfiltered query.
        --- @type EntitySearchFilters
        local ground_filter = { type = 'item-entity', area = filter.area, position = filter.position, radius = filter.radius }
        for _, entity in pairs(surface.find_entities_filtered(ground_filter)) do
            found[#found + 1] = entity
        end
    end

    local excluded = data.excluded
    local entities = found
    if next(excluded) ~= nil then
        entities = {}
        for _, entity in pairs(found) do
            if not excluded[entity.unit_number] then
                entities[#entities + 1] = entity
            end
        end
    end

    data.cache = { key = key, tick = game.tick, x = position.x, y = position.y, entities = entities }
    return entities
end

-- == Shared helpers =========================================================

--- Player item totals by name, summed across qualities (reserves are per-name, §6).
--- @param main LuaInventory
--- @return table<string, integer>
local function inventory_totals(main)
    local totals = {}
    for _, item in pairs(main.get_contents()) do
        totals[item.name] = (totals[item.name] or 0) + item.count
    end
    return totals
end

--- What the player can spare above their reserve.
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param name string
--- @return integer
local function available(totals, reserves, name)
    return (totals[name] or 0) - (reserves[name] or 0)
end

--- @class LbfFeedGroup
--- @field name string item to distribute
--- @field cap integer? per-target cap; defaults to one stack at distribution time
--- @field inventories LuaInventory[]
--- @field counts integer[]

--- Water-fill each item group across its target inventories, capped per target,
--- and execute the transfers. Decrements `totals` as it goes.
--- @param groups table<string, LbfFeedGroup>
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param report LbfReport
local function distribute_groups(groups, main, totals, reserves, report)
    local fed = report.fed
    for _, group in pairs(groups) do
        local name = group.name
        local budget = available(totals, reserves, name)
        if budget > 0 then
            local cap = group.cap or prototypes.item[name].stack_size
            local gives = Distribution.balanced_fill(group.counts, budget, cap)
            for i, give in ipairs(gives) do
                if give > 0 then
                    local moved = Transfer.give(main, group.inventories[i], name, give)
                    if moved > 0 then
                        totals[name] = totals[name] - moved
                        fed[name] = (fed[name] or 0) + moved
                    end
                end
            end
        end
    end
end

--- Targets with equal caps pool into one group; distinct caps for the same item
--- form separate groups that share the same (decrementing) budget.
--- @param groups table<string, LbfFeedGroup>
--- @param name string
--- @param inventory LuaInventory
--- @param cap integer?
local function add_to_group(groups, name, inventory, cap)
    local key = cap and (name .. '/' .. cap) or name
    local group = groups[key]
    if not group then
        group = { name = name, cap = cap, inventories = {}, counts = {} }
        groups[key] = group
    end
    local n = #group.inventories + 1
    group.inventories[n] = inventory
    group.counts[n] = Transfer.count_by_name(inventory, name)
end

--- First item name in a small inventory, or nil if empty.
--- @param inventory LuaInventory
--- @return string?
local function first_item_name(inventory)
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read then
            return stack.name
        end
    end
    return nil
end

-- == Pass 1+2: collect ======================================================

--- @class LbfRival
--- @field x double
--- @field y double
--- @field radius integer
--- @field square boolean
--- @field chests boolean

--- This player's or another connected player's service-area anchor: the
--- character. Mirrors Raid.service's own anchor choice so rival overlap is
--- checked against where the service area actually is.
--- @param player LuaPlayer
--- @return LuaEntity?
local function service_anchor(player)
    return player.character
end

--- Other players still due in this sweep whose service area may overlap ours:
--- shared collect sources get split with them instead of taken whole (§1.4).
--- Players already serviced this sweep took their share when it was their turn.
--- Returns nil when nobody contests — the fast path costs one loop over `pending`.
--- @param player LuaPlayer
--- @param pending uint[]?
--- @return LbfRival[]?
local function get_rivals(player, pending)
    if not pending then
        return nil
    end
    local anchor = service_anchor(player)
    local surface_index = anchor.surface.index
    local px, py = anchor.position.x, anchor.position.y
    local radius = State.get_radius(player.index)
    local rivals
    for _, index in pairs(pending) do
        if index ~= player.index and State.effective(index, 'collect') then
            local other = game.get_player(index)
            local other_anchor = other and other.connected and service_anchor(other)
            if other_anchor and other_anchor.surface.index == surface_index then
                local other_radius = State.get_radius(index)
                local ox, oy = other_anchor.position.x, other_anchor.position.y
                if math.abs(ox - px) <= radius + other_radius and math.abs(oy - py) <= radius + other_radius then
                    local other_data = State.get_player_data(index)
                    rivals = rivals or {}
                    rivals[#rivals + 1] = {
                        x = ox,
                        y = oy,
                        radius = other_radius,
                        square = other_data.shape == 'square',
                        chests = other_data.flags.chests,
                    }
                end
            end
        end
    end
    return rivals
end

--- How many players get a cut of this entity: us + every rival whose area
--- covers it (their AoE shape is their search shape, §5).
--- @param entity LuaEntity
--- @param rivals LbfRival[]
--- @param is_chest boolean chests only count rivals who take from chests
--- @return integer
local function claim_divisor(entity, rivals, is_chest)
    local k = 1
    local position = entity.position
    for _, rival in pairs(rivals) do
        if not is_chest or rival.chests then
            local dx, dy = position.x - rival.x, position.y - rival.y
            local inside
            if rival.square then
                inside = math.abs(dx) <= rival.radius and math.abs(dy) <= rival.radius
            else
                inside = dx * dx + dy * dy <= rival.radius * rival.radius
            end
            if inside then
                k = k + 1
            end
        end
    end
    return k
end

--- Take a 1/k share of each item in the source (by name, across qualities).
--- The floor remainder stays put for the players still due this sweep.
--- @param source LuaInventory
--- @param dest LuaInventory
--- @param k integer
--- @param report LbfReport
local function take_share(source, dest, k, report)
    local totals = {}
    for _, item in pairs(source.get_contents()) do
        totals[item.name] = (totals[item.name] or 0) + item.count
    end
    local collected = report.collected
    for name, count in pairs(totals) do
        local share = k > 1 and math.floor(count / k) or count
        if share > 0 then
            local moved = Transfer.give(source, dest, name, share)
            if moved > 0 then
                collected[name] = (collected[name] or 0) + moved
            end
        end
    end
end

--- Scoop one ground stack whole — no fair-share split; a single dropped stack
--- is not worth the shape checks.
--- @param entity LuaEntity item-entity
--- @param main LuaInventory
--- @param report LbfReport
local function take_ground_item(entity, main, report)
    local stack = entity.stack
    if not (stack and stack.valid_for_read) then
        return
    end
    local name = stack.name
    local moved = Transfer.stack_into(stack, main)
    if moved > 0 then
        report.collected[name] = (report.collected[name] or 0) + moved
    end
    -- Emptying the stack usually removes the entity; sweep up if it lingers.
    if entity.valid then
        local rest = entity.stack
        if not (rest and rest.valid_for_read) then
            entity.destroy()
        end
    end
end

--- @param entities LuaEntity[]
--- @param main LuaInventory
--- @param take_chests boolean
--- @param rivals LbfRival[]?
--- @param report LbfReport
local function collect_pass(entities, main, take_chests, rivals, report)
    for _, entity in pairs(entities) do
        if entity.valid then
            if entity.type == 'item-entity' then
                take_ground_item(entity, main, report)
            else
                local is_chest = IS_CHEST[entity.type]
                local k = rivals and claim_divisor(entity, rivals, is_chest or false) or 1
                local output_define = OUTPUT_INVENTORY[entity.type]
                if output_define then
                    local output = entity.get_inventory(output_define)
                    if output and not output.is_empty() then
                        take_share(output, main, k, report)
                    end
                end
                local burnt = entity.get_burnt_result_inventory()
                if burnt and not burnt.is_empty() then
                    take_share(burnt, main, k, report)
                end
                if take_chests and is_chest then
                    local chest = entity.get_inventory(defines.inventory.chest)
                    if chest and not chest.is_empty() then
                        take_share(chest, main, k, report)
                    end
                end
            end
        end
    end
end

-- == Pass 3: feed fuel ======================================================

--- @class LbfFuelCandidate
--- @field name string
--- @field category string
--- @field value double

--- Spareable fuel items the player carries, best (highest fuel value) first —
--- nuclear before rocket fuel before solid fuel before coal before wood, all
--- derived from prototype fuel values. Reserves are the tool to hold good fuel back.
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @return LbfFuelCandidate[]
local function get_player_fuels(totals, reserves)
    local fuels = {}
    for name in pairs(totals) do
        if available(totals, reserves, name) > 0 then
            local proto = prototypes.item[name]
            local category = proto and proto.fuel_category
            if category and proto.fuel_value > 0 then
                fuels[#fuels + 1] = { name = name, category = category, value = proto.fuel_value }
            end
        end
    end
    table.sort(fuels, function(a, b)
        return a.value > b.value
    end)
    return fuels
end

--- Fuel to feed this entity: top up whatever is already loaded, else the
--- best carried fuel its burner accepts. Records starved/saturated entities
--- for the optional starvation feedback (DESIGN.md §10.10) when the caller
--- passes those lists (nil when the flag is off — no extra cost).
--- @param entity LuaEntity
--- @param fuel_inventory LuaInventory
--- @param fuels LbfFuelCandidate[]
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param starved LuaEntity[]?
--- @param saturated LuaEntity[]?
--- @return string?
local function pick_fuel(entity, fuel_inventory, fuels, totals, reserves, starved, saturated)
    local current = first_item_name(fuel_inventory)
    if current then
        if available(totals, reserves, current) > 0 then
            if saturated and Transfer.count_by_name(fuel_inventory, current) >= prototypes.item[current].stack_size then
                saturated[#saturated + 1] = entity
            end
            return current
        end
        -- Fuel slots are usually single; mixing in a second fuel type can't
        -- work anyway, so if the player can't spare this one, skip the entity.
        if starved then
            starved[#starved + 1] = entity
        end
        return nil
    end
    local burner = entity.prototype.burner_prototype
    if not burner then
        return nil
    end
    local categories = burner.fuel_categories
    for _, fuel in ipairs(fuels) do
        if categories[fuel.category] then
            return fuel.name
        end
    end
    if starved then
        starved[#starved + 1] = entity
    end
    return nil
end

--- @param entities LuaEntity[]
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param report LbfReport
--- @param starved LuaEntity[]? populated when the starvation flag is on
--- @param saturated LuaEntity[]? populated when the starvation flag is on
local function feed_fuel_pass(entities, main, totals, reserves, report, starved, saturated)
    local fuels = get_player_fuels(totals, reserves)
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local fuel_inventory = entity.get_fuel_inventory()
            if fuel_inventory then
                local name = pick_fuel(entity, fuel_inventory, fuels, totals, reserves, starved, saturated)
                if name then
                    add_to_group(groups, name, fuel_inventory)
                end
            end
        end
    end
    distribute_groups(groups, main, totals, reserves, report)
end

-- == Pass 4: feed ingredients ===============================================

--- Item requirements of the machine's set recipe: the active one, or (furnaces)
--- the recipe it last smelted — an idle furnace keeps making what it made.
--- @param entity LuaEntity
--- @return Ingredient[]?
--- @return double? recipe crafting energy (seconds at crafting_speed 1)
local function recipe_ingredients(entity)
    local recipe = entity.get_recipe()
    if recipe then
        return recipe.ingredients, recipe.energy
    end
    if entity.type == 'furnace' then
        local previous = entity.previous_recipe
        local id = previous and previous.name
        if id then
            local proto = type(id) == 'string' and prototypes.recipe[id] or id
            if proto then
                return proto.ingredients, proto.energy
            end
        end
    end
    return nil
end

--- Per-craft amount + recipe energy of `name` in this machine's smelt-map
--- categories (amount 1 / energy 1 if unknown).
--- @param proto LuaEntityPrototype
--- @param name string
--- @return {amount: integer, energy: double}
local function smelt_entry(proto, name)
    local map = storage.smelt_map or {}
    for category in pairs(proto.crafting_categories) do
        local set = map[category]
        local entry = set and set[name]
        if entry then
            return entry
        end
    end
    return { amount = 1, energy = 1 }
end

--- Best smeltable the player can spare for a fresh (recipe-less, empty) furnace:
--- the most abundant spare input its categories accept, name as tiebreak.
--- @param proto LuaEntityPrototype
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @return string? name
--- @return {amount: integer, energy: double}? entry
local function pick_smelt_input(proto, totals, reserves)
    local map = storage.smelt_map or {}
    local best_name, best_entry, best_spare
    for category in pairs(proto.crafting_categories) do
        local set = map[category]
        if set then
            for name, entry in pairs(set) do
                local spare = available(totals, reserves, name)
                if spare > 0 and (not best_name or spare > best_spare or (spare == best_spare and name < best_name)) then
                    best_name, best_entry, best_spare = name, entry, spare
                end
            end
        end
    end
    return best_name, best_entry
end

--- How many crafts/research-units this entity gets through in ~FEED_SECONDS at
--- its current speed (min 1, so a slow/unresearched entity still gets its full
--- per-craft amount instead of a fraction). Labs have no LuaEntity.crafting_speed
--- (that's crafter/character-only), so derive their speed from the prototype's
--- get_researching_speed() and entity.speed_bonus (force + module/beacon effects
--- on the lab itself — unlike the old force-modifier-only approximation, this is exact).
--- Unlike LuaRecipe.energy (seconds at speed 1), LuaTechnology.research_unit_energy
--- is in ticks, so it needs converting to seconds before it's comparable.
--- @param entity LuaEntity
--- @param energy double? recipe/research energy; nil/0 -> treat as 1 craft
--- @return double
local function crafts_in_window(entity, energy)
    if not energy or energy <= 0 then
        return 1
    end
    local speed
    if entity.type == 'lab' then
        speed = (entity.prototype.get_researching_speed(entity.quality) or 1) * (1 + entity.speed_bonus)
        energy = energy / 60
    else
        speed = entity.crafting_speed
    end
    if not speed or speed <= 0 then
        speed = 0.01
    end
    return math.max(1, FEED_SECONDS * speed / energy)
end

--- @param player LuaPlayer
--- @param entities LuaEntity[]
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param report LbfReport
--- @param starved LuaEntity[]? populated when the starvation flag is on
--- @param saturated LuaEntity[]? populated when the starvation flag is on
local function feed_ingredients_pass(player, entities, main, totals, reserves, report, starved, saturated)
    local research = player.force.current_research
    local research_ingredients = research and research.research_unit_ingredients
    local research_energy = research and research.research_unit_energy
    local lab_accepts = {} -- lab prototype name -> { pack name -> true }
    local track = starved ~= nil or saturated ~= nil
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local entity_type = entity.type
            -- Per-entity starvation bookkeeping: any unspareable ingredient
            -- marks it starved; if every checked ingredient is already at its
            -- cap, it's saturated. Skipped entirely (both lists nil) when the
            -- starvation flag is off.
            local wants_any, is_starved, is_saturated = false, false, true
            if INGREDIENT_TYPES[entity_type] then
                local input = entity.get_inventory(defines.inventory.crafter_input)
                if input then
                    local ingredients, energy = recipe_ingredients(entity)
                    if ingredients then
                        local crafts = crafts_in_window(entity, energy)
                        for _, ingredient in pairs(ingredients) do
                            if ingredient.type == 'item' then
                                wants_any = true
                                local cap = math.ceil(ingredient.amount * crafts)
                                if available(totals, reserves, ingredient.name) > 0 then
                                    add_to_group(groups, ingredient.name, input, cap)
                                    if track and Transfer.count_by_name(input, ingredient.name) < cap then
                                        is_saturated = false
                                    end
                                else
                                    is_starved = true
                                end
                            end
                        end
                    elseif entity_type == 'furnace' then
                        -- No recipe history: top up what's loaded, else infer
                        -- from the smelt map (§1.1 pass 4).
                        local proto = entity.prototype
                        local name = first_item_name(input)
                        local entry
                        if name then
                            entry = smelt_entry(proto, name)
                            if available(totals, reserves, name) <= 0 then
                                wants_any, is_starved = true, true
                                name = nil
                            end
                        else
                            name, entry = pick_smelt_input(proto, totals, reserves)
                        end
                        if name and entry then
                            wants_any = true
                            local crafts = crafts_in_window(entity, entry.energy)
                            local cap = math.ceil(entry.amount * crafts)
                            add_to_group(groups, name, input, cap)
                            if track and Transfer.count_by_name(input, name) < cap then
                                is_saturated = false
                            end
                        end
                    end
                end
            elseif entity_type == 'lab' and research_ingredients then
                -- Feed only what current research consumes and this lab accepts.
                local input = entity.get_inventory(defines.inventory.lab_input)
                if input then
                    local proto = entity.prototype
                    local accepts = lab_accepts[proto.name]
                    if not accepts then
                        accepts = {}
                        for _, name in pairs(proto.lab_inputs or {}) do
                            accepts[name] = true
                        end
                        lab_accepts[proto.name] = accepts
                    end
                    local crafts = crafts_in_window(entity, research_energy)
                    for _, ingredient in pairs(research_ingredients) do
                        if accepts[ingredient.name] then
                            wants_any = true
                            local cap = math.ceil(ingredient.amount * crafts)
                            if available(totals, reserves, ingredient.name) > 0 then
                                add_to_group(groups, ingredient.name, input, cap)
                                if track and Transfer.count_by_name(input, ingredient.name) < cap then
                                    is_saturated = false
                                end
                            else
                                is_starved = true
                            end
                        end
                    end
                end
            end
            if track and wants_any then
                if is_starved then
                    if starved then
                        starved[#starved + 1] = entity
                    end
                elseif is_saturated and saturated then
                    saturated[#saturated + 1] = entity
                end
            end
        end
    end
    distribute_groups(groups, main, totals, reserves, report)
end

-- == Pass 5: feed ammo ======================================================

--- @class LbfAmmoCandidate
--- @field name string
--- @field category string
--- @field order string

--- Spareable ammo items the player carries.
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @return LbfAmmoCandidate[]
local function get_player_ammo(totals, reserves)
    local ammo = {}
    for name in pairs(totals) do
        if available(totals, reserves, name) > 0 then
            local proto = prototypes.item[name]
            local category = proto and proto.ammo_category
            if category then
                ammo[#ammo + 1] = { name = name, category = category.name, order = proto.order }
            end
        end
    end
    return ammo
end

--- Ammo to feed this turret: top up what it already holds, else the best
--- (highest prototype order — vanilla orders ascend by tier) carried ammo
--- matching the turret's categories.
--- @param turret LuaEntity
--- @param ammo_inventory LuaInventory
--- @param candidates LbfAmmoCandidate[]
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @return string?
local function pick_ammo(turret, ammo_inventory, candidates, totals, reserves)
    local current = first_item_name(ammo_inventory)
    if current then
        if available(totals, reserves, current) > 0 then
            return current
        end
        return nil
    end
    -- Artillery turrets have no attack_parameters (they live on the gun
    -- prototype), so fall back to asking the ammo inventory itself — it
    -- enforces the accepted ammo category on insert.
    local params = turret.prototype.attack_parameters
    local categories = params and params.ammo_categories
    local best
    for _, ammo in pairs(candidates) do
        local accepts
        if categories then
            accepts = false
            for _, category in pairs(categories) do
                if ammo.category == category then
                    accepts = true
                    break
                end
            end
        else
            accepts = ammo_inventory.can_insert(ammo.name)
        end
        if accepts and (not best or ammo.order > best.order) then
            best = ammo
        end
    end
    return best and best.name
end

--- @param entities LuaEntity[]
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param report LbfReport
local function feed_ammo_pass(entities, main, totals, reserves, report)
    local candidates = get_player_ammo(totals, reserves)
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for _, turret in pairs(entities) do
        if turret.valid then
            local ammo_define = TURRET_AMMO_INVENTORY[turret.type]
            if ammo_define then
                local ammo_inventory = turret.get_inventory(ammo_define)
                if ammo_inventory then
                    local name = pick_ammo(turret, ammo_inventory, candidates, totals, reserves)
                    if name then
                        -- One stack is the wrong ceiling for artillery (shells
                        -- stack to 1): allow what inserters would load instead.
                        local cap = math.max(
                            turret.prototype.automated_ammo_count or 0,
                            prototypes.item[name].stack_size
                        )
                        add_to_group(groups, name, ammo_inventory, cap)
                    end
                end
            end
        end
    end
    distribute_groups(groups, main, totals, reserves, report)
end

-- == Pass 6: rebalance (DESIGN.md §1.1 pass 6, §12) =========================
--
-- Machine-to-machine only — never touches the player's inventory or reserves,
-- so it works even when the player carries nothing. Scoped by **item name**
-- rather than "identical machines" (DESIGN.md's original wording): simpler,
-- and it lets e.g. a coal-hoarding stone furnace feed a coal-starved steel
-- furnace. The ingredient side only considers inventories that *already* hold
-- the item (no empty-acceptance inference — that would duplicate all of
-- feed_ingredients_pass's recipe/smelt-map logic for marginal benefit). Both
-- sides use a flat stack-size cap rather than each pass's finer per-entity
-- cap (FEED_SECONDS, artillery automated_ammo_count, ...) — rebalance only
-- needs a coarse "don't overfill" ceiling, not an exact one.

--- Fuel-item groups: every fuel inventory already holding a given item, plus
--- every empty one whose burner accepts that item's fuel category.
--- @param entities LuaEntity[]
--- @return table<string, LbfFeedGroup>
local function rebalance_fuel_groups(entities)
    local present, infos = {}, {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local fuel_inventory = entity.get_fuel_inventory()
            if fuel_inventory then
                local name = first_item_name(fuel_inventory)
                infos[#infos + 1] = { entity = entity, inventory = fuel_inventory, name = name }
                if name then
                    present[name] = true
                end
            end
        end
    end
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for name in pairs(present) do
        local cap = prototypes.item[name].stack_size
        local category = prototypes.item[name].fuel_category
        for _, info in pairs(infos) do
            if info.name == name then
                add_to_group(groups, name, info.inventory, cap)
            elseif not info.name and category then
                local burner = info.entity.prototype.burner_prototype
                if burner and burner.fuel_categories[category] then
                    add_to_group(groups, name, info.inventory, cap)
                end
            end
        end
    end
    return groups
end

--- Ingredient-item groups: every crafter/lab input inventory already holding
--- a given item.
--- @param entities LuaEntity[]
--- @return table<string, LbfFeedGroup>
local function rebalance_ingredient_groups(entities)
    local present, inventories = {}, {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local entity_type = entity.type
            local input
            if INGREDIENT_TYPES[entity_type] then
                input = entity.get_inventory(defines.inventory.crafter_input)
            elseif entity_type == 'lab' then
                input = entity.get_inventory(defines.inventory.lab_input)
            end
            if input then
                inventories[#inventories + 1] = input
                for i = 1, #input do
                    local stack = input[i]
                    if stack.valid_for_read then
                        present[stack.name] = true
                    end
                end
            end
        end
    end
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for name in pairs(present) do
        local cap = prototypes.item[name].stack_size
        for _, inventory in pairs(inventories) do
            if Transfer.count_by_name(inventory, name) > 0 then
                add_to_group(groups, name, inventory, cap)
            end
        end
    end
    return groups
end

--- Execute one group's rebalance: compute the shared water level, then pair
--- off donors (holders above it) and receivers (holders below it) with
--- direct inventory-to-inventory transfers — no player inventory involved.
--- @param group LbfFeedGroup
local function rebalance_group(group)
    if #group.inventories < 2 then
        return
    end
    local name = group.name
    local cap = group.cap or prototypes.item[name].stack_size
    local gives, takes = Distribution.rebalance(group.counts, cap)
    local donors = {}
    for i, take in ipairs(takes) do
        if take > 0 then
            donors[#donors + 1] = { inventory = group.inventories[i], remaining = take }
        end
    end
    local di = 1
    for i, give in ipairs(gives) do
        local need = give
        while need > 0 and di <= #donors do
            local donor = donors[di]
            local moved = Transfer.give(donor.inventory, group.inventories[i], name, math.min(need, donor.remaining))
            if moved == 0 then
                di = di + 1
            else
                donor.remaining = donor.remaining - moved
                need = need - moved
                if donor.remaining <= 0 then
                    di = di + 1
                end
            end
        end
    end
end

--- @param entities LuaEntity[]
local function rebalance_pass(entities)
    for _, group in pairs(rebalance_fuel_groups(entities)) do
        rebalance_group(group)
    end
    for _, group in pairs(rebalance_ingredient_groups(entities)) do
        rebalance_group(group)
    end
end

-- == Trash-slot drain (DESIGN.md §10.3) =====================================

--- @class LbfChestTarget
--- @field entity LuaEntity
--- @field inventory LuaInventory
--- @field requests table<string, boolean>? requested/filtered item names
--- @field accepts_any boolean not pull-only and not filtered to specific items

--- Classify the chests in the service area as drain targets. Requester/buffer
--- chests and filtered storage chests only ever receive what they ask for.
--- @param entities LuaEntity[]
--- @return LbfChestTarget[]?
local function chest_targets(entities)
    local targets
    for _, entity in pairs(entities) do
        if entity.valid and IS_CHEST[entity.type] then
            local inventory = entity.get_inventory(defines.inventory.chest)
            if inventory then
                local mode = entity.prototype.logistic_mode
                local requests
                local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
                if point then
                    local filters = point.filters
                    if filters then
                        for _, filter in pairs(filters) do
                            if filter.name and (filter.count or 0) > 0 then
                                requests = requests or {}
                                requests[filter.name] = true
                            end
                        end
                    end
                end
                if mode == 'storage' then
                    local storage_filter = entity.storage_filter
                    if storage_filter then
                        -- ID pairs read back with prototype objects, not strings.
                        local item = storage_filter.name
                        requests = requests or {}
                        requests[type(item) == 'string' and item or item.name] = true
                    end
                end
                local pull_only = mode == 'requester' or mode == 'buffer'
                targets = targets or {}
                targets[#targets + 1] = {
                    entity = entity,
                    inventory = inventory,
                    requests = requests,
                    accepts_any = not pull_only and requests == nil,
                }
            end
        end
    end
    return targets
end

--- Chest priority for one item (§10.3 — never dump blindly): 1. chests already
--- holding it, 2. chests requesting/filtered to it, 3. empty unfiltered chests.
--- @param target LbfChestTarget
--- @param name string
--- @param tier integer
--- @return boolean
local function drain_tier_match(target, name, tier)
    local requested = target.requests and target.requests[name]
    if tier == 1 then
        return (requested or target.accepts_any) and Transfer.count_by_name(target.inventory, name) > 0
    elseif tier == 2 then
        return requested == true
    end
    return target.accepts_any and target.inventory.is_empty() and not target.inventory.is_filtered()
end

--- Move everything from the player's logistic trash into nearby chests.
--- @param player LuaPlayer
--- @param entities LuaEntity[]
--- @param report LbfReport
local function trash_pass(player, entities, report)
    local trash = player.get_inventory(defines.inventory.character_trash)
    if not trash or trash.is_empty() then
        return
    end
    local targets = chest_targets(entities)
    if not targets then
        return
    end
    local totals = {}
    for _, item in pairs(trash.get_contents()) do
        totals[item.name] = (totals[item.name] or 0) + item.count
    end
    local fed = report.fed
    for name, count in pairs(totals) do
        local remaining = count
        for tier = 1, 3 do
            if remaining <= 0 then
                break
            end
            for _, target in pairs(targets) do
                if remaining <= 0 then
                    break
                end
                if target.entity.valid and drain_tier_match(target, name, tier) then
                    local moved = Transfer.give(trash, target.inventory, name, remaining)
                    if moved > 0 then
                        remaining = remaining - moved
                        fed[name] = (fed[name] or 0) + moved
                    end
                end
            end
        end
    end
end

-- == Reporting (DESIGN.md §4.4, §10.5) ======================================

--- Pump the cycle's tally into the production graphs (collected = input,
--- fed = output on the lbf-items-moved item) and the global counter every
--- cycle; the optional flying-text summary is accumulated across cycles and
--- only actually shown every SUMMARY_INTERVAL_TICKS — at the default ~1s
--- per-player cycle a per-cycle flying text would be constant noise.
--- @param player LuaPlayer
--- @param surface LuaSurface where the transfers happened (the character's surface)
--- @param data LbfPlayerData
--- @param report LbfReport
local function flush_report(player, surface, data, report)
    local collected_total, fed_total = 0, 0
    for _, count in pairs(report.collected) do
        collected_total = collected_total + count
    end
    for _, count in pairs(report.fed) do
        fed_total = fed_total + count
    end
    if collected_total == 0 and fed_total == 0 then
        return
    end

    storage.items_moved = (storage.items_moved or 0) + collected_total + fed_total
    local stats = player.force.get_item_production_statistics(surface)
    if collected_total > 0 then
        stats.on_flow('lbf-items-moved', collected_total)
    end
    if fed_total > 0 then
        stats.on_flow('lbf-items-moved', -fed_total)
    end

    if not data.flags.summary then
        return
    end
    local summary = data.summary
    for name, count in pairs(report.collected) do
        summary.collected[name] = (summary.collected[name] or 0) + count
    end
    for name, count in pairs(report.fed) do
        summary.fed[name] = (summary.fed[name] or 0) + count
    end
    if game.tick < summary.next_flush then
        return
    end
    summary.next_flush = game.tick + SUMMARY_INTERVAL_TICKS

    local parts = {}
    for name, count in pairs(summary.collected) do
        parts[#parts + 1] = '[color=150,255,150]+' .. count .. '[/color] [item=' .. name .. ']'
    end
    for name, count in pairs(summary.fed) do
        parts[#parts + 1] = '[color=255,150,150]-' .. count .. '[/color] [item=' .. name .. ']'
    end
    summary.collected = {}
    summary.fed = {}
    if #parts > 0 then
        player.create_local_flying_text({
            text = table.concat(parts, '  '),
            position = player.position,
        })
    end
end

-- == Entry point ============================================================

--- Service one player for one cycle. Cheap early-outs first (§7).
--- @param player LuaPlayer
--- @param pending uint[]? indices of players still due in this scheduler sweep
function Raid.service(player, pending)
    if not player.valid or not player.connected then
        return
    end
    local anchor = service_anchor(player)
    if not anchor then
        return
    end
    local data = State.get_player_data(player.index)

    if player.afk_time > AFK_TICKS then
        data.idle = (data.idle + 1) % 4
        if data.idle ~= 0 then
            return
        end
    else
        data.idle = 0
    end

    local main = player.get_main_inventory()
    if not main then
        return
    end

    local flags = data.flags
    local collect = State.effective(player.index, 'collect')
    local feed = State.effective(player.index, 'feed')
    local combat = State.effective(player.index, 'combat')
    local feed_fuel = feed and flags.fuel
    local feed_ingredients = feed and flags.ingredients
    local rebalance = feed and flags.rebalance
    local starvation = feed and flags.starvation
    local take_chests = collect and flags.chests and settings.global['lbf-allow-chest-take'].value == true
    -- Chest-take wins over trash drain: draining trash into a chest we raid
    -- back next cycle would churn items in a loop (auto-trash re-trashes them).
    local drain_trash = feed and flags.trash and not take_chests
    local take_ground = collect and flags.ground

    if not (collect or feed_fuel or feed_ingredients or combat or drain_trash or rebalance) then
        return
    end

    local entities = get_entities(player, data, anchor, take_chests or drain_trash, take_ground)
    --- @type LbfReport
    local report = { collected = {}, fed = {} }

    if collect then
        collect_pass(entities, main, take_chests, get_rivals(player, pending), report)
    end
    local starved, saturated
    if starvation then
        starved, saturated = {}, {}
    end
    if feed_fuel or feed_ingredients or combat then
        local totals = inventory_totals(main)
        local reserves = data.reserves
        if feed_fuel then
            feed_fuel_pass(entities, main, totals, reserves, report, starved, saturated)
        end
        if feed_ingredients then
            feed_ingredients_pass(player, entities, main, totals, reserves, report, starved, saturated)
        end
        if combat then
            feed_ammo_pass(entities, main, totals, reserves, report)
        end
    end
    if rebalance then
        rebalance_pass(entities)
    end
    if drain_trash then
        trash_pass(player, entities, report)
    end
    if starvation and (#starved > 0 or #saturated > 0) then
        Rendering.flash_starvation(player, starved, saturated)
    end
    flush_report(player, anchor.surface, data, report)
end

return Raid
