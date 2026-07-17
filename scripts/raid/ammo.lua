--- Pass 5: feed ammo. Gated by `feed_combat` (state.lua's TREE_DEF) rather than its own channel.

local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')

local Ammo = {}

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
        if Shared.available(totals, reserves, name) > 0 then
            local proto = prototypes.item[name]
            local category = proto and proto.ammo_category
            if category then
                ammo[#ammo + 1] = { name = name, category = category.name, order = proto.order }
            end
        end
    end
    return ammo
end

--- Ammo to feed this turret: top up what it already holds, else the best (highest prototype order — vanilla orders ascend by tier) carried ammo matching its categories.
--- @param turret LuaEntity
--- @param ammo_inventory LuaInventory
--- @param candidates LbfAmmoCandidate[]
--- @param totals table<string, integer>
--- @param reserves table<string, integer>
--- @return string?
local function pick_ammo(turret, ammo_inventory, candidates, totals, reserves)
    local current = Shared.first_item_name(ammo_inventory)
    if current then
        if Shared.available(totals, reserves, current) > 0 then
            return current
        end
        return nil
    end
    -- Artillery turrets have no attack_parameters (they live on the gun prototype); fall back to asking the ammo inventory itself, which enforces the accepted category on insert.
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
function Ammo.pass(entities, main, totals, reserves, report)
    local candidates = get_player_ammo(totals, reserves)
    --- @type table<string, LbfFeedGroup>
    local groups = {}
    for _, turret in pairs(entities) do
        if turret.valid then
            local ammo_define = Shared.TURRET_AMMO_INVENTORY[turret.type]
            if ammo_define then
                local ammo_inventory = turret.get_inventory(ammo_define)
                if ammo_inventory then
                    local name = pick_ammo(turret, ammo_inventory, candidates, totals, reserves)
                    if name then
                        -- One stack is the wrong ceiling for artillery (shells stack to 1): allow what inserters would load instead
                        local cap = math.max(
                            turret.prototype.automated_ammo_count or 0,
                            prototypes.item[name].stack_size
                        )
                        Shared.add_to_group(groups, name, ammo_inventory, cap)
                    end
                end
            end
        end
    end
    Shared.distribute_groups(groups, main, totals, reserves, report)
end

return Ammo
