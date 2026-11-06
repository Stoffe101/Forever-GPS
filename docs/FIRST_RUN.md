# First-run smoke check

Five minutes in the game, before the [full checklist](MANUAL_TESTING.md). Stop at the first thing that fails and send what you have.

**Nothing in this repository has been run in the WoW client.** This is where that starts.

## Set up

```
/console scriptErrors 1
```

```
/fgps report
```

Press Ctrl-C and keep the text. It holds no character or realm name.

- [ ] The first lines read `[ok] Route engine ready`. A `[note]` about the data's build is expected. Any `[broken]` line: stop and send the report.

## The checks

1. **Opens.** `/fgps`. The window appears with Search, From Your Quests and Trip across the top.
2. **Finds.** Type `auberdine`. A row appears within a moment, with a time beside it.
3. **Plans.** Click it. The journey shows a time, steps joined by a line, and a label saying how sure it is.
4. **Shows.** Click the map button beside Start. The world map opens with a magenta line and a labeled boat mark. Nothing has started yet.
5. **Goes.** Click Start navigation. The HUD appears and its arrow turns as you turn.
6. **Stops.** Click the HUD's small x. The route goes. No error appears.
7. **Quests.** `/fgps quests`. With a quest in your log, open it and check the objective has a place or says why not.
8. **Quick.** `/fgps go mailbox`, then Enter. Navigation starts with the window closed. Then `/fgps stop`.

## Send back

- [ ] The report from above.
- [ ] Anything from `/bugsack`, if you have it.
- [ ] A screenshot of the journey panel and of the HUD.
- [ ] Where it failed, or that all eight passed.

## Status words

When reporting anything, please use these:

| Word | Meaning |
| --- | --- |
| **Works** | Did what it says |
| **Limited** | Works, with less than it should |
| **Wrong** | Works, and gives a wrong answer |
| **Broken** | Raises an error, or does nothing |
| **Not checked** | You did not get to it |
