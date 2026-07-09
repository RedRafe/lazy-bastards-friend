--- L09 — SPM watchdog auto-retirement and the admin GUI:
--- labs are pre-wired to consume science the moment they get packs, the
--- threshold is lowered so retirement trips within seconds instead of needing a
--- real factory, and the intro points at /lbf-admin for the lock/bulk-action UI.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Harness = require('__lazy-bastards-friend__.scripts.tests.lib.harness')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -8 }, { 12, 8 } }
local SPM_THRESHOLD = 5

local BENCH = {
    { name = 'lab', position = { -2, 0 } },
    { name = 'lab', position = { 2, 0 } },
    { name = 'medium-electric-pole', position = { 0, 0 } },
    { name = 'hidden-electric-energy-interface', position = { 0, 0 } }, -- base's creative power source
}

local KIT = {
    ['automation-science-pack'] = 200,
}

-- 'automation' only costs 10 packs, so with two labs it finishes in seconds —
-- long before 3 consecutive over-threshold watchdog checks (601 ticks apart)
-- can land. Re-queue it forever so the labs never run dry mid-test.
local function requeue_research()
    local force = game.forces.player
    local technology = force.technologies['automation']
    technology.researched = false
    force.add_research(technology)
end

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    game.speed = 10 -- the watchdog's one-minute flow-precision window is tick-based, not realtime, so this only cuts wall-clock wait
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
    Bench.research(game.forces.player, { 'automation-science-pack' })
    game.forces.player.add_research('automation')
    -- Runtime-global settings can only be written by their owning mod, so the
    -- threshold change goes through the remote interface (docs/API.md).
    remote.call('lazy-bastards-friend', 'set_spm_threshold', SPM_THRESHOLD)
end)

Event.add(defines.events.on_research_finished, function(event)
    if event.research.name == 'automation' then
        requeue_research()
    end
end)

Bench.on_player_created(KIT, 'L09 watchdog & admin', {
    'Threshold is lowered to ' .. SPM_THRESHOLD .. ' SPM and the level runs at 10x game speed — standing near the labs feeds them packs and should trip the watchdog (Collect+Feed off) within a few seconds.',
    'Turn off "Feed ingredients" first if you want to poke around before it retires itself.',
    'Open /lbf-admin: re-enable the masters after retirement, try per-player per-channel locks, and check the SPM readout matches get_spm from docs/API.md.',
})

Event.add(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    if not player then
        return
    end
    Harness.check('spm threshold applied', function()
        return remote.call('lazy-bastards-friend', 'get_state').spm_threshold == SPM_THRESHOLD
    end)
    Harness.eventually('watchdog auto-retired collect+feed', function()
        return remote.call('lazy-bastards-friend', 'get_state').auto_disabled == true
    end, 3030)
    Harness.summary_after(3060)
end)
