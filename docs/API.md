# Lazy Bastard's Friend — Remote API

Everything the mod's own script can do, your mod or scenario can do through
the remote interface `lazy-bastards-friend`:

```lua
remote.call('lazy-bastards-friend', '<function>', ...)
```

Call only from an event context (never `on_load`). Invalid arguments raise a
Lua error prefixed `lazy-bastards-friend:` — wrap in `pcall` for untrusted input.

## Concepts

**Channels** — three admin-lockable channels, addressed by name:

- `'collect'` — pull products/burnt results (+ opt-in chest contents) from
  machines into the player's inventory.
- `'feed'` — push fuel, ingredients, and (via the `feed_combat` flag) turret
  ammo from the player into machines/turrets; opt-in trash drain.
- `'appearance'` — gates every render for a player: their own AoE area,
  others' areas they've opted into, starvation/saturation icons. Turning it
  off for someone hides all of it regardless of their own prefs (destructive
  override); leaving it on respects each opt-in as normal. Moves no items.

`feed_combat` (turret ammo) is **not** a channel — it's a plain `feed`
behavior flag (see `set_player_flag`), with no lock/master of its own.
Turning `feed` off always stops turret-feeding too.

**Tri-state activation** — a channel is effective for a player only if: the
global whole-mod switch is on, the channel's global master is on, the player
isn't admin-locked (whole-mod or per-channel), and the player's own toggle is
on. Reported as `effective` in `get_player_state`. Behavior flags inherit
their parent channel's whole chain plus their own preference.

**Watchdog** — auto-retires `collect` + `feed` (and transitively turret
feeding) once a force's science throughput passes `lbf-spm-threshold`.
Re-enabling masters via `set_active` does **not** re-arm it — only
`set_watchdog_enabled(true)` does.

## Functions

### `set_global_master(value)`

The "Everyone" On/Off switch. Stops/restores the mod for every player without
touching channel masters, locks, or preferences. Doesn't re-arm the watchdog.

```lua
remote.call('lazy-bastards-friend', 'set_global_master', false)
```

### `set_active(channel, value)` / `get_active(channel)`

Get/set a channel's global master. `channel` is `'collect'`, `'feed'`, or
`'appearance'`. Doesn't override per-player toggles/locks or re-arm the watchdog.

```lua
-- Stop collecting into inventories, leave feeding running:
remote.call('lazy-bastards-friend', 'set_active', 'collect', false)

if remote.call('lazy-bastards-friend', 'get_active', 'appearance') then ... end
```

### `lock_player(player_index, channel, locked)`

Admin lock on one channel: while locked, it's off for that player regardless
of their own toggle.

```lua
-- Griefer containment:
remote.call('lazy-bastards-friend', 'lock_player', 7, 'collect', true)
remote.call('lazy-bastards-friend', 'lock_player', 7, 'feed', true)
```

### `lock_player_master(player_index, locked)`

Admin lock on the whole mod for one player (preferences are kept, apply
again once unlocked). This is the admin GUI's per-player On/Off column.

```lua
remote.call('lazy-bastards-friend', 'lock_player_master', 7, true)
```

### `set_player_enabled(player_index, channel, enabled)`

Set the player's own preference toggle, as if they clicked it. No effect
while locked/master-off (the value is stored and applies once unlocked).

```lua
remote.call('lazy-bastards-friend', 'set_player_enabled', 1, 'feed', false)
```

### `get_player_state(player_index)` → `table`

```lua
{
  enabled   = { collect = true,  feed = true,  appearance = true },  -- own toggles
  locked    = { collect = false, feed = false, appearance = false }, -- admin locks
  locked_master = false,   -- whole-mod admin lock
  effective = { collect = true,  feed = true,  appearance = true },  -- what actually runs
  radius    = 16,
  shape     = 'circle',    -- 'circle' | 'square'
  flags     = {            -- see set_player_flag
    feed_fuel = true, feed_ingredients = true, feed_combat = true,
    feed_trash = false, feed_rebalance = true,
    collect_chests = false, collect_ground = false,
    appearance_summary = false, appearance_show_others_area = false,
    appearance_starvation = false, appearance_use_player_color = true,
  },
  reserves  = { ['coal'] = 50 },  -- item name -> protected minimum
}
```

