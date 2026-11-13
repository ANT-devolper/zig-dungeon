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
        try out.writeAll("\x1b[2J\x1b[H"); // clear the screen (ANSI)
        try game.render(out);
        try out.flush();

        const line = try in.takeDelimiter('\n') orelse break; // EOF (Ctrl+Z / end of pipe)
        if (dungeon.parseCommand(line)) |cmd| {
            game.step(cmd);
        } else {
            game.message = "Invalid command. Use w/a/s/d, . or q.";
        }
    }

    try out.writeAll("\x1b[2J\x1b[H");
    try game.render(out);
    try out.print("\nFinal score: {d} gold, level {d}.\n", .{ game.gold, game.level });
    try out.flush();
}
