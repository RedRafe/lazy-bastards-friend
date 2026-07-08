--- SPM watchdog (DESIGN.md §2.1): auto-retire Collect+Feed (and optionally
--- Combat) once the factory's science throughput passes the threshold. Uses the
--- built-in hidden `science` item that labs consume in production statistics —
--- no science-pack detection needed. Conditional nth-tick like the scheduler:
--- zero cost when disabled, tripped, or with nothing left to retire.

local State = require('scripts.state')

local Watchdog = {}

-- 601, not a round 600: the scheduler's nth-tick interval can be any value up
-- to lbf-update-period's maximum (600), and registering two handlers on the
-- same nth-tick value would clobber one of them.
local CHECK_INTERVAL = 601
local STRIKES_TO_TRIP = 3 -- consecutive over-threshold checks before retiring

--- Mirrors the nth-tick registration; rebuilt from storage on every load.
--- @type boolean
local registered = false

-- Called after every measurement so open admin GUIs can refresh their SPM
-- readout (control.lua wires this; a direct require would be circular).
--- @type fun()[]
local check_listeners = {}

--- @param listener fun()
function Watchdog.add_check_listener(listener)
    check_listeners[#check_listeners + 1] = listener
end

--- Current science consumption per minute for a force, summed over surfaces.
--- @param force LuaForce
--- @return double
function Watchdog.spm(force)
    local total = 0
    for _, surface in pairs(game.surfaces) do
        total = total + force.get_item_production_statistics(surface).get_flow_count({
            name = 'science',
            category = 'input',
            precision_index = defines.flow_precision_index.one_minute,
        })
    end
    return total
end

--- 'armed' = will retire when SPM stays over threshold; 'tripped' = already
--- retired; 'disabled' = turned off by setting; 'idle' = nothing left to stop.
--- @return 'armed'|'tripped'|'disabled'|'idle'
function Watchdog.status()
    if storage.auto_disabled then
        return 'tripped'
    end
    if settings.global['lbf-watchdog-enabled'].value ~= true then
        return 'disabled'
    end
    return storage.watchdog_armed and 'armed' or 'idle'
end

local function trip()
    storage.auto_disabled = true
    storage.spm_strikes = 0
    storage.active.collect = false
    storage.active.feed = false
    if settings.global['lbf-watchdog-stops-combat'].value == true then
        storage.active.combat = false
    end
    game.print({ 'lbf-message.retired' })
    State.refresh_all() -- renders, GUIs, shortcut indicators, scheduler, and this watchdog
end

local function check()
    local threshold = settings.global['lbf-spm-threshold'].value --[[@as double]]
    local over = false
    for _, force in pairs(game.forces) do
        if #force.connected_players > 0 and Watchdog.spm(force) > threshold then
            over = true
            break
        end
    end
    if over then
        storage.spm_strikes = storage.spm_strikes + 1
        if storage.spm_strikes >= STRIKES_TO_TRIP then
            trip()
        end
    else
        storage.spm_strikes = 0
    end
    for _, listener in pairs(check_listeners) do
        listener()
    end
end

--- (Re)register the nth-tick handler to match storage.watchdog_armed.
--- Reads storage only — the only entry point legal in on_load.
function Watchdog.apply()
    local armed = storage.watchdog_armed == true
    if armed == registered then
        return
    end
    registered = armed
    script.on_nth_tick(CHECK_INTERVAL, armed and check or nil)
end

--- Recompute whether the watchdog should run, persist it, re-register.
--- Call from events only (writes storage) — never from on_load.
function Watchdog.rebuild()
    local active = storage.active
    local stops_anything = active.collect
        or active.feed
        or (settings.global['lbf-watchdog-stops-combat'].value == true and active.combat)
    storage.watchdog_armed = (
        settings.global['lbf-watchdog-enabled'].value == true
        and not storage.auto_disabled
        and stops_anything
    ) or nil
    Watchdog.apply()
end

--- State refresh handler signature (player unused: masters are global).
function Watchdog.refresh(_)
    Watchdog.rebuild()
end

return Watchdog
