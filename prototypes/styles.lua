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

styles.lbf_relative_frame = {
    type = 'frame_style',
    parent = 'frame',
    natural_width = 300,
}

-- Advanced-options list nested under a behavior row.
styles.lbf_indented_flow = {
    type = 'vertical_flow_style',
    left_padding = 16,
    vertical_spacing = 4,
}

-- Reserve grid cells (one per reserved item).
styles.lbf_reserve_sprite = {
    type = 'image_style',
    size = 28,
    stretch_image_to_widget_size = true,
}

styles.lbf_reserve_textfield = {
    type = 'textbox_style',
    width = 60,
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
