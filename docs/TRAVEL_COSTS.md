# Travel costs

Every journey shows what it costs beside how long it takes. Two ways of planning, **Best value** and **Cheapest**, weigh money as well as time.

## Fares

- **Learned, not made up:** a flight master's map gives every fare from there for this character, discounts included. Each is kept per character, with the day it was seen.
- **Several flights:** a route with more than one adds them up.
- **A flight never priced:** estimated from this character's own fares per yard, and shown with `~`.
- **No fares seen at all:** a rough figure stands in, also shown with `~`, so Best value can still weigh a flight. The route says to open a flight master's map once to learn the real fares.
- **Free means free:** a route with no flight is shown as free. A missing fare is never read as free.
- **Not counted:** boats, trams and zeppelins are free here. Teleport reagents are not priced yet.

Money is kept in copper throughout.

## The ways

| Way | What it does |
| --- | --- |
| Fastest, Safer, Roads, Overland | As before. Each shows its price |
| Best value | Adds each flight's fare to its time, at the rate you set |
| Cheapest | The least money, but only within the extra time you allow |

Best value is planned like any other way: the route engine adds each flight's fare to its time while it searches. So it can find a tram, a boat or a walk that is worth more than the flight. It is not the fastest route with the flights taken out.

Finding the best route for one rate finds every route that some rate would make best. A full multi-criteria search would also find the few that no rate prefers, at several times the cost. It is not done, so the planner stays within its frame budget.

## What your time is worth

**Settings, Travel costs.** The rate is the money you would spend to save a minute:

| Choice | Rate |
| --- | --- |
| Save money | 20 copper a minute |
| Balanced | 1 silver a minute |
| Save time | 5 silver a minute |
| Custom | Your own |

At Balanced, a flight costing 8 silver must save more than 8 minutes before Best value takes it.

## Limits

- **Most extra time for a cheaper way:** 10 minutes by default. Cheapest is not offered past it, and never if it is more than half as long again as the fastest.
- **Least time a hearth must save:** 3 minutes by default. A hearth is free but uses its cooldown, so it must save at least this much before any way uses it. Set 0 to turn this off.

## The hearthstone

The route panel says when a plan uses your hearth: where it is bound, whether it is ready or how long until it is, and whether the landing is known.

- **Landing known:** learned from your last hearth after binding.
- **Not yet known:** the town's spot by the inn's name, until you have used it once.
- **Rebinding:** an old landing is dropped as soon as you bind elsewhere.

Nothing is ever cast for you.

## After a reroute

A reroute plans with the same way as before, so a route started as Best value stays Best value. If you take a paid flight that Best value did not choose, the route goes on from where you land. It never sends you back.
