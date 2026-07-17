--- L00 — Showcase. Not a test: no Harness assertions, nothing to pass or
--- fail. A small, hand-placed early-game base built into the natural
--- terrain (trees and rocks are only cleared where a building actually
--- sits, everything else is left standing) so every channel and pass has
--- something to do at once — mining drills and furnaces, crafters and labs,
--- turrets, a loot chest, trash, and ground-dropped items — meant to be
--- screenshotted for the mod's thumbnail/store-page images, not played.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -24, -16 }, { 24, 16 } }

--- Tile footprint (in tiles, radius from center) to clear of trees/rocks before placing a building, keyed by entity name. Everything outside these little pockets keeps its natural terrain.
local FOOTPRINT = {
    ['stone-furnace'] = 1.3,
    ['burner-mining-drill'] = 1.3,
    ['assembling-machine-2'] = 1.9,
    ['lab'] = 1.9,
    ['gun-turret'] = 1.3,
    ['iron-chest'] = 0.8,
    ['wooden-chest'] = 0.8,
    ['electric-energy-interface'] = 1.2,
}

--- Scatters a resource patch as an irregular blob instead of a rectangle — a wobbling radius (two sine harmonics) around `center` so patches look natural rather than blueprinted.
--- @param surface LuaSurface
--- @param center MapPosition
--- @param base_radius number
--- @param name string
--- @param amount integer
local function organic_patch(surface, center, base_radius, name, amount)
    local cx, cy = center[1], center[2]
    local pad = base_radius + 3
    for x = math.floor(cx - pad), math.ceil(cx + pad) do
        for y = math.floor(cy - pad), math.ceil(cy + pad) do
            local dx, dy = x - cx, y - cy
            local distance = math.sqrt(dx * dx + dy * dy)
            local angle = math.atan2(dy, dx)
            local wobble = base_radius + math.sin(angle * 3) * 1.5 + math.cos(angle * 5)
            if distance <= wobble then
                surface.create_entity({ name = name, position = { x + 0.5, y + 0.5 }, amount = amount })
            end
        end
    end
end

--- Destroys trees/rocks/etc. in a small box around `position`, leaving the rest of the natural terrain (and any resource entities, e.g. a drill sitting on its own ore patch) untouched.
--- @param surface LuaSurface
--- @param position MapPosition
--- @param half_size number
local function clear_footprint(surface, position, half_size)
    local area = {
        { position[1] - half_size, position[2] - half_size },
        { position[1] + half_size, position[2] + half_size },
    }
    for _, entity in pairs(surface.find_entities_filtered({ area = area })) do
        if entity.valid and entity.type ~= 'character' and entity.type ~= 'resource' then
            entity.destroy()
        end
    end
end

--- Like Bench.spawn, but clears each entity's own footprint out of the natural terrain first instead of flattening the whole area.
--- @param surface LuaSurface
--- @param force LuaForce
--- @param specs table[]
--- @return table<string, LuaEntity>
local function spawn_into_terrain(surface, force, specs)
    for _, spec in pairs(specs) do
        clear_footprint(surface, spec.position, FOOTPRINT[spec.name] or 1.5)
    end
    return Bench.spawn(surface, force, specs)
end

local IRON_PATCH = { -18, -6 }
local COPPER_PATCH = { 16, -7 }

