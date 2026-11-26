# High scores

Code: `Scores`, `max_scores`, `writeRecord`, `Title.render` in `src/root.zig` (pure, tested); `scoresPath`, `loadScores`, `saveScores`, `recordRun` in `src/main.zig`.

A user request (2026-11-26): a local top 10 to give a reason to replay.

## Rules (user choices)

- The best **10** runs are kept, ranked by **level reached, then gold**. A tie goes after the older runs (`Scores.add`). A run that does not make the list is dropped.
- Stored in **`scores.txt` next to the executable** (`zig-out/bin/scores.txt` with `zig build`), one `<level> <gold>` per line. `zig build` does not touch it; deleting the file resets the scores.
- Shown on the **title screen** under the menu (and "Last run"): "Best runs", one row per run. The row of the run just played is cyan with a ` <` marker (`last_rank`).
- At the end of a run, `writeRecord` prints **"New record!"** (yellow) for rank 1, **"Rank N in the top 10."** for the others, and nothing when the run missed the list. It shows on the end-of-run screen (before "Press any key...") and after "Final score" on exit.
- Nothing is added to the in-game header.

## How it works

- `Scores.parse` skips bad lines and level 0, and inserts each run with `add`, so a hand-edited file is still sorted and capped. `write` is the inverse.
- `main.zig` loads the file once at startup (a missing file gives an empty list), and `recordRun` adds the run and saves right after **every** run, including one closed by Ctrl+C, the end of the input or the panic screen. Reading and writing errors are ignored: the game never fails over scores.
- The path comes from `std.process.executableDirPath`; the file is read with `Io.Dir.cwd().readFile` and written with `writeFile` (absolute paths).
- With `--no-title` the run is recorded too, and the notice prints after the final score.
- Smoke test: run a **copy** of the exe in a scratch folder (`printf "q" > in.txt`, `--mute --no-title < in.txt > out.txt`), so the real `scores.txt` is not touched.
