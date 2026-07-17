--- Minimal pass/fail assertion framework for test-bench levels that can verify themselves; inherently manual levels (GUI interaction, multiplayer fairness) skip this and just use Bench.intro.
---
--- Usage from a level file:
---   local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
---   Harness.check('threshold applied', function() return remote.call(...) == 5 end)
---   Harness.eventually('furnace got fuel', function() return furnace.get_fuel_inventory().get_item_count('coal') > 0 end, 600)
---   Harness.watch('reserve never violated', function() return player.get_main_inventory().get_item_count('coal') < 20 end, 3600)
--- Results render live in the on-screen panel (scripts/tests/lib/gui.lua); call Harness.summary_after(ticks) once at the end of a level's setup to finish the panel once every check has settled.

local Gui = require('__lazy-bastards-friend__.scripts.tests.lib.gui')

local Harness = {}

--- @type { name: string, condition: fun(): boolean, deadline: uint, watch: boolean? }[]
local pending = {}
local results = {} -- name -> boolean

local function report(name, ok, extra)
    results[name] = ok
    Gui.upsert(name, ok, extra)
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
            if entry.watch then
                if ok and result == true then
                    report(entry.name, false, 'invariant violated')
                    table.remove(pending, index)
                elseif event.tick >= entry.deadline then
                    report(entry.name, ok, (not ok) and tostring(result) or nil)
                    table.remove(pending, index)
                end
            else
                if ok and result == true then
                    report(entry.name, true)
                    table.remove(pending, index)
                elseif event.tick >= entry.deadline then
                    report(entry.name, false, ok and 'timed out' or tostring(result))
                    table.remove(pending, index)
                end
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
    Gui.upsert(name, 'pending')
    pending[#pending + 1] = { name = name, condition = condition, deadline = game.tick + timeout_ticks }
end

--- Polls `violated` every 30 ticks; fails immediately (and permanently) on first true, otherwise passes once `timeout_ticks` elapses — for invariants that must hold continuously.
--- @param name string
--- @param violated fun(): boolean
--- @param timeout_ticks uint
function Harness.watch(name, violated, timeout_ticks)
    ensure_poller()
    Gui.upsert(name, 'pending')
    pending[#pending + 1] = { name = name, condition = violated, deadline = game.tick + timeout_ticks, watch = true }
end

--- Finishes the results panel once every `eventually`/`watch` check has resolved. The panel is the sole record of completion — nothing is printed to chat and the game keeps running (no game_finished modal), so you can keep poking at the admin GUI to debug a failure.
--- @param delay_ticks uint how long to wait before finishing, should exceed the
---   longest `eventually`/`watch` timeout registered in this level
local summary_scheduled = false
function Harness.summary_after(delay_ticks)
    if summary_scheduled then
        return
    end
    summary_scheduled = true
    local tick = game.tick + delay_ticks
    script.on_nth_tick(60, function(event)
        if #pending > 0 and event.tick < tick then
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
        Gui.finish(passed, failed)
    end)
end

return Harness
