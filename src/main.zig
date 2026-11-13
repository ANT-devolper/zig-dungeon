const std = @import("std");
const Io = std.Io;
const dungeon = @import("dungeon");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // Random seed from the operating system.
    var seed_bytes: [8]u8 = undefined;
    io.random(&seed_bytes);
    var prng = std.Random.DefaultPrng.init(std.mem.readInt(u64, &seed_bytes, .little));

    var game = dungeon.Game.init(prng.random());

    var out_buf: [4096]u8 = undefined;
    var out_file: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const out = &out_file.interface;

    var in_buf: [256]u8 = undefined;
    var in_file: Io.File.Reader = .init(.stdin(), io, &in_buf);
    const in = &in_file.interface;

    while (game.state == .playing) {
        try drawFrame(out, &game, .{ .color = true });

        const line = try in.takeDelimiter('\n') orelse break; // EOF (Ctrl+Z / end of pipe)
        if (dungeon.parseCommand(line)) |cmd| {
            game.step(cmd);
            // Same order as the turn: the hero's strike, then the monsters' bites.
            if (game.hit_pos != null) try playStrikeEffect(io, out, &game);
            if (game.damage_taken > 0) try playHitEffect(io, out, &game);
        } else {
            game.message = "Invalid command. Use w/a/s/d, . or q.";
        }
    }

    try drawFrame(out, &game, .{ .color = true });
    try out.print("\nFinal score: {d} gold, level {d}.\n", .{ game.gold, game.level });
    try out.flush();
}

/// Clears the screen and draws one frame.
fn drawFrame(out: *Io.Writer, game: *const dungeon.Game, opts: dungeon.RenderOptions) !void {
    try out.writeAll("\x1b[2J\x1b[H"); // clear the screen (ANSI)
    try game.render(out, opts);
    try out.flush();
}

/// Short animation when the hero hits a monster: a spark blinks over it.
fn playStrikeEffect(io: Io, out: *Io.Writer, game: *const dungeon.Game) !void {
    const frames = [_]struct { opts: dungeon.RenderOptions, ms: i64 }{
        .{ .opts = .{ .color = true, .spark = true }, .ms = 90 },
        .{ .opts = .{ .color = true }, .ms = 60 },
        .{ .opts = .{ .color = true, .spark = true }, .ms = 90 },
    };
    for (frames) |f| {
        try drawFrame(out, game, f.opts);
        try io.sleep(Io.Duration.fromMilliseconds(f.ms), .awake);
    }
}

/// Short animation when the hero gets hurt: red flash, then a screen shake.
fn playHitEffect(io: Io, out: *Io.Writer, game: *const dungeon.Game) !void {
    const frames = [_]struct { opts: dungeon.RenderOptions, ms: i64 }{
        .{ .opts = .{ .flash = true, .shake = 2 }, .ms = 70 },
        .{ .opts = .{ .flash = true, .shake = 0 }, .ms = 70 },
        .{ .opts = .{ .color = true, .shake = 2 }, .ms = 60 },
        .{ .opts = .{ .color = true, .shake = 0 }, .ms = 60 },
    };
    for (frames) |f| {
        try drawFrame(out, game, f.opts);
        try io.sleep(Io.Duration.fromMilliseconds(f.ms), .awake);
    }
}
