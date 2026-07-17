--- L12 — Per-entity exclusion. One furnace, excluded via the remote interface before the player gets near it (mirrors the hover+hotkey flow without mouse input). Confirms the fuel pass skips it while excluded, then feeds it once un-excluded.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }
local FURNACE_POSITION = { 0, 0 }

local BENCH = {
    { name = 'stone-furnace', position = FURNACE_POSITION },
}

local KIT = { ['coal'] = 40 }

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L12 exclusion', {
    'The furnace starts excluded via the remote interface (set_entity_excluded).',
    'Walk next to it: confirm it stays unfueled while excluded.',
    'It gets un-excluded automatically after a while — confirm the Feed channel then tops it up.',
    'You can also press the exclude hotkey yourself (unbound by default, see Controls) to toggle it back off.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    local furnace = player.surface.find_entities_filtered({ area = AREA, name = 'stone-furnace' })[1]
    if not furnace then
        return
    end
    remote.call('lazy-bastards-friend', 'set_entity_excluded', player.index, furnace.unit_number, true)

    Harness.check('is_entity_excluded reports true right after exclusion', function()
        return remote.call('lazy-bastards-friend', 'is_entity_excluded', player.index, furnace.unit_number) == true
    end)

    -- Long enough that, if exclusion didn't work, the fuel pass would have topped the furnace up before this window closes.
    Harness.watch('furnace stays unfueled while excluded', function()
        local fuel = furnace.get_fuel_inventory()
        return fuel and not fuel.is_empty()
    end, 900)

    -- One-shot: un-exclude once the "stays unfueled" watch window has closed.
    script.on_nth_tick(900, function()
        script.on_nth_tick(900, nil)
        remote.call('lazy-bastards-friend', 'set_entity_excluded', player.index, furnace.unit_number, false)
    end)

    Harness.eventually('furnace gets fueled once un-excluded', function()
        local fuel = furnace.get_fuel_inventory()
        return fuel and not fuel.is_empty()
    end, 1800)

    Harness.summary_after(1860)
end)
