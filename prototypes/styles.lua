local styles = data.raw['gui-style'].default

-- Shared building blocks (scripts/lib/gui.lua) -------------------------------

styles.lbf_pusher = {
    type = 'empty_widget_style',
    horizontally_stretchable = 'on',
}

styles.lbf_drag_handle = {
    type = 'empty_widget_style',
    parent = 'draggable_space_header',
    horizontally_stretchable = 'on',
    height = 24,
}

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

styles.lbf_section_body_flow = {
    type = 'vertical_flow_style',
    padding = 8,
    vertical_spacing = 6,
}

styles.lbf_row_flow = {
    type = 'horizontal_flow_style',
    vertical_align = 'center',
}

-- Relative panel (scripts/gui/relative.lua) ----------------------------------

styles.lbf_open_button = {
    type = 'button_style',
    parent = 'shortcut_bar_button_blue',
    size = 32,
}

styles.lbf_banner_image = {
    type = 'image_style',
    top_margin = 8,
    bottom_margin = 4,
}

styles.lbf_relative_frame = {
    type = 'frame_style',
    parent = 'frame',
    natural_width = 328,
    vertically_stretchable = 'off',
}

styles.lbf_color_frame = {
    type = 'frame_style',
    parent = 'bordered_frame',
    horizontally_stretchable = 'on',
    horizontal_align = 'center',
}

styles.lbf_color_row_flow = {
    type = 'horizontal_flow_style',
    parent = 'lbf_row_flow',
    horizontally_stretchable = 'on',
    horizontal_align = 'center',
}

styles.lbf_indented_flow = {
    type = 'vertical_flow_style',
    left_padding = 16,
    vertical_spacing = 4,
}

styles.lbf_section_flow = {
    type = 'vertical_flow_style',
    horizontally_stretchable = 'on',
    top_margin = 4,
}

styles.lbf_section_header_flow = {
    type = 'horizontal_flow_style',
    vertical_align = 'center',
    horizontal_spacing = 6,
}

styles.lbf_section_icon_button = {
    type = 'button_style',
    parent = 'transparent_slot',
    size = 24,
}

-- Collapse/expand arrow — same transparent look as the icon, left un-tinted.
styles.lbf_section_arrow_button = {
    type = 'button_style',
    parent = 'transparent_slot',
    size = 24,
}

styles.lbf_section_caption_label = {
    type = 'label_style',
    font = 'default-bold',
    font_color = { 255, 255, 255 },
}

styles.lbf_section_header_line = {
    type = 'line_style',
    horizontally_stretchable = 'on',
}

styles.lbf_row_separator_line = {
    type = 'line_style',
    height = 40,
}

styles.lbf_row_separator_line_stretch = {
    type = 'line_style',
    minimal_height = 40,
    vertically_stretchable = 'on',
}

styles.lbf_appearance_row_table = {
    type = 'table_style',
    horizontal_spacing = 4,
    column_alignments = {
        { column = 1, alignment = 'middle-center' }, -- master switch
        { column = 2, alignment = 'middle-center' }, -- separator
        { column = 3, alignment = 'top-left' }, -- radius/opacity/flags settings
    },
}

styles.lbf_appearance_sliders_table = {
    type = 'table_style',
    vertical_spacing = 4,
    horizontal_spacing = 8,
    column_alignments = {
        { column = 1, alignment = 'middle-left' },
        { column = 2, alignment = 'middle-left' },
    },
}

styles.lbf_appearance_slider = {
    type = 'slider_style',
    parent = 'slider',
    minimal_width = 148,
}

styles.lbf_icon_row_flow = {
    type = 'horizontal_flow_style',
    vertical_align = 'center',
    horizontal_spacing = 4,
}

styles.lbf_reserves_scroll_pane = {
    type = 'scroll_pane_style',
    parent = 'deep_slots_scroll_pane',
    maximal_height = 160, -- 4 rows of 40px slots
}

styles.lbf_reserves_footer_frame = {
    type = 'frame_style',
    parent = 'subfooter_frame',
    horizontally_stretchable = 'on',
    left_margin = -8,
    right_margin = -8,
    bottom_margin = -8,
}

styles.lbf_reserve_elem_button = {
    type = 'button_style',
    parent = 'slot_button_in_shallow_frame',
    size = 28,
}

styles.lbf_reserve_slider = {
    type = 'slider_style',
    parent = 'notched_slider',
    width = 120,
}

-- Admin panel (scripts/gui/admin.lua) ----------------------------------------

styles.lbf_players_table = {
    type = 'table_style',
    parent = 'table_with_selection',
    horizontally_stretchable = 'on',
    column_alignments = {
        { column = 1, alignment = 'middle-left' }, -- name
        { column = 2, alignment = 'middle-center' }, -- on/off switch
        { column = 3, alignment = 'middle-center' }, -- feed lock
        { column = 4, alignment = 'middle-center' }, -- collect lock
        { column = 5, alignment = 'middle-center' }, -- appearance lock
    },
}

-- Test results panel (scripts/tests/lib/gui.lua) ------------------------------

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
