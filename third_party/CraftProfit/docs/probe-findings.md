# Probe findings (WoW: Forever beta)

Filled in by hand after running `/cpp` commands in the game (Task 2). Build: ____ (from `/cpp locale`). Date: ____.
Status marks: ✅ measured in game · ⚠️ not measured · ❌ unusable.

## F1. Search type for reagents (`/cpp search 2772`, then `/cpp search <a weapon/armor itemID>`)
- Event received for a reagent: `COMMODITY_SEARCH_RESULTS_UPDATED` (arg1 = itemID) ✅ 2026-10-08, French client
- Event received for a piece of gear: `ITEM_SEARCH_RESULTS_UPDATED` (arg1 = itemKey table) ✅
- Fields on a result: commodity `unitPrice`, `quantity`; item `buyoutAmount`, `quantity` (`bidAmount` nil) ✅
- Latency from query to event: about 1 s per item in a queue. Zero-result search still fires the event: yes ✅ (`item results: 0`).
- Each search event arrives twice in a row (harmless; results identical).

## F2. Replicate rows (`/cpp replicate`, once per 15 min)
- Row layout matches (17 values then hasAll): yes ✅. 79,078 rows at 15:05:21, one scan.
- The event fires hundreds of times per scan (427 seen in one tail), so reads are debounced.
- For a stack row (count > 1): `buyout` is the **whole stack** ✅ → `AH.PER_UNIT_REPLICATE = false`. Evidence: spring water count 7 buyout 105 (15 each), linen bolt count 18 buyout 1476 (82 each); the scan median per unit matches the targeted search (bronze bar 323 vs 322, coarse grindstone 524 vs 524, item 11083 512 vs 512).
- Any `<SECRET>` fields: none ✅

## F3. Recipe API (`/cpp trade` with the blacksmithing window open and a recipe selected)
- Strategy A (`C_TradeSkillUI`) usable: yes / no — fields seen: ____
- Strategy B (classic `GetTradeSkill*`) usable: yes / no
- `relativeDifficulty` values for a known orange / yellow / green / grey recipe: ____ (expected 0 / 1 / 2 / 3)
- Reagent slot `reagentType` for ordinary reagents: ____ (expected `Enum.CraftingReagentType.Basic`)
- `quantityMin` / `quantityMax` / `outputItemID` present: ____

## F4. Selected recipe detection
- Which expression returns the selected recipeID while a recipe is highlighted: ____
- Does the profession window global exist before first opening (lazy-loaded)? ____

## F5. AH commission and deposit
- Measured 2026-10-08 from a sale mail (French client): 20 Wool Cloth at 1s each = 20s 00c "Prix de vente"; deposit returned +1s 32c; "Commission de l'HV" -1s 00c; received 20s 32c (2000 + 132 - 100 = 2032).
- Commission = 100 / 2000 = **5 %** of the total sale price, on top of which the deposit is refunded when the item sells. ✅ → `DB.DEFAULTS.cut = 0.05` stands.
- One data point, at a round amount: the rounding of the commission on other prices (floor / ceil / nearest) is not measured. The 8 hour deposit for 20 Wool Cloth was 1s 32c (not used by the addon: it is refunded on a sale).

## F6. Secret values
- `/cpp api` prints `issecretvalue` as `function`: yes / no
- Item names, recipe names and AH row fields that printed `<SECRET>`: ____

## F7. Enum values (printed by `/cpp api`)
- `Enum.TradeskillRelativeDifficulty`: ____
- `Enum.CraftingReagentType`: ____
- `Enum.AuctionHouseSortOrder` present: ____

## F8. Frames and locale
- AH frame global: `AuctionHouseFrame` / `AuctionFrame` — ____
- `GetLocale()`: ____ · `GetCoinTextureString(123456)`: ____
- `C_Item.GetItemInfo(2772)` fields (sellPrice, classID, bindType): ____

