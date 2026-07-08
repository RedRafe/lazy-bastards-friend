--- The service passes (DESIGN.md §1.1): collect outputs/burnt results (+chests
--- opt-in), feed fuel, feed ammo. Ingredient feeding ships in M4. One call to
--- Raid.service handles one player for one cycle; the scheduler decides when.

local State = require('scripts.state')
local Transfer = require('scripts.lib.transfer')
local Distribution = require('scripts.lib.distribution')

local Raid = {}

local AFK_TICKS = 5 * 60 * 60 -- after 5 min AFK, service at 1/4 rate
local CACHE_CYCLES = 10 -- re-scan at most every N update periods
local CACHE_MOVE_FRACTION = 0.25 -- re-scan when moved more than radius * this

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

-- == Entity cache (DESIGN.md §7) ============================================

--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param take_chests boolean
--- @return LuaEntity[]
local function get_entities(player, data, take_chests)
    local character = player.character
    local position = character.position
    local surface = character.surface
    local radius = State.get_radius(player.index)
    local period = settings.global['lbf-update-period'].value --[[@as integer]]

    local key = table.concat({ surface.index, radius, data.shape, take_chests and 1 or 0 }, ':')
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
    if take_chests then
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
    local entities = surface.find_entities_filtered(filter)
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
--- @field inventories LuaInventory[]
--- @field counts integer[]
--- @field cap integer? per-target cap override when one stack is wrong (artillery)

--- Water-fill each item group across its target inventories, capped at one
--- stack per target, and execute the transfers. Decrements `totals` as it goes.
--- @param groups table<string, LbfFeedGroup>
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
local function distribute_groups(groups, main, totals, reserves)
    for name, group in pairs(groups) do
        local budget = available(totals, reserves, name)
        if budget > 0 then
            local cap = math.max(group.cap or 0, prototypes.item[name].stack_size)
            local gives = Distribution.balanced_fill(group.counts, budget, cap)
            for i, give in ipairs(gives) do
                if give > 0 then
                    local moved = Transfer.give(main, group.inventories[i], name, give)
                    totals[name] = totals[name] - moved
                end
            end
        end
    end
end

--- @param groups table<string, LbfFeedGroup>
--- @param name string
--- @param inventory LuaInventory
local function add_to_group(groups, name, inventory)
    local group = groups[name]
    if not group then
        group = { inventories = {}, counts = {} }
        groups[name] = group
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
    local character = player.character
    local surface_index = character.surface.index
    local px, py = character.position.x, character.position.y
    local radius = State.get_radius(player.index)
    local rivals
    for _, index in pairs(pending) do
        if index ~= player.index and State.effective(index, 'collect') then
            local other = game.get_player(index)
            local other_character = other and other.connected and other.character
            if other_character and other_character.surface.index == surface_index then
                local other_radius = State.get_radius(index)
                local ox, oy = other_character.position.x, other_character.position.y
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
local function take_share(source, dest, k)
    if k <= 1 then
        Transfer.take_all(source, dest)
        return
    end
    local totals = {}
    for _, item in pairs(source.get_contents()) do
        totals[item.name] = (totals[item.name] or 0) + item.count
    end
    for name, count in pairs(totals) do
        local share = math.floor(count / k)
        if share > 0 then
            Transfer.give(source, dest, name, share)
        end
    end
end

--- @param entities LuaEntity[]
--- @param main LuaInventory
--- @param take_chests boolean
--- @param rivals LbfRival[]?
local function collect_pass(entities, main, take_chests, rivals)
    for _, entity in pairs(entities) do
        if entity.valid then
            local is_chest = IS_CHEST[entity.type]
            local k = rivals and claim_divisor(entity, rivals, is_chest or false) or 1
            local output_define = OUTPUT_INVENTORY[entity.type]
            if output_define then
                local output = entity.get_inventory(output_define)
                if output and not output.is_empty() then
                    take_share(output, main, k)
                end
            end
            local burnt = entity.get_burnt_result_inventory()
            if burnt and not burnt.is_empty() then
                take_share(burnt, main, k)
            end
            if take_chests and is_chest then
                local chest = entity.get_inventory(defines.inventory.chest)
                if chest and not chest.is_empty() then
                    take_share(chest, main, k)
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
--- best carried fuel its burner accepts.
--- @param entity LuaEntity
--- @param fuel_inventory LuaInventory
--- @param fuels LbfFuelCandidate[]
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @return string?
local function pick_fuel(entity, fuel_inventory, fuels, totals, reserves)
    local current = first_item_name(fuel_inventory)
    if current then
        -- Fuel slots are usually single; mixing in a second fuel type can't
        -- work anyway, so if the player can't spare this one, skip the entity.
        if available(totals, reserves, current) > 0 then
            return current
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
    return nil
end

--- @param entities LuaEntity[]
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
local function feed_fuel_pass(entities, main, totals, reserves)
    local fuels = get_player_fuels(totals, reserves)
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local fuel_inventory = entity.get_fuel_inventory()
            if fuel_inventory then
                local name = pick_fuel(entity, fuel_inventory, fuels, totals, reserves)
                if name then
                    add_to_group(groups, name, fuel_inventory)
                end
            end
        end
    end
    distribute_groups(groups, main, totals, reserves)
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
local function feed_ammo_pass(entities, main, totals, reserves)
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
                        add_to_group(groups, name, ammo_inventory)
                        -- One stack is the wrong ceiling for artillery (shells
                        -- stack to 1): allow what inserters would load instead.
                        local group = groups[name]
                        local automated = turret.prototype.automated_ammo_count or 0
                        if automated > (group.cap or 0) then
                            group.cap = automated
                        end
                    end
                end
            end
        end
    end
    distribute_groups(groups, main, totals, reserves)
end

-- == Entry point ============================================================

--- Service one player for one cycle. Cheap early-outs first (§7).
--- @param player LuaPlayer
--- @param pending uint[]? indices of players still due in this scheduler sweep
function Raid.service(player, pending)
    if not player.valid or not player.connected then
        return
    end
    local character = player.character
    if not character then
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

    local collect = State.effective(player.index, 'collect')
    local feed = State.effective(player.index, 'feed') and data.flags.fuel
    local combat = State.effective(player.index, 'combat')
    if not (collect or feed or combat) then
        return
    end

    local take_chests = collect and data.flags.chests and settings.global['lbf-allow-chest-take'].value == true
    local entities = get_entities(player, data, take_chests)

    if collect then
        collect_pass(entities, main, take_chests, get_rivals(player, pending))
    end
    if feed or combat then
        local totals = inventory_totals(main)
        local reserves = data.reserves
        if feed then
            feed_fuel_pass(entities, main, totals, reserves)
        end
        if combat then
            feed_ammo_pass(entities, main, totals, reserves)
        end
    end
end

return Raid
