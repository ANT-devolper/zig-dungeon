# Project memory

Durable memory of **Brewdungeon** (repo `zig-dungeon`): how each system works, why it is that way, and what changed. **Read this before reading code.** Open the code only for what these pages do not answer.

## Read order

1. This index, to find the page for your topic.
2. The page itself (`features/*.md` for a system, the logs below for history).
3. Only then the code, at the symbols the page names.

If a page and the code disagree, **the code wins**: fix the page in the same change.

## Where is X

| Topic | Page | Main code symbols |
|---|---|---|
| Module map, main loop, game state | [architecture.md](architecture.md) | `Game`, `Game.step`, `main` |
| Maze generation, stairs, loot spots | [features/levels.md](features/levels.md) | `generateLevel`, `carveMaze`, `carveShortcuts`, `spawnLoot` |
| Field of view, fog | [features/fov.md](features/fov.md) | `visibility`, `lineIsClear`, `view_radius` |
| Monster AI, combat numbers | [features/monsters.md](features/monsters.md) | `monstersTurn`, `moveMonsterToward`, `wander` |
| Inventory, item numbers, `i` screen | [features/inventory.md](features/inventory.md) | `Inventory.add/remove`, `renderInventory`, `Command.use_N` |
| Shop levels, prices, buying | [features/shop.md](features/shop.md) | `nextLevel`, `loadShop`, `buy`, `Potion.price` |
| Chests and all potions | [features/potions.md](features/potions.md) | `Potion`, `drink`, `chest_*_chance` |
| Fountain levels, offerings, totems, max HP | [features/fountains-totems.md](features/fountains-totems.md) | `loadFountain`, `makeOffering`, `touchTotem`, `spawnTotem`, `Game.max_hp` |
| The rival adventurer (AI, off-screen race, hostility) | [features/rival.md](features/rival.md) | `Rival`, `RivalStatus`, `huntChance`, `rivalTurn`, `rivalAwayRound`, `rivalOnNewLevel` |
| Rounds, timed effects, speed | [features/rounds.md](features/rounds.md) | `endRound`, `half_round`, `*_fresh` |
| Keyboard input, terminal, alternate screen | [features/input-terminal.md](features/input-terminal.md) | `term.RawMode`, `readKey`, `alt_screen_on` |
| Colors, frames, animations | [features/rendering.md](features/rendering.md) | `render`, `RenderOptions`, `writeHeader`, `playHitEffect` |
| Sound effects | [features/sound.md](features/sound.md) | `Sfx`, `Bank`, `synth`, `play` |

## Logs

- [decisions.md](decisions.md): rules and choices the user made, with the reason. Check it before changing a behavior.
- [changelog.md](changelog.md): one entry per change, newest first.
- [workflow.md](workflow.md): the agreed way of working (plan, tests, commits).
- [backlog.md](backlog.md): ideas and known issues not done yet, with GitHub issue links when they exist.

## How to update (part of every change)

In the **same commit** as the change:

- Update the feature page(s) the change touches, or add a new page and list it in the table above.
- Add an entry at the top of `changelog.md`. The hash is only known after the commit, so fill it in with the next commit (or write the entry with the subject line and leave the hash out).
- Add a line to `decisions.md` for every new rule or choice the user makes.
- Move finished items out of `backlog.md`, and add new ideas or known issues there.

Write in English (repo convention), short and factual: numbers, symbol names, the reason behind a rule.
