//! Sound effects: retro tones synthesized into in-memory WAV files.
//!
//! Synthesis is pure and testable. Playback uses `PlaySoundA` from
//! winmm.dll on Windows and is a no-op on other systems.
const std = @import("std");
const builtin = @import("builtin");

pub const sample_rate = 22050;
pub const header_len = 44;
pub const silence: u8 = 128;

pub const Wave = enum { square, triangle, noise };

/// One synthesized segment. The frequency slides linearly from
/// `freq_start` to `freq_end` and the volume decays linearly to zero.
pub const Note = struct {
    wave: Wave = .square,
    freq_start: f32 = 0,
    /// End frequency for a sweep; null keeps the frequency constant.
    freq_end: ?f32 = null,
    ms: u32,
    /// Peak volume, 0..1.
    volume: f32 = 0.4,
};

pub const Sfx = enum {
    strike,
    kill,
    hurt,
    gold,
    chest,
    drink,
    time_stop,
    speed,
    strength,
    vision,
    invisible,
    stairs,
    buy,
    curse,
    lost,

    pub fn notes(s: Sfx) []const Note {
        return switch (s) {
            .strike => &.{
                .{ .wave = .noise, .ms = 40, .volume = 0.6 },
                .{ .freq_start = 900, .ms = 50, .volume = 0.3 },
            },
            .kill => &.{
                .{ .freq_start = 700, .freq_end = 120, .ms = 220, .volume = 0.45 },
            },
            .hurt => &.{
                .{ .freq_start = 180, .freq_end = 90, .ms = 160, .volume = 0.5 },
            },
            .gold => &.{
                .{ .freq_start = 990, .ms = 60, .volume = 0.3 },
                .{ .freq_start = 1320, .ms = 140, .volume = 0.3 },
            },
            .buy => &.{
                .{ .freq_start = 1320, .ms = 50, .volume = 0.3 },
                .{ .freq_start = 1760, .ms = 50, .volume = 0.3 },
                .{ .freq_start = 1320, .ms = 50, .volume = 0.3 },
                .{ .freq_start = 1760, .ms = 120, .volume = 0.3 },
            },
            .curse => &.{
                .{ .freq_start = 330, .freq_end = 220, .ms = 120, .volume = 0.4 },
                .{ .freq_start = 233, .freq_end = 110, .ms = 260, .volume = 0.4 },
            },
            .chest => &.{
                .{ .freq_start = 784, .ms = 80, .volume = 0.3 },
                .{ .freq_start = 988, .ms = 80, .volume = 0.3 },
                .{ .freq_start = 1319, .ms = 220, .volume = 0.3 },
            },
            .drink => &.{
                .{ .freq_start = 300, .freq_end = 900, .ms = 180, .volume = 0.25 },
            },
            .time_stop => &.{
                .{ .freq_start = 1200, .freq_end = 200, .ms = 400, .volume = 0.3 },
            },
            .speed => &.{
                .{ .freq_start = 600, .freq_end = 1200, .ms = 70, .volume = 0.3 },
                .{ .freq_start = 600, .freq_end = 1200, .ms = 70, .volume = 0.3 },
            },
            .strength => &.{
                .{ .freq_start = 220, .ms = 90, .volume = 0.35 },
                .{ .freq_start = 330, .freq_end = 440, .ms = 180, .volume = 0.35 },
            },
            .vision => &.{
                .{ .freq_start = 880, .freq_end = 1320, .ms = 120, .volume = 0.3 },
                .{ .freq_start = 1320, .ms = 160, .volume = 0.3 },
            },
            // A soft fade downwards: the hero vanishes.
            .invisible => &.{
                .{ .freq_start = 1200, .freq_end = 600, .ms = 150, .volume = 0.2 },
                .{ .freq_start = 600, .freq_end = 300, .ms = 200, .volume = 0.12 },
            },
            .stairs => &.{
                .{ .freq_start = 660, .ms = 90 },
                .{ .freq_start = 494, .ms = 90 },
                .{ .freq_start = 330, .ms = 160 },
            },
            .lost => &.{
                .{ .freq_start = 392, .ms = 200 },
                .{ .freq_start = 330, .ms = 200 },
                .{ .freq_start = 262, .freq_end = 180, .ms = 400 },
            },
        };
    }
};

