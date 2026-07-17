--- L02 — Feed channel, ingredient pass (M4). Furnace ore-feed, assembler ingredient-feed and lab science-pack-feed, isolated from the fuel pass (L01 covers that) by pre-fueling everything here.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }

local BENCH = {
    -- Fueled but empty of ore: ingredient pass must supply the iron-ore from the kit.
    { name = 'stone-furnace', position = { -8, -4 }, items = { [defines.inventory.fuel] = { ['coal'] = 5 } } },
    -- Starving assemblers with a recipe set but no ingredients.
    { name = 'assembling-machine-1', position = { -2, -4 }, recipe = 'iron-gear-wheel' },
    { name = 'assembling-machine-1', position = { 4, -4 }, recipe = 'copper-cable' },
    -- Labs for the science-pack feed; research is queued in on_init below.
    { name = 'lab', position = { -2, 4 } },
    { name = 'lab', position = { 2, 4 } },
    { name = 'medium-electric-pole', position = { 1, 0 } },
    { name = 'hidden-electric-energy-interface', position = { 1, 0 } }, -- base's creative power source
}

local KIT = {
    ['iron-ore'] = 100,
    ['iron-plate'] = 100,
    ['copper-plate'] = 100,
    ['automation-science-pack'] = 100,
}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
    Bench.research(game.forces.player, { 'automation-science-pack' })
    game.forces.player.add_research('automation')
end)

Bench.on_player_created(KIT, 'L02 ingredient feed', {
    'Everything here already has fuel/power — walk close and let the Feed channel push ore/plates/packs from your kit.',
    'The furnace should start smelting, both assemblers should start crafting, and the labs should start consuming packs.',
    'Toggle "Feed ingredients" off in your panel to confirm only fuel (none needed here) keeps moving.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    Harness.eventually('assemblers received their ingredients', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = AREA, name = 'assembling-machine-1' })) do
            if entity.get_inventory(defines.inventory.crafter_input).is_empty() then
                return false
            end
        end
        return true
    end, 3600)
    Harness.eventually('labs received science packs', function()
        for _, entity in pairs(player.surface.find_entities_filtered({ area = AREA, name = 'lab' })) do
            if entity.get_inventory(defines.inventory.lab_input).is_empty() then
                return false
            end
        end
        return true
    end, 3600)
    Harness.summary_after(3660)
end)
