# Decisions

Rules and choices the user made. Newest first. Check here before changing a behavior; do not undo a decision without asking.

| Date | Decision | Why / context | Where |
|---|---|---|---|
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
| 2026-11-13 | Keep the double wall on the right and bottom (30x12 map) instead of resizing to 31x13. | User choice. | [features/levels.md](features/levels.md) |