pub fn samplesFor(ms: u32) usize {
    return @as(usize, ms) * sample_rate / 1000;
}

/// Total size of the WAV file (header + samples) for these notes.
pub fn wavLen(notes: []const Note) usize {
    var n: usize = header_len;
    for (notes) |note| n += samplesFor(note.ms);
    return n;
}

/// Writes a 44-byte header for 8-bit unsigned mono PCM.
fn writeHeader(h: *[header_len]u8, data_len: usize) void {
    @memcpy(h[0..4], "RIFF");
    std.mem.writeInt(u32, h[4..8], @intCast(36 + data_len), .little);
    @memcpy(h[8..12], "WAVE");
    @memcpy(h[12..16], "fmt ");
    std.mem.writeInt(u32, h[16..20], 16, .little); // fmt chunk size
    std.mem.writeInt(u16, h[20..22], 1, .little); // PCM
    std.mem.writeInt(u16, h[22..24], 1, .little); // mono
    std.mem.writeInt(u32, h[24..28], sample_rate, .little);
    std.mem.writeInt(u32, h[28..32], sample_rate, .little); // bytes per second
    std.mem.writeInt(u16, h[32..34], 1, .little); // block align
    std.mem.writeInt(u16, h[34..36], 8, .little); // bits per sample
    @memcpy(h[36..40], "data");
    std.mem.writeInt(u32, h[40..44], @intCast(data_len), .little);
}

/// Synthesizes `notes` as a complete WAV file into `buf` and returns the
/// used part. `buf` must hold at least `wavLen(notes)` bytes.
pub fn synth(buf: []u8, notes: []const Note) []u8 {
    const total = wavLen(notes);
    std.debug.assert(buf.len >= total);
    writeHeader(buf[0..header_len], total - header_len);

    writeNotes(buf[header_len..total], notes, .set);
    return buf[0..total];
}

/// How `writeNotes` stores each sample: `set` overwrites the buffer, `add`
/// mixes the notes into what is already there (clamped to 0..255).
const WriteMode = enum { set, add };

/// Synthesizes `notes` as raw 8-bit samples into `out`, which must hold
/// exactly their samples.
fn writeNotes(out: []u8, notes: []const Note, mode: WriteMode) void {
    var i: usize = 0;
    var noise: u32 = 0x1234_5678; // fixed seed: same sound every time
    for (notes) |n| {
        const count = samplesFor(n.ms);
        const count_f: f32 = @floatFromInt(count);
        const freq_end = n.freq_end orelse n.freq_start;
        var phase: f32 = 0;
        for (0..count) |s| {
            const t = @as(f32, @floatFromInt(s)) / count_f; // 0..1 through the note
            const value: f32 = switch (n.wave) {
                .square => blk: {
                    const freq = n.freq_start + (freq_end - n.freq_start) * t;
                    phase += freq / sample_rate;
                    phase -= @floor(phase);
                    break :blk if (phase < 0.5) 1 else -1;
                },
                .triangle => blk: {
                    const freq = n.freq_start + (freq_end - n.freq_start) * t;
                    phase += freq / sample_rate;
                    phase -= @floor(phase);
                    break :blk 4 * @abs(phase - 0.5) - 1;
                },
                .noise => blk: {
                    // xorshift32
                    noise ^= noise << 13;
                    noise ^= noise >> 17;
                    noise ^= noise << 5;
                    break :blk @as(f32, @floatFromInt(noise & 0xff)) / 127.5 - 1;
                },
            };
            const envelope = n.volume * (1 - t);
            const base: f32 = switch (mode) {
                .set => silence,
                .add => @floatFromInt(out[i]),
            };
            const sample = @round(base + 127 * value * envelope);
            out[i] = @intFromFloat(std.math.clamp(sample, 0, 255));
            i += 1;
        }
    }
    std.debug.assert(i == out.len);
}

