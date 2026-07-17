--- Per-player settings panel, anchored to the character screen (DESIGN.md §4.2).
--- Starts collapsed to a single blue icon button that opens the panel; once
--- opened, content is a stack of "family sections" (GuiUtil.add_family_section)
--- — each a plain vertical flow (no frame of its own, so siblings don't draw
--- extra dividers between each other) holding an inside_shallow_frame body,
--- with an optional borderless header row above it (family icon, bold
--- caption, a divider line, a collapse arrow). The On/Off switch (the
--- per-player master, data.settings.mod) plus the admin-panel button sit in
--- the first section, which has no header/collapse control of its own. Then
--- Feed and Collect (each one strip of sprite-buttons: the channel's own
--- master button followed by its child flag buttons), Appearance (the
--- channel's master switch on the left, a vertical divider, then radius,
--- opacity, and a strip of five buttons — shape plus four flags — stacked on
--- the right; colors below), and Reserved items — these four do have the
--- collapsible header. Every checkbox in the
--- panel is a sprite-button (icon + a two-line tooltip — bold title, then
--- description, plus a warning line when admin-blocked) rather than a
--- checkbox with caption text. Open/closed and per-section expand state are
--- per-player UI prefs (State.default_ui, data.ui) that persist like any
--- other preference.
--- All interactions route through tags (element.tags.lbf_action), never element names.

local State = require('__lazy-bastards-friend__.scripts.state')
local GuiUtil = require('__lazy-bastards-friend__.scripts.lib.gui')

local set_style = GuiUtil.set_style

local Gui = {}

-- Bump to force a destroy+rebuild of every player's panel on join/config change.
local GUI_VERSION = 1

local FRAME_NAME = 'lbf-relative'

local SHOW_BANNER = false

-- Slot columns in the reserved-items grid; filter_slot_table sizes the pane to this.
local RESERVE_COLUMNS = 6

local ANCHOR = {
    gui = defines.relative_gui_type.controller_gui,
    position = defines.relative_gui_position.right,
}

-- The two user-facing behavior sections (Feed, Collect — each its own
-- top-level bordered section now, not a row nested under one "Behavior"
-- section). Each is one strip of sprite-buttons: the channel's own master
-- button ("Feed machines" / "Collect from machines") followed by its child
-- flag buttons (tree node ids, `flags`) in the same row — no separate
-- advanced-options expander anymore. 'combat' ("Feed turrets") is a true
-- tree child of 'feed' (DESIGN.md §1/§12) with no admin lock/master of its
-- own — a plain preference like feed_fuel, just placed here in Feed's flag
-- list. 'starvation'/'show-others' live in the Appearance section below —
-- they're tree children of the 'appearance' channel now, not 'feed', so
-- admins can lock the whole render channel independently even though
-- raid.lua only ever populates starvation data during a feed pass.
local BEHAVIOR_GROUPS = {
    {
        id = 'feed',
        channel = 'feed',
        flags = { 'feed_fuel', 'feed_ingredients', 'combat', 'feed_trash', 'feed_rebalance' },
    },
    {
        id = 'collect',
        channel = 'collect',
        flags = { 'collect_chests', 'collect_ground' },
    },
}

