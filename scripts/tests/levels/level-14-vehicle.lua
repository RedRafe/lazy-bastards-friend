--- L14 — Vehicle support (DESIGN.md §10.9, M5). A car with an empty fuel slot
--- sits next to the player's spawn; the player is put in the driver's seat
--- automatically (`character.driving = true` enters the nearest vehicle) and
--- carries fuel the car accepts. Confirms the car's own fuel inventory gets
--- topped up — the AoE actually following the car instead of the character
--- while driving still needs an eyeball check in-game (render state isn't
--- remote-readable), called out in the instructions.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }
local CAR_POSITION = { 2, 0 }

local KIT = { ['solid-fuel'] = 20 }

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    surface.create_entity({ name = 'car', position = CAR_POSITION, force = game.forces.player })
end)

Bench.on_player_created(KIT, 'L14 vehicle', {
    'You start seated in a nearby car with an empty tank and solid fuel in your inventory.',
    "Confirm the Feed channel tops up the car's own fuel slot even though it is not one of the burner machines the other levels test.",
    'Eyeball check: your serviced-area circle should be centered on the car, not on your character, while driving — it should jump back to your character when you get out.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    local character = player.character
    if character then
        character.driving = true -- enters the nearest vehicle: the car spawned above
    end

    Harness.eventually("the ridden car gets fueled from the player's inventory", function()
        local vehicle = player.vehicle
        if not vehicle then
            return false
        end
        local fuel = vehicle.get_fuel_inventory()
        return fuel ~= nil and not fuel.is_empty()
    end, 900)

    Harness.summary_after(960)
end)
