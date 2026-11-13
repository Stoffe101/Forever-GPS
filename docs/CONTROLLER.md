# Controller and Steam Deck

Forever-GPS 2.6 can be used with a controller alone: opening it, searching, choosing a result and a route, the route map, saved places, the Quest Explorer, trips, all five Professions views, lists, prices and every setting. Every button can be changed, by pressing the new one.

It is a controller mode for Forever-GPS's own window, not a combat controller addon. Outside the window, and always in combat, the controller is the game's.

**Status:** tested against a simulation of the client's controller input (below). **Not yet tested on a real controller or a Steam Deck.** The checklist at the end is for that.

## Using it

| Button (Xbox / PlayStation / Deck) | In the window |
| --- | --- |
| D-pad | Move the selection. Held, it repeats |
| A / ✕ | Select |
| B / ◯ | Back: closes the route map, the keyboard, a quest, the journey on a narrow window, the settings, then the window |
| X / ▢ | More: what a right-click does (a result's menu, delete on the keyboard) |
| Y / △ | Search, with the on-screen keyboard. On the Quest Explorer, its own search |
| LB / RB (L1 / R1) | Previous and next page: Search, Quests, Professions, Trip, Settings |
| LT / RT (L2 / R2) | Previous and next view on the page: search filters, Your Quests and Explorer, the Professions views, the settings groups |
| L3 | Show the journey |
| R3 | Open or close the route map |
| View / Share | Controller settings and help |
| Steam Deck L4 | Open or close Forever-GPS, from anywhere, if you allow it |
| Steam Deck L5 / R5 | Page up and down |
| Steam Deck R4 | Start navigation |

On the route map: the D-pad moves between the bar's buttons (next map along the route, the whole route, where you are, Start navigation, close) and the marks on the map, and A presses the one selected. LB and RB (or LT and RT) step through the route, X shows all of it, B or R3 closes the map and keeps the plan. The selection starts on Start navigation.

Left and right stay on the row you are on whenever there is something on it that way, and up and down keep to the column, the way television and console menus move ("beam" navigation). A test walks every page at 1920×1080 and 1280×800 pressing every direction from every control, about 4,600 presses, and fails on any control that cannot be reached or any move that leaves the row.

On the keyboard: A types, X deletes, Y searches (or accepts), B cancels and puts the text back. A search accepted from the keyboard runs at once and the selection lands on its first result.

The labels in the settings are the game's own button glyphs for the controller in use (Xbox, PlayStation or generic), from `GetBindingText`. Where the game has none, a short name is shown.

The first time a controller is used with the window open, a short introduction names the buttons as your profile has them. **Got it** skips it. It can be shown again from Settings, Controller.

### If LT and RT are Shift and Ctrl

The game's own controller settings can make LT, RT or other buttons act as Shift, Ctrl or Alt (`GamePadEmulateShift`, `GamePadEmulateCtrl`, `GamePadEmulateAlt`). Such a button does nothing alone, and its label says so, for example "LT (SHIFT)". Either give those actions other buttons, or use the button as a modifier: "LT + X" is a binding of its own.

## The game's Gamepad UI

WoW Forever has its own controller interface: Options, Gamepad, "Enable Gamepad UI". It is not ConsolePort or any addon: it is a set of Blizzard modules in the client, `Blizzard_Gamepad`, `Blizzard_GamepadActionBars`, `Blizzard_GamepadSharedUtility` (and `…Secure`), `Blizzard_GamepadSmartNavigation`, `Blizzard_GamepadSoftCursor` and `Blizzard_GamepadTargeting`, read in the Forever client's own UI code (build 1.60.1.70938, Gethe/wow-ui-source, branch `forever`).

### Why addons get "blocked from an action only available to the Blizzard UI"

What the evidence shows, with the uncertain parts marked:

- **The function blocked** is `SetPreferredGamepadInteractTarget()`. The client's API documentation marks it `HasRestrictions = true`: only Blizzard's own code may call it. `Blizzard_GamepadActionBars/MainActionBarFrame.lua` calls it from `UpdateInteractIcons`, at every soft target, target, equipment and combat change.
- **What it reads** is the Gamepad UI's binding stack (`InputBindingManager:IsOnlyCoreBindingSetActive()`). The same bookkeeping (`FrameControlsManager`, `SmartNavigation`) is written whenever a Blizzard menu, popup or panel is shown or hidden, and whenever a frame is made under an open panel (`SmartNavigation` post-hooks the global `CreateFrame`). It is written **inside whatever execution caused it**.
- **So**: when addon code causes one of those (adds an entry to a Blizzard menu with `Menu.ModifyMenu`, opens a menu with `MenuUtil`, shows a `StaticPopup`, calls `ShowUIPanel`/`HideUIPanel`/`ToggleWorldMap`, opens the bags, makes a frame on the open world map), the bookkeeping is written tainted. From then on, every `UpdateInteractIcons` is blocked and blamed on that addon: the error repeats until the addon is disabled or the UI reloaded.
- **Not new**: the gamepad code has not changed since build 70862 (7 November; a focus-handling tweak), and the same error is reported for Questie, EllesmereUI, RXPGuides, GatherLite, Polestar, Horizon Suite and others since September. It is a long-standing interaction between the Gamepad UI and addons, which also explains the same errors with bag and minimap addons.
- **Not proved for one report**: without Karfuss's own BugSack stack or taint log, which Forever-GPS action his errors came from is not known. The candidates in 2.6 were all of the kinds above, and all now stand aside (below).

### What Forever-GPS does while the Gamepad UI is on

Detected with `C_InputInterfaceStyle.GetCurrentStyle()`, and followed live through `INPUT_DEVICE_INTERFACE_TRANSITION`, so turning it on or off needs no reload.

| Stands aside | Instead |
| --- | --- |
| Forever-GPS's journey preview on the game's world map | Its own route map shows the journey (R3) |
| EasyFind GPS's route line on the game's world map, EasyFind's dungeon entrance pins and its map search tab | The minimap, the HUD and the route map still show the way |
| "Directions" in the game's quest log and tracker menus, "Make note" in unit menus | Directions from Forever-GPS's own quest pages |
| EasyFind's own context menus built with the game's menu system | Their fallbacks |
| Opening or closing the game's panels from addon code (quest log, world map, others) | The game's own buttons do it |
| The one-time "old EasyFind folders" popup | A line in the chat |

Forever-GPS's own window, its controller layer (override bindings only while its window is open, none in combat), its keyboard and its settings are unchanged: none of them writes anything the Gamepad UI reads. With keyboard and mouse, nothing at all changes.

### When it still happens: what to send

1. `/fgps pad`, then Ctrl+C: Gamepad UI state, controller, bindings Forever-GPS holds, the last 40 controller events, focus moves and every blocked action the game reported this session, with the function name. No character or realm names.
2. BugSack's full entry, with its stack.
3. Ideally the taint log: `/console taintLog 1` (or `11` for where taint began), `/reload`, reproduce, then send `World of Warcraft/_forever_/Logs/taint.log`. Turn it off afterwards with `/console taintLog 0`.

### Narrowing it down in the game

| | Setup | What it shows |
| --- | --- | --- |
| A | Gamepad UI on, every addon off | Blizzard's own baseline |
| B | A + Forever-GPS 2.5 | Whether 2.5 already did it |
| C | A + Forever-GPS 2.7 | This version |
| D | C with Settings, Controller, input set to "Never" | Whether its controller layer matters |
| E | C without Questie and TomTom | Whether they are part of it |
| F | A + Questie alone | Questie's own (known) reports |
| G | A + the bag addon that also errors | The same function? |
| H | C with keyboard and mouse, Gamepad UI off | The same actions, without the Gamepad UI |

## Customize Controls

Settings, Controller.

| Part | What it does |
| --- | --- |
| Layout | Automatic, Desktop or Handheld. Automatic is Handheld only when the screen is at most 1600 by 900 pixels **and** a controller is in use. A small screen alone does not mean a Steam Deck |
| Controller highlight and hints | When the controller is in use, always, or never |
| Profile | One chip per profile; New (from the Steam Deck or Xbox layout), Duplicate, Rename (with the on-screen keyboard), Delete. The last profile cannot be deleted |
| Use this profile for this character only | A per-character profile over the account's |
| Open Forever-GPS from anywhere | The one button that works outside the window, only with your consent, and never in combat. The game's own use of it is named. Consent is for that one button: choosing another button, switching profile or Undo never carries it over |
| Customize controls | Every action: its button, Change and Reset |
| Undo the last change | One step back, whatever it was |
| Start again from a layout | Steam Deck, Xbox, PlayStation or Minimal, with Undo |
| Feel | Left stick moves the selection (off by default), how soon a held direction repeats, highlight strength, a soft click, the navigation display on a handheld |

Profiles are account-wide. The account keeps one profile in use for the handheld layout and one for desktop, so a Deck used docked and undocked switches by itself.

### Changing a button

1. Select **Change** on the action.
2. Press the new button, or hold a modifier and press a button. B alone cancels (unless B is what is being changed), so does Escape, so does waiting 10 seconds.
3. If the button is taken:
   - another Forever-GPS action has it: **Swap**, **Replace** (the other is left without a button) or **Cancel**;
   - Move up, Move down, Select and Back always keep a button: a change that would leave one without is refused, and says why.
4. For **Open or close Forever-GPS** only, if the game itself uses the button (`GetBindingAction`), you are asked **before anything is saved or bound**: **Use it** (it opens Forever-GPS while playing, out of combat; your saved key bindings are untouched), **Only to close it**, **Choose another** or **Cancel**. Until you answer, the button stays the game's and the old one keeps working.

Not in combat: the game does not let addons listen to the controller then. A change asked for in combat says so; a fight starting while waiting for a press ends the wait.

A wait for a press, or a question about it, also ends cleanly when the window closes (as Cancel), when the controller is disconnected, or with a reload: nothing keeps listening to the keyboard or controller afterwards, and no unanswered choice is saved. Taking up the mouse does not end it: a keyboard key can still be the answer, and the mouse can click Cancel.

When a conflict cannot be known, nothing claims there is none. The game reports its own bindings; another addon's override bindings are not visible to Forever-GPS.

### Getting back to a working setup

- **Undo the last change**, **Reset** on one action, or **Start again from a layout**.
- The mouse and keyboard always work: nothing about them changes.
- `/fgps` opens the window whatever the controller does.
- The game's Key Bindings still list Forever-GPS's own entries, unchanged.

## Handheld

At 1280 by 800, as on a Steam Deck, with the Handheld layout:

- the window fills most of the screen, centred, one column, scaled up 12% for reading at arm's length;
- a line at the foot names the buttons that matter;
- the navigation display (HUD) is compact but wide enough for two lines, so what to do next is not cut off, unless you turn that off; the HUD settings say so while it applies. It can be put at the top, top left, right or bottom from the settings, with the controller.

Renders at 1280×800, drawn from the addon's real layout code in the stand-in client (not screenshots of the game): `docs/screenshots/2.6/` (introduction, home, keyboard, results, journey, route map, quests, professions, settings, waiting for a press, a clash, the HUD with news, Professions Skill up).

## Steam Deck

### Installing

WoW Forever runs on a Steam Deck through Proton, usually added to Steam as a non-Steam game. Where its files are depends on how it was installed, so Forever-GPS does not guess a path.

1. Switch to Desktop Mode.
2. Find the game's `_forever_` folder. In Konsole:
   ```bash
   find ~ /run/media -type d -name "_forever_" 2>/dev/null
   ```
   It is often under `~/.local/share/Steam/steamapps/compatdata/<number>/pfx/drive_c/`, or on an SD card under `/run/media/`.
3. Unzip the Forever-GPS package into `_forever_/Interface/AddOns/`, so that `ForeverGPS/` sits directly inside it.
4. Back in Gaming Mode, start the game and enable Forever-GPS in the AddOns list.

### Steam Input

The game sees what Steam Input sends. For Forever-GPS:

- Use a **gamepad** template (for example "Gamepad with Joystick Trackpad"), not a keyboard-and-mouse one, so the game sees the controller at all. In the game, the controller must be enabled (`/console GamePadEnable 1`, or the game's controller settings).
- **Back buttons (L4, L5, R4, R5):** the game has paddle buttons (`PADPADDLE1`–`4`), but whether Steam passes the Deck's back buttons through as those depends on the template. If they are mapped to other buttons or keys, bind those instead: Change, then press the back button.
- **Trackpads** are the mouse for the window, as for the rest of the game. The touchscreen clicks like a mouse.
- **Text:** Steam + X opens SteamOS's own keyboard, which types into Forever-GPS's boxes like a real keyboard. Forever-GPS's own keyboard (Y) needs nothing from Steam.

## How it works

| Part | File | What it does |
| --- | --- | --- |
| Input | `Core/Pad.lua` | Actions, layouts and profiles; takes the window's buttons while it is open; learns a binding; the left stick if wanted |
| Focus | `UI/Focus.lua` | What is selected, moving by direction across whatever can be clicked, item by item in long lists, and the highlight |
| Keyboard | `UI/PadKeyboard.lua` | The on-screen keyboard, for Forever-GPS's own boxes only |
| Settings | `UI/PadSettings.lua` | Settings, Controller; the dialogs; the introduction |
| Window | `UI/MainWindow.lua` | The handheld layout, page and view changes, the button hints |

**Taking the buttons.** While the window is open, each bound button is a priority override binding (`SetOverrideBindingClick`) to a hidden button named `ForeverGPSPad_<action>`. The hidden button hears both down and up, so a held direction repeats and stops on release. Closing the window clears them. A button already held when the window opens is bound only once released, so its release stays the game's. The player's saved key bindings are never written (`SetBinding` and `SaveBindings` are never called).

**Combat.** Two guards, for both binding owners: the window's buttons and the open-from-anywhere button. `PLAYER_REGEN_DISABLED` comes just before the combat lockdown, while protected changes are still allowed: both are cleared then. And each owner is a secure state handler (`SecureHandlerStateTemplate` with `RegisterStateDriver(owner, "fgpscombat", "[combat] 1; 0")`) whose restricted snippet calls `self:ClearBindings()` when combat starts. Nothing protected is called during combat; every button is the game's for the whole fight. Afterwards the open-from-anywhere button comes back, and the window's buttons too if it is still open.

**Focus.** Anything in the front window that can be clicked can be selected: buttons, chips, checks, list rows, edit boxes, sliders. A direction picks the nearest one that way, weighing distance along the direction against twice the distance across. Virtual lists are moved through item by item, scrolling as needed, so each of hundreds of items can be reached with only a screenful of rows. A selected item that changes or disappears (new prices, a narrower search) is found again by its key, or its nearest neighbour is taken. Surfaces stack above the window: the route map, the keyboard, a dialog. The top one gets the buttons.

**The keyboard** writes only to boxes named `ForeverGPS…`, never to chat or the game's own fields, and calls nothing protected.

## Verified APIs

From Blizzard's UI source of build 12.1.5.70783, the line WoW Forever 1.60.1.70790 is built on, and from the Forever client's own UI code (Gethe/wow-ui-source, branch `forever`, build 1.60.1.70938), which also holds the Gamepad UI. That source matches the client's own line for line where checked (docs/REALCLIENT.md).

| API | Where it is used by Blizzard | Used for |
| --- | --- | --- |
| `C_GamePad.IsEnabled`, `GetActiveDeviceID`, `GetDeviceMappedState` | `Blizzard_APIDocumentationGenerated/GamePadDocumentation.lua` | Whether the controller is on |
| `GAME_PAD_ACTIVE_CHANGED`, `GAME_PAD_CONNECTED`, `GAME_PAD_DISCONNECTED` | same | Whether it is the input in use |
| `Frame:EnableGamePadButton`, `OnGamePadButtonDown` | `Blizzard_Settings_Shared` key binding listener | Learning a binding |
| `Frame:EnableGamePadStick`, `OnGamePadStick` | `GamePadDocumentation.lua` | The optional left stick |
| `SetOverrideBindingClick`, `ClearOverrideBindings` | many | Taking the window's buttons |
| `GetBindingAction`, `GetBindingText(key, 1)` | the key bindings UI | The game's own use; glyphs |
| `GamePadEmulateShift` / `Ctrl` / `Alt` (cvars) | the controller settings | Which buttons are modifiers |
| `RegisterStateDriver`, `SecureHandlerStateTemplate` | `SecureStateDriver.lua`, `SecureHandlers.lua` | Clearing bindings in combat |
| `GetPhysicalScreenSize` | the graphics settings | The handheld layout |
| `IsKeyDown` | the key bindings UI | Buttons held as the window opens |
| `C_InputInterfaceStyle.GetCurrentStyle`, `INPUT_DEVICE_INTERFACE_TRANSITION` | Forever `Blizzard_SharedXML/Mainline/InputUtil.lua`, `InputInterfaceStyleDocumentation.lua` | Whether the game's Gamepad UI is on |
| `ADDON_ACTION_BLOCKED`, `ADDON_ACTION_FORBIDDEN` | events every client fires | Counted and named in `/fgps pad` |

### Not confirmed on Forever

- Whether a frame hearing the left stick (`EnableGamePadStick`) stops the character moving with it. So the stick is off by default.
- The game's default controller bindings. Conflicts are read at run time (`GetBindingAction`), not assumed.
- Whether Steam passes the Deck's back buttons as `PADPADDLE1`–`4`.

## Components evaluated

| Component | License | Decision |
| --- | --- | --- |
| Easy Controller - Forever (`cf2ad94`) | MIT for the part read; ConsolePort parts Artistic 2.0; dictionaries CC-BY-SA-4.0 | The way its config window takes buttons and learns them was followed (THIRD_PARTY.md). Nothing copied. Not required, not detected |
| ConsolePort | Artistic 2.0 | Its keyboard was read and not used: its terms for a Modified Version are more than a small keyboard warrants |
| Blizzard's gamepad UI | the game's | Left alone: Forever-GPS never replaces it |

Forever-GPS needs none of them. With Easy Controller or ConsolePort installed, each keeps its own bindings while Forever-GPS's window is closed; while it is open, Forever-GPS's priority bindings take the buttons it uses, and gives them back on close.

## Testing

`tests/test_controller.lua` (44 tests), `tests/test_gamepadui.lua` (8) and `tests/test_controller_feel.lua` drives the real addon through `tests/support/gamepad.lua`, a simulation of how the client delivers controller input:

- a frame hearing the controller gets the press first, then override bindings (priority first, then the latest), then the game's own binding;
- each owner keeps its own override bindings;
- the emulated modifiers turn LT + X into `SHIFT-PAD3`;
- protected calls in combat lockdown are refused and recorded, and `PLAYER_REGEN_DISABLED` comes just before the lockdown;
- the secure state handler drops its owner's bindings when combat starts.

The layout tests (`tests/test_ui.lua`) also run every page at 1280×800 in the handheld layout, at the default and the largest UI scale: nothing outside the window, no controls overlapping, no text painted over, the keyboard, every dialog, every Controller setting and the HUD in each place.

The tests press buttons; they do not call actions where a press can do it. They cover searching and starting a journey with buttons alone, typing on the keyboard, every page, a list of 400 items, items changing under the selection, the route map, remapping with swap, replace, cancel, timeout and Escape, the game's own use of a button, profiles, combat at every step, the handheld screen, and that the player's saved key bindings are never touched.

## Real-device checklist

On a Steam Deck (or a PC with a controller). Tick each:

1. [ ] The controller works in the game (`/console GamePadEnable 1`).
2. [ ] `/fgps` opens the window. A highlight appears when a button is pressed, and the introduction names the buttons.
3. [ ] D-pad moves through results; holding it repeats; A opens a result; B goes back and then closes.
4. [ ] Y opens the keyboard on the search; typing shows results; Y searches and lands on the first result.
5. [ ] LB/RB change page; LT/RT change view (or, if they are Shift/Ctrl in the game's settings, their labels say so).
6. [ ] R3 opens the route map; left/right step; B closes it, the plan kept.
7. [ ] Start a journey; close the window; the controller moves and fights as before.
8. [ ] With the window open, enter combat: the controller is the game's at once, no error. After combat, the window's buttons work again.
9. [ ] Settings, Controller: change Search to another button; it works at once after letting go. Undo.
10. [ ] Change a button to one another action has: Swap, Replace and Cancel do what they say.
11. [ ] The Steam Deck back buttons: what does Change hear when one is pressed? (Write it down: `PADPADDLE1`, another button, or a key.)
12. [ ] Allow L4 (or another button) to open Forever-GPS from anywhere; it opens and closes the window while playing.
13. [ ] The left stick option: does the character move while it is on and the window open?
14. [ ] Handheld layout at 1280×800: everything readable, nothing cut off, on every page.
15. [ ] Steam + X keyboard types into the search.
16. [ ] The game's own Key Bindings are unchanged after all of this.
17. [ ] `/fgps report` and BugSack: no errors, no blocked actions.

## Limitations

- Not tested on a real controller or Steam Deck yet.
- The left stick is off by default until checklist item 13 is answered.
- The Deck's back buttons depend on the Steam Input template.
- The window's buttons are Forever-GPS's only while it is open; a button pressed to open it from the world needs consent, and replaces the game's use of that button while Forever-GPS is loaded, out of combat only.
- The route map has no controller zoom; up shows all of the route and left/right step through it.
- Another addon's override bindings on the same buttons are not visible: while the window is open, Forever-GPS's priority bindings win.
