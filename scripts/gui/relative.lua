--- Per-player settings panel, anchored to the character screen (DESIGN.md §4.2).
--- M1 scope: channel switches + radius slider. Appearance and reserves editors are M4.
--- All interactions route through tags (element.tags.lbf_action), never element names.

local State = require('scripts.state')

local Gui = {}

-- Bump to force a destroy+rebuild of every player's panel on join/config change.
local GUI_VERSION = 2

local FRAME_NAME = 'lbf-relative'

--- @param player LuaPlayer
--- @return LuaGuiElement?
local function get_frame(player)
    return player.gui.relative[FRAME_NAME]
end

--- @param player LuaPlayer
function Gui.build(player)
    local existing = get_frame(player)
    if existing then
        existing.destroy()
    end

    local frame = player.gui.relative.add({
        type = 'frame',
        name = FRAME_NAME,
        direction = 'vertical',
        caption = { 'lbf-gui.title' },
        anchor = {
            gui = defines.relative_gui_type.controller_gui,
            position = defines.relative_gui_position.right,
        },
    })
    local content = frame.add({
        type = 'frame',
        name = 'content',
        style = 'inside_shallow_frame_with_padding',
        direction = 'vertical',
    })

    for _, channel in pairs(State.channels) do
        content.add({
            type = 'checkbox',
            name = 'lbf-channel-' .. channel,
            caption = { 'lbf-gui.channel-' .. channel },
            state = true,
            tags = { lbf_action = 'toggle-channel', channel = channel },
        })
    end

    content.add({ type = 'line', name = 'separator' })

    local radius_flow = content.add({ type = 'flow', name = 'radius-flow', direction = 'horizontal' })
    radius_flow.style.vertical_align = 'center'
    radius_flow.add({ type = 'label', name = 'radius-label', caption = { 'lbf-gui.radius' }, tooltip = { 'lbf-gui.radius-tooltip' } })
    radius_flow.add({
        type = 'slider',
        name = 'lbf-radius-slider',
        minimum_value = 1,
        maximum_value = 100,
        value = 16,
        value_step = 1,
        tags = { lbf_action = 'radius-slider' },
    })
    radius_flow.add({ type = 'label', name = 'lbf-radius-value', caption = '16' })

    -- Tagged for the admin dispatcher (scripts/gui/admin.lua), not ours.
    content.add({
        type = 'button',
        name = 'lbf-admin-open',
        caption = { 'lbf-gui.admin-open' },
        tooltip = { 'lbf-gui.admin-open-tooltip' },
        tags = { lbf_admin_action = 'toggle' },
    })

    State.get_player_data(player.index).gui_version = GUI_VERSION
    Gui.sync(player)
end

--- Rebuild only when missing or from an older schema (used on join/config change).
--- @param player LuaPlayer
function Gui.ensure(player)
    if not get_frame(player) or State.get_player_data(player.index).gui_version ~= GUI_VERSION then
        Gui.build(player)
    end
end

--- Push storage state into the panel: checkbox states, enabled/disabled with a
--- "why" tooltip, slider bounds and value. Registered as a State refresh handler.
--- @param player LuaPlayer
function Gui.sync(player)
    local frame = get_frame(player)
    if not frame then
        return
    end
    local content = frame.content
    local data = State.get_player_data(player.index)

    for _, channel in pairs(State.channels) do
        local checkbox = content['lbf-channel-' .. channel]
        checkbox.state = data.enabled[channel]
        if not storage.active[channel] then
            checkbox.enabled = false
            checkbox.tooltip = { 'lbf-gui.master-off' }
        elseif data.locked[channel] then
            checkbox.enabled = false
            checkbox.tooltip = { 'lbf-gui.locked-by-admin' }
        else
            checkbox.enabled = true
            checkbox.tooltip = { 'lbf-gui.channel-' .. channel .. '-tooltip' }
        end
    end

    content['lbf-admin-open'].visible = player.admin

    local radius = State.get_radius(player.index)
    local radius_flow = content['radius-flow']
    local slider = radius_flow['lbf-radius-slider']
    slider.set_slider_minimum_maximum(settings.global['lbf-min-radius'].value --[[@as number]], settings.global['lbf-max-radius'].value --[[@as number]])
    slider.slider_value = radius
    radius_flow['lbf-radius-value'].caption = tostring(radius)
end

--- @param event EventData.on_gui_checked_state_changed|EventData.on_gui_value_changed
function Gui.dispatch(event)
    local element = event.element
    if not (element and element.valid) then
        return
    end
    local action = element.tags and element.tags.lbf_action
    if not action then
        return
    end
    local player = game.get_player(event.player_index)
    if not player then
        return
    end

    if action == 'toggle-channel' then
        State.set_player_enabled(player, element.tags.channel --[[@as LbfChannel]], element.state)
        State.refresh(player)
    elseif action == 'radius-slider' then
        State.set_radius(player, element.slider_value)
        State.refresh(player)
    end
end

return Gui
