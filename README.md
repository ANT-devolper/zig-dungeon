# zig-dungeon

A small turn-based dungeon crawler for the terminal, written in [Zig](https://ziglang.org/).

```
DUNGEON  Level 1/3   HP 10/10   Gold 0

##############################
#...........#.......#>#.....##
#########.#.#.###M#.#.#.###.##
#........@........#.#M..#...##
#.#############.#.#.#####.#.##
#.#$#...............#...#...##
#.#.#####.#######.###.#.#.#.##
#.#.....#.#.......#$..#.....##
#.#####.#.#.###.#.###.#####.##
#.......#....$#......M#$....##
##############################
##############################

Find the stairs (>)! Beware of the monsters (M).
[w/a/s/d] move  [.] wait  [i] inventory  [q] quit
```

## Requirements

- Zig **0.17.1**. The code uses the new `std.Io` API, so older versions will not compile it.
- A terminal with ANSI escape support to clear the screen (Windows Terminal, the VS Code terminal or any Linux/macOS terminal).

## Build and run

```sh
zig build run
```

Or build the executable and run it directly:

```sh
zig build                         # debug build
zig build -Doptimize=ReleaseFast  # optimized build
./zig-out/bin/dungeon             # on Windows: .\zig-out\bin\dungeon.exe
```

## How to play

The game takes over the whole terminal window while you play, so moves leave no history behind. When it ends, only the last screen and your score stay in the terminal.

Press a key. It acts at once, with no need to press **Enter**:

| Key | Action     |
|-----|------------|
| `w` | move up    |
| `s` | move down  |
| `a` | move left  |
| `d` | move right |
| `.` | wait       |
| `i` | open the inventory (does not use a turn; any key other than a number closes it) |
| `1`-`9` | use the item with that number in the inventory (uses a turn), from the inventory or the map |
| `q` | quit (Ctrl+C also quits) |

| Symbol | Meaning            |
|--------|--------------------|
| `@`    | you, the hero (cyan; red when hurt) |
| `M`    | monster (red)      |
| `$`    | gold, +10 (green)  |
| `&`    | chest: 20-50 gold or a potion (magenta) |
| `>`    | stairs, your goal (yellow) |
| `#`    | wall               |

### Rules

- You start with **10 HP**.
- Walk into a monster to attack it. Each hit deals 2 damage and monsters have 3 HP, so it takes two hits. A hit makes the monster blink with a `*`, or with an `X` when it dies.
- You only see what is in your line of sight, up to 5 tiles away, and walls block your view. Outside it the maze is drawn in light gray, and monsters, gold and the stairs are hidden.
- Monsters within 6 tiles chase you. Farther away, they wander around at random. A monster next to you bites for 1 damage per turn.
- Taking damage flashes and shakes the screen. The hero turns red and the attacking monster is drawn white on red.
- Take the stairs to go down a level. Your HP and gold carry over.
- There are **3 levels**. The number of monsters grows on each one (3, 5 and 7).
- Every level is a randomly generated maze with a few shortcuts, so each run is different. The stairs are always reachable at the far end of the maze, and loot tends to hide in dead ends. Each item spot holds gold or, 1 time in 4, a chest. A chest holds either 20 to 50 gold or a potion.
- Most chests (85%) hold a potion; the other 15% hold gold (never both). Chest potions are a **time stop potion** 10% of the time, a **speed potion** 15% of the time and a **vision potion** 10% of the time; these are single kinds with no sizes. Another 15% are **strength potions**: small (+1 damage, 50%), medium (+2 damage, 35%) or large (+3 damage, 15%). The other 50% are health potions: small (+1 HP, 50%), medium (+3 HP, 35%) or large (+5 HP, 15%).
- The game runs in **rounds**. Normally each of your actions is one round. Monsters act, and effect counters tick, once per round.
- **Time stop** freezes every monster for the round you drink it and 3 more rounds: they do not move or attack, but you can still hit them. Frozen monsters turn blue and the status line shows `TIME STOP N`, the free rounds left. Drinking another one resets it to 3. It works at full health.
- **Speed** makes you fast for 10 rounds: you get **2 actions per round**, so monsters move and bite only once for every 2 of your actions. That is 20 actions in total, counting the one where you drink it. Your `@` gets a cyan background and the status line shows `SPEED N`. Drinking another one resets it to 10.
- **Strength** adds its bonus to your attack damage (normally 2) for the round you drink it and 3 more rounds, whatever the size. The status line shows `STRENGTH +B (N)`: the bonus and the rounds left. Drinking another strength potion while one is active **adds** its bonus and resets the counter to 3 (small + large = +4). It works at full health.
- **Vision** lets you see the whole map (monsters, gold, chests and the stairs) for the round you drink it and 3 more rounds. The status line shows `VISION N`, the rounds left. Drinking another one resets it to 3. It works at full health.
- **Effects combine.** With speed and time stop together, each frozen round lasts 2 of your actions, so `TIME STOP` only drops once for every 2 actions. Strength and vision work with all of them too, and with speed they last 2 actions per round.
- Potions go to your inventory, which numbers items in the order you picked them up. When an item runs out, the ones below move up, so the numbers are always 1, 2, 3... Drinking uses a turn and never heals past 10 HP. Typing a number with no item, or drinking at full health, uses no turn.
- Take the stairs on level 3 and you **win**. If your HP reaches 0, you **lose**.

## Sound

On Windows the game plays retro sound effects for strikes, kills, damage, gold, stairs, victory and defeat. They are synthesized in code (square waves, noise and pitch sweeps) into in-memory WAV files, so there are no audio assets or libraries. On other systems the game is silent.

To play without sound:

```sh
zig build run -- --mute
./zig-out/bin/dungeon --mute
```

## Tests

```sh
zig build test --summary all
```

The tests cover command parsing, movement, combat, monster AI, level changes, winning and losing, the visual effects (strike spark, colors, flash and shake), and the sound synthesizer (WAV header, durations, fade-out and deterministic noise). One test checks that every level has a path from the start to the stairs.

## Project layout

```
build.zig       build script (run and test steps)
build.zig.zon   package manifest
src/root.zig    pure game logic (map, turns, monsters, rendering) and its tests
src/sound.zig   sound effect synthesizer (in-memory WAV) and Windows playback
src/main.zig    entry point: input/output loop, animations and sound
```

The game logic in `src/root.zig` does no I/O. It renders to any `std.Io.Writer`, so it can be tested without a terminal.
