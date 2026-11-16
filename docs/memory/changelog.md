# Changelog

One entry per change, newest first. Format: `date` `hash` subject, then what changed (pages touched). The hash of the newest entry is filled in with the next commit.

## 2026-11-16

- `(this commit)` feat: add a panic key that hides the game behind a fake test run. The disguise is a `python -m pytest -v` run in `C:\Users\dev\projects\gestao-qualidade`. Space on any screen shows `renderDisguise`; only Space returns. ([input-terminal](features/input-terminal.md), [rendering](features/rendering.md))
- `ccdfbdc` feat: move the hero with the arrow keys as well as wasd. `readKey` moved to `src/root.zig` and decodes arrow escape sequences; Windows raw mode turns on VT input. ([input-terminal](features/input-terminal.md))

## 2026-11-13

- `c13e25c` feat: add a title screen with Play and Quit, and --no-title. ([input-terminal](features/input-terminal.md), [rendering](features/rendering.md))
- `036dc74` chore: rename the game to Brewdungeon. Executable and module are now `brewdungeon`; the header keeps `DUNGEON`.
- `8ea1f05` feat: add a ??? potion that is a random potion or a curse. ([potions](features/potions.md), [rounds](features/rounds.md), [fov](features/fov.md), [shop](features/shop.md), [rendering](features/rendering.md), [sound](features/sound.md))
- `7ad6c29` feat: use the whole map with a 31x13 maze and a single border. ([levels](features/levels.md), [shop](features/shop.md))
- `920c164` feat: add shop levels where gold buys potions. Each potion kind has its own color (`Potion.color`). ([shop](features/shop.md), [potions](features/potions.md), [levels](features/levels.md), [rendering](features/rendering.md), [sound](features/sound.md))
- `0319674` feat: make the dungeon endless with tougher monsters every 3 levels. No win, no `last_level`; monster HP grows; `Sfx.won` removed. ([levels](features/levels.md), [monsters](features/monsters.md), [rendering](features/rendering.md), [sound](features/sound.md))
- `39ef9c2` feat: reveal the stairs once every monster on the level is defeated. ([fov](features/fov.md), [monsters](features/monsters.md))
- `d4be073` build: force LF line endings with .gitattributes. Fixes `zig fmt --check` failing and files showing as modified after a checkout (`core.autocrlf=true`). ([backlog](backlog.md) item closed)
- `7f98ae6` docs: add a durable project memory in docs/memory. Created this folder; moved the per-system details out of `CLAUDE.md`; added the decisions, changelog, workflow and backlog logs.
- `0699960` docs: require a body in every commit message.
- `b4a5603` feat: add a vision potion that reveals the whole map for 3 rounds. ([potions](features/potions.md), [fov](features/fov.md), [rounds](features/rounds.md), [sound](features/sound.md))
- `a60e7f7` feat: play on the alternate screen so moves leave no history. Ctrl+C quits cleanly. ([input-terminal](features/input-terminal.md))
- `4ecfea8` feat: read each key at once without waiting for Enter. Added `src/term.zig`. ([input-terminal](features/input-terminal.md))
- `25b01ed` feat: make 85% of chests hold a potion instead of gold. ([potions](features/potions.md))
- `371cc4e` feat: add strength potions that boost attack damage for 3 rounds. ([potions](features/potions.md), [rounds](features/rounds.md))
- `196d7e8` feat: add a speed potion that gives two actions per round. Introduced world rounds. ([rounds](features/rounds.md))
- `93d04cc` feat: add a time stop potion that freezes monsters for 3 turns.
- `505086b` feat: add healing potions found in chests.
- `8551023` feat: add chests that hold 20-50 gold.
- `10fe844` feat: add an inventory screen opened with i. ([inventory](features/inventory.md))
- `d9e81fb` feat: add line-of-sight field of view. ([fov](features/fov.md))
- `bbb98ea` feat: make monsters wander when they are not chasing. ([monsters](features/monsters.md))
- `7e1fe2c` `3b80cdf` `0ee07eb` `59ecadc` feat: colors for gold, monsters, stairs and the hero. ([rendering](features/rendering.md))
- `4c81b9b` feat: generate maze levels with shortcuts. ([levels](features/levels.md))
- `8d55796` feat: add synthesized sound effects. ([sound](features/sound.md))
- `528b523` feat: add strike effect when the hero hits a monster.
- `7ec056a` docs: add CLAUDE.md with project context for agents.
- `afcc374` feat: add damage feedback effects.
- `88616f9` docs: add README.
- `a061652` Add terminal dungeon game in Zig.
