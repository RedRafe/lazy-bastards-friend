--- SPM watchdog: auto-retire Collect+Feed (and optionally Combat)
--- once the factory's science throughput passes the threshold. 
--- Uses the built-in hidden `science` item that labs consume in production statistics.
--- Conditional nth-tick like the scheduler:
--- zero cost when disabled, tripped, or with nothing left to retire.

local State = require('__lazy-bastards-friend__.scripts.state')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local Watchdog = {}

-- 601, not a round 600: the scheduler's nth-tick interval can be any value up
-- to lbf-update-period's maximum (600). Registering through Event.on_nth_tick
-- means a collision would fan out rather than clobber, but keeping this
-- disjoint still avoids running the check mid-scheduler-sweep for no reason.
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
    -- 'combat' is a tree child of 'feed' (DESIGN.md §12): stopping feed
    -- already stops turret-feeding too, no separate write needed.
    State.set_master('collect', false)
    State.set_master('feed', false)
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
    if armed then
        Event.on_nth_tick(CHECK_INTERVAL, check)
    else
        Event.remove_nth_tick(CHECK_INTERVAL, check)
    end
end

--- The admin on/off switch (admin GUI Watchdog tab, remote API). Switching ON
--- also un-trips and re-arms after an auto-retirement — the only re-arm path,
--- since re-enabling the channel masters deliberately does not (§2.1).
--- Notifies check listeners so open admin GUIs repaint immediately.
--- @param value boolean
function Watchdog.set_enabled(value)
    if value then
        storage.auto_disabled = false
    end
    storage.spm_strikes = 0
    if settings.global['lbf-watchdog-enabled'].value ~= value then
        -- Fires on_runtime_mod_setting_changed, whose handler rebuilds too.
        settings.global['lbf-watchdog-enabled'] = { value = value }
    end
    Watchdog.rebuild()
    for _, listener in pairs(check_listeners) do
        listener()
    end
end

--- Recompute whether the watchdog should run, persist it, re-register.
--- Call from events only (writes storage) — never from on_load.
function Watchdog.rebuild()
    local active = storage.settings
    -- Nothing to retire while the global switch is off (§4.3 "Everyone" row).
    -- 'combat' isn't checked separately — it's a tree child of 'feed' now, so
    -- stopping feed always stops it too (DESIGN.md §12).
    local stops_anything = active.mod.enabled and (active.collect.enabled or active.feed.enabled)
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
