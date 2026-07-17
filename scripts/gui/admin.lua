--- Admin frame (DESIGN.md §4.3), tabbed like the map-settings GUI:
--- - Watchdog tab: on/off switch (On after a trip re-arms — the only re-arm
---   path), SPM threshold field, live SPM/status readout.
--- - Players tab: /admin-style roster (titlebar search, alphabetical) where
---   every row is "On/Off switch + one lock checkbox per channel", including
---   the global "Everyone" row above the table (global switch + masters).
--- Opened from the button in the relative panel or the /lbf-admin command.
--- Every action is re-checked against player.admin server-side — a GUI can go
--- stale between demotion and the close we do on on_player_demoted.

local State = require('__lazy-bastards-friend__.scripts.state')
local Watchdog = require('__lazy-bastards-friend__.scripts.watchdog')
local GuiUtil = require('__lazy-bastards-friend__.scripts.lib.gui')

local set_style = GuiUtil.set_style

local Admin = {}

local FRAME_NAME = 'lbf-admin'

--- @param player LuaPlayer
--- @return LuaGuiElement? valid open frame, clearing stale registry entries
local function get_frame(player)
    if not storage.admin_guis then
        return nil -- pre-M3 save, before on_configuration_changed ran State.init
    end
    local frame = storage.admin_guis[player.index]
    if frame and frame.valid then
        return frame
    end
    storage.admin_guis[player.index] = nil
    return nil
end

--- The tabbed pane, at the bottom of the vanilla nesting for tabbed GUIs:
--- frame > entity_frame > inside_shallow_frame > tab_deep_frame_in_entity_frame > tabbed_pane.
--- @param frame LuaGuiElement
--- @return LuaGuiElement
local function get_tabs(frame)
    return frame.shell.deep['lbf-tabs']
end

--- Point the blurb above the tabs at the selected tab's feature. Keyed on the
--- tab content's name, so adding a tab only needs a matching locale entry.
--- @param frame LuaGuiElement
local function update_tab_description(frame)
    local tabs = get_tabs(frame)
    local content = tabs.tabs[tabs.selected_tab_index or 1].content
    frame.shell['lbf-tab-desc'].caption = { 'lbf-gui.tab-desc-' .. content.name }
end

-- Status label font color, keyed on Watchdog.status(): green while armed and
-- watching, red once tripped (auto-retired), grey when turned off by
-- setting, yellow while idle (nothing left to retire).
local STATUS_COLORS = {
    armed = { r = 0.3, g = 0.9, b = 0.3 },
    tripped = { r = 1, g = 0.3, b = 0.3 },
    disabled = { r = 0.6, g = 0.6, b = 0.6 },
    idle = { r = 1, g = 0.8, b = 0.2 },
}

-- == Watchdog tab =============================================================

--- @param parent LuaGuiElement
--- @return LuaGuiElement row
local function add_setting_row(parent, name, caption, tooltip)
    local row = parent.add({ type = 'flow', name = name, direction = 'horizontal', style = 'lbf_row_flow' })
    row.add({ type = 'label', caption = caption, tooltip = tooltip })
    GuiUtil.add_pusher(row)
    return row
end

--- @param parent LuaGuiElement
--- @return LuaGuiElement row
local function add_stat_row(parent, name, caption, tooltip, value_name)
    local row = parent.add({ type = 'flow', name = name, direction = 'horizontal', style = 'lbf_row_flow' })
    row.add({ type = 'label', caption = caption, tooltip = tooltip})
    GuiUtil.add_pusher(row)
    row.add({ type = 'label', name = value_name, tooltip = tooltip })
    return row
end

