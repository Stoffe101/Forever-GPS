# Manual testing in game

**Nothing in this repository has been run in the WoW client.** Automated tests run the real addon code against a fake client. That proves logic and layout, not that the game agrees. This list covers what only the game can show. Start with the five-minute [first-run check](FIRST_RUN.md).

## Before you start

Turn on Lua errors, and keep them on while testing:

```
/console scriptErrors 1
```

You already have BugSack and BugGrabber installed. `/bugsack` shows anything caught.

Then check the client and addons:

```
/fgps diag
```

Save that output. `/fgps report` gives the same as text to copy, with no character or realm name. Expected: client `1.60.1`, interface `16001`, `EasyFind internals: all present`, `Game API: all 28 present`, and `Questie data: ready` if Questie is enabled. If anything says MISSING, stop there and send that output first, since most of what follows depends on it.

These help if a route looks wrong:

```
/dump C_Map.GetBestMapForUnit("player")
```

```
/dump GetBuildInfo()
```

Screenshots of the panel and HUD are the most useful report.

## 1. First run

- [ ] `/fgps` opens the window with no errors, and no EasyFind tutorial or welcome appears.
- [ ] Text is in the Inter font, not the game's default.
- [ ] Rounded corners have no visible seams at your UI scale.
- [ ] Icons are crisp and tinted, not white squares or green boxes.
- [ ] The window drags by its header, resizes from its corner, and closes with Escape.
- [ ] Your key bindings appear under Forever-GPS in the key binding settings.

## 2. Stormwind to Auberdine

Alliance, in Stormwind.

- [ ] Search `auberdine`. A travel time appears on the result after a moment.
- [ ] The journey shows: go to the dock for the boat to Auberdine, board it, walk to Auberdine.
- [ ] Follow the arrow. It leads to the correct pier in **Stormwind Harbor**, the one for the direct boat.
- [ ] The HUD names the boat and its destination. A departure countdown appears once a crossing has been timed.
- [ ] Aboard, the HUD stops pointing and says to stay on board.
- [ ] Arriving in Auberdine advances to the last step with no input.
- [ ] Reaching the end shows Arrived, then the HUD goes away.

## 3. Ironforge to Darkshore

- [ ] With few flights known, the route is the tram to Stormwind, then the direct boat.
- [ ] Learn or use flights and compare. The engine should prefer the direct Stormwind boat over the much longer Menethil boat unless flights change the sums.
- [ ] A flight master you have not visited is never used as a flight's destination.
- [ ] After opening a flight master's map, routes use the newly learned nodes.

## 4. From Your Quests

With at least three quests, one with two unfinished objectives, and Questie enabled.

- [ ] The tab lists quests under zone headers with level, status and progress.
- [ ] Opening a quest with two unfinished objectives shows both, each with its own Directions.
- [ ] Each location line shows a zone and a time, and many spawns read as a number of areas.
- [ ] Directions on the *second* objective routes to it, not the first.
- [ ] The location button in the journey lists the other areas with their times.
- [ ] A finished quest offers its turn-in, naming the NPC.
- [ ] Objective progress in the list updates as you kill or collect.
- [ ] Finishing the objective you are heading to stops the route and says so.
- [ ] Abandoning the quest you are heading for stops the route and says so.
- [ ] Turning it in does not claim you abandoned it.
- [ ] Find a quest with no location (some escort or event quests). It says no reliable location is known, and offers no Directions.

Then disable Questie and repeat quickly:

- [ ] The tab still lists everything, with a note that Questie would add locations.
- [ ] Quests where the game has a marker still offer a route. No errors.

## 5. NPC selection

- [ ] Search `innkeeper`, `flight master`, `repair`, `bank`, `auction house`, `mailbox`. Sensible nearby results, ordered by travel time.
- [ ] Search your class's trainer, and a profession trainer.
- [ ] Search an NPC name that exists in two places. Both can be reached.
- [ ] Pick an NPC with several spawn areas. The location button lists them.
- [ ] As Horde, search `Marshal Dughan`. It is marked hostile and comes after friendly results.
- [ ] Search `deadmines` and `molten core`. The route ends at the entrance.
- [ ] Type `45 60`, then `Westfall 56 47`. Both offer a route. A made-up zone name offers nothing wrong.
- [ ] Place a pin on the world map. The home view offers it.
- [ ] Alt-click the world map. The HUD picks that route up too.

## 6. Off-route navigation

