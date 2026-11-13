# Architecture

## Files

```
build.zig       module "dungeon" (src/root.zig) + executable "dungeon" (src/main.zig)
build.zig.zon   package manifest (package name `.zig` is tied to the fingerprint; leave it)
src/root.zig    pure game logic + its tests (also pulls in sound.zig's tests)
src/sound.zig   sound synthesizer (pure, tested) + PlaySoundA playback (Windows only)
src/main.zig    entry point: I/O loop, strike/hit animations, sound triggers, --mute
src/term.zig    raw stdin mode (one key at a time, no echo, Ctrl+C as a key) for Windows and POSIX
```

## Split between logic and I/O

- **`src/root.zig` does no I/O.** It holds the map, turns, monster AI and rendering. `Game.render(w, RenderOptions)` writes to any `*std.Io.Writer`, which is what makes the logic testable without a terminal. **New game logic goes here**, with tests.
- **`src/main.zig` is a thin shell.** Startup: parse `--mute`, build the sound `Bank`, turn on `term.RawMode`, seed the RNG from `io.random`, enter the alternate screen. Loop: `drawFrame` (always with `fov = true`), `readKey`, `parseCommand(&.{key})`, `Game.step`, then `afterTurn` plays sounds and animations in turn order. End: leave the alternate screen, print the last frame and the final score, play the ending jingle and wait about 900 ms. Details in [features/input-terminal.md](features/input-terminal.md) and [features/rendering.md](features/rendering.md).

## Game state (`Game` in `src/root.zig`)

- Map `[H][W]Tile` (`W` 30, `H` 12), `Tile` = wall, floor, gold, chest, stairs.
- Hero position, `hp` (`max_hp` 10), `level` (1..`last_level` 3), `state` (playing, won, lost, quit), `inventory`.
- Monsters in a fixed array (`max_monsters` 8). Level `n` spawns `min(max_monsters, 1 + 2n)` monsters: 3, 5, 7.
- Effect counters: `time_stop`, `speed`, `strength` + `strength_bonus`, `vision`, the `*_fresh` flags and `half_round` (see [features/rounds.md](features/rounds.md)).
- **Per-turn effect state** (`damage_taken`, `hit_pos`, `hit_killed`, `healed`, `chest_gold`, `chest_potion`, `events`, `Monster.bit`) is reset at the start of `Game.step`. The renderer and `main.zig` read it after the step.
- `message` is a static string. Numbers are appended by `render` ("(+N gold)", "(+N HP)", "(<potion label>)"), so **no formatted text is stored in `Game`**. Do not store slices into `Game`'s own memory, because `Game.init` returns it by value.

## Rules that hold everywhere

- **No allocations.** Fixed arrays only (`max_monsters`, fixed-size maze stack). Keep it that way unless a feature really needs dynamic memory.
- **Randomness** goes through `Game.rng`. In tests, build the game with `testGame(&prng, layout)` and a fixed seed. Test layouts (`Layout`, `loadLayout`) are hand-drawn maps that can place `@`, `M`, `$`, `>` directly, so nothing in them is random. They exist only for tests.
- Commands: `parseCommand` maps the first non-space char of a slice (case-insensitive, trims `\r`): `w/a/s/d` move, `.` wait, `i` inventory, `1`-`9` use item, `q` quit.
- Combat: moving into a monster attacks it for `attackDamage()` (`hero_damage` 2 + strength bonus); monsters have `monster_hp` 3 and bite for `monster_damage` 1. Walking onto gold gives `gold_value` 10.
