//! Dungeon: pure game logic (no I/O), so it is easy to test.
const std = @import("std");

pub const W = 30;
pub const H = 12;
pub const max_monsters = 8;
pub const last_level = 3;
pub const max_hp = 10;

const hero_damage = 2;
const monster_hp = 3;
const monster_damage = 1;
const gold_value = 10;
const chase_radius = 6;

pub const Tile = enum { wall, floor, gold, stairs };

pub const Pos = struct {
    x: i32,
    y: i32,

    fn add(a: Pos, b: Pos) Pos {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    fn eql(a: Pos, b: Pos) bool {
        return a.x == b.x and a.y == b.y;
    }

    fn manhattan(a: Pos, b: Pos) u32 {
        return @abs(a.x - b.x) + @abs(a.y - b.y);
    }
};

pub const Monster = struct {
    pos: Pos,
    hp: i32,
};

pub const Command = enum {
    up,
    down,
    left,
    right,
    wait,
    quit,

    fn delta(c: Command) Pos {
        return switch (c) {
            .up => .{ .x = 0, .y = -1 },
            .down => .{ .x = 0, .y = 1 },
            .left => .{ .x = -1, .y = 0 },
            .right => .{ .x = 1, .y = 0 },
            .wait, .quit => .{ .x = 0, .y = 0 },
        };
    }
};

pub const State = enum { playing, won, lost, quit };

/// Turns a typed line into a command. Ignores spaces and the Windows '\r'.
pub fn parseCommand(line: []const u8) ?Command {
    const t = std.mem.trim(u8, line, " \t\r\n");
    if (t.len == 0) return null;
    return switch (std.ascii.toLower(t[0])) {
        'w' => .up,
        's' => .down,
        'a' => .left,
        'd' => .right,
        '.' => .wait,
        'q' => .quit,
        else => null,
    };
}

/// Level layout: '#' wall, '.' floor, '@' start, '>' stairs,
/// 'M' monster and '$' gold (these two are used by tests; in real
/// levels they are placed randomly).
pub const Layout = [H][]const u8;

const levels = [last_level]Layout{
    .{
        "##############################",
        "#@.......#...................#",
        "#........#.......#####.......#",
        "#........#.......#...#.......#",
        "#....................#.......#",
        "#........#.......#...#.......#",
        "######.###.......#.###.......#",
        "#........#...................#",
        "#........#.........#######...#",
        "#........#.........#.........#",
        "#..................#........>#",
        "##############################",
    },
    .{
        "##############################",
        "#>.......#.........#.........#",
        "#........#.........#.........#",
        "#........#....#....#.........#",
        "####.#####....#....####.######",
        "#.............#..............#",
        "#.............#..............#",
        "####.#####....#....####.######",
        "#........#.........#.........#",
        "#........#.........#.........#",
        "#........#.........#........@#",
        "##############################",
    },
    .{
        "##############################",
        "#@...........#...............#",
        "#.#########..#..###########..#",
        "#.#.......#..#..#.........#..#",
        "#.#..###..#.....#..#####..#..#",
        "#.#..#>#..#######..#...#..#..#",
        "#.#..#.#...........#...#..#..#",
        "#.#..#.###########.#.###..#..#",
        "#.#..#.............#......#..#",
        "#.#..###############.######..#",
        "#............................#",
        "##############################",
    },
};

// Compile-time check that every row is exactly W columns wide.
comptime {
    for (levels) |lvl| for (lvl) |row| {
        if (row.len != W) @compileError("level row has the wrong width");
    };
}

pub const Game = struct {
    map: [H][W]Tile = undefined,
    hero: Pos = .{ .x = 1, .y = 1 },
    hp: i32 = max_hp,
    gold: u32 = 0,
    level: u8 = 1,
    monsters: [max_monsters]Monster = undefined,
    monster_count: usize = 0,
    state: State = .playing,
    message: []const u8 = "",
    rng: std.Random,

    /// Starts a new game on level 1, with random monsters and gold.
    pub fn init(rng: std.Random) Game {
        var g: Game = .{ .rng = rng };
        g.loadLevel(1);
        g.message = "Find the stairs (>)! Beware of the monsters (M).";
        return g;
    }

    /// Loads level `n` (1..last_level), keeping HP and gold.
    pub fn loadLevel(g: *Game, n: u8) void {
        g.level = n;
        g.loadLayout(levels[n - 1]);
        g.spawnRandom(.gold, 4);
        g.spawnMonsters(@min(max_monsters, 1 + n * 2));
    }

    /// Loads a layout exactly as written (no randomness).
    pub fn loadLayout(g: *Game, layout: Layout) void {
        g.monster_count = 0;
        for (layout, 0..) |row, y| {
            for (row, 0..) |c, x| {
                const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
                g.map[y][x] = switch (c) {
                    '#' => .wall,
                    '>' => .stairs,
                    '$' => .gold,
                    else => .floor,
                };
                switch (c) {
                    '@' => g.hero = p,
                    'M' => g.addMonster(p),
                    else => {},
                }
            }
        }
    }

    fn addMonster(g: *Game, p: Pos) void {
        if (g.monster_count == max_monsters) return;
        g.monsters[g.monster_count] = .{ .pos = p, .hp = monster_hp };
        g.monster_count += 1;
    }

    fn removeMonster(g: *Game, i: usize) void {
        g.monster_count -= 1;
        g.monsters[i] = g.monsters[g.monster_count];
    }

    fn randomFreeFloor(g: *Game) Pos {
        while (true) {
            const p: Pos = .{
                .x = g.rng.intRangeLessThan(i32, 1, W - 1),
                .y = g.rng.intRangeLessThan(i32, 1, H - 1),
            };
            if (g.tileAt(p) == .floor and !p.eql(g.hero) and g.monsterAt(p) == null) return p;
        }
    }

    fn spawnRandom(g: *Game, tile: Tile, count: usize) void {
        for (0..count) |_| {
            const p = g.randomFreeFloor();
            g.map[@intCast(p.y)][@intCast(p.x)] = tile;
        }
    }

    fn spawnMonsters(g: *Game, count: usize) void {
        for (0..count) |_| {
            // Never spawn right next to the hero, to give them a chance at the start.
            var p = g.randomFreeFloor();
            while (p.manhattan(g.hero) < 5) p = g.randomFreeFloor();
            g.addMonster(p);
        }
    }

    pub fn tileAt(g: *const Game, p: Pos) Tile {
        if (p.x < 0 or p.y < 0 or p.x >= W or p.y >= H) return .wall;
        return g.map[@intCast(p.y)][@intCast(p.x)];
    }

    pub fn monsterAt(g: *const Game, p: Pos) ?usize {
        for (g.monsters[0..g.monster_count], 0..) |m, i| {
            if (m.pos.eql(p)) return i;
        }
        return null;
    }

    /// Runs one turn: the hero's action, then the monsters'.
    pub fn step(g: *Game, cmd: Command) void {
        if (g.state != .playing) return;

        switch (cmd) {
            .quit => {
                g.state = .quit;
                g.message = "You fled the dungeon.";
                return;
            },
            .wait => g.message = "You wait...",
            .up, .down, .left, .right => {
                const target = g.hero.add(cmd.delta());
                if (g.monsterAt(target)) |i| {
                    g.monsters[i].hp -= hero_damage;
                    if (g.monsters[i].hp <= 0) {
                        g.removeMonster(i);
                        g.message = "You defeated a monster!";
                    } else {
                        g.message = "You hit the monster.";
                    }
                } else switch (g.tileAt(target)) {
                    .wall => g.message = "A wall blocks the way.",
                    .floor => {
                        g.hero = target;
                        g.message = "";
                    },
                    .gold => {
                        g.hero = target;
                        g.gold += gold_value;
                        g.map[@intCast(target.y)][@intCast(target.x)] = .floor;
                        g.message = "You picked up gold!";
                    },
                    .stairs => {
                        if (g.level == last_level) {
                            g.hero = target;
                            g.state = .won;
                            g.message = "You escaped the dungeon! VICTORY!";
                        } else {
                            g.loadLevel(g.level + 1);
                            g.message = "You go down the stairs...";
                        }
                        return; // new level: monsters do not act this turn
                    },
                }
            },
        }

        g.monstersTurn();
    }

    fn monstersTurn(g: *Game) void {
        for (g.monsters[0..g.monster_count]) |*m| {
            const dist = m.pos.manhattan(g.hero);
            if (dist == 1) {
                g.hp -= monster_damage;
                g.message = "A monster bites you!";
                if (g.hp <= 0) {
                    g.hp = 0;
                    g.state = .lost;
                    g.message = "You died. GAME OVER.";
                    return;
                }
            } else if (dist <= chase_radius) {
                g.moveMonsterToward(m, g.hero);
            }
        }
    }

    fn moveMonsterToward(g: *Game, m: *Monster, goal: Pos) void {
        const dx = std.math.sign(goal.x - m.pos.x);
        const dy = std.math.sign(goal.y - m.pos.y);
        // Try the axis with the larger distance first, then the other one.
        const prefer_x = @abs(goal.x - m.pos.x) >= @abs(goal.y - m.pos.y);
        const options = if (prefer_x)
            [2]Pos{ .{ .x = dx, .y = 0 }, .{ .x = 0, .y = dy } }
        else
            [2]Pos{ .{ .x = 0, .y = dy }, .{ .x = dx, .y = 0 } };

        for (options) |d| {
            if (d.x == 0 and d.y == 0) continue;
            const next = m.pos.add(d);
            if (g.tileAt(next) != .wall and g.monsterAt(next) == null and !next.eql(g.hero)) {
                m.pos = next;
                return;
            }
        }
    }

    /// Draws the game state to any Writer.
    pub fn render(g: *const Game, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("DUNGEON  Level {d}/{d}   HP {d}/{d}   Gold {d}\n\n", .{
            g.level, last_level, g.hp, max_hp, g.gold,
        });
        for (0..H) |y| {
            for (0..W) |x| {
                const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
                const c: u8 = if (p.eql(g.hero))
                    '@'
                else if (g.monsterAt(p) != null)
                    'M'
                else switch (g.map[y][x]) {
                    .wall => '#',
                    .floor => '.',
                    .gold => '$',
                    .stairs => '>',
                };
                try w.writeByte(c);
            }
            try w.writeByte('\n');
        }
        try w.print("\n{s}\n", .{g.message});
        if (g.state == .playing) {
            try w.writeAll("[w/a/s/d] move  [.] wait  [q] quit  + Enter\n> ");
        }
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

fn testGame(prng: *std.Random.DefaultPrng, layout: Layout) Game {
    var g: Game = .{ .rng = prng.random() };
    g.loadLayout(layout);
    return g;
}

// Small test layout: hero in the middle, wall to the left,
// gold above, monster to the right and stairs below.
const test_layout: Layout = .{
    "##############################",
    "#............................#",
    "#............................#",
    "#............................#",
    "#...$........................#",
    "#..#@M.......................#",
    "#...>........................#",
    "#............................#",
    "#............................#",
    "#............................#",
    "#............................#",
    "##############################",
};

test "parseCommand handles keys, uppercase and \\r" {
    try testing.expectEqual(Command.up, parseCommand("w").?);
    try testing.expectEqual(Command.left, parseCommand("A\r").?);
    try testing.expectEqual(Command.down, parseCommand("  s  ").?);
    try testing.expectEqual(Command.right, parseCommand("d").?);
    try testing.expectEqual(Command.wait, parseCommand(".").?);
    try testing.expectEqual(Command.quit, parseCommand("q").?);
    try testing.expectEqual(@as(?Command, null), parseCommand(""));
    try testing.expectEqual(@as(?Command, null), parseCommand("x"));
}

test "wall blocks the hero" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    const before = g.hero;
    g.step(.left);
    try testing.expectEqual(before, g.hero);
}

test "picking up gold adds score and clears the tile" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.up);
    try testing.expectEqual(@as(u32, gold_value), g.gold);
    try testing.expectEqual(Tile.floor, g.tileAt(g.hero));
}

