# Monsters

Code: `monstersTurn`, `moveMonsterToward`, `wander`, `isFreeForMonster`, `Monster` in `src/root.zig`.

- Each round (see [rounds.md](rounds.md)), unless time is stopped, every monster acts once:
  - **Next to the hero:** it bites for `monster_damage` (1). `Monster.bit` marks it for the white-on-red highlight, and `Game.damage_taken` triggers the red flash and shake.
  - **Within `chase_radius`** (6, Manhattan distance): it steps toward the hero (`moveMonsterToward`).
  - **Otherwise:** `wander_chance` (30%) per round to step in a random free direction (`wander`).
- Both kinds of step use `isFreeForMonster`: no wall, no other monster, not the hero.
- Monsters have `monster_hp` (3). The hero hits for `attackDamage()` (2, plus any strength bonus), so a plain monster dies in 2 hits.
- Count per level: `min(max_monsters, 1 + 2 * level)` = 3, 5, 7.
- Colors: red; blue while time is stopped (`ansi_blue`); white on red for the one that just bit (`ansi_bite`).
