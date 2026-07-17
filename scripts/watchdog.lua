--- SPM watchdog: auto-retires Collect+Feed once science throughput passes the threshold; conditional nth-tick like the scheduler.

local State = require('__lazy-bastards-friend__.scripts.state')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local Watchdog = {}

local CHECK_INTERVAL = 601 -- disjoint from the scheduler's interval (max 600), avoids mid-sweep collisions
local STRIKES_TO_TRIP = 3 -- consecutive over-threshold checks before retiring

--- Mirrors the nth-tick registration; rebuilt from storage on every load.
--- @type boolean
local registered = false

-- Called after every measurement to refresh open admin GUIs (wired by control.lua to avoid a circular require).
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

--- 'armed'/'tripped'/'disabled'/'idle'.
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
    State.set_master('collect', false)
    State.set_master('feed', false) -- also stops turret-feeding, a child of 'feed'
    game.print({ 'lbf-message.retired' })
    State.refresh_all()
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

--- (Re)register the nth-tick handler to match storage.watchdog_armed; the only entry point legal in on_load.
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

--- Admin on/off switch; turning it on also un-trips and re-arms (the only re-arm path).
--- @param value boolean
function Watchdog.set_enabled(value)
    if value then
        storage.auto_disabled = false
    end
    storage.spm_strikes = 0
    if settings.global['lbf-watchdog-enabled'].value ~= value then
        settings.global['lbf-watchdog-enabled'] = { value = value } -- fires the setting-changed handler, which rebuilds too
    end
    Watchdog.rebuild()
    for _, listener in pairs(check_listeners) do
        listener()
    end
end

--- Recompute whether the watchdog should run, persist it, re-register. Events only, never on_load.
function Watchdog.rebuild()
    local active = storage.settings
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
