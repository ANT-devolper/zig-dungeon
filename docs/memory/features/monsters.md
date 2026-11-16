# Monsters

Code: `MonsterKind` (`symbol`, `maxHp`, `damage`, `sight`, `actions`, `firstLevel`, `spawnWeight`, `biteMessage`, `hitMessage`, `defeatMessage`), `Monster`, `monstersTurn`, `monsterAct`, `moveMonsterToward`, `wander`, `isFreeForMonster`, `addMonster(pos, kind)`, `spawnMonsters`, `randomMonsterKind`, `monsterSpawnSpot`, `freeSpotNear` in `src/root.zig`.

## Kinds

Every monster has a `kind` (`MonsterKind`), which gives its letter, HP, bite, sight (chase radius) and messages. Sight values are user rules (2026-11-16).

| Kind | Letter | From level | Spawn weight | HP | Bite | Sight | Actions per round |
|---|---|---|---|---|---|---|---|
| monster | `M` | 1 | 40 | `monsterHp(level)` | 1 | 4 (was 6 before kinds) | 1 |
| rat | `r` | 2 | 20 | 1 | 1 | 5 (the monster's + 1) | **2** (`actions()`): it moves twice, or bites twice |

Test layouts map each letter to its kind in `loadLayout`.

**Spawning** (`spawnMonsters`): the count stays `min(max_monsters, 1 + 2 * level)`. Each monster's kind is rolled by `randomMonsterKind` among the kinds whose `firstLevel()` is reached, weighted by `spawnWeight()` (level 1 is all `M`). A rat brings 1 or 2 more rats (`rat_group_min`..`rat_group_max` = a group of 2-3) on free tiles next to it (`freeSpotNear`), or anywhere if there is no room; they count toward the total, so the count is exact. Spots keep `monster_safe_distance` (5) from the hero (`monsterSpawnSpot`).

## Turn

- Each round (see [rounds.md](rounds.md)), unless time is stopped, every monster acts once (`monstersTurn(hidden)`):
  - **Hero invisible** (`hidden`, the invisibility potion, see [potions.md](potions.md)): every monster only wanders (`wander_chance` 30%), even next to the hero: no chase and no bite (a user rule). The AI keeps no chase state (it decides by distance every round), so a chase already under way simply stops.
  - **Next to the hero:** it bites for `kind.damage()` (1 for `M`), with `kind.biteMessage()`. `Monster.bit` marks it for the white-on-red highlight, and `Game.damage_taken` triggers the red flash and shake.
  - **Within its sight** (`kind.sight()`, Manhattan distance): it steps toward the hero (`moveMonsterToward`).
  - **Otherwise:** `wander_chance` (30%) per round to step in a random free direction (`wander`).
- Both kinds of step use `isFreeForMonster`: no wall, no other monster, not the hero.
- Monsters have `monsterHp(level)` HP: `monster_hp` (3) plus 1 every `monster_hp_step` (3) levels, so 3 on levels 1-3, 4 on 4-6, 5 on 7-9... The bite stays at 1. The hero hits for `attackDamage()` (2, plus any strength bonus), so a plain monster dies in 2 hits.
- **Sneak attack** (user rules): a hit while the hero is invisible or time is stopped (`isSneaky()`) deals `attackDamage() * sneak_multiplier` (2), strength included: `(2 + bonus) x 2`. Both at once is still x2. A plain 3-4 HP monster dies in one sneak hit. The hit still ends invisibility (time stop goes on). `Game.sneak_damage` makes render append " (sneak attack: N damage)" in yellow right after the message. Same strike/kill sound and spark.
- Killing the last monster of a level reveals the stairs through the field of view (see [fov.md](fov.md)).
- **Clear reward** (user rules): the same kill calls `giveClearReward`, which rolls `rewardChests(level)` chests (`openChest`, the normal chest odds, see [potions.md](potions.md)) **straight into the inventory**. That is one roll per monster HP tier: `(level - 1) / monster_hp_step + 1` = 1 on levels 1-3, 2 on 4-6, 3 on 7-9..., with no cap. The per-turn fields `reward_chests`, `reward_potions` (counts by `Potion.index()`) and `reward_gold` feed `writeReward`, which appends ` (reward: N chests: speed, small potion x2, +30 gold)` in green after the kill message. `events.reward` plays `Sfx.chest`. Shops have no monsters, so no reward there.
- Count per level: `min(max_monsters, 1 + 2 * level)` = 3, 5, 7, then 8 from level 4 on.
- Colors: red; blue while time is stopped (`ansi_blue`); white on red for the one that just bit (`ansi_bite`).
