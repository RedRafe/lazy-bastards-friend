--- Per-player settings panel, anchored to the character screen (DESIGN.md §4.2).
--- Starts collapsed to a single blue icon button that opens the panel; once
--- opened, the On/Off switch (the per-player master, data.master) sits at the
--- top and content is split into three collapsible sections — Behavior (a
--- Feed row and a Take row, each with an advanced-options expander),
--- Appearance (radius, area visuals and all feedback toggles) and Reserved
--- items. Open/closed and per-section expand state are per-player UI prefs
--- (State.default_ui, data.ui) that persist like any other preference.
--- All interactions route through tags (element.tags.lbf_action), never element names.

local State = require('__lazy-bastards-friend__.scripts.state')
local GuiUtil = require('__lazy-bastards-friend__.scripts.lib.gui')

local set_style = GuiUtil.set_style

local Gui = {}

-- Bump to force a destroy+rebuild of every player's panel on join/config change.
local GUI_VERSION = 5

local FRAME_NAME = 'lbf-relative'

-- Slot columns in the reserved-items grid; filter_slot_table sizes the pane to this.
local RESERVE_COLUMNS = 6

local ANCHOR = {
    gui = defines.relative_gui_type.controller_gui,
    position = defines.relative_gui_position.right,
}

-- The two user-facing behavior rows. Each is a channel checkbox ("Feed
-- machines" / "Collect from machines") plus an advanced-options expander
-- (ui.sections[id]) revealing the fine-grained flags; Feed's advanced list
-- also hosts the combat channel ("Feed turrets") — a channel in the
-- implementation, but "something I feed" to the player.
local BEHAVIOR_GROUPS = {
    {
        id = 'feed',
        channel = 'feed',
        advanced = { { flag = 'fuel' }, { flag = 'ingredients' }, { channel = 'combat' }, { flag = 'trash' }, { flag = 'rebalance' } },
    },
    {
        id = 'take',
        channel = 'collect',
        advanced = { { flag = 'chests' }, { flag = 'ground' } },
    },
}

-- Feedback flags shown at the bottom of the Appearance section ("show my
-- area to everyone" is there too, but has its own caption/tooltip keys).
local APPEARANCE_FLAGS = { 'starvation', 'summary' }

-- Per-player mod setting each behavior flag mirrors (State.push_setting, §8).
local FLAG_SETTING = State.flag_setting

-- Logistic group prefix whose minimum values the import button copies into reserves (§6).
-- Matched case-insensitively as "lbf::<player-name>"; a matching group is renamed to the
-- canonical "LBF::<player-name>" (using the player's exact name) after a successful import.
local IMPORT_GROUP_TAG = 'LBF'

local COLOR_COMPONENTS = { 'r', 'g', 'b' }

-- Slider styles matching Factorio's own player-color picker.
local COLOR_SLIDER_STYLE = { r = 'red_slider', g = 'green_slider', b = 'blue_slider' }

local TOP_SECTIONS = { 'behavior', 'appearance', 'reserves' }

--- @param player LuaPlayer
--- @return LuaGuiElement?
local function get_frame(player)
    return player.gui.relative[FRAME_NAME]
end

--- @param content LuaGuiElement the panel's content frame
--- @param id string top-level section id
--- @return LuaGuiElement the 'lbf-section-<id>' frame
local function section_frame(content, id)
    return content['lbf-section-' .. id]
end

--- @param content LuaGuiElement
--- @param id string
--- @return LuaGuiElement body flow to add section content into
local function add_section(content, id, caption, tooltip)
    local _, body = GuiUtil.add_collapsible(content, id, caption, { lbf_action = 'toggle-section', section = id }, tooltip)
    return body
end

--- The per-player master On/Off switch, at the top of the open panel
--- (mirrored by the toolbar shortcut).
--- @param parent LuaGuiElement
--- @return LuaGuiElement
local function add_master_switch(parent)
    return parent.add({
        type = 'switch',
        name = 'lbf-master',
        switch_state = 'right',
        left_label_caption = { 'lbf-gui.switch-off' },
        right_label_caption = { 'lbf-gui.switch-on' },
        tooltip = { 'lbf-gui.master-switch-tooltip' },
        tags = { lbf_action = 'master-switch' },
    })
end

--- @param parent LuaGuiElement
--- @param channel LbfChannel
--- @return LuaGuiElement
local function add_channel_checkbox(parent, channel)
    return parent.add({
        type = 'checkbox',
        name = 'lbf-channel-' .. channel,
        caption = { 'lbf-gui.channel-' .. channel },
        state = true,
        tags = { lbf_action = 'toggle-channel', channel = channel },
    })
end

--- @param parent LuaGuiElement
--- @param flag string
--- @return LuaGuiElement
local function add_flag_checkbox(parent, flag)
    return parent.add({
        type = 'checkbox',
        name = 'lbf-flag-' .. flag,
        caption = { 'lbf-gui.flag-' .. flag },
        state = false,
        tags = { lbf_action = 'toggle-flag', flag = flag },
    })
end

--- @param player LuaPlayer
function Gui.build(player)
    local existing = get_frame(player)
    if existing then
        existing.destroy()
    end
    local data = State.get_player_data(player.index)

    if not data.ui.open then
        -- Compact form: a single blue icon button, nothing else — it just
        -- opens the panel. The master switch lives in the open panel (and the
        -- toolbar shortcut mirrors it).
        player.gui.relative.add({
            type = 'sprite-button',
            name = FRAME_NAME,
            style = 'lbf_open_button',
            sprite = 'lbf-icon',
            tooltip = { 'lbf-gui.open-tooltip' },
            anchor = ANCHOR,
            tags = { lbf_action = 'toggle-panel' },
        })
        data.gui_version = GUI_VERSION
        return
    end

    local frame = player.gui.relative.add({
        type = 'frame',
        name = FRAME_NAME,
        style = 'lbf_relative_frame',
        direction = 'vertical',
        anchor = ANCHOR,
    })
    GuiUtil.add_titlebar(frame, {
        caption = { 'lbf-gui.title' },
        close_tags = { lbf_action = 'toggle-panel' },
        draggable = false,
    })
    local content = GuiUtil.add_content_frame(frame, 'inside_shallow_frame')

    local master_flow = set_style(content.add({ type = 'flow', name = 'master-flow', direction = 'horizontal', style = 'lbf_row_flow' }), { padding = 8 })
    add_master_switch(master_flow)
    GuiUtil.add_pusher(master_flow)
    -- Tagged for the admin dispatcher (scripts/gui/admin.lua), not ours.
    master_flow.add({
        type = 'sprite-button',
        name = 'lbf-admin-open',
        style = 'tool_button',
        sprite = 'utility/export_slot',
        tooltip = { '', { 'lbf-gui.admin-open' }, '\n', { 'lbf-gui.admin-open-tooltip' } },
        tags = { lbf_admin_action = 'toggle' },
    })

    local behavior_body = add_section(content, 'behavior', { 'lbf-gui.behavior' })
    for _, group in pairs(BEHAVIOR_GROUPS) do
        local row = behavior_body.add({ type = 'flow', name = group.id .. '-row', direction = 'horizontal', style = 'lbf_row_flow' })
        add_channel_checkbox(row, group.channel)
        GuiUtil.add_pusher(row)
        row.add({
            type = 'sprite-button',
            name = 'arrow',
            style = 'frame_action_button',
            sprite = 'utility/expand',
            tooltip = { 'lbf-gui.advanced-tooltip' },
            tags = { lbf_action = 'toggle-section', section = group.id },
        })
        local advanced = behavior_body.add({ type = 'flow', name = group.id .. '-advanced', direction = 'vertical', style = 'lbf_indented_flow' })
        for _, entry in pairs(group.advanced) do
            if entry.flag then
                add_flag_checkbox(advanced, entry.flag)
            else
                add_channel_checkbox(advanced, entry.channel)
            end
        end
    end

    local appearance_body = add_section(content, 'appearance', { 'lbf-gui.appearance' })

    local radius_flow = appearance_body.add({ type = 'flow', name = 'radius-flow', direction = 'horizontal', style = 'lbf_row_flow' })
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

    local shape_flow = appearance_body.add({ type = 'flow', name = 'shape-flow', direction = 'horizontal', style = 'lbf_row_flow' })
    shape_flow.add({ type = 'label', name = 'shape-label', caption = { 'lbf-gui.shape' } })
    shape_flow.add({
        type = 'drop-down',
        name = 'lbf-shape',
        items = { { 'lbf-gui.shape-circle' }, { 'lbf-gui.shape-square' } },
        selected_index = 1,
        tags = { lbf_action = 'shape' },
    })

    local fill_flow = appearance_body.add({ type = 'flow', name = 'fill-flow', direction = 'horizontal', style = 'lbf_row_flow' })
    fill_flow.add({
        type = 'checkbox',
        name = 'lbf-fill',
        caption = { 'lbf-gui.fill' },
        tooltip = { 'lbf-gui.fill-tooltip' },
        state = true,
        tags = { lbf_action = 'fill' },
    })
    fill_flow.add({
        type = 'slider',
        name = 'lbf-opacity',
        minimum_value = 2,
        maximum_value = 50,
        value = 8,
        value_step = 1,
        tooltip = { 'lbf-gui.opacity-tooltip' },
        tags = { lbf_action = 'opacity' },
    })

    appearance_body.add({
        type = 'checkbox',
        name = 'lbf-use-player-color',
        caption = { 'lbf-gui.use-player-color' },
        state = true,
        tags = { lbf_action = 'use-player-color' },
    })

    local color_flow = appearance_body.add({ type = 'flow', name = 'color-flow', direction = 'vertical' })
    for _, component in pairs(COLOR_COMPONENTS) do
        local row = color_flow.add({ type = 'flow', name = 'row-' .. component, direction = 'horizontal', style = 'lbf_row_flow' })
        row.add({ type = 'label', name = 'label', caption = { 'lbf-gui.color-' .. component } })
        row.add({
            type = 'slider',
            name = 'lbf-color-' .. component,
            style = COLOR_SLIDER_STYLE[component],
            minimum_value = 0,
            maximum_value = 255,
            value = 255,
            value_step = 1,
            tags = { lbf_action = 'color', component = component },
        })
        row.add({
            type = 'textfield',
            name = 'lbf-color-value-' .. component,
            style = 'slider_value_textfield',
            text = '255',
            numeric = true,
            allow_decimal = false,
            allow_negative = false,
            tags = { lbf_action = 'color-text', component = component },
        })
    end

    appearance_body.add({
        type = 'checkbox',
        name = 'lbf-flag-show_others',
        caption = { 'lbf-gui.show-others' },
        tooltip = { 'lbf-gui.show-others-tooltip' },
        state = false,
        tags = { lbf_action = 'toggle-flag', flag = 'show_others' },
    })
    add_flag_checkbox(appearance_body, 'starvation')
    add_flag_checkbox(appearance_body, 'summary')

    local reserves_body = add_section(content, 'reserves', { 'lbf-gui.reserves' }, { 'lbf-gui.reserves-tooltip' })

    -- The pane hugs the grid's width; pushers on both sides center it in the body.
    local pane_row = reserves_body.add({ type = 'flow', name = 'reserves-pane-row', direction = 'horizontal' })
    GuiUtil.add_pusher(pane_row)
    local reserves_pane = pane_row.add({
        type = 'scroll-pane',
        name = 'reserves-pane',
        style = 'lbf_reserves_scroll_pane',
        horizontal_scroll_policy = 'never',
    })
    GuiUtil.add_pusher(pane_row)
    reserves_pane.add({ type = 'table', name = 'lbf-reserves', style = 'filter_slot_table', column_count = RESERVE_COLUMNS })

    -- Inline set-reserve editor, hidden until a slot is clicked (never a
    -- separate window — that would fight the character screen for focus).
    local editor = reserves_body.add({
        type = 'flow',
        name = 'reserve-editor',
        direction = 'horizontal',
        style = 'lbf_row_flow',
        visible = false,
    })
    editor.add({
        type = 'choose-elem-button',
        name = 'lbf-reserve-elem',
        style = 'lbf_reserve_elem_button',
        elem_type = 'item',
        tooltip = { 'lbf-gui.reserve-add-tooltip' },
        tags = { lbf_action = 'reserve-editor-elem' },
    })
    editor.add({
        type = 'textfield',
        name = 'lbf-reserve-count',
        style = 'slider_value_textfield',
        numeric = true,
        allow_decimal = false,
        allow_negative = false,
        tooltip = { 'lbf-gui.reserve-count-tooltip' },
        tags = { lbf_action = 'reserve-editor-count' },
    })
    editor.add({
        type = 'slider',
        name = 'lbf-reserve-slider',
        style = 'lbf_reserve_slider',
        minimum_value = 0,
        maximum_value = 100,
        value = 0,
        tooltip = { 'lbf-gui.reserve-count-tooltip' },
        tags = { lbf_action = 'reserve-editor-slider' },
    })
    editor.add({
        type = 'sprite-button',
        name = 'lbf-reserve-confirm',
        style = 'item_and_count_select_confirm',
        sprite = 'utility/check_mark',
        tags = { lbf_action = 'reserve-editor-confirm' },
    })

    -- Import bar at the bottom of the section, styled like the map
    -- generator's "Map exchange string" subfooter.
    local import_footer = reserves_body.add({ type = 'frame', name = 'import-footer', style = 'lbf_reserves_footer_frame' })
    local import_flow = set_style(
        import_footer.add({ type = 'flow', name = 'flow', direction = 'horizontal', style = 'player_input_horizontal_flow' }),
        { horizontally_stretchable = true }
    )
    GuiUtil.add_pusher(import_flow)
    import_flow.add({ type = 'label', name = 'label', caption = { 'lbf-gui.reserves-import' }, style = 'caption_label' })
    import_flow.add({
        type = 'sprite-button',
        name = 'lbf-reserves-import',
        style = 'tool_button',
        sprite = 'utility/import',
        tooltip = { 'lbf-gui.reserves-import-tooltip', IMPORT_GROUP_TAG .. '::' .. player.name },
        tags = { lbf_action = 'reserve-import' },
    })

    data.gui_version = GUI_VERSION
    Gui.sync(player)
end

--- Rebuild only when missing or from an older schema (used on join/config change).
--- @param player LuaPlayer
function Gui.ensure(player)
    if not get_frame(player) or State.get_player_data(player.index).gui_version ~= GUI_VERSION then
        Gui.build(player)
    end
end

--- True when the rendered slots already show exactly these items and counts —
--- sync runs on every panel interaction, so skip the rebuild when nothing changed.
--- @param grid LuaGuiElement
--- @param reserves table<string, uint>
--- @return boolean
local function reserve_slots_match(grid, reserves)
    local total = 0
    for _ in pairs(reserves) do
        total = total + 1
    end
    local children = grid.children
    if #children ~= total + 1 then
        return false
    end
    for i = 1, total do
        local item = children[i].tags.item
        if not item or reserves[item] ~= children[i].number then
            return false
        end
    end
    return true
end

--- One slot per reserved item (count on the number badge) plus a trailing
--- empty slot that appends a new item. All editing goes through the inline
--- set-reserve editor row (left-click); right-click removes the item.
--- @param grid LuaGuiElement
--- @param reserves table<string, uint>
local function sync_reserves(grid, reserves)
    if reserve_slots_match(grid, reserves) then
        return
    end
    grid.clear()
    local names = {}
    for name in pairs(reserves) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in pairs(names) do
        grid.add({
            type = 'sprite-button',
            style = 'slot_button',
            sprite = 'item/' .. name,
            number = reserves[name],
            elem_tooltip = { type = 'item', name = name },
            tooltip = { 'lbf-gui.reserve-slot-tooltip' },
            tags = { lbf_action = 'reserve-slot', item = name },
        })
    end
    grid.add({
        type = 'sprite-button',
        style = 'slot_button',
        tooltip = { '', { 'lbf-gui.reserve-add' }, '\n', { 'lbf-gui.reserve-add-tooltip' } },
        tags = { lbf_action = 'reserve-slot' },
    })
end

--- The inline set-reserve editor row of the reserves section, or nil when the
--- panel is collapsed to the open button.
--- @param player LuaPlayer
--- @return LuaGuiElement?
local function get_reserve_editor(player)
    local frame = get_frame(player)
    local content = frame and frame.type == 'frame' and frame.content
    return content and section_frame(content, 'reserves').body['reserve-editor'] or nil
end

--- Enable/refresh the editor's amount widgets for the currently picked item.
--- Slider notches sit at full stacks (0–10); the textfield takes anything.
--- @param editor LuaGuiElement the editor row
--- @param item string? picked item, nil when the elem button is empty
--- @param count uint? amount to show (defaults kept by callers)
local function sync_editor_count(editor, item, count)
    local slider = editor['lbf-reserve-slider']
    local textfield = editor['lbf-reserve-count']
    local enabled = item ~= nil
    slider.enabled = enabled
    textfield.enabled = enabled
    editor['lbf-reserve-confirm'].enabled = enabled
    if item then
        local stack = prototypes.item[item].stack_size
        -- Step must stay compatible with the bounds at every point, so reset
        -- it before shrinking the range (the previous item's stack could be
        -- larger than the new maximum).
        slider.set_slider_value_step(1)
        slider.set_slider_minimum_maximum(0, 10 * stack)
        slider.set_slider_value_step(stack)
        slider.slider_value = count --[[@as number]]
        textfield.text = tostring(count)
    else
        textfield.text = ''
    end
end

--- Show the editor row prefilled for `item` (nil = adding a new reserve).
--- The slot it was opened from is kept in the row's tags so confirming with a
--- different item replaces it.
--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param item string?
local function open_reserve_editor(player, data, item)
    local editor = get_reserve_editor(player)
    if not editor then
        return
    end
    editor.visible = true
    editor.tags = { item = item }
    editor['lbf-reserve-elem'].elem_value = item
    sync_editor_count(editor, item, item and (data.reserves[item] or prototypes.item[item].stack_size))
end

--- Apply the editor: write the picked item/amount into reserves (replacing the
--- edited item if the picker changed; amount 0 clears it) and hide the row.
--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param editor LuaGuiElement
local function confirm_reserve_editor(player, data, editor)
    local item = editor['lbf-reserve-elem'].elem_value --[[@as string?]]
    local original = editor.tags.item --[[@as string?]]
    if original and original ~= item then
        data.reserves[original] = nil
    end
    if item then
        local count = math.floor(tonumber(editor['lbf-reserve-count'].text) or 0)
        data.reserves[item] = count > 0 and count or nil
    end
    editor.visible = false
    State.refresh(player)
end

--- @param checkbox LuaGuiElement
--- @param data LbfPlayerData
--- @param channel LbfChannel
local function sync_channel_checkbox(checkbox, data, channel)
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

--- @param checkbox LuaGuiElement
--- @param flags table<string, boolean>
--- @param flag string
local function sync_flag_checkbox(checkbox, flags, flag)
    checkbox.state = flags[flag] == true
    checkbox.tooltip = { 'lbf-gui.flag-' .. flag .. '-tooltip' }
end

--- Push storage state into the panel: master switch, checkbox states,
--- enabled/disabled with a "why" tooltip, slider bounds and values, appearance
--- widgets, reserve rows, section expand/collapse. Registered as a State
--- refresh handler. The collapsed state is a bare open button with nothing
--- to sync.
--- @param player LuaPlayer
function Gui.sync(player)
    local frame = get_frame(player)
    if not frame or frame.type ~= 'frame' then
        return
    end
    local data = State.get_player_data(player.index)
    local content = frame.content
    if not content then
        return -- stale pre-M6 schema; ensure() rebuilds on next join
    end
    local flags = data.flags

    content['master-flow']['lbf-master'].switch_state = data.master and 'right' or 'left'

    for _, id in pairs(TOP_SECTIONS) do
        local section = section_frame(content, id)
        local expanded = data.ui.sections[id]
        section['header']['header-flow']['arrow'].sprite = expanded and 'utility/collapse' or 'utility/expand'
        section.body.visible = expanded
    end

    local behavior_body = section_frame(content, 'behavior').body
    for _, group in pairs(BEHAVIOR_GROUPS) do
        local row = behavior_body[group.id .. '-row']
        sync_channel_checkbox(row['lbf-channel-' .. group.channel], data, group.channel)
        local advanced = behavior_body[group.id .. '-advanced']
        local expanded = data.ui.sections[group.id]
        row['arrow'].sprite = expanded and 'utility/collapse' or 'utility/expand'
        advanced.visible = expanded
        for _, entry in pairs(group.advanced) do
            if entry.flag then
                sync_flag_checkbox(advanced['lbf-flag-' .. entry.flag], flags, entry.flag)
            else
                sync_channel_checkbox(advanced['lbf-channel-' .. entry.channel], data, entry.channel)
            end
        end
    end
    local take_advanced = behavior_body['take-advanced']
    if settings.global['lbf-allow-chest-take'].value ~= true then
        local chests = take_advanced['lbf-flag-chests']
        chests.enabled = false
        chests.tooltip = { 'lbf-gui.flag-chests-forbidden' }
    else
        take_advanced['lbf-flag-chests'].enabled = true
    end

    content['master-flow']['lbf-admin-open'].visible = player.admin

    local appearance_body = section_frame(content, 'appearance').body

    local radius = State.get_radius(player.index)
    local radius_flow = appearance_body['radius-flow']
    local slider = radius_flow['lbf-radius-slider']
    slider.set_slider_minimum_maximum(settings.global['lbf-min-radius'].value --[[@as number]], settings.global['lbf-max-radius'].value --[[@as number]])
    slider.slider_value = radius
    radius_flow['lbf-radius-value'].caption = tostring(radius)

    appearance_body['shape-flow']['lbf-shape'].selected_index = data.shape == 'square' and 2 or 1
    local fill_flow = appearance_body['fill-flow']
    fill_flow['lbf-fill'].state = data.fill
    fill_flow['lbf-opacity'].slider_value = math.floor(data.opacity * 100 + 0.5)
    fill_flow['lbf-opacity'].enabled = data.fill
    appearance_body['lbf-use-player-color'].state = data.use_player_color
    local color_flow = appearance_body['color-flow']
    color_flow.visible = not data.use_player_color
    for _, component in pairs(COLOR_COMPONENTS) do
        local row = color_flow['row-' .. component]
        local value = math.floor((data.color[component] or 0) * 255 + 0.5)
        row['lbf-color-' .. component].slider_value = value
        row['lbf-color-value-' .. component].text = tostring(value)
    end
    appearance_body['lbf-flag-show_others'].state = flags.show_others == true
    for _, flag in pairs(APPEARANCE_FLAGS) do
        sync_flag_checkbox(appearance_body['lbf-flag-' .. flag], flags, flag)
    end

    sync_reserves(section_frame(content, 'reserves').body['reserves-pane-row']['reserves-pane']['lbf-reserves'], data.reserves)
end

--- Copy minimum values from the player's logistic group named `LBF::<player-name>`
--- (case-insensitive) into their reserves (§6 — import-on-click only, no live sync).
--- @param player LuaPlayer
--- @param data LbfPlayerData
local function import_reserves(player, data)
    local canonical_name = IMPORT_GROUP_TAG .. '::' .. player.name
    local match_name = canonical_name:lower()
    local character = player.character
    local sections = character and character.get_logistic_sections()
    local imported = 0
    if sections then
        for _, section in pairs(sections.sections) do
            if section.group:lower() == match_name then
                for _, filter in pairs(section.filters) do
                    local value = filter.value
                    local name = value and (value.type == nil or value.type == 'item') and value.name
                    local min = filter.min or 0
                    if name and min > 0 and prototypes.item[name] then
                        data.reserves[name] = math.floor(min)
                        imported = imported + 1
                    end
                end
            end
        end
    end
    if imported > 0 then
        player.print({ 'lbf-message.import-done', imported, canonical_name })
    else
        player.create_local_flying_text({
            text = { 'lbf-message.import-none', canonical_name },
            create_at_cursor = true,
        })
    end
end

--- @param event EventData.on_gui_checked_state_changed|EventData.on_gui_value_changed|EventData.on_gui_click|EventData.on_gui_elem_changed|EventData.on_gui_text_changed|EventData.on_gui_selection_state_changed|EventData.on_gui_switch_state_changed|EventData.on_gui_confirmed
function Gui.dispatch(event)
    local element = event.element
    if not (element and element.valid) then
        return
    end
    local tags = element.tags
    local action = tags and tags.lbf_action
    if not action then
        return
    end
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    local data = State.get_player_data(player.index)

    if action == 'toggle-panel' then
        data.ui.open = not data.ui.open
        Gui.build(player)
    elseif action == 'toggle-section' then
        local section = tags.section --[[@as string]]
        data.ui.sections[section] = not data.ui.sections[section]
        Gui.sync(player)
    elseif action == 'master-switch' then
        State.set_player_master(player, element.switch_state == 'right')
        State.refresh(player)
    elseif action == 'toggle-channel' then
        State.set_player_enabled(player, tags.channel --[[@as LbfChannel]], element.state)
        State.refresh(player)
    elseif action == 'radius-slider' then
        State.set_radius(player, element.slider_value)
        State.refresh(player)
    elseif action == 'toggle-flag' then
        local flag = tags.flag --[[@as string]]
        data.flags[flag] = element.state
        State.push_setting(player, FLAG_SETTING[flag])
        State.refresh(player)
    elseif action == 'shape' then
        data.shape = element.selected_index == 2 and 'square' or 'circle'
        State.push_setting(player, 'lbf-shape')
        State.refresh(player)
    elseif action == 'fill' then
        data.fill = element.state
        State.push_setting(player, 'lbf-fill-area')
        State.refresh(player)
    elseif action == 'opacity' then
        data.opacity = element.slider_value / 100
        State.push_setting(player, 'lbf-opacity')
        State.refresh(player)
    elseif action == 'use-player-color' then
        data.use_player_color = element.state
        State.push_setting(player, 'lbf-use-my-color')
        State.refresh(player)
    elseif action == 'color' then
        local component = tags.component --[[@as string]]
        data.color[component] = element.slider_value / 255
        data.color.a = 1
        State.push_setting(player, 'lbf-color')
        State.refresh(player)
    elseif action == 'color-text' then
        local component = tags.component --[[@as string]]
        local value = tonumber(element.text)
        if value and value >= 0 and value <= 255 then
            data.color[component] = value / 255
            data.color.a = 1
            State.push_setting(player, 'lbf-color')
            State.refresh(player)
        end
    elseif action == 'reserve-slot' then
        local item = tags.item --[[@as string?]]
        if event.button == defines.mouse_button_type.right then
            if item then
                data.reserves[item] = nil
                local editor = get_reserve_editor(player)
                if editor and editor.tags.item == item then
                    editor.visible = false -- it was editing the removed item
                end
                State.refresh(player)
            end
        else
            open_reserve_editor(player, data, item)
        end
    elseif action == 'reserve-editor-elem' then
        -- The picker button also receives plain clicks; only react to the pick.
        if event.name == defines.events.on_gui_elem_changed then
            local item = element.elem_value --[[@as string?]]
            sync_editor_count(element.parent, item, item and (data.reserves[item] or prototypes.item[item].stack_size))
        end
    elseif action == 'reserve-editor-slider' then
        element.parent['lbf-reserve-count'].text = tostring(element.slider_value)
    elseif action == 'reserve-editor-count' then
        if event.name == defines.events.on_gui_confirmed then
            confirm_reserve_editor(player, data, element.parent)
        else
            -- Mid-typing: follow with the slider (clamped), never touch the text.
            element.parent['lbf-reserve-slider'].slider_value = tonumber(element.text) or 0
        end
    elseif action == 'reserve-editor-confirm' then
        confirm_reserve_editor(player, data, element.parent)
    elseif action == 'reserve-import' then
        import_reserves(player, data)
        State.refresh(player)
    end
end

return Gui