local BENCH = {
    -- Mining drills, sat on the organic ore blobs below.
    { name = 'burner-mining-drill', position = { -18, -6 }, direction = defines.direction.east },
    { name = 'burner-mining-drill', position = { 16, -7 }, direction = defines.direction.west },

    -- Furnace cluster fed by the iron drill: every fuel/ore state at once, staggered rather than gridded.
    { name = 'stone-furnace', position = { -13, 2 } }, -- empty: nothing to smelt or burn
    { name = 'stone-furnace', position = { -10, 3 }, items = { [defines.inventory.crafter_input] = { ['iron-ore'] = 40 } } }, -- ore, no fuel
    { name = 'stone-furnace', position = { -7, 1 }, items = { [defines.inventory.fuel] = { ['coal'] = 2 } } }, -- low fuel, no ore
    { name = 'stone-furnace', position = { -4, 3 }, items = { [defines.inventory.crafter_input] = { ['iron-ore'] = 40 }, [defines.inventory.fuel] = { ['coal'] = 50 } } }, -- fully fed, mid-smelt
    { name = 'stone-furnace', position = { -1, 2 } }, -- second empty target

    -- Crafters fed by the copper drill.
    { name = 'assembling-machine-2', position = { 9, 3 }, recipe = 'iron-gear-wheel' },
    { name = 'assembling-machine-2', position = { 14, 2 }, recipe = 'copper-cable', items = { [defines.inventory.crafter_input] = { ['copper-plate'] = 10 } } },

    -- Labs, kept fed by an ever-requeued research (see on_research_finished below).
    { name = 'lab', position = { 3, -6 } },
    { name = 'lab', position = { -3, -8 } },

    -- Power: the surface has one global electric network (see on_init), so every
    -- electric entity is already connected — no poles or wiring needed, just a
    -- source. A hidden electric-energy-interface (vanilla's always-on 500GW supply)
    -- sitting anywhere on the surface covers the whole base.
    { name = 'electric-energy-interface', position = { 5, 0 } },

    -- Turrets on a loose defensive arc south of the base.
    { name = 'gun-turret', position = { -7, 10 } },
    { name = 'gun-turret', position = { 0, 11 }, items = { [defines.inventory.turret_ammo] = { ['firearm-magazine'] = 5 } } },
    { name = 'gun-turret', position = { 7, 9 }, items = { [defines.inventory.turret_ammo] = { ['piercing-rounds-magazine'] = 10 } } },

    -- A full chest for the "collect from chests" demo, and an empty one nearby for trash-drain to fill.
    { name = 'iron-chest', position = { 3, 3 }, items = { [defines.inventory.chest] = {
        ['iron-plate'] = 50, ['copper-plate'] = 50, ['electronic-circuit'] = 20, ['iron-gear-wheel'] = 30,
    } } },
    { name = 'wooden-chest', position = { -2, -3 } },
}

local KIT = {
    ['coal'] = 100,
    ['wood'] = 30,
    ['solid-fuel'] = 20,
    ['iron-ore'] = 50,
    ['iron-plate'] = 100,
    ['copper-plate'] = 100,
    ['automation-science-pack'] = 60,
    ['firearm-magazine'] = 40,
    ['piercing-rounds-magazine'] = 20,
}

local RESERVE_ITEM = 'coal'
local RESERVE_AMOUNT = 50 -- half the kit: leaves some starvation moments for the render, without starving everything permanently

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    surface.always_day = true -- consistent, flattering light for screenshots

    surface.request_to_generate_chunks({ 0, 0 }, 4)
    surface.force_generate_chunk_requests()
    game.forces.player.chart(surface, AREA)
    surface.create_global_electric_network() -- every electric entity shares one network; no poles/wiring needed

    organic_patch(surface, IRON_PATCH, 4, 'iron-ore', 600)
    organic_patch(surface, COPPER_PATCH, 4, 'copper-ore', 600)

    spawn_into_terrain(surface, game.forces.player, BENCH)

    -- Keep the labs fed indefinitely: 'automation' has no prerequisites but only
    -- costs 10 packs (see level-09's fix for the same gotcha), so it's requeued
    -- forever on completion rather than left to go idle.
    game.forces.player.add_research('automation')
end)

Event.add(defines.events.on_research_finished, function(event)
    if event.research.name == 'automation' then
        game.forces.player.add_research('automation')
    end
end)

Bench.on_player_created(KIT, 'L00 showcase', {
    'This is a screenshot rig, not a test: nothing here passes or fails.',
    'Walk around the base and let a raid cycle or two pass — furnaces/crafters/labs fill in, the chest empties into your inventory, ground items and trash get swept up.',
    'Your area is drawn in the default warm color (not your player color); adjust radius/shape/color/opacity from the panel next to your character screen to frame a shot.',
    'A ' .. RESERVE_AMOUNT .. '-coal reserve is set so you will occasionally see a starvation icon flash — toggle it off in the panel if you want a cleaner shot.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    -- A few ground-dropped items near spawn for the "collect ground items" demo.
    for _, drop in pairs({
        { { 2, -3 }, 'iron-plate', 8 },
        { { 3, -2 }, 'copper-plate', 6 },
        { { 1, -1 }, 'coal', 10 },
        { { -2, -1 }, 'iron-gear-wheel', 4 },
    }) do
        player.surface.spill_item_stack({ position = drop[1], stack = { name = drop[2], count = drop[3] }, enable_looted = false, force = player.force })
    end

    -- A couple of items waiting in the trash slots for the "feed trash into chests" demo.
    local trash = player.get_inventory(defines.inventory.character_trash)
    if trash then
        trash.insert({ name = 'wood', count = 20 })
        trash.insert({ name = 'stone', count = 10 })
    end

    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'collect_chests', true)
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'collect_ground', true)
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'feed_trash', true)
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'appearance_starvation', true)
    -- Falls back to the default lbf-color (warm orange) now that it won't use the player's own color; shape/opacity are left at their defaults too — no remote setter exists for those, and the scenario's own script runs as the engine's separate "level" context, so it can't write the mod's settings directly the way the mod's own code can.
    remote.call('lazy-bastards-friend', 'set_player_flag', player.index, 'appearance_use_player_color', false)
    remote.call('lazy-bastards-friend', 'set_player_radius', player.index, 20)
    remote.call('lazy-bastards-friend', 'set_player_reserve', player.index, RESERVE_ITEM, RESERVE_AMOUNT)

    player.zoom = 0.6
end)
