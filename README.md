# zig-dungeon

A small turn-based dungeon crawler for the terminal, written in [Zig](https://ziglang.org/).

```
DUNGEON  Level 1/3   HP 10/10   Gold 0

##############################
#.@$.....#$..................#
#...$....#.......#####.......#
#..M.....#.......#...#.......#
#$........M..........#.......#
#........#.......#...#.......#
######.###......M#.###.......#
#........#...................#
#........#.........#######...#
#........#.........#.........#
#..................#........>#
##############################

Find the stairs (>)! Beware of the monsters (M).
[w/a/s/d] move  [.] wait  [q] quit  + Enter
>
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

Type a command and press **Enter**:

| Key | Action     |
|-----|------------|
| `w` | move up    |
| `s` | move down  |
| `a` | move left  |
| `d` | move right |
| `.` | wait       |
| `q` | quit       |

| Symbol | Meaning            |
|--------|--------------------|
| `@`    | you, the hero      |
| `M`    | monster            |
| `$`    | gold (+10)         |
| `>`    | stairs             |
| `#`    | wall               |

### Rules

- You start with **10 HP**.
- Walk into a monster to attack it. Each hit deals 2 damage and monsters have 3 HP, so it takes two hits. A hit makes the monster blink with a `*`, or with an `X` when it dies.
- Monsters within 6 tiles chase you. A monster next to you bites for 1 damage per turn.
- Taking damage flashes and shakes the screen. The hero turns red and the attacking monster turns yellow.
- Take the stairs to go down a level. Your HP and gold carry over.
- There are **3 levels**. The number of monsters grows on each one (3, 5 and 7).
- Take the stairs on level 3 and you **win**. If your HP reaches 0, you **lose**.

## Tests

```sh
zig build test --summary all
```

The tests cover command parsing, movement, combat, monster AI, level changes, winning and losing, and the visual effects (strike spark, colors, flash and shake). One test checks that every level has a path from the start to the stairs.

## Project layout

```
build.zig       build script (run and test steps)
build.zig.zon   package manifest
src/root.zig    pure game logic (map, turns, monsters, rendering) and its tests
src/main.zig    entry point: input/output loop
```

The game logic in `src/root.zig` does no I/O. It renders to any `std.Io.Writer`, so it can be tested without a terminal.