-- Logistic group prefix whose minimum values the import button copies into reserves (§6).
-- Matched case-insensitively as "lbf::<player-name>"; a matching group is renamed to the
-- canonical "LBF::<player-name>" (using the player's exact name) after a successful import.
local IMPORT_GROUP_TAG = 'LBF'

local COLOR_COMPONENTS = { 'r', 'g', 'b' }

-- Slider styles matching Factorio's own player-color picker.
local COLOR_SLIDER_STYLE = { r = 'red_slider', g = 'green_slider', b = 'blue_slider' }

local TOP_SECTIONS = { 'feed', 'collect', 'appearance', 'reserves' }

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
--- @param sprite string family icon shown in the section header
--- @return LuaGuiElement body flow to add section content into
local function add_section(content, id, sprite, caption, tooltip)
    local _, body = GuiUtil.add_family_section(content, id, sprite, caption, { lbf_action = 'toggle-section', section = id }, tooltip)
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

-- Behavior/appearance flag ids carry a family prefix (feed_/collect_/
-- appearance_ — see state.lua's TREE_DEF; also the public remote-API flag
-- names). Locale keys predate that prefix, so strip it back off before
-- building 'lbf-gui.flag-<...>' — e.g. 'feed_fuel' -> 'lbf-gui.flag-fuel'.
local FAMILY_PREFIXES = { 'feed_', 'collect_', 'appearance_' }

--- @param id string tree node id
--- @return string unprefixed locale-key suffix
local function locale_suffix(id)
    for _, prefix in pairs(FAMILY_PREFIXES) do
        if id:sub(1, #prefix) == prefix then
            return id:sub(#prefix + 1)
        end
    end
    return id
end

-- Sprite suffix for each child flag's 'lbf-flag-<suffix>' icon (tools/
-- make_flag_icons.py). Independent of locale_suffix's family-prefix
-- stripping — some flags need a different (shorter/hyphenated) suffix than
-- their locale key, e.g. appearance_show_others_area -> 'show-others', not
-- 'show_others_area'. Channels aren't listed here: they're rendered as an
-- add_channel_switch, not a sprite-button.
local FLAG_SPRITE_SUFFIX = {
    feed_fuel = 'fuel',
    feed_ingredients = 'ingredients',
    combat = 'combat',
    feed_trash = 'trash',
    feed_rebalance = 'rebalance',
    collect_chests = 'chests',
    collect_ground = 'ground',
    appearance_show_others_area = 'show-others',
    appearance_starvation = 'starvation',
}

-- 'appearance' (formerly 'appearance_fill')/'appearance_show_others_area'
-- predate the settings tree and keep their own locale keys (built alongside
-- their sliders/extra tooltips) rather than the generic 'channel-'/
-- 'flag-<suffix>' patterns.
local CAPTION_OVERRIDE = {
    appearance = 'lbf-gui.fill',
    appearance_show_others_area = 'lbf-gui.show-others',
}
local TOOLTIP_OVERRIDE = {
    appearance = 'lbf-gui.fill-tooltip',
    appearance_show_others_area = 'lbf-gui.show-others-tooltip',
}

--- Builds a tooltip in the admin-open panel's format (relative.lua's
--- 'lbf-admin-open' button): a bold/tinted title line, then the description,
--- with a warning appended as a third, alert-prefixed line when disabled.
--- Composed at runtime rather than baked into locale.cfg so the plain
--- caption/tooltip keys stay reusable elsewhere (e.g. [mod-setting-name]
--- reuses the same concepts unwrapped).
--- @param title_key string locale key for the title half
--- @param desc_key string locale key for the description half
--- @param locked_reason string? 'global'|'allowed'|'parent'|nil — 'global'/'allowed' from
---   State.tree:admin_blocked, 'parent' when a switch above this one (own preference, not
---   admin) is off — see ancestor_effective.
--- @return LocalisedString
local function flag_tooltip(title_key, desc_key, locked_reason)
    local tooltip = { '', '[font=var][color=1,0.9,0.75]', { title_key }, '[/color][/font]', '\n', { desc_key } }
    if locked_reason then
        local warning = locked_reason == 'global' and { 'lbf-gui.master-off' }
            or locked_reason == 'allowed' and { 'lbf-gui.locked-by-admin' }
            or { 'lbf-gui.channel-off' }
        tooltip = { '', tooltip, '\n', '[img=lbf-alert-warning] ', warning }
    end
    return tooltip
end

-- Area-shape button (relative.lua's lbf-shape): cycles circle/square rather
-- than a drop-down, matching the rest of the panel's icon-button look.
local SHAPE_SPRITE = { circle = 'lbf-flag-circle', square = 'lbf-flag-square' }

--- Tooltip for the shape button: title, then "Selected: <type>" (its own
--- distinct formatting, not plain text, per the flag-button title styling
--- above), then the plain description, plus the same parent-off warning
--- line as flag_tooltip when the appearance channel above it is off — shape
--- is never admin-gated, but it is still a child of 'appearance' and greys
--- with it (2026-07-17).
--- @param shape 'circle'|'square'
--- @param locked boolean? true when the appearance channel above it is off
--- @return LocalisedString
local function shape_tooltip(shape, locked)
    local type_key = shape == 'square' and 'lbf-gui.shape-square' or 'lbf-gui.shape-circle'
    local tooltip = {
        '', '[font=var][color=1,0.9,0.75]', { 'lbf-gui.shape' }, '[/color][/font]', '\n',
        '[font=default-semibold]', { 'lbf-gui.shape-selected', { type_key } }, '[/font]', '\n',
        { 'lbf-gui.shape-tooltip' },
    }
    if locked then
        tooltip = { '', tooltip, '\n', '[img=lbf-alert-warning] ', { 'lbf-gui.channel-off' } }
    end
    return tooltip
end

--- Whether `id`'s immediate parent (and transitively, everything above it) is
--- currently fully effective for this player — i.e. every switch from the
--- root down to (and including) the parent is on, both admin-side and the
--- player's own preference. A flag button's own clickability follows this
--- (DESIGN.md §2, revised): turning off a channel/master switch greys out
--- its children. Channel switches are themselves children of the top-level
--- mod switch, so this also greys them when the player's own master is off
--- (2026-07-17) — only the root mod switch never greys itself, since it has
--- no parent to be gated by.
--- @param player_index uint
--- @param id string tree node id
--- @return boolean
local function ancestor_effective(player_index, id)
    local parent = State.tree:node(id).parent
    return parent == nil or State.effective(player_index, parent.id)
end

--- The master On/Off switch for one family/channel (feed, collect,
--- appearance) — same widget as the top player-master switch, just tagged
--- with the channel id so the dispatcher/sync can target it.
--- @param parent LuaGuiElement
--- @param id string channel tree node id
--- @return LuaGuiElement
local function add_channel_switch(parent, id)
    return parent.add({
        type = 'switch',
        name = 'lbf-setting-' .. id,
        switch_state = 'right',
        left_label_caption = { 'lbf-gui.switch-off' },
        right_label_caption = { 'lbf-gui.switch-on' },
        tags = { lbf_action = 'toggle-channel', id = id },
    })
end

--- @param switch LuaGuiElement
--- @param data LbfPlayerData
--- @param id string channel tree node id
--- @param player_index uint
local function sync_channel_switch(switch, data, id, player_index)
    local enabled = data.settings[id].enabled
    switch.switch_state = enabled and 'right' or 'left'
    local _, reason = State.tree:admin_blocked(storage.settings, data.settings, id)
    if not reason and not ancestor_effective(player_index, id) then
        reason = 'parent'
    end
    switch.enabled = reason == nil
    local title_key = CAPTION_OVERRIDE[id] or ('lbf-gui.channel-' .. locale_suffix(id))
    local desc_key = TOOLTIP_OVERRIDE[id] or ('lbf-gui.channel-' .. locale_suffix(id) .. '-tooltip')
    switch.tooltip = flag_tooltip(title_key, desc_key, reason)
end

--- A vanilla shortcut_bar_inner_panel (no outer shortcut_bar_window_frame) to
--- hold a row of shortcut_bar_button flag buttons, matching the look of
--- Factorio's own shortcut bar.
--- @param parent LuaGuiElement
--- @param name string element name for the panel
--- @return LuaGuiElement panel add shortcut_bar_button children into this
local function add_shortcut_panel(parent, name)
    return parent.add({ type = 'frame', name = name .. '-panel', style = 'shortcut_bar_inner_panel', direction = 'horizontal' })
end

--- One sprite-button per settings-tree flag id, styled as a vanilla
--- shortcut-bar button (yellow highlight when toggled on, 40px). Sync fills
--- in `.toggled`/`.enabled`/`.tooltip`.
--- @param parent LuaGuiElement
--- @param id string tree node id
--- @return LuaGuiElement
local function add_flag_button(parent, id)
    return parent.add({
        type = 'sprite-button',
        name = 'lbf-setting-' .. id,
        style = 'shortcut_bar_button',
        sprite = 'lbf-flag-' .. FLAG_SPRITE_SUFFIX[id],
        tags = { lbf_action = 'toggle-setting', id = id },
    })
end

--- Sync for a settings-tree flag's sprite-button: toggled (yellow highlight)
--- follows data.settings[id].enabled, greyed out with a warning-prefixed
--- tooltip when an admin-side control (global switch or lock, anywhere from
--- the root down to this node) blocks it, or when a switch above this one is
--- off — either the channel's own master or the player's own top-level
--- master (DESIGN.md §2, revised: switches always stay clickable themselves,
--- but now do grey their children).
--- @param button LuaGuiElement
--- @param data LbfPlayerData
--- @param id string tree node id
--- @param player_index uint
local function sync_flag_button(button, data, id, player_index)
    button.toggled = data.settings[id].enabled
    local _, reason = State.tree:admin_blocked(storage.settings, data.settings, id)
    if not reason and not ancestor_effective(player_index, id) then
        reason = 'parent'
    end
    button.enabled = reason == nil
    local title_key = CAPTION_OVERRIDE[id] or ('lbf-gui.flag-' .. locale_suffix(id))
    local desc_key = TOOLTIP_OVERRIDE[id] or ('lbf-gui.flag-' .. locale_suffix(id) .. '-tooltip')
    button.tooltip = flag_tooltip(title_key, desc_key, reason)
end

--- Sprite-button + tooltip for a plain (non-tree, never admin-locked)
--- preference toggle — use-player-color and the flying-text summary today.
--- Same vanilla shortcut-bar look/size as add_flag_button. Tooltip's title/desc
--- keys are stashed in tags so sync_plain_flag_button can rebuild the tooltip
--- (with the parent-off warning line) without the caller having to repeat them.
--- @param parent LuaGuiElement
--- @param name string element name
--- @param action string tags.lbf_action
--- @param sprite string
--- @param title_key string
--- @param desc_key string
--- @return LuaGuiElement
local function add_plain_flag_button(parent, name, action, sprite, title_key, desc_key)
    local button = parent.add({
        type = 'sprite-button',
        name = name,
        style = 'shortcut_bar_button',
        sprite = sprite,
        tags = { lbf_action = action, title_key = title_key, desc_key = desc_key },
    })
    button.tooltip = flag_tooltip(title_key, desc_key)
    return button
end

--- These are children of 'appearance' too (not tree nodes, so never
--- admin-locked), so they still grey and warn when the channel above them is
--- off (2026-07-17) — same rule as the tree-backed flag buttons.
--- @param button LuaGuiElement
--- @param on boolean
--- @param locked boolean? true when the appearance channel above it is off
local function sync_plain_flag_button(button, on, locked)
    button.toggled = on
    button.tooltip = flag_tooltip(button.tags.title_key --[[@as string]], button.tags.desc_key --[[@as string]], locked and 'parent' or nil)
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
        close_tooltip = { 'lbf-gui.close-tooltip' },
        draggable = false,
    })
    local content = frame.add({ type = 'flow', name = 'content', direction = 'vertical' })

    -- Decorative wordmark strip; pushers center it, and it must never
    -- intercept clicks (no tags, ignored_by_interaction).
    if SHOW_BANNER then
        local banner_row = content.add({ type = 'flow', name = 'banner-row', direction = 'horizontal' })
        GuiUtil.add_pusher(banner_row)
        banner_row.add({ type = 'sprite', name = 'banner', sprite = 'lbf-banner', style = 'lbf_banner_image', ignored_by_interaction = true })
        GuiUtil.add_pusher(banner_row)
    end

    local _, master_body = GuiUtil.add_family_section(content, 'master')
    local master_flow = master_body.add({ type = 'flow', name = 'master-flow', direction = 'horizontal', style = 'lbf_row_flow' })
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

    for _, group in pairs(BEHAVIOR_GROUPS) do
        local body = add_section(content, group.id, 'lbf-family-' .. group.channel, { 'lbf-gui.channel-' .. group.channel })
        local row = body.add({ type = 'flow', name = 'row', direction = 'horizontal', style = 'lbf_icon_row_flow' })
        add_channel_switch(row, group.channel)
        row.add({ type = 'line', name = 'separator', direction = 'vertical', style = 'lbf_row_separator_line' })
        local panel = add_shortcut_panel(row, 'shortcut')
        for _, id in pairs(group.flags) do
            add_flag_button(panel, id)
        end
    end

    local appearance_body = add_section(content, 'appearance', 'lbf-family-appearance', { 'lbf-gui.appearance' })

    -- Same left/right split as Feed/Collect: the channel's own master switch
    -- on the left, a vertical divider, then everything it gates stacked
    -- vertically on the right (radius, opacity, then a strip of five buttons
    -- — shape plus the four toggles).
    local appearance_row = appearance_body.add({ type = 'table', name = 'row', column_count = 3, style = 'lbf_appearance_row_table' })
    add_channel_switch(appearance_row, 'appearance')
    appearance_row.add({ type = 'line', name = 'separator', direction = 'vertical', style = 'lbf_row_separator_line_stretch' })
    local appearance_settings = appearance_row.add({ type = 'flow', name = 'settings', direction = 'vertical' })

    local sliders_table = appearance_settings.add({ type = 'table', name = 'sliders-table', column_count = 2, style = 'lbf_appearance_sliders_table' })
    sliders_table.add({ type = 'label', name = 'radius-label', caption = { 'lbf-gui.radius' }, tooltip = { 'lbf-gui.radius-tooltip' } })
    sliders_table.add({
        type = 'slider',
        name = 'lbf-radius-slider',
        style = 'lbf_appearance_slider',
        minimum_value = 1,
        maximum_value = 100,
        value = 16,
        value_step = 1,
        tooltip = '16',
        tags = { lbf_action = 'radius-slider' },
    })

    sliders_table.add({ type = 'label', name = 'opacity-label', caption = { 'lbf-gui.opacity' }, tooltip = { 'lbf-gui.opacity-tooltip' } })
    sliders_table.add({
        type = 'slider',
        name = 'lbf-opacity',
        style = 'lbf_appearance_slider',
        minimum_value = 0,
        maximum_value = 100,
        value = 8,
        value_step = 1,
        tooltip = '8%',
        tags = { lbf_action = 'opacity' },
    })

    -- The five Appearance toggles as one strip: shape cycles circle/square;
    -- use-player-color and summary are plain per-player prefs
    -- (add_plain_flag_button); show-others and starvation are tree children
    -- of 'appearance' (add_flag_button), admin-lockable independently.
    local flags_row = appearance_settings.add({ type = 'flow', name = 'flags-row', direction = 'horizontal' })
    local flags_panel = add_shortcut_panel(flags_row, 'shortcut')
    flags_panel.add({
        type = 'sprite-button',
        name = 'lbf-shape',
        style = 'shortcut_bar_button',
        sprite = SHAPE_SPRITE.circle,
        tags = { lbf_action = 'shape' },
    })
    add_plain_flag_button(
        flags_panel, 'lbf-use-player-color', 'use-player-color', 'lbf-flag-use-player-color',
        'lbf-gui.flag-use-player-color', 'lbf-gui.flag-use-player-color-tooltip'
    )
    add_flag_button(flags_panel, 'appearance_show_others_area')
    add_flag_button(flags_panel, 'appearance_starvation')
    -- Not a tree node: nothing gates the flying-text summary, it's a plain
    -- per-player preference (DESIGN.md §12).
    add_plain_flag_button(
        flags_panel, 'lbf-summary', 'toggle-summary', 'lbf-flag-summary',
        'lbf-gui.flag-summary', 'lbf-gui.flag-summary-tooltip'
    )

    local color_flow = appearance_body.add({
        type = 'frame',
        name = 'color-flow',
        style = 'lbf_color_frame',
        caption = { 'lbf-gui.color-frame' },
        direction = 'vertical',
    })
    for _, component in pairs(COLOR_COMPONENTS) do
        local row = color_flow.add({ type = 'flow', name = 'row-' .. component, direction = 'horizontal', style = 'lbf_color_row_flow' })
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

    local reserves_body =
        add_section(content, 'reserves', 'lbf-family-filters', { 'lbf-gui.reserves' }, { 'lbf-gui.reserves-tooltip' })

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

    -- Inline set-reserve editor, always visible below the grid (never a
    -- separate window — that would fight the character screen for focus).
    -- Empty picker = "add a new item"; the amount widgets stay disabled
    -- until an item is picked. Pushers on both sides center it, matching
    -- the reserves grid above.
    local editor_row = reserves_body.add({ type = 'flow', name = 'reserve-editor-row', direction = 'horizontal' })
    GuiUtil.add_pusher(editor_row)
    local editor = editor_row.add({
        type = 'flow',
        name = 'reserve-editor',
        direction = 'horizontal',
        style = 'lbf_row_flow',
    })
    editor.add({
        type = 'choose-elem-button',
        name = 'lbf-reserve-elem',
        style = 'lbf_reserve_elem_button',
        elem_type = 'item',
        tooltip = { '', { 'lbf-gui.reserve-add' }, '\n', { 'lbf-gui.reserve-add-tooltip' } },
        tags = { lbf_action = 'reserve-editor-elem' },
    })
    editor.add({
        type = 'textfield',
        name = 'lbf-reserve-count',
        style = 'slider_value_textfield',
        numeric = true,
        allow_decimal = false,
        allow_negative = false,
        enabled = false,
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
        enabled = false,
        tooltip = { 'lbf-gui.reserve-count-tooltip' },
        tags = { lbf_action = 'reserve-editor-slider' },
    })
    editor.add({
        type = 'sprite-button',
        name = 'lbf-reserve-confirm',
        style = 'item_and_count_select_confirm',
        sprite = 'utility/check_mark',
        enabled = false,
        tags = { lbf_action = 'reserve-editor-confirm' },
    })
    GuiUtil.add_pusher(editor_row)

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
    if #children ~= total then
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

