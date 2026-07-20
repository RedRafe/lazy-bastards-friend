--- Pass 4: feed ingredients to machines with a set recipe (including a furnace's last-smelted recipe while idle) and lab feeding scoped to current research.

local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')

local Ingredients = {}

local FEED_SECONDS = 30 -- top up ingredient inputs to ~this many seconds of crafting/research
local STARVE_SECONDS = 10 -- only flag starved once buffer drops below ~this many seconds (latch: refill still tops up to FEED_SECONDS well before this, so a machine sitting at e.g. 29/30 plates never flashes)

--- Item requirements of the machine's set recipe: the active one, or (furnaces) the last-smelted recipe — an idle furnace keeps making what it made. Returns nil for a furnace that never had a recipe, so it gets no ingredients pushed in.
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

--- How many crafts/research-units this entity gets through in ~`seconds` at its current speed (min 1). Labs derive speed from prototype.get_researching_speed() + entity.speed_bonus since LuaEntity.crafting_speed doesn't apply to them; research_unit_energy is in ticks so it's converted to seconds to match LuaRecipe.energy.
--- @param entity LuaEntity
--- @param energy double? recipe/research energy; nil/0 -> treat as 1 craft
--- @param seconds double? window size; defaults to FEED_SECONDS
--- @return double
local function crafts_in_window(entity, energy, seconds)
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
    return math.max(1, (seconds or FEED_SECONDS) * speed / energy)
end

--- @param player LuaPlayer
--- @param entities LuaEntity[]
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param report LbfReport
--- @param starved LuaEntity[]? populated when the starvation flag is on
function Ingredients.pass(player, entities, main, totals, reserves, report, starved)
    local research = player.force.current_research
    local research_ingredients = research and research.research_unit_ingredients
    local research_energy = research and research.research_unit_energy
    local lab_accepts = {} -- lab prototype name -> { pack name -> true }
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local entity_type = entity.type
            -- Per-entity starvation bookkeeping: any unspareable ingredient marks it starved.
            local wants_any, is_starved = false, false
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
                                local count = Transfer.count_by_name(input, ingredient.name)
                                if count < cap then
                                    if Shared.available(totals, reserves, ingredient.name) > 0 then
                                        Shared.add_to_group(groups, ingredient.name, input, cap)
                                    elseif count < math.ceil(ingredient.amount * crafts_in_window(entity, energy, STARVE_SECONDS)) then
                                        is_starved = true
                                    end
                                end
                            end
                        end
                    end
                end
            elseif entity_type == 'lab' and research_ingredients then
                -- Feed only what current research consumes and this lab accepts
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
                            local count = Transfer.count_by_name(input, ingredient.name)
                            if count < cap then
                                if Shared.available(totals, reserves, ingredient.name) > 0 then
                                    Shared.add_to_group(groups, ingredient.name, input, cap)
                                elseif count < math.ceil(ingredient.amount * crafts_in_window(entity, research_energy, STARVE_SECONDS)) then
                                    is_starved = true
                                end
                            end
                        end
                    end
                end
            end
            if starved and wants_any and is_starved then
                starved[#starved + 1] = entity
            end
        end
    end
    Shared.distribute_groups(groups, main, totals, reserves, report)
end

return Ingredients
