# Chests and potions

Code: `Potion` (`heal`, `strength`, `fromRoll`, `strengthFromRoll`, `label`, `price`), `Game.randomPotion`, `Game.openChest` (one chest roll into the inventory, returns a `ChestLoot`), the `.chest` branch of `Game.step`, `Game.drink`, the `*_chance` and `*_turns` constants in `src/root.zig`.

## What a chest holds

`openChest` is also used by the clear reward (chest rolls for killing every monster on a level, see [monsters.md](monsters.md)).

A chest (25% of item spots, see [levels.md](levels.md)) holds **a potion or gold, never both** (a user rule). Rolled when it is opened:

1. `chest_potion_chance` (**85%**, a user choice): a potion. Otherwise 20-50 gold (`chest_gold_min`..`chest_gold_max`), stored in `Game.chest_gold`.
2. Potion kind (`randomPotion`, also used for the [shop](shop.md)'s items), one roll in 0..99, in this order:

| Roll | Kind | Constant |
|---|---|---|
| 0-9 | time stop | `time_stop_chance` 10 |
| 10-24 | speed | `speed_chance` 15 |
| 25-39 | strength (size from `strengthFromRoll`) | `strength_chance` 15 |
| 40-49 | vision | `vision_chance` 10 |
| 50-59 | invisibility | `invisibility_chance` 10 (taken from health, a user choice) |
| 60-69 | mystery | `mystery_chance` 10 (taken from health, a user choice) |
| 70-99 | health (size from `fromRoll`) | the rest, 30 |

3. Sizes (health and strength): small 50%, medium 35%, large 15%.

Overall per chest: gold 15%, health 25.5% (small 12.75, medium 8.93, large 3.83), strength 12.75%, speed 12.75%, time stop 8.5%, vision 8.5%, invisibility 8.5%, mystery 8.5%.

The result is stored in `Game.chest_potion` (or `Game.chest_gold`) for that turn; `render` appends "(<label>)" or "(+N gold)". Use `Potion.label()` for names, not `@tagName`. Shop prices: `Potion.price()` (see [shop.md](shop.md)).

Colors (`Potion.color()`, used for the shop's `!` and the names on the inventory screen): health green (`ansi_green`), strength brown (`ansi_brown`, 256-color 130), time stop yellow (`ansi_yellow`), vision purple (`ansi_purple`, 256-color 129), speed blue (`ansi_blue`), mystery white (`ansi_white`, my pick, not asked), invisibility gray (`ansi_invisible`, 256-color 244, my pick, not asked). The others are user choices.

## Potion kinds

`Potion.count` is 11. Single kinds have no sizes (a user rule for time stop; the same for speed, vision, invisibility and mystery). `drink` handles the inventory and the full-HP refusal; `applyPotion` applies an effect (also used by a good mystery).

| Kind | Effect | Duration | Drinking again |
|---|---|---|---|
| `small/medium/large` | +1/+3/+5 HP (`heal()`), capped at `Game.max_hp` (raised by offerings) through `Game.heal`, recorded in `Game.healed` | instant | - |
| `time_stop` | monsters do not act (blue); hits are sneak attacks (x2, see [monsters.md](monsters.md)) | drink round + 3 (`time_stop_turns`) | resets to 3 |
| `speed` | 2 actions per round, cyan hero background | 10 rounds = 20 actions incl. the drink (`speed_turns`) | resets to 10 |
| `strength_small/medium/large` | +1/+2/+3 attack damage (`strength()`) | drink round + 3 (`strength_turns`) | **bonus adds up**, counter resets to 3 (a user rule) |
| `vision` | whole map visible, field of view off | drink round + 3 (`vision_turns`) | resets to 3 |
| `invisibility` | monsters only wander (no chase, no bite, even next to the hero); attacking a monster is a sneak attack (x2) and ends it (`revealed`: render appends "(you are visible again)"); the hero `@` is gray | drink round + 5 (`invisible_turns`) | resets to 5 |
| `mystery` | 50% (`mystery_good_chance`): a random chest potion (never a mystery), applied at once; 50%: a random `Curse` | see below | - |

## Mystery potion and curses (user rules)

Its name is shown as just `???` everywhere (label, inventory line, shop, chest message; a user choice). `drinkMystery`: works at full health. Good result: `randomPotion` re-rolled until it is not a mystery, then `applyPotion`; `Game.mystery_potion` makes `render` append "(it was a <label>)". Bad result: one of the 5 `Curse` values, 20% each (`randomCurse`, also used by totems, see [fountains-totems.md](fountains-totems.md)); `Game.mystery_curse` makes `render` append "(it was a curse)" and `events.curse` plays `Sfx.curse`. `applyCurse` sets:

| Curse | Effect | Duration | Header |
|---|---|---|---|
| `slow` | `endRound` runs `monstersTurn` twice | 3 rounds after the drink round (`slow_turns`, fresh flag: the drink round is not doubled) | `SLOW N` |
| `paralysis` | `Game.paralyzed`: the next action (not quit) becomes a lost turn, "You are paralyzed! You lose this turn." | 1 action | `PARALYZED` |
| `burn` | `curse_damage` 2, **never below 1 HP** (user choice); `damage_taken` = real loss, so the red flash plays | instant | - |
| `blind` | `visibility` uses `blind_radius` 2 instead of 5; vision still shows the whole map | drink round + 5 (`blind_turns`) | `BLIND N` |
| `confused` | `Command.reversed()`: up/down and left/right swapped in `step` | drink round + 5 (`confused_turns`, user choice) | `CONFUSED N` |

While `isCursed()` (slow, paralyzed, blind or confused) the hero's `@` is red (a user rule). Tests: `"a mystery potion is good half the time and a curse the other half"`, `"a mystery potion works at full health and says what it was"`, one test per curse, `"the hero is red while cursed"`.

- A health potion at full HP is refused: `drink` returns false and the action uses no turn (`step` returns before the round ends). Every other potion works at full health.
- Status line: `TIME STOP N`, `SPEED N`, `STRENGTH +B (N)`, `VISION N`, `INVISIBLE N` (`writeHeader`).
- Each kind sets its `events.*` flag, which plays its sound (see [sound.md](sound.md)).
- How the durations count (rounds, fresh flags, speed): [rounds.md](rounds.md).

## Adding a new potion (checklist)

Constant(s) for chance and turns; enum value + `count`; `label()`; inventory line in `renderInventory`; branch in the chest roll (keep the order and update the table here); `drink` branch; counter + `_fresh` in `Game`; tick in `endRound`; `writeHeader`; `Events` flag; `Sfx` + `afterTurn`; README rules; tests (chest split, counter, duration, re-drink). Fix the `[Potion.count]usize{...}` literals in the size-split tests.