- [ ] During a walk, step a little off the line. Nothing rebuilds and the arrow stays calm.
- [ ] Wander far away. Within about 15 seconds the route rebuilds from where you are, once.
- [ ] Keep moving off-route for a minute. It does not flicker or rebuild constantly.
- [ ] The line on the world map and minimap follows roads and does not vanish after a reroute.
- [ ] **Check this one specifically:** this path depends on the `Jumps.lua` fix, so wander off a long walk a few minutes after starting a route.

## 7. Transport

- [ ] A flight step tells you the right flight master, and the HUD says where the flight goes.
- [ ] While flying, the HUD stops pointing and arrival advances the route.
- [ ] Deeprun Tram: boarding and arrival are recognized.
- [ ] A zeppelin as Horde, boarded at the right tower.
- [ ] A hearth step shows the Hearthstone on the HUD, and clicking it casts. In combat the button is gone and nothing errors.

## 8. Route options

- [ ] Fastest, Safer and Roads show different times where they differ, and read as "same as fastest" where they do not.
- [ ] As a low-level character, route across a dangerous zone. Safer avoids it and the risk label changes.
- [ ] As Horde, route through Stormwind. The label warns of guards.
- [ ] Hover the risk label. It lists reasons and says enemy players cannot be detected.
- [ ] Avoid toggles replan, and the same toggles appear in EasyFind GPS's own settings.

## 9. Reloads, death and combat

- [ ] `/reload` mid-journey. The route, step and HUD come back.
- [ ] Log out and in within two hours: same. After more than two hours: the route is gone.
- [ ] Die during a route. As a ghost you are led to your corpse, and after you rise the route carries on.
- [ ] Hearth or use a portal mid-route. It recovers.
- [ ] Open the window and move the HUD in combat. No errors, and no "action blocked" messages.

## 10. UI scaling

At each of these, check the home, results, journey, quests and settings views, and the HUD:

- [ ] 3440×1440, your usual setup
- [ ] 3440×1440, default UI scale
- [ ] 1920×1080, default UI scale
- [ ] 1920×1080, largest UI scale

In the game, UI units per pixel come from the UI scale: UIParent's height is 768 divided by that scale, unless a UI scale addon sets it. Your EllesmereUI setting of 0.5333 leaves UIParent at 3440 by 1440 units, one per pixel. The tests cover that, the default range, and 640 by 360 units as a worst case tighter than the game goes. To check what you have, `/dump UIParent:GetSize()` and `/dump UIParent:GetEffectiveScale()`.

For each:

- [ ] The window fits. On narrow screens it shows one column, with Back from the journey.
- [ ] No clipped text, overlapping controls or cut-off labels.
- [ ] Scrolling works with the wheel, and rows do not bleed past the list's edge.
- [ ] Tooltips stay on screen.
- [ ] The HUD fits, drags when unlocked, and its position survives a reload.
- [ ] The sliders in Settings show a knob you can drag, with the value beside them. The mouse wheel moves them too.
- [ ] On a tall interface the window and HUD open at 125%, until you choose a size.
- [ ] Resize the window. Layout follows without a reload.

## 11. New in 2.0

- [ ] **Map preview**: open a journey with the world map open. A magenta line follows the roads, with a labeled boat mark. Nothing starts. Read it over snow, sand, forest and dark ground if you can.
- [ ] Click a step in the panel. The map turns to it and picks it out. The fit and return buttons on the banner work.
- [ ] With a route under way, preview somewhere else. The HUD does not change, and closing the preview leaves the route as it was.
- [ ] **Waiting**: stand at a dock. The HUD says it is waiting and says the time is not known. After one ride on that boat, it should give a real departure.
- [ ] **Trip**: add three stops, press Best order, plan it, start it. Skip a stop from the panel.
- [ ] **Quick**: bind the key, press it, type, press Enter.
- [ ] **Quest filters**: each filter and grouping shows what it says.
- [ ] Finish an objective while heading to it. An offer appears with Show route, and no route starts by itself.
- [ ] **HUD sizes**, opacity, text size and arrow style in Settings, HUD.
- [ ] **Reduce motion**: the arrow steps rather than swings.

## 12. New in 2.1

