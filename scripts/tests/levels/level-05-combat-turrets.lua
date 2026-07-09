--- L05 — Combat channel. Ammo-turrets in every ammo state; the Combat channel
--- keeps them topped up from the player's inventory independently of Collect/Feed
--- (DESIGN.md §1: Combat is meant to keep running after the SPM watchdog retires
--- the other two — see L09 for that interaction).

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    { name = 'gun-turret', position = { -8, 0 } }, -- empty
    { name = 'gun-turret', position = { -4, 0 }, items = { [defines.inventory.turret_ammo] = { ['firearm-magazine'] = 5 } } }, -- partial
    { name = 'gun-turret', position = { 0, 0 }, items = { [defines.inventory.turret_ammo] = { ['piercing-rounds-magazine'] = 5 } } }, -- partial, better ammo already loaded
    { name = 'artillery-turret', position = { 6, 0 } }, -- empty, needs artillery shells
}

local KIT = {
    ['firearm-magazine'] = 60,
    ['piercing-rounds-magazine'] = 40,
    ['artillery-shell'] = 10,
}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L05 combat turrets', {
    'Walk near the turrets and let the Combat channel load them from your ammo kit.',
    'The mixed-ammo turret should not get its piercing rounds replaced by firearm rounds — check the pass respects what is already loaded.',
    'Disable the master (shortcut) or your own "Combat" toggle to confirm turrets stop receiving ammo.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    local AMMO_INVENTORY = {
        ['ammo-turret'] = defines.inventory.turret_ammo,
        ['artillery-turret'] = defines.inventory.artillery_turret_ammo,
    }
    Harness.eventually('every turret received ammo', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = AREA, type = { 'ammo-turret', 'artillery-turret' } })) do
            local ammo = entity.get_inventory(AMMO_INVENTORY[entity.type])
            if ammo and ammo.is_empty() then
                return false
            end
        end
        return true
    end, 3600)
    Harness.summary_after(3660)
end)
