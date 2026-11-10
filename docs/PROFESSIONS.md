# Professions

The **Professions** tab shows what your character has, the cheapest way to raise a profession, which recipes look worth making, lists of what to make and buy, and your auction house's prices. It needs no other addon and no web service.

Forever-GPS is a navigation addon. This is a tool for questions a player asks: which trainer can teach me, what will it cost, and what is worth making. It is not a levelling guide.

## Where each figure comes from

| Figure | Source | How sure |
| --- | --- | --- |
| Professions, skill, cap | `GetProfessions`, read at login and on `SKILL_LINES_CHANGED` | From the game |
| Recipes, reagents, output | The profession window, when you open it | From the game, for this character |
| A recipe's colour now | The profession window | From the game |
| Where a colour changes | Written down each time a colour is seen at a skill | Firms up with use. Estimated until then, and marked as such |
| Auction prices | Your own scans of your own auction house | Says how old |
| Merchant prices | Merchants you have opened | From the game |
| What a merchant pays | `GetItemInfo` | From the game |
| What a trainer teaches | That trainer's own window, once opened | From the game, for every character on the account |

Nothing comes from another addon's data. QuestieDB is not used here, Questie has no recipe data, and nothing was copied from Wowhead or anywhere else.

## Skill-up chances

A craft always gives a point while orange and never once grey. Between yellow and grey the chance is `(grey - skill) / (grey - yellow)`. That rule is long-standing and is not confirmed on Forever.

The client says a known recipe's colour at your current skill, not the skills where it changes. Each time you open the profession window, every colour is written down against your skill, and the turning points narrow:

- Seen orange at 132: it turns yellow after 132.
- Seen yellow at 141: it turned yellow at 141 or earlier.

Where a point is not pinned down, a band of 10 skill is assumed, and every plan that rests on that says it is an estimate. Opening the window at a few skills makes the plans firmer.

## The cheapest way up

Choose a profession and a target. The plan picks, at each skill, the recipe whose expected cost per point (a craft's cost divided by its chance) is lowest. Each point stands alone, so this is the exact cheapest plan for the prices and chances it uses. It is only as good as those inputs.

| Mode | A craft costs |
| --- | --- |
| Least spent | The cheaper of a merchant and the auction house for each reagent |
| After selling | That, less what the output sells for |
| Use my bags | That, with reagents already in your bags counted as free |

- **Training** is added where the plan reaches your cap. Whether a trainer teaches the next rank sooner is the trainer's to say.
- **Recipes you have not learned** are left out. Where to learn one is not known reliably.
- **Gathering professions** have no crafting plan, because they are raised by gathering.

## Profit

**If it sells at today's lowest price:** a craft's output, at the lowest buyout listed now, less the auction house's 5% cut, or what a merchant pays if that is more. Reagents are costed at the cheaper of a merchant and the lowest buyout.

- Posted is not sold. **Nobody else selling** means there is no sign anyone buys it.
- Deposits are not counted, because the client does not say what they are.
- One scan says nothing about how much sells, so there is no sales-per-day figure.
- A recipe with any reagent unpriced shows no figure rather than a smaller one.

**Sorts:**

- **Most profit**
- **Best margin**
- **Least outlay**
- **Surest:** fresh prices with other sellers come first

## Lists

Add recipes from Profit, or start a new list. A list merges the reagents of all its recipes and shows:

- What you need
- What is in your bags, and what is in the bank. The bank is shown but not counted as in hand.
- What is left to get, and its price

A reagent you can make for less than it costs to buy is broken into its own reagents, up to four deep, never round a loop.

Click a reagent to mark it bought, then collected. A mark you set is never changed by the addon. Lists are saved per character and survive reloads and updates.

## Prices

- Open the auction house, then press **Scan** under Prices. The server allows a full scan about every 15 minutes, and the page says when the next is allowed.
- The listings are read a few milliseconds a frame, and only three figures per item are kept: the lowest unit buyout, a typical one (a quarter of the units are listed under it), and the units listed.
- Each auction house is its own market: your realm, then your side's house or the neutral one in Booty Bay, Gadgetzan or Everlook. A price is only read from the market it came from.
- **Ages:** this hour reads as fresh, three days as recent, and older as stale.
- **Never automatic:** nothing is bought, bid on or posted, and no scan starts unless you press Scan.
- **No outside prices:** an addon cannot reach the internet, and none are imported. AHledger and similar services are not used. An import could be added later, but only with their terms checked.

## Trainers

A trainer's title says nothing about the ranks it teaches. When you open a trainer's window, what it offers is saved for every character on your account.

A search such as `alchemy trainer` or `my profession trainers` then puts trainers in this order:

1. Known to teach your next rank, with its cost when the window gave one
2. Not visited yet
3. Known not to teach it

Within each group, results are ordered by travel time. At first every trainer is "not visited", so the list fills in as you play.

## How it was tested

Every part has tests in the stand-in client: 30 cases that can be worked out by hand, including a brute-force check of the plan's total. It has also been checked for layout on six screens. None of it has run in the game.
