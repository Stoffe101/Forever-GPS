# Forever-GPS

Google Maps for Azeroth. A navigation addon for **World of Warcraft: Forever** that answers one question: *where do I need to go, and what is the best way to get there?*

Search for a destination, inspect the journey, start navigation, and follow the HUD. Boats, trams, zeppelins, flights, portals and your hearthstone are all considered, using what your character can actually use.

Forever-GPS is the product layer on top of [EasyFind](https://github.com/fallenguards/EasyFind) and [EasyFind GPS](https://github.com/fallenguards/EasyFind_GPS), used and modified with the author's written permission. See [NOTICE.md](NOTICE.md).

## What it does

- **Search** places, NPCs, trainers, services, dungeons, raids, boats and coordinates, the way people type them: `nearest mailbox`, `bank stormwind`, `Westfall 56 47`. Misspellings are corrected out loud. Results show zone, type, a travel time, and a warning for NPCs hostile to you, and searches for a kind of thing are ordered by travel time. With Questie installed, its creatures and objects are searched too.
- **Find quests** explores every quest Questie knows, in your log or not: search, browse by zone, what you can take now and near you, prerequisites, chains and directions to starters. See [docs/QUEST_EXPLORER.md](docs/QUEST_EXPLORER.md).
- **From Your Quests** turns the quest log into destinations. Every unfinished objective can be chosen, not just the first. Spawns are grouped into areas and the closest *by travel time* leads. With Questie installed it knows objective locations; without it, it falls back to the game's quest marker. When no reliable location is known it says so and offers no route.
- **Quest Circuit** puts several objectives on one trip, in a sensible order from real travel times.
- **Journey panel** compares ways of going and says how they differ, with each step, transport and wait, how sure the route is, a plain risk label, and toggles to avoid flights, boats, zeppelins, portals or your hearth.
- **Map preview** shows the journey on the world map before anything starts.
- **HUD** shows what to do now, distance, time left and the next step, in three sizes. At a dock it says it is waiting, and gives a departure only when a real ride has timed that boat. A hearth or teleport is offered as a button and never used for you.
- **Automatic progress** recognizes arrivals, reroutes when you wander, leads a ghost to its corpse, and survives a reload. A route for a quest stops if you abandon the quest or finish that objective.

Route lines on the world map and minimap, and the route's beacon, are EasyFind GPS's own.

Risk labels describe known hazards only: creatures by level, enemy guards, enemy towns, enemy transport, contested ground and drops. **They cannot see enemy players and promise nothing about them.**

## Install

See [docs/INSTALL.md](docs/INSTALL.md). In short:

```bash
python tools/package.py
```

The zip holds one folder, `ForeverGPS`. Unzip `dist/ForeverGPS-2.1.0-forever.zip` into `_forever_/Interface/AddOns`. Coming from 2.0, the old folders must go first: [INSTALL.md](docs/INSTALL.md) has a script for it. In game, `/fgps` opens it. The five-minute [first-run check](docs/FIRST_RUN.md) comes next.

## Using it

| Command | |
| --- | --- |
| `/fgps` | Open or close |
| `/fgps go [place]` | Quick navigation: type, Enter, go |
| `/fgps target` | Directions to your target |
| `/fgps resume` | Back to the journey you stopped |
| `/fgps quests` | From Your Quests |
| `/fgps trip` | The stops of a trip |
| `/fgps way [zone] <x> <y>` | Route to coordinates |
| `/fgps save [name]` | Keep this spot |
| `/fgps share` | A clean line to pass on the destination |
| `/fgps stop` | Stop navigation |
| `/fgps hud`, `/fgps hud unlock` | Show or hide the HUD, or move it |
| `/fgps diag` | Report the client, addons, API state and timings |
| `/fgps report` | The same as text to copy |
| `/fgps reset` | Reset window and HUD positions |

Key bindings are under Forever-GPS in the game's key binding settings. Alt-click the world map for directions to any spot.

## Repository

```
addons/ForeverGPS/         The product: search, quests, planner, journey, HUD
addons/EasyFind/           Vendored, with one declared patch
addons/EasyFind_GPS/       Vendored, with three declared patches
addons/EasyFind_Questie/   Vendored, with two declared patches
build/assembled/           What ships: one folder, put together by tools/assemble.py
tests/                     Forever-GPS's tests and the fake client
tools/                     Packaging, validation, pin verification, art, previews, baselines
docs/                      Install, architecture, lifecycle, design, performance, testing
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it fits together, and [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) for what it does not do yet.

## Development

```bash
python tools/run_tests.py
```

```bash
python tools/upstream.py verify
```

The first runs EasyFind's, EasyFind GPS's, the Questie extension's and Forever-GPS's suites. The second checks every vendored file against [UPSTREAM.lock.json](UPSTREAM.lock.json). Both need Lua 5.4 on the path; on Windows, run them from Git Bash.

```bash
lua tools/ui_preview.lua
```

That draws the real interface to `build/preview/*.html` at each target screen, from the real addon code. Run `python tools/art_png.py` once first for its icons.
