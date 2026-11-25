# World rounds and timed effects

Code: end of `Game.step`, `Game.endRound`, `half_round`, `time_stop_fresh`, `strength_fresh`, `vision_fresh` in `src/root.zig`.

**Effects combine (a user rule): every effect counter counts rounds, not actions.**

- At the end of `step`, while `speed > 0` the hero gets 2 actions per round: the first sets `half_round` and returns, and the second closes the round. Without speed, every action closes a round.
- `endRound()` ticks every counter once per round and calls `monstersTurn` unless time is stopped.
- Actions that use no turn (number with no item, health potion at full HP, the `i` screen) return before this, so they never touch `half_round`.
- Taking the stairs resets `half_round` and the monsters do not act that turn.
- **New timed effects must tick in `endRound`, never per action.**

## The "fresh" flag (drink round is free)

Time stop, strength and vision set a `*_fresh` flag when drunk. In `endRound`, a fresh effect clears the flag without decrementing, so the round it was drunk in does not count: the effect lasts that round plus `*_turns` (3). This holds even when drunk in the first half of a fast round.

- **Time stop:** rounds with `time_stop > 0` decrement and skip `monstersTurn`. `timeStopped()` drives the blue monsters.
- **Strength:** decrements; at 0 `strength_bonus` is cleared.
- **Vision:** decrements; `hasVision()` lifts the field of view.

## Speed (no fresh flag)

Speed is always drunk at the start of a fast round, so that round counts: 10 rounds are 20 actions, including the drink. `endRound` decrements it. `isFast()` drives the hero's cyan background (`ansi_fast`; red when hurt wins).

**Rats and speed (a user rule):** a rat has 2 actions per round. In a fast round `halfRoundTurn` (called in the first half of `step`) gives each 2-action monster one action right after the hero's first action, and `endRound` (`split = speed > 0`, read before the tick) gives it the remaining one through `monstersTurn(hidden, split)`. So the rat moves or bites once per hero action. Time stop skips both halves; the slow curse's extra monster turn stays a full turn.

With speed and time stop together, each frozen round lasts 2 actions, so `TIME STOP` drops once every 2 actions. Strength and vision also last 2 actions per round with speed.

Tests: `"speed gives 2 actions per round for 10 rounds (20 actions)"`, `"time stop drunk in the first half of a fast round still gives 3 free rounds"`, `"strength combines with speed and time stop: it counts rounds, not actions"`, `"vision shows the whole map for the drink round plus 3, then fov comes back"`.

## Curses (mystery potion)

**Invisibility** (`invisible`, `invisible_fresh`) ticks the same way through `tickCurse`. `endRound` reads `hidden = invisible > 0` **before** the tick (like `frozen` for time stop), so the hero is hidden in the drink round and the 5 rounds after it; `hidden` goes to both `monstersTurn` calls (normal and slow). Attacking a monster in `step` zeroes the counter before `endRound`, so the monsters act normally in that round.

`slow`, `blind` and `confused` tick in `endRound` through `tickCurse`, with fresh flags like vision (drink round + N). While slow (and not fresh), `endRound` calls `monstersTurn` a second time. `paralyzed` is not a counter: the next action in `step` spends it. See [potions.md](potions.md).
