# Changelog

## 2.0.0 (unreleased, not yet tested in the game)

### Added

- **Map preview**: a journey on the world map before it starts, following the ground, with labeled rides, a focus on any step, and a fit and a return-to-player button. It starts nothing and touches no route under way. Across continents the legs stand apart, joined by marks, with no line through the world.
- **Search**: what players call things, `nearest` and `any`, spelling correction that says what it did, boats and zeppelins as places to go, and Questie's creatures and objects read at run time from the installed addon. A row for many places moves to the quickest, passing over enemy towns.
- **Quest browser**: filters, grouping by zone, status or distance, and an offer of what comes next when an objective is done, without touching any other route.
- **Trips and Quest Circuit**: up to eight stops ordered from real travel times, with turn-ins after what they are for, followed by EasyFind GPS's own multi-stop engine. Skip a stop, reorder, and finished objectives drop out.
- **Transport**: waiting, aboard and riding read differently, a departure shows only when a real ride has timed that loop, and a reroute says why, naming a ride that went elsewhere.
- **HUD 2.0**: compact, standard and detailed sizes, background opacity, text size, arrow style, the next turn, reduced motion, and hiding while riding. The arrow eases and the time left glides.
- **Settings** in eight groups, with sliders drawn in full.
- **Quick navigation** (`/fgps go`, a key binding), a **minimap button**, saved spots (`/fgps save`), a sanitized line to share (`/fgps share`), and a copyable report (`/fgps report`).
- **Comparison**: each way says how it differs in time, transport, walking and hazards, and ways that came out the same stop being offered as a choice.
- **Confidence**: Fully mapped, Partially estimated or Estimated, with no percentages.
- **Risk**: contested ground, drops and dangerous approaches named. Never a claim of safety from players.
- Golden-path and property tests, a Lua 5.1 syntax job, repository validation, and renders of every state at six screens.

### Fixed

See [docs/LIFECYCLE.md](docs/LIFECYCLE.md) for each with its effect.

- Safer routes losing their settings on start and after a reload, which stopped off-route detection.
- Trips losing their stops on a reroute, and doubling back round stops already reached.
- Starting while the other ways were still planning leaving the walking grid on the wrong settings.
- 1.0.0 writing EasyFind's arrow setting, and first run overriding existing EasyFind users. Both are undone, and what first run changes can be restored from Settings.
- News lines vanishing with the HUD at the end of a route.
- Slider thumbs left to the client.

### Changed in vendored code

See [docs/UPSTREAM.md](docs/UPSTREAM.md) for detail.

- EasyFind GPS: a route rebuilt keeps its stops and goes on from those still ahead.
- EasyFind: search rows carry every instance, not just the nearest.
- EasyFind Questie: a run-time index of Questie's creatures and objects, built in slices.

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
