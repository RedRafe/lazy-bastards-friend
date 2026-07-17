--- L08 — Multiplayer fairness: a stateless pending-rivals scheme keeps two players reaching the same machine from double-feeding past its cap, and splits shared workload evenly instead of favoring whoever's scheduler slot fires first. Needs a second connected player to mean anything, so it stays instruction-driven.

local Bench = require('__lazy-bastards-friend__.scripts.tests.lib.bench')
local Event = require('__lazy-bastards-friend__.scripts.lib.event')

local AREA = { { -12, -10 }, { 12, 10 } }

local BENCH = {
    -- Small-capacity furnaces: two players feeding at once must not overfill the input slots.
    { name = 'stone-furnace', position = { -6, 0 } },
    { name = 'stone-furnace', position = { -2, 0 } },
    { name = 'stone-furnace', position = { 2, 0 } },
    { name = 'stone-furnace', position = { 6, 0 } },
    { name = 'gun-turret', position = { -3, 5 } },
    { name = 'gun-turret', position = { 3, 5 } },
}

local KIT = {
    ['coal'] = 100,
    ['iron-ore'] = 200,
    ['firearm-magazine'] = 60,
}

Event.on_init(function()
    local surface = game.surfaces['nauvis']
    surface.peaceful_mode = true
    Bench.prepare_area(surface, AREA, game.forces.player)
    Bench.spawn(surface, game.forces.player, BENCH)
end)

Bench.on_player_created(KIT, 'L08 multiplayer fairness', {
    'Have a second player join this save and stand near the same furnace/turret cluster at the same time.',
    'Neither player should ever see a machine over-filled past its normal capacity — the pending-rivals split caps what each player delivers per cycle.',
    'Over a few cycles, feeding/looting work on the shared machines should be split roughly evenly between the two of you, not always won by the same player.',
    'A player who disables a channel or gets admin-locked out of one should contribute nothing and take nothing on it — the other player should pick up the full load alone.',
})
