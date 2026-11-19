# Sound

Code: `src/sound.zig` (`Note`, `Sfx`, `synth`, `Bank`, `play`, `PlaySoundA`); `playSfx` and `afterTurn` in `src/main.zig`.

- `synth` writes 8-bit mono 22050 Hz WAV files from `Note` lists: square or noise wave, linear pitch sweep (`freq_start` -> `freq_end`), linear fade-out.
- Each `Sfx` defines its notes in `Sfx.notes()`. Current list: strike, kill, hurt, gold, chest, drink, time_stop, speed, strength, vision, invisible (a soft falling fade, 1200->600 Hz then 600->300 Hz), stairs, buy, curse, lost. (`won` was removed with the endless dungeon.)
- `Bank.init` synthesizes them all once at startup (skipped with `--mute`).
- `play` calls `PlaySoundA(SND_MEMORY | SND_ASYNC)` from winmm.dll on Windows and does nothing elsewhere. The `extern "winmm"` declaration links the DLL by itself.
- Async playback reads straight from the bank's buffers, so **the bank is a global that must outlive playback**. A new sound cuts off the previous one.
- `main.zig` triggers sounds from `Game.events` (gold, chest and reward (both `Sfx.chest`), drink, time_stop, speed, strength, vision, invisible, stairs, buy, curse and stolen (both `Sfx.curse`)), `hit_pos`/`hit_killed` (strike or kill) and `damage_taken` (hurt). After the defeat jingle (lost) it waits about 900 ms so the process does not cut it off.
- A new effect needs a new `Sfx` value, its notes, and a line in `afterTurn`.
- `synth` and `synthMusic` share `writeNotes(out, notes, .set | .add)`; `.add` mixes into the buffer (clamped 0..255).

## Music (dungeon soundtrack)

Code: `Music`, `dungeon_theme`, `musicLen`, `synthMusic`, `MusicPlayer` in `src/sound.zig`; `music_buf`, `music`, `music_on`, `in_dungeon`, `setDungeon`, `updateMusic` in `src/main.zig`; `music_key` (`'m'`) in `src/root.zig`.

- `dungeon_theme`: 8 bars in A minor (Am F G E Am F Dm E), eighth = 200 ms, 12.8 s. Two voices (melody 0.16, bass 0.14 volume, both square) mixed by `synthMusic` into raw 8-bit samples (no WAV header). It ends on a rest so the loop joins without a click. Melody and bass must last the same (asserted and tested).
- **Why not `PlaySoundA`**: it plays one sound at a time, so every sound effect would cut the music. `MusicPlayer` uses the **waveOut API** (same winmm.dll): its own stream, mixed by Windows with the effects. `start` opens `WAVE_MAPPER`, pauses, prepares one `WAVEHDR` and only then sets `WHDR_BEGINLOOP | WHDR_ENDLOOP` and `dwLoops = maxInt(u32)` (prepare needs `dwFlags` zero), then writes it. `setPlaying` = `waveOutPause`/`waveOutRestart` (resumes where it stopped). `stop` = reset, unprepare, close (deferred in `main`). If the device cannot be opened, the player stays silent. No-op off Windows.
- The player and `music_buf` are globals (the driver reads them while playing). Skipped with `--mute`.
- **When it plays** (user rule): only during a run (`playRun` calls `setDungeon(true)`, deferred `false`), so the title and the end-of-run screen are silent. The inventory keeps it playing. `panicScreen` pauses it on entry and Esc calls `updateMusic` (it must not betray the disguise).
- `m` during a run toggles `music_on` (no turn, message "Music on." / "Music off. Press m to turn it on."); the choice holds for the whole session. There is no command-line flag for it (user choice).
