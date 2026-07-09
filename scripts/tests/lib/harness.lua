--- Minimal pass/fail assertion framework for test-bench levels that can verify
--- themselves instead of relying on a human staring at a furnace (DESIGN.md-style
--- "the mod behaves correctly" checks). Levels that are inherently manual (GUI
--- interaction, multiplayer fairness) skip this and just use Bench.intro.
---
--- Usage from a level file:
---   local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
---   Harness.check('threshold applied', function() return remote.call(...) == 5 end)
---   Harness.eventually('furnace got fuel', function() return furnace.get_fuel_inventory().get_item_count('coal') > 0 end, 600)
---   Harness.watch('reserve never violated', function() return player.get_main_inventory().get_item_count('coal') < 20 end, 3600)
--- Results render live in the on-screen panel (scripts/tests/lib/gui.lua) as
--- they resolve; call Harness.summary_after(ticks) once at the end of a
--- level's setup to finish the panel and end the scenario with a win/lose
--- screen once every check has settled.

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

--- Polls `violated` every 30 ticks; fails immediately (and permanently) the
--- moment it returns true, otherwise passes once `timeout_ticks` elapses
--- without a violation. For invariants that must hold continuously rather
--- than eventually become true.
--- @param name string
--- @param violated fun(): boolean
--- @param timeout_ticks uint
function Harness.watch(name, violated, timeout_ticks)
    ensure_poller()
    Gui.upsert(name, 'pending')
    pending[#pending + 1] = { name = name, condition = violated, deadline = game.tick + timeout_ticks, watch = true }
end

--- Finishes the results panel and ends the scenario with a win/lose screen
--- once every `eventually`/`watch` check registered so far has resolved.
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
        Gui.finish(passed, failed)
        Harness.end_scenario(passed, failed)
    end)
end

--- Ends the scenario with a Factorio-native win/lose screen, listing every
--- test and its result as bullet points. Mirrors how base's silo-script.lua
--- and the community "Better Victory Screen" mod report level completion via
--- game.set_win_ending_info / set_lose_ending_info + game.set_game_state,
--- instead of leaving the tally in chat scrollback.
--- @param passed integer
--- @param failed integer
function Harness.end_scenario(passed, failed)
    local bullet_points = {}
    for _, row in pairs(Gui.rows()) do
        local mark = row.status == false and '[color=220,0,0]FAIL[/color]' or '[color=0,220,0]PASS[/color]'
        bullet_points[#bullet_points + 1] = mark .. '  ' .. row.name .. (row.extra and (' — ' .. row.extra) or '')
    end
    local total = passed + failed
    local summary = string.format('%d/%d checks passed.', passed, total)

    game.reset_game_state()
    if failed == 0 then
        game.set_win_ending_info({
            title = 'All tests passed',
            message = summary,
            bullet_points = bullet_points,
            final_message = 'LBF test bench complete.',
        })
        game.set_game_state({ game_finished = true, player_won = true, can_continue = true })
    else
        game.set_lose_ending_info({
            title = string.format('%d test(s) failed', failed),
            message = summary,
            bullet_points = bullet_points,
            final_message = 'Fix the failing check(s) and re-run the level.',
        })
        game.set_game_state({ game_finished = true, player_won = false, can_continue = true })
    end
end

return Harness
