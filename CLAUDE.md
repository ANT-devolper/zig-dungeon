# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`zig-dungeon` is a small turn-based dungeon crawler for the terminal, written in Zig. The player (`@`) moves through 3 randomly generated ASCII mazes, fights monsters (`M`), collects gold (`$`) and takes the stairs (`>`). Input is one key at a time: every key press acts at once, with no Enter. See `README.md` for the player-facing rules.

## Toolchain

- **Zig 0.17.1**, which `build.zig.zon` pins as `minimum_zig_version`. Older versions will not compile the code.
- The code uses the new **`std.Io`** API. Many tutorials and examples online target older Zig and will not compile. Before using an API you are unsure about, check it in the stdlib (`<zig>/lib/std/`).
- APIs verified for 0.17 and used here:
  - `pub fn main(init: std.process.Init) !void`, using `init.io`
  - stdout: `var fw: std.Io.File.Writer = .init(.stdout(), io, &buf);`, then `&fw.interface` and `flush()`
  - stdin: `var fr: std.Io.File.Reader = .init(.stdin(), io, &buf);`, then `fr.interface.takeByte()` (`error.EndOfStream` means EOF) or `takeDelimiter('\n')`, which returns `?[]u8` (`null` means EOF)
  - std 0.17 has no `SetConsoleMode`; `src/term.zig` declares it with `extern "kernel32"`. POSIX uses `std.posix.tcgetattr`/`tcsetattr`
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

## Project memory (read this first)

Durable project memory lives in [`docs/memory/`](docs/memory/README.md). It replaces the detailed architecture notes that used to be here.

1. **Before reading code** for a question or a change, read `docs/memory/README.md` (index + "where is X" table) and the page for the topic. Open the code only for what the page does not answer.
2. **Every change updates the memory in the same commit:** the feature page(s) in `docs/memory/features/`, a new entry at the top of `docs/memory/changelog.md`, `docs/memory/decisions.md` for every new user rule or choice, and `docs/memory/backlog.md` when an item is done or raised.
3. If a page and the code disagree, the code wins: fix the page in the same change.
4. The agreed way of working (plan, tests, user tests, commits) is in `docs/memory/workflow.md`.

## Architecture (map)

```
build.zig       module "dungeon" (src/root.zig) + executable "dungeon" (src/main.zig)
build.zig.zon   package manifest (package name `.zig` is tied to the fingerprint; leave it)
src/root.zig    pure game logic + its tests (also pulls in sound.zig's tests)
src/sound.zig   sound synthesizer (pure, tested) + PlaySoundA playback (Windows only)
src/main.zig    entry point: I/O loop, strike/hit animations, sound triggers, --mute
src/term.zig    raw stdin mode (one key at a time, no echo, Ctrl+C as a key) for Windows and POSIX
```

- **`src/root.zig` does no I/O** and holds all game logic; `Game.render` writes to any `*std.Io.Writer`, so everything is testable. **`src/main.zig` is a thin shell.** See [architecture.md](docs/memory/architecture.md).
- **No allocations** (fixed arrays). **Randomness** only through `Game.rng`; tests use `testGame(&prng, layout)` with a fixed seed.
- Systems: [levels](docs/memory/features/levels.md), [field of view](docs/memory/features/fov.md), [monsters](docs/memory/features/monsters.md), [inventory](docs/memory/features/inventory.md), [chests and potions](docs/memory/features/potions.md), [rounds and timed effects](docs/memory/features/rounds.md), [input and terminal](docs/memory/features/input-terminal.md), [rendering](docs/memory/features/rendering.md), [sound](docs/memory/features/sound.md).
- User rules that are easy to break are listed in [decisions.md](docs/memory/decisions.md). Do not undo one without asking.

## Conventions

- **English everywhere in the repo:** code, comments, test names, identifiers, game text, docs and commit messages.
- **Conventional Commits:** `feat: ...`, `fix: ...`, `docs: ...`, `test: ...`, `refactor: ...`, `chore: ...`, `build: ...`, with a lowercase imperative description. Every commit also has a **body** (a user rule): a blank line after the subject, then plain English text wrapped at about 72 columns that says what changed and why (rules, numbers, files touched when useful). Do **not** add `Co-Authored-By` or any other AI attribution lines.
- Game text is plain ASCII (no accents), because the Windows console may not render UTF-8.
- Every behavior change comes with a test in `src/root.zig`. Name tests with a sentence, e.g. `test "wall blocks the hero"`.
- Before committing, `zig fmt --check src/ build.zig` and `zig build test` must both pass.
- Update `README.md` when player-facing rules or controls change.

## Gotchas

- **Do not pipe the game's output in Git Bash** (`... | dungeon.exe | grep`, or `out=$(dungeon.exe ...)`). Once a pipe fills up (a field-of-view frame is over 5 KB), Zig 0.17.1's Windows writer panics with `reached unreachable code` / `.PENDING ... wrong File nonblocking flag`. Both `File.Writer.init` and `initStreaming` fail the same way. Redirect to a file instead (`> out.txt`). In a real console (Windows Terminal, PowerShell, VS Code) this does not happen.

- 0.17 renamed or removed some builtins and std helpers. `zig fmt` rewrites `@intFromEnum` to `@backingInt`, and `std.meta.fields` is a compile error (use `@typeInfo` or `std.enums.values(E)`). Run `zig fmt` after writing code.
- The array repetition operator `**` no longer compiles in 0.17. Use `@splat`, e.g. `var seen: [H][W]bool = @splat(@splat(false));`.
- On Windows, `zig build` fails at the "install" step if `dungeon.exe` is running. Close the game and build again.
- Lines from a redirected file on Windows may end with `\r\n`. `parseCommand` trims `\r` and the map loop skips whitespace keys, so keep that in mind for any new input parsing.
- Local git has `core.autocrlf=true`: a checkout can rewrite files with CRLF, which `zig fmt --check` rejects. Convert back with `sed -i 's/\r$//' <files>`; the files then show as modified with an empty `git diff` (line endings only), so leave them out of commits. See `docs/memory/backlog.md`.
- The default branch is `main` and the remote is `origin` (GitHub). Push authentication is set up per machine in local git config. Do not change the global git config.
