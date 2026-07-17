--- L06 — Trash-slot drain and ground-item pickup (both opt-in flags, DESIGN.md
--- §10.3). Three chests exercise the drain's target priority: a chest already
--- holding the same item, a chest filtered for a different item but otherwise
--- empty, and a plain empty chest with no filter — the first two must win over
--- the third. Loose items on the ground exercise the separate pickup pass.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    { name = 'iron-chest', position = { -8, -4 }, items = { [defines.inventory.chest] = { ['coal'] = 10 } } }, -- priority 1: same-item chest
    { name = 'storage-chest', position = { -2, -4 } }, -- priority 2: filtered for stone, set below
    { name = 'iron-chest', position = { 4, -4 } }, -- priority 3: empty, unfiltered
}

local KIT = {
    ['coal'] = 20,
    ['stone'] = 20,
}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    local built = Bench.spawn(surface, game.forces.player, BENCH)
    built['-2,-4'].storage_filter = 'stone'
    Bench.research(game.forces.player, { 'logistic-robotics' }) -- unlocks personal trash slots

    surface.spill_item_stack({ position = { 8, -4 }, stack = { name = 'iron-plate', count = 20 }, enable_looted = false })
    surface.spill_item_stack({ position = { 10, -4 }, stack = { name = 'copper-plate', count = 20 }, enable_looted = false })
end)

Bench.on_player_created(KIT, 'L06 trash & ground', {
    'This level enables "Empty trash into chests" and "Collect ground items" for you.',
    'Right-click your inventory slots to mark coal/stone as trash (logistic trash slots) — coal should land in the chest that already has coal, stone in the filtered chest, never the plain empty one.',
    'Walk over the loose plates on the ground east of the chests to test pickup.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'feed_trash', true)
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'collect_ground', true)

    Harness.eventually('ground items were picked up', function()
        return player.get_main_inventory().get_item_count('iron-plate') > 0
            and player.get_main_inventory().get_item_count('copper-plate') > 0
    end, 3600)
    Harness.summary_after(3660)
end)
