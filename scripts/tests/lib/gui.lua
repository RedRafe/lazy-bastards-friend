--- On-screen results panel for test-bench levels: a single frame pinned top-left, kept in sync for every connected player. Harness owns when things resolve; this module only renders whatever Harness/Bench hand it.
---
--- Layout mirrors RedMew's admin_panel/tasklist GUIs: a titlebar, then boxed `inside_shallow_frame` sections with `subheader_frame` headers (Instructions, Checks) rather than bare labels stacked in a column.

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
    local header = inner.add({ type = 'frame', name = 'lbf-header', style = 'lbf_subheader_frame' })
    local header_flow = header.add({ type = 'flow', name = 'lbf-header-flow', direction = 'horizontal', style = 'lbf_subheader_flow' })
    header_flow.add({ type = 'label', caption = caption, style = 'subheader_caption_label' })
    return inner, header_flow
end

--- Small bordered tile showing a big colored number over a caption — used for the live Pending/Passed/Failed counts.
--- @param parent LuaGuiElement
--- @param name string
--- @param color Color
--- @param caption LocalisedString
--- @return LuaGuiElement
local function add_stat_tile(parent, name, color, caption)
    local tile = parent.add({ type = 'frame', name = name, style = 'lbf_stat_tile_frame', direction = 'vertical' })
    set_style(tile.add({ type = 'label', name = 'lbf-number', caption = '0', style = 'lbf_large_bold_label' }), { font_color = color })
    tile.add({ type = 'label', name = 'lbf-label', caption = caption, style = 'lbf_muted_label' })
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

    local final = canvas.add({ type = 'frame', name = 'lbf-final-frame', style = 'lbf_neutral_message_frame', direction = 'vertical' })
    final.visible = false
    final.add({ type = 'label', name = 'lbf-final-title', style = 'lbf_large_bold_label' })
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
            lines_flow.add({ type = 'label', caption = line, style = 'lbf_instruction_label' })
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
        grid.add({ type = 'label', caption = index .. '. ' .. row.name, style = 'lbf_check_label' })
        local status_label = grid.add({ type = 'label', caption = status_caption(row.status) })
        if row.extra then
            status_label.tooltip = row.extra
        end
    end

    local final_frame = canvas['lbf-final-frame']
    if finished then
        final_frame.visible = true
        final_frame.style = finished.failed == 0 and 'lbf_positive_message_frame' or 'lbf_negative_message_frame'
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

--- Marks the suite as complete; the panel keeps showing the full table plus a closing banner — the sole on-screen record of scenario completion (see Harness.summary_after).
--- @param passed integer
--- @param failed integer
function Gui.finish(passed, failed)
    finished = { passed = passed, failed = failed }
    Gui.refresh()
end

return Gui
