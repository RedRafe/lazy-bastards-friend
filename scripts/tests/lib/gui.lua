--- On-screen results panel for test-bench levels. Replaces the old chat-print
--- reporting (level tag/instructions, per-check PASS/FAIL, final tally) with a
--- single frame pinned to the top-left of the screen, kept in sync for every
--- connected player. Harness owns when things resolve; this module only knows
--- how to render whatever Harness/Bench hand it.
---
--- Layout mirrors RedMew's admin_panel/tasklist GUIs: a titlebar, then boxed
--- `inside_shallow_frame` sections with `subheader_frame` headers (Instructions,
--- Checks) rather than bare labels stacked in a column.

local GuiUtil = require('__lazy-bastards-friend__.scripts.lib.gui')

local set_style = GuiUtil.set_style

local Gui = {}

local FRAME_NAME = 'lbf-test-results'

--- @type { tag: string, lines: string[] }?
local header = nil
--- @type { name: string, status: boolean|'pending', extra: string? }[]
local rows = {}
--- @type { passed: integer, failed: integer }?
local finished = nil

--- @param status boolean|'pending'
--- @return string
local function status_caption(status)
    if status == 'pending' then
        return '[font=default-bold][color=170,170,170]…[/color][/font]'
    elseif status then
        return '[font=default-bold][color=120,220,80]PASS[/color][/font]'
    else
        return '[font=default-bold][color=220,80,80]FAIL[/color][/font]'
    end
end

--- @param frame LuaGuiElement
--- @param name string
--- @param caption LocalisedString
--- @return LuaGuiElement content frame of the new section
--- @return LuaGuiElement header flow, holding the title label and (once added by the caller) any trailing widgets
local function add_section(frame, name, caption)
    local inner = frame.add({ type = 'frame', name = name, style = 'inside_shallow_frame', direction = 'vertical' })
    local header = set_style(inner.add({ type = 'frame', name = 'lbf-header', style = 'subheader_frame' }), { horizontally_stretchable = true })
    local header_flow = set_style(header.add({ type = 'flow', name = 'lbf-header-flow', direction = 'horizontal' }), { horizontally_stretchable = true })
    header_flow.add({ type = 'label', caption = caption, style = 'subheader_caption_label' })
    return inner, header_flow
end

--- Small bordered tile showing a big colored number over a caption — used for
--- the live Pending/Passed/Failed counts instead of a single text line.
--- @param parent LuaGuiElement
--- @param name string
--- @param color Color
--- @param caption LocalisedString
--- @return LuaGuiElement
local function add_stat_tile(parent, name, color, caption)
    local tile = set_style(parent.add({ type = 'frame', name = name, style = 'bordered_frame', direction = 'vertical' }), {
        padding = 4,
        horizontally_stretchable = true,
        horizontal_align = 'center',
    })
    set_style(tile.add({ type = 'label', name = 'lbf-number', caption = '0' }), { font = 'default-large-bold', font_color = color })
    set_style(tile.add({ type = 'label', name = 'lbf-label', caption = caption }), { font_color = { 170, 170, 170 } })
    return tile
end

--- @param player LuaPlayer
--- @return LuaGuiElement
local function ensure_frame(player)
    local existing = player.gui.screen[FRAME_NAME]
    if existing then
        return existing
    end

    local frame = set_style(player.gui.screen.add({ type = 'frame', name = FRAME_NAME, direction = 'vertical' }), { width = 420 })
    frame.location = { x = 8, y = 8 }

    GuiUtil.add_titlebar(frame, { name = 'lbf-titlebar', label_name = 'lbf-tag' })

    local canvas = set_style(frame.add({ type = 'flow', name = 'lbf-canvas', direction = 'vertical' }), { vertical_spacing = 6 })

    local instructions = add_section(canvas, 'lbf-instructions', { 'lbf-gui.instructions-title' })
    set_style(instructions.add({ type = 'flow', name = 'lbf-lines', direction = 'vertical' }), { padding = 8 })

    local checks = add_section(canvas, 'lbf-checks', { 'lbf-gui.checks-title' })

    local stats = set_style(checks.add({ type = 'flow', name = 'lbf-stats', direction = 'horizontal' }), {
        padding = 8,
        horizontal_spacing = 6,
    })
    add_stat_tile(stats, 'lbf-stat-pending', { 170, 170, 170 }, { 'lbf-gui.stat-pending' })
    add_stat_tile(stats, 'lbf-stat-passed', { 120, 220, 80 }, { 'lbf-gui.stat-passed' })
    add_stat_tile(stats, 'lbf-stat-failed', { 220, 80, 80 }, { 'lbf-gui.stat-failed' })

    local pane = set_style(checks.add({ type = 'scroll-pane', name = 'lbf-pane', vertical_scroll_policy = 'never' }), {
        padding = 8,
        top_padding = 0,
    })
    set_style(pane.add({ type = 'table', name = 'lbf-rows', column_count = 2 }), {
        horizontal_spacing = 12,
        vertical_spacing = 4,
    })

    local final = set_style(canvas.add({ type = 'frame', name = 'lbf-final-frame', style = 'neutral_message_frame', direction = 'vertical' }), {
        horizontally_stretchable = true,
        horizontal_align = 'center',
        padding = 8,
    })
    final.visible = false
    set_style(final.add({ type = 'label', name = 'lbf-final-title' }), { font = 'default-large-bold' })
    final.add({ type = 'label', name = 'lbf-final-counts' })

    return frame
