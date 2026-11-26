# Changelog

One entry per change, newest first. Format: `date` `hash` subject, then what changed (pages touched). The hash of the newest entry is filled in with the next commit.

## 2026-11-26

- `(this commit)` feat: add vim movement keys h j k l. `parseCommand` maps `h/j/k/l` to left/down/up/right next to WASD, and `Title.key` moves the cursor with `k`/`j`. README updated. ([input-terminal](features/input-terminal.md))

## 2026-11-19

- `(this commit)` fix: let a rat act once per hero action while the hero is fast. With speed the rat took both of its actions at the end of the round (it stood still, then jumped 2 tiles or bit twice). New `halfRoundTurn` gives 2-action monsters one action after the hero's first action, and `monstersTurn(hidden, split)` gives them the other after the second; time stop skips both halves. ([rounds](features/rounds.md), [monsters](features/monsters.md))
- `e016be5` fix: say so when speed or time stop is drunk again. Potions were never blocked during speed/time stop (new tests cover every kind in both halves of a fast round); re-drinking speed or time stop only reset the counter with the same message, which looked like nothing happened. `applyPotion` now has "renewed" messages. ([potions](features/potions.md))
- `44bec2d` feat: make the dungeon theme slower and darker. New `Wave.triangle`; `dungeon_theme` rewritten: 8 bars in A minor with a B flat, 760 ms beats, 24.3 s, low triangle voices with long notes. ([sound](features/sound.md))
- `10eefe2` feat: add a looping dungeon soundtrack that m turns off. `Music`/`dungeon_theme`/`synthMusic` (two mixed voices via the new `writeNotes`), `MusicPlayer` on waveOut (looped by the driver, so effects do not cut it); plays only during a run, paused on the panic screen; `music_key` and `[m] music` in the help line. ([sound](features/sound.md), [input-terminal](features/input-terminal.md), [rendering](features/rendering.md))
- `ad25535` feat: type one character per key and color the panic editor like an IDE. `Disguise.key` adds 1 character plus auto-indent; `writeCodeLine`/`codeToken` highlight Python with `ide_*` colors on a dark background; tests strip ANSI with `stripAnsi`. ([input-terminal](features/input-terminal.md), [rendering](features/rendering.md))
- `175af9a` feat: turn the panic screen into a fake editor you can type into. `renderDisguise` (static pytest run) was replaced by `Disguise` (vim look-alike "hacker typer" over `disguise_code`) and `readDisguiseKey`; Esc returns instead of Space; `main.zig` keeps a global `Disguise`. ([input-terminal](features/input-terminal.md), [rendering](features/rendering.md))
- `0b9c13c` feat: freeze the rival one level ahead until the hero arrives. `rivalAwayRound` returns while `rival.level > g.level`, so the lead is at most 1 level and the hero finds it near the start (`placeRivalAhead(0)`). ([rival](features/rival.md))
- `fd6a9df` feat: add a rival adventurer who races down the dungeon. `Rival`/`RivalStatus` on `Game`, `huntChance`, on-map AI `rivalTurn`, off-screen race `rivalAwayRound`/`rivalCrossedLevel`, `rivalOnNewLevel`/`rivalLeftBehind`; monsters target the nearer of hero and rival; new `Tile.remains`; `openChest` now calls `rollChest(inv)`; the hero's attack setup moved to `heroStrike`; `main.zig` prints how deep the rival got. ([rival](features/rival.md) new, [monsters](features/monsters.md), [rendering](features/rendering.md), [backlog](backlog.md))

## 2026-11-16

- `3b375c4` feat: add ghosts that walk through walls. `MonsterKind.ghost` (`G`, HP -1, sight 6); `canEnter` lets ghosts cross inner walls but not the border. ([monsters](features/monsters.md))
- `767d1bd` feat: add brutes that hit hard but act every other round. `MonsterKind.brute` (`B`, HP +3, bite 2, sight 2), `Monster.rested`. ([monsters](features/monsters.md))
- `48e3f16` feat: add thieves that steal gold and run away. `MonsterKind.thief` (`T`), `Monster.gold`, `moveMonsterAway`, `stolen`/`recovered`, `events.stolen`. ([monsters](features/monsters.md))
- `52e986c` feat: add slimes that split in two when they die. `MonsterKind.slime` (`S`, HP +1) and `.small_slime` (`s`); `splitSlime` runs before the clear check. ([monsters](features/monsters.md))
- `656d4fc` feat: add rats that act twice per round and come in groups. `MonsterKind.rat` (`r`, 1 HP, sight 5, 2 actions); spawn kinds rolled by level and weight (`randomMonsterKind`); rats spawn in groups of 2-3. ([monsters](features/monsters.md))
- `855a0ac` feat: give monsters a kind and a sight radius. `MonsterKind` holds the letter, HP, bite, sight and messages; `monsterAct` is one monster's action; `addMonster(pos, kind)`. The plain `M` now chases from 4 tiles instead of 6. ([monsters](features/monsters.md))
- `15af93a` feat: deal double damage with sneak attacks. A hit while invisible or during time stop deals `attackDamage() * 2` (`isSneaky`, `sneak_multiplier`); render appends "(sneak attack: N damage)". ([monsters](features/monsters.md), [potions](features/potions.md), [backlog](backlog.md))
- `882d965` feat: add an invisibility potion that makes the monsters lose track of the hero. 10% of chest potions (health 40% -> 30%), price 25, 5 rounds after the drink round; monsters only wander (`monstersTurn(hidden)`), attacking ends it. `Potion.count` is 11; new `Sfx.invisible`. ([potions](features/potions.md), [monsters](features/monsters.md), [rounds](features/rounds.md), [rendering](features/rendering.md), [sound](features/sound.md), [shop](features/shop.md), [backlog](backlog.md))
- `edc1415` feat: add fountain levels with offerings, and totems. A fountain replaces 30% of shops: free +5 HP once, and 40 gold for +2 max HP. A totem may replace a loot spot (10%, never two levels in a row): full heal or a curse. `max_hp` became `Game.max_hp` (`start_max_hp` is the old constant); all heals go through `Game.heal`; the curse roll moved to `randomCurse`. ([fountains-totems](features/fountains-totems.md) new, [shop](features/shop.md), [levels](features/levels.md), [potions](features/potions.md), [rendering](features/rendering.md), [backlog](backlog.md))
- `0fe16e0` docs: plan new monsters, sneak attacks, level-up perks and altars. Added them as a to-do list of next steps, plus the unusable 10th inventory slot as a known issue. ([backlog](backlog.md))
- `3e9fe1e` feat: reward chest rolls for killing every monster on a level. `openChest` now holds the chest roll; `giveClearReward` rolls `rewardChests(level)` of them on the last kill. ([monsters](features/monsters.md), [potions](features/potions.md), [sound](features/sound.md))
- `30859f8` feat: add a panic key that hides the game behind a fake test run. The disguise is a `python -m pytest -v` run in `C:\Users\dev\projects\gestao-qualidade`. Space on any screen shows `renderDisguise`; only Space returns. ([input-terminal](features/input-terminal.md), [rendering](features/rendering.md))
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
