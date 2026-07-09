--- On-screen results panel for test-bench levels. Replaces the old chat-print
--- reporting (level tag/instructions, per-check PASS/FAIL, final tally) with a
--- single frame pinned to the top-left of the screen, kept in sync for every
--- connected player. Harness owns when things resolve; this module only knows
--- how to render whatever Harness/Bench hand it.

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
        return '[color=170,170,170]…[/color]'
    elseif status then
        return '[color=0,220,0]PASS[/color]'
    else
        return '[color=220,0,0]FAIL[/color]'
    end
end

--- @param player LuaPlayer
--- @return LuaGuiElement
local function ensure_frame(player)
    local existing = player.gui.screen[FRAME_NAME]
    if existing then
        return existing
    end

    local frame = player.gui.screen.add({ type = 'frame', name = FRAME_NAME, direction = 'vertical' })
    frame.location = { x = 8, y = 8 }

    frame.add({ type = 'label', name = 'lbf-tag', style = 'frame_title' })
    local lines_flow = frame.add({ type = 'flow', name = 'lbf-lines', direction = 'vertical' })
    lines_flow.style.bottom_margin = 6

    frame.add({ type = 'line' })
    frame.add({ type = 'label', name = 'lbf-counter' })

    local pane = frame.add({ type = 'scroll-pane', name = 'lbf-pane' })
    pane.style.maximal_height = 420
    local grid = pane.add({ type = 'table', name = 'lbf-rows', column_count = 2 })
    grid.style.horizontal_spacing = 12

    frame.add({ type = 'label', name = 'lbf-final' })
    return frame
end

--- @param frame LuaGuiElement
local function rebuild(frame)
    frame['lbf-tag'].caption = header and header.tag or ''

    local lines_flow = frame['lbf-lines']
    lines_flow.clear()
    if header then
        for _, line in pairs(header.lines) do
            local label = lines_flow.add({ type = 'label', caption = line })
            label.style.single_line = false
            label.style.maximal_width = 420
        end
    end

    local total = #rows
    local passed, resolved = 0, 0
    for _, row in pairs(rows) do
        if row.status ~= 'pending' then
            resolved = resolved + 1
            if row.status then
                passed = passed + 1
            end
        end
    end
    local counter_color = (resolved < total) and '220,220,0' or (passed == total) and '0,220,0' or '220,0,0'
    frame['lbf-counter'].caption = string.format(
        '[color=%s]%d/%d resolved — %d passed, %d failed[/color]',
        counter_color, resolved, total, passed, resolved - passed
    )

    local grid = frame['lbf-pane']['lbf-rows']
    grid.clear()
    for index, row in pairs(rows) do
        grid.add({ type = 'label', caption = index .. '. ' .. row.name })
        local status_label = grid.add({ type = 'label', caption = status_caption(row.status) })
        if row.extra then
            status_label.tooltip = row.extra
        end
    end

    if finished then
        frame['lbf-final'].caption = finished.failed == 0
            and '[color=0,220,0]All tests passed — scenario complete.[/color]'
            or string.format('[color=220,0,0]%d test(s) failed — scenario complete.[/color]', finished.failed)
    else
        frame['lbf-final'].caption = ''
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

--- @return { name: string, status: boolean|'pending', extra: string? }[] a shallow copy, in registration order
function Gui.rows()
    local copy = {}
    for index, row in pairs(rows) do
        copy[index] = row
    end
    return copy
end

--- Marks the suite as complete; the panel keeps showing the full table plus a
--- closing line, on top of whatever end-of-scenario screen Harness triggers.
--- @param passed integer
--- @param failed integer
function Gui.finish(passed, failed)
    finished = { passed = passed, failed = failed }
    Gui.refresh()
end

return Gui
