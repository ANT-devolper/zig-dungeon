# Level-up perks

Code: `Perk`, `perkKey`, `Game.choosePerk`, `Game.perk_pending`, `damage_bonus`, `perk_taken`, `Game.renderPerks` in `src/root.zig`; `perkScreen` in `src/main.zig`.

A user request (2026-11-26): fix the late game, where `max_hp` and the hero's damage never grew while monster HP did (+1 every `monster_hp_step` = 3 levels).

## Rules (user choices)

- On arriving at level **4, 7, 10...** (`(level - 1) % monster_hp_step == 0`, the same pace as `monsterHp`), a perk is offered. The check runs in the `.stairs` branch of `Game.step` after `nextLevel`, so it also fires when that level is a shop or a fountain.
- Three options, chosen with the keys **1 / 2 / 3**; a perk can be taken again at a later level:
  1. `max_hp`: **+3 max HP**, and the 3 new HP (`perk_max_hp`).
  2. `damage`: **+1 attack damage for good** (`perk_damage`, `damage_bonus`). `attackDamage()` is `hero_damage + strength_bonus + damage_bonus`, so strength and the x2 sneak attack build on it.
  3. `heal`: **full heal** (`heal(max_hp)`). It replaced the "+1 view radius" idea of the backlog.
- The choice is on a **separate screen** (`renderPerks`, like the inventory), shown by `playRun` right after the stairs turn. It uses no turn, and the panic key hides it and comes back to it. Ctrl+C or the end of the input closes the game.
- While `perk_pending`, `step` ignores every command except `.quit` ("Choose a perk first."): a safety net, since `main.zig` always shows the screen first. `choosePerk` does nothing when no perk is pending.
- After the choice the map message is "You feel stronger!" plus "(+3 max HP)" or "(+1 damage)"; a full heal shows the usual "(+N HP)". It plays the buy sound (`events.buy`).
- The inventory screen has an "Attack damage" line (`attackDamage()`), so the bonus is visible.

## Tests

`"a perk is offered when reaching levels 4, 7 and 10 only"`, `"the hero cannot act while a perk is pending"`, one test per perk, `"choosePerk does nothing without a pending perk"`, `"perk keys are 1, 2 and 3"` and the two render tests.
