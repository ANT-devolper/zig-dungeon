# Field of view

Code: `Game.visibility`, `lineIsClear`, `view_radius`, `RenderOptions.fov`, `ansi_dim` in `src/root.zig`.

- The hero sees tiles within `view_radius` (5), a rounded circle `dx^2 + dy^2 <= r^2 + r`, when a Bresenham line in either direction crosses no wall between the two ends (`lineIsClear`). The wall that blocks the view is itself visible.
- With `RenderOptions.fov`, tiles out of sight are drawn as plain `#` or `.` in light gray (`ansi_dim`, 256-color 248). This hides monsters, gold, chests and the stairs.
- There is **no memory** of tiles already seen.
- **Blind curse** (mystery potion): while `blind > 0`, `visibility` uses `blind_radius` (2) instead of `view_radius`.
- **Vision potion:** while `hasVision()` (`vision > 0`), `render` skips the field of view and draws the whole map. See [potions.md](potions.md).
- **Level cleared:** once `stairsRevealed()` (`monster_count == 0`), `render` draws the stairs tile even out of sight. Only the stairs; gold and chests stay hidden. Monsters never respawn, so it lasts until the next level. The last kill's message is "You defeated the last monster! The stairs are revealed."
- `main.zig`'s `drawFrame` always turns `fov` on. Tests render without it unless they set it.

**User choices** (all of them): radius 5, walls block the view, the stairs hide too (until the level is cleared), a dimmed maze instead of blank tiles.

Tests: `"the hero sees up to view_radius tiles away"`, `"fov render hides what is out of sight"`, `"fov color render dims tiles out of sight"`, `"the stairs show through the fov once every monster is defeated"`, `"killing the last monster says the stairs are revealed"`, and the vision tests.
