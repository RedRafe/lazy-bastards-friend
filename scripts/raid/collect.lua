--- Pass 1+2: collect outputs/burnt results, optionally chests and ground items; shared sources get split fairly with other players still due this sweep instead of taken whole.

local State = require('__lazy-bastards-friend__.scripts.state')
local Transfer = require('__lazy-bastards-friend__.scripts.lib.transfer')
local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')

local Collect = {}

--- @class LbfRival
--- @field x double
--- @field y double
--- @field radius integer
--- @field square boolean
--- @field chests boolean

--- Other players still due in this sweep whose service area may overlap ours (already-serviced players took their share on their turn); nil when nobody contests.
--- @param player LuaPlayer
--- @param pending uint[]?
--- @return LbfRival[]?
function Collect.get_rivals(player, pending)
    if not pending then
        return nil
    end
    local anchor = Shared.service_anchor(player)
    local surface_index = anchor.surface.index
    local px, py = anchor.position.x, anchor.position.y
    local radius = State.get_radius(player.index)
    local rivals
    for _, index in pairs(pending) do
        if index ~= player.index and State.effective(index, 'collect') then
            local other = game.get_player(index)
            local other_anchor = other and other.connected and Shared.service_anchor(other)
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
                        chests = State.effective(index, 'collect_chests'),
                    }
                end
            end
        end
    end
    return rivals
end

--- How many players get a cut of this entity: us + every rival whose area covers it (their AoE shape is their search shape).
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

--- Take a 1/k share of each item in the source (by name, across qualities); the floor remainder stays put for the players still due this sweep.
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

--- Scoop one ground stack whole — no fair-share split; a single dropped stack isn't worth the shape checks.
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
function Collect.pass(entities, main, take_chests, rivals, report)
    for _, entity in pairs(entities) do
        if entity.valid then
            if entity.type == 'item-entity' then
                take_ground_item(entity, main, report)
            else
                local is_chest = Shared.IS_CHEST[entity.type]
                local k = rivals and claim_divisor(entity, rivals, is_chest or false) or 1
                local output_define = Shared.OUTPUT_INVENTORY[entity.type]
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

return Collect