## F9. Magnifier icon of the AH search box (`/cpp icon`, auction house open, 2026-10)
- `AuctionHouseFrame.SearchBar.SearchBox.searchIcon` exists (the key is `searchIcon`; `SearchIcon` is nil).
- `searchIcon:GetAtlas()`: `common-search-magnifyingglass`; `GetTexture()`: `6725697` (a file id); `GetTexCoord()`: `0,0,0,1,1,0,1,1`.
- `C_Texture.GetAtlasInfo("common-search-magnifyingglass")`: found, 24 x 24 (file 6725697). `search-icon` and `auctionhouse-icon-search`: nil.
- Used by `Native.searchIcon` (`CraftProfit/UI/Native.lua`): when the atlas is unknown, it falls back to the AH search box icon measured here.

## F10. Native templates and atlases (`/cppn`, `/cppn list`, 2026-10-09, build 1.60.1.70291)
- Templates that create and render: `ButtonFrameTemplate`, `PortraitFrameTemplate`, `DefaultPanelTemplate`, `DefaultPanelFlatTemplate`, `BasicFrameTemplateWithInset`, `InsetFrameTemplate`, `NineSlicePanelTemplate`, `UIPanelButtonTemplate`, `UICheckButtonTemplate`, `InputBoxTemplate`, `SearchBoxTemplate`, `ScrollFrameTemplate`, `MinimalScrollBar`, `WowScrollBoxList`, `PanelTabButtonTemplate`, `MagicButtonTemplate`, `UIPanelCloseButton`, `TooltipBackdropTemplate`, `QuestLogBorderFrameTemplate`.
- Atlases that exist: `questlog-reward-top-frame` (307 x 51), `questlog-reward-header-top`, `questlog-reward-bottom`, `questlog-frame`, `friends-frame-toptexbg`, `friends-frame-bottomtexbg`, `friends-frame-infobg`, `common-framedivider`, `perks-divider-short`, `looting_itemcard_bg` and `looting_itemcard_stroke_normal` (298 x 76), `common-search-magnifyingglass` (24 x 24), `_UI-Frame-TopTileStreaks` (only with the leading underscore), `auctionhouse-rowstripe-1`, `auctionhouse-background-index`, `RedButton-Exit`, `common-dropdown-a-button`, `Options_ListExpand_Right`.
- Files served to addons: `Interface\FrameGeneral\UI-Background-Rock`, `Interface\FrameGeneral\UI-Background-Marble`, `Interface\QuestFrame\UI-QuestTitleHighlight`.
- `NineSlicePanelTemplate` created without a parent raises in its `OnLoad`: it reads the parent's `layoutType`. Create it with a parent (a template that holds a `NineSlice` child, such as `ButtonFrameTemplate`, is fine with a nil parent). A templated frame that could sit under a Blizzard panel is created with a nil parent, then `SetParent` (gamepad navigation trap); the insets of our own panels and tiles are created with their own frame as parent.
- From the client source (`Gethe/wow-ui-source`, branch `forever`): after `ButtonFrameTemplate_HideAttic`, `_HidePortrait` and `_HideButtonBar` (in that order) the inset runs from (9, -24) to (-6, 4); the title bar is 20 px; the close button is 24 px at TOPRIGHT (-2, 1) (Camelot override).
- Used by the native kit (`CraftProfit/UI/Native.lua`, `NativeCards.lua`, `NativeLists.lua`). To re-run: enable `probe/CraftProfitProbe`, `/cppn` toggles the showcase window, `/cppn list` prints every atlas, file and template above with `ok`, its size or `MISSING`; `/reload` writes the log to `CraftProfitProbe.lua` in the SavedVariables folder.

## F11: Money strings (measured 2026-10-10, `/cppn money`)

- `GetCoinTextureString` and `GetCoinText` do not exist on Forever. `GetMoneyString(copper)` does and returns the coin icons as texture escapes: `21|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t 29|T...UI-SilverIcon...|t 5|T...UI-CopperIcon...|t` (height 0 = the font height). `Controller.fmt` uses it and falls back to the plain `21g 29s 5c` text when it answers nothing.

## F12. Options window, minimap button and compartment (to measure in game) ⚠️

- Addon compartment: does the CraftProfit entry (TOC `AddonCompartmentFunc: CraftProfit_OnCompartmentClick`, `IconTexture: Interface\Icons\INV_Misc_Coin_01`) show on Forever's minimap? Does left click open the options and right click the pinned recipes window? ⚠️
- Minimap button icon: does `GetFileIDFromPath("Interface\Icons\INV_Misc_Coin_01")` return an id (the coin draws), or does the button fall back to `INV_Misc_QuestionMark`? ⚠️
- Minimap art: `Interface\Minimap\MiniMap-TrackingBorder` (ring), `UI-Minimap-Background`, `UI-Minimap-ZoomButton-Highlight` draw and line up with the 24 px background and 18 px icon, both anchored CENTER (0, 1) as LibDBIcon does? ⚠️

