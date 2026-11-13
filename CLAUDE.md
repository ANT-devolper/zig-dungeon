# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`zig-dungeon` is a small turn-based dungeon crawler for the terminal, written in Zig. The player (`@`) moves through 3 randomly generated ASCII mazes, fights monsters (`M`), collects gold (`$`) and takes the stairs (`>`). Input is line-based: a key and then Enter. See `README.md` for the player-facing rules.

## Toolchain

- **Zig 0.17.1**, which `build.zig.zon` pins as `minimum_zig_version`. Older versions will not compile the code.
- The code uses the new **`std.Io`** API. Many tutorials and examples online target older Zig and will not compile. Before using an API you are unsure about, check it in the stdlib (`<zig>/lib/std/`).
- APIs verified for 0.17 and used here:
  - `pub fn main(init: std.process.Init) !void`, using `init.io`
  - stdout: `var fw: std.Io.File.Writer = .init(.stdout(), io, &buf);`, then `&fw.interface` and `flush()`
  - stdin: `var fr: std.Io.File.Reader = .init(.stdin(), io, &buf);`, then `fr.interface.takeDelimiter('\n')`, which returns `?[]u8` (`null` means EOF)
  - random seed: `io.random(&bytes)`, then `std.Random.DefaultPrng.init(u64)`
  - sleep: `io.sleep(std.Io.Duration.fromMilliseconds(n), .awake)`
  - in-memory writer for tests: `var w: std.Io.Writer = .fixed(&buf);`, then `w.buffered()`

## Commands

```sh
zig build test --summary all     # run all tests (must pass before committing)
zig test src/root.zig --test-filter "wall blocks"  # run only tests whose name contains the text
zig fmt --check src/ build.zig   # formatting check (zig fmt src/ build.zig to fix)
zig build run                    # build and play
zig build                        # build zig-out/bin/dungeon(.exe)
zig build -Doptimize=ReleaseFast # optimized build
zig build run -- --mute          # play without sound
zig build -Dtarget=x86_64-linux  # cross-compile check (sound is a no-op off Windows)
```

Smoke test without a terminal (commands from a file, output to a file; see Gotchas for why not a pipe):

```sh
printf "d\nd\ns\nq\n" > in.txt
./zig-out/bin/dungeon.exe --mute < in.txt > out.txt
```

## Architecture

```
build.zig       module "dungeon" (src/root.zig) + executable "dungeon" (src/main.zig)
build.zig.zon   package manifest (package name `.zig` is tied to the fingerprint; leave it)
src/root.zig    pure game logic + its tests (also pulls in sound.zig's tests)
src/sound.zig   sound synthesizer (pure, tested) + PlaySoundA playback (Windows only)
src/main.zig    entry point: I/O loop, strike/hit animations, sound triggers, --mute
```