Returned table is a copy — mutating it does nothing.

### `set_player_flag(player_index, flag, value)`

Set one behavior toggle, as if clicked in the panel. Flag names carry their
channel's prefix (`feed_`, `collect_`, `appearance_`):

| flag | default | |
|---|---|---|
| `feed_fuel` | `true` | top up burners with fuel |
| `feed_ingredients` | `true` | fill crafter/lab/furnace inputs |
| `feed_combat` | `true` | top up ammo-turrets — follows `feed`'s chain, no lock of its own |
| `feed_trash` | `false` | drain logistic trash into nearby chests (paused while `collect_chests` is on) |
| `feed_rebalance` | `true` | move surplus fuel/ingredients between over- and under-stocked machines |
| `collect_chests` | `false` | also empty chests (needs `lbf-allow-chest-collect` map setting) |
| `collect_ground` | `false` | also pick up items on the ground |
| `appearance_summary` | `false` | floating per-cycle transfer summary |
| `appearance_show_others_area` | `false` | also see every other player's area render |
| `appearance_starvation` | `false` | flash a red icon over starved machines |
| `appearance_use_player_color` | `true` | draw the area in the player's own color |

`appearance_fill` ("Fill area") is not a flag — it's the `appearance`
channel's own toggle, set via `set_active`/`set_player_enabled`/`lock_player`.

```lua
remote.call('lazy-bastards-friend', 'set_player_flag', 1, 'collect_chests', true)
```

### `set_player_radius(player_index, radius)`

Clamped to `lbf-min-radius`/`lbf-max-radius`. Updates the mirrored setting
and redraws the area.

```lua
remote.call('lazy-bastards-friend', 'set_player_radius', 1, 24)
```

### `set_player_reserve(player_index, item_name, count)`

Set (or clear with `nil`) the per-item minimum feeding never dips below.
Keyed by item name, applies across qualities.

```lua
remote.call('lazy-bastards-friend', 'set_player_reserve', 1, 'coal', 100)
remote.call('lazy-bastards-friend', 'set_player_reserve', 1, 'coal', nil) -- clear
```

### `get_state()` → `table`

```lua
{
  master        = true,
  active        = { collect = true, feed = true, appearance = true },
  auto_disabled = false,      -- true after the watchdog tripped
  watchdog      = 'armed',    -- 'armed' | 'tripped' | 'disabled' | 'idle'
  spm_threshold = 45,
}
```

`watchdog`: `armed` = counting toward retirement, `tripped` = auto-retired,
`disabled` = `lbf-watchdog-enabled` is off, `idle` = nothing left to stop.

### `set_spm_threshold(value)`

Set the `lbf-spm-threshold` map setting (use this instead of writing
`settings.global` directly — only the owning mod may). Resets the strike
debounce.

```lua
remote.call('lazy-bastards-friend', 'set_spm_threshold', 90)
```

### `set_watchdog_enabled(value)`

The watchdog's on/off switch. Turning it **on** also clears a tripped state
and re-arms — the only re-arm path after a trip.

```lua
remote.call('lazy-bastards-friend', 'set_watchdog_enabled', true)
```

### `get_spm(force)` → `double`

Science-per-minute the watchdog measures for `force` (name, index, or
`LuaForce`), summed over all surfaces.

```lua
game.print(remote.call('lazy-bastards-friend', 'get_spm', 'player'))
```

### `set_entity_excluded(player_index, unit_number, excluded)` / `is_entity_excluded(...)`

Exclude/include one entity from a player's raids. Takes a bare `unit_number`,
so it cannot register destruction cleanup for you — clear the exclusion
yourself if the entity might be destroyed while excluded.

```lua
remote.call('lazy-bastards-friend', 'set_entity_excluded', 1, furnace.unit_number, true)
if remote.call('lazy-bastards-friend', 'is_entity_excluded', 1, furnace.unit_number) then ... end
```

## Scenario example

Disable raiding on a protected surface; give donators a bigger radius:

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
