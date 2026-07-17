--- Moves the player's logistic trash into nearby chests, never dumping blindly onto whatever's closest.

local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')

local Trash = {}

--- @class LbfChestTarget
--- @field entity LuaEntity
--- @field inventory LuaInventory
--- @field requests table<string, boolean>? requested/filtered item names
--- @field accepts_any boolean not pull-only and not filtered to specific items

--- Classify the chests in the service area as drain targets. Requester/buffer chests and filtered storage chests only ever receive what they ask for.
--- @param entities LuaEntity[]
--- @return LbfChestTarget[]?
local function chest_targets(entities)
    local targets
    for _, entity in pairs(entities) do
        if entity.valid and Shared.IS_CHEST[entity.type] then
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

--- Chest priority for one item: 1. chests already holding it, 2. chests requesting/filtered to it, 3. empty unfiltered chests.
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
function Trash.pass(player, entities, report)
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

return Trash