test "attacking wounds and then kills the monster" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.right);
    try testing.expectEqual(@as(usize, 1), g.monster_count);
    try testing.expectEqual(@as(i32, monster_hp - hero_damage), g.monsters[0].hp);
    g.step(.right);
    try testing.expectEqual(@as(usize, 0), g.monster_count);
}

test "adjacent monster bites the hero" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.wait);
    try testing.expectEqual(@as(i32, max_hp - monster_damage), g.hp);
}

test "nearby monster chases the hero" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, .{
        "##############################",
        "#@...M.......................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "##############################",
    });
    g.step(.wait);
    try testing.expectEqual(Pos{ .x = 4, .y = 1 }, g.monsters[0].pos);
}

test "zero HP ends the game in defeat" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.hp = 1;
    g.step(.wait);
    try testing.expectEqual(State.lost, g.state);
    try testing.expectEqual(@as(i32, 0), g.hp);
    g.step(.up); // nothing happens after the game ends
    try testing.expectEqual(@as(u32, 0), g.gold);
}

test "stairs lead to the next level keeping HP and gold" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.gold = 30;
    g.hp = 7;
    g.step(.down);
    try testing.expectEqual(@as(u8, 2), g.level);
    try testing.expectEqual(@as(u32, 30), g.gold);
    try testing.expectEqual(@as(i32, 7), g.hp);
    try testing.expectEqual(State.playing, g.state);
}

