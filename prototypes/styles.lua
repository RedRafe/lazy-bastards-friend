--- Style prototypes backing the runtime GUIs (scripts/lib/gui.lua,
--- scripts/gui/*, scripts/tests/lib/gui.lua). Anything used in more than one
--- place, or created inside a loop, gets a named style here so runtime code
--- just references it; genuine one-off tweaks (a single padding on a single
--- element, dynamic per-player colors) stay as runtime set_style calls.

local styles = data.raw['gui-style'].default

-- Shared building blocks (scripts/lib/gui.lua) -------------------------------

-- Stretching spacer (GuiUtil.add_pusher).
styles.lbf_pusher = {
    type = 'empty_widget_style',
    horizontally_stretchable = 'on',
}

-- Titlebar drag handle for screen-anchored frames (GuiUtil.add_titlebar).
styles.lbf_drag_handle = {
    type = 'empty_widget_style',
    parent = 'draggable_space_header',
    horizontally_stretchable = 'on',
    height = 24,
}

-- Section header frame + its inner flow (GuiUtil.add_collapsible, test panel sections).
styles.lbf_subheader_frame = {
    type = 'frame_style',
    parent = 'subheader_frame',
    horizontally_stretchable = 'on',
}

styles.lbf_subheader_flow = {
    type = 'horizontal_flow_style',
    vertical_align = 'center',
    horizontally_stretchable = 'on',
}

-- Padded vertical flow a collapsible section's content lives in.
styles.lbf_section_body_flow = {
    type = 'vertical_flow_style',
    padding = 8,
    vertical_spacing = 4,
}

-- Label + control on one line, vertically centered — the workhorse row flow.
styles.lbf_row_flow = {
    type = 'horizontal_flow_style',
    vertical_align = 'center',
}

-- Relative panel (scripts/gui/relative.lua) ----------------------------------

-- The collapsed panel: a single blue icon button.
styles.lbf_open_button = {
    type = 'button_style',
    parent = 'shortcut_bar_button_blue',
    size = 32,
}

-- 308 = width the reserve editor row pushes the panel to (with the 28px elem
-- button below), so opening the editor doesn't resize the frame.
-- Wordmark banner at the top of the open panel.
styles.lbf_banner_image = {
    type = 'image_style',
    top_margin = 8,
    bottom_margin = 4,
}

styles.lbf_relative_frame = {
    type = 'frame_style',
    parent = 'frame',
    natural_width = 308,
}

-- Advanced-options list nested under a behavior row.
styles.lbf_indented_flow = {
    type = 'vertical_flow_style',
    left_padding = 16,
    vertical_spacing = 4,
}

-- Reserved-items slot grid: vanilla dark tiled-slots background, scrolls past 4 rows.
styles.lbf_reserves_scroll_pane = {
    type = 'scroll_pane_style',
    parent = 'deep_slots_scroll_pane',
    maximal_height = 160, -- 4 rows of 40px slots
}

-- Import bar closing the reserved-items section, shaped like the map
-- generator's "Map exchange string" subfooter. Negative margins cancel the
-- section body's 8px padding so the bar runs flush to the section edges.
styles.lbf_reserves_footer_frame = {
    type = 'frame_style',
    parent = 'subfooter_frame',
    horizontally_stretchable = 'on',
    left_margin = -8,
    right_margin = -8,
    bottom_margin = -8,
}

-- Item picker of the inline set-reserve editor; shrunk from the 40px slot
-- default to match the 28px-tall slider/textfield row and save panel width.
styles.lbf_reserve_elem_button = {
    type = 'button_style',
    parent = 'slot_button_in_shallow_frame',
    size = 28,
}

-- Amount slider of the inline set-reserve editor; narrowed so the whole
-- [elem|amount|slider|confirm] row fits the panel's natural width.
styles.lbf_reserve_slider = {
    type = 'slider_style',
    parent = 'notched_slider',
    width = 120,
}

-- Test results panel (scripts/tests/lib/gui.lua) ------------------------------

-- Pending/Passed/Failed count tile (number color stays runtime — per tile).
styles.lbf_stat_tile_frame = {
    type = 'frame_style',
    parent = 'bordered_frame',
    padding = 4,
    horizontally_stretchable = 'on',
    horizontal_align = 'center',
}

styles.lbf_large_bold_label = {
    type = 'label_style',
    font = 'default-large-bold',
}

styles.lbf_muted_label = {
    type = 'label_style',
    font_color = { 170, 170, 170 },
}

-- Wrapping labels created per instruction / per check row.
styles.lbf_instruction_label = {
    type = 'label_style',
    single_line = false,
    maximal_width = 380,
}

styles.lbf_check_label = {
    type = 'label_style',
    single_line = false,
    maximal_width = 280,
}

-- Closing banner: same shape in three tones, so finishing a suite is a pure
-- style-name swap at runtime.
for _, tone in pairs({ 'neutral', 'positive', 'negative' }) do
    styles['lbf_' .. tone .. '_message_frame'] = {
        type = 'frame_style',
        parent = tone .. '_message_frame',
        horizontally_stretchable = 'on',
        horizontal_align = 'center',
        padding = 8,
    }
end