--- One slot per reserved item (count on the number badge). New items are
--- added through the always-visible set-reserve editor row below the grid;
--- left-click loads a slot into that row for editing, right-click removes it.
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
end

--- The inline set-reserve editor row of the reserves section, or nil when the
--- panel is collapsed to the open button.
--- @param player LuaPlayer
--- @return LuaGuiElement?
local function get_reserve_editor(player)
    local frame = get_frame(player)
    local content = frame and frame.type == 'frame' and frame.content
    return content and section_frame(content, 'reserves')['body-frame'].body['reserve-editor'] or nil
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

--- Back to the empty "add a new item" state: picker cleared, amount widgets
--- disabled, no slot being edited.
--- @param editor LuaGuiElement
local function reset_reserve_editor(editor)
    editor.tags = {}
    editor['lbf-reserve-elem'].elem_value = nil
    sync_editor_count(editor, nil)
end

--- Load an existing slot's `item` into the editor row for editing. The slot
--- it came from is kept in the row's tags so confirming with a different
--- item replaces it.
--- @param player LuaPlayer
--- @param data LbfPlayerData
--- @param item string
local function open_reserve_editor(player, data, item)
    local editor = get_reserve_editor(player)
    if not editor then
        return
    end
    editor.tags = { item = item }
    editor['lbf-reserve-elem'].elem_value = item
    sync_editor_count(editor, item, data.reserves[item] or prototypes.item[item].stack_size)
