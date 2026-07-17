--- Conditional round-robin scheduler: one player serviced per firing, nth-tick interval is update_period / queue_size. Empty queue = no handler registered.

local State = require('__lazy-bastards-friend__.scripts.state')
local Raid = require('__lazy-bastards-friend__.scripts.raid')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local Scheduler = {}

--- Interval currently registered; plain local, rebuilt from storage on every load via Scheduler.apply.
--- @type integer?
local registered_interval

local function on_nth_tick_handler()
    local scheduler = storage.scheduler
    local queue = scheduler.queue
    if #queue == 0 then
        Scheduler.rebuild()
        return
    end
    if scheduler.cursor > #queue then
        table.insert(queue, table.remove(queue, 1)) -- new sweep: rotate so the fair-share remainder doesn't always land on the same player
        scheduler.cursor = 1
    end
    local player_index = queue[scheduler.cursor]
    scheduler.cursor = scheduler.cursor + 1

    local player = game.get_player(player_index)
    if player and player.connected and State.any_effective(player_index) then
        local pending -- players still due in this sweep, contesting shared collect sources
        for i = scheduler.cursor, #queue do
            pending = pending or {}
            pending[#pending + 1] = queue[i]
        end
        Raid.service(player, pending)
    else
        Scheduler.rebuild() -- queue went stale (player left/disabled/removed)
    end
end

--- (Re)register the nth-tick handler to match storage.scheduler.interval; the only entry point legal in on_load.
function Scheduler.apply()
    local scheduler = storage.scheduler -- nil on a save where on_load fires before on_configuration_changed creates it
    local interval = scheduler and scheduler.interval
    if interval == registered_interval then
        return
    end
    if registered_interval then
        Event.remove_nth_tick(registered_interval, on_nth_tick_handler)
    end
    registered_interval = interval
    if interval then
        Event.on_nth_tick(interval, on_nth_tick_handler)
    end
end

--- Rebuild the queue from connected players with any effective channel, recompute the interval, re-register. Events only, never on_load.
function Scheduler.rebuild()
    local queue = {}
    for _, player in pairs(game.connected_players) do
        if State.any_effective(player.index) then
            queue[#queue + 1] = player.index
        end
    end
    local scheduler = storage.scheduler
    scheduler.queue = queue
    if scheduler.cursor > #queue then
        scheduler.cursor = 1
    end
    if #queue > 0 then
        local period = settings.global['lbf-update-period'].value --[[@as integer]]
        scheduler.interval = math.max(1, math.floor(period / #queue))
    else
        scheduler.interval = nil
    end
    Scheduler.apply()
end

--- State refresh handler signature (player unused: any change rebuilds the whole queue).
function Scheduler.refresh(_)
    Scheduler.rebuild()
end

return Scheduler
