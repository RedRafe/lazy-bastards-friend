--- L10 — Remote interface smoke test (docs/API.md). Fully automated: no bench,
--- no player interaction needed, just exercise every `lazy-bastards-friend`
--- remote call and report PASS/FAIL for each in the results panel. Useful as
--- a fast regression check after touching scripts/remote.lua.

local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Gui = require('__lazy-bastards-friend__.scripts.tests.lib.gui')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local INTERFACE = 'lazy-bastards-friend'

local function call(method, ...)
    return remote.call(INTERFACE, method, ...)
end

Event.on_init(function()
    game.surfaces['nauvis'].peaceful_mode = true
end)

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    Gui.set_header('LBF test bench — L10 remote API smoke test', {
        'Fully automated — results show in this panel, no need to move.',
    })

    Harness.check('get_active accepts all three channels', function()
        return type(call('get_active', 'collect')) == 'boolean'
            and type(call('get_active', 'feed')) == 'boolean'
            and type(call('get_active', 'appearance')) == 'boolean'
    end)

    Harness.check('set_active / get_active round-trip', function()
        call('set_active', 'appearance', false)
        local off = call('get_active', 'appearance') == false
        call('set_active', 'appearance', true)
        local on = call('get_active', 'appearance') == true
        return off and on
    end)

    Harness.check('unknown channel is rejected', function()
        local ok = pcall(call, 'get_active', 'nonsense')
        return not ok
    end)

    -- 'combat' is no longer a channel (§1/§12 "vertical" refactor) — it's a
    -- plain per-player flag under Feed's chain, gated by lock_player('feed').
    Harness.check('unknown channel "combat" is rejected', function()
        local ok = pcall(call, 'get_active', 'combat')
        return not ok
    end)

    Harness.check('set_player_enabled / get_player_state round-trip', function()
        call('set_player_enabled', player.index, 'feed', false)
        local state = call('get_player_state', player.index)
        local off = state.enabled.feed == false and state.effective.feed == false
        call('set_player_enabled', player.index, 'feed', true)
        return off
    end)

    Harness.check('lock_player overrides player preference', function()
        call('lock_player', player.index, 'appearance', true)
        local locked_off = call('get_player_state', player.index).effective.appearance == false
        call('lock_player', player.index, 'appearance', false)
        local unlocked_on = call('get_player_state', player.index).effective.appearance == true
        return locked_off and unlocked_on
    end)

    -- 'feed_combat' has no admin lock/channel of its own (§1/§12): locking
    -- Feed is the only way an admin stops it now. get_player_state has no
    -- `effective.feed_combat` entry to read (it's a flag, not a channel), so
    -- this only asserts the one lock path that actually gates it still works.
    Harness.check('lock_player("feed") is the only admin lock reaching feed_combat', function()
        call('lock_player', player.index, 'feed', true)
        local feed_locked = call('get_player_state', player.index).effective.feed == false
        call('lock_player', player.index, 'feed', false)
        local feed_unlocked = call('get_player_state', player.index).effective.feed == true
        return feed_locked and feed_unlocked
    end)

    Harness.check('set_player_flag / get_player_state round-trip', function()
        call('set_player_flag', player.index, 'collect_ground', true)
        local on = call('get_player_state', player.index).flags.collect_ground == true
        call('set_player_flag', player.index, 'collect_ground', false)
        local off = call('get_player_state', player.index).flags.collect_ground == false
        return on and off
    end)

    Harness.check('feed_combat is settable through set_player_flag', function()
        call('set_player_flag', player.index, 'feed_combat', false)
        local off = call('get_player_state', player.index).flags.feed_combat == false
        call('set_player_flag', player.index, 'feed_combat', true)
        local on = call('get_player_state', player.index).flags.feed_combat == true
        return off and on
    end)

    Harness.check('unknown flag is rejected', function()
        local ok = pcall(call, 'set_player_flag', player.index, 'nonsense', true)
        return not ok
    end)

    Harness.check('set_player_radius clamps to configured bounds', function()
        call('set_player_radius', player.index, 1)
        local min_radius = call('get_player_state', player.index).radius
        call('set_player_radius', player.index, 1000)
        local max_radius = call('get_player_state', player.index).radius
        return min_radius >= settings.global['lbf-min-radius'].value
            and max_radius <= settings.global['lbf-max-radius'].value
    end)

    Harness.check('set_player_reserve accepts and clears', function()
        call('set_player_reserve', player.index, 'coal', 10)
        local reserved = call('get_player_state', player.index).reserves.coal == 10
        call('set_player_reserve', player.index, 'coal', nil)
        local cleared = call('get_player_state', player.index).reserves.coal == nil
        return reserved and cleared
    end)

    Harness.check('unknown item is rejected by set_player_reserve', function()
        local ok = pcall(call, 'set_player_reserve', player.index, 'not-a-real-item', 10)
        return not ok
    end)

    Harness.check('set_spm_threshold / get_state round-trip', function()
        call('set_spm_threshold', 30)
        return call('get_state').spm_threshold == 30
    end)

    Harness.check('negative spm threshold is rejected', function()
        local ok = pcall(call, 'set_spm_threshold', -1)
        return not ok
    end)

    Harness.check('get_spm returns a number for the player force', function()
        return type(call('get_spm', player.force)) == 'number'
    end)

    Harness.check('get_state shape matches docs/API.md', function()
        local state = call('get_state')
        return type(state.active) == 'table'
            and type(state.auto_disabled) == 'boolean'
            and type(state.watchdog) == 'string'
            and type(state.spm_threshold) == 'number'
    end)

    Harness.summary_after(60)
end)
