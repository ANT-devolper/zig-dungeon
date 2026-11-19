# Rendering and animations

Code: `Game.render`, `RenderOptions`, `writeHeader`, `renderInventory`, the `ansi_*` constants in `src/root.zig`; `drawFrame`, `afterTurn`, `playStrikeEffect`, `playHitEffect` in `src/main.zig`.

## Frame

- `RenderOptions{}` (the default) produces plain text with **no ANSI codes**; tests use it. Options: `color`, `flash` (red background), `shake` (row indent 0/1/2), `spark`, `fov` (see [fov.md](fov.md)).
- Layout: header line (`writeHeader`: `Level N` with no maximum, plus ` (SHOP)` in a shop or ` (FOUNTAIN)` on a fountain level, `HP hp/max_hp` (max HP grows with offerings), gold, then `TIME STOP N`, `SPEED N`, `STRENGTH +B (N)`, `VISION N`, `INVISIBLE N`, `SLOW N`, `BLIND N`, `CONFUSED N`, `PARALYZED` while active, then `RIVAL Lv N` once the rival is met and alive, with ` HP x/y` while the hero sees it), blank line, the map, the message (with "(+N gold)", "(<potion>)", "(+N HP)", "(-N HP)" appended), and the help line `[w/a/s/d] move  [.] wait  [i] inventory  [q] quit` while playing. There is no `> ` prompt and no mention of Enter.
- The panic screen (`renderDisguise`, a fake PowerShell pytest run) is drawn instead of the frame while the panic key is active; see [input-terminal.md](input-terminal.md#panic-button-user-choices).
- `drawFrame` in `main.zig` clears with `\x1b[2J\x1b[H` and always sets `fov`.

## Colors (`color = true`)

| Thing | Color |
|---|---|
| hero `@` | cyan; black on cyan while fast (`ansi_fast`); gray while invisible (`ansi_invisible`); red when hurt this turn or cursed |
| monster `M` | red; blue while time is stopped; white on red if it just bit |
| gold `$` | green |
| chest `&` | magenta |
| stairs `>` | yellow |
| fountain `~` | blue; dimmed once used |
| offering `+` | yellow |
| totem `Y` | purple (`ansi_purple`), hidden in the fog |
| out of sight | light gray `#`/`.` (`ansi_dim`, 256-color 248) |
| strike spark | white on magenta (`ansi_spark`) |
| healed / gold amounts | green; damage taken in red |

## Animations (`main.zig`, after each turn, in turn order)

- `game.hit_pos != null`: `playStrikeEffect` blinks a spark over the monster the hero hit (`*` if wounded, `X` if killed): 90/60/90 ms frames.
- `game.damage_taken > 0`: `playHitEffect` runs the red flash then the screen shake: 70/70/60/60 ms frames.
- Sounds are triggered in the same function (see [sound.md](sound.md)).
- The rival: a magenta `@` (`ansi_magenta`, white on red `ansi_bite` when it just hit the hero), only where the hero sees. Its remains `%` are magenta. `rival_message` is drawn in magenta on its own line under the message, only when set; rival loot taken appends ` (+N gold, M potions)` to the message. See [rival.md](rival.md).
- Shop: items `!` in their potion's color (`Potion.color`), the shopkeeper `@` in orange (`ansi_shopkeeper`), a `For sale:` line (`writeForSale`) before the message, no field of view. See [shop.md](shop.md).
- The hero's `@` is red while hurt or cursed (`isCursed()`), which wins over the speed background.
- Title screen (`Title.render`): **every line fits the map's width** (`W` + the 1-column indent; a user request, checked by a test). A `#` frame as wide as the map with `B R E W D U N G E O N` centered in yellow (`frameLine`), `> Play` / `  Quit` with the selected line in cyan, `Last run: level N, G gold`, and the help line `[w/s] select  [Enter] confirm` (`p` and `q` still work but are not shown, a user choice). See [input-terminal.md](input-terminal.md).