--- @param tabs LuaGuiElement
local function build_watchdog_tab(tabs)
    -- A plain padded flow: the tabbed pane's own content frame already draws
    -- the panel background.
    local page = set_style(
        tabs.add({ type = 'flow', name = 'watchdog', direction = 'vertical' }),
        { padding = 12, vertical_spacing = 8 }
    )

    local settings_frame = page.add({
        type = 'frame',
        name = 'lbf-settings',
        style = 'bordered_frame',
        caption = { 'lbf-gui.watchdog-settings-frame' },
        direction = 'vertical',
    })

    local enabled_row = add_setting_row(
        settings_frame, 'enabled-row', { 'lbf-gui.watchdog-enabled' }, { 'lbf-gui.watchdog-switch-tooltip' }
    )
    enabled_row.add({
        type = 'switch',
        name = 'lbf-watchdog-switch',
        switch_state = 'right',
        left_label_caption = { 'lbf-gui.switch-off' },
        right_label_caption = { 'lbf-gui.switch-on' },
        tooltip = { 'lbf-gui.watchdog-switch-tooltip' },
        tags = { lbf_admin_action = 'watchdog-switch' },
    })

    local threshold_row = add_setting_row(
        settings_frame, 'threshold-row', { 'lbf-gui.threshold' }, { 'lbf-gui.threshold-tooltip' }
    )
    set_style(threshold_row.add({
        type = 'textfield',
        name = 'lbf-threshold',
        numeric = true,
        allow_decimal = true,
        allow_negative = false,
        tooltip = { 'lbf-gui.threshold-tooltip' },
        tags = { lbf_admin_action = 'threshold' },
    }), { width = 70 })

    local stats_frame = page.add({
        type = 'frame',
        name = 'lbf-stats',
        style = 'bordered_frame',
        caption = { 'lbf-gui.watchdog-stats-frame' },
        direction = 'vertical',
    })

    add_stat_row(stats_frame, 'status-row', { 'lbf-gui.watchdog-status' }, nil, 'lbf-status')
    add_stat_row(stats_frame, 'spm-row', { 'lbf-gui.watchdog-spm' }, nil, 'lbf-spm')
    add_stat_row(stats_frame, 'activity-row', { 'lbf-gui.watchdog-activity' }, { 'lbf-gui.items-moved-tooltip' }, 'lbf-moved')
end

-- == Players tab ==============================================================