end

--- Apply the editor: write the picked item/amount into reserves (replacing the
--- edited item if the picker changed; amount 0 clears it) and reset the row
--- to its empty state.
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
    reset_reserve_editor(editor)
    State.refresh(player)
end

--- Push storage state into the panel: master switch, flag-button states,
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
    local master_flow = section_frame(content, 'master')['body-frame'].body['master-flow']
    local master_switch = master_flow['lbf-master']
    local _, master_blocked_reason = State.tree:admin_blocked(storage.settings, data.settings, 'mod')
    local mod = data.settings.mod
    master_switch.switch_state = mod.enabled and 'right' or 'left'
    master_switch.enabled = master_blocked_reason == nil
    master_switch.tooltip = master_blocked_reason == nil and { 'lbf-gui.master-switch-tooltip' }
        or master_blocked_reason == 'global' and { 'lbf-gui.master-off' }
        or { 'lbf-gui.locked-by-admin' }

    for _, id in pairs(TOP_SECTIONS) do
        local section = section_frame(content, id)
        local expanded = data.ui.sections[id]
        section['header-flow']['arrow'].sprite = expanded and 'utility/collapse' or 'utility/expand'
        section['body-frame'].visible = expanded
    end

    local collect_panel
    for _, group in pairs(BEHAVIOR_GROUPS) do
        local row = section_frame(content, group.id)['body-frame'].body.row
        sync_channel_switch(row['lbf-setting-' .. group.channel], data, group.channel, player.index)
        local panel = row['shortcut-panel']
        for _, id in pairs(group.flags) do
            sync_flag_button(panel['lbf-setting-' .. id], data, id, player.index)
        end
        if group.id == 'collect' then
            collect_panel = panel
        end
    end
    if settings.global['lbf-allow-chest-collect'].value ~= true then
        local chests = collect_panel['lbf-setting-collect_chests']
        chests.enabled = false
        chests.tooltip = flag_tooltip('lbf-gui.flag-chests', 'lbf-gui.flag-chests-forbidden')
    end

    master_flow['lbf-admin-open'].visible = player.admin

    local appearance_body = section_frame(content, 'appearance')['body-frame'].body
    local appearance_row = appearance_body.row
    sync_channel_switch(appearance_row['lbf-setting-appearance'], data, 'appearance', player.index)
    local appearance_settings = appearance_row.settings
    -- Same rule as the flag buttons: the switch itself greys when the
    -- master above it is off (sync_channel_switch), and everything it gates
    -- (radius, opacity, and the five buttons below) follows the full
    -- effective state (own preference + every ancestor + admin).
    local appearance_effective = State.effective(player.index, 'appearance')

    -- Radius/opacity are children of 'appearance' too, so their labels and
    -- sliders grey and warn like the rest when the channel above them is off
    -- (2026-07-17).
    local appearance_locked_reason = (not appearance_effective) and 'parent' or nil

    local sliders_table = appearance_settings['sliders-table']

    local radius = State.get_radius(player.index)
    local slider = sliders_table['lbf-radius-slider']
    slider.set_slider_minimum_maximum(settings.global['lbf-min-radius'].value --[[@as number]], settings.global['lbf-max-radius'].value --[[@as number]])
    slider.slider_value = radius
    slider.enabled = appearance_effective
    slider.tooltip = tostring(radius)
    sliders_table['radius-label'].tooltip = flag_tooltip('lbf-gui.radius', 'lbf-gui.radius-tooltip', appearance_locked_reason)

    local opacity_percent = math.floor(data.opacity * 100 + 0.5)
    sliders_table['lbf-opacity'].slider_value = opacity_percent
    sliders_table['lbf-opacity'].enabled = appearance_effective
    sliders_table['lbf-opacity'].tooltip = opacity_percent .. '%'
    sliders_table['opacity-label'].tooltip = flag_tooltip('lbf-gui.opacity', 'lbf-gui.opacity-tooltip', appearance_locked_reason)

    local flags_panel = appearance_settings['flags-row']['shortcut-panel']
    local shape_button = flags_panel['lbf-shape']
    shape_button.sprite = SHAPE_SPRITE[data.shape]
    shape_button.tooltip = shape_tooltip(data.shape, not appearance_effective)
    shape_button.enabled = appearance_effective
    sync_plain_flag_button(flags_panel['lbf-use-player-color'], data.use_player_color, not appearance_effective)
    flags_panel['lbf-use-player-color'].enabled = appearance_effective
    sync_flag_button(flags_panel['lbf-setting-appearance_show_others_area'], data, 'appearance_show_others_area', player.index)
    sync_flag_button(flags_panel['lbf-setting-appearance_starvation'], data, 'appearance_starvation', player.index)
    sync_plain_flag_button(flags_panel['lbf-summary'], data.summary_enabled, not appearance_effective)
    flags_panel['lbf-summary'].enabled = appearance_effective

    local color_flow = appearance_body['color-flow']
    color_flow.visible = not data.use_player_color
    for _, component in pairs(COLOR_COMPONENTS) do
        local row = color_flow['row-' .. component]
        local value = math.floor((data.color[component] or 0) * 255 + 0.5)
        row['lbf-color-' .. component].slider_value = value
        row['lbf-color-' .. component].enabled = appearance_effective
        row['lbf-color-value-' .. component].text = tostring(value)
        row['lbf-color-value-' .. component].enabled = appearance_effective
    end

    sync_reserves(section_frame(content, 'reserves')['body-frame'].body['reserves-pane-row']['reserves-pane']['lbf-reserves'], data.reserves)
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

