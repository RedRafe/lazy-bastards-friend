# Lazy Bastard's Friend — Remote API

Everything the mod's own script can do, your mod or scenario can do through the
remote interface. The interface name is **`lazy-bastards-friend`**.

```lua
remote.call('lazy-bastards-friend', '<function>', ...)
```

All calls must run in an event context (never during `on_load`). Invalid
arguments raise a Lua error with a `lazy-bastards-friend:` prefix — wrap in
`pcall` if you pass untrusted input.

## Concepts

- **Channels** — the mod's three admin-lockable channels, always addressed by
  string name:
  - `'collect'` — pull finished products / burnt results (and opt-in chest
    contents) from machines into the player's inventory.
  - `'feed'` — push fuel, ingredients and (via the `feed_combat` flag, see
    below) ammo from the player into machines/turrets (and opt-in, drain their
    trash slots into chests).
  - `'appearance'` — gates every render the mod draws for a player: their own
    AoE area, other players' AoE areas they've opted into seeing, and
    starvation/saturation icons. Turning it off for someone hides all of it
    regardless of their own preferences (a destructive admin override,
    e.g. "declutter this player's screen"); leaving it on is non-destructive
    — each player's own opt-in flags (`appearance_show_others_area`,
    `appearance_starvation`, and the channel's own toggle — the "Fill area"
    checkbox) still apply as before. It does no item movement of its own.
    Shown as **"Appearance"** in the admin GUI (internally `'renders'` for a
    few hours on 2026-07-16 before this rename — see DESIGN.md §12).
  - **BREAKING (2026-07-16):** turret ammo feeding is **not** a channel
    anymore — it's a plain `'feed'` behavior flag, set like any other one
    through `set_player_flag`/`get_player_state` (see below), with no admin
    lock/global master of its own. It follows Feed's rules exactly like
    `feed_fuel`/`feed_ingredients` do: no independent lock, no independent
    global master, and (like them) a mirrored `lbf-feed-combat` mod setting.
    Turning `'feed'` off, including the SPM watchdog retiring it, always
    stops turret-feeding too — there is no path to decouple them. Admins gate
    it only indirectly, by locking/disabling Feed. **BREAKING (2026-07-17):**
    the flag itself was renamed `'combat'` → `'feed_combat'` — it was the one
    flag without its family's prefix, an oversight rather than a deliberate
    exception (see DESIGN.md §12).
- **Tri-state activation** — a channel actually runs for a player only if all
  of these are true: the global whole-mod switch is on (`set_global_master`),
  the channel's global master is on (`set_active`), the player is not
  admin-locked — neither for the whole mod (`lock_player_master`) nor for that
  channel (`lock_player`) — and the player's own toggle is on
  (`set_player_enabled`). The combined result is reported as `effective` in
  `get_player_state`. Behavior/appearance flags (`set_player_flag`) sit one
  level below a channel and inherit its whole chain — `feed_combat`'s
  effective state, for instance, depends on Feed's global/lock/toggle as well
  as its own `flags.feed_combat` preference, even though it has no `effective`
  entry of its own (only channels do).
