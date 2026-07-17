--- The service passes (DESIGN.md §1.1): collect outputs/burnt results (+chests
--- and ground items, opt-in), feed fuel, feed ingredients (smelt map for recipe-less
--- furnaces), feed ammo, rebalance machine-to-machine, drain trash slots into
--- chests. One call to Raid.service handles one player for one cycle; the
--- scheduler decides when. Every transfer is tallied into a per-cycle report
--- that feeds the production-graph statistics item and the optional flying-text
--- summary (§4.4, §10.5).
---
--- Each pass lives in its own scripts/raid/*.lua module (shared/collect/fuel/
--- ingredients/ammo/rebalance/trash/report); this file is just the entry point
--- that wires them together per DESIGN.md §12's "split raid" cleanup.

local State = require('__lazy-bastards-friend__.scripts.state')
local Shared = require('__lazy-bastards-friend__.scripts.raid.shared')
local Collect = require('__lazy-bastards-friend__.scripts.raid.collect')
local Fuel = require('__lazy-bastards-friend__.scripts.raid.fuel')
local Ingredients = require('__lazy-bastards-friend__.scripts.raid.ingredients')
local Ammo = require('__lazy-bastards-friend__.scripts.raid.ammo')
local Rebalance = require('__lazy-bastards-friend__.scripts.raid.rebalance')
local Trash = require('__lazy-bastards-friend__.scripts.raid.trash')
local Report = require('__lazy-bastards-friend__.scripts.raid.report')
local Rendering = require('__lazy-bastards-friend__.scripts.rendering')

local Raid = {}

local AFK_TICKS = 5 * 60 * 60 -- after 5 min AFK, service at 1/4 rate

--- Rebuild storage.smelt_map (pass 4's recipe-less-furnace inference). Call
--- on_init/config_changed.
Raid.rebuild_smelt_map = Ingredients.rebuild_smelt_map

--- Whether `entity` is a type any raid pass could act on — used by the
--- exclusion-toggle custom-input to validate the hovered entity.
--- @param entity LuaEntity?
--- @return boolean
function Raid.is_targetable(entity)
    return entity ~= nil and entity.valid and Shared.TARGETABLE_TYPE[entity.type] == true
end

--- Service one player for one cycle. Cheap early-outs first (§7).
--- @param player LuaPlayer
--- @param pending uint[]? indices of players still due in this scheduler sweep
function Raid.service(player, pending)
    if not player.valid or not player.connected then
        return
    end
    local anchor = Shared.service_anchor(player)
    if not anchor then
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
    local combat = State.effective(player.index, 'feed_combat')
    local feed_fuel = State.effective(player.index, 'feed_fuel')
    local feed_ingredients = State.effective(player.index, 'feed_ingredients')
    local rebalance = State.effective(player.index, 'feed_rebalance')
    local starvation = State.effective(player.index, 'appearance_starvation')
    local take_chests = State.effective(player.index, 'collect_chests') and settings.global['lbf-allow-chest-collect'].value == true
    -- Chest-take wins over trash drain: draining trash into a chest we raid
    -- back next cycle would churn items in a loop (auto-trash re-trashes them).
    local drain_trash = State.effective(player.index, 'feed_trash') and not take_chests
    local take_ground = State.effective(player.index, 'collect_ground')

    if not (collect or feed_fuel or feed_ingredients or combat or drain_trash or rebalance) then
        return
    end

    local entities = Shared.get_entities(player, data, anchor, take_chests or drain_trash, take_ground)
    --- @type LbfReport
    local report = { collected = {}, fed = {} }

    if collect then
        Collect.pass(entities, main, take_chests, Collect.get_rivals(player, pending), report)
    end
    local starved, saturated
    if starvation then
        starved, saturated = {}, {}
    end
    if feed_fuel or feed_ingredients or combat then
        local totals = Shared.inventory_totals(main)
        local reserves = data.reserves
        if feed_fuel then
            Fuel.pass(entities, main, totals, reserves, report, starved, saturated)
        end
        if feed_ingredients then
            Ingredients.pass(player, entities, main, totals, reserves, report, starved, saturated)
        end
        if combat then
            Ammo.pass(entities, main, totals, reserves, report)
        end
    end
    if rebalance then
        Rebalance.pass(entities)
    end
    if drain_trash then
        Trash.pass(player, entities, report)
    end
    if starvation and (#starved > 0 or #saturated > 0) then
        Rendering.flash_starvation(player, starved, saturated)
    end
    Report.flush(player, anchor.surface, data, report, State.effective(player.index, 'appearance_summary'))
end

return Raid