- **`src/root.zig` does no I/O.** It holds the map, turns, monster AI and rendering. `Game.render(w, RenderOptions)` writes to any `*std.Io.Writer`, which is what makes the logic testable without a terminal. Keep new game logic here.
- **`src/main.zig` is a thin shell.** It seeds the RNG, then loops: draw a frame, read a line, call `parseCommand`, call `Game.step`. Then it plays the turn's effects in turn order. If `game.hit_pos != null`, `playStrikeEffect` blinks a spark over the monster the hero hit (`*` if wounded, `X` if killed). If `game.damage_taken > 0`, `playHitEffect` runs the red flash and screen shake.
- **Field of view** (`Game.visibility`): the hero sees tiles within `view_radius` (5, a rounded circle `dx²+dy² <= r²+r`) when a Bresenham line in either direction crosses no wall between the two ends (`lineIsClear`). The wall that blocks the view is visible. With `RenderOptions.fov`, tiles out of sight are drawn as plain `#` or `.` in light gray (`ansi_dim`, 256-color 248), which hides monsters, gold and the stairs. There is no memory of tiles already seen. `main.zig`'s `drawFrame` always turns `fov` on, while tests render without it unless they set it. The user chose all of these behaviors (radius 5, walls block, the stairs hide too, dimmed maze instead of blank).
- **Inventory:** `Game.inventory` (`Inventory` struct) holds what the hero carries: `gold` (the score), `potions[Potion.count]` (counts indexed by `Potion.index()`) and `slots`/`slot_count`, the usable items **in pick-up order**. Numbers are positions, not fixed per kind (a user rule): `add` appends a kind the hero did not have, and `remove` drops a kind that runs out and shifts the rest up, so the numbers are always 1..n with no gaps. Always go through `add`/`remove`, never write `potions` directly, or `slots` gets out of sync. `renderInventory` lists only what the hero has (zero gold hidden), shows "(empty)" when there is nothing, and offers `[1-n] use`. Keys `1`-`9` parse to `Command.use_1..use_9` (`Command.slot()` gives the 0-based slot). They work from the map too, and a number with no item uses no turn. The `i` key (`Command.inventory`) is a pause screen: `main.zig` draws `renderInventory` and reads one line. A number runs `step(.use_N)` plus `afterTurn` (sounds and animations); anything else closes the screen **without** calling `Game.step`. `step(.inventory)` is a no-op as a safety net.
- **Potions** (`Potion`: small +1, medium +3, large +5 HP, plus `time_stop`): a chest has a `chest_potion_chance` (50%) chance to hold one **instead of gold, never both** (a user rule). The potion is `time_stop` with `time_stop_chance` (10%). Otherwise it is a health potion size from `Potion.fromRoll` (50/35/15), which never returns `time_stop`, because **time stop is a single kind with no sizes** (a user rule). The result is stored in `Game.chest_potion` (or `Game.chest_gold`) for that turn. `Game.drink` caps healing at `max_hp` and records `Game.healed`. For a health potion it returns false (no turn: `step` returns before `monstersTurn`) when HP is already full. `render` appends "(<label>)" or "(+N gold)", and "(+N HP)". Use `Potion.label()` for names, not `@tagName`.
- **World rounds (effects combine — a user rule):** every effect counter counts **rounds, not actions**. At the end of `step`, while `speed > 0` the hero gets 2 actions per round: the first sets `half_round` and returns, and the second closes the round. Without speed, every action closes a round, which is the old behavior. `endRound()` ticks the counters once per round and calls `monstersTurn` unless time is stopped. Actions that use no turn return before this, so they never touch `half_round`. Taking the stairs resets `half_round`. New timed effects must tick in `endRound`, never per action.
- **Time stop:** drinking it sets `Game.time_stop = time_stop_turns` (3; drinking again resets, never adds), `time_stop_fresh` and `events.time_stop`. In `endRound`, a fresh time stop clears the flag without decrementing: the round it was drunk in is free, even when it was drunk in the first half of a fast round. Later rounds with `time_stop > 0` decrement and skip `monstersTurn`, so monsters are frozen for the drink round plus 3. `timeStopped()` drives the blue monsters (`ansi_blue`), and `writeHeader` shows `TIME STOP N`.
- **Speed:** `Potion.speed` (15% of chest potions; `speed_chance` follows `time_stop_chance` in the same roll) sets `Game.speed = speed_turns` (10; resets, never adds) and `events.speed`. It is always drunk at the start of a fast round, so that round counts: 10 rounds are 20 actions, including the drink. `endRound` decrements it. `isFast()` drives the hero's cyan background (`ansi_fast`; red when hurt wins), and `writeHeader` shows `SPEED N`.
- **Strength:** three sized kinds (`strength_small/medium/large`, +1/+2/+3 damage from `Potion.strength()`), 15% of chest potions (`strength_chance`, after speed in the same roll), and the size comes from `Potion.strengthFromRoll` (same 50/35/15 split). Drinking adds to `Game.strength_bonus` (**bonuses add up** — a user rule) and sets `Game.strength = strength_turns` (3, resets) plus `strength_fresh`, so like time stop the drink round is free and the bonus lasts it plus 3 rounds. `endRound` decrements it and clears the bonus at 0. Attacks deal `attackDamage()` (`hero_damage + strength_bonus`), and `writeHeader` shows `STRENGTH +B (N)`.
- **Monster AI** (`monstersTurn`): a monster next to the hero bites. Within `chase_radius` (6, Manhattan distance), it steps toward the hero (`moveMonsterToward`). Otherwise it has a `wander_chance` (30%) chance per turn to step in a random free direction (`wander`). Both kinds of step use `isFreeForMonster`: no wall, no other monster, not the hero.
- **Per-turn effect state** (`damage_taken`, `hit_pos`, `hit_killed`, `events`, `Monster.bit`) is reset at the start of `Game.step`. The renderer reads it, and `RenderOptions` (`color`, `flash`, `shake`, `spark`) chooses how each frame looks.
- **No allocations.** The map is `[H][W]Tile` and monsters live in a fixed array (`max_monsters`). Keep it that way unless a feature really needs dynamic memory.
- **Levels are generated mazes.** `Game.generateLevel` retries `tryGenerateLevel` until the result is good:
  1. `carveMaze` builds a perfect maze with a recursive backtracker (fixed-size stack, no allocations). Maze cells sit on odd coordinates (`cellTile`), so there are 14×5 cells. Because 30×12 is even, column `W-2` and row `H-2` stay wall, which gives a double border on the right and at the bottom. The user chose to keep this instead of resizing to 31×13.
  2. `carveShortcuts` opens `maze_loops` (8) extra walls between cells, creating loops. It only ever adds paths, so all floor stays connected and **the stairs are always reachable**. It never opens (even, even) tiles, so corridors stay one tile wide.
  3. The hero starts on a random cell. The stairs go on the floor tile farthest from the hero (`distanceMap`, a BFS), at least `min_stairs_distance` steps away. `spawnLoot` fills `loot_count` (4) item spots, preferring dead ends (`isDeadEnd`). Each spot holds a chest (`&`, `chest_chance` 25%) or gold (`randomLoot`). A chest gives `chest_gold_min`..`chest_gold_max` (20–50) gold, stored in `Game.chest_gold` for that turn. `render` appends "(+N gold)" to the message, so no formatted text is stored in `Game`. Do not store slices into `Game`'s own memory, because `Game.init` returns it by value. Monsters spawn at random with `spawnMonsters`.
