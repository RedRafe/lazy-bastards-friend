--- L07 — Reserved items (DESIGN.md §6). A per-item minimum the mod must never
--- dip below when feeding/collecting on the player's behalf. One empty furnace
--- is enough to drive the player's coal down toward zero if reserves aren't
--- respected; the level sets a 20-coal reserve and the check fails if the pass
--- ever spends past it.

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
    end, 3600)

    -- Long-lived guard: any tick where the reserve is violated is an immediate,
    -- permanent failure, so this check fires as soon as it happens rather than
    -- polling once at a fixed deadline. Uses a period (61) distinct from
    -- Harness's own poller (30) — one mod can't hold two handlers on the same period.
    script.on_nth_tick(61, function()
        if player.get_main_inventory().get_item_count(RESERVE_ITEM) < RESERVE_AMOUNT then
            game.print('[color=red][FAIL][/color] reserve was violated: coal dropped below ' .. RESERVE_AMOUNT)
            script.on_nth_tick(61, nil)
        end
    end)

    Harness.summary_after(3660)
end)