- **Watchdog** — the mod retires Collect+Feed (and, transitively, turret
  feeding) automatically once a force's science consumption passes the
  `lbf-spm-threshold` map setting. Re-enabling masters through
  `set_active(..., true)` does **not** re-arm it — only
  `set_watchdog_enabled(true)` (or the switch in the admin GUI's Watchdog tab)
  does.

Internally, channels and behavior flags are nodes of one hierarchical
settings tree (`scripts/lib/settings_tree.lua`, DESIGN.md §2/§9) — this is
mostly an implementation detail, but two of its shapes are public-API-visible:
`'feed_combat'` is a tree child of `'feed'` (above), and every behavior/
appearance flag name carries a family prefix matching its tree parent, with no
exceptions (see `set_player_flag` below).

## Functions

### `set_global_master(value)`

The global whole-mod switch — the "Everyone" On/Off in the admin GUI's Players
tab. Turning it off stops the mod for every player; turning it back on restores
exactly what was configured before (channel masters, locks, and player
preferences are all preserved). Does *not* re-arm a tripped SPM watchdog.

```lua
remote.call('lazy-bastards-friend', 'set_global_master', false)
```

### `set_active(channel, value)`

Set a global master switch. Turning a master on does *not* override per-player
toggles or admin locks, and does *not* re-arm a tripped SPM watchdog (use
`set_watchdog_enabled(true)` for that).

| arg | type | |
|---|---|---|
| `channel` | `string` | `'collect'`, `'feed'` or `'appearance'` |
| `value` | `boolean` | |

```lua
-- Stop collecting into player inventories, but leave feeding (fuel,
-- ingredients, turret ammo) running:
remote.call('lazy-bastards-friend', 'set_active', 'collect', false)
```

`'feed_combat'` (turret ammo feeding) has no master of its own — it's a plain
`'feed'` behavior flag (see `set_player_flag` below), so turning `'feed'` off
always stops turret-feeding too. There is no way to keep turrets fed while
`'feed'` is off.

### `get_active(channel)` → `boolean`

Read a global master switch.

```lua
if remote.call('lazy-bastards-friend', 'get_active', 'appearance') then ... end
```

### `lock_player(player_index, channel, locked)`

Admin lock: while locked, the channel is off for that player no matter what
they choose, and their own toggle is greyed out in their panel.

| arg | type | |
|---|---|---|
| `player_index` | `uint` | must be an existing player |
| `channel` | `string` | |
| `locked` | `boolean` | `true` = lock out, `false` = allow |

```lua
-- Griefer containment: no more raiding for player 7.
remote.call('lazy-bastards-friend', 'lock_player', 7, 'collect', true)
remote.call('lazy-bastards-friend', 'lock_player', 7, 'feed', true)
```

### `lock_player_master(player_index, locked)`

Admin master lock: while locked, the **whole mod** is off for that player —
every channel, regardless of their own preferences (which are kept and apply
again once unlocked). This is the "On/Off" column in the admin GUI's player
list.

| arg | type | |
|---|---|---|
| `player_index` | `uint` | must be an existing player |
| `locked` | `boolean` | `true` = mod fully off for them, `false` = allow |

```lua
remote.call('lazy-bastards-friend', 'lock_player_master', 7, true)
```

### `set_player_enabled(player_index, channel, enabled)`

Set the player's *own* preference toggle, exactly as if they clicked it.
Has no effect while the channel is admin-locked or its master is off (the
preference is stored and applies once unlocked).

```lua
remote.call('lazy-bastards-friend', 'set_player_enabled', 1, 'feed', false)
```

### `get_player_state(player_index)` → `table`

Full per-player state:

```lua
{
  enabled   = { collect = true,  feed = true,  appearance = true },  -- own toggles
  locked    = { collect = false, feed = false, appearance = false }, -- admin locks
  locked_master = false,   -- admin whole-mod lock (lock_player_master)
  effective = { collect = true,  feed = true,  appearance = true },  -- what actually runs
  radius    = 16,          -- service radius, tiles (already clamped)
  shape     = 'circle',    -- 'circle' | 'square'
  flags     = {            -- behavior toggles (see set_player_flag)
    feed_fuel = true, feed_ingredients = true, collect_chests = false, collect_ground = false,
    feed_trash = false, appearance_summary = false, appearance_show_others_area = false,
    feed_rebalance = false, appearance_starvation = false, feed_combat = true,
    appearance_use_player_color = true,
  },
  reserves  = { ['coal'] = 50 },  -- item name -> protected minimum
}
```

The returned table is a copy — mutating it does nothing.

### `set_player_flag(player_index, flag, value)`

Set one of the player's behavior toggles, exactly as if they clicked it in
their panel. Valid flag names, each carrying its settings-tree family prefix
(`feed_`, `collect_`, `appearance_`) — no exceptions:

| flag | default | |
|---|---|---|
| `'feed_fuel'` | `true` | Feed channel tops up burners with fuel |
| `'feed_ingredients'` | `true` | Feed channel fills machine inputs (recipes, smeltables, science packs) |
| `'feed_combat'` | `true` | Feed channel tops up ammo-turrets from the player's inventory — same rules as `feed_fuel`/`feed_ingredients`: no admin lock/master of its own, gated only by Feed's chain |
| `'collect_chests'` | `false` | Collect channel also empties chests (needs the `lbf-allow-chest-collect` map setting) |
| `'collect_ground'` | `false` | Collect channel also picks up items on the ground |
| `'feed_trash'` | `false` | Feed channel drains logistic trash slots into nearby chests (paused while `collect_chests` is active) |
| `'appearance_summary'` | `false` | show a per-cycle floating summary of what was moved — gated by the `'appearance'` channel (2026-07-17: was the unprefixed exception `'summary'`, see DESIGN.md §12) |
| `'appearance_show_others_area'` | `false` | this player also sees every other player's area render (viewer-side; does not affect whether others see *their* area) — gated by the `'appearance'` channel |
| `'feed_rebalance'` | `false` | Feed channel moves surplus fuel/ingredients between over- and under-stocked machines, even when the player carries nothing (§1.1 pass 6) |
| `'appearance_starvation'` | `false` | briefly show a red icon over machines that wanted an item the player couldn't spare, or green over ones already full — gated by the `'appearance'` channel |
| `'appearance_use_player_color'` | `true` | draw the serviced area in this player's own color instead of their custom color below — gated by the `'appearance'` channel (2026-07-17: newly remote-settable, see DESIGN.md §12) |

Note: `appearance_fill` ("Fill area") is **not** in this table — it graduated
to the `'appearance'` channel's own toggle (2026-07-16), so it's set through
`set_active`/`set_player_enabled`/`lock_player` instead.

```lua
-- Scenario hands out pre-configured chest raiding:
remote.call('lazy-bastards-friend', 'set_player_flag', 1, 'collect_chests', true)
```

### `set_player_radius(player_index, radius)`

Set the player's service radius, clamped to the `lbf-min-radius` /
`lbf-max-radius` map settings. Also updates their per-player mod setting and
redraws their area.

```lua
remote.call('lazy-bastards-friend', 'set_player_radius', 1, 24)
```

### `set_player_reserve(player_index, item_name, count)`

Set (or clear, with `nil`) the per-item minimum that feeding never dips below.
Reserves are keyed by item name and apply to the total across qualities.

```lua
remote.call('lazy-bastards-friend', 'set_player_reserve', 1, 'coal', 100)
remote.call('lazy-bastards-friend', 'set_player_reserve', 1, 'coal', nil) -- clear
```

### `get_state()` → `table`

Global mod state:

```lua
{
  master        = true,       -- global whole-mod switch (set_global_master)
  active        = { collect = true, feed = true, appearance = true }, -- masters
  auto_disabled = false,      -- true after the SPM watchdog tripped
  watchdog      = 'armed',    -- 'armed' | 'tripped' | 'disabled' | 'idle'
  spm_threshold = 45,         -- current lbf-spm-threshold map setting
}
```

`watchdog` values: `armed` = counting toward retirement, `tripped` =
auto-retired, `disabled` = the `lbf-watchdog-enabled` setting is off,
`idle` = nothing left to retire (the masters it would stop are already off).

### `set_spm_threshold(value)`

Set the `lbf-spm-threshold` map setting. Factorio only allows the owning mod
(or a player, through the settings GUI) to write a runtime-global setting, so
scenarios and other mods must use this call instead of writing
`settings.global` directly. Changing the threshold resets the watchdog's
strike debounce.

```lua
remote.call('lazy-bastards-friend', 'set_spm_threshold', 90)
```

### `set_watchdog_enabled(value)`

The watchdog's on/off switch (mirrors the `lbf-watchdog-enabled` map setting
and the switch in the admin GUI's Watchdog tab). Turning it **on** also clears
the auto-retired state and re-arms — the only re-arm path after a trip;
`set_active(..., true)` alone leaves the watchdog tripped.

```lua
-- Re-arm after an auto-retirement:
remote.call('lazy-bastards-friend', 'set_watchdog_enabled', true)
```

### `get_spm(force)` → `double`

The science-per-minute reading the watchdog uses for a force (the built-in
`science` production statistic, summed over all surfaces). `force` is a force
name, index, or LuaForce.

```lua
game.print(remote.call('lazy-bastards-friend', 'get_spm', 'player'))
```

### `set_entity_excluded(player_index, unit_number, excluded)`

Exclude or include one entity from a player's raids (DESIGN.md §10.4), as if
they hovered it and pressed the exclude hotkey. Unlike the hotkey path, this
call only has a bare `unit_number` — not a `LuaEntity` — so it **cannot**
register destruction cleanup for you. If the entity might be destroyed while
still excluded, clear the exclusion yourself (e.g. on your own
`on_object_destroyed` registration) to avoid leaking an entry.

| arg | type | |
|---|---|---|
| `player_index` | `uint` | |
| `unit_number` | `uint` | the target entity's `unit_number` |
| `excluded` | `boolean` | |

```lua
remote.call('lazy-bastards-friend', 'set_entity_excluded', 1, furnace.unit_number, true)
```

### `is_entity_excluded(player_index, unit_number)` → `boolean`

```lua
if remote.call('lazy-bastards-friend', 'is_entity_excluded', 1, furnace.unit_number) then ... end
```

## Scenario example

A RedMew-style scenario that disables raiding on a protected surface and grants
a bigger radius to donators:

```lua
script.on_event(defines.events.on_player_changed_surface, function(event)
    local locked = game.get_player(event.player_index).surface.name == 'protected'
    remote.call('lazy-bastards-friend', 'lock_player', event.player_index, 'collect', locked)
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    if Donators.is_donator(event.player_index) then
        remote.call('lazy-bastards-friend', 'set_player_radius', event.player_index, 32)
    end
end)
```
