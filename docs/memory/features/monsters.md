# Monsters

Code: `monstersTurn`, `moveMonsterToward`, `wander`, `isFreeForMonster`, `Monster` in `src/root.zig`.

- Each round (see [rounds.md](rounds.md)), unless time is stopped, every monster acts once (`monstersTurn(hidden)`):
  - **Hero invisible** (`hidden`, the invisibility potion, see [potions.md](potions.md)): every monster only wanders (`wander_chance` 30%), even next to the hero: no chase and no bite (a user rule). The AI keeps no chase state (it decides by distance every round), so a chase already under way simply stops.
  - **Next to the hero:** it bites for `monster_damage` (1). `Monster.bit` marks it for the white-on-red highlight, and `Game.damage_taken` triggers the red flash and shake.
  - **Within `chase_radius`** (6, Manhattan distance): it steps toward the hero (`moveMonsterToward`).
  - **Otherwise:** `wander_chance` (30%) per round to step in a random free direction (`wander`).
- Both kinds of step use `isFreeForMonster`: no wall, no other monster, not the hero.
- Monsters have `monsterHp(level)` HP: `monster_hp` (3) plus 1 every `monster_hp_step` (3) levels, so 3 on levels 1-3, 4 on 4-6, 5 on 7-9... The bite stays at 1. The hero hits for `attackDamage()` (2, plus any strength bonus), so a plain monster dies in 2 hits.
- Killing the last monster of a level reveals the stairs through the field of view (see [fov.md](fov.md)).
- **Clear reward** (user rules): the same kill calls `giveClearReward`, which rolls `rewardChests(level)` chests (`openChest`, the normal chest odds, see [potions.md](potions.md)) **straight into the inventory**. That is one roll per monster HP tier: `(level - 1) / monster_hp_step + 1` = 1 on levels 1-3, 2 on 4-6, 3 on 7-9..., with no cap. The per-turn fields `reward_chests`, `reward_potions` (counts by `Potion.index()`) and `reward_gold` feed `writeReward`, which appends ` (reward: N chests: speed, small potion x2, +30 gold)` in green after the kill message. `events.reward` plays `Sfx.chest`. Shops have no monsters, so no reward there.
- Count per level: `min(max_monsters, 1 + 2 * level)` = 3, 5, 7, then 8 from level 4 on.
- Colors: red; blue while time is stopped (`ansi_blue`); white on red for the one that just bit (`ansi_bite`).
