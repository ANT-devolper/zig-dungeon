# Input and terminal

Code: `src/term.zig` (`RawMode.enable`, `RawMode.restore`), `readKey`, `leaveScreen`, `alt_screen_on/off`, `ctrl_c` and the main loop in `src/main.zig`.

## One key at a time (no Enter)

A user request: every key press acts at once, as if Enter were pressed after it.

- `term.RawMode.enable()` turns off line buffering and echo on stdin; `defer raw.restore()` puts the old mode back.
  - **Windows:** std 0.17 has no `SetConsoleMode`, so `term.zig` declares `GetStdHandle`, `GetConsoleMode`, `SetConsoleMode` with `extern "kernel32"`. It clears `ENABLE_LINE_INPUT`, `ENABLE_ECHO_INPUT` and `ENABLE_PROCESSED_INPUT`.
  - **POSIX:** `std.posix.tcgetattr`/`tcsetattr`, clearing `ICANON`, `ECHO`, `ISIG` and `ICRNL` (so Enter is `\r` like on Windows), with `VMIN` 1, `VTIME` 0.
  - When stdin is not a console (a redirected file), it does nothing.
- std's reader (`NtReadFile` on Windows) returns each key in this mode: **verified by the user** in a real console.
- `readKey` reads one byte with `takeByte`, skips `\n` (only redirected files have it) and returns null at EOF. On the map, whitespace keys (Enter `\r`, space, tab) do nothing; on the `i` screen any non-number key closes it.
- **Ctrl+C** arrives as the byte `0x03` (signal turned off). On the map and on the `i` screen it ends the run with `.quit` and **closes the whole game** (`playRun` returns true); on the title it closes the game. Either way the game exits through the cleanup path.

## Title screen and runs (user choices)

- `Title` in `src/root.zig` (pure, tested): `key()` handles `w`/`s` (cursor), `\r` (Enter confirms), `p` (play), `q` (quit); `render()` draws the name (`title_name`) in a wall frame, the menu with a `>` cursor and the last run (`LastRun`).
- `main.zig`: without `--no-title`, a loop: `drawTitle`, then Play starts a new `Game` and `playRun`. When the run ends (death or `q`), its last frame stays with "Press any key to return to the title." (the defeat jingle plays here), then the title comes back. Quit, Ctrl+C or the end of the input close the game.
- `--no-title` (combines with `--mute`): one run straight away, then the old ending (the jingle waits about 900 ms before exiting).
- On exit, the last run's frame and final score are printed after leaving the alternate screen; nothing if no run was played.
- Redirected input: Enter in a file is `\n`, which `readKey` skips, so smoke tests press `p` on the title or use `--no-title`.

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