// ---------------------------------------------------------------- music

/// A looping background tune: two voices played at the same time. Both
/// must last exactly as long.
pub const Music = struct {
    melody: []const Note,
    bass: []const Note,
};

/// Length of one beat in the music, in ms (about 79 beats per minute).
/// A multiple of 40 ms, so every note is a whole number of samples and
/// the two voices stay in step.
const beat = 760;

/// A melody note lasting `beats` beats, on the soft triangle wave.
fn mel(freq: f32, beats: u32) Note {
    return .{ .wave = .triangle, .freq_start = freq, .ms = beats * beat, .volume = if (freq == 0) 0 else 0.3 };
}

fn rest(beats: u32) Note {
    return mel(0, beats);
}

/// One bar of bass: two long half notes, the root and then its fifth.
fn bassBar(root: f32, fifth: f32) [2]Note {
    const n = struct {
        fn half(f: f32) Note {
            return .{ .wave = .triangle, .freq_start = f, .ms = 2 * beat, .volume = 0.35 };
        }
    }.half;
    return .{ n(root), n(fifth) };
}

// Note frequencies (Hz).
const D2 = 73.42;
const E2 = 82.41;
const F2 = 87.31;
const A2 = 110.0;
const Bb2 = 116.54;
const B2 = 123.47;
const C3 = 130.81;
const E3 = 164.81;
const F3 = 174.61;
const Gs3 = 207.65;
const A3 = 220.0;
const Bb3 = 233.08;
const B3 = 246.94;
const C4 = 261.63;
const D4 = 293.66;
const E4 = 329.63;
const F4 = 349.23;
const G4 = 392.0;
const A4 = 440.0;

/// The dungeon theme: 8 slow bars in A minor with a dark B flat
/// (Am Am F E Am Dm Bb E), 4 beats each at about 79 bpm, 24.3 s. Low triangle
/// waves and long fading notes, quiet so the sound effects stay on top.
/// It ends on a rest, so the loop joins without a click.
pub const dungeon_theme: Music = .{
    .melody = &[_]Note{
        mel(A3, 1), mel(C4, 1), mel(E4, 2), // Am
        mel(E4, 1), mel(D4, 1), mel(C4, 1), mel(B3, 1), // Am
        mel(A3, 2), mel(C4, 1), mel(A3, 1), // F
        mel(Gs3, 3), rest(1), // E
        mel(E4, 1), mel(A4, 1), mel(G4, 1), mel(E4, 1), // Am
        mel(F4, 2), mel(E4, 1), mel(D4, 1), // Dm
        mel(F4, 1), mel(D4, 1), mel(Bb3, 2), // Bb
        mel(B3, 1), mel(Gs3, 1), mel(E3, 1), rest(1), // E
    },
    .bass = &(bassBar(A2, E3) ++ bassBar(A2, E3) ++ bassBar(F2, C3) ++ bassBar(E2, B2) ++
        bassBar(A2, E3) ++ bassBar(D2, A2) ++ bassBar(Bb2, F3) ++ bassBar(E2, B2)),
};

fn samplesIn(notes: []const Note) usize {
    var n: usize = 0;
    for (notes) |note| n += samplesFor(note.ms);
    return n;
}

/// Number of raw samples (= bytes) in one loop of `m`.
pub fn musicLen(m: Music) usize {
    return samplesIn(m.melody);
}

