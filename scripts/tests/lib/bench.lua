--- Shared setup helpers for the test-bench campaign (scripts/tests/levels/*).
--- Every level is an independent scenario save: it must not touch the mod's own
--- storage directly (cross-mod pokes go through `remote.call('lazy-bastards-friend',
--- ...)`, see docs/API.md) but it can freely build its own bench geometry with the
--- helpers below.

local Event = require('__lazy-bastards-friend__.scripts.lib.event')
local Gui = require('__lazy-bastards-friend__.scripts.tests.lib.gui')

local Bench = {}

--- Flattens, clears and tiles a rectangular area, then charts it for `force`.
--- @param surface LuaSurface
--- @param area BoundingBox `{ { x1, y1 }, { x2, y2 } }`
--- @param force LuaForce
--- @param tile string tile name to lay down, default 'grass-1'
function Bench.prepare_area(surface, area, force, tile)
    surface.request_to_generate_chunks({ 0, 0 }, 3)
    surface.force_generate_chunk_requests()

    local tiles = {}
    for x = area[1][1], area[2][1] do
        for y = area[1][2], area[2][2] do
            tiles[#tiles + 1] = { name = tile or 'grass-1', position = { x, y } }
        end
    end
    surface.set_tiles(tiles, true)

    for _, entity in pairs(surface.find_entities_filtered({ area = area })) do
        if entity.valid and entity.type ~= 'character' then
            entity.destroy()
        end
    end

    force.chart(surface, area)
end

--- Lays down a resource patch as a solid rectangle.
--- @param surface LuaSurface
--- @param area BoundingBox
--- @param name string resource entity name, e.g. 'iron-ore'
--- @param amount integer per tile
function Bench.ore_patch(surface, area, name, amount)
    for x = area[1][1], area[2][1] do
        for y = area[1][2], area[2][2] do
            surface.create_entity({ name = name, position = { x, y }, amount = amount })
        end
    end
end

--- Builds every entity in `specs` and fills the requested inventories.
--- @param surface LuaSurface
--- @param force LuaForce
--- @param specs { name: string, position: MapPosition, direction: defines.direction?, recipe: string?, items: table<defines.inventory, table<string, integer>>? }[]
--- @return table<string, LuaEntity> entities keyed by spec position ("x,y") for specs that need a handle back
function Bench.spawn(surface, force, specs)
    local built = {}
    for _, spec in pairs(specs) do
        local entity = surface.create_entity({
            name = spec.name,
            position = spec.position,
            direction = spec.direction,
            force = force,
            recipe = spec.recipe,
            create_build_effect_smoke = false,
        })
        if entity and spec.items then
            for define, contents in pairs(spec.items) do
                local inventory = entity.get_inventory(define)
                if inventory then
                    for name, count in pairs(contents) do
                        inventory.insert({ name = name, count = count })
                    end
                end
            end
        end
        if entity then
            built[spec.position[1] .. ',' .. spec.position[2]] = entity
        end
    end
    return built
end

--- Fills a player's main inventory with a starting kit.
--- @param player LuaPlayer
--- @param kit table<string, integer>
function Bench.give_kit(player, kit)
    local main = player.get_main_inventory()
    if not main then
        return
    end
    for name, count in pairs(kit) do
        main.insert({ name = name, count = count })
    end
end

--- Researches a list of technologies outright (no queueing, no prerequisites check
--- beyond what `researched = true` already cascades).
--- @param force LuaForce
--- @param names string[]
function Bench.research(force, names)
    for _, name in pairs(names) do
        local technology = force.technologies[name]
        if technology then
            technology.researched = true
        end
    end
end

--- Sets the level tag + instruction lines shown in the on-screen results
--- panel (scripts/tests/lib/gui.lua).
--- @param player LuaPlayer
--- @param tag string short level tag, e.g. "L01 fuel feed"
--- @param lines string[]
function Bench.intro(player, tag, lines)
    Gui.set_header('LBF test — ' .. tag, lines)
    player.game_view_settings.show_entity_info = true
end

--- Standard on_player_created wiring: give the kit, show the intro, done once
--- per player. Call this from a level's top level, e.g.:
---   Bench.on_player_created(KIT, 'L01 fuel feed', LINES)
--- @param kit table<string, integer>
--- @param tag string
--- @param lines string[]
function Bench.on_player_created(kit, tag, lines)
    Event.add(defines.events.on_player_created, function(event)
        local player = game.get_player(event.player_index)
        if not player then
            return
        end
        Bench.give_kit(player, kit)
        Bench.intro(player, tag, lines)
    end)
end

return Bench
