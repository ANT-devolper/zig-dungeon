# Input and terminal

Code: `src/term.zig` (`RawMode.enable`, `RawMode.restore`), `readKey` (in `src/root.zig`, tested), `leaveScreen`, `alt_screen_on/off`, `ctrl_c` and the main loop in `src/main.zig`.

## One key at a time (no Enter)

A user request: every key press acts at once, as if Enter were pressed after it.

- `term.RawMode.enable()` turns off line buffering and echo on stdin; `defer raw.restore()` puts the old mode back.
  - **Windows:** std 0.17 has no `SetConsoleMode`, so `term.zig` declares `GetStdHandle`, `GetConsoleMode`, `SetConsoleMode` with `extern "kernel32"`. It clears `ENABLE_LINE_INPUT`, `ENABLE_ECHO_INPUT` and `ENABLE_PROCESSED_INPUT`, and sets `ENABLE_VIRTUAL_TERMINAL_INPUT` so the arrow keys arrive as escape sequences (without it `ReadFile` drops them: no bytes at all).
  - **POSIX:** `std.posix.tcgetattr`/`tcsetattr`, clearing `ICANON`, `ECHO`, `ISIG` and `ICRNL` (so Enter is `\r` like on Windows), with `VMIN` 1, `VTIME` 0.
  - When stdin is not a console (a redirected file), it does nothing.
- std's reader (`NtReadFile` on Windows) returns each key in this mode: **verified by the user** in a real console.
- `readKey` (`src/root.zig`, works on any `*std.Io.Reader`, so it is tested with `.fixed`) reads one byte with `takeByte`, skips `\n` (only redirected files have it) and returns null at EOF. On the map, Enter (`\r`) and tab do nothing; on the `i` screen any non-number key closes it. Space is the panic button (below). `m` (`music_key`, not a `Command`) toggles the music in `playRun` without a turn (see [sound](sound.md)).
- **Arrow keys** (a user request: they move like WASD): `readKey` turns `ESC [ A/B/C/D` and `ESC O A/B/C/D` into `w`/`s`/`d`/`a`, so the map, the title cursor (up/down) and the `i` screen (closes it) need no other change. Other sequences (with parameters like Ctrl+arrow `ESC[1;5A`, or other final bytes like Insert `ESC[2~`) are skipped whole. `ESC` followed by another byte drops the ESC and returns that byte, so a lone Esc waits for the next key (Esc does nothing in the game).
- **Vim keys** (a user request, 2026-11-26): `h/j/k/l` are left/down/up/right in `parseCommand`, in addition to WASD (WASD stays). `k`/`j` also move the title cursor (`Title.key`). No other vim features (counts, `w`/`b`).
- **Ctrl+C** arrives as the byte `0x03` (signal turned off). On the map and on the `i` screen it ends the run with `.quit` and **closes the whole game** (`playRun` returns true); on the title it closes the game. Either way the game exits through the cleanup path.

## Title screen and runs (user choices)

- `Title` in `src/root.zig` (pure, tested): `key()` handles `w`/`s` (cursor), `\r` (Enter confirms), `p` (play), `q` (quit); `render()` draws the name (`title_name`) in a wall frame, the menu with a `>` cursor and the last run (`LastRun`).
- `main.zig`: without `--no-title`, a loop: `drawTitle`, then Play starts a new `Game` and `playRun`. When the run ends (death or `q`), its last frame stays with "Press any key to return to the title." (the defeat jingle plays here), then the title comes back. Quit, Ctrl+C or the end of the input close the game.
- The title also lists the **best runs** and the end-of-run screen says "New record!" or the rank (user request, 2026-11-26): see [scores](scores.md).
- `--no-title` (combines with `--mute`): one run straight away, then the old ending (the jingle waits about 900 ms before exiting).
- On exit, the last run's frame and final score are printed after leaving the alternate screen; nothing if no run was played.
- Redirected input: Enter in a file is `\n`, which `readKey` skips, so smoke tests press `p` on the title or use `--no-title`.

## Panic button (user choices)

A user request: Space must hide the game at once and make the terminal look like work.

