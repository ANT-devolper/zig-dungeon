# Sound

Code: `src/sound.zig` (`Note`, `Sfx`, `synth`, `Bank`, `play`, `PlaySoundA`); `playSfx` and `afterTurn` in `src/main.zig`.

- `synth` writes 8-bit mono 22050 Hz WAV files from `Note` lists: square or noise wave, linear pitch sweep (`freq_start` -> `freq_end`), linear fade-out.
- Each `Sfx` defines its notes in `Sfx.notes()`. Current list: strike, kill, hurt, gold, chest, drink, time_stop, speed, strength, vision, stairs, won, lost.
- `Bank.init` synthesizes them all once at startup (skipped with `--mute`).
- `play` calls `PlaySoundA(SND_MEMORY | SND_ASYNC)` from winmm.dll on Windows and does nothing elsewhere. The `extern "winmm"` declaration links the DLL by itself.
- Async playback reads straight from the bank's buffers, so **the bank is a global that must outlive playback**. A new sound cuts off the previous one.
- `main.zig` triggers sounds from `Game.events` (gold, chest, drink, time_stop, speed, strength, vision, stairs), `hit_pos`/`hit_killed` (strike or kill) and `damage_taken` (hurt). After the ending jingle (won/lost) it waits about 900 ms so the process does not cut it off.
- A new effect needs a new `Sfx` value, its notes, and a line in `afterTurn`.
