--- Admin player-management frame (DESIGN.md §4.3): global master switches,
--- SPM/watchdog readout, per-player per-channel lock table with bulk actions.
--- Opened from the button in the relative panel or the /lbf-admin command.
--- Every action is re-checked against player.admin server-side — a GUI can go
--- stale between demotion and the close we do on on_player_demoted.

local State = require('__lazy-bastards-friend__.scripts.state')
local Watchdog = require('__lazy-bastards-friend__.scripts.watchdog')
local set_style = require('__lazy-bastards-friend__.scripts.lib.style')

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

--- @param player LuaPlayer
--- @return LocalisedString
local function status_caption(player)
    local spm = string.format('%.1f', Watchdog.spm(player.force))
    local threshold = settings.global['lbf-spm-threshold'].value
    return { 'lbf-gui.admin-status', spm, tostring(threshold), { 'lbf-gui.watchdog-' .. Watchdog.status() } }
end

--- @param frame LuaGuiElement
local function rebuild_rows(frame)
    local content = frame.content
    local connected_only = content['lbf-scope'].switch_state == 'left'
    local grid = content['lbf-players']['lbf-table']
    grid.clear()

    grid.add({ type = 'label', caption = { 'lbf-gui.col-player' }, style = 'caption_label' })
    for _, channel in pairs(State.channels) do
        grid.add({ type = 'label', caption = { 'lbf-gui.col-' .. channel }, style = 'caption_label' })
    end

    local list = connected_only and game.connected_players or game.players
    for _, target in pairs(list) do
        local data = State.get_player_data(target.index)
        local dot = target.connected and '[color=0,0.8,0]●[/color] ' or '[color=0.5,0.5,0.5]○[/color] '
        set_style(grid.add({ type = 'label', caption = dot .. target.name }), { font_color = target.chat_color })
        for _, channel in pairs(State.channels) do
            --- @type LocalisedString
            local tooltip = { 'lbf-gui.lock-tooltip', target.name }
            if not data.enabled[channel] then
                -- The read-only "their own preference differs" indicator (§4.3).
                tooltip = { '', tooltip, '\n', { 'lbf-gui.own-pref-off' } }
            end
            grid.add({
                type = 'checkbox',
                state = not data.locked[channel],
                tooltip = tooltip,
                tags = { lbf_admin_action = 'lock', player_index = target.index, channel = channel },
            })
        end
    end