- [ ] **One folder**: one Forever-GPS in the AddOns list, no EasyFind, no error at login, nothing about EasyFind in chat.
- [ ] Text uses Inter, and every icon and texture shows. A square of nothing means a path did not move with the code.
- [ ] Questie and TomTom are found, in Settings, Integrations.
- [ ] **Memory**: `/fgps diag` against 2.0's roughly 30 MB in total.
- [ ] **Planning**: long journeys answer sooner. Compare `planFrame` in `/fgps diag`, the busiest frame, with `plan`, the total.
- [ ] **Home**: under way, stopped, and suggestions as your character's situation changes.
- [ ] **Plan a circuit** with several objectives close by.
- [ ] **Instance quest**: an objective inside a dungeon routes to its door.
- [ ] **Search**: `my trainer`, `flights to learn`, `56 47 Westfall`.
- [ ] **Directions to target**: bind the key, target an NPC, press it.
- [ ] **Map**: alternatives under the line, hovering a step, the next-continent arrow on a boat journey.
- [ ] **Arrival**: the HUD says how long it took. Turn the sound on and listen for it.

## 13. New in 2.2

Check these first. The taint steps come before anything else, because a false pass there is the costliest mistake. [TAINT.md](TAINT.md) says how to read the result.

These quests are real, with ids and data read from the installed QuestieDB 1.0.11. Your character's own status decides what each shows.

| # | Quest | Why it is here |
| --- | --- | --- |
| 953 | The Fall of Ameth'Aran | Plain: Sentinel Tysha Moonblade, Darkshore, level 12 |
| 954 | Bashal'Aran | A chain that starts here, Thundris Windweaver |
| 990 | Trek to Ashenvale | Any one of 994 or 995, which close each other, after 993 |
| 217 | In Defense of the King's Lands | All of 263 and 267 |
| 163 | Raven Hill | A breadcrumb to 5, Jitters' Growling Gut |
| 45 | Discover Rolf's Fate | Starts at an object, A half-eaten body, after 37 |
| 123 | The Collector | Starts from an item, Gold Pickup Schedule |
| 109 | Report to Gryan Stoutmantle | Several givers |
| 167 | Oh Brother. . . | Done in the Deadmines |
| 794 | Burning Blade Medallion | Horde: an Alliance character should see it closed |
| 4604 | More Sparklematic Action | Links to 2955, which the database does not hold |
| 1516 | Call of Earth | Lists itself and 1519 as alternatives |

1. [ ] `/fgps diag`: `Forever-GPS 2.2.0`, `Questie data: ready`, and no `Game API MISSING`. Turn on `/console taintLog 1`, `/reload`, clear BugSack.
2. [ ] Press M to open and close the map. Start a journey with several steps. Fight something while walking it, past a step change if you can. The HUD keeps working, and the game's waypoint catches up when the fight ends.
3. [ ] Accept and turn in a quest, and click a tracked quest, near or during a fight. Press M in combat and close it.
4. [ ] Open a preview with **Show on map**. The **route map** opens with real map art, and the game's map stays shut. Step through continents with the arrow. Open it in a fight as well.
5. [ ] Press M with a preview up: it draws over the game's map, on whatever you turn it to.
6. [ ] BugSack and `Logs/taint.log` show nothing naming ForeverGPS. Note the `Game waypoint` line in `/fgps diag`.
7. [ ] **Settings, Map:** turn off **Show the game's beacon in the world** and repeat steps 2 and 3. Navigation carries on without it.
8. [ ] `/fgps quest 953`: status, level, Sentinel Tysha Moonblade as the start, travel time. **Directions** plans a route, and nothing starts until you start it.
9. [ ] `/fgps quest 990`: **What comes first** says any one of the two, and **Go to the first step** is not offered, because that choice is yours. Open 994: 995 is named as closed by taking it.
10. [ ] `/fgps quest 217`: both prerequisites listed. `/fgps quest 163`: its chain marks it as optional.
11. [ ] `/fgps quest 45`: **Starts at an object**. `/fgps quest 123`: **Starts from an item**, with what drops it. `/fgps quest 109`: the nearest giver by journey leads. `/fgps quest 167`: the route goes to the entrance.
12. [ ] `/fgps quest 794`: closed to the character, and no route offered. `/fgps quest 4604`: says a link is missing. `/fgps quest 1516`: says its links run in a circle, with no error.
13. [ ] **Find quests**, **Near me**: nearby pickups by travel time. **Plan a circuit**, then look it over before starting. Add a stop first and it stays.
14. [ ] With a journey running, open a quest and press **Directions**: your journey keeps running until you choose to start the other. Accept a quest you walked to: the walk ends and says so. Turn in a chain quest: the next is named and nothing starts.
15. [ ] `/reload` mid-journey and mid-fight. `/fgps report`, and send it with any error text. It has the timing lines: planning's busiest frame by part, and search by part.