- **A fake editor you type into** (user choices, 2026-11-19; it replaced a static PowerShell `pytest` screen). `panic_key` (`' '`), `Disguise`, `DisguiseKey`, `readDisguiseKey` and `disguise_code` live in `src/root.zig` (pure, tested).
  - `Disguise.render` draws a vim look-alike over the whole screen, with **IDE colors** on a dark background (user request, 2026-11-19) and nothing from the game:
    - the last `disguise_rows` (20) typed lines, each with a right-aligned line number, and `~` rows below while the text is short
    - the status line `"app/inspecao.py" [+]` with `line,col` at column 60
    - `-- INSERT --`
    - finally the cursor (`ESC[r;cH`) after the last typed character
  - It overwrites each line with `ESC[K` instead of clearing, so typing does not flicker.
  - **Colors** (`ide_*` constants, 256-color dark theme): the background is 234 on every line, filled by `ESC[K`. Line numbers are gray, `~` dim blue and the status bar gray on 238. The `-- INSERT --` line is bold green. It ends with `ESC[0m` before the cursor move, so the game's next clear has no background.
    - `writeCodeLine`/`codeToken` is a small Python highlighter with these colors:
      - keywords (`if`, `for`, `return`, `import`...) purple
      - `def`, `class`, `self`, `None`, `True`, `False` blue
      - Capitalized names (classes) teal
      - names after `def`/`class` or before `(` yellow
      - strings (with `f` and triple quotes) orange
      - numbers light green
      - `#` comments green
    - Colors come from the **whole** code line, so a word being typed already has its final color. Code colors only set the foreground; spaces do not emit codes.
  - **"Hacker typer"**: whatever key is pressed types the next piece of `disguise_code`:
    - any key (arrows and Space included) adds **one character** (a user request; it was 3)
    - Enter adds up to the end of the line
    - after a new line, the next line's indentation comes by itself, like an IDE's auto-indent
    - Backspace takes back one character
    - after the end of the code it starts over
  - `disguise_code` is about 95 lines of believable Python for the made-up `gestao-qualidade` project (inspection sampling, AQL, non-conformities): lines of 75 columns at most, and no `@`, so no decorators.
- `readDisguiseKey` classifies keys:
  - `0x03` is Ctrl+C, `\r` is Enter, `0x08`/`0x7f` are Backspace, and `\n` is skipped.
  - **Esc** is an ESC with nothing buffered after it, or followed by a byte other than `[`/`O`; that byte stays unread. A real Esc key arrives alone, while arrows arrive as a whole `ESC [ x` sequence, which is consumed and types like any key.
- `panicScreen` in `main.zig` clears the screen once, renders the editor and **shows the cursor**. Each key re-renders it. **Esc** comes back (it hides the cursor again). Space can no longer come back, because typing uses it.
  - The `Disguise` is a global in `main.zig`, so the typed code stays between panics in the same session.
- It works on **every screen**: map (no turn used; the map is redrawn), inventory (redrawn and waits again), title (redrawn) and the end-of-run screen (frame and message redrawn, waits again). Before this, Space did nothing on the map and the title, and closed the inventory.
- Ctrl+C or the end of the input inside the disguise closes the game and sets `closed_hidden`, so **nothing from the game is printed on exit** (no final frame, no score, no `--no-title` jingle). The terminal just goes back to the real shell.
- Smoke tests: a space in an input file opens the disguise, and an ESC byte followed by any other byte (e.g. `printf ' abc\x1bq'`) comes back; the following byte then acts in the game.

## Alternate screen (no history)

A user request: moves must not leave copies of the map in the terminal.

- At start, `main.zig` writes `alt_screen_on` (`\x1b[?1049h`, enter the alternate screen, plus `\x1b[?25l`, hide the cursor). The alternate screen has no scrollback, so the per-frame clear (`\x1b[2J\x1b[H`) leaves no history.
- At the end, `leaveScreen` writes `alt_screen_off` (show the cursor, back to the normal screen). Then the last frame is printed once, **without** clearing, with the final score (`Final score: reached level N with G gold.`), so the result stays visible and the terminal's earlier text is kept. `errdefer` also leaves the screen on an error.

## Smoke test

Redirected files still work, with or without newlines (`d\nd\ns\nq\n` or `ddsq`):

```sh
printf "ddsixq" > in.txt
./zig-out/bin/brewdungeon.exe --mute --no-title < in.txt > out.txt
```

Never pipe the output in Git Bash (see the Gotchas in `CLAUDE.md`).
