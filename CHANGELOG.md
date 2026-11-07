# Changelog

## 2.2.0 (unreleased, not yet tested in the game)

### Fixed

- **The map taint error, in the code.** `ADDON_ACTION_BLOCKED` on `Button:SetPassThroughButtons()`. The game's source shows quest pins refresh on a super-track change even with the map closed, once it has been opened, so waiting for the map to close protected nothing. Every change to the game's waypoint and tracking now goes through one door that also holds through a fight, and skips what changes nothing. **This has not been retested in the game.** [docs/TAINT.md](docs/TAINT.md) has the findings, what remains, and how to check.
- Forever-GPS's windows were in `UISpecialFrames`, which taints the game's window closing for the session. Escape now uses a temporary binding.
- Native pins are no longer written to.
- Carrying saved data over embedded all 1.36 MB of EasyFind's file, to load at every login, for 739 bytes that were wanted.

### Changed

- **The game's map is the player's.** Forever-GPS no longer opens or turns it. **Show on map** opens the **route map**, a window of our own that also works in a fight. A preview still draws over the game's map when you open it yourself.
- A planning slice with little budget left hands unpacking to the next one, which cuts the worst frames.

### Added

- **Quest Explorer:** **Find quests** beside Your quests. Search every quest Questie knows, browse by zone, filter by what this character can do, and see what can be picked up near you by travel time. A quest shows its status, starters, turn-in, requirements, what comes first, and its chain as a timeline. Directions go to the start or to the first missing prerequisite, with alternatives left to you. [docs/QUEST_EXPLORER.md](docs/QUEST_EXPLORER.md)
- **Quest circuits with pickups,** in the right order: picked up before it is worked on, and a prerequisite handed in before the next is picked up.
- A turn-in names what it opens, as an offer.
- A beacon switch: **Settings, Map, Show the game's beacon in the world**.
- `/fgps quest [name or id]`.
- `/fgps diag` separates time asked from work done, and says what filled planning's busiest frame and where search spent its time. It also counts changes made to the game's waypoint and those held back.

## 2.1.0 (not yet tested in the game when written, since run in the client)

### Changed

- **One folder.** Forever-GPS installs as a single `ForeverGPS` addon: 389 files and 25 MB, down from 14 folders, 456 files and 41 MB. EasyFind, EasyFind GPS and the Questie extension are built into it under `Vendor/`. The ten companion apps served EasyFind's search bar and are gone. Questie and TomTom stay separate and optional.
- **Planning stops doing work that cannot change the answer.** A way is settled without a plan when nothing reaches the place at all, when the fastest uses no transport for Overland to leave out, when it touches no dangerous ground for Safer to go around, or when the walk is too short to compare. Starting drops the rest of the comparison.
- The plan budget follows the frame rate, so a slow machine waits about as long as a fast one, and quick navigation starts on the first answer.
- EasyFind's search bar no longer loads its spells, toys, mounts and settings at login, since it stays hidden and navigation reads none of them.
- Reopening the window after starting a journey shows that journey, not the old search.

### Added

- **Home leads with what matters:** the journey under way, or one stopped short to pick up again, then suggestions: quests ready to hand in, things to do close by, flight paths to learn, the way back to your hearth.
- **Plan a circuit:** everything close by becomes a Quest Circuit in one click.
- **Saved trips,** and a trip list that survives a reload.
- **Instance quests** route to the entrance instead of stopping at "no route".
- **Journey summaries:** an arrival says how long it took, and journeys are logged against what was planned.
- **History:** places you go often rise above plain recents.
- **Search:** `my trainer`, `flights to learn`, more of what players call things, and coordinates as people write them (`56.1/47.2`, `56 47 Westfall`, `/way 56 47`).
- **Directions to your target,** with a key binding and `/fgps target`. `/fgps resume` picks up a stopped journey.
- **Map:** the ways not chosen show faintly under the chosen one, hovering a step lights it, and a journey across continents can be stepped through from the banner.
- **HUD:** outlined text for bright ground, and a sound on arrival.
- A **high contrast** theme.
- `/fgps diag` reports a plan's busiest frame beside its total. That total is time across many frames, not a freeze.
- `tools/install_local.py` and `tools/migrate_saved.py`, which move an install across without losing anything.

### Removed

- The settings for EasyFind's own search bar and for restoring it. There is no separate EasyFind left to restore.
- EasyFind's update notices, which would have told players to update something that is no longer installed separately.
- The ten companion apps: calculator, clipboard, snippets, quicklists, item and icon browsers, EasyFind's options, tutorial, settings search and guide. None served navigation.

### Fixed

- Reports and diagnostics no longer ask the game about addons that are not installed.
- Phrases typed in full, such as `auction house`, were doubled when read.
- Rides are labeled on the map, and marks keep their size as the map zooms.

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
