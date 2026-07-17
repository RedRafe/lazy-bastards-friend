--- L01 — Feed channel, fuel pass only. Burner machines in every fuel state (empty, ore-with-no-fuel, fully fed, low-fuel) plus a drill, boiler and burner-inserter, isolated from the ingredient pass (that's L02).

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    { name = 'stone-furnace', position = { -8, -4 } }, -- empty: nothing to smelt, nothing to fuel
    { name = 'stone-furnace', position = { -4, -4 }, items = { [defines.inventory.crafter_input] = { ['iron-ore'] = 50 } } }, -- ore, no fuel
    { name = 'stone-furnace', position = { 0, -4 }, items = { [defines.inventory.fuel] = { ['coal'] = 1 } } }, -- low fuel
    { name = 'stone-furnace', position = { 4, -4 } }, -- second empty target for tiered-fuel testing
    { name = 'burner-mining-drill', position = { -6, 4 }, direction = defines.direction.south },
    { name = 'burner-inserter', position = { 0, 4 } },
    { name = 'boiler', position = { 6, 4 } },
}

--- Tiered fuel kit — verifies the fuel pass prefers higher-value fuel (coal) and only spends what it needs.
local KIT = {
    ['coal'] = 40,
    ['wood'] = 40,
    ['solid-fuel'] = 20,
}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.ore_patch(surface, { { -8, 2 }, { -4, 6 } }, 'iron-ore', 800)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L01 fuel feed', {
    'Walk near the furnaces/drill/boiler/inserter and let the Feed channel top them up from your kit.',
    'Expect coal spent before wood/solid-fuel (best-first) and only as much as each burner needs.',
    'Toggle "Feed fuel" off in your panel to confirm the pass stops.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    Harness.eventually('fuel pass reaches the empty furnaces', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = AREA, name = 'stone-furnace' })) do
            local fuel = entity.get_fuel_inventory()
            if fuel and fuel.is_empty() then
                return false
            end
        end
        return true
    end, 3600)
    Harness.summary_after(3660)
end)