- **Level tests:** `"generated mazes are always valid and finishable"` checks every level of 500 seeds with `expectValidLevel`: borders, a single reachable stairs tile, connectivity, one-tile corridors and spawns. Other tests cover gold in dead ends and the shortcut count. Keep them passing when you change the generator. `Layout` and `loadLayout` exist only for hand-drawn test maps.
- **Randomness** goes through `Game.rng`. In tests, build the game with `testGame(&prng, layout)` and a fixed seed. Test layouts can place `M` and `$` directly, so nothing in them is random.
- **Sound** (`src/sound.zig`): `synth` writes 8-bit mono 22050 Hz WAV files from `Note` lists (square or noise, linear pitch sweep, linear fade-out). Each `Sfx` defines its notes. `Bank.init` synthesizes them all once. `play` calls `PlaySoundA(SND_MEMORY | SND_ASYNC)` from winmm.dll on Windows and does nothing elsewhere; the `extern "winmm"` declaration links the DLL by itself. Async playback reads straight from the bank's buffers, so the bank is a global that must outlive playback. A new sound cuts off the previous one. `main.zig` triggers sounds from `Game.events`, `hit_pos`/`hit_killed` and `damage_taken`, and waits about 900 ms after the ending jingle.
- **Rendering:** `RenderOptions{}` (the default) produces plain text with no ANSI codes. Colors, flash and shake are opt-in. The screen is cleared with ANSI `\x1b[2J\x1b[H`.

## Conventions

- **English everywhere in the repo:** code, comments, test names, identifiers, game text, docs and commit messages.
- **Conventional Commits:** `feat: ...`, `fix: ...`, `docs: ...`, `test: ...`, `refactor: ...`, `chore: ...`, `build: ...`, with a lowercase imperative description. Do **not** add `Co-Authored-By` or any other AI attribution lines.
- Game text is plain ASCII (no accents), because the Windows console may not render UTF-8.
- Every behavior change comes with a test in `src/root.zig`. Name tests with a sentence, e.g. `test "wall blocks the hero"`.
- Before committing, `zig fmt --check src/ build.zig` and `zig build test` must both pass.
- Update `README.md` when player-facing rules or controls change.

## Gotchas

- **Do not pipe the game's output in Git Bash** (`... | dungeon.exe | grep`, or `out=$(dungeon.exe ...)`). Once a pipe fills up (a field-of-view frame is over 5 KB), Zig 0.17.1's Windows writer panics with `reached unreachable code` / `.PENDING ... wrong File nonblocking flag`. Both `File.Writer.init` and `initStreaming` fail the same way. Redirect to a file instead (`> out.txt`). In a real console (Windows Terminal, PowerShell, VS Code) this does not happen.

- 0.17 renamed or removed some builtins and std helpers. `zig fmt` rewrites `@intFromEnum` to `@backingInt`, and `std.meta.fields` is a compile error (use `@typeInfo` or `std.enums.values(E)`). Run `zig fmt` after writing code.
- The array repetition operator `**` no longer compiles in 0.17. Use `@splat`, e.g. `var seen: [H][W]bool = @splat(@splat(false));`.
- On Windows, `zig build` fails at the "install" step if `dungeon.exe` is running. Close the game and build again.
- Lines read from stdin on Windows end with `\r`. `parseCommand` trims it, so keep that in mind for any new input parsing.
- The default branch is `main` and the remote is `origin` (GitHub). Push authentication is set up per machine in local git config. Do not change the global git config.
