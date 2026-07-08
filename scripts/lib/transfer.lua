--- Stack-preserving inventory-to-inventory transfers (DESIGN.md §7).
--- Reimplemented from scratch; reference: reference/even-distribution.lua
--- (transfer). Preserves quality, health, durability, ammo, spoilage and tags;
--- never spills — whatever the destination can't take stays in the source.

local Transfer = {}

-- Items whose extra data (equipment grids, blueprints, entity data) would be
-- destroyed by a plain LuaInventory.insert; these move whole-stack only.
local complex_types = {
    ['item-with-entity-data'] = true,
    ['armor'] = true,
    ['spidertron-remote'] = true,
    ['blueprint'] = true,
    ['blueprint-book'] = true,
    ['upgrade-planner'] = true,
    ['deconstruction-planner'] = true,
}

--- Move up to `limit` items from one stack into an inventory.
--- @param stack LuaItemStack valid_for_read
--- @param dest LuaInventory
--- @param limit integer? defaults to the whole stack
--- @return integer moved
local function move_stack(stack, dest, limit)
    if complex_types[stack.type] then
        local slot = dest.find_empty_stack()
        if not slot or not slot.transfer_stack(stack) then
            return 0
        end
        return slot.count
    end

    local count = stack.count
    if limit and limit < count then
        count = limit
    end
    --- @type ItemStackDefinition
    local spec = {
        name = stack.name,
        quality = stack.quality.name,
        count = count,
        health = stack.health,
        durability = stack.type == 'tool' and stack.durability or nil,
        ammo = stack.type == 'ammo' and stack.ammo or nil,
        tags = stack.type == 'item-with-tags' and stack.tags or nil,
        custom_description = stack.type == 'item-with-tags' and stack.custom_description or nil,
        spoil_percent = stack.spoil_percent,
    }
    if spec.ammo and spec.ammo < 1 then
        -- The game occasionally hands out stacks with ammo == 0 even though it
        -- shouldn't be possible; insert() rejects those.
        spec.ammo = 1
    end
    local inserted = dest.insert(spec)
    if inserted > 0 then
        stack.count = stack.count - inserted
    end
    return inserted
end

--- Move everything that fits from `source` into `dest`.
--- @param source LuaInventory
--- @param dest LuaInventory
--- @return integer moved
function Transfer.take_all(source, dest)
    local moved = 0
    for i = 1, #source do
        local stack = source[i]
        if stack.valid_for_read then
            moved = moved + move_stack(stack, dest)
        end
    end
    return moved
end

--- Move up to `count` items named `name` (any quality) from `source` to `dest`.
--- @param source LuaInventory
--- @param dest LuaInventory
--- @param name string
--- @param count integer
--- @return integer moved
function Transfer.give(source, dest, name, count)
    local moved = 0
    for i = 1, #source do
        if moved >= count then
            break
        end
        local stack = source[i]
        if stack.valid_for_read and stack.name == name then
            local n = move_stack(stack, dest, count - moved)
            if n == 0 then
                break -- destination full or filtered against this item
            end
            moved = moved + n
        end
    end
    return moved
end

--- Count items named `name` (any quality) by iterating stacks — avoids the
--- quality-defaulting ambiguity of LuaInventory.get_item_count. Only use on
--- small inventories (fuel/ammo slots).
--- @param inventory LuaInventory
--- @param name string
--- @return integer
function Transfer.count_by_name(inventory, name)
    local total = 0
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack.valid_for_read and stack.name == name then
            total = total + stack.count
        end
    end
    return total
end

return Transfer