## 14. New in 2.3

Everything here is new and untested in the game. Report anything that disagrees with what you see, with `/fgps report`.

1. [ ] **No EasyFind button.** Only the Forever-GPS button, on the minimap and in the addon list. `/fgps` opens the window. Check again after `/reload` and on another character.
2. [ ] **Another flight.** Start a journey that waits for a boat or uses your hearth. Take a flight instead. The HUD says you are flying and the route picks up where you land. After landing it plans from there by itself.
3. [ ] **A wrong flight.** On a planned flight, land somewhere else. It plans from the landing, without sending you back.
4. [ ] **Hearth instead.** Hearth while the plan says to walk or take a boat. It plans from the inn.
5. [ ] **Reload in the air.** Mid-flight, `/reload`. On landing it plans from there.
6. [ ] **Fares.** Open a flight master's map, then plan a journey that flies. The price shows without `~`. Before opening one, it shows with `~`.
7. [ ] **Best value.** Settings, Travel costs: choose Save money. Plan a journey where a flight competes with a tram, boat or walk. Best value shows its price and can differ from Fastest. The comparison says what it saves.
8. [ ] **Hearth status.** Plan a journey that uses your hearth. The route panel says where it is bound and when it is ready. Rebind at another inn: the old landing is gone.
9. [ ] **Professions.** The Overview shows your professions with skill, cap and next rank. Open your profession window once, then Skill up shows a plan and Profit lists your recipes.
10. [ ] **Prices.** Open the auction house, then Professions, Prices: Scan. It reads, then shows how many items. Scan again at once: it says when the server allows it.
11. [ ] **A trainer.** Open a profession trainer's window. Search `alchemy trainer` (your profession): that trainer says what it teaches, and one that teaches your next rank comes first.
12. [ ] **A list.** Add recipes from Profit to a list. Lists shows what is left to buy, with bags and bank apart. Mark one bought, then reload: the mark stays.
13. [ ] Repeat the taint check from section 13 with these in use. Nothing in BugSack names ForeverGPS.

## 15. New in 2.4

Everything here is new and untested in the game. Report anything that disagrees with what you see, with `/fgps report`.

1. [ ] **The report.** `/fgps report` has lines for Navigation, Prices and Trainer window. Paste it with any report below.
2. [ ] **A jump.** Start a journey, then hearth or teleport away. The HUD says "Recalculating from where you are now" and a new route appears within a second or two.
3. [ ] **A wrong flight.** Land somewhere else: "Recalculating from where you landed".
4. [ ] **From elsewhere.** Search `from Ironforge to Goldshire`. The search says "From Ironforge". Pick Goldshire: the route starts in Ironforge and says so. Start it: it waits until you are in Ironforge.
5. [ ] **Why this way.** A route's note says what it was chosen for: quickest of N ways, or what Best value saves.
6. [ ] **A trainer.** Open a profession trainer's window. `/fgps report` says "Trainer window: current shape" or "classic shape". Search `expert alchemy trainer` (your profession and next rank): that trainer is first and says "Teaches Expert Alchemy", or last with "Does not teach this rank".
7. [ ] **Another profession's trainer.** Open a trainer of a profession you do not have. Your own profession's search does not count it as teaching your rank.
8. [ ] **The scan.** Open the auction house, Professions, Prices: Scan. It says "Waiting for its answer", then "Receiving listings", then "Reading". It ends with a count. Close the window mid-scan once: it says what was kept.
9. [ ] **Refresh a list.** With a list and the auction house open, press "Refresh these prices". Each reagent is asked in turn and the prices update.
10. [ ] **Skill up.** Professions, Skill up: segments say "ranges from the game's data". Choose "Include recipes to learn": recipes to learn appear with "Learn ..." lines.
11. [ ] **Quantities.** A list of 20 of something whose reagent has few listed says "N more than are listed".
12. [ ] **Make or buy.** On a list with something you can make, choose the other way. It stays after `/reload`.
13. [ ] **Copy.** On a list, press Copy. The text has one line per item.
14. [ ] **Another character.** Log in to a second character with a profession, then back. Overview shows it under "Other characters (as last seen)" with its age.
15. [ ] **An alert.** `/fgps alert <a reagent> <a price above today's>`. Scan: chat says it is under your price, once.
16. [ ] Repeat the taint check from section 13. Nothing in BugSack names ForeverGPS.

