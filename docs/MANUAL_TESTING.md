# Manual testing in game

**Nothing in this repository has been run in the WoW client.** Automated tests run the real addon code against a fake client. That proves logic and layout, not that the game agrees. This list covers what only the game can show.

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

Save that output. Expected: client `1.60.1`, interface `16001`, `EasyFind internals: all present`, `Game API: all 17 present`, and `Questie data: ready` if Questie is enabled. If anything says MISSING, stop there and send that output first, since most of what follows depends on it.

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

- [ ] 3440×1440, GUI scale 2
- [ ] 3440×1440, GUI scale 3
- [ ] 1920×1080, GUI scale 2
- [ ] 1920×1080, GUI scale 3

"Scale" was modelled as pixels per UI unit, so 1920×1080 at 3 leaves 640 by 360 units. If your GUI scale setting means something else, tell me what `/dump UIParent:GetSize()` and `/dump UIParent:GetEffectiveScale()` report.

For each:

- [ ] The window fits. On narrow screens it shows one column, with Back from the journey.
- [ ] No clipped text, overlapping controls or cut-off labels.
- [ ] Scrolling works with the wheel, and rows do not bleed past the list's edge.
- [ ] Tooltips stay on screen.
- [ ] The HUD fits, drags when unlocked, and its position survives a reload.
- [ ] Resize the window. Layout follows without a reload.

## 11. Living with it

- [ ] Run around a city with a route active and watch your frame rate. No hitching on starting a route or typing a search.
- [ ] `/fgps diag` memory line after an hour is reasonable.
- [ ] TomTom as the arrow: exactly one TomTom waypoint, gone at each ride and when stopped.
- [ ] No other addon's arrow or tracker conflicts, particularly with EllesmereUI's quest tracker and minimap skin.
