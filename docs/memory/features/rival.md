# The rival adventurer

Code: `Rival`, `RivalStatus`, `huntChance`, and the `Game` methods `rivalAt`, `rivalSeen`, `rivalOnNewLevel`, `maybeMeetRival`, `placeRivalAhead`, `rivalLeftBehind`, `rivalAwayRound`, `rivalCrossedLevel`, `rivalTurn`, `rivalStepToward`, `rivalHitsMonster`, `rivalKilledByMonsters`, `takeRivalLoot`, `monsterVsRival` in `src/root.zig`. The constants are `rival_*`.

Another adventurer races the hero down the dungeon. User rules (2026-11-19):
- it never exists before level 5
- it acts like the player and keeps racing level after level
- it may or may not try to kill the hero, with an opportunistic random hunt roll
- there is one rival per run
- it is drawn as a magenta `@`

The numbers are my picks.

## State

- `Game.rival: Rival`, with `status`:
  - `none`: not met yet.
  - `here`: on the hero's map.
  - `away`: off screen on `rival.level`. It is ahead if `rival.level > g.level` (or equal on arrival, because it got there first) and behind otherwise.
  - `dead`: gone for the run.
- The rival has its own `hp`/`max_hp` (10), `inventory` (gold and potions, reusing `Inventory`), `strength` and `strength_bonus`, `hunting`, `saw_hero`/`seen_hero_hp` (when to reroll), `rounds_left`/`rounds_total` (off-screen progress) and `bit` (it hit the hero this turn).
- `Game.entry` is the hero's start tile on the level, set by `loadLevel`, `loadRoom` and `loadLayout`. A rival coming from behind enters there, or on the nearest free floor tile (`nearestFreeFloor`).
- Per turn, reset in `step`: `rival_message` (a static string, drawn on its own line), and `rival_loot_gold`/`rival_loot_potions`.

## Meeting it (`maybeMeetRival`, at the end of `loadLevel`; maze levels only)

- It only rolls while `status == .none` and `level >= rival_first_level` (5). The chance is `rival_chance` (40%) per level, and it always shows up at `rival_sure_level` (7).
- It starts with 10 HP, `rival_start_gold` (20) gold and one small health potion.
- 50% **ahead**: `placeRivalAhead(20..70%)`, with "Another adventurer races you to the stairs!".
- 50% **behind**: `away` on `level - 1`, arriving after `rival_arrive_min..max` (10-30) rounds.

## Off screen (`rivalAwayRound`, every round in `endRound`, even during time stop)

- **Ahead = frozen** (user rule, 2026-11-19): while `rival.level > g.level`, `rivalAwayRound` returns at once. The counter does not tick, it takes no damage, and it never crosses another level, so the lead is at most 1 level. A rival that reaches `g.level + 1` (by the stairs on the hero's map, or off screen) has a fresh counter, so on the hero's arrival its progress is 0% and `placeRivalAhead(0)` puts it near the start: the free tile nearest to the hero by walking, at least `monster_safe_distance` away. Only a rival that is behind (or on the level of the hero's shop or fountain room) races on.
- Behind, `rounds_left` counts down. When it ends, `level += 1` and `rivalCrossedLevel` runs, in this order:
  1. one chest roll (`rollChest(&rival.inventory)`)
  2. 1-3 damage (`rival_away_damage_*`); at 0 HP it becomes `dead`, its loot is lost and the hero sees "A distant scream echoes... your rival is gone."
  3. a health potion if its HP is at or below 4
  4. +1 HP of rest
  5. its strength is reset
- If the new level is the hero's maze level, the rival comes in at `entry` (`here`): "You hear footsteps on the stairs: your rival is here!". Otherwise it gets a new counter (`newRivalCounter`, 40-80 rounds), including when the hero is in a shop or fountain room, since rooms are the hero's alone.
- **The hero takes the stairs** (`rivalLeftBehind`, at the start of `nextLevel`): a rival that is `here` becomes `away` on the old level, with `rounds_left` = its walking distance to the stairs + 0..10. It is now behind.
- **A new level loads** (`rivalOnNewLevel`): if the rival is `away` on that level, it got there first. It appears with `placeRivalAhead(100 - rounds_left * 100 / rounds_total)`: the free floor tile whose walking distance from the hero is closest to progress x the stairs distance, at least `monster_safe_distance` from the hero. Message: "Your rival is already here!".

## On the map (`rivalTurn`, in `endRound` before the monsters; time stop freezes it)

1. Its strength counter ticks.
2. **Hostility.** `rivalSeesHero` is true when the hero is within `rival_sight` (5, Manhattan), the line is clear both ways, and the hero is not invisible.
   - When the rival first sees the hero, or sees the hero with less HP than at its last roll, and it is not hunting yet, it rolls `huntChance(hero hp, hero max, rival hp, rival max)`:
     - the chance is `5 + (100 - hero HP %) * rival HP % / 100`, capped at 90
     - it is 0 when the rival's HP is at or below `rival_flee_hp` (3)
   - Out of sight (or with the hero invisible), it stops hunting. At 3 HP or less it never hunts.
3. If its HP is at or below `rival_low_hp` (4) and it has a health potion, it drinks the largest one.
4. If it is hunting and next to the hero, it hits for `rival_damage` (2) + its strength. The hero's `damage_taken` drives the flash and shake, the rival is drawn white on red, and the message is "Your rival stabs you!". If the hero dies: "Your rival killed you. GAME OVER."
5. If a monster is next to it, it attacks it (`rivalHitsMonster`). It drinks its largest strength potion first if the monster would survive the hit. A kill:
   - gives the rival a thief's gold
   - splits a slime
   - gives the hero **no** clear reward (the stairs still show once `monster_count` is 0)
6. If it is hunting, it steps toward the hero.
7. If gold or a chest is within `rival_loot_reach` (6) walking steps, it goes for the nearest one.
8. Otherwise it walks toward the stairs. `rivalStepToward` walks the BFS (`distanceMap(goal)`) and picks up gold or chests it walks over. On the stairs it becomes `away` on `level + 1` with a new counter (it is now ahead).

When the hero sees it, messages go to `rival_message`: grabs the gold, opens a chest, drinks a potion, fights or slays a monster, takes the stairs.

## Fights with the hero and the monsters

- Bumping the rival is an attack through `heroStrike()`, which the monster attack uses too: sneak attacks count, and invisibility ends.
  - If the rival survives with HP above 3, it hunts for sure.
  - A kill sets `dead` and gives the hero all of its gold and potions (`takeRivalLoot`), shown as " (+N gold, M potions)". The message is "You defeated your rival!".
- Monsters target the nearer of the hero and the rival (see [monsters.md](monsters.md)). When they kill it (`rivalKilledByMonsters`), its tile becomes `Tile.remains` (`%`). Walking over it gives its loot: "You search your rival's remains."
- `isFreeForMonster`, `canEnter` and `randomFreeFloor` avoid the rival's tile. The rival avoids walls, monsters and the hero (`isFreeForRival`) and ignores totems.

## Display

- The rival is a magenta `@`, white on red when it just hit the hero, drawn only where the hero sees.
- The header shows `RIVAL Lv N` once the rival is met and alive, with ` HP x/y` while it is seen.
- At the end, `main.zig` prints "Your rival reached level N." or "Your rival died on level N.".
- Test layouts place the rival with `A` (here, on the layout's level) and remains with `%`.
