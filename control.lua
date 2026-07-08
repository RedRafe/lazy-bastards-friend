--- Wiring only: module requires, refresh-handler registration, event dispatch.
--- All behavior lives in scripts/ (see DESIGN.md §11).

local State = require('scripts.state')
local Rendering = require('scripts.rendering')
local RelativeGui = require('scripts.gui.relative')
local AdminGui = require('scripts.gui.admin')
local Shortcut = require('scripts.shortcut')
local Scheduler = require('scripts.scheduler')
local Watchdog = require('scripts.watchdog')
local Raid = require('scripts.raid')
require('scripts.remote')

State.add_refresh_handler(Rendering.refresh)
State.add_refresh_handler(RelativeGui.sync)
State.add_refresh_handler(AdminGui.sync)
State.add_refresh_handler(Shortcut.sync)
State.add_refresh_handler(Watchdog.refresh)
State.add_refresh_handler(Scheduler.refresh)
Watchdog.add_check_listener(AdminGui.refresh_all) -- live SPM readout while open

-- Tiny dispatcher so multiple modules can subscribe to the same event without
-- clobbering each other's script.on_event registration.
--- @type table<uint, fun(event)[]>
local handlers = {}

--- @param event_id defines.events|string
--- @param handler fun(event)
local function on(event_id, handler)
    local list = handlers[event_id]
    if not list then
        list = {}
        handlers[event_id] = list
        script.on_event(event_id, function(event)
            for _, fn in pairs(list) do
                fn(event)
            end
        end)
    end
    list[#list + 1] = handler
end

--- @param player LuaPlayer
local function setup_player(player)
    State.init_player(player)
    RelativeGui.build(player)
    State.refresh(player)
end

-- == Lifecycle ==============================================================

script.on_init(function()
    State.init()
    Raid.rebuild_smelt_map()
    for _, player in pairs(game.players) do
        setup_player(player)
    end
    Watchdog.rebuild()
end)

script.on_configuration_changed(function()
    State.init()
    Raid.rebuild_smelt_map()
    AdminGui.close_all() -- schemas may have changed; stale frames crash sync
    for _, player in pairs(game.players) do
        RelativeGui.build(player)
        State.refresh(player)
    end
    Watchdog.rebuild()
end)

-- on_load may only read storage: re-register the conditional nth-tick
-- handlers exactly as the saved state implies.
script.on_load(function()
    Scheduler.apply()
    Watchdog.apply()
end)

on(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if player then
        setup_player(player)
    end
end)

on(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    if player then
        RelativeGui.ensure(player)
        State.refresh(player)
    end
    AdminGui.refresh_all() -- online dots + connected-only lists
end)

on(defines.events.on_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if player then
        AdminGui.close(player)
        State.refresh(player) -- player.connected is false: destroys renders
    end
    AdminGui.refresh_all()
end)

on(defines.events.on_player_removed, function(event)
    local data = storage.players[event.player_index]
    if data then
        Rendering.destroy(data)
        storage.players[event.player_index] = nil
    end
    storage.admin_guis[event.player_index] = nil
    AdminGui.refresh_all()
end)

on(defines.events.on_player_demoted, function(event)
    local player = game.get_player(event.player_index)
    if player then
        AdminGui.close(player) -- their frame must not outlive their rights
        State.refresh(player) -- hides the admin button in their panel
    end
end)

on(defines.events.on_player_promoted, function(event)
    local player = game.get_player(event.player_index)
    if player then
        State.refresh(player)
    end
end)

-- Renders live on a fixed surface and/or target the character entity, so any
-- surface/character change requires a destroy+redraw.
for _, event_id in pairs({
    defines.events.on_player_changed_surface,
    defines.events.on_player_respawned,
    defines.events.on_player_died,
    defines.events.on_player_controller_changed,
}) do
    on(event_id, function(event)
        local player = game.get_player(event.player_index)
        if player then
            State.refresh(player)
        end
    end)
end

on(defines.events.on_player_color_changed, function(event)
    local player = game.get_player(event.player_index)
    if player then
        Rendering.on_color_changed(player)
    end
end)

-- == Controls ===============================================================

on(defines.events.on_lua_shortcut, function(event)
    if event.prototype_name ~= 'lbf-toggle' then
        return
    end
    local player = game.get_player(event.player_index)
    if player then
        Shortcut.toggle(player)
    end
end)

on('lbf-toggle', function(event)
    local player = game.get_player(event.player_index)
    if player then
        Shortcut.toggle(player)
    end
end)

on(defines.events.on_runtime_mod_setting_changed, function(event)
    local setting = event.setting
    if event.player_index and State.player_settings[setting] then
        local player = game.get_player(event.player_index)
        if player then
            State.pull_setting(player, setting)
            State.refresh(player)
        end
    elseif setting == 'lbf-min-radius' or setting == 'lbf-max-radius' then
        State.refresh_all() -- re-clamp slider bounds and drawn radii everywhere
    elseif setting == 'lbf-allow-chest-take' then
        State.refresh_all() -- grey out / restore the per-player chest checkbox
    elseif setting == 'lbf-update-period' then
        Scheduler.rebuild() -- recompute the nth-tick interval
    elseif setting == 'lbf-watchdog-enabled' or setting == 'lbf-watchdog-stops-combat' or setting == 'lbf-spm-threshold' then
        storage.spm_strikes = 0 -- changed rules restart the debounce
        Watchdog.rebuild()
        AdminGui.refresh_all()
    end
end)

-- == GUI ====================================================================

on(defines.events.on_gui_checked_state_changed, RelativeGui.dispatch)
on(defines.events.on_gui_checked_state_changed, AdminGui.dispatch)
on(defines.events.on_gui_value_changed, RelativeGui.dispatch)
on(defines.events.on_gui_click, RelativeGui.dispatch)
on(defines.events.on_gui_click, AdminGui.dispatch)
on(defines.events.on_gui_selection_state_changed, RelativeGui.dispatch)
on(defines.events.on_gui_elem_changed, RelativeGui.dispatch)
on(defines.events.on_gui_text_changed, RelativeGui.dispatch)
on(defines.events.on_gui_switch_state_changed, AdminGui.dispatch)
on(defines.events.on_gui_closed, AdminGui.on_gui_closed)
