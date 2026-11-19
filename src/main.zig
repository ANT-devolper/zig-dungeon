const std = @import("std");
const Io = std.Io;
const brewdungeon = @import("brewdungeon");
const sound = brewdungeon.sound;
const term = @import("term.zig");

/// All synthesized sound effects. Global because it is large and because
/// sounds play asynchronously straight from these buffers.
var bank: sound.Bank = undefined;
var muted = false;
/// Set when the game closes from the panic screen: nothing from the game is
/// printed on exit, so the disguise holds.
var closed_hidden = false;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var no_title = false;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--mute")) muted = true;
        if (std.mem.eql(u8, arg, "--no-title")) no_title = true;
    }
    if (!muted) bank.init();

    // Read each key as it is pressed, without Enter and without echo.
    const raw = term.RawMode.enable();
    defer raw.restore();

    // Random seed from the operating system.
    var seed_bytes: [8]u8 = undefined;
    io.random(&seed_bytes);
    var prng = std.Random.DefaultPrng.init(std.mem.readInt(u64, &seed_bytes, .little));

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

    // The last run played, printed after leaving the alternate screen.
    var last: ?brewdungeon.Game = null;
    if (no_title) {
        // --no-title: straight into one run.
        var game = brewdungeon.Game.init(prng.random());
        _ = try playRun(io, in, out, &game);
        last = game;
    } else {
        var title: brewdungeon.Title = .{};
        while (true) {
            try drawTitle(out, &title, last);
            const key = try readKey(in) orelse break; // EOF
            if (key == ctrl_c) break;
            if (key == brewdungeon.panic_key) {
                if (try panicScreen(in, out)) break;
                continue;
            }
            const choice = title.key(key) orelse continue;
            if (choice == .quit) break;

            var game = brewdungeon.Game.init(prng.random());
            const exit = try playRun(io, in, out, &game);
            last = game;
            if (exit) break;

            // The run is over: its last frame stays until a key, then the
            // title comes back. The panic key hides it and waits again.
            if (game.state == .lost) playSfx(.lost);
            const any = while (true) {
                try drawFrame(out, &game, .{ .color = true });
                try out.writeAll("\nPress any key to return to the title.\n");
                try out.flush();
                const k = try readKey(in) orelse break ctrl_c;
                if (k != brewdungeon.panic_key) break k;
                if (try panicScreen(in, out)) break ctrl_c;
            };
            if (any == ctrl_c) break;
            title = .{};
        }
    }

    // Back on the normal screen, print only the last frame and the score, so
    // the result stays visible after the game exits. No clear here: the
    // terminal's earlier text stays where it was.
    try leaveScreen(out);
    if (closed_hidden) return; // closed from the panic screen: show nothing
    const game = last orelse return; // quit from the title without playing
    try game.render(out, .{ .color = true, .fov = true });
    try out.print("\nFinal score: reached level {d} with {d} gold.\n", .{ game.level, game.inventory.gold });
    switch (game.rival.status) {
        .none => {},
        .dead => try out.print("Your rival died on level {d}.\n", .{game.rival.level}),
        .here, .away => try out.print("Your rival reached level {d}.\n", .{game.rival.level}),
    }
    try out.flush();

    // With --no-title the defeat jingle plays here. Wait for it, or it is
    // cut off when the process exits.
    if (no_title and game.state == .lost) {
        playSfx(.lost);
        if (!muted) try io.sleep(Io.Duration.fromMilliseconds(900), .awake);
    }
}

