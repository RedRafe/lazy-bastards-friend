--- Conditional round-robin scheduler (DESIGN.md §7). One player is serviced per
--- firing; the nth-tick interval is update_period / queue_size, so each player
--- gets one cycle per period with the load spread evenly. No queue = no handler
--- registered at all — the mod costs zero while nobody needs it.

local State = require('__lazy-bastards-friend__.scripts.state')
local Raid = require('__lazy-bastards-friend__.scripts.raid')

local Scheduler = {}

--- Interval currently registered with script.on_nth_tick. Plain local (not
--- storage): it mirrors registration state, which is rebuilt from scratch on
--- every load via Scheduler.apply.
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
        -- New sweep: rotate the order so the tail position (which collects any
        -- fair-share remainder, §1.4) doesn't always fall on the same player.
        table.insert(queue, table.remove(queue, 1))
        scheduler.cursor = 1
    end
    local player_index = queue[scheduler.cursor]
    scheduler.cursor = scheduler.cursor + 1

    local player = game.get_player(player_index)
    if player and player.connected and State.any_effective(player_index) then
        -- Players still due in this sweep contest shared collect sources (§1.4).
        local pending
        for i = scheduler.cursor, #queue do
            pending = pending or {}
            pending[#pending + 1] = queue[i]
        end
        Raid.service(player, pending)
    else
        Scheduler.rebuild() -- queue went stale (player left/disabled/removed)
    end
end

--- (Re)register the nth-tick handler to match storage.scheduler.interval.
--- Reads storage only, writes nothing — the only entry point legal in on_load.
function Scheduler.apply()
    -- storage.scheduler is nil when loading a pre-M2 save: on_load fires before
    -- on_configuration_changed gets the chance to create it.
    local scheduler = storage.scheduler
    local interval = scheduler and scheduler.interval
    if interval == registered_interval then
        return
    end
    if registered_interval then
        script.on_nth_tick(registered_interval, nil)
    end
    registered_interval = interval
    if interval then
        script.on_nth_tick(interval, on_nth_tick_handler)
    end
end

--- Rebuild the queue from connected players with any effective channel, recompute
--- the interval, then re-register. Call from events only (writes storage) —
--- never from on_load.
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

--- State refresh handler signature (player unused: any change rebuilds the
--- whole queue — it is tiny).
function Scheduler.refresh(_)
    Scheduler.rebuild()
end

return Scheduler
