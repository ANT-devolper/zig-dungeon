# Decisions

Rules and choices the user made. Newest first. Check here before changing a behavior; do not undo a decision without asking.

| Date | Decision | Why / context | Where |
|---|---|---|---|
| 2026-11-16 | The arrow keys move the hero like WASD (and move the title cursor). Other escape sequences are ignored. | User request. | `readKey`, `term.zig`, [features/input-terminal.md](features/input-terminal.md) |
| 2026-11-13 | The title screen is small and fits the map's width (31 columns + indent), with the name in a wall frame. | User request (the first banner was 68 columns wide). | `Title.render` |
| 2026-11-13 | A title screen with Play and Quit (`w`/`s` + Enter, or `p`/`q`). After a run, any key returns to the title; Ctrl+C closes the game. `--no-title` skips the title. | User request and choices. | `Title`, `main.zig`, [features/input-terminal.md](features/input-terminal.md) |
| 2026-11-13 | The game is called **Brewdungeon** (exe and module `brewdungeon`). The in-game header keeps `DUNGEON  Level N`; the repo stays `zig-dungeon` unless the user renames it on GitHub. | User choice (over Brewdeep and Brewdepth). | `build.zig`, README |
| 2026-11-13 | After every change, the reply ends with the proposed commit message (before committing), so the user decides. | User rule. | [workflow.md](workflow.md) |
| 2026-11-13 | The mystery potion's name is just `???` everywhere. | User choice. | `Potion.label` |
| 2026-11-13 | Mystery potion: 50% a random chest potion (applied at once), 50% a curse: slow 3 rounds, paralysis 1 action, 2 damage, blind (radius 2) 5 rounds, confused 5 rounds. The hero is red while cursed. | User rules (confusion length chosen by the user). | `drinkMystery`, `Curse`, [features/potions.md](features/potions.md) |
| 2026-11-13 | The burn curse never kills: the hero keeps 1 HP. | User choice. | `applyCurse` |
| 2026-11-13 | Mystery: 10% of chest potions, taken from health (50% -> 40%); shop price 10. | User choice. | `mystery_chance`, `Potion.price` |
| 2026-11-13 | The map is 31x13 with a single border, so the maze uses every line (reverses the double-border choice). | User request: a whole line was wasted. | `W`, `H`, [features/levels.md](features/levels.md) |
| 2026-11-13 | Potion colors: vision purple, health green, strength brown, time stop yellow, speed blue. Used for the shop's `!` and inventory names. | User request. | `Potion.color` |
| 2026-11-13 | Shop event on the stairs of every even level: 80% the first call, 50% after. Right after a shop the next chance is skipped (not called). | User rules. | `nextLevel`, [features/shop.md](features/shop.md) |
| 2026-11-13 | The shop counts as a level. | User choice. | `loadShop` |
| 2026-11-13 | A shop sells 2 potions rolled like a chest's, on the floor; walking over one buys it; the shopkeeper is an `@` in another color (orange). | User rules. | `buy`, `randomPotion` |
| 2026-11-13 | Prices follow rarity: 10, 15, 20, 25, 25, 30, 30, 45, 70 (health S, health M, speed, time stop, vision, health L, strength S, M, L). | User-approved table. | `Potion.price` |
| 2026-11-13 | The dungeon is endless: the goal is to reach the deepest level. No win state. | User request. | `loadLevel`, [features/levels.md](features/levels.md) |
| 2026-11-13 | Difficulty past level 4: still 8 monsters, **+1 monster HP every 3 levels**, bite stays 1. | User choice (over stronger bites or more monsters). | `monsterHp`, [features/monsters.md](features/monsters.md) |
| 2026-11-13 | No saved record between runs; the final score is the level reached plus gold. | User choice. | `main.zig` |
| 2026-11-13 | When every monster on a level is defeated, the stairs show through the field of view until the next level. Only the stairs, not gold or chests. | User request: a reward for clearing a level. | `stairsRevealed`, [features/fov.md](features/fov.md) |
| 2026-11-13 | Claude never runs `git push`; the user pushes. | User rule. | [workflow.md](workflow.md) |
| 2026-11-13 | `.gitattributes` forces LF line endings for the whole repo; the global git config stays untouched. | `core.autocrlf=true` rewrote files with CRLF and broke `zig fmt --check`. | `.gitattributes` |
| 2026-11-13 | Project memory lives in `docs/memory/` (Markdown, in the repo). It is read before the code and updated in the same commit as every change. Details moved out of `CLAUDE.md`. | The ai-memory server was down, so there was no durable memory between sessions. | `docs/memory/`, `CLAUDE.md` |
| 2026-11-13 | Backlog items may link to GitHub issues. | Keep ideas trackable outside the repo. | [backlog.md](backlog.md) |
| 2026-11-13 | Every commit message has a body (what changed and why). The full message is shown to the user on every commit. | The user wants readable history and to see what goes into it. | `CLAUDE.md` Conventions, [workflow.md](workflow.md) |
| 2026-11-13 | Vision potion: whole map visible for the drink round + 3; 10% of chest potions, **taken from health** (60% -> 50%). | User request and choice. | [features/potions.md](features/potions.md) |
| 2026-11-13 | The game runs on the alternate screen; only the last frame and the score stay in the terminal. Ctrl+C quits cleanly. | Each move left a copy of the map in the scrollback. | [features/input-terminal.md](features/input-terminal.md) |
| 2026-11-13 | One key at a time: every key acts at once, no Enter. | Better gameplay. | [features/input-terminal.md](features/input-terminal.md) |
| 2026-11-13 | 85% of chests hold a potion, 15% gold. | Was 50/50; the user wanted potions to be the usual reward. | `chest_potion_chance` |
| 2026-11-13 | Strength potions come in 3 sizes (+1/+2/+3); **bonuses add up**, the counter resets. | User rule. | [features/potions.md](features/potions.md) |
| 2026-11-13 | Effects combine: every counter counts rounds, not actions. | Speed must not shorten other effects. | [features/rounds.md](features/rounds.md) |
| 2026-11-13 | Time stop (and later speed and vision) is a single kind with no sizes. | User rule. | `Potion` |
| 2026-11-13 | A chest holds a potion **or** gold, never both. | User rule. | `.chest` branch of `step` |
| 2026-11-13 | Inventory numbers are positions in pick-up order, with no gaps. | User rule. | [features/inventory.md](features/inventory.md) |
| 2026-11-13 | Field of view: radius 5, walls block, the stairs hide too, a dimmed maze instead of blank. | User choices. | [features/fov.md](features/fov.md) |
| 2026-11-13 | ~~Keep the double wall on the right and bottom (30x12 map) instead of resizing to 31x13.~~ Reversed: the map is now 31x13 (see the newer row). | User choice. | [features/levels.md](features/levels.md) |
