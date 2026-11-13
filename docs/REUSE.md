# Reusing open-source profession code

Forever-GPS 2.3 built its own professions, prices and crafting code. For 2.4, every MIT-licensed WoW Forever addon in the same field was read and compared before anything was rebuilt. The aim was one strong foundation, plus additions only where they were justified.

Nothing was run: each repository was downloaded at a pinned commit and read. Exact provenance is in [THIRD_PARTY.md](../THIRD_PARTY.md).

## The candidates

| | CraftProfit | profit | ForeverNet | ForeverProfit | Profiteer-Forever |
| --- | --- | --- | --- | --- | --- |
| Repository | github.com/Renaud-Sto/CraftProfit | github.com/ExcEssIv3/profit | github.com/thewoolfi/ForeverNet | github.com/konderziller/ForeverProfit | Not found |
| Commit read | `79e8eda` | `823413b` | `10a81d9` | `f778a9e` | |
| License | MIT, © 2026 Sto | MIT, © 2026 seth | MIT, © 2026 Andrew Woolfi | MIT, © 2026 KonDerZiller | Unknown |
| Forever client (interface 16001) | Yes | Yes | Yes | Yes | |
| Checked in the real client | **Yes.** A written record of in-game measurements (`docs/probe-findings.md`) | Data generated from the real client's tables, build 1.60.1.70790 | Partly. Its own notes say where it is unverified | Not documented | |
| Lua lines | 27,900 | 8,700, including 620 KB of data | 17,000 | 3,700 | |
| Test files | 41, on a fake client | None | 47 | None | |
| Dependencies | None | None | None | **Auctionator or TradeSkillMaster** | |
| Saved data | Per account and per character | Per account and per character | Per account, bounded (300 items, 500 offers, 90 days) | Per account | |
| Strongest part | The auction house scanner and targeted searches, measured in the game | Every recipe's skill-up thresholds, sources and reagents, from the client | Quantity-aware buying (`Market.Quote`), bounded and tested | | |
| Weakest part | Skill-up chances are its own estimates (orange 1, yellow 0.75, green 0.25) | No tests. Trainer skills only where its author recorded them | A large addon (networking, requests, themes). Its market code needs its own snapshot store | Needs another addon for prices | |

Profiteer-Forever is on CurseForge only. No source repository could be found, and its license could not be confirmed, so nothing of it is used.

## What was chosen, and why

**One foundation per job, never two.**

| Job | Taken from | Why | What changed |
| --- | --- | --- | --- |
| Auction house full scan | CraftProfit `AHAdapter.lua` | Its rules come from the real client: the scan event fires hundreds of times, a replicate row's buyout is the whole stack, and closing the window must end the scan | Written into Forever-GPS's `Core/Market.lua`, in its style and with its own store. It now waits for the row count to settle, adds a time limit for an unanswered scan, rereads once if rows arrived during the read, and keeps the price depth |
| Targeted price searches | CraftProfit `AHAdapter.lua` (`search`, `readCommodity`, `readItem`) | Measured answer times and duplicate events (F13). Searches wait for the client's throttle | Queued, with a time limit per item, and only for items the player asks about |
| Buying a quantity | ForeverNet `Market.Quote` | Cheapest-first along price tiers for commodities, and a bounded 0/1 covering knapsack for whole auctions | Works on Forever-GPS's compact price ladders. Merchant stock is added as an unlimited tier |
| Recipe thresholds, sources and reagents | profit `Data/Recipes.lua` | The client's own skill-up ranges (`TrivialSkillLineRankLow` and `High`) for 2,486 recipes, instead of guessing them | Packed into `Data/Recipes.lua` by `tools/recipes_import.py`, keyed by the client's skill line IDs. Names are dropped, since the game gives them |
| Merchant-sold reagents | profit `Data/Items.lua` and `tools/vendor_items.txt` | Which crafting reagents merchants sell without limit, and the client's listed price | Kept only for those items, and marked as listed until a merchant is opened |

**Kept from Forever-GPS 2.3:**

- Skill-up chance. Between yellow and grey it is `(grey - skill) / (grey - yellow)`, now using the client's real thresholds. CraftProfit's fixed chances are its own estimates.
- The profession window reading, profit maths, lists and trainer records, which were already tested here.

**Not used:**

- ForeverProfit, which needs Auctionator or TradeSkillMaster.
- ForeverNet's networking, requests, queue board and themes, which are outside a navigation addon.
- Every minimap button, slash command, global and saved variable of all of them. Nothing of theirs is registered.
- CraftProfit's chart and history views. Price history here has its own bounded store.

## Licenses of data inside MIT repositories

An MIT repository does not make every fact in it MIT.

- **profit's recipe and item data** are generated from tables in the WoW Forever client. The MIT license covers seth's generator, the file layout and his hand-made lists (merchant reagents, recorded trainer skills). The facts themselves are the game's and Blizzard's, from the client every player already has. They are used as facts about the game, as addons commonly do, and they are not claimed to be MIT or Forever-GPS's own.
- **CraftProfit's probe findings** are its author's measurements, under its MIT license.
- Nothing from Wowhead or any other site, and no Questie data, is included.

## Keeping up with upstream

`third_party/` holds the exact upstream files used, at the pinned commits, with their licenses. `python -I tools/third_party.py verify` checks each one against the hash recorded in `third_party/THIRD_PARTY.lock.json`. To take a newer upstream version:

1. Replace the file in `third_party/` and update its commit and hash in the lock file.
2. For recipe data, run `python -I tools/recipes_import.py`. The tests fail until the generated file matches.
3. For code, compare the old and new upstream file and carry the change into the adapted module by hand. The adapted modules name their source at the top.
