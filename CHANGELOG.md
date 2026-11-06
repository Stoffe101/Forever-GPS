# Changelog

## 1.0.0 (first version, unreleased)

### Added

- **Search**: places, zones, NPCs, trainers, services, dungeons, raids, coordinates and your map pin, with zone, type, hostile marks and travel times. Searches for a kind of thing are ordered by travel time.
- **From Your Quests**: the quest log with progress, every unfinished objective selectable, spawn areas with the closest by travel time leading, turn-ins, and an honest message when no location is known. Works with Questie, and falls back to the game's marker without it.
- **Journey panel**: Fastest, Safer and Roads routes compared, identical ones merged; every step with its time and wait; risk labels with their reasons and limits; avoid toggles; favorites and recents.
- **HUD**: instruction, distance, time left, step count, next step and progress; an arrow following the walk; ride-aware; a one-click hearth; movable and scalable.
- Quest-aware routes that stop when the quest is abandoned or the objective finished.
- Optional TomTom mirroring, with exactly one arrow in use at a time.
- Obsidian, Glacier and Parchment themes.
- A one-column layout for small screens at large UI scales.
- `/fgps` commands, key bindings and `/fgps diag`.
- A private packaging script, pin verification, CI, regression tests and a fake client running the real stack.

### Changed in vendored code

See [docs/UPSTREAM.md](docs/UPSTREAM.md) for detail.

- EasyFind GPS: `N.SpotsOf` and `N.ReactionOf` added.
- EasyFind GPS: **fixed** `Jumps.ShopTip` leaving the walking grid at an unlimited drop height, which silently stopped off-route detection and could draw walks over lethal drops.
- EasyFind Questie: `isReady` and `questSpots` actions added.
