# CLAUDE.md

Guidance for working in this repository.

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
zig fmt --check src/ build.zig   # formatting check (zig fmt src/ build.zig to fix)
zig build run                    # build and play
zig build                        # build zig-out/bin/dungeon(.exe)
zig build -Doptimize=ReleaseFast # optimized build
zig build run -- --mute          # play without sound
zig build -Dtarget=x86_64-linux  # cross-compile check (sound is a no-op off Windows)
```

Smoke test without a terminal (pipe commands into stdin):

```sh
printf "d\nd\ns\nq\n" | ./zig-out/bin/dungeon.exe
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
- **Monster AI** (`monstersTurn`): a monster next to the hero bites. Within `chase_radius` (6, Manhattan distance), it steps toward the hero (`moveMonsterToward`). Otherwise it has a `wander_chance` (30%) chance per turn to step in a random free direction (`wander`). Both kinds of step use `isFreeForMonster`: no wall, no other monster, not the hero.
- **Per-turn effect state** (`damage_taken`, `hit_pos`, `hit_killed`, `events`, `Monster.bit`) is reset at the start of `Game.step`. The renderer reads it, and `RenderOptions` (`color`, `flash`, `shake`, `spark`) chooses how each frame looks.
- **No allocations.** The map is `[H][W]Tile` and monsters live in a fixed array (`max_monsters`). Keep it that way unless a feature really needs dynamic memory.
- **Levels are generated mazes.** `Game.generateLevel` retries `tryGenerateLevel` until the result is good:
  1. `carveMaze` builds a perfect maze with a recursive backtracker (fixed-size stack, no allocations). Maze cells sit on odd coordinates (`cellTile`), so there are 14×5 cells. Because 30×12 is even, column `W-2` and row `H-2` stay wall, which gives a double border on the right and at the bottom. The user chose to keep this instead of resizing to 31×13.
  2. `carveShortcuts` opens `maze_loops` (8) extra walls between cells, creating loops. It only ever adds paths, so all floor stays connected and **the stairs are always reachable**. It never opens (even, even) tiles, so corridors stay one tile wide.
  3. The hero starts on a random cell. The stairs go on the floor tile farthest from the hero (`distanceMap`, a BFS), at least `min_stairs_distance` steps away. `spawnGold` prefers dead ends (`isDeadEnd`). Monsters spawn at random with `spawnMonsters`.
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

- 0.17 renamed or removed some builtins and std helpers. `zig fmt` rewrites `@intFromEnum` to `@backingInt`, and `std.meta.fields` is a compile error (use `@typeInfo` or `std.enums.values(E)`). Run `zig fmt` after writing code.
- The array repetition operator `**` no longer compiles in 0.17. Use `@splat`, e.g. `var seen: [H][W]bool = @splat(@splat(false));`.
- On Windows, `zig build` fails at the "install" step if `dungeon.exe` is running. Close the game and build again.
- Lines read from stdin on Windows end with `\r`. `parseCommand` trims it, so keep that in mind for any new input parsing.
- The default branch is `main` and the remote is `origin` (GitHub). Push authentication is set up per machine in local git config. Do not change the global git config.
