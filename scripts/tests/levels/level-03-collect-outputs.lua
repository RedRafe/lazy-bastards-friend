--- L03 — Collect channel, output pass. Furnaces and assemblers pre-loaded so they
--- are actively producing; the Collect channel should pull finished plates/gears
--- out of their output slots into the player inventory without being asked.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    -- Fully fed furnaces: smelting on its own, output should get pulled.
    { name = 'stone-furnace', position = { -8, -4 }, items = { [defines.inventory.fuel] = { ['coal'] = 10 }, [defines.inventory.crafter_input] = { ['iron-ore'] = 100 } } },
    { name = 'stone-furnace', position = { -4, -4 }, items = { [defines.inventory.fuel] = { ['coal'] = 10 }, [defines.inventory.crafter_input] = { ['stone'] = 100 } } },
    -- Fully fed assembler crafting gear wheels: output should get pulled.
    { name = 'assembling-machine-1', position = { 2, -4 }, recipe = 'iron-gear-wheel', items = { [defines.inventory.crafter_input] = { ['iron-plate'] = 100 } } },
    { name = 'medium-electric-pole', position = { 5, -4 } },
    { name = 'hidden-electric-energy-interface', position = { 5, -4 } },
}

local KIT = {} -- deliberately empty: everything the player ends up with came from collection

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L03 collect outputs', {
    'Your kit is empty on purpose — everything you end up holding should come from the Collect channel.',
    'Stand near the furnaces/assembler and watch plates and gear wheels land in your inventory as they finish.',
    'Toggle "Collect" off in your panel to confirm output stops moving (machines keep producing, just stop draining).',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    Harness.eventually('player received smelted plates', function()
        return player.get_main_inventory().get_item_count('iron-plate') > 0
            and player.get_main_inventory().get_item_count('stone-brick') > 0
    end, 3600)
    Harness.eventually('player received crafted gear wheels', function()
        return player.get_main_inventory().get_item_count('iron-gear-wheel') > 0
    end, 3600)
    Harness.summary_after(3660)
end)
