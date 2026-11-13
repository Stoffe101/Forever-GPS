# The map taint

The error, from BugSack on 2.1.0 beside Questie 12.6.2 and TomTom v4.4.0:

```
[ADDON_ACTION_BLOCKED] AddOn 'ForeverGPS' tried to call the protected function 'Button:SetPassThroughButtons()'.
MapCanvas_DataProviderBase.lua:290: CheckMouseButtonPassthrough
Blizzard_MapCanvas.lua:331: AcquirePin
QuestDataProvider.lua:194: AddQuest
QuestDataProvider.lua:134: CheckAddQuest
QuestDataProvider.lua:141: RefreshAllData
QuestDataProvider.lua:39
CallbackRegistry.lua:210: TriggerEvent
Blizzard_QuestSuperTracking.lua:59: CacheCurrentSuperTrackInfo
```

> **Status: fixed in the code, not proven in the game.** Every path below is closed in the code and held by tests in a stand-in client. Nobody has yet shown the error gone in the real client. [Check it yourself](#checking-it-in-the-game).

## What is known, and how

The game's UI source is public, and its line numbers match this stack exactly (`QuestDataProvider.lua:39`, `Blizzard_QuestSuperTracking.lua:59`, `MapCanvas_DataProviderBase.lua:290`), so the path below is read, not guessed. Which of the routes fired in the one reported session cannot be told from outside it. A taint log from the game would say.

| Claim | Basis |
| --- | --- |
| The chain from a super-track change to `SetPassThroughButtons` | Read in the game's public source |
| Quest pins refresh with the map closed, once it has been opened | Read: `QuestDataProvider:RegisterEvents` registers `Supertracking.OnChanged` and `UnregisterEvents` leaves it registered |
| `SUPER_TRACKING_CHANGED` runs inside the call that caused it, in the caller's taint | EasyFind observed it for the waypoint event and wrote it down. Community reports of this exact error describe the same. Not tested here |
| `UISpecialFrames` taints the game's window closing | EasyFind's own taint log, quoted in `Shared/Utils.lua` |
| An id written with `SetMapID` taints later readers | Follows from the taint rules and `RefreshAllData` reading `GetMapID()`. Not observed here |

## The routes

**1. A super-track change from addon code, the route in the stack.** `C_SuperTrack` setters and clearing a tracked waypoint fire `SUPER_TRACKING_CHANGED` synchronously. Blizzard's handler runs in the caller's taint, fires `Supertracking.OnChanged`, and quest pins refresh. In combat, `SetPassThroughButtons` is refused.

EasyFind already held these changes while the map was open, which looks like it should be enough. It is not, because **the refresh does not stop when the map closes.** The callback is registered when the map first shows and is never removed.

**2. The map turned from addon code.** `MapPreview` opened and turned the game's map. `WorldMapFrame.mapID` then holds a value written by addon code, and `RefreshAllData` reads it. So a later clean refresh, one with no setter of ours anywhere near it, can go tainted and be refused in combat. A combat check alone cannot help this route. The game's own quest changes reach that refresh.

**3. The map opened from addon code.** Pins built during that show are tainted for the session. Their mixin fields are read on every later refresh.

**4. `UISpecialFrames`.** Forever-GPS put three windows in it. That taints Blizzard's window closing for the session, which is not this stack but is the same kind of harm, and it was ours.

**5. Native pins.** EasyFind wrote alpha, mouse state and a field of its own onto pooled game pins. These are not known to have caused this error, but they had no reason to be there.

Pool internals turned out not to be a route: the game's frame pools keep them in secure containers.

## What changed

- **Forever-GPS no longer touches the game's map.** No `SetMapID`, no opening or closing. Showing a journey now opens the **route map** (`UI/RouteMap.lua`), a frame of our own that draws the same map art. It also works in a fight. A map the player opens by hand still shows the preview on whatever they turned it to.
- **One door for the game's waypoint and tracking.** Every change goes through `MapSearch.WaypointChange`, which holds it through a fight as well as an open map. A test fails if any vendored file changes them outside it.
- **Fewer changes.** A change that changes nothing is skipped. Steps of a journey move the waypoint rather than the tracking, and a waiting clear checks the waypoint is still ours, so it cannot take one the player dropped in the meantime.
- **Escape** uses EasyFind's temporary key binding rather than `UISpecialFrames`.
- **Native pins** are no longer written to. Where EasyFind's mark and the game's waypoint pin coincide, both now show.
- **EasyFind's own map panel** still turns the map on a click inside it, through one guarded door: never in a fight, never to the map already showing.

All vendored changes are counted edits in `tools/assemble.py`. The pins in `addons/` stay exact.

## What remains

**The beacon.** Lighting the game's in-world beacon needs `SetSuperTrackedUserWaypoint`, and no addon can make that call clean. It now happens out of combat, with the map closed, and only when it changes something, but after the map has been opened it still refreshes the quest pins in our name. A pin built by such a refresh would stay tainted. That is much narrower than before, but it is not nothing, so the beacon has a switch: **Settings, Map, Show the game's beacon in the world**. With it off, Forever-GPS changes no super-track at all, and navigation carries on with the HUD and minimap. Off is the clean test.

Other addons can cause this same error. The name in it is whichever addon's code tainted the path, and the map is shared. Questie and TomTom are both installed here. Since 2.1 anything from the vendored addons is reported as ForeverGPS too.

`/ef` map search can still open the game's map, as it always has, on an explicit action. Forever-GPS's own flows never do.

## Checking it in the game

Turn the log on, then reload:

```
/console taintLog 1
/reload
```

Level 1 records blocked actions, and 2 records every global write, which is much larger. Logs go to `Logs/taint.log` under `_forever_`. Turn it off with `/console taintLog 0`.

1. Enable BugGrabber and BugSack. Note what is already in the sack, then clear it.
2. `/fgps diag`. Note the `Game waypoint` line.
3. Open and close the map with M, to arm the callback.
4. Start a journey with several steps.
5. Fight something while walking it, past a step change if you can.
6. Accept and turn in a quest near the fight. Click a quest in the tracker to super-track it.
7. Press M in combat and close it again.
8. Stop the journey. Open **Show on map** from a plan, and step through its continents.
9. Fight again with the map open.
10. Look in BugSack, and in `Logs/taint.log` for `ForeverGPS`.

Then repeat with the beacon off.

| Result | Meaning |
| --- | --- |
| Nothing, beacon on | The fix holds as far as this session tested |
| Error with the beacon on, none with it off | The remaining route: the default should change to off |
| Error with the beacon off | Something else. The taint log's first `ForeverGPS` line names it, or shows it is another addon |

For a comparison, install 2.1 from `dist/` and run the same steps.