## 16. 2.5 in the real game

The first things to check. Each is quick, and together they show whether 2.5 fixed what 2.4 got wrong. Before starting, empty BugSack.

1. [ ] `/fgps report`: the Items line says `info C_Item.GetItemInfo` and `merchant C_MerchantFrame.GetItemInfo`.
2. [ ] Open a profession window. Recipes load. The report's "Recipe reading" line says `last ok` with your recipe count.
3. [ ] Professions, Profit: your recipes are listed, unpriced ones with "No figure yet: ... has no price". Nothing is stuck.
4. [ ] Professions, Skill up: a plan appears, or a card saying how far it got and why. Never a lasting "working it out".
5. [ ] Professions, Lists: add a few recipes. No text overlaps. Make the window narrower: still none.
6. [ ] Open a merchant that sells vials or thread. A list using them shows "from a merchant".
7. [ ] Open an auction house and touch nothing. Within a few seconds, Prices says "Scanning by itself", or why not. Afterwards Profit shows figures.
8. [ ] Close and open it again at once: no second full scan. Prices says what it did instead.
9. [ ] Close the auction house mid-scan. Prices says what was kept. Nothing stays "scanning".
10. [ ] Search the auction house yourself while it searches items: it stops ("you are searching yourself").
11. [ ] Repeat 2 to 4 with another profession.
12. [ ] `/reload`. The Professions page opens where you left it, and prices and lists are still there.
13. [ ] BugSack: nothing names ForeverGPS. Then paste `/fgps report` with any report.

## 17. 2.6 with a controller

The full list is in [CONTROLLER.md](CONTROLLER.md), "Real-device checklist". The short version:

1. [ ] `/fgps`, then press the D-pad: a highlight, and the introduction.
2. [ ] Y, type a place, Y: the first result is selected. A, then start the journey.
3. [ ] With the window open, start a fight: the controller is the game's at once. BugSack stays empty.
4. [ ] Settings, Controller: change a button, Undo it.
5. [ ] The game's own Key Bindings are unchanged.

## 18. ForeverGPS.API v2 with HarvestMate Enhanced

Only with the `feature/public-api` build (see [INSTALL.md](INSTALL.md#the-api-branch-for-harvestmate-enhanced)) and HarvestMate Enhanced 0.3.0. None of this has been tried in the game yet. HME's own list is its `docs/MANUAL_TESTING.md`, items 37-56; these are the Forever-GPS side.

1. [ ] `/fgps diag`: `Game API: all 28 present` (the list now includes `C_Map.GetMapPosFromWorldPos` and `CreateVector2D`). In HME, `/hme diag`: `Forever-GPS: 2.7.0 (API v2); ... walking grid API yes; arrow hold yes`.
2. [ ] Start a journey with Forever-GPS. In HME at a farm, press Guide me here: Forever-GPS's HUD arrow, EasyFind's character arrow, the TomTom waypoint and the beacon's edge arrow all go; the HUD keeps its steps; the journey keeps running. Give arrow back: they come back as you had them.
3. [ ] With a hold standing, start a new journey yourself: Forever-GPS's arrow comes back at once (your newest choice leads). `/reload` with a hold: Forever-GPS's arrow is back after the reload.
4. [ ] Let HME plan a 100-stop Mining loop in a hilly zone. Watch the frame rate while the legs are walked (about half a minute to a few minutes): no hitches; Forever-GPS's own route planning, started meanwhile, is not slowed noticeably and its route is unchanged; the walking grid's settings (roads, danger, drop limit) are unchanged afterwards.
5. [ ] Enter combat while HME is walking legs: no new walking starts until the fight is over.
6. [ ] HME's "bags nearly full" Do it: the journey to the nearest vendor opens, not started; you press Go. Never an enemy town's vendor.
7. [ ] No new BugSack errors and no `ADDON_ACTION_BLOCKED` with `/console taintLog 1`.

## 19. Living with it

- [ ] Run around a city with a route active and watch your frame rate. No hitching on starting a route or typing a search.
- [ ] `/fgps diag` memory line after an hour is reasonable.
- [ ] TomTom as the arrow: exactly one TomTom waypoint, gone at each ride and when stopped.
- [ ] No other addon's arrow or tracker conflicts, particularly with EllesmereUI's quest tracker and minimap skin.
