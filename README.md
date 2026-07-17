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

- **Collect** — pulls finished products and burnt fuel results out of machines,
  plus (opt-in) chest contents and ground-dropped items, into your inventory.
- **Feed** — pushes fuel, recipe ingredients, and ore into burners, crafters, and
  labs in range. Furnaces without a recipe set get smeltable ore inferred
  automatically; labs are fed only the packs your current research needs.
- **Combat** — keeps ammo turrets and artillery topped up from your inventory.
- **Rebalance** — moves surplus fuel/ingredients from over-stocked machines to
  under-stocked ones sharing the same item, even when you're carrying none to
  give — a coal-hoarding furnace can top off its coal-starved neighbor.
- **Trash drain** — empties your logistic trash slots into nearby chests
  (already holding the item, then requesting it, then any empty chest).
- **Vehicle support** — while driving, the serviced area follows your vehicle
  and its fuel tank gets topped up too. Always on, no setting needed.
- **Per-entity exclusion** — hover any machine and press a (unbound by default)
  hotkey to permanently exclude it from raids, independent of any channel.
- **Starvation feedback** — optional icons flash over machines that wanted an
  item you couldn't spare (red) or are already fully stocked (green).
- **Reserved items** — set per-item minimums the mod will never dip into when
  feeding machines or turrets; import them straight from a logistic group, or
  edit them from an in-panel slot grid.
- **Area-of-effect display** — a configurable circle or square shows exactly what's
  in range, with adjustable radius, shape, color, and opacity; optionally shown
  to other players too.
- **Auto-retirement (SPM watchdog)** — stops itself once your factory's science
  throughput passes a threshold; only an explicit admin action re-arms it.
- **Multiplayer-aware** — overlapping players split collected items and share
  machines fairly, with no double-feeding or double-collecting.
- **Per-player controls** — every channel and behavior flag can be toggled
  individually from a settings panel anchored to the character screen, plus a
  toolbar shortcut for a quick on/off.
- **Admin panel** (`/lbf-admin`) — a global master switch plus per-channel locks,
  watchdog on/off with live SPM readout and threshold, and a searchable,
  sortable player list with per-player On/Off and per-channel locks.
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
