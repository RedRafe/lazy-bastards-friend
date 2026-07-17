--- L11 — Rebalance pass. Two stone furnaces close enough to share the
--- player's AoE: one starts fully fueled, the other
--- empty. The player carries no coal at all, so the fuel-feed pass (disabled
--- here anyway) could never be responsible for any change — only the
--- machine-to-machine rebalance pass can move coal from one furnace to the
--- other.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    { name = 'stone-furnace', position = { -2, 0 }, items = { [defines.inventory.fuel] = { ['coal'] = 50 } } },
    { name = 'stone-furnace', position = { 2, 0 } }, -- empty: only rebalance can fuel this one
}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created({}, 'L11 rebalance', {
    'You carry no coal at all — the fuel-feed pass has nothing to give.',
    'Walk between the two furnaces and confirm the empty one still gets fueled: only the rebalance pass, stealing surplus from the already-fueled furnace, can explain it.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'feed_fuel', false)
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'feed_ingredients', false)
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'feed_rebalance', true)

    Harness.watch('player coal never changes (rebalance never touches the player)', function()
        return player.get_main_inventory().get_item_count('coal') > 0
    end, 1800)

    Harness.eventually('the empty furnace receives coal from the fueled one', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = AREA, name = 'stone-furnace' })) do
            local fuel = entity.get_fuel_inventory()
            if fuel and fuel.get_item_count('coal') > 0 and fuel.get_item_count('coal') < 50 then
                return true -- neither furnace holds the original 0 or 50 anymore: they balanced
            end
        end
        return false
    end, 1800)

    Harness.summary_after(1860)
end)