## F13. Search trace (measured 2026-10-11, `/cpp trace`)

Why: some searches end as "no listing" or "no answer" and a second click finds the price. The trace shows what the client did for each item.

How to run it:
1. Enable `probe/CraftProfitProbe` (version 0.8.0 or later) next to CraftProfit, open the auction house.
2. `/cpp clear`, then `/cpp trace on`. Nothing is printed in chat while it runs; each line goes to the probe's log.
3. Press **Refresh recipe** or **Refresh pinned** in CraftProfit (and, to compare, search an item by hand in the AH window). Note the status line at the end.
4. `/cpp trace off`, then `/reload` to write the log: `WTF/Account/<ACCOUNT>/SavedVariables/CraftProfitProbe.lua`, lines starting with `TRACE`.

Each line has the `GetTime()` stamp in seconds:
- `TRACE t SEND key <itemID>/<itemLevel> ready <true|false>`: every `C_AuctionHouse.SendSearchQuery` (from CraftProfit, the AH UI or another addon), with `IsThrottledMessageSystemReady()` at that instant.
- `TRACE t EVENT <event> key <itemID or itemID/itemLevel> results <n> ready <...>`: `COMMODITY_SEARCH_RESULTS_UPDATED`, `ITEM_SEARCH_RESULTS_UPDATED`, `ITEM_SEARCH_RESULTS_ADDED` (with the result count read at that instant), and `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` / `AUCTION_HOUSE_THROTTLED_MESSAGE_*` (sent, response received, queued, dropped). An event the client does not know is noted once at load as `trace: event rejected by client`.

What to look for, per item:
- How many result events arrive per search, and whether the first one says `results 0` while a later one (or `ITEM_SEARCH_RESULTS_ADDED`) brings the rows: CraftProfit currently reads the first event only.
- The gap between `SEND` and the first event for that item, against the 6 s timeout; items marked "no answer" with an event after 6 s mean the timeout is too short.
- `SEND` with `ready false`, `MESSAGE_QUEUED` or `MESSAGE_DROPPED`: the search was throttled; how long until `THROTTLED_SYSTEM_READY`.
- Whether gear (item keys with an item level) behaves differently from commodities.

Results (2026-10-11, build 1.60.1, French client, about one minute of **Refresh recipe** and **Refresh pinned**: 36 searches, 31 commodities and 5 gear item keys):
- **Every search was answered.** The first result event came 0.15 to 0.27 s after `SEND` (median 0.20 s), far below the 6 s timeout. No `MESSAGE_QUEUED` or `MESSAGE_DROPPED`.
- **The first event already holds the rows.** Its result count never changed on a later event: no "0 first, rows later" pattern, and no `ITEM_SEARCH_RESULTS_ADDED`.
- **Duplicate events.** 18 of 36 searches got a second, identical result event 0.13 to 0.41 s after the first: 16 of 31 commodity searches (`COMMODITY_SEARCH_RESULTS_UPDATED`) and 2 of 5 gear searches. The queue has moved on by then and ignores it, since it is not the current item.
- **Throttle.** `THROTTLED_MESSAGE_SENT` fires at each `SEND` (so `ready` reads false at that instant). `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` comes 0.37 to 0.39 s after the answer. CraftProfit's next `SEND` followed about 0.6 s after the previous one, which is roughly 6 s for 10 items.
- **One genuine empty result.** Item 250528 (gear) answered `ITEM_SEARCH_RESULTS_UPDATED` with `results 0`: nobody was selling it. That is the "no listing" case, not a missed answer.
- **What changed in CraftProfit.** Nothing was needed: it reads the first event, which is complete, and ignores the duplicate. The misses seen before this trace are not explained by the client's events in this sample. If they come back, trace again around them.

## F14. Chart primitives (to measure in game) ⚠️

