# Chests and potions

Code: `Potion` (`heal`, `strength`, `fromRoll`, `strengthFromRoll`, `label`), the `.chest` branch of `Game.step`, `Game.drink`, the `*_chance` and `*_turns` constants in `src/root.zig`.

## What a chest holds

A chest (25% of item spots, see [levels.md](levels.md)) holds **a potion or gold, never both** (a user rule). Rolled when it is opened:

1. `chest_potion_chance` (**85%**, a user choice): a potion. Otherwise 20-50 gold (`chest_gold_min`..`chest_gold_max`), stored in `Game.chest_gold`.
2. Potion kind, one roll in 0..99, in this order:

| Roll | Kind | Constant |
|---|---|---|
| 0-9 | time stop | `time_stop_chance` 10 |
| 10-24 | speed | `speed_chance` 15 |
| 25-39 | strength (size from `strengthFromRoll`) | `strength_chance` 15 |
| 40-49 | vision | `vision_chance` 10 |
| 50-99 | health (size from `fromRoll`) | the rest, 50 |

3. Sizes (health and strength): small 50%, medium 35%, large 15%.

Overall per chest: gold 15%, health 42.5% (small 21.25, medium 14.875, large 6.375), strength 12.75%, speed 12.75%, time stop 8.5%, vision 8.5%.

The result is stored in `Game.chest_potion` (or `Game.chest_gold`) for that turn; `render` appends "(<label>)" or "(+N gold)". Use `Potion.label()` for names, not `@tagName`.

## Potion kinds

`Potion.count` is 9. Single kinds have no sizes (a user rule for time stop; the same for speed and vision).

| Kind | Effect | Duration | Drinking again |
|---|---|---|---|
| `small/medium/large` | +1/+3/+5 HP (`heal()`), capped at `max_hp`, recorded in `Game.healed` | instant | - |
| `time_stop` | monsters do not act (blue) | drink round + 3 (`time_stop_turns`) | resets to 3 |
| `speed` | 2 actions per round, cyan hero background | 10 rounds = 20 actions incl. the drink (`speed_turns`) | resets to 10 |
| `strength_small/medium/large` | +1/+2/+3 attack damage (`strength()`) | drink round + 3 (`strength_turns`) | **bonus adds up**, counter resets to 3 (a user rule) |
| `vision` | whole map visible, field of view off | drink round + 3 (`vision_turns`) | resets to 3 |

- A health potion at full HP is refused: `drink` returns false and the action uses no turn (`step` returns before the round ends). Every other potion works at full health.
- Status line: `TIME STOP N`, `SPEED N`, `STRENGTH +B (N)`, `VISION N` (`writeHeader`).
- Each kind sets its `events.*` flag, which plays its sound (see [sound.md](sound.md)).
- How the durations count (rounds, fresh flags, speed): [rounds.md](rounds.md).

## Adding a new potion (checklist)

Constant(s) for chance and turns; enum value + `count`; `label()`; inventory line in `renderInventory`; branch in the chest roll (keep the order and update the table here); `drink` branch; counter + `_fresh` in `Game`; tick in `endRound`; `writeHeader`; `Events` flag; `Sfx` + `afterTurn`; README rules; tests (chest split, counter, duration, re-drink). Fix the `[Potion.count]usize{...}` literals in the size-split tests.