test "stairs on the last level win the game" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.level = last_level;
    g.step(.down);
    try testing.expectEqual(State.won, g.state);
}

test "q quits the game" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.quit);
    try testing.expectEqual(State.quit, g.state);
}

test "every level has a path from the start to the stairs" {
    for (levels) |lvl| {
        var prng = std.Random.DefaultPrng.init(1);
        var g = testGame(&prng, lvl);
        // Breadth-first search (BFS) over the map.
        var seen: [H][W]bool = @splat(@splat(false));
        var queue: [W * H]Pos = undefined;
        var head: usize = 0;
        var tail: usize = 0;
        queue[tail] = g.hero;
        tail += 1;
        seen[@intCast(g.hero.y)][@intCast(g.hero.x)] = true;
        var found = false;
        while (head < tail) : (head += 1) {
            const p = queue[head];
            if (g.tileAt(p) == .stairs) found = true;
            for ([_]Command{ .up, .down, .left, .right }) |c| {
                const n = p.add(c.delta());
                if (g.tileAt(n) == .wall or seen[@intCast(n.y)][@intCast(n.x)]) continue;
                seen[@intCast(n.y)][@intCast(n.x)] = true;
                queue[tail] = n;
                tail += 1;
            }
        }
        try testing.expect(found);
    }
}

test "new game spawns monsters away from the hero and renders" {
    var prng = std.Random.DefaultPrng.init(12345);
    const g = Game.init(prng.random());
    try testing.expectEqual(@as(usize, 3), g.monster_count);
    for (g.monsters[0..g.monster_count]) |m| {
        try testing.expect(m.pos.manhattan(g.hero) >= 5);
        try testing.expect(g.tileAt(m.pos) != .wall);
    }
    var buf: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try g.render(&w);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "@") != null);
}