/// Synthesizes one loop of `m` as raw 8-bit mono samples (no WAV header):
/// the melody first, then the bass mixed on top. `buf` must hold at least
/// `musicLen(m)` bytes.
pub fn synthMusic(buf: []u8, m: Music) []u8 {
    const len = musicLen(m);
    std.debug.assert(samplesIn(m.bass) == len);
    writeNotes(buf[0..len], m.melody, .set);
    writeNotes(buf[0..len], m.bass, .add);
    return buf[0..len];
}

const sfx_count = std.enums.values(Sfx).len;

const max_wav_len = blk: {
    var m: usize = 0;
    for (std.enums.values(Sfx)) |s| m = @max(m, wavLen(s.notes()));
    break :blk m;
};

/// Every sound effect, synthesized once. It must outlive any sound that
/// is still playing, because playback reads straight from these buffers.
pub const Bank = struct {
    data: [sfx_count][max_wav_len]u8,
    wavs: [sfx_count][]const u8,

    /// Fills the bank in place (the slices point into `b.data`).
    pub fn init(b: *Bank) void {
        for (std.enums.values(Sfx)) |s| {
            const i = @backingInt(s);
            b.wavs[i] = synth(&b.data[i], s.notes());
        }
    }

    pub fn get(b: *const Bank, s: Sfx) []const u8 {
        return b.wavs[@backingInt(s)];
    }
};

const SND_ASYNC = 0x0001;
const SND_NODEFAULT = 0x0002;
const SND_MEMORY = 0x0004;

extern "winmm" fn PlaySoundA(
    sound: ?*const anyopaque,
    module: ?*anyopaque,
    flags: u32,
) callconv(.winapi) c_int;