/// Plays one run until the hero dies or flees. Returns true when the whole
/// game must close: Ctrl+C or the end of the input.
fn playRun(io: Io, in: *Io.Reader, out: *Io.Writer, game: *brewdungeon.Game) !bool {
    while (game.state == .playing) {
        try drawFrame(out, game, .{ .color = true });

        const key = try readKey(in) orelse return true; // EOF (Ctrl+Z / end of file)
        // The panic key hides the game; no turn is used.
        if (key == brewdungeon.panic_key) {
            if (try panicScreen(in, out)) {
                game.step(.quit);
                return true;
            }
            continue;
        }
        // Enter and tab do nothing on the map.
        if (std.ascii.isWhitespace(key)) continue;
        // Ctrl+C closes the game through the normal path, so the terminal
        // is restored.
        if (key == ctrl_c) {
            game.step(.quit);
            return true;
        }
        if (brewdungeon.parseCommand(&.{key})) |cmd| {
            if (cmd == .inventory) {
                // A pause screen: looking uses no turn. A number uses that item
                // (which does use a turn); any other key just closes it.
                // The panic key hides it and comes back to it.
                const choice = while (true) {
                    try out.writeAll("\x1b[2J\x1b[H");
                    try game.renderInventory(out, true);
                    try out.flush();
                    const k = try readKey(in) orelse return true;
                    if (k != brewdungeon.panic_key) break k;
                    if (try panicScreen(in, out)) {
                        game.step(.quit);
                        return true;
                    }
                };
                if (choice == ctrl_c) {
                    game.step(.quit);
                    return true;
                }
                if (brewdungeon.parseCommand(&.{choice})) |c| {
                    if (c.slot() != null) {
                        game.step(c);
                        try afterTurn(io, out, game);
                    }
                }
                continue;
            }
            game.step(cmd);
            try afterTurn(io, out, game);
        } else {
            game.message = "Invalid command. Use w/a/s/d or arrows, ., i, 1-9 or q.";
        }
    }
    return false;
}

/// Clears the screen and draws the title screen.
fn drawTitle(out: *Io.Writer, title: *const brewdungeon.Title, last: ?brewdungeon.Game) !void {
    try out.writeAll("\x1b[2J\x1b[H");
    const run: ?brewdungeon.LastRun = if (last) |g| .{ .level = g.level, .gold = g.inventory.gold } else null;
    try title.render(out, true, run);
    try out.flush();
}

/// The panic button: hides the game behind a fake PowerShell pytest run
/// (`renderDisguise`) with a visible cursor, until the panic key is pressed
/// again; other keys do nothing. Returns true when the game must close
/// (Ctrl+C or the end of the input), and then nothing from the game is
/// printed on exit.
fn panicScreen(in: *Io.Reader, out: *Io.Writer) !bool {
    try out.writeAll("\x1b[2J\x1b[H");
    try brewdungeon.renderDisguise(out);
    try out.writeAll("\x1b[?25h"); // show the cursor, like a real prompt
    try out.flush();
    while (true) {
        const key = try readKey(in) orelse 0x03;
        if (key == ctrl_c) {
            closed_hidden = true;
            return true;
        }
        if (key == brewdungeon.panic_key) {
            try out.writeAll("\x1b[?25l"); // hide it again for the game
            return false;
        }
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

const readKey = brewdungeon.readKey;

fn playSfx(sfx: sound.Sfx) void {
    if (!muted) sound.play(bank.get(sfx));
}

/// Clears the screen and draws one frame. The hero's field of view is
/// always on in the game.
fn drawFrame(out: *Io.Writer, game: *const brewdungeon.Game, opts: brewdungeon.RenderOptions) !void {
    var frame_opts = opts;
    frame_opts.fov = true;
    try out.writeAll("\x1b[2J\x1b[H"); // clear the screen (ANSI)
    try game.render(out, frame_opts);
    try out.flush();
}

/// Plays the sounds and animations for what happened during the last turn.
fn afterTurn(io: Io, out: *Io.Writer, game: *const brewdungeon.Game) !void {
    if (game.events.gold) playSfx(.gold);
    if (game.events.chest or game.events.reward) playSfx(.chest);
    if (game.events.drink) playSfx(.drink);
    if (game.events.time_stop) playSfx(.time_stop);
    if (game.events.speed) playSfx(.speed);
    if (game.events.strength) playSfx(.strength);
    if (game.events.vision) playSfx(.vision);
    if (game.events.invisible) playSfx(.invisible);
    if (game.events.stairs) playSfx(.stairs);
    if (game.events.buy) playSfx(.buy);
    if (game.events.curse or game.events.stolen) playSfx(.curse);
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
fn playStrikeEffect(io: Io, out: *Io.Writer, game: *const brewdungeon.Game) !void {
    const frames = [_]struct { opts: brewdungeon.RenderOptions, ms: i64 }{
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
fn playHitEffect(io: Io, out: *Io.Writer, game: *const brewdungeon.Game) !void {
    const frames = [_]struct { opts: brewdungeon.RenderOptions, ms: i64 }{
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
