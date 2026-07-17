--- L07 — Reserved items: a per-item minimum the mod must never dip below when feeding/collecting. Sets a 20-coal reserve; the check fails if the pass ever spends past it.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local RESERVE_ITEM = 'coal'
local RESERVE_AMOUNT = 20

local BENCH = {
    { name = 'stone-furnace', position = { -4, 0 } },
    { name = 'stone-furnace', position = { 0, 0 } },
    { name = 'stone-furnace', position = { 4, 0 } },
}

local KIT = {
    ['coal'] = 30, -- only 10 above the reserve: any over-spend is immediately visible
    ['iron-ore'] = 200,
}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    game.speed = 10 -- fuel burn-down is the whole test; run it faster than realtime
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L07 reserves', {
    'A ' .. RESERVE_AMOUNT .. '-coal reserve is set on your behalf (docs/API.md set_player_reserve).',
    'You start with only ' .. KIT.coal .. ' coal — walk near the furnaces and confirm the Feed channel stops fueling once you hit the reserve, even though the furnaces still want more.',
    'Raise or clear the reserve from the reserves editor in your panel to see the remaining coal get spent.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    remote.call('lazy-bastards-friend', 'set_player_reserve', player.index, RESERVE_ITEM, RESERVE_AMOUNT)

    Harness.eventually('feed pass touched the furnaces at all', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = AREA, name = 'stone-furnace' })) do
            local fuel = entity.get_fuel_inventory()
            if fuel and not fuel.is_empty() then
                return true
            end
        end
        return false
    end, 900)

    -- Long-lived guard: fails immediately on violation rather than polling once at a deadline; 1800 ticks is ample for the feed pass to burn through the spendable 10 coal above the reserve.
    Harness.watch('reserve never dips below ' .. RESERVE_AMOUNT .. ' coal', function()
        return player.get_main_inventory().get_item_count(RESERVE_ITEM) < RESERVE_AMOUNT
    end, 1800)

    Harness.summary_after(1860)
end)