/// Starts playing a WAV in the background, cutting off any sound that is
/// already playing. Does nothing outside Windows.
pub fn play(wav: []const u8) void {
    if (builtin.os.tag == .windows) {
        _ = PlaySoundA(wav.ptr, null, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
    }
}

// ------------------------------------------------------- music playback
//
// `PlaySoundA` plays one sound at a time, so a sound effect would cut the
// music off. The music uses the waveOut API instead: its own stream, which
// Windows mixes with the sound effects, looped by the driver.

const WAVE_MAPPER: u32 = 0xFFFF_FFFF;
const CALLBACK_NULL = 0;
const WHDR_BEGINLOOP = 0x04;
const WHDR_ENDLOOP = 0x08;

const WaveFormatEx = extern struct {
    wFormatTag: u16,
    nChannels: u16,
    nSamplesPerSec: u32,
    nAvgBytesPerSec: u32,
    nBlockAlign: u16,
    wBitsPerSample: u16,
    cbSize: u16,
};

const WaveHdr = extern struct {
    lpData: [*]u8,
    dwBufferLength: u32,
    dwBytesRecorded: u32 = 0,
    dwUser: usize = 0,
    dwFlags: u32 = 0,
    dwLoops: u32 = 0,
    lpNext: ?*WaveHdr = null,
    reserved: usize = 0,
};

const HWaveOut = *anyopaque;

extern "winmm" fn waveOutOpen(phwo: *?HWaveOut, device: u32, fmt: *const WaveFormatEx, callback: usize, instance: usize, flags: u32) callconv(.winapi) u32;
extern "winmm" fn waveOutPrepareHeader(hwo: HWaveOut, hdr: *WaveHdr, size: u32) callconv(.winapi) u32;
extern "winmm" fn waveOutUnprepareHeader(hwo: HWaveOut, hdr: *WaveHdr, size: u32) callconv(.winapi) u32;
extern "winmm" fn waveOutWrite(hwo: HWaveOut, hdr: *WaveHdr, size: u32) callconv(.winapi) u32;
extern "winmm" fn waveOutPause(hwo: HWaveOut) callconv(.winapi) u32;
extern "winmm" fn waveOutRestart(hwo: HWaveOut) callconv(.winapi) u32;
extern "winmm" fn waveOutReset(hwo: HWaveOut) callconv(.winapi) u32;
extern "winmm" fn waveOutClose(hwo: HWaveOut) callconv(.winapi) u32;

/// Loops raw 8-bit mono samples in the background, paused or playing.
/// It must outlive playback (the driver reads `header` and the samples),
/// so keep it in a global. Does nothing outside Windows or when the audio
/// device cannot be opened.
pub const MusicPlayer = struct {
    handle: ?HWaveOut = null,
    header: WaveHdr = undefined,

    /// Queues `samples` to loop forever, starting paused.
    pub fn start(p: *MusicPlayer, samples: []u8) void {
        if (builtin.os.tag != .windows) return;
        const fmt: WaveFormatEx = .{
            .wFormatTag = 1, // PCM
            .nChannels = 1,
            .nSamplesPerSec = sample_rate,
            .nAvgBytesPerSec = sample_rate,
            .nBlockAlign = 1,
            .wBitsPerSample = 8,
            .cbSize = 0,
        };
        var h: ?HWaveOut = null;
        if (waveOutOpen(&h, WAVE_MAPPER, &fmt, 0, 0, CALLBACK_NULL) != 0) return;
        const hwo = h orelse return;
        _ = waveOutPause(hwo); // nothing plays until setPlaying(true)
        p.header = .{ .lpData = samples.ptr, .dwBufferLength = @intCast(samples.len) };
        if (waveOutPrepareHeader(hwo, &p.header, @sizeOf(WaveHdr)) != 0) {
            _ = waveOutClose(hwo);
            return;
        }
        // The loop flags go on after preparing, which needs them cleared.
        p.header.dwFlags |= WHDR_BEGINLOOP | WHDR_ENDLOOP;
        p.header.dwLoops = std.math.maxInt(u32);
        _ = waveOutWrite(hwo, &p.header, @sizeOf(WaveHdr));
        p.handle = hwo;
    }

    /// Pauses or resumes the loop where it was.
    pub fn setPlaying(p: *MusicPlayer, playing: bool) void {
        if (builtin.os.tag != .windows) return;
        const hwo = p.handle orelse return;
        _ = if (playing) waveOutRestart(hwo) else waveOutPause(hwo);
    }

    /// Stops the music and frees the audio device.
    pub fn stop(p: *MusicPlayer) void {
        if (builtin.os.tag != .windows) return;
        const hwo = p.handle orelse return;
        _ = waveOutReset(hwo);
        _ = waveOutUnprepareHeader(hwo, &p.header, @sizeOf(WaveHdr));
        _ = waveOutClose(hwo);
        p.handle = null;
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "synth writes a valid 8-bit mono WAV header" {
    var buf: [max_wav_len]u8 = undefined;
    const wav = synth(&buf, Sfx.hurt.notes());
    try testing.expectEqualStrings("RIFF", wav[0..4]);
    try testing.expectEqualStrings("WAVE", wav[8..12]);
    try testing.expectEqualStrings("fmt ", wav[12..16]);
    try testing.expectEqualStrings("data", wav[36..40]);
    try testing.expectEqual(@as(u32, @intCast(wav.len - 8)), std.mem.readInt(u32, wav[4..8], .little));
    try testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, wav[22..24], .little));
    try testing.expectEqual(@as(u32, sample_rate), std.mem.readInt(u32, wav[24..28], .little));
    try testing.expectEqual(@as(u16, 8), std.mem.readInt(u16, wav[34..36], .little));
    try testing.expectEqual(@as(u32, @intCast(wav.len - header_len)), std.mem.readInt(u32, wav[40..44], .little));
}

test "sample count matches the notes' duration" {
    const notes = [_]Note{ .{ .freq_start = 440, .ms = 100 }, .{ .freq_start = 880, .ms = 50 } };
    var buf: [header_len + 4000]u8 = undefined;
    const wav = synth(&buf, &notes);
    try testing.expectEqual(@as(usize, header_len + 2205 + 1102), wav.len);
}

test "sounds fade out to silence" {
    var buf: [max_wav_len]u8 = undefined;
    for (std.enums.values(Sfx)) |s| {
        const wav = synth(&buf, s.notes());
        const last = wav[wav.len - 1];
        try testing.expect(@abs(@as(i16, last) - silence) <= 3);
    }
}

test "square wave swings around silence" {
    var buf: [header_len + 2000]u8 = undefined;
    const wav = synth(&buf, &.{.{ .freq_start = 440, .ms = 50, .volume = 0.5 }});
    const samples = wav[header_len..];
    try testing.expect(std.mem.max(u8, samples) > silence + 40);
    try testing.expect(std.mem.min(u8, samples) < silence - 40);
}

test "triangle wave swings around silence without jumps" {
    var buf: [header_len + 2000]u8 = undefined;
    const wav = synth(&buf, &.{.{ .wave = .triangle, .freq_start = 220, .ms = 50, .volume = 0.5 }});
    const samples = wav[header_len..];
    try testing.expect(std.mem.max(u8, samples) > silence + 40);
    try testing.expect(std.mem.min(u8, samples) < silence - 40);
    // Unlike the square wave it ramps: neighbors are always close.
    for (samples[1..], samples[0 .. samples.len - 1]) |b, a| {
        try testing.expect(@abs(@as(i16, b) - a) <= 4);
    }
}

test "noise is deterministic" {
    var a: [max_wav_len]u8 = undefined;
    var b: [max_wav_len]u8 = undefined;
    try testing.expectEqualSlices(u8, synth(&a, Sfx.strike.notes()), synth(&b, Sfx.strike.notes()));
}

test "the dungeon theme's two voices last exactly as long" {
    var melody_ms: u32 = 0;
    for (dungeon_theme.melody) |n| melody_ms += n.ms;
    var bass_ms: u32 = 0;
    for (dungeon_theme.bass) |n| bass_ms += n.ms;
    try testing.expectEqual(melody_ms, bass_ms);
    try testing.expectEqual(@as(u32, 32 * beat), melody_ms);
}

var test_music: [musicLen(dungeon_theme)]u8 = undefined;
var test_music2: [musicLen(dungeon_theme)]u8 = undefined;

test "the dungeon theme's voices stay in step sample by sample" {
    try testing.expectEqual(samplesIn(dungeon_theme.melody), samplesIn(dungeon_theme.bass));
}

test "music loop length matches its duration" {
    const samples = synthMusic(&test_music, dungeon_theme);
    try testing.expectEqual(samplesFor(32 * beat), samples.len);
}

test "music loop ends in silence so it joins without a click" {
    const samples = synthMusic(&test_music, dungeon_theme);
    for (samples[samples.len - 100 ..]) |s| {
        try testing.expect(@abs(@as(i16, s) - silence) <= 3);
    }
}

test "music mixes both voices" {
    const both = synthMusic(&test_music, dungeon_theme);
    const melody_only = synthMusic(&test_music2, .{ .melody = dungeon_theme.melody, .bass = &.{.{ .ms = 32 * beat, .volume = 0 }} });
    try testing.expect(!std.mem.eql(u8, both, melody_only));
    // Both voices together swing wider than the melody alone.
    try testing.expect(std.mem.max(u8, both) > std.mem.max(u8, melody_only));
}

test "music synthesis is deterministic" {
    try testing.expectEqualSlices(u8, synthMusic(&test_music, dungeon_theme), synthMusic(&test_music2, dungeon_theme));
}

test "bank holds every sound effect" {
    const bank = try testing.allocator.create(Bank);
    defer testing.allocator.destroy(bank);
    bank.init();
    for (std.enums.values(Sfx)) |s| {
        const wav = bank.get(s);
        try testing.expectEqual(wavLen(s.notes()), wav.len);
        try testing.expectEqualStrings("RIFF", wav[0..4]);
    }
}
