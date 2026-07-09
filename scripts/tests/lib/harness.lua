--- Minimal pass/fail assertion framework for test-bench levels that can verify
--- themselves instead of relying on a human staring at a furnace (DESIGN.md-style
--- "the mod behaves correctly" checks). Levels that are inherently manual (GUI
--- interaction, multiplayer fairness) skip this and just use Bench.intro.
---
--- Usage from a level file:
---   local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
---   Harness.check('threshold applied', function() return remote.call(...) == 5 end)
---   Harness.eventually('furnace got fuel', function() return furnace.get_fuel_inventory().get_item_count('coal') > 0 end, 600)
--- Results print to all players as they resolve; call Harness.summary_after(ticks)
--- once at the end of a level's setup to print a final tally.

local Harness = {}

local function color_tag(ok)
    return ok and '[color=green][PASS][/color]' or '[color=red][FAIL][/color]'
end

--- @type { name: string, condition: fun(): boolean, deadline: uint }[]
local pending = {}
local results = {} -- name -> boolean

local function report(name, ok, extra)
    results[name] = ok
    game.print(color_tag(ok) .. ' ' .. name .. (extra and (' — ' .. extra) or ''))
end

--- Runs `condition` immediately and reports the result.
--- @param name string
--- @param condition fun(): boolean
function Harness.check(name, condition)
    local ok, result = pcall(condition)
    report(name, ok and result == true, (not ok) and tostring(result) or nil)
end

local nth_tick_registered = false
local function ensure_poller()
    if nth_tick_registered then
        return
    end
    nth_tick_registered = true
    script.on_nth_tick(30, function(event)
        for index = #pending, 1, -1 do
            local entry = pending[index]
            local ok, result = pcall(entry.condition)
            if ok and result == true then
                report(entry.name, true)
                table.remove(pending, index)
            elseif event.tick >= entry.deadline then
                report(entry.name, false, ok and 'timed out' or tostring(result))
                table.remove(pending, index)
            end
        end
    end)
end

--- Polls `condition` every 30 ticks until it's true or `timeout_ticks` elapses.
--- @param name string
--- @param condition fun(): boolean
--- @param timeout_ticks uint
function Harness.eventually(name, condition, timeout_ticks)
    ensure_poller()
    pending[#pending + 1] = { name = name, condition = condition, deadline = game.tick + timeout_ticks }
end

--- Prints a final PASS/FAIL tally once every `eventually` check has resolved.
--- @param delay_ticks uint how long to wait before printing, should exceed the
---   longest `eventually` timeout registered in this level
local summary_scheduled = false
function Harness.summary_after(delay_ticks)
    if summary_scheduled then
        return
    end
    summary_scheduled = true
    local tick = game.tick + delay_ticks
    script.on_nth_tick(60, function(event)
        if event.tick < tick then
            return
        end
        script.on_nth_tick(60, nil)
        local passed, failed = 0, 0
        for _, ok in pairs(results) do
            if ok then
                passed = passed + 1
            else
                failed = failed + 1
            end
        end
        game.print(string.format('[color=yellow]LBF test summary: %d passed, %d failed[/color]', passed, failed))
    end)
end

return Harness
