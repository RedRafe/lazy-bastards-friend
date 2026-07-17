# Lazy Bastard's Friend

An early-game quality-of-life mod. While active, it periodically "raids" a radius
around each player — pulling finished products out of machines, feeding fuel and
ingredients into burners/crafters/labs, and keeping your turrets topped up with
ammo — so you never have to hand-feed a furnace line again. Skip the tedious part
of the early game and get back to building.

It automatically retires itself once your factory's science throughput passes a
configurable threshold (default 45 SPM), at which point real logistics should have
taken over. Admins can always re-enable it.

## Features

- **Collect** — pulls finished products, burnt fuel results, and (opt-in) chest or
  ground-item contents into your inventory.
- **Feed** — pushes fuel and recipe ingredients into burners, crafters, and labs in
  range. Furnaces without a recipe set get smeltable ore inferred automatically.
- **Combat** — keeps ammo-turrets and artillery topped up from your inventory.
- **Reserved items** — set per-item minimums the mod will never dip into when
  feeding machines or turrets; import them straight from a logistic group.
- **Area-of-effect display** — a configurable circle or square shows exactly what's
  in range, with adjustable radius, shape, color, and opacity.
- **Auto-retirement (SPM watchdog)** — stops itself once your factory is
  self-sufficient; the threshold and behavior are admin-configurable.
- **Multiplayer-aware** — overlapping players split collected items and share
  machines fairly, with no double-feeding or double-collecting.
- **Per-player controls** — every channel and behavior flag can be toggled
  individually from a settings panel anchored to the character screen, plus a
  toolbar shortcut for a quick on/off.
- **Admin panel** — global and per-player locks for every channel, watchdog status
  and threshold, live SPM readout, and a searchable player list.
- **Remote interface** — a full scripting API (`docs/API.md`) for other mods or
  scenarios to drive and query the mod's state.

## Settings

Radius bounds, the update period, chest-raiding permission, and the SPM watchdog
(enable + threshold) are server-configurable map settings. Everything else is a
per-player preference, editable from the in-game panel or mirrored mod settings.

## Links

- [Architecture](.vscode/ARCHITECTURE.md) — module layout and how the pieces fit together
- [Remote API](docs/API.md) — scripting interface for other mods/scenarios

---

*Join my [Discord](https://discord.gg/pq6bWs8KTY)*