end

--- @param frame LuaGuiElement
local function rebuild(frame)
    frame['lbf-titlebar']['lbf-tag'].caption = header and header.tag or { 'lbf-gui.default-title' }

    local canvas = frame['lbf-canvas']
    local instructions = canvas['lbf-instructions']
    local lines_flow = instructions['lbf-lines']
    lines_flow.clear()
    instructions.visible = header ~= nil and #header.lines > 0
    if header then
        for _, line in pairs(header.lines) do
            set_style(lines_flow.add({ type = 'label', caption = line }), { single_line = false, maximal_width = 380 })
        end
    end

    local checks = canvas['lbf-checks']
    local total = #rows
    local passed, failed_count = 0, 0
    for _, row in pairs(rows) do
        if row.status ~= 'pending' then
            if row.status then
                passed = passed + 1
            else
                failed_count = failed_count + 1
            end
        end
    end
    local pending_count = total - passed - failed_count

    local stats = checks['lbf-stats']
    stats['lbf-stat-pending']['lbf-number'].caption = tostring(pending_count)
    stats['lbf-stat-passed']['lbf-number'].caption = tostring(passed)
    stats['lbf-stat-failed']['lbf-number'].caption = tostring(failed_count)

    local grid = checks['lbf-pane']['lbf-rows']
    grid.clear()
    for index, row in pairs(rows) do
        set_style(grid.add({ type = 'label', caption = index .. '. ' .. row.name }), {
            single_line = false,
            maximal_width = 280,
        })
        local status_label = grid.add({ type = 'label', caption = status_caption(row.status) })
        if row.extra then
            status_label.tooltip = row.extra
        end
    end

    local final_frame = canvas['lbf-final-frame']
    if finished then
        final_frame.visible = true
        set_style(final_frame, finished.failed == 0 and 'positive_message_frame' or 'negative_message_frame')
        set_style(final_frame, { horizontally_stretchable = true, horizontal_align = 'center', padding = 8 })
        final_frame['lbf-final-title'].caption = finished.failed == 0
            and { 'lbf-gui.final-title-passed' }
            or { 'lbf-gui.final-title-failed' }
        final_frame['lbf-final-counts'].caption = string.format(
            '%d/%d checks passed', finished.passed, finished.passed + finished.failed
        )
    else
        final_frame.visible = false
    end
end

--- Rebuilds every connected player's results panel from current state.
function Gui.refresh()
    for _, player in pairs(game.connected_players) do
        rebuild(ensure_frame(player))
    end
end

--- Sets the level tag + instruction lines shown above the results table.
--- @param tag string
--- @param lines string[]
function Gui.set_header(tag, lines)
    header = { tag = tag, lines = lines }
    Gui.refresh()
end

--- Adds or updates a named row and re-renders every open panel.
--- @param name string
--- @param status boolean|'pending'
--- @param extra string? shown as a tooltip on the status cell
function Gui.upsert(name, status, extra)
    for _, row in pairs(rows) do
        if row.name == name then
            row.status, row.extra = status, extra
            Gui.refresh()
            return
        end
    end
    rows[#rows + 1] = { name = name, status = status, extra = extra }
    Gui.refresh()
end

--- Marks the suite as complete; the panel keeps showing the full table plus a
--- closing banner — this panel is the sole on-screen record of scenario
--- completion (see Harness.summary_after).
--- @param passed integer
--- @param failed integer
function Gui.finish(passed, failed)
    finished = { passed = passed, failed = failed }
    Gui.refresh()
end

return Gui
