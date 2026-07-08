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

- **Channels** — the mod's three independent features, always addressed by
  string name:
  - `'collect'` — pull finished products / burnt results (and opt-in chest
    contents) from machines into the player's inventory.
  - `'feed'` — push fuel and ingredients from the player into machines (and
    opt-in, drain their trash slots into chests).
  - `'combat'` — keep turrets topped up with ammo.
- **Tri-state activation** — a channel actually runs for a player only if all
  three are true: the global master is on (`set_active`), the player is not
  admin-locked (`lock_player`), and the player's own toggle is on
  (`set_player_enabled`). The combined result is reported as `effective` in
  `get_player_state`.
- **Watchdog** — the mod retires Collect+Feed automatically once a force's
  science consumption passes the `lbf-spm-threshold` map setting. Re-enabling
  any master through `set_active(..., true)` re-arms it.

## Functions

### `set_active(channel, value)`

Set a global master switch. Turning a master **on** also clears the
auto-retired state and re-arms the SPM watchdog. Turning it on does *not*
override per-player toggles or admin locks.

| arg | type | |
|---|---|---|
| `channel` | `string` | `'collect'`, `'feed'` or `'combat'` |
| `value` | `boolean` | |

```lua
-- Retire the raid but keep turret feeding:
remote.call('lazy-bastards-friend', 'set_active', 'collect', false)
remote.call('lazy-bastards-friend', 'set_active', 'feed', false)
```

### `get_active(channel)` → `boolean`

Read a global master switch.

```lua
if remote.call('lazy-bastards-friend', 'get_active', 'combat') then ... end
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
  enabled   = { collect = true,  feed = true,  combat = true },  -- own toggles
  locked    = { collect = false, feed = false, combat = false }, -- admin locks
  effective = { collect = true,  feed = true,  combat = true },  -- what actually runs
  radius    = 16,          -- service radius, tiles (already clamped)
  shape     = 'circle',    -- 'circle' | 'square'
  flags     = {            -- behavior toggles (see set_player_flag)
    fuel = true, ingredients = true, chests = false, ground = false,
    trash = false, summary = false, show_others = false,
  },
  reserves  = { ['coal'] = 50 },  -- item name -> protected minimum
}
```

The returned table is a copy — mutating it does nothing.

### `set_player_flag(player_index, flag, value)`

Set one of the player's behavior toggles, exactly as if they clicked it in
their panel. Valid flag names:

| flag | default | |
|---|---|---|
| `'fuel'` | `true` | Feed channel tops up burners with fuel |
| `'ingredients'` | `true` | Feed channel fills machine inputs (recipes, smeltables, science packs) |
| `'chests'` | `false` | Collect channel also empties chests (needs the `lbf-allow-chest-take` map setting) |
| `'ground'` | `false` | Collect channel also picks up items on the ground |
| `'trash'` | `false` | Feed channel drains logistic trash slots into nearby chests (paused while `chests` is active) |
| `'summary'` | `false` | show a per-cycle floating summary of what was moved |
| `'show_others'` | `false` | the player's area render is visible to everyone |

```lua
-- Scenario hands out pre-configured chest raiding:
remote.call('lazy-bastards-friend', 'set_player_flag', 1, 'chests', true)
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
  active        = { collect = true, feed = true, combat = true }, -- masters
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

### `get_spm(force)` → `double`

The science-per-minute reading the watchdog uses for a force (the built-in
`science` production statistic, summed over all surfaces). `force` is a force
name, index, or LuaForce.

```lua
game.print(remote.call('lazy-bastards-friend', 'get_spm', 'player'))
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