Why: the history chart (price history step 2) is drawn from coloured textures on a plain frame. The `Line` object would add a line through the daily averages, but it is not assumed to work on Forever. The history's local days rely on `time(table)` (`History.dayOf`); if it misbehaves there, the code falls back to an estimate that is wrong only after the change hour of a daylight saving day.

How to run it:
1. Enable `probe/CraftProfitProbe` next to CraftProfit (the version from the commit that adds this entry or later).
2. `/cpp clear`, then `/cppn line`, then `/cppn time`. Each prints one verdict line in chat; the details go to the probe's log only, through the main probe's logger (`CraftProfitProbe_Log`, with its timestamps and `MAX_LOG` trimming).
3. `/reload` to write the log: `WTF/Account/<ACCOUNT>/SavedVariables/CraftProfitProbe.lua`, lines with `[CPP native] line` and `[CPP native] time`.

`/cppn line` opens a movable window `CPPLineProbe` (Escape closes it, `/cppn line` toggles it) with three drawings on a dark background: a fan of 5 coloured lines from one point (thickness 1 and 2 alternating), a yellow 7 point polyline, and 7 blue texture bars for comparison. Every call runs in `pcall`.
- Verdict: `lines: ok`, or `lines: FAILS <first error> (<n> failures, see the log)`.
- Log: `CreateLine is <type>`, `GetObjectType <type>` (expected `Line`), then one line per call: `SetThickness(1)`, `SetThickness(2)`, `SetColorTexture`, `SetStartPoint`, `SetEndPoint`, and the same for each fan and polyline segment.

What to look for:
- The verdict, and whether the lines **look right**: thin, sharp lines meeting at the fan's origin, and a polyline whose segments join without gaps. Take a screenshot.
- Whether thickness 1 and 2 are visibly different.
- Whether the lines draw over the texture layer as expected.

`/cppn time` checks six fixed timestamps: noon UTC on 15 June, 28 October and 28 March of the current and previous year (the same calendar date in any zone from UTC-11 to UTC+11). For each one it logs:
- `date("*t", ts)`: year, month, day, hour, minute, second, `wday`, `yday`, `isdst`;
- the UTC offset deduced from `date("*t")` and `date("!*t")` (no `time()` involved);
- `time(date("*t", ts)) - ts` (expected 0);
- `time{year, month, day, hour = 0}` of that date, its type, `noon - midnight` and the round trip `date("*t", midnight)`.

It also logs `time()`, `GetServerTime()` and `GetTime()` once.
- Verdict: `time(table): ok (6 dates, ...)` when every `time{...}` returns a number less than 25 hours before the noon timestamp that `date` maps back to the same date at 00:00; otherwise `time(table): FAILS (see the log)`.

What to look for:
- The verdict.
- Whether `isdst` changes between June and late October or late March. That shows whether the client follows the computer's daylight saving rules.
- Whether `time()` and `GetServerTime()` agree.

Checked outside the game only: the same code under plain LuaJIT (`os.date` / `os.time`) gives `time(table): ok` for Europe/Paris, America/Los_Angeles and Pacific/Kiritimati (UTC+14). Results in game: see below.

**Results in game (2026-10-12, build 1.60.1, French client, computer in Europe/Paris):**
- **`CreateLine` works.** `/cppn line` printed `lines: ok`: `CreateLine`, `SetStartPoint`, `SetEndPoint`, `SetThickness` (1 and 2) and `SetColorTexture` all succeeded, and the fan of five lines and the polyline of seven points drew correctly next to the seven texture bars (screenshot checked). `Chart.USE_LINES` may be switched on; the History window (step 3) draws bars and line together so the author can judge the look.
- **`time(table)` works.** `/cppn time` printed `time(table): ok (6 dates)`: `time{year,month,day,hour=0}` returns a number for every date, `date("*t", time(t))` round-trips to the same date at 00:00, and `time(date("*t", ts)) - ts` is 0. The client follows the computer's daylight saving rules: the offset deduced from `date("*t")` and `date("!*t")` is 7200 s in June and 3600 s in late October and March (late March 2026 is before the change on the 29th, so winter time), with `isdst` changing accordingly. `time()` and `GetServerTime()` agree to the second. The exact day computation of `History.dayOf` is therefore reliable on Forever; the estimate fallback stays as a safety net.
