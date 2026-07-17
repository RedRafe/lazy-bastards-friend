--- Cross-pass infrastructure for scripts/raid.lua's orchestration (DESIGN.md
--- §1.1, §7): the entity type tables every pass filters by, the entity-scan
--- cache, and the generic water-fill distribution helpers each feed pass
--- builds its groups on top of.

local State = require('__lazy-bastards-friend__.scripts.state')
local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Distribution = require('__lazy-bastards-friend__.scripts.lib.distribution')

local Shared = {}

local CACHE_CYCLES = 10 -- re-scan at most every N update periods
local CACHE_MOVE_FRACTION = 0.25 -- re-scan when moved more than radius * this

-- Everything any pass may want; each pass filters by capability at use time
-- (fuel inventory present, output map entry, turret ammo define).
Shared.SCAN_TYPES = {
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
Shared.CHEST_TYPES = { 'container', 'logistic-container' }

-- Explicit output map: get_output_inventory() on other types can return
-- inventories we must not raid (a turret's "output" is its ammo).
Shared.OUTPUT_INVENTORY = {
    ['furnace'] = defines.inventory.crafter_output,
    ['assembling-machine'] = defines.inventory.crafter_output,
    ['rocket-silo'] = defines.inventory.crafter_output,
    ['agricultural-tower'] = defines.inventory.agricultural_tower_output,
}

Shared.TURRET_AMMO_INVENTORY = {
    ['ammo-turret'] = defines.inventory.turret_ammo,
    ['artillery-turret'] = defines.inventory.artillery_turret_ammo,
}

Shared.IS_CHEST = { ['container'] = true, ['logistic-container'] = true }

-- Crafter types the ingredient pass fills through defines.inventory.crafter_input.
Shared.INGREDIENT_TYPES = { ['furnace'] = true, ['assembling-machine'] = true, ['rocket-silo'] = true }

-- Lookup set of every type a raid could ever touch (SCAN_TYPES + CHEST_TYPES),
-- for the exclusion-toggle hotkey (DESIGN.md §10.4) to validate what's hovered.
Shared.TARGETABLE_TYPE = {}
for _, t in pairs(Shared.SCAN_TYPES) do
    Shared.TARGETABLE_TYPE[t] = true
end
for _, t in pairs(Shared.CHEST_TYPES) do
    Shared.TARGETABLE_TYPE[t] = true
end

--- This player's or another connected player's service-area anchor: the
--- character. Shared between Raid.service's own anchor choice and collect's
--- rival lookup, so overlap is checked against where the service area actually is.
--- @param player LuaPlayer
--- @return LuaEntity?
function Shared.service_anchor(player)
    return player.character
end

--- Per-cycle transfer tally: item name -> count, split by direction.
--- @class LbfReport
--- @field collected table<string, integer> machines/ground -> player
--- @field fed table<string, integer> player -> machines/turrets/chests

-- == Entity cache (DESIGN.md §7) ============================================

--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param anchor LuaEntity center of the service area — the player's character
--- @param include_chests boolean chest-take or trash-drain wants containers scanned
--- @param include_ground boolean ground-item pickup wants item-entities scanned
--- @return LuaEntity[]
function Shared.get_entities(player, data, anchor, include_chests, include_ground)
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

    local types = Shared.SCAN_TYPES
    if include_chests then
        types = {}
        for _, t in pairs(Shared.SCAN_TYPES) do
            types[#types + 1] = t
        end
        for _, t in pairs(Shared.CHEST_TYPES) do
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

-- == Distribution helpers ====================================================

--- Player item totals by name, summed across qualities (reserves are per-name, §6).
--- @param main LuaInventory
--- @return table<string, integer>
function Shared.inventory_totals(main)
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
function Shared.available(totals, reserves, name)
    return (totals[name] or 0) - (reserves[name] or 0)
end

--- @class LbfFeedGroup
--- @field name string item to distribute
--- @field cap integer? per-target cap; defaults to one stack at distribution time
--- @field inventories LuaInventory[]
--- @field counts integer[]

--- First item name in a small inventory, or nil if empty.
--- @param inventory LuaInventory
--- @return string?
function Shared.first_item_name(inventory)
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read then
            return stack.name
        end
    end
    return nil
end

--- Targets with equal caps pool into one group; distinct caps for the same item
--- form separate groups that share the same (decrementing) budget.
--- @param groups table<string, LbfFeedGroup>
--- @param name string
--- @param inventory LuaInventory
--- @param cap integer?
function Shared.add_to_group(groups, name, inventory, cap)
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

--- Water-fill each item group across its target inventories, capped per target,
--- and execute the transfers. Decrements `totals` as it goes.
--- @param groups table<string, LbfFeedGroup>
--- @param main LuaInventory
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @param report LbfReport
function Shared.distribute_groups(groups, main, totals, reserves, report)
    local fed = report.fed
    for _, group in pairs(groups) do
        local name = group.name
        local budget = Shared.available(totals, reserves, name)
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

return Shared
