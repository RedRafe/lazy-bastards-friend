--- Wiring only: module requires, refresh-handler registration, event dispatch.
--- All behavior lives in scripts/ (see DESIGN.md §11).

local State = require('__lazy-bastards-friend__.scripts.state')
local Rendering = require('__lazy-bastards-friend__.scripts.rendering')
local RelativeGui = require('__lazy-bastards-friend__.scripts.gui.relative')
local AdminGui = require('__lazy-bastards-friend__.scripts.gui.admin')
local Shortcut = require('__lazy-bastards-friend__.scripts.shortcut')
local Scheduler = require('__lazy-bastards-friend__.scripts.scheduler')
local Watchdog = require('__lazy-bastards-friend__.scripts.watchdog')
local Raid = require('__lazy-bastards-friend__.scripts.raid')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')
require('__lazy-bastards-friend__.scripts.remote')

State.add_refresh_handler(Rendering.refresh)
State.add_refresh_handler(RelativeGui.sync)
State.add_refresh_handler(AdminGui.sync)
State.add_refresh_handler(Shortcut.sync)
State.add_refresh_handler(Watchdog.refresh)
State.add_refresh_handler(Scheduler.refresh)
Watchdog.add_check_listener(AdminGui.refresh_all) -- live SPM readout while open

local on = Event.add

--- @param player LuaPlayer
local function setup_player(player)
    State.init_player(player)
    RelativeGui.build(player)
    State.refresh(player)
end

-- == Lifecycle ==============================================================

Event.on_init(function()
    State.init()
    Raid.rebuild_smelt_map()
    for _, player in pairs(game.players) do
        setup_player(player)
    end
    Watchdog.rebuild()
end)

Event.on_configuration_changed(function()
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
Event.on_load(function()
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
        -- Recreates their own render (hidden while offline, see leave below).
        -- Other owners' whitelists are connection-independent (rendering.lua
        -- iterates game.players, not connected_players), so this player's
        -- entry in them is already correct — no State.refresh_all() needed.
        State.refresh(player)
    end
    AdminGui.refresh_all() -- online dots + connected-only lists
end)

on(defines.events.on_player_left_game, function(event)
    local player = game.get_player(event.player_index)
    if player then
        AdminGui.close(player)
        -- player.connected is now false: Rendering.refresh destroys their own
        -- render without recreating it. Doesn't touch anyone else's whitelist.
        State.refresh(player)
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
    -- The removed index may still be sitting in other owners' render
    -- whitelists (rendering.lua built them from game.players before removal)
    -- — rebuild everyone so none of them hand the engine a stale identity.
    State.refresh_all()
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

-- Renders live on a fixed surface and/or target the character entity,
-- so any surface/character change requires a destroy+redraw.
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

-- Per-entity exclusion cleanup (DESIGN.md §10.4): once an excluded entity is
-- gone, drop it from every player's table — `useful_id` is already the
-- entity's unit_number, so no separate registration-id map is needed.
on(defines.events.on_object_destroyed, function(event)
    local unit_number = event.useful_id
    if not unit_number then
        return
    end
    for _, data in pairs(storage.players) do
        data.excluded[unit_number] = nil
    end
end)

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

-- Per-entity exclusion toggle (DESIGN.md §10.4): hover an entity, press the
-- (unbound-by-default) hotkey. No selection-tool item needed.
on('lbf-toggle-exclude', function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    local entity = player.selected
    if not Raid.is_targetable(entity) then
        player.create_local_flying_text({
            text = { 'lbf-message.exclude-none' },
            create_at_cursor = true,
        })
        return
    end
    local data = State.get_player_data(player.index)
    local unit_number = entity.unit_number
    if data.excluded[unit_number] then
        data.excluded[unit_number] = nil
        player.create_local_flying_text({ text = { 'lbf-message.included' }, create_at_cursor = true })
    else
        data.excluded[unit_number] = true
        script.register_on_object_destroyed(entity)
        player.create_local_flying_text({ text = { 'lbf-message.excluded' }, create_at_cursor = true })
    end
    data.cache = nil
end)

on(defines.events.on_runtime_mod_setting_changed, function(event)
    local setting = event.setting
    if event.player_index and State.player_settings[setting] then
        local player = game.get_player(event.player_index)
        if player then
            State.pull_setting(player, setting)
            if setting == 'lbf-show-others-area' then
                -- Viewer-opt-in (§12): this player's own area is unaffected,
                -- but every other owner's render list needs recomputing to
                -- add/drop this player.
                State.refresh_all()
            else
                State.refresh(player)
            end
        end
    elseif setting == 'lbf-min-radius' or setting == 'lbf-max-radius' then
        State.refresh_all() -- re-clamp slider bounds and drawn radii everywhere
    elseif setting == 'lbf-allow-chest-collect' then
        State.refresh_all() -- grey out / restore the per-player chest checkbox
    elseif setting == 'lbf-update-period' then
        Scheduler.rebuild() -- recompute the nth-tick interval
    elseif setting == 'lbf-watchdog-enabled' or setting == 'lbf-spm-threshold' then
        if setting == 'lbf-watchdog-enabled' and settings.global[setting].value == true then
            -- Turning the watchdog on (settings screen or admin switch) un-trips
            -- it — the only re-arm path; re-enabling masters no longer is (§2.1).
            storage.auto_disabled = false
        end
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
on(defines.events.on_gui_text_changed, AdminGui.dispatch)
on(defines.events.on_gui_confirmed, RelativeGui.dispatch)
on(defines.events.on_gui_confirmed, AdminGui.dispatch)
on(defines.events.on_gui_switch_state_changed, RelativeGui.dispatch)
on(defines.events.on_gui_switch_state_changed, AdminGui.dispatch)
on(defines.events.on_gui_selected_tab_changed, AdminGui.dispatch)
on(defines.events.on_gui_closed, AdminGui.on_gui_closed)
