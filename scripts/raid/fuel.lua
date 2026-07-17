--- Pass 3: feed fuel (DESIGN.md §1.1). Tops up whatever's already loaded in a
--- burner, else the best carried fuel it accepts.

local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')

local Fuel = {}

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
        if Shared.available(totals, reserves, name) > 0 then
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
    local current = Shared.first_item_name(fuel_inventory)
    if current then
        if Shared.available(totals, reserves, current) > 0 then
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
function Fuel.pass(entities, main, totals, reserves, report, starved, saturated)
    local fuels = get_player_fuels(totals, reserves)
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local fuel_inventory = entity.get_fuel_inventory()
            if fuel_inventory then
                local name = pick_fuel(entity, fuel_inventory, fuels, totals, reserves, starved, saturated)
                if name then
                    Shared.add_to_group(groups, name, fuel_inventory)
                end
            end
        end
    end
    Shared.distribute_groups(groups, main, totals, reserves, report)
end

return Fuel