--- One dispatcher for every panel element, keyed on tags.lbf_action.
--- GuiUtil.new_dispatcher asserts each action is only registered once, so a
--- copy-pasted `on_action` can't silently shadow an earlier handler.
local on_action, dispatch_action = GuiUtil.new_dispatcher('lbf_action')

on_action('toggle-panel', function(_, _, _, player)
    local data = State.get_player_data(player.index)
    data.ui.open = not data.ui.open
    Gui.build(player)
end)

on_action('toggle-section', function(_, _, tags, player)
    local data = State.get_player_data(player.index)
    local section = tags.section --[[@as string]]
    data.ui.sections[section] = not data.ui.sections[section]
    Gui.sync(player)
end)

on_action('master-switch', function(_, element, _, player)
    State.set_player_master(player, element.switch_state == 'right')
    State.refresh(player)
end)

on_action('toggle-channel', function(_, element, tags, player)
    local id = tags.id --[[@as string]]
    State.set_enabled(player, id, element.switch_state == 'right')
    State.refresh(player)
end)

on_action('toggle-setting', function(_, _, tags, player)
    local id = tags.id --[[@as string]]
    local data = State.get_player_data(player.index)
    -- Sprite-buttons carry no boolean on the click event (unlike a
    -- checkbox's element.state) — flip the currently stored value instead.
    State.set_enabled(player, id, not data.settings[id].enabled)
    if id == 'appearance_show_others_area' then
        -- Viewer-opt-in (§12): this toggle changes what *other* owners'
        -- renders show this player, not this player's own area.
        State.refresh_all()
    else
        State.refresh(player)
    end
end)

on_action('toggle-summary', function(_, _, _, player)
    local data = State.get_player_data(player.index)
    data.summary_enabled = not data.summary_enabled
    State.push_setting(player, 'lbf-show-summary')
    State.refresh(player)
end)

on_action('radius-slider', function(_, element, _, player)
    State.set_radius(player, element.slider_value)
    State.refresh(player)
end)

on_action('shape', function(_, _, _, player)
    local data = State.get_player_data(player.index)
    data.shape = data.shape == 'square' and 'circle' or 'square'
    State.push_setting(player, 'lbf-shape')
    State.refresh(player)
end)

on_action('opacity', function(_, element, _, player)
    local data = State.get_player_data(player.index)
    data.opacity = element.slider_value / 100
    State.push_setting(player, 'lbf-opacity')
    State.refresh(player)
end)

on_action('use-player-color', function(_, _, _, player)
    local data = State.get_player_data(player.index)
    data.use_player_color = not data.use_player_color
    State.push_setting(player, 'lbf-use-my-color')
    State.refresh(player)
end)

on_action('color', function(_, element, tags, player)
    local data = State.get_player_data(player.index)
    local component = tags.component --[[@as string]]
    data.color[component] = element.slider_value / 255
    data.color.a = 1
    State.push_setting(player, 'lbf-color')
    State.refresh(player)
end)

on_action('color-text', function(_, element, tags, player)
    local value = tonumber(element.text)
    if not (value and value >= 0 and value <= 255) then
        return
    end
    local data = State.get_player_data(player.index)
    local component = tags.component --[[@as string]]
    data.color[component] = value / 255
    data.color.a = 1
    State.push_setting(player, 'lbf-color')
    State.refresh(player)
end)

on_action('reserve-slot', function(event, _, tags, player)
    local data = State.get_player_data(player.index)
    local item = tags.item --[[@as string]]
    if event.button == defines.mouse_button_type.right then
        data.reserves[item] = nil
        local editor = get_reserve_editor(player)
        if editor and editor.tags.item == item then
            reset_reserve_editor(editor) -- it was editing the removed item
        end
        State.refresh(player)
    else
        open_reserve_editor(player, data, item)
    end
end)

on_action('reserve-editor-elem', function(event, element, _, player)
    -- The picker button also receives plain clicks; only react to the pick.
    if event.name ~= defines.events.on_gui_elem_changed then
        return
    end
    local data = State.get_player_data(player.index)
    local item = element.elem_value --[[@as string?]]
    sync_editor_count(element.parent, item, item and (data.reserves[item] or prototypes.item[item].stack_size))
end)

on_action('reserve-editor-slider', function(_, element)
    element.parent['lbf-reserve-count'].text = tostring(element.slider_value)
end)

on_action('reserve-editor-count', function(event, element, _, player)
    local data = State.get_player_data(player.index)
    if event.name == defines.events.on_gui_confirmed then
        confirm_reserve_editor(player, data, element.parent)
    else
        -- Mid-typing: follow with the slider (clamped), never touch the text.
        element.parent['lbf-reserve-slider'].slider_value = tonumber(element.text) or 0
    end
end)

on_action('reserve-editor-confirm', function(_, element, _, player)
    local data = State.get_player_data(player.index)
    confirm_reserve_editor(player, data, element.parent)
end)

on_action('reserve-import', function(_, _, _, player)
    local data = State.get_player_data(player.index)
    import_reserves(player, data)
    State.refresh(player)
end)

--- @param event EventData.on_gui_checked_state_changed|EventData.on_gui_value_changed|EventData.on_gui_click|EventData.on_gui_elem_changed|EventData.on_gui_text_changed|EventData.on_gui_selection_state_changed|EventData.on_gui_switch_state_changed|EventData.on_gui_confirmed
function Gui.dispatch(event)
    dispatch_action(event)
end

return Gui
