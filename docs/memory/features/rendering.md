# Rendering and animations

Code: `Game.render`, `RenderOptions`, `writeHeader`, `renderInventory`, the `ansi_*` constants in `src/root.zig`; `drawFrame`, `afterTurn`, `playStrikeEffect`, `playHitEffect` in `src/main.zig`.

## Frame

- `RenderOptions{}` (the default) produces plain text with **no ANSI codes**; tests use it. Options: `color`, `flash` (red background), `shake` (row indent 0/1/2), `spark`, `fov` (see [fov.md](fov.md)).
- Layout: header line (`writeHeader`: level, HP, gold, then `TIME STOP N`, `SPEED N`, `STRENGTH +B (N)`, `VISION N` while active), blank line, the map, the message (with "(+N gold)", "(<potion>)", "(+N HP)", "(-N HP)" appended), and the help line `[w/a/s/d] move  [.] wait  [i] inventory  [q] quit` while playing. There is no `> ` prompt and no mention of Enter.
- `drawFrame` in `main.zig` clears with `\x1b[2J\x1b[H` and always sets `fov`.

## Colors (`color = true`)

| Thing | Color |
|---|---|
| hero `@` | cyan; black on cyan while fast (`ansi_fast`); red when hurt this turn |
| monster `M` | red; blue while time is stopped; white on red if it just bit |
| gold `$` | green |
| chest `&` | magenta |
| stairs `>` | yellow |
| out of sight | light gray `#`/`.` (`ansi_dim`, 256-color 248) |
| strike spark | white on magenta (`ansi_spark`) |
| healed / gold amounts | green; damage taken in red |

## Animations (`main.zig`, after each turn, in turn order)

- `game.hit_pos != null`: `playStrikeEffect` blinks a spark over the monster the hero hit (`*` if wounded, `X` if killed): 90/60/90 ms frames.
- `game.damage_taken > 0`: `playHitEffect` runs the red flash then the screen shake: 70/70/60/60 ms frames.
- Sounds are triggered in the same function (see [sound.md](sound.md)).
