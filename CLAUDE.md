# CLAUDE.md

Guidance for working in this repository.

## Project

`zig-dungeon` is a small turn-based dungeon crawler for the terminal, written in Zig. The player (`@`) moves through 3 hand-made ASCII levels, fights monsters (`M`), collects gold (`$`) and takes the stairs (`>`). Input is line-based: a key and then Enter. See `README.md` for the player-facing rules.

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
```

Smoke test without a terminal (pipe commands into stdin):

```sh
printf "d\nd\ns\nq\n" | ./zig-out/bin/dungeon.exe
```

## Architecture

```
build.zig       module "dungeon" (src/root.zig) + executable "dungeon" (src/main.zig)
build.zig.zon   package manifest (package name `.zig` is tied to the fingerprint; leave it)
src/root.zig    pure game logic + all tests
src/main.zig    entry point: I/O loop and the strike/hit animations
```

- **`src/root.zig` does no I/O.** It holds the map, turns, monster AI and rendering. `Game.render(w, RenderOptions)` writes to any `*std.Io.Writer`, which is what makes the logic testable without a terminal. Keep new game logic here.
- **`src/main.zig` is a thin shell.** It seeds the RNG, then loops: draw a frame, read a line, call `parseCommand`, call `Game.step`. Then it plays the turn's effects in turn order. If `game.hit_pos != null`, `playStrikeEffect` blinks a spark over the monster the hero hit (`*` if wounded, `X` if killed). If `game.damage_taken > 0`, `playHitEffect` runs the red flash and screen shake.
- **Per-turn effect state** (`damage_taken`, `hit_pos`, `hit_killed`, `Monster.bit`) is reset at the start of `Game.step`. The renderer reads it, and `RenderOptions` (`color`, `flash`, `shake`, `spark`) chooses how each frame looks.
- **No allocations.** The map is `[H][W]Tile` and monsters live in a fixed array (`max_monsters`). Keep it that way unless a feature really needs dynamic memory.
- **Levels** are string literals in `levels`. A `comptime` block checks that every row is exactly `W` wide. A test runs a BFS on each level to check that the start can reach the stairs, so new levels are covered automatically.
- **Randomness** goes through `Game.rng`. In tests, build the game with `testGame(&prng, layout)` and a fixed seed. Test layouts can place `M` and `$` directly, so nothing in them is random.
- **Rendering:** `RenderOptions{}` (the default) produces plain text with no ANSI codes. Colors, flash and shake are opt-in. The screen is cleared with ANSI `\x1b[2J\x1b[H`.

## Conventions

- **English everywhere in the repo:** code, comments, test names, identifiers, game text, docs and commit messages.
- **Conventional Commits:** `feat: ...`, `fix: ...`, `docs: ...`, `test: ...`, `refactor: ...`, `chore: ...`, `build: ...`, with a lowercase imperative description. Do **not** add `Co-Authored-By` or any other AI attribution lines.
- Game text is plain ASCII (no accents), because the Windows console may not render UTF-8.
- Every behavior change comes with a test in `src/root.zig`. Name tests with a sentence, e.g. `test "wall blocks the hero"`.
- Before committing, `zig fmt --check src/ build.zig` and `zig build test` must both pass.
- Update `README.md` when player-facing rules or controls change.

## Gotchas

- The array repetition operator `**` no longer compiles in 0.17. Use `@splat`, e.g. `var seen: [H][W]bool = @splat(@splat(false));`.
- On Windows, `zig build` fails at the "install" step if `dungeon.exe` is running. Close the game and build again.
- Lines read from stdin on Windows end with `\r`. `parseCommand` trims it, so keep that in mind for any new input parsing.
- The default branch is `main` and the remote is `origin` (GitHub). Push authentication is set up per machine in local git config. Do not change the global git config.
