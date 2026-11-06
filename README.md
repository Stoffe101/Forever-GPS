# Forever-GPS

Google Maps for Azeroth. A navigation addon for **World of Warcraft: Forever** that answers one question: *where do I need to go, and what is the best way to get there?*

Search for a destination, inspect the journey, start navigation, and follow the HUD. Boats, trams, zeppelins, flights, portals and your hearthstone are all considered, using what your character can actually use.

Forever-GPS is the product layer on top of [EasyFind](https://github.com/fallenguards/EasyFind) and [EasyFind GPS](https://github.com/fallenguards/EasyFind_GPS), used and modified with the author's written permission. See [NOTICE.md](NOTICE.md).

## What it does

- **Search** places, NPCs, trainers, services, dungeons, raids and coordinates. Results show zone, type, a travel time, and a warning for NPCs hostile to you. "Any inn" style searches are ordered by travel time.
- **From Your Quests** turns the quest log into destinations. Every unfinished objective can be chosen, not just the first. Spawns are grouped into areas and the closest *by travel time* leads. With Questie installed it knows objective locations; without it, it falls back to the game's quest marker. When no reliable location is known it says so and offers no route.
- **Journey panel** compares Fastest, Safer and Roads routes, with each step, transport and wait, a plain risk label, and toggles to avoid flights, boats, zeppelins, portals or your hearth.
- **HUD** shows what to do now, distance, time left and the next step. On a ride it stops pointing and names the ride.
- **Automatic progress** recognizes arrivals, reroutes when you wander, leads a ghost to its corpse, and survives a reload. A route for a quest stops if you abandon the quest or finish that objective.

Route lines on the world map and minimap, and the route's beacon, are EasyFind GPS's own.

Risk labels describe known hazards only: creatures by level, enemy guards, enemy towns and enemy transport. **They cannot see enemy players and promise nothing about them.**

## Install

See [docs/INSTALL.md](docs/INSTALL.md). In short:

```bash
python tools/package.py
```

Then unzip `dist/ForeverGPS-1.0.0-forever.zip` into `_forever_/Interface/AddOns`. In game, `/fgps` opens it.

## Using it

| Command | |
| --- | --- |
| `/fgps` | Open or close |
| `/fgps quests` | From Your Quests |
| `/fgps way [zone] <x> <y>` | Route to coordinates |
| `/fgps stop` | Stop navigation |
| `/fgps hud`, `/fgps hud unlock` | Show or hide the HUD, or move it |
| `/fgps diag` | Report the client, addons and API state |
| `/fgps reset` | Reset window and HUD positions |

Key bindings are under Forever-GPS in the game's key binding settings. Alt-click the world map for directions to any spot.

## Repository

```
addons/ForeverGPS/         The product: search, quests, planner, journey, HUD
addons/EasyFind/           Vendored, byte-exact at its pin
addons/EasyFind_GPS/       Vendored, with two declared patches
addons/EasyFind_Questie/   Vendored, with one declared patch
tests/                     Forever-GPS's tests and the fake client
tools/                     Packaging, pin verification, art, UI previews
docs/                      Install, architecture, upstream, manual testing
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
