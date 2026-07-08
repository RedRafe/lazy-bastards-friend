--- Test bench for lazy-bastards-friend. Start via New Game → lazy-bastards-friend
--- → test-bench. Builds a machine park around spawn and hands every new player a
--- kit of test items, so each M2+ pass can be exercised within seconds.
---
--- This is the scenario level script: it runs next to (not inside) the mod's
--- control.lua and must not touch the mod's storage. Cross-mod pokes go through
--- the console, e.g. reserves:
---   /c __lazy-bastards-friend__ storage.players[1].reserves['coal'] = 50

local AREA = { { -18, -20 }, { 18, 18 } } -- bench footprint, cleared and flattened

--- Entities placed relative to spawn. `items` = inventory define -> item -> count.
local BENCH = {
    -- Furnace row (fuel + collect passes): empty, ore-no-fuel, smelting, low-fuel
    { name = 'stone-furnace', position = { -10, -6 } },
    { name = 'stone-furnace', position = { -6, -6 }, items = { [defines.inventory.crafter_input] = { ['iron-ore'] = 50 } } },
    { name = 'stone-furnace', position = { -2, -6 }, items = { [defines.inventory.crafter_input] = { ['iron-ore'] = 50 }, [defines.inventory.fuel] = { ['coal'] = 5 } } },
    { name = 'stone-furnace', position = { 2, -6 }, items = { [defines.inventory.fuel] = { ['coal'] = 1 } } },
    { name = 'stone-furnace', position = { 6, -6 }, items = { [defines.inventory.crafter_input] = { ['copper-ore'] = 50 }, [defines.inventory.fuel] = { ['coal'] = 5 } } },
    { name = 'stone-furnace', position = { 10, -6 } },
    -- Drills on the spawned ore patch (fuel pass on mining drills)
    { name = 'burner-mining-drill', position = { -4, -14 }, direction = defines.direction.south },
    { name = 'burner-mining-drill', position = { 2, -14 }, direction = defines.direction.south },
    { name = 'stone-furnace', position = { -4, -12 } },
    { name = 'stone-furnace', position = { 2, -12 } },
    -- Turret row (ammo pass): empty, partially loaded, artillery; boiler + inserter (fuel pass)
    { name = 'gun-turret', position = { -8, 6 } },
    { name = 'gun-turret', position = { -4, 6 }, items = { [defines.inventory.turret_ammo] = { ['firearm-magazine'] = 5 } } },
    { name = 'artillery-turret', position = { 4, 6 } },
    { name = 'boiler', position = { 10, 6 } },
    { name = 'burner-inserter', position = { 6, 12 } },
    -- Chest row: loot target (opt-in chest take) + empty chest (M4 trash drain)
    { name = 'wooden-chest', position = { -2, 12 }, items = { [defines.inventory.chest] = { ['coal'] = 50, ['iron-plate'] = 100 } } },
    { name = 'iron-chest', position = { 2, 12 } },
    -- Powered assembler crafting gears (collect pass now, ingredient pass in M4)
    { name = 'assembling-machine-1', position = { 10, 12 }, recipe = 'iron-gear-wheel', items = { [defines.inventory.crafter_input] = { ['iron-plate'] = 40 } } },
    -- Labs for the SPM watchdog (M3): research is queued but the labs start
    -- empty — insert packs from the kit to make science flow and trip it.
    { name = 'lab', position = { 15, 12 } },
    { name = 'lab', position = { 15, 15 } },
    { name = 'medium-electric-pole', position = { 12.5, 12.5 } },
    -- base's creative power source: 500GW, no collision box
    { name = 'hidden-electric-energy-interface', position = { 12.5, 12.5 } },
}

--- Per-player starting kit: one fuel of each tier (best-first feeding), ore,
--- plates, two ammo tiers, artillery shells.
local KIT = {
    ['coal'] = 100,
    ['wood'] = 50,
    ['solid-fuel'] = 20,
    ['iron-ore'] = 100,
    ['iron-plate'] = 200,
    ['firearm-magazine'] = 60,
    ['piercing-rounds-magazine'] = 40,
    ['artillery-shell'] = 10,
    ['automation-science-pack'] = 200,
}

local function build_bench(surface, force)
    surface.request_to_generate_chunks({ 0, 0 }, 3)
    surface.force_generate_chunk_requests()

    local tiles = {}
    for x = AREA[1][1], AREA[2][1] do
        for y = AREA[1][2], AREA[2][2] do
            tiles[#tiles + 1] = { name = 'grass-1', position = { x, y } }
        end
    end
    surface.set_tiles(tiles, true)

    for _, entity in pairs(surface.find_entities_filtered({ area = AREA })) do
        if entity.valid and entity.type ~= 'character' then
            entity.destroy()
        end
    end

    -- Small iron patch under the drills
    for x = -5, 5 do
        for y = -16, -12 do
            surface.create_entity({ name = 'iron-ore', position = { x, y }, amount = 800 })
        end
    end

    for _, spec in pairs(BENCH) do
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
    end

    force.chart(surface, AREA)
end

script.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    build_bench(surface, game.forces.player)
    -- Watchdog test setup: research is queued so the labs consume packs the
    -- moment they get some, and the threshold is low enough to trip within
    -- ~30s of research (3 checks × ~10s) instead of needing a 45 SPM factory.
    -- Runtime-global settings can only be written by their owning mod, so the
    -- threshold goes through the mod's remote interface (docs/API.md).
    game.forces.player.technologies['steam-power'].researched = true
    game.forces.player.technologies['electronics'].researched = true
    game.forces.player.technologies['automation-science-pack'].researched = true
    game.forces.player.add_research('automation')
    remote.call('lazy-bastards-friend', 'set_spm_threshold', 5)
end)

script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    local main = player.get_main_inventory()
    if main then
        for name, count in pairs(KIT) do
            main.insert({ name = name, count = count })
        end
    end

    player.game_view_settings.show_entity_info = true

    player.print('[color=yellow]LBF test bench[/color]: furnaces north, turrets south, chests + assembler south-east.')
    player.print('Reserves: /c __lazy-bastards-friend__ storage.players[' .. player.index .. "].reserves['coal'] = 50")
    player.print('Watchdog: threshold is lowered to 5 SPM — put science packs into the labs south-east and it should retire the mod in ~30s. Admin panel: /lbf-admin or the button in the character-screen side panel.')
end)
