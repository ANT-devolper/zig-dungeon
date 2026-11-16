# Brewdungeon

Brewdungeon is a small turn-based dungeon crawler for the terminal, written in [Zig](https://ziglang.org/).

```
DUNGEON  Level 1   HP 10/10   Gold 0

###############################
#$#...#.....#...#.......#....>#
#.#.#.#.#.#.#.#.#.#.###.###.#.#
#.#.#.#.#.....#...#.#.#...#.#.#
#.#.#.#.###########.#.###.#.###
#.#.....#M........#.......#&..#
#.#####.#.#.#.#####.#.#######.#
#.....#...#...#.....M.#.....#.#
#####.#########.#####.###.#.#.#
#...#........@#.#...#...#.#.#.#
#.#.#.#.#.#.#.#.#.#####.#.#.#.#
#.#.....#.......#..$......#...#
###############################

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
./zig-out/bin/brewdungeon         # on Windows: .\zig-out\bin\brewdungeon.exe
```

The game opens on a **title screen** with **Play** and **Quit**: `w`/`s` (or the Up/Down arrows) move the cursor and **Enter** confirms (or press `p` to play, `q` to quit). When a run ends, its last screen stays until you press a key, then the title comes back with your last result, so you can play again. To skip the title and start a run right away:

```sh
zig build run -- --no-title
./zig-out/bin/brewdungeon --no-title
```

## How to play

The game takes over the whole terminal window while you play, so moves leave no history behind. When you quit, only the last run's screen and its score (`Final score: reached level N with G gold.`) stay in the terminal.

Press a key. It acts at once, with no need to press **Enter**:

| Key | Action     |
|-----|------------|
| `w` or Up arrow    | move up    |
| `s` or Down arrow  | move down  |
| `a` or Left arrow  | move left  |
| `d` or Right arrow | move right |
| `.` | wait       |
| `i` | open the inventory (does not use a turn; any key other than a number closes it) |
| `1`-`9` | use the item with that number in the inventory (uses a turn), from the inventory or the map |
| `q` | give up the run (back to the title; Ctrl+C closes the whole game) |
| Space | **panic button**: hides the game behind a fake `python -m pytest -v` run in a PowerShell window, on any screen. Only Space brings the game back (nothing is lost, no turn is used) |

| Symbol | Meaning            |
|--------|--------------------|
| `@`    | you, the hero (cyan; red when hurt) |
| `M`    | monster (red)      |
| `r`    | rat (red): 1 HP, acts twice per round, comes in groups, from level 2 |
| `S` `s` | slime and small slime (red): a slime splits into two small slimes when it dies, from level 3 |
| `T`    | thief (red): steals 25 gold and runs away (kill it to get the gold back), from level 4 |
| `$`    | gold, +10 (green)  |
| `&`    | chest: 20-50 gold or a potion (magenta) |
| `>`    | stairs, your goal (yellow) |
| `!`    | potion for sale in a shop: health green, strength brown, time stop yellow, vision purple, speed blue, invisibility gray, mystery white |
| `@`    | the shopkeeper (orange) |
| `~`    | fountain: heals 5 HP once (blue) |
| `+`    | offering at a fountain: 40 gold for +2 max HP (yellow) |
| `Y`    | totem: a full heal or a curse (purple) |
| `#`    | wall               |

### Rules

- You start with **10 HP**, which is also your max HP. Offerings at fountains raise the max (the header shows `HP current/max`).
- Walk into a monster to attack it. Each hit deals 2 damage and monsters have 3 HP, so it takes two hits. A hit makes the monster blink with a `*`, or with an `X` when it dies.
- **Sneak attack**: a hit while you are **invisible** or while **time is stopped** deals **double damage**, strength included ((2 + bonus) x 2, so 4 without strength: a 3 or 4 HP monster dies in one hit). Having both at once is still double. The message shows `(sneak attack: N damage)`. Hitting still ends invisibility, but not time stop.
- You only see what is in your line of sight, up to 5 tiles away, and walls block your view. Outside it the maze is drawn in light gray, and monsters, gold and the stairs are hidden.
- Defeat every monster on a level and the stairs are revealed: they show on the map from anywhere until you go down.
- Clearing a level is also **rewarded**: the moment the last monster dies you get chest rolls straight into your inventory (each one a potion or 20 to 50 gold, like a chest). You get 1 chest on levels 1-3, 2 on levels 4-6, 3 on levels 7-9, and one more every 3 levels as the monsters get tougher.
- Monsters within 4 tiles chase you (each kind has its own sight). Farther away, they wander around at random. A monster next to you bites for 1 damage per turn.
- Taking damage flashes and shakes the screen. The hero turns red and the attacking monster is drawn white on red.
- Take the stairs to go down a level. Your HP and gold carry over.
- The dungeon has **no bottom**: every level is a new maze, and the goal is to go **as deep as you can**. Levels 1, 2 and 3 have 3, 5 and 7 monsters, and from level 4 on there are 8. Monsters also get tougher: 3 HP on levels 1-3, then **+1 HP every 3 levels** (4 HP on levels 4-6, 5 HP on 7-9, ...). Their bite always does 1 damage.
- Every level is a randomly generated maze with a few shortcuts, so each run is different. The stairs are always reachable at the far end of the maze, and loot tends to hide in dead ends. Each item spot holds gold or, 1 time in 4, a chest. A chest holds either 20 to 50 gold or a potion.
- Most chests (85%) hold a potion; the other 15% hold gold (never both). Chest potions are a **time stop potion** 10% of the time, a **speed potion** 15% of the time, a **vision potion** 10% of the time, an **invisibility potion** 10% of the time and a **mystery potion** 10% of the time; these are single kinds with no sizes. Another 15% are **strength potions**: small (+1 damage, 50%), medium (+2 damage, 35%) or large (+3 damage, 15%). The other 30% are health potions: small (+1 HP, 50%), medium (+3 HP, 35%) or large (+5 HP, 15%).
- The game runs in **rounds**. Normally each of your actions is one round. Monsters act, and effect counters tick, once per round.
- **Time stop** freezes every monster for the round you drink it and 3 more rounds: they do not move or attack, but you can still hit them. Frozen monsters turn blue and the status line shows `TIME STOP N`, the free rounds left. Drinking another one resets it to 3. It works at full health.
- **Speed** makes you fast for 10 rounds: you get **2 actions per round**, so monsters move and bite only once for every 2 of your actions. That is 20 actions in total, counting the one where you drink it. Your `@` gets a cyan background and the status line shows `SPEED N`. Drinking another one resets it to 10.
- **Strength** adds its bonus to your attack damage (normally 2) for the round you drink it and 3 more rounds, whatever the size. The status line shows `STRENGTH +B (N)`: the bonus and the rounds left. Drinking another strength potion while one is active **adds** its bonus and resets the counter to 3 (small + large = +4). It works at full health.
- **Vision** lets you see the whole map (monsters, gold, chests and the stairs) for the round you drink it and 3 more rounds. The status line shows `VISION N`, the rounds left. Drinking another one resets it to 3. It works at full health.
- **Invisibility** hides you from the monsters for the round you drink it and 5 more rounds. They stop chasing you and only wander around, even if they are right next to you, and they do not bite. **Attacking a monster gives you away**: the invisibility ends at once and the monsters act normally that round. Your `@` turns gray and the status line shows `INVISIBLE N`, the rounds left. Drinking another one resets it to 5. It works at full health.
- **Mystery**, shown as `???`, is a gamble that works at full health. Half the time it is one of the chest potions above (the message says which). The other half it is a **curse**, one of five, each just as likely, and your `@` turns red while a curse lasts:
  - **slow**: the monsters act twice per round for 3 rounds after the one you drink it in (`SLOW N`);
  - **paralysis**: your next action is lost (`PARALYZED`);
  - **burn**: 2 damage, but it never kills: you keep at least 1 HP;
  - **blind**: you see only 2 tiles away for the round you drink it and 5 more (`BLIND N`);
  - **confusion**: up/down and left/right are swapped for the round you drink it and 5 more (`CONFUSED N`).
- **Effects combine.** With speed and time stop together, each frozen round lasts 2 of your actions, so `TIME STOP` only drops once for every 2 actions. Strength and vision work with all of them too, and with speed they last 2 actions per round.
- Potions go to your inventory, which numbers items in the order you picked them up. When an item runs out, the ones below move up, so the numbers are always 1, 2, 3... Drinking uses a turn and never heals past your max HP. Typing a number with no item, or drinking at full health, uses no turn.
- **Totems.** About 1 level in 10 hides a **totem** (`Y`) in place of gold or a chest, never on two levels in a row. Walk over it and it disappears: 60% of the time it heals you completely, 40% of the time it casts one of the five curses below. It works at full health.
- **Fountains.** Sometimes the next level is a **fountain** instead of a shop (30% of the times a shop would show up; see Shops below). It is a lit room with the fountain (`~`), an offering (`+`) and the stairs, and it counts as a level. Bump the fountain to heal **5 HP**, for free, once (not at full health: then it waits for you). Walk over the offering to pay **40 gold** for **+2 max HP** (and the 2 new HP), once; without enough gold it stays there.
- **Shops.** Gold buys potions. On the stairs of every even level (2, 4, 6...) the next level may be a **shop** (or a fountain, 3 times in 10): 80% the first time, 50% every later time. Right after a shop or a fountain, the next chance is skipped. A shop counts as a level. It is one lit room with the shopkeeper (an orange `@`), 2 potions on the floor (`!`, rolled like a chest's potion) and the stairs. Walk over a potion to buy it; without enough gold it stays there. Prices follow rarity:

  | Potion | Price |
  |---|---|
  | small health, mystery | 10 |
  | medium health | 15 |
  | speed | 20 |
  | time stop, vision, invisibility | 25 |
  | large health, small strength | 30 |
  | medium strength | 45 |
  | large strength | 70 |

- If your HP reaches 0, the game is over. Your score is the deepest level you reached, plus your gold.

## Sound

On Windows the game plays retro sound effects for strikes, kills, damage, gold, stairs, shopping and defeat. They are synthesized in code (square waves, noise and pitch sweeps) into in-memory WAV files, so there are no audio assets or libraries. On other systems the game is silent.

To play without sound:

```sh
zig build run -- --mute
./zig-out/bin/brewdungeon --mute
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