end

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
    local content = frame.content
    for _, channel in pairs(State.channels) do
        content['lbf-masters']['lbf-master-' .. channel].state = storage.active[channel]
    end
    content['lbf-status'].caption = status_caption(player)
    content['lbf-moved'].caption = { 'lbf-gui.items-moved', tostring(storage.items_moved or 0) }
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

    local titlebar = frame.add({ type = 'flow', name = 'titlebar', direction = 'horizontal' })
    titlebar.drag_target = frame
    titlebar.add({
        type = 'label',
        caption = { 'lbf-gui.admin-title' },
        style = 'frame_title',
        ignored_by_interaction = true,
    })
    set_style(titlebar.add({ type = 'empty-widget', style = 'draggable_space_header', ignored_by_interaction = true }), {
        horizontally_stretchable = true,
        height = 24,
    })
    titlebar.add({
        type = 'sprite-button',
        style = 'frame_action_button',
        sprite = 'utility/close',
        tags = { lbf_admin_action = 'close' },
    })

    local content = frame.add({
        type = 'frame',
        name = 'content',
        style = 'inside_shallow_frame_with_padding',
        direction = 'vertical',
    })

    local masters = set_style(content.add({ type = 'flow', name = 'lbf-masters', direction = 'horizontal' }), { horizontal_spacing = 12 })
    for _, channel in pairs(State.channels) do
        masters.add({
            type = 'checkbox',
            name = 'lbf-master-' .. channel,
            caption = { 'lbf-gui.col-' .. channel },
            tooltip = { 'lbf-gui.master-tooltip' },
            state = storage.active[channel],
            tags = { lbf_admin_action = 'master', channel = channel },
        })
    end

    content.add({ type = 'label', name = 'lbf-status' })
    content.add({ type = 'label', name = 'lbf-moved', tooltip = { 'lbf-gui.items-moved-tooltip' } })
    content.add({ type = 'line' })

    content.add({
        type = 'switch',
        name = 'lbf-scope',
        switch_state = 'left',
        left_label_caption = { 'lbf-gui.scope-connected' },
        right_label_caption = { 'lbf-gui.scope-all' },
        tags = { lbf_admin_action = 'scope' },
    })

    local pane = set_style(content.add({ type = 'scroll-pane', name = 'lbf-players' }), { maximal_height = 320 })
    set_style(pane.add({ type = 'table', name = 'lbf-table', column_count = 1 + #State.channels }), { horizontal_spacing = 16 })

    local bulk = set_style(content.add({ type = 'flow', name = 'lbf-bulk', direction = 'horizontal' }), { vertical_align = 'center' })
    bulk.add({
        type = 'drop-down',
        name = 'lbf-bulk-channel',
        items = {
            { 'lbf-gui.col-collect' },
            { 'lbf-gui.col-feed' },
            { 'lbf-gui.col-combat' },
            { 'lbf-gui.bulk-channel-all' },
        },
        selected_index = 4,
    })
    for _, mode in pairs({ 'unlock-all', 'lock-all' }) do
        bulk.add({
            type = 'button',
            caption = { 'lbf-gui.bulk-' .. mode },
            tags = { lbf_admin_action = 'bulk', mode = mode },
        })
    end

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

--- Channels a bulk action applies to, from the drop-down next to the buttons.
--- @param frame LuaGuiElement
--- @return LbfChannel[]
local function bulk_channels(frame)
    local index = frame.content['lbf-bulk']['lbf-bulk-channel'].selected_index
    local channel = State.channels[index]
    return channel and { channel } or State.channels
end

--- @param channels LbfChannel[]
--- @param locked boolean
local function bulk_lock(channels, locked)
    for _, target in pairs(game.players) do
        for _, channel in pairs(channels) do
            State.set_locked(target.index, channel, locked)
        end
    end
    State.refresh_all()
end

--- One dispatcher for every admin element, keyed on tags.lbf_admin_action
--- (the open button lives in the relative panel but is tagged for us too).
--- @param event EventData.on_gui_click|EventData.on_gui_checked_state_changed|EventData.on_gui_switch_state_changed
function Admin.dispatch(event)
    local element = event.element
    if not (element and element.valid) then
        return
    end
    local tags = element.tags
    local action = tags and tags.lbf_admin_action
    if not action then
        return
    end
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    if action == 'toggle' then
        Admin.toggle(player)
        return
    elseif action == 'close' then
        Admin.close(player)
        return
    end
    if not player.admin then
        Admin.close(player) -- stale frame after demotion
        return
    end

    if action == 'master' then
        State.set_master(tags.channel --[[@as LbfChannel]], element.state)
        State.refresh_all()
        Admin.refresh_all()
    elseif action == 'lock' then
        State.set_locked(tags.player_index --[[@as uint]], tags.channel --[[@as LbfChannel]], not element.state)
        local target = game.get_player(tags.player_index --[[@as uint]])
        if target then
            State.refresh(target)
        end
        Admin.refresh_all()
    elseif action == 'scope' then
        local frame = get_frame(player)
        if frame then
            rebuild_rows(frame)
        end
    elseif action == 'bulk' then
        local frame = get_frame(player)
        if frame then
            local channels = bulk_channels(frame)
            if tags.mode == 'unlock-all' then
                bulk_lock(channels, false)
            elseif tags.mode == 'lock-all' then
                bulk_lock(channels, true)
            end
            Admin.refresh_all()
        end
    end
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
