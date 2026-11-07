# Quest Explorer

**From Your Quests** still shows the log. **Find quests**, beside it, shows every quest Questie knows, whether it is in the log or not.

Open it from the Quests tab, or with `/fgps quest [name or id]`. Normal search also lists a few quests that are not in your log, and they open here.

## What it does

- **Search** by name in whole or part, id, quest giver, or zone, or several of those at once. A near miss still finds. Quests for the other faction stay out unless **All known** is on.
- **Browse** the zone you are in, or pick another. The filters are Available, Coming up, My level, Chains, Repeatable, In my log, Completed and All known.
- **Near me** finds what you can pick up close by, ordered by real travel time, and can plan a circuit of them in one click.
- **Opening a quest** shows its status, where it starts and ends, what comes first, what it asks for, the chain, and what to do.
- **Directions** go to the start. For a locked quest they go to the first missing prerequisite. Where more than one quest would do, all of them are shown and none is chosen for you.
- **Show on map** marks the start, the objectives and the turn-in on the route map.
- A turn-in names what it opens, as an offer. Nothing is ever started for you, and a journey under way stays as it is until you start another.

## Where the data comes from

Everything is read from your installed Questie while the game runs, through one file, `Core/QuestDB.lua`. No quest data ships with Forever-GPS. It uses no network and no Wowhead. `QuestDB` checks that Questie looks as expected when it binds, so a changed Questie shows as "not available" rather than as wrong answers. Without Questie the page says so, and your own quests keep working.

## What a status means

Questie's `IsDoable` decides. There is one eligibility engine, and this only puts its answer into words.

| Status | Meaning |
| --- | --- |
| Available | Questie says this character can take it, and knows what starts it |
| Likely available | Questie says yes, but knows of nothing that starts it |
| In progress, Ready to turn in | In your log |
| From level N | Only your level stands in the way |
| Needs an earlier quest | A prerequisite is missing |
| Has a requirement to meet | Reputation, a profession, a spell |
| Not for this character | Race, class, faction, a quest that closes this one, an event that is not running |
| Completed | Turned in |
| Unknown | Questie is not ready, or has no record of it |

A status is Questie's reading of its data, not the game's. Only the quest giver can confirm it. Missing data is never read as available.

## Prerequisites

The rules follow `QuestieDB.IsDoable`, and a test compares the two across every combination of a small set.

| Field | Meaning |
| --- | --- |
| `preQuestSingle` | Any one of these turned in. Takes the place of `preQuestGroup` |
| `preQuestGroup` | All of these turned in. A positive id also counts if a quest exclusive to it is done. A negative id wants that exact quest |
| `parentQuest` | Must be in the log. Turned in does not count |
| `availableStartingWith` | In the log or turned in |
| `exclusiveTo` | Taking one closes the others |
| `breadcrumbs`, `breadcrumbForQuestId` | Optional quests that lead here, never required |

## Starters

| Starter | What is shown |
| --- | --- |
| A person | Their name. With several, the one with the shortest journey leads |
| An object | Called an object, because no one stands there |
| An item | Called an item. Only what Questie records as dropping it is offered, as where it comes from |
| None known | Says so, and offers no route |

Quests done inside an instance route to the entrance, as your own quests do.

## Measured on the installed database

QuestieDB 1.0.11 for Forever, read only. These figures come from a local script and nothing of the database is kept in this repository. The chain code was run over every quest on desktop Lua.

| Measure | Value |
| --- | --- |
| Quests | 5,233 |
| Started by a person, an object, an item, nothing known | 4,401, 314, 387, 180 |
| With several givers | 125 |
| `preQuestSingle`, `preQuestGroup` | 2,485, 82, never both on one quest |
| Quests in a true linear chain | 2,045 |
| Largest chain view | 108 quests in 30 rows |
| Longest way to a quest | 28 steps |
| Chains cut at the 120 limit | 0 |
| Views touching a cycle | 11, all from `1516` and `1519`, which list themselves and each other |
| Links to a quest it does not hold | 1, to `2955` |
| Whole database walked | 0.22 s, worst quest 1 ms |

The limits come from these: 120 quests in a view, 64 deep. "Part 3 of 7" only appears for a true line with nothing cut or unknown. Anything else shows as a branching chain with no number.

## Cost

Nothing is read until the window first opens. The index then takes about 3 ms a frame, and a status scan the same. Both use a few megabytes. A status changes on quests accepted, removed or turned in, on level, skills and reputation, and when Questie appears, never on a kill.

## Not verified

None of this has run in the game. See [MANUAL_TESTING.md](MANUAL_TESTING.md). Real Questie data has only been read offline. Status, `IsDoableVerbose`'s reasons and spawn lookups have only been run against a stand-in that follows Questie's rules.
