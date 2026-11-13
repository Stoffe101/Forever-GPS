# Design system

Every color and text size lives in `UI/Theme.lua`, and every widget in `UI/Kit.lua`. Nothing is drawn from Blizzard's frame art, so the look stays one thing beside any UI skin.

## Principles

1. **One thing leads.** The time and the primary button are what the eye finds first. Everything else steps back in size and color.
2. **Say what is known.** A word for how sure a route is, a real departure or none at all, "no reliable location" rather than a guess.
3. **Nothing moves without a reason.** Panels do not animate. The arrow eases, and the time left glides, because both report something changing. Reduce motion stops the easing.
4. **Every control earns its place.** A setting nothing reads does not get a control.

## Color

Each theme defines the same tokens, so widgets name a role, never a color.

| Token | Role |
| --- | --- |
| `window`, `raised`, `card`, `cardHover`, `field` | Surfaces, from furthest back to nearest |
| `line`, `lineStrong` | Edges and rules |
| `text`, `textDim`, `textFaint` | Three levels of text. `textFaint` is for what can be missed |
| `accent`, `accentHover`, `onAccent` | The one action, and selection |
| `route`, `routeSoft` | The journey under way |
| `good`, `warn`, `danger`, `dangerSoft` | Status. Always with words, never color alone |
| `hud`, `glyph` | The HUD's surface, icons at rest |

On the world map the preview walks in magenta, because nothing in the map's art is. It reads on snow, sand, forest and dark ground, and it can never be taken for the active route's blue. Marks carry a dark disc and a colored ring, and ride labels sit on a dark pill.

## Type

Inter, as EasyFind ships it, with the client's font for CJK locales.

| Style | Face | Size | Use |
| --- | --- | --- | --- |
| `display` | Bold | 22 | The time of a journey |
| `title` | Bold | 15 | The window's name |
| `heading` | Semibold | 13 | Row titles, the current instruction |
| `label` | Semibold | 12 | Buttons, short values |
| `body` | Regular | 12 | Steps, objectives |
| `small` | Regular | 11 | Secondary lines |
| `caption` | Semibold | 10 | Section headings, chips |

## Spacing

Panels pad 14, windows 12. Rows are 54 for a result, 60 for a quest, 32 or more for a step. Controls are 24 to 34 tall. Rounded corners are 6 on buttons, 8 on panels, 10 to 12 on windows, and half the height on chips.

## Components

| Component | Notes |
| --- | --- |
| `Kit.Button` | Primary, ghost, danger. An icon alone centers itself |
| `Kit.IconButton` | A bare glyph that lights under the cursor. Always has a tooltip |
| `Kit.Chip` | Sizes itself to its text. `Kit.FlowChips` wraps a row of them |
| `Kit.Check`, `Kit.Choice` | On or off, one of several |
| `Kit.Scale` | Slider drawn in full: track, fill, knob, value. Wheel and drag both work |
| `Kit.Bar` | Thin progress |
| `Kit.Menu` | A small popup, closed by clicking elsewhere |
| `List.New` | Builds only the rows that fit, of mixed heights |

## Layout

Sizes are in UI units, and a screen's units depend on its UI scale: the height in pixels over 768, times the scale, is pixels per unit. Default UIParent heights run from about 668 to 1200 units, and a UI scale addon can make UIParent as tall as the screen in pixels. So:

- The window prefers 880 by 580 and never exceeds the screen. Below 700 wide it shows one column and the journey takes turns with the list.
- Where UIParent is 1000 units tall or more, the window and HUD default to 125%, until the player chooses a size.
- The journey panel moves its extras out of the way below 400 tall, so steps always show.
- Over-constrained anchors are refused by the test client, which also reports them.

## Checking it

`tools/ui_preview.lua` draws every significant state from the real addon code at six screens, to `build/preview/`, 177 renders in all. `tools/shoot_previews.py` photographs them. These are renders in a stand-in client, not screenshots of the game. `tests/test_ui.lua` asserts that nothing leaves its window, that controls do not overlap, that labels fit, that no text is painted over, and that sliders have a knob on their track, across eleven screen setups.
