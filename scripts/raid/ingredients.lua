--- Pass 4: feed ingredients (DESIGN.md §1.1), including the recipe-less-furnace
--- smelt map that lets a fresh/idle furnace still get fed from carried inputs,
--- and lab feeding scoped to the force's current research.

local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')

local Ingredients = {}

local FEED_SECONDS = 30 -- top up ingredient inputs to ~this many seconds of crafting/research

-- == Smelt map (DESIGN.md §1.1 pass 4) ======================================

--- Rebuild storage.smelt_map: crafting category -> { ingredient item -> {amount,
--- energy} } (per-craft amount and the recipe's crafting time, §1.1's 30s-of-
--- crafting cap needs both), from visible single-item-ingredient recipes. Hidden
--- recipes are excluded on purpose — that keeps recycler-style categories (whose
--- hidden recipes accept nearly every item) out of the map. Call on_init/config_changed.
function Ingredients.rebuild_smelt_map()
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
                local spare = Shared.available(totals, reserves, name)
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
function Ingredients.pass(player, entities, main, totals, reserves, report, starved, saturated)
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
            if Shared.INGREDIENT_TYPES[entity_type] then
                local input = entity.get_inventory(defines.inventory.crafter_input)
                if input then
                    local ingredients, energy = recipe_ingredients(entity)
                    if ingredients then
                        local crafts = crafts_in_window(entity, energy)
                        for _, ingredient in pairs(ingredients) do
                            if ingredient.type == 'item' then
                                wants_any = true
                                local cap = math.ceil(ingredient.amount * crafts)
                                if Shared.available(totals, reserves, ingredient.name) > 0 then
                                    Shared.add_to_group(groups, ingredient.name, input, cap)
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
                        local name = Shared.first_item_name(input)
                        local entry
                        if name then
                            entry = smelt_entry(proto, name)
                            if Shared.available(totals, reserves, name) <= 0 then
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
                            Shared.add_to_group(groups, name, input, cap)
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
                            if Shared.available(totals, reserves, ingredient.name) > 0 then
                                Shared.add_to_group(groups, ingredient.name, input, cap)
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
    Shared.distribute_groups(groups, main, totals, reserves, report)
end

return Ingredients
