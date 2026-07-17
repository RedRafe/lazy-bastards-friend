--- L04 — Collect channel, opt-in chest looting. Chest contents only move when
--- `lbf-collect-chests` (per-player flag, "chests" in FLAG_NAMES) is on and
--- `lbf-allow-chest-collect` (global runtime setting) allows it; both default the
--- way vanilla balance wants (per-player off, global on), so this level's intro
--- tells the player to flip their own switch.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    { name = 'wooden-chest', position = { -6, 0 }, items = { [defines.inventory.chest] = { ['coal'] = 50, ['iron-plate'] = 100 } } },
    { name = 'iron-chest', position = { 0, 0 }, items = { [defines.inventory.chest] = { ['copper-plate'] = 100 } } },
    { name = 'steel-chest', position = { 6, 0 }, items = { [defines.inventory.chest] = { ['electronic-circuit'] = 100 } } },
}

local KIT = {}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L04 collect chests', {
    'Chest looting is opt-in ("Take from chests" in your panel, off by default) — this level flips it on for you.',
    'Walk up to the chests and watch their contents drain into your inventory.',
    'Toggle "Take from chests" off in your panel to confirm the pass stops immediately.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'collect_chests', true)
    Harness.eventually('chest contents were collected once the flag is on', function()
        return player.get_main_inventory().get_item_count('coal') > 0
    end, 3600)
    Harness.summary_after(3660)
end)