--- @param tabs LuaGuiElement
local function build_players_tab(tabs)
    local page = set_style(
        tabs.add({ type = 'flow', name = 'players', direction = 'vertical' }),
        { padding = 12, vertical_spacing = 8 }
    )

    -- Global controls, above the player manager: one captioned bordered frame
    -- whose single row reads exactly like a player row — On/Off switch on the
    -- left (the global whole-mod switch, storage.settings.mod), channel checkboxes
    -- (the masters) on the right.
    local globals = page.add({
        type = 'frame',
        name = 'lbf-globals',
        style = 'bordered_frame',
        caption = { 'lbf-gui.globals-frame' },
        direction = 'horizontal',
    })
    local row = set_style(
        globals.add({ type = 'flow', name = 'row', direction = 'horizontal', style = 'lbf_row_flow' }),
        { horizontal_spacing = 12 }
    )
    row.add({
        type = 'switch',
        name = 'lbf-global-master',
        switch_state = 'right',
        tooltip = { 'lbf-gui.global-switch-tooltip' },
        tags = { lbf_admin_action = 'global-master' },
    })
    for _, channel in pairs(State.channels) do
        row.add({
            type = 'checkbox',
            name = 'lbf-master-' .. channel,
            caption = { 'lbf-gui.col-' .. channel },
            tooltip = { '', { 'lbf-gui.master-tooltip' }, '\n', { 'lbf-gui.col-' .. channel .. '-tooltip' } },
            state = storage.settings[channel].enabled,
            tags = { lbf_admin_action = 'master', channel = channel },
        })
    end

    -- The player manager proper, structured like the vanilla /admin GUI:
    -- frame > subheader_frame_with_text_on_the_right > scroll_pane > table.
    local manager = page.add({ type = 'frame', name = 'manager', style = 'deep_frame_in_shallow_frame', direction = 'vertical' })
    local subheader = manager.add({ type = 'frame', name = 'subheader', style = 'subheader_frame_with_text_on_the_right' })
    local flow = subheader.add({ type = 'flow', name = 'subheader-flow', direction = 'horizontal', style = 'lbf_subheader_flow' })
    GuiUtil.add_pusher(flow)
    flow.add({
        type = 'switch',
        name = 'lbf-scope',
        switch_state = 'left',
        left_label_caption = { 'lbf-gui.scope-connected' },
        right_label_caption = { 'lbf-gui.scope-all' },
        tags = { lbf_admin_action = 'scope' },
    })

    local pane = set_style(
        manager.add({ type = 'scroll-pane', name = 'lbf-players' }),
        { maximal_height = 400, horizontally_stretchable = true }
    )
    pane.add({ type = 'table', name = 'lbf-table', style = 'lbf_players_table', column_count = 2 + #State.channels })
end

--- @param frame LuaGuiElement
local function rebuild_rows(frame)
    local manager = get_tabs(frame).players.manager
    local search = frame.titlebar['lbf-search']
    local query = search.visible and search.text:lower() or ''
    local connected_only = manager.subheader['subheader-flow']['lbf-scope'].switch_state == 'left'
    local grid = manager['lbf-players']['lbf-table']
    grid.clear()

    -- Name column stretches: the widest element sets a table column's width,
    -- so both the header and every name label below carry the stretch flag.
    set_style(
        grid.add({ type = 'label', caption = { 'lbf-gui.col-player' }, style = 'caption_label' }),
        { horizontally_stretchable = true }
    )
    grid.add({ type = 'label', caption = { 'lbf-gui.col-onoff' }, style = 'caption_label' })
    for _, channel in pairs(State.channels) do
        grid.add({
            type = 'label',
            caption = { 'lbf-gui.col-' .. channel },
            tooltip = { 'lbf-gui.col-' .. channel .. '-tooltip' },
            style = 'caption_label',
        })
    end

    --- @type LuaPlayer[]
    local list = {}
    for _, target in pairs(connected_only and game.connected_players or game.players) do
        if query == '' or target.name:lower():find(query, 1, true) then
            list[#list + 1] = target
        end
    end
    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    for _, target in pairs(list) do
        local data = State.get_player_data(target.index)
        local dot = target.connected and '[color=0,0.8,0]●[/color] ' or '[color=0.5,0.5,0.5]○[/color] '
        set_style(
            grid.add({ type = 'label', caption = dot .. target.name }),
            { font_color = target.chat_color, horizontally_stretchable = true }
        )

        -- On/Off: the admin's whole-mod lock for this player.
        local mod = data.settings.mod
        --- @type LocalisedString
        local master_tooltip = { 'lbf-gui.lock-master-tooltip', target.name }
        if not mod.enabled then
            master_tooltip = { '', master_tooltip, '\n', { 'lbf-gui.own-master-off' } }
        end
        grid.add({
            type = 'switch',
            switch_state = mod.allowed and 'right' or 'left',
            enabled = storage.settings.mod.enabled,
            tooltip = master_tooltip,
            tags = { lbf_admin_action = 'lock-master', player_index = target.index },
        })

        for _, channel in pairs(State.channels) do
            --- @type LocalisedString
            local tooltip = { 'lbf-gui.lock-tooltip', target.name }
            if not data.settings[channel].enabled then
                -- The read-only "their own preference differs" indicator (§4.3).
                tooltip = { '', tooltip, '\n', { 'lbf-gui.own-pref-off' } }
            end
            grid.add({
                type = 'checkbox',
                state = data.settings[channel].allowed,
                -- Greyed when something above it already turns the cell moot:
                -- the global switch, that channel's master, or the row's On/Off.
                enabled = storage.settings.mod.enabled and storage.settings[channel].enabled and mod.allowed,
                tooltip = tooltip,
                tags = { lbf_admin_action = 'lock', player_index = target.index, channel = channel },
            })
        end
    end
end

-- == Sync =====================================================================

--- Push current state into one player's open frame. Registered as a State
--- refresh handler; also closes the frame if the viewer lost admin.
--- @param player LuaPlayer
function Admin.sync(player)
    local frame = get_frame(player)
    if not frame then
        return
    end
    if not player.admin then
        Admin.close(player)
        return
    end
    local watchdog = get_tabs(frame).watchdog
    local settings_group = watchdog['lbf-settings']
    -- The switch shows "will the watchdog act": enabled and not tripped.
    -- Off while tripped, so flipping it back to On is the re-arm gesture.
    local armed = settings.global['lbf-watchdog-enabled'].value == true and not storage.auto_disabled
    settings_group['enabled-row']['lbf-watchdog-switch'].switch_state = armed and 'right' or 'left'
    local threshold = settings.global['lbf-spm-threshold'].value --[[@as double]]
    local field = settings_group['threshold-row']['lbf-threshold']
    -- Only overwrite when the value actually differs, so the ~10 s live
    -- refresh doesn't clobber a threshold the admin is mid-typing.
    if tonumber(field.text) ~= threshold then
        field.text = string.format('%g', threshold)
    end
    local stats_group = watchdog['lbf-stats']
    local status = Watchdog.status()
    local status_label = stats_group['status-row']['lbf-status']
    status_label.caption = { 'lbf-gui.watchdog-' .. status }
    set_style(status_label, { font_color = STATUS_COLORS[status] })
    local spm = Watchdog.spm(player.force)
    stats_group['spm-row']['lbf-spm'].caption = string.format('%.1f [img=item.science]/min', spm)
    local moved = storage.items_moved or 0
    stats_group['activity-row']['lbf-moved'].caption = string.format('%d [img=item.lbf-items-moved]', moved)

    local globals = get_tabs(frame).players['lbf-globals'].row
    globals['lbf-global-master'].switch_state = storage.settings.mod.enabled and 'right' or 'left'
    for _, channel in pairs(State.channels) do
        local box = globals['lbf-master-' .. channel]
        box.state = storage.settings[channel].enabled
        box.enabled = storage.settings.mod.enabled -- same greying a player row gets from its switch
    end
    rebuild_rows(frame)
end

--- Sync every open admin frame (join/leave, lock changes, master changes).
--- Free when none are open — the usual case.
function Admin.refresh_all()
    if not storage.admin_guis then
        return
    end
    for player_index in pairs(storage.admin_guis) do
        local player = game.get_player(player_index)
        if player then
            Admin.sync(player)
        else
            storage.admin_guis[player_index] = nil
        end
    end
end

-- == Open/close ===============================================================

--- @param player LuaPlayer
function Admin.open(player)
    if not player.admin then
        player.create_local_flying_text({
            text = { 'lbf-message.admins-only' },
            create_at_cursor = true,
        })
        return
    end
    local existing = get_frame(player)
    if existing then
        existing.bring_to_front()
        player.opened = existing
        return
    end

    local frame = player.gui.screen.add({ type = 'frame', name = FRAME_NAME, direction = 'vertical' })

    local titlebar = GuiUtil.add_titlebar(frame, {
        caption = { 'lbf-gui.admin-title' },
        close_tags = { lbf_admin_action = 'close' },
    })
    set_style(titlebar, { height = 32, vertical_align = 'top', horizontal_spacing = 8 })

    -- Vanilla /admin search: a frame_action_button in the titlebar toggles a
    -- textfield to its left. Inserted before the close button (titlebar
    -- children so far: label, drag handle, close).
    titlebar.add({
        type = 'textfield',
        name = 'lbf-search',
        style = 'search_popup_textfield',
        visible = false,
        index = 3,
        tags = { lbf_admin_action = 'search' },
    })
    titlebar.add({
        type = 'sprite-button',
        name = 'lbf-search-toggle',
        style = 'frame_action_button',
        sprite = 'utility/search',
        auto_toggle = true,
        tooltip = { 'lbf-gui.search-tooltip' },
        index = 4,
        tags = { lbf_admin_action = 'search-toggle' },
    })

    -- The vanilla nesting for a tabbed GUI:
    -- frame > entity_frame > inside_shallow_frame > tab_deep_frame_in_entity_frame > tabbed_pane.
    -- The pane is named 'lbf-tabs', not 'tabs': indexing an element with .tabs
    -- hits the LuaGuiElement API attribute (tabbed-pane only), not the child.
    local shell = frame.add({ type = 'frame', name = 'shell', style = 'entity_frame', direction = 'vertical' })
    -- One-line blurb for the selected tab, heading the entity frame.
    set_style(
        shell.add({ type = 'label', name = 'lbf-tab-desc' }),
        { single_line = false, width = 400 }
    )
    local deep = shell.add({ type = 'frame', name = 'deep', style = 'tab_deep_frame_in_entity_frame', direction = 'vertical' })
    local tabs = deep.add({ type = 'tabbed-pane', name = 'lbf-tabs', tags = { lbf_admin_action = 'tab' } })
    local watchdog_tab = tabs.add({ type = 'tab', caption = { 'lbf-gui.tab-watchdog' } })
    build_watchdog_tab(tabs)
    tabs.add_tab(watchdog_tab, tabs.watchdog)
    local players_tab = tabs.add({ type = 'tab', caption = { 'lbf-gui.tab-players' } })
    build_players_tab(tabs)
    tabs.add_tab(players_tab, tabs.players)
    tabs.selected_tab_index = 2 -- player management is the everyday page
    update_tab_description(frame)

    storage.admin_guis[player.index] = frame
    frame.force_auto_center()
    player.opened = frame
    Admin.sync(player)
end

--- @param player LuaPlayer
function Admin.close(player)
    local frame = get_frame(player)
    if frame then
        frame.destroy()
        storage.admin_guis[player.index] = nil
    end
end

--- Close every open admin frame — the GUI schema may have changed
--- (on_configuration_changed); stale frames would crash the next sync.
function Admin.close_all()
    if not storage.admin_guis then
        return
    end
    for player_index in pairs(storage.admin_guis) do
        local player = game.get_player(player_index)
        if player then
            Admin.close(player)
        else
            storage.admin_guis[player_index] = nil
        end
    end
end

--- @param player LuaPlayer
function Admin.toggle(player)
    if get_frame(player) then
        Admin.close(player)
    else
        Admin.open(player)
    end
end

-- == Actions ==================================================================

--- One dispatcher for every admin element, keyed on tags.lbf_admin_action
--- (the open button lives in the relative panel but is tagged for us too).
--- GuiUtil.new_dispatcher asserts each action is only registered once, so a
--- copy-pasted `on_action` can't silently shadow an earlier handler.
local on_action, dispatch_action = GuiUtil.new_dispatcher('lbf_admin_action')

--- Re-checks player.admin before running a handler — a GUI can go stale
--- between demotion and the close we do on on_player_demoted.
--- @param handler fun(event: table, element: LuaGuiElement, tags: table, player: LuaPlayer)
--- @return fun(event: table, element: LuaGuiElement, tags: table, player: LuaPlayer)
local function admin_only(handler)
    return function(event, element, tags, player)
        if not player.admin then
            Admin.close(player) -- stale frame after demotion
            return
        end
        handler(event, element, tags, player)
    end
end

on_action('toggle', function(_, _, _, player)
    Admin.toggle(player)
end)

on_action('close', function(_, _, _, player)
    Admin.close(player)
end)

on_action('global-master', admin_only(function(_, element)
    State.set_global_master(element.switch_state == 'right')
    State.refresh_all()
    Admin.refresh_all()
end))

on_action('master', admin_only(function(_, element, tags)
    State.set_master(tags.channel --[[@as LbfChannel]], element.state)
    State.refresh_all()
    Admin.refresh_all()
end))

on_action('lock', admin_only(function(_, element, tags)
    State.set_locked(tags.player_index --[[@as uint]], tags.channel --[[@as LbfChannel]], not element.state)
    local target = game.get_player(tags.player_index --[[@as uint]])
    if target then
        State.refresh(target)
    end
    Admin.refresh_all()
end))

on_action('lock-master', admin_only(function(_, element, tags)
    State.set_locked_master(tags.player_index --[[@as uint]], element.switch_state == 'left')
    local target = game.get_player(tags.player_index --[[@as uint]])
    if target then
        State.refresh(target)
    end
    Admin.refresh_all()
end))

on_action('watchdog-switch', admin_only(function(_, element)
    -- set_enabled notifies the check listeners, which refresh all admin GUIs.
    Watchdog.set_enabled(element.switch_state == 'right')
end))

on_action('threshold', admin_only(function(event, element, _, player)
    if event.name ~= defines.events.on_gui_confirmed then
        return
    end
    local value = tonumber(element.text)
    if value and value >= 0 then
        settings.global['lbf-spm-threshold'] = { value = value }
    else
        Admin.sync(player) -- restore the last good value
    end
end))

on_action('tab', admin_only(function(_, _, _, player)
    local frame = get_frame(player)
    if frame then
        update_tab_description(frame)
    end
end))

--- @param player LuaPlayer
local function rebuild_if_open(player)
    local frame = get_frame(player)
    if frame then
        rebuild_rows(frame)
    end
end

on_action('search', admin_only(function(_, _, _, player)
    rebuild_if_open(player)
end))

on_action('scope', admin_only(function(_, _, _, player)
    rebuild_if_open(player)
end))

on_action('search-toggle', admin_only(function(_, element, _, player)
    local frame = get_frame(player)
    if not frame then
        return
    end
    local field = frame.titlebar['lbf-search']
    field.visible = element.toggled
    if element.toggled then
        field.focus()
    elseif field.text ~= '' then
        field.text = '' -- closing the search clears the filter
        rebuild_rows(frame)
    end
end))

--- @param event EventData.on_gui_click|EventData.on_gui_checked_state_changed|EventData.on_gui_switch_state_changed|EventData.on_gui_text_changed|EventData.on_gui_confirmed|EventData.on_gui_selected_tab_changed
function Admin.dispatch(event)
    dispatch_action(event)
end

--- @param event EventData.on_gui_closed
function Admin.on_gui_closed(event)
    local element = event.element
    if element and element.valid and element.name == FRAME_NAME then
        local player = game.get_player(event.player_index)
        if player then
            Admin.close(player)
        end
    end
end

commands.add_command('lbf-admin', { 'lbf-message.admin-command-help' }, function(command)
    local player = command.player_index and game.get_player(command.player_index)
    if player then
        Admin.toggle(player)
    end
end)

return Admin
