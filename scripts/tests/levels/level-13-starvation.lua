--- L13 — Starvation feedback. Rendered icons aren't assertable through the
--- remote interface, so this checks the underlying
--- behavior the render reflects: a furnace the player has no spare fuel for
--- (reserve == carried amount, so `available <= 0` — the exact condition the
--- fuel pass records as "starved") stays unfueled, and a furnace pre-filled
--- to its cap never receives more. Rebalance is force-disabled here — it
--- defaults on and would otherwise siphon coal from the full furnace into the
--- "starved" one, defeating the whole premise. The starvation flag itself is
--- switched on throughout as a smoke test that recording starved entities and
--- drawing the short-lived icon never errors.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    { name = 'stone-furnace', position = { -3, 0 } }, -- starved: no spareable coal
    { name = 'stone-furnace', position = { 3, 0 }, items = { [defines.inventory.fuel] = { ['coal'] = 50 } } }, -- saturated: already at cap
}

local KIT = { ['coal'] = 20 }
local RESERVE = 20 -- equal to the kit: nothing is ever spareable

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L13 starvation', {
    'Your coal is fully reserved — you have none spare, so the empty furnace should flash a red "starved" icon over it and never get fueled.',
    'The other furnace starts already full and should never receive more.',
    'Toggle "Show starvation feedback" off in your panel to confirm the icon stops appearing.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'appearance_starvation', true)
    -- Rebalance defaults to true; disable it so it can't feed the starved furnace from the full one and mask the condition under test.
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'feed_rebalance', false)
    remote.call('lazy-bastards-friend', 'set_player_reserve', player.index, 'coal', RESERVE)

    Harness.watch('starved furnace never gets fueled (nothing spareable)', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = { { -5, -2 }, { -1, 2 } }, name = 'stone-furnace' })) do
            local fuel = entity.get_fuel_inventory()
            if fuel and not fuel.is_empty() then
                return true
            end
        end
        return false
    end, 1200)

    Harness.watch('saturated furnace never receives more than its cap', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = { { 1, -2 }, { 5, 2 } }, name = 'stone-furnace' })) do
            local fuel = entity.get_fuel_inventory()
            if fuel and fuel.get_item_count('coal') > 50 then
                return true
            end
        end
        return false
    end, 1200)

    Harness.summary_after(1260)
end)
