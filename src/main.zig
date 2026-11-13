const std = @import("std");
const Io = std.Io;
const dungeon = @import("dungeon");
const sound = dungeon.sound;
const term = @import("term.zig");

/// All synthesized sound effects. Global because it is large and because
/// sounds play asynchronously straight from these buffers.
var bank: sound.Bank = undefined;
var muted = false;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--mute")) muted = true;
    }
    if (!muted) bank.init();

    // Read each key as it is pressed, without Enter and without echo.
    const raw = term.RawMode.enable();
    defer raw.restore();

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

    // Play on the alternate screen, which has no scrollback, so the frames
    // leave no history in the terminal. Leaving it restores the terminal.
    try out.writeAll(alt_screen_on);
    try out.flush();
    errdefer leaveScreen(out) catch {};

    while (game.state == .playing) {
        try drawFrame(out, &game, .{ .color = true });

        const key = try readKey(in) orelse break; // EOF (Ctrl+Z / end of file)
        // Enter, space and tab do nothing on the map.
        if (std.ascii.isWhitespace(key)) continue;
        // Ctrl+C quits through the normal path, so the terminal is restored.
        if (dungeon.parseCommand(&.{if (key == ctrl_c) 'q' else key})) |cmd| {
            if (cmd == .inventory) {
                // A pause screen: looking uses no turn. A number uses that item
                // (which does use a turn); any other key just closes it.
                try out.writeAll("\x1b[2J\x1b[H");
                try game.renderInventory(out, true);
                try out.flush();
                const choice = try readKey(in) orelse break;
                if (choice == ctrl_c) {
                    game.step(.quit);
                    continue;
                }
                if (dungeon.parseCommand(&.{choice})) |c| {
                    if (c.slot() != null) {
                        game.step(c);
                        try afterTurn(io, out, &game);
                    }
                }
                continue;
            }
            game.step(cmd);
            try afterTurn(io, out, &game);
        } else {
            game.message = "Invalid command. Use w/a/s/d, ., i, 1-9 or q.";
        }
    }

    // Back on the normal screen, print only the last frame and the score, so
    // the result stays visible after the game exits. No clear here: the
    // terminal's earlier text stays where it was.
    try leaveScreen(out);
    try game.render(out, .{ .color = true, .fov = true });
    try out.print("\nFinal score: {d} gold, level {d}.\n", .{ game.inventory.gold, game.level });
    try out.flush();

    // Ending jingle. Wait for it, or it is cut off when the process exits.
    const ending: ?sound.Sfx = switch (game.state) {
        .won => .won,
        .lost => .lost,
        else => null,
    };
    if (ending) |sfx| {
        playSfx(sfx);
        if (!muted) try io.sleep(Io.Duration.fromMilliseconds(900), .awake);
    }
}

/// Enters the alternate screen and hides the cursor (there is no prompt).
const alt_screen_on = "\x1b[?1049h\x1b[?25l";
/// Shows the cursor and goes back to the normal screen.
const alt_screen_off = "\x1b[?25h\x1b[?1049l";
/// Ctrl+C, read as a key because raw mode turns off its signal.
const ctrl_c = 0x03;

fn leaveScreen(out: *Io.Writer) !void {
    try out.writeAll(alt_screen_off);
    try out.flush();
}

/// Reads one key press. Skips '\n', which only comes from redirected input
/// (a file with one command per line); Enter in a raw console is '\r'.
/// Returns null at the end of the input.
fn readKey(in: *Io.Reader) !?u8 {
    while (true) {
        const b = in.takeByte() catch |err| switch (err) {
            error.EndOfStream => return null,
            else => |e| return e,
        };
        if (b != '\n') return b;
    }
}

fn playSfx(sfx: sound.Sfx) void {
    if (!muted) sound.play(bank.get(sfx));
}

/// Clears the screen and draws one frame. The hero's field of view is
/// always on in the game.
fn drawFrame(out: *Io.Writer, game: *const dungeon.Game, opts: dungeon.RenderOptions) !void {
    var frame_opts = opts;
    frame_opts.fov = true;
    try out.writeAll("\x1b[2J\x1b[H"); // clear the screen (ANSI)
    try game.render(out, frame_opts);
    try out.flush();
}

/// Plays the sounds and animations for what happened during the last turn.
fn afterTurn(io: Io, out: *Io.Writer, game: *const dungeon.Game) !void {
    if (game.events.gold) playSfx(.gold);
    if (game.events.chest) playSfx(.chest);
    if (game.events.drink) playSfx(.drink);
    if (game.events.time_stop) playSfx(.time_stop);
    if (game.events.speed) playSfx(.speed);
    if (game.events.strength) playSfx(.strength);
    if (game.events.stairs) playSfx(.stairs);
    // Same order as the turn: the hero's strike, then the monsters' bites.
    if (game.hit_pos != null) {
        playSfx(if (game.hit_killed) .kill else .strike);
        try playStrikeEffect(io, out, game);
    }
    if (game.damage_taken > 0) {
        playSfx(.hurt);
        try playHitEffect(io, out, game);
    }
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
