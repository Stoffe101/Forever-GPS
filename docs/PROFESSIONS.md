# Professions

The **Professions** tab has five views:

- **Overview:** what your character has.
- **Skill up:** the cheapest way to raise a profession.
- **Profit:** which recipes look worth making.
- **Lists:** what to make and buy.
- **Prices:** your auction house's prices.

It needs no other addon and no web service.

Forever-GPS is a navigation addon. This tab answers questions a player asks: which trainer can teach me, what will it cost, and what is worth making. It is not a levelling guide.

Parts of it come from three MIT-licensed addons: CraftProfit, ForeverNet and profit. [REUSE.md](REUSE.md) says why each was chosen, and [THIRD_PARTY.md](../THIRD_PARTY.md) says exactly what was taken.

## Where each figure comes from

| Figure | Source | How sure |
| --- | --- | --- |
| Professions, skill, cap | `GetProfessions`, read at login and on `SKILL_LINES_CHANGED` | From the game |
| Your recipes, reagents, output | The profession window, when you open it | From the game, for this character |
| Every recipe's skill ranges, and how it is learned | The client's own tables, via profit's data (`Data/Recipes.lua`) | From the game's files |
| A recipe's colour now | The profession window | From the game |
| Auction prices | Your own scans and searches of your own auction house | Says how old |
| Merchant prices | Merchants you have opened. Until then, the client's listed price for reagents merchants sell without limit | Seen, or "listed" |
| What a merchant pays | `GetItemInfo` | From the game |
| What a trainer teaches | That trainer's own window, once opened | From the game, for every character on the account |
| Other characters | What each one showed when last logged in | A copy, with its age |

Nothing comes from Wowhead or any website. No Questie data is used here.

## Skill-up chances

A craft always gives a point while orange, and never once grey. Between yellow and grey the chance is `(grey - skill) / (grey - yellow)`. That rule is long-standing but not confirmed on Forever.

Where a turning point comes from:

1. **The game's data.** For 2,486 recipes the client's own tables give the skill where each turns yellow and grey. Plans say "ranges from the game's data".
2. **What you have seen.** Each time you open the profession window, every recipe's colour is written down against your skill. If what you saw disagrees with the game's data, what you saw is believed, and the disagreement is noted.
3. **An estimate.** With neither of those, a band of 10 skill is assumed, and every plan that rests on it says "estimated".

## The cheapest way up

Choose a profession, a target, a mode and which recipes to use.

| Mode | A craft costs |
| --- | --- |
| Least spent | Its reagents, bought for the whole quantity the plan needs |
| After selling | That, less what the output sells for |
| Use my bags | That, with what is in your bags used first. Each reagent in your bags is used once, across the whole plan |

| Recipes | What is used |
| --- | --- |
| Known recipes only | Recipes this character has learned |
| Include recipes to learn | Also every recipe the game's data says can be learned from a trainer or a recipe item. A recipe item's price counts toward the plan. A trainer's recipe price is not known until its window is read, so it is left out of the total, and the plan says so |

**How the plan is found:**

- Each point costs a craft's reagents divided by its chance.
- Prices rise as a plan buys more of a reagent, your bags run out, and a recipe to learn costs something once. So the best recipe at each point is not always part of the cheapest plan.
- **A short climb is solved exactly:** with up to 4,096 possible plans, every one is tried.
- **A longer climb** starts from the cheapest recipe at each point. It then changes one point at a time, and two at a time for climbs up to 40 points, keeping each change that lowers the whole plan's total.
  - Its work is capped, and it runs a few milliseconds a frame, so the game does not pause.
  - In tests on 24 small cases with tiered prices and bags it matched the cheapest plan every time. That is a measurement, not a proof.

**What a plan shows:**

- **Crafts:** the expected number of crafts, and a safe number: enough 19 times in 20, given the chances.
- **To buy:** each reagent, the expected and safe quantity, what is in your bags, and what the safe quantity costs. When too few are listed, it says how many short.
- **Training:** where your cap is reached, with how many trainers are known to teach the next rank, and their level requirement and cost when their window gave it.
- **Learning:** each recipe to learn, from a recipe item or a trainer.
- **Gathering professions** have no crafting plan: they are raised by gathering.

## Profit

Each recipe shows these figures, kept apart:

| Figure | What it is |
| --- | --- |
| Cost | Its reagents at today's prices, bought for one craft |
| Spend now | The same, after what is in your bags |
| Sale | The output at today's lowest listing, less the house's 5% cut, if it sells |
| Merchant pays | What a merchant gives for the output: the floor, sold or not |
| Margin | Sale less cost. A hypothetical figure, not a sale |

- **Not counted or not known:**
  - Posted is not sold, and listings are not sales. The client does not say what sold, so there is no sales figure.
  - **Nobody else selling** means there is no sign anyone buys it.
  - Deposits are not counted. CraftProfit measured that a deposit is refunded when the item sells.
  - A recipe with any reagent unpriced, or too few listed, shows no figure rather than a smaller one.
