# Levels (generated mazes)

Code: `Game.loadLevel`, `generateLevel`, `tryGenerateLevel`, `carveMaze`, `carveShortcuts`, `distanceMap`, `spawnLoot`, `randomLoot`, `isDeadEnd`, `spawnMonsters` in `src/root.zig`.

`loadLevel(n)` generates the maze, spawns loot, then spawns monsters (3, 5, 7 on levels 1-3, then `max_monsters` 8). **There is no last level:** the stairs always call `loadLevel(level + 1)` and the game only ends on death or quit (the user's goal: reach the deepest level). There is no win state; finished runs go into the [high scores](scores.md). The stairs go through `nextLevel`, which may load a [shop](shop.md) (`loadShop`) instead of a maze. `generateLevel` retries `tryGenerateLevel` until the result is good (stairs far enough, room for monsters...).

1. **`carveMaze`** builds a perfect maze with a recursive backtracker (fixed-size stack, no allocations). Maze cells sit on odd coordinates (`cellTile`), so the 31x13 map (`W`, `H`) fits 15x6 cells (`maze_cols`, `maze_rows`) exactly, with a **single wall line** on every side. (It used to be 30x12 with a double border on the right and at the bottom; the user asked to use that wasted line.)
2. **`carveShortcuts`** opens `maze_loops` (8) extra walls between cells, creating loops. It only ever adds paths, so all floor stays connected and **the stairs are always reachable**. It never opens (even, even) tiles, so corridors stay one tile wide.
3. The hero starts on a random cell. The stairs go on the floor tile farthest from the hero (`distanceMap`, a BFS), at least `min_stairs_distance` (10) steps away. Monsters spawn at random (`spawnMonsters`), at least `monster_safe_distance` (5) from the hero.
4. **`spawnLoot`** fills `loot_count` (4) item spots, preferring dead ends (`isDeadEnd`). Each spot holds a chest (`&`, `chest_chance` 25%) or gold (`$`, `randomLoot`). What a chest holds is rolled when it is opened: see [potions.md](potions.md).
5. **`spawnTotem`** may turn one loot spot into a totem (`Y`, 10%, never on two levels in a row): see [fountains-totems.md](fountains-totems.md).

## Tests

- `"generated mazes are always valid and finishable"` checks levels 1-12 of 500 seeds with `expectValidLevel`: a single border with the maze reaching the row and column next to it, a single reachable stairs tile, connectivity, one-tile corridors and spawns.
- Other tests cover gold in dead ends, the chest share of item spots and the shortcut count.
- Keep them passing when you change the generator.
- Test layouts (`Layout`, a slice of rows) can be smaller than the map: `loadLayout` fills the rest with wall. The test layouts are 30x12.
