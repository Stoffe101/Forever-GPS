# What the real game showed

Forever-GPS 2.4 was the first version with professions to be used in the WoW Forever client (1.60.1, build 70790). Three problems were reported:

- the Lists page overlapped;
- Profit and Skill up never showed anything useful;
- prices needed a manual scan every time.

This page records what was found, from the player's own game files, read and not changed, and what 2.5 changes because of it.

## The evidence

| Source | What it said |
| --- | --- |
| BugSack (`!BugGrabber.lua`), session 36, 2.4 | `Core/Crafting.lua:72: attempt to call a nil value`, 14 times, while ranking recipes by profit. `UI/ProfessionsView.lua:328: attempt to call a nil value`, 5 times, while drawing the Skill up plan |
| The lines named | `GetItemCount(id)` and `GetItemInfo(row.id)` |
| The game's own UI code, build 12.1.5.70783 (the line Forever 1.60.1.70790 is built on) | No global `GetItemInfo`, `GetItemCount`, `GetItemCooldown` or `GetMerchantItemInfo`. It calls `C_Item.GetItemInfo`, `C_Item.GetItemCount`, `C_Container.GetItemCooldown` and `C_MerchantFrame.GetItemInfo` |
| The character's saved data | 759 recipes read from the profession window, 15 of them learned (6 Leatherworking, 5 Cooking, 3 First Aid, 1 Skinning). Every learned one had its output and reagents, and 14 of the 15 IDs are in the client's recipe data |
| The account's saved data | A full scan of 5,534 items, read when another addon (Auctionator, installed) asked for it. Merchant prices: none at all. The trainer window was the current shape. The two "trainers" kept were a class trainer (79 spells) and a pet trainer |
| BugSack, session 35, 2.2 | `Core/Journey.lua:203: attempt to get length of a nil value` when a quest was accepted. Also taint from Forever-GPS: blocked `SetPassThroughButtons` through the quest map pins, and `GetAuraDataByIndex` |
| Auctionator's code, installed | Calls `C_AuctionHouse.ReplicateItems()` by itself when the auction house opens (its autoscan), with no click |

## Root causes, and what changed

### Profit and Skill up never loaded

**Cause, confirmed:** the item functions 2.4 called do not exist in this client. Every profit figure, every plan's shopping list and every list row raised an error. The page then kept showing whatever it showed before, so it looked stuck.

**Why the tests missed it:** the stand-in client had the old globals, and its `C_Item.GetItemInfo` returned nothing. That is the opposite of the real client.

**2.5:**

- `Core/Compat.lua` asks `C_Item`, `C_Container` and `C_MerchantFrame` first, and the old names only where a client still has them.
- The stand-in client no longer has the old names.
- A static test fails if any file but `Compat.lua` calls them.
- Run against the 2.4 code, the new tests fail with `Crafting.lua:72: attempt to call a nil value (global 'GetItemCount')`, the same line and error as BugSack.

**Same cause, also fixed:** merchant prices were never learned. The code checked for `GetMerchantItemInfo`, found none, and quietly did nothing.

### Recipe reading

**Not the cause:** it worked in the game.

**Made sturdier anyway**, since it is not known whether the list-update event always follows the window opening:

- The window opening reads too.
- Many update events give one read.
- An empty list, or learned recipes without reagents, is read again up to 6 times, a second apart, and then left alone.
- A recipe the client's data knows gets that data's reagents until the window's arrive.
- `/fgps report` says which events came and what each read found.

### The Lists page overlapped

**Two causes in the row layout:**

1. Rows were measured at the list's full width but drawn 8 units narrower once the scrollbar showed. Text near a line break took one more line than its row had, and ran into the next row.
2. List rows had fixed heights of 44 or 30, whatever their text.

**Also seen in the renders:** a card's button could cover the first line of its text.

**2.5:**

- Every row is measured with the font, width and line limit it is drawn with.
- A list that scrolls is measured again at its narrower width.
- After drawing, each row checks its text's real height, and gets more room if the game's fonts need it. `/fgps report` counts those cases.
- A card's text starts below its button.
- A test checks every row on every Professions view at three screens, scrolled and not: each text inside its row, no two rows over each other, and no button over text.

**Not confirmed in the game:** whether these were the overlaps the player saw. The page also could not draw at all once a calculation failed, which the item-function fix removes.

### Endless "working it out"

**Cause:** a plan that raised an error, or never answered, left the page waiting.

**2.5:**

- A plan is planning, done, failed with its message, or stalled after 10 seconds without progress. The last two offer to try again.
- Planning shows how far it has got.
- A plan made before the recipes were read again, or before prices changed, is made again.

### Prices needed a click

**2.5:** opening an auction house decides by itself, after 3 seconds:

- A full scan when the server allows it and the prices are old enough. This is the default, and it can be set to "if older than an hour", "if older than a day" or off.
- Otherwise, searches for up to 20 items that matter now, one at a time: a list's reagents, alerts, and recipes' missing prices.
- A scan another addon starts in those 3 seconds is read instead.
- Auctionator's record of its last scan counts toward the server's 15-minute wait.
- The searches stop when the player searches the auction house.

### Smaller fixes from the same evidence

- Class and pet trainers are no longer kept as profession trainers.
- Accepting a quest no longer fails on a route without stops.

## Not yet confirmed in the game

| Change | How to confirm |
| --- | --- |
| Profit, Skill up and Lists draw | Open each. `/fgps report` shows "page errors 0" |
| No overlap | Look at Lists with a long list, then make the window narrower |
| Automatic scan | Open an auction house without touching anything. Prices, or `/fgps report`, says "full scan" within a few seconds, or why not |
| Merchant prices | Open a merchant that sells vials or thread, then check a list using them |
| Item names | A reagent never seen shows "Item 1234 (loading)" and then its name |

## Found but not fixed here

**The 2.2 taint in session 35.** The game blocked `SetPassThroughButtons` from Forever-GPS while it redrew the map's quest pins after the super-tracked quest changed, and aura reads were tainted. 2.2's protections were meant to stop exactly that. Session 36 (2.4) shows none, but the conditions may simply not have come up. It needs its own investigation with the taint log on (`/fgps` Settings, Advanced).
