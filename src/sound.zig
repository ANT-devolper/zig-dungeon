//! Sound effects: retro tones synthesized into in-memory WAV files.
//!
//! Synthesis is pure and testable. Playback uses `PlaySoundA` from
//! winmm.dll on Windows and is a no-op on other systems.
const std = @import("std");
const builtin = @import("builtin");

pub const sample_rate = 22050;
pub const header_len = 44;
pub const silence: u8 = 128;

pub const Wave = enum { square, noise };

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
    stairs,
    won,
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
            .stairs => &.{
                .{ .freq_start = 660, .ms = 90 },
                .{ .freq_start = 494, .ms = 90 },
                .{ .freq_start = 330, .ms = 160 },
            },
            .won => &.{
                .{ .freq_start = 523, .ms = 110 },
                .{ .freq_start = 659, .ms = 110 },
                .{ .freq_start = 784, .ms = 110 },
                .{ .freq_start = 1047, .ms = 300 },
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

    var i: usize = header_len;
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
                .noise => blk: {
                    // xorshift32
                    noise ^= noise << 13;
                    noise ^= noise >> 17;
                    noise ^= noise << 5;
                    break :blk @as(f32, @floatFromInt(noise & 0xff)) / 127.5 - 1;
                },
            };
            const envelope = n.volume * (1 - t);
            buf[i] = @intFromFloat(@round(@as(f32, silence) + 127 * value * envelope));
            i += 1;
        }
    }
    return buf[0..total];
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

test "noise is deterministic" {
    var a: [max_wav_len]u8 = undefined;
    var b: [max_wav_len]u8 = undefined;
    try testing.expectEqualSlices(u8, synth(&a, Sfx.strike.notes()), synth(&b, Sfx.strike.notes()));
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