- **Sorts:**
  - **Most profit**
  - **Best margin**
  - **Least outlay**
  - **Surest:** fresh prices with other sellers first
  - **Safest to make:** what a merchant gives back against the cost
- **Filters:**
  - **Priced**
  - **Makeable now**
  - **Others sell it**
  - **Shows a gain**
- **Trend:** when your scans have seen an item on several days, the row says whether its lowest listing is up, down or steady.

## Lists

Add recipes from Profit, or start a new list. A list merges the reagents of all its recipes and shows:

- **What you need:** what is in your bags, and what is in the bank. The bank is shown but not counted as in hand.
- **What is left to get:** priced for the whole quantity, with what comes from a merchant, and how many short when too few are listed.
- **Make or buy:** a reagent you can make is made when that is cheaper, and bought otherwise. Either way you can choose the other. What is made shows how many crafts and what each batch leaves over.
- **Other characters:** which of your other characters can make a reagent, as each last showed it.
- **Copy:** the list as plain text, one line per item still to get.
- **Refresh these prices:** with the auction house open, each reagent still to buy is searched on its own, for a fresher and fuller price than the last full scan.

Click a reagent to mark it bought, then collected. A mark you set is never changed by the addon. Lists are saved per character and survive reloads and updates.

## Prices

**A full scan:**

- Open the auction house, then press **Scan** under Prices. The server allows one about every 15 minutes, and the page says when the next is allowed.
- The client sends hundreds of updates for one scan. CraftProfit measured this in the game. The scan reads once the updates and the row count have both stopped for a second.
- **Never left running:**
  - No answer in 30 seconds: the scan ends and says so, and you can ask again a minute later.
  - Updates still arriving after a minute: what is there is read and marked partial.
  - Rows arriving during the read: read once more.
  - An empty answer forgets nothing.
- **Closing the auction house mid-read:** what was read is kept and marked partial. Everything else keeps its older price and age.
- **Another addon's scan:** read too, and it counts toward the server's wait.
- **What is kept per item:** the lowest unit buyout, a typical one (a quarter of the units are listed under it), the units listed, and the ten cheapest price tiers, so a quantity can be priced.

**Searches** for a list's reagents:

- One item at a time, sent only when the client's throttle allows.
- A 6-second limit per item. CraftProfit measured answers in under a third of a second.
- A second, identical answer is ignored.
- A search reads up to 100 listings. Fewer means the list was complete.

**Markets:**

- **Each auction house is its own market:** your realm, then your side's house or the neutral one. A price is only read from the market it came from.
- **Neutral houses are told apart by map**, so this works in any language: Stranglethorn Vale for Booty Bay, Tanaris for Gadgetzan, Winterspring for Everlook. The zone's name is used only when the map cannot say.

**Ages:** this hour reads as fresh, three days as recent, and older as old.

**History and alerts:**

- **History:** one point a day per item (its lowest listing and the units listed), for two weeks. Only items that matter to you are kept: reagents and outputs of your recipes, items on a list, items with an alert. At most 600 items per house.
- **Alerts:** `/fgps alert <item or link> <price>` tells you in chat when new prices list it at or under that price. It is checked only when new prices arrive, never on a timer. `/fgps alert <item> off` stops it, and `/fgps alerts` lists them.

**Never automatic:** nothing is bought, bid on or posted. No scan or search starts unless you press for it. No outside prices are imported.

## Trainers

A trainer's title says nothing about the ranks it teaches. When you open a trainer's window, what it offers is saved for every character on your account.

- **Kept by numbers:** the trainer's NPC ID, the profession's skill line (171 is Alchemy) and the rank's cap (225 is Expert). A trainer of Expert Alchemy is never taken for Expert Tailoring.
- **Both window shapes are read:**

  | Shape | What it shows | What a missing rank means |
  | --- | --- | --- |
  | Current | Only the next rank, as its own service | No next rank shown: this trainer does not teach it, as of that visit |
  | Classic | Every rank it teaches | A rank not listed is not taught |

- **A rank's cap comes from numbers:** the next cap above yours, or the skill the rank needs (Journeyman 50, Expert 125, Artisan 200). A rank word is used last, and a recipe whose name starts with one is not a rank.
- **Earlier visits add up:** a second visit keeps what the first learned unless it says otherwise.
- **Records from 2.3 are dropped:** they could not tell professions apart, so those trainers read as not visited.

**Searches:**

- `alchemy trainer`, `expert alchemy trainer`, `artisan blacksmithing` and `my profession trainers` put trainers in this order:
  1. Known to teach the rank, with its cost and whether you have learned it
  2. Not visited yet
  3. Known not to teach it
- Without a rank, the rank is your next one.
- Within each group, results are ordered by travel time.

## How it was tested

Everything here runs in the stand-in client:

- `test_professions.lua` (40)
- `test_crafting.lua` (20)
- `test_market.lua` (24)

These include a brute-force check of quantities against every subset of auctions, and of plans against every plan. None of it has run in the game.
