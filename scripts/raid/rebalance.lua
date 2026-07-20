--- Pass 6: rebalance. Machine-to-machine only (never touches player inventory/reserves), scoped by item name rather than identical machines (e.g. a coal-hoarding stone furnace can feed a coal-starved steel furnace). Ingredient side only tops up inventories that already hold the item (no empty-acceptance inference, to avoid duplicating ingredients.pass's recipe logic); both sides use a flat stack-size cap rather than each pass's finer per-entity cap.

local Distribution = require('__lazy-bastards-friend__.scripts.lib.distribution')
local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')

local Rebalance = {}

--- Fuel-item groups: every fuel inventory already holding a given item, plus every empty one whose burner accepts that item's fuel category.
--- @param entities LuaEntity[]
--- @return table<string, LbfFeedGroup>
local function rebalance_fuel_groups(entities)
    local present, infos = {}, {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local fuel_inventory = entity.get_fuel_inventory()
            if fuel_inventory then
                local name = Shared.first_item_name(fuel_inventory)
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
                Shared.add_to_group(groups, name, info.inventory, cap)
            elseif not info.name and category then
                local burner = info.entity.prototype.burner_prototype
                if burner and burner.fuel_categories[category] then
                    Shared.add_to_group(groups, name, info.inventory, cap)
                end
            end
        end
    end
    return groups
end

--- Ingredient-item groups: every crafter/lab input inventory already holding a given item.
--- @param entities LuaEntity[]
--- @return table<string, LbfFeedGroup>
local function rebalance_ingredient_groups(entities)
    local present, inventories = {}, {}
    for _, entity in pairs(entities) do
        if entity.valid then
            local entity_type = entity.type
            local input
            if Shared.INGREDIENT_TYPES[entity_type] then
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
                Shared.add_to_group(groups, name, inventory, cap)
            end
        end
    end
    return groups
end

--- Execute one group's rebalance: compute the shared water level, then pair off donors (holders above it) and receivers (below it) with direct inventory-to-inventory transfers.
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
function Rebalance.pass(entities)
    for _, group in pairs(rebalance_fuel_groups(entities)) do
        rebalance_group(group)
    end
    for _, group in pairs(rebalance_ingredient_groups(entities)) do
        rebalance_group(group)
    end
end

return Rebalance
