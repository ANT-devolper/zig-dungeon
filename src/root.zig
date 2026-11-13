//! Dungeon: pure game logic (no I/O), so it is easy to test.
const std = @import("std");

pub const sound = @import("sound.zig");

pub const W = 30;
pub const H = 12;
pub const max_monsters = 8;
pub const last_level = 3;
pub const max_hp = 10;

const hero_damage = 2;
const monster_hp = 3;
const monster_damage = 1;
const gold_value = 10;
/// Chance (in %) that an item spot holds a chest instead of gold.
const chest_chance = 25;
const chest_gold_min = 20;
const chest_gold_max = 50;
const chase_radius = 6;
/// Chance (in %) that a monster that is not chasing takes a random step.
const wander_chance = 30;

pub const Tile = enum { wall, floor, gold, chest, stairs };

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
    /// True if this monster bit the hero during the last turn.
    bit: bool = false,
};

/// How to draw a frame. The defaults produce plain text with no ANSI codes.
pub const RenderOptions = struct {
    /// Use ANSI colors (red hero and yellow attackers after taking damage).
    color: bool = false,
    /// Draw the map with a red background (damage flash).
    flash: bool = false,
    /// Left indent of each map row; 1 is the resting position, 0 and 2
    /// shift the map left/right to shake the screen.
    shake: u2 = 1,
    /// Draw the strike spark where the hero's attack landed this turn:
    /// '*' on a wounded monster, 'X' where a monster was killed.
    spark: bool = false,
    /// Field of view: tiles the hero cannot see are drawn dimmed, as plain
    /// wall or floor, hiding monsters, gold and the stairs.
    fov: bool = false,
};

/// How far the hero can see, in tiles (walls also block the view).
pub const view_radius = 5;

const ansi_reset = "\x1b[0m";
const ansi_red = "\x1b[1;31m";
const ansi_yellow = "\x1b[1;33m";
const ansi_cyan = "\x1b[1;36m";
const ansi_green = "\x1b[1;32m";
const ansi_magenta = "\x1b[1;35m";
const ansi_dim = "\x1b[38;5;248m"; // light gray: out of sight
const ansi_bite = "\x1b[1;37;41m"; // white on red: the monster that just bit
const ansi_red_bg = "\x1b[41m";
const ansi_spark = "\x1b[1;37;45m";

pub const Command = enum {
    up,
    down,
    left,
    right,
    wait,
    quit,
    /// Open the inventory screen. Does not use a turn.
    inventory,

    fn delta(c: Command) Pos {
        return switch (c) {
            .up => .{ .x = 0, .y = -1 },
            .down => .{ .x = 0, .y = 1 },
            .left => .{ .x = -1, .y = 0 },
            .right => .{ .x = 1, .y = 0 },
            .wait, .quit, .inventory => .{ .x = 0, .y = 0 },
        };
    }
};

/// What the hero carries. New item kinds go here as new fields, and
/// `Game.renderInventory` lists them.
pub const Inventory = struct {
    gold: u32 = 0,
};

pub const State = enum { playing, won, lost, quit };

/// Things that happened during the last turn (used for sound effects).
/// Strikes and damage are tracked by `hit_pos`, `hit_killed` and `damage_taken`.
pub const Events = struct {
    gold: bool = false,
    chest: bool = false,
    stairs: bool = false,
    won: bool = false,
    lost: bool = false,
};

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
        'i' => .inventory,
        else => null,
    };
}

/// Hand-drawn level used by tests: '#' wall, '.' floor, '@' start,
/// '>' stairs, 'M' monster and '$' gold. Real levels are generated.
pub const Layout = [H][]const u8;

// Maze generator settings. Maze cells sit on odd coordinates and the even
// tiles between two cells are walls that can be opened. With the even
// 30x12 map this leaves column W-2 and row H-2 as an extra wall line.
const maze_cols = (W - 1) / 2;
const maze_rows = (H - 1) / 2;
/// Extra walls opened after the maze is built, to create loops.
const maze_loops = 8;
const min_stairs_distance = 10;
const monster_safe_distance = 5;
/// Item spots per level; each holds gold or a chest.
const loot_count = 4;

const directions = [_]Pos{
    .{ .x = 0, .y = -1 },
    .{ .x = 0, .y = 1 },
    .{ .x = -1, .y = 0 },
    .{ .x = 1, .y = 0 },
};

/// Map tile at the center of maze cell `c`.
fn cellTile(c: Pos) Pos {
    return .{ .x = 2 * c.x + 1, .y = 2 * c.y + 1 };
}

pub const Game = struct {
    map: [H][W]Tile = undefined,
    hero: Pos = .{ .x = 1, .y = 1 },
    hp: i32 = max_hp,
    inventory: Inventory = .{},
    level: u8 = 1,
    monsters: [max_monsters]Monster = undefined,
    monster_count: usize = 0,
    state: State = .playing,
    message: []const u8 = "",
    /// Damage the hero took during the last turn (drives the hit effects).
    damage_taken: i32 = 0,
    /// Where the hero's attack landed during the last turn, if anywhere.
    hit_pos: ?Pos = null,
    /// Whether that attack killed the monster.
    hit_killed: bool = false,
    /// Gold found in the chest opened during the last turn (0 if none).
    chest_gold: u32 = 0,
    events: Events = .{},
    rng: std.Random,

    /// Starts a new game on level 1, with random monsters and gold.
    pub fn init(rng: std.Random) Game {
        var g: Game = .{ .rng = rng };
        g.loadLevel(1);
        g.message = "Find the stairs (>)! Beware of the monsters (M).";
        return g;
    }

    /// Generates level `n` (1..last_level), keeping HP and gold.
    pub fn loadLevel(g: *Game, n: u8) void {
        g.level = n;
        g.generateLevel();
        g.spawnLoot();
        g.spawnMonsters(@min(max_monsters, 1 + n * 2));
    }

    /// Builds a random maze with a few shortcuts, puts the hero in a maze
    /// cell and the stairs on the floor tile farthest from the hero.
    fn generateLevel(g: *Game) void {
        while (!g.tryGenerateLevel()) {}
    }

    /// One generation attempt. Returns false when the result is not good
    /// enough (stairs too close, no room for monsters...) and must be redone.
    fn tryGenerateLevel(g: *Game) bool {
        g.monster_count = 0;
        for (&g.map) |*row| @memset(row, .wall);
        g.carveMaze();
        g.carveShortcuts();

        g.hero = cellTile(.{
            .x = g.rng.intRangeLessThan(i32, 0, maze_cols),
            .y = g.rng.intRangeLessThan(i32, 0, maze_rows),
        });

        const dist = g.distanceMap(g.hero);
        var stairs = g.hero;
        var stairs_dist: u16 = 0;
        var spawnable: usize = 0; // floor tiles where a monster may spawn
        for (0..H) |y| for (0..W) |x| {
            const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
            if (dist[y][x]) |d| {
                if (d > stairs_dist) {
                    stairs_dist = d;
                    stairs = p;
                }
                if (p.manhattan(g.hero) >= monster_safe_distance) spawnable += 1;
            } else if (g.map[y][x] != .wall) {
                return false; // unreachable floor: never expected, but be safe
            }
        };
        if (stairs_dist < min_stairs_distance) return false;
        if (spawnable < 2 * max_monsters) return false;

        g.setTile(stairs, .stairs);
        return true;
    }

    /// Carves a perfect maze (exactly one path between any two cells) with
    /// a depth-first "recursive backtracker" that uses a fixed-size stack.
    fn carveMaze(g: *Game) void {
        var visited: [maze_rows][maze_cols]bool = @splat(@splat(false));
        var stack: [maze_rows * maze_cols]Pos = undefined;
        const start: Pos = .{
            .x = g.rng.intRangeLessThan(i32, 0, maze_cols),
            .y = g.rng.intRangeLessThan(i32, 0, maze_rows),
        };
        visited[@intCast(start.y)][@intCast(start.x)] = true;
        g.setTile(cellTile(start), .floor);
        stack[0] = start;
        var len: usize = 1;

        while (len > 0) {
            const cur = stack[len - 1];
            var options: [directions.len]Pos = undefined;
            var n: usize = 0;
            for (directions) |d| {
                const next = cur.add(d);
                if (next.x < 0 or next.y < 0 or next.x >= maze_cols or next.y >= maze_rows) continue;
                if (visited[@intCast(next.y)][@intCast(next.x)]) continue;
                options[n] = next;
                n += 1;
            }
            if (n == 0) {
                len -= 1; // dead end: backtrack
                continue;
            }
            const next = options[g.rng.uintLessThan(usize, n)];
            visited[@intCast(next.y)][@intCast(next.x)] = true;
            const a = cellTile(cur);
            const b = cellTile(next);
            g.setTile(.{ .x = @divExact(a.x + b.x, 2), .y = @divExact(a.y + b.y, 2) }, .floor); // the wall between
            g.setTile(b, .floor);
            stack[len] = next;
            len += 1;
        }
    }

    /// Opens `maze_loops` extra walls between two cells, creating loops so
    /// the hero can walk around monsters. Only adds paths, so the maze stays
    /// connected, and never opens (even, even) tiles, so corridors stay
    /// one tile wide.
    fn carveShortcuts(g: *Game) void {
        var opened: usize = 0;
        var attempts: usize = 0;
        while (opened < maze_loops and attempts < 1000) : (attempts += 1) {
            const p: Pos = .{
                .x = g.rng.intRangeAtMost(i32, 1, 2 * maze_cols - 1),
                .y = g.rng.intRangeAtMost(i32, 1, 2 * maze_rows - 1),
            };
            const between_cells = @mod(p.x + p.y, 2) == 1; // exactly one coordinate is even
            if (!between_cells or g.tileAt(p) != .wall) continue;
            g.setTile(p, .floor);
            opened += 1;
        }
    }

    /// Picks what an item spot holds: a chest (`chest_chance`%) or gold.
    fn randomLoot(g: *Game) Tile {
        return if (g.rng.uintLessThan(u8, 100) < chest_chance) .chest else .gold;
    }

    /// Puts the loot (gold or chests) in dead ends first, rewarding
    /// exploration, then on random free floor if there are not enough.
    fn spawnLoot(g: *Game) void {
        var dead_ends: [W * H]Pos = undefined;
        var n: usize = 0;
        for (0..H) |y| for (0..W) |x| {
            const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
            if (g.isDeadEnd(p) and !p.eql(g.hero)) {
                dead_ends[n] = p;
                n += 1;
            }
        };
        var placed: usize = 0;
        while (placed < loot_count and n > 0) : (placed += 1) {
            const i = g.rng.uintLessThan(usize, n);
            g.setTile(dead_ends[i], g.randomLoot());
            dead_ends[i] = dead_ends[n - 1];
            n -= 1;
        }
        for (placed..loot_count) |_| {
            g.setTile(g.randomFreeFloor(), g.randomLoot());
        }
    }

    /// A floor tile with exactly one open neighbor.
    fn isDeadEnd(g: *const Game, p: Pos) bool {
        if (g.tileAt(p) != .floor) return false;
        var open: usize = 0;
        for (directions) |d| {
            if (g.tileAt(p.add(d)) != .wall) open += 1;
        }
        return open == 1;
    }

    fn setTile(g: *Game, p: Pos, t: Tile) void {
        g.map[@intCast(p.y)][@intCast(p.x)] = t;
    }

    /// Steps needed to walk from `from` to every tile (null = unreachable).
    /// Walls block the way; monsters and items do not.
    pub fn distanceMap(g: *const Game, from: Pos) [H][W]?u16 {
        var dist: [H][W]?u16 = @splat(@splat(null));
        var queue: [W * H]Pos = undefined;
        var head: usize = 0;
        var tail: usize = 0;
        dist[@intCast(from.y)][@intCast(from.x)] = 0;
        queue[tail] = from;
        tail += 1;
        while (head < tail) : (head += 1) {
            const p = queue[head];
            const d = dist[@intCast(p.y)][@intCast(p.x)].?;
            for (directions) |dir| {
                const next = p.add(dir);
                if (g.tileAt(next) == .wall) continue;
                const slot = &dist[@intCast(next.y)][@intCast(next.x)];
                if (slot.* != null) continue;
                slot.* = d + 1;
                queue[tail] = next;
                tail += 1;
            }
        }
        return dist;
    }

    /// True if every non-wall tile can be reached from the hero.
    pub fn isFullyConnected(g: *const Game) bool {
        const dist = g.distanceMap(g.hero);
        for (0..H) |y| for (0..W) |x| {
            if (g.map[y][x] != .wall and dist[y][x] == null) return false;
        };
        return true;
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
                    '&' => .chest,
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
        // Looking at the inventory is free: no turn passes, nothing changes.
        if (cmd == .inventory) return;

        g.damage_taken = 0;
        g.hit_pos = null;
        g.hit_killed = false;
        g.events = .{};
        g.chest_gold = 0;
        for (g.monsters[0..g.monster_count]) |*m| m.bit = false;

        switch (cmd) {
            .quit => {
                g.state = .quit;
                g.message = "You fled the dungeon.";
                return;
            },
            .wait => g.message = "You wait...",
            .inventory => unreachable, // handled above
            .up, .down, .left, .right => {
                const target = g.hero.add(cmd.delta());
                if (g.monsterAt(target)) |i| {
                    g.monsters[i].hp -= hero_damage;
                    g.hit_pos = target;
                    if (g.monsters[i].hp <= 0) {
                        g.removeMonster(i);
                        g.hit_killed = true;
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
                        g.inventory.gold += gold_value;
                        g.events.gold = true;
                        g.map[@intCast(target.y)][@intCast(target.x)] = .floor;
                        g.message = "You picked up gold!";
                    },
                    .chest => {
                        g.hero = target;
                        g.chest_gold = g.rng.intRangeAtMost(u32, chest_gold_min, chest_gold_max);
                        g.inventory.gold += g.chest_gold;
                        g.events.chest = true;
                        g.setTile(target, .floor);
                        // render() appends the amount: "(+N gold)".
                        g.message = "You open the chest!";
                    },
                    .stairs => {
                        if (g.level == last_level) {
                            g.hero = target;
                            g.state = .won;
                            g.events.won = true;
                            g.message = "You escaped the dungeon! VICTORY!";
                        } else {
                            g.loadLevel(g.level + 1);
                            g.events.stairs = true;
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
                g.damage_taken += monster_damage;
                m.bit = true;
                g.message = "A monster bites you!";
                if (g.hp <= 0) {
                    g.hp = 0;
                    g.state = .lost;
                    g.events.lost = true;
                    g.message = "You died. GAME OVER.";
                    return;
                }
            } else if (dist <= chase_radius) {
                g.moveMonsterToward(m, g.hero);
            } else if (g.rng.uintLessThan(u8, 100) < wander_chance) {
                g.wander(m);
            }
        }
    }

    /// Takes one step in a random free direction (or stays put if boxed in).
    fn wander(g: *Game, m: *Monster) void {
        var options: [directions.len]Pos = undefined;
        var n: usize = 0;
        for (directions) |d| {
            const next = m.pos.add(d);
            if (g.isFreeForMonster(next)) {
                options[n] = next;
                n += 1;
            }
        }
        if (n > 0) m.pos = options[g.rng.uintLessThan(usize, n)];
    }

    /// A tile a monster may step on: no wall, no other monster, not the hero.
    fn isFreeForMonster(g: *const Game, p: Pos) bool {
        return g.tileAt(p) != .wall and g.monsterAt(p) == null and !p.eql(g.hero);
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
            if (g.isFreeForMonster(next)) {
                m.pos = next;
                return;
            }
        }
    }

    /// Which tiles the hero can see: within `view_radius` (a rounded circle)
    /// and with no wall in between. Walls that block the view are visible.
    pub fn visibility(g: *const Game) [H][W]bool {
        var vis: [H][W]bool = @splat(@splat(false));
        const r = view_radius;
        var dy: i32 = -r;
        while (dy <= r) : (dy += 1) {
            var dx: i32 = -r;
            while (dx <= r) : (dx += 1) {
                if (dx * dx + dy * dy > r * r + r) continue;
                const p = g.hero.add(.{ .x = dx, .y = dy });
                if (p.x < 0 or p.y < 0 or p.x >= W or p.y >= H) continue;
                // Checking both directions smooths out Bresenham's
                // asymmetric corners.
                if (g.lineIsClear(g.hero, p) or g.lineIsClear(p, g.hero)) {
                    vis[@intCast(p.y)][@intCast(p.x)] = true;
                }
            }
        }
        return vis;
    }

    /// True if the Bresenham line from `a` to `b` crosses no wall between
    /// its two ends (the ends themselves may be walls).
    fn lineIsClear(g: *const Game, a: Pos, b: Pos) bool {
        const dx: i32 = @intCast(@abs(b.x - a.x));
        const dy: i32 = -@as(i32, @intCast(@abs(b.y - a.y)));
        const sx: i32 = if (a.x < b.x) 1 else -1;
        const sy: i32 = if (a.y < b.y) 1 else -1;
        var err = dx + dy;
        var p = a;
        while (!p.eql(b)) {
            if (!p.eql(a) and g.tileAt(p) == .wall) return false;
            const e2 = 2 * err;
            if (e2 >= dy) {
                err += dy;
                p.x += sx;
            }
            if (e2 <= dx) {
                err += dx;
                p.y += sy;
            }
        }
        return true;
    }

    /// Draws the game state to any Writer.
    pub fn render(g: *const Game, w: *std.Io.Writer, opts: RenderOptions) std.Io.Writer.Error!void {
        const hurt = g.damage_taken > 0;
        const seen: ?[H][W]bool = if (opts.fov) g.visibility() else null;
        try g.writeHeader(w);
        for (0..H) |y| {
            try w.splatByteAll(' ', opts.shake);
            if (opts.flash) try w.writeAll(ansi_red_bg);
            for (0..W) |x| {
                const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
                // Color to wrap this cell with, if any.
                var color: ?[]const u8 = null;
                const visible = if (seen) |s| s[y][x] else true;
                const sparkling = opts.spark and g.hit_pos != null and g.hit_pos.?.eql(p);
                const c: u8 = if (!visible) blk: {
                    // Out of sight: only the maze's shape, dimmed.
                    color = ansi_dim;
                    break :blk if (g.map[y][x] == .wall) '#' else '.';
                } else if (sparkling) blk: {
                    color = ansi_spark;
                    break :blk if (g.hit_killed) 'X' else '*';
                } else if (p.eql(g.hero)) blk: {
                    // The hero always stands out: cyan, or red when just hurt.
                    color = if (hurt) ansi_red else ansi_cyan;
                    break :blk '@';
                } else if (g.monsterAt(p)) |i| blk: {
                    color = if (g.monsters[i].bit) ansi_bite else ansi_red;
                    break :blk 'M';
                } else switch (g.map[y][x]) {
                    .wall => '#',
                    .floor => '.',
                    .gold => blk: {
                        color = ansi_green;
                        break :blk '$';
                    },
                    .chest => blk: {
                        color = ansi_magenta;
                        break :blk '&';
                    },
                    .stairs => blk: {
                        color = ansi_yellow; // the goal stands out
                        break :blk '>';
                    },
                };
                if (opts.color and !opts.flash and color != null) {
                    try w.print("{s}{c}{s}", .{ color.?, c, ansi_reset });
                } else {
                    try w.writeByte(c);
                }
            }
            if (opts.flash) try w.writeAll(ansi_reset);
            try w.writeByte('\n');
        }
        try w.print("\n{s}", .{g.message});
        if (g.events.chest) {
            if (opts.color) {
                try w.print(" {s}(+{d} gold){s}", .{ ansi_green, g.chest_gold, ansi_reset });
            } else {
                try w.print(" (+{d} gold)", .{g.chest_gold});
            }
        }
        if (hurt) {
            if (opts.color) {
                try w.print(" {s}(-{d} HP){s}", .{ ansi_red, g.damage_taken, ansi_reset });
            } else {
                try w.print(" (-{d} HP)", .{g.damage_taken});
            }
        }
        try w.writeByte('\n');
        if (g.state == .playing) {
            try w.writeAll("[w/a/s/d] move  [.] wait  [i] inventory  [q] quit  + Enter\n> ");
        }
    }

    /// Status line shared by the map and the inventory screen.
    fn writeHeader(g: *const Game, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("DUNGEON  Level {d}/{d}   HP {d}/{d}   Gold {d}\n\n", .{
            g.level, last_level, g.hp, max_hp, g.inventory.gold,
        });
    }

    /// Draws the inventory screen to any Writer.
    pub fn renderInventory(g: *const Game, w: *std.Io.Writer, color: bool) std.Io.Writer.Error!void {
        try g.writeHeader(w);
        try w.writeAll("========== INVENTORY ==========\n\n");
        if (color) {
            try w.print("  Gold ................... {s}{d}{s}\n\n", .{ ansi_green, g.inventory.gold, ansi_reset });
        } else {
            try w.print("  Gold ................... {d}\n\n", .{g.inventory.gold});
        }
        try w.writeAll("  (no other items yet)\n\n");
        try w.writeAll("===============================\n");
        try w.writeAll("[Enter] close\n> ");
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
    try testing.expectEqual(Command.inventory, parseCommand("i").?);
    try testing.expectEqual(Command.inventory, parseCommand("I\r").?);
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
    try testing.expectEqual(@as(u32, gold_value), g.inventory.gold);
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

// Hero in the top-left corner; a monster shut in a 3x3 pocket far away
// (more than chase_radius tiles), so it can only wander.
const pocket_layout: Layout = .{
    "##############################",
    "#@...........................#",
    "#............................#",
    "#............................#",
    "#............................#",
    "#...................#####....#",
    "#...................#...#....#",
    "#...................#.M.#....#",
    "#...................#...#....#",
    "#...................#####....#",
    "#............................#",
    "##############################",
};

test "far-away monsters wander now and then" {
    var prng = std.Random.DefaultPrng.init(3);
    var g = testGame(&prng, pocket_layout);
    var moves: usize = 0;
    for (0..200) |_| {
        const before = g.monsters[0].pos;
        g.step(.wait);
        const now = g.monsters[0].pos;
        if (!now.eql(before)) moves += 1;
        // Never walks through the pocket's walls.
        try testing.expect(now.x >= 21 and now.x <= 23 and now.y >= 6 and now.y <= 8);
        try testing.expectEqual(Tile.floor, g.tileAt(now));
    }
    // About 30% of 200 turns; a wide range, but the seed is fixed.
    try testing.expect(moves >= 30 and moves <= 90);
}

test "a boxed-in monster cannot wander" {
    var prng = std.Random.DefaultPrng.init(3);
    var g = testGame(&prng, .{
        "##############################",
        "#@...........................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#.....................###....#",
        "#.....................#M#....#",
        "#.....................###....#",
        "#............................#",
        "#............................#",
        "##############################",
    });
    const start = g.monsters[0].pos;
    for (0..50) |_| g.step(.wait);
    try testing.expectEqual(start, g.monsters[0].pos);
}

test "zero HP ends the game in defeat" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.hp = 1;
    g.step(.wait);
    try testing.expectEqual(State.lost, g.state);
    try testing.expectEqual(@as(i32, 0), g.hp);
    g.step(.up); // nothing happens after the game ends
    try testing.expectEqual(@as(u32, 0), g.inventory.gold);
}

test "stairs lead to the next level keeping HP and gold" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.gold = 30;
    g.hp = 7;
    g.step(.down);
    try testing.expectEqual(@as(u8, 2), g.level);
    try testing.expectEqual(@as(u32, 30), g.inventory.gold);
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

test "opening the inventory does not use a turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.message = "before";
    const monster_before = g.monsters[0].pos;
    g.step(.inventory);
    try testing.expectEqual(@as(i32, max_hp), g.hp); // the adjacent monster did not bite
    try testing.expectEqual(monster_before, g.monsters[0].pos);
    try testing.expectEqualStrings("before", g.message);
    try testing.expectEqual(Events{}, g.events);
    try testing.expectEqual(State.playing, g.state);
    // A real turn does let the monster bite.
    g.step(.wait);
    try testing.expectEqual(@as(i32, max_hp - monster_damage), g.hp);
}

test "inventory screen lists the gold" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.gold = 30;
    var buf: [4096]u8 = undefined;

    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    const plain = w.buffered();
    try testing.expect(std.mem.indexOf(u8, plain, "INVENTORY") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "Gold ................... 30") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "(no other items yet)") != null);
    try testing.expect(std.mem.indexOf(u8, plain, "[Enter] close") != null);
    try testing.expect(std.mem.indexOfScalar(u8, plain, 0x1b) == null);

    var cw: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&cw, true);
    try testing.expect(std.mem.indexOf(u8, cw.buffered(), ansi_green ++ "30" ++ ansi_reset) != null);
}

test "map help mentions the inventory key" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "[i] inventory") != null);
}

test "q quits the game" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.quit);
    try testing.expectEqual(State.quit, g.state);
}

/// Checks every rule a generated level must follow.
fn expectValidLevel(g: *const Game) !void {
    // Solid border, plus the extra wall line left by the even map size.
    for (0..W) |x| {
        try testing.expectEqual(Tile.wall, g.map[0][x]);
        try testing.expectEqual(Tile.wall, g.map[H - 2][x]);
        try testing.expectEqual(Tile.wall, g.map[H - 1][x]);
    }
    for (0..H) |y| {
        try testing.expectEqual(Tile.wall, g.map[y][0]);
        try testing.expectEqual(Tile.wall, g.map[y][W - 2]);
        try testing.expectEqual(Tile.wall, g.map[y][W - 1]);
    }

    try testing.expectEqual(Tile.floor, g.tileAt(g.hero));
    try testing.expect(g.isFullyConnected());

    // Exactly one stairs tile, reachable and far from the start; all loot.
    const dist = g.distanceMap(g.hero);
    var stairs_count: usize = 0;
    var loot: usize = 0;
    for (0..H) |y| for (0..W) |x| switch (g.map[y][x]) {
        .stairs => {
            stairs_count += 1;
            const d = dist[y][x] orelse return error.StairsUnreachable;
            try testing.expect(d >= min_stairs_distance);
        },
        .gold, .chest => loot += 1,
        else => {},
    };
    try testing.expectEqual(@as(usize, 1), stairs_count);
    try testing.expectEqual(@as(usize, loot_count), loot);

    // Corridors are one tile wide: no 2x2 block of open tiles.
    for (0..H - 1) |y| for (0..W - 1) |x| {
        const open = g.map[y][x] != .wall and g.map[y][x + 1] != .wall and
            g.map[y + 1][x] != .wall and g.map[y + 1][x + 1] != .wall;
        try testing.expect(!open);
    };

    for (g.monsters[0..g.monster_count]) |m| {
        try testing.expect(g.tileAt(m.pos) != .wall);
        try testing.expect(m.pos.manhattan(g.hero) >= monster_safe_distance);
    }
}

test "generated mazes are always valid and finishable" {
    var seed: u64 = 0;
    while (seed < 500) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = Game.init(prng.random());
        for (1..last_level + 1) |n| {
            if (n > 1) g.loadLevel(@intCast(n));
            try testing.expectEqual(@as(usize, 1 + n * 2), g.monster_count);
            expectValidLevel(&g) catch |err| {
                std.debug.print("invalid level {d} for seed {d}\n", .{ n, seed });
                return err;
            };
        }
    }
}

test "about a quarter of the item spots are chests" {
    var chests: usize = 0;
    var total: usize = 0;
    var seed: u64 = 0;
    while (seed < 500) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = Game.init(prng.random());
        for (1..last_level + 1) |n| {
            if (n > 1) g.loadLevel(@intCast(n));
            for (g.map) |row| for (row) |t| switch (t) {
                .chest => {
                    chests += 1;
                    total += 1;
                },
                .gold => total += 1,
                else => {},
            };
        }
    }
    const percent = chests * 100 / total;
    try testing.expect(percent >= 15 and percent <= 35);
}

test "opening a chest gives 20 to 50 gold" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, .{
        "##############################",
        "#@&..........................#",
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
    g.inventory.gold = 5;
    g.step(.right);
    try testing.expectEqual(Pos{ .x = 2, .y = 1 }, g.hero);
    try testing.expect(g.chest_gold >= chest_gold_min and g.chest_gold <= chest_gold_max);
    try testing.expectEqual(5 + g.chest_gold, g.inventory.gold);
    try testing.expectEqual(Tile.floor, g.tileAt(g.hero));
    try testing.expectEqual(Events{ .chest = true }, g.events);
    try testing.expectEqualStrings("You open the chest!", g.message);

    // The message shows the amount.
    var buf: [4096]u8 = undefined;
    var expected: [32]u8 = undefined;
    const suffix = try std.fmt.bufPrint(&expected, "(+{d} gold)", .{g.chest_gold});
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), suffix) != null);

    // Next turn, the chest state is cleared.
    g.step(.wait);
    try testing.expectEqual(@as(u32, 0), g.chest_gold);
    try testing.expectEqual(Events{}, g.events);
}

test "chests are drawn in magenta and hidden out of sight" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, .{
        "##############################",
        "#@.&.....................&...#",
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
    var buf: [16384]u8 = undefined;
    const colored = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, colored, ansi_magenta ++ "&" ++ ansi_reset) != null);
    const fov = try renderToBuf(&g, &buf, .{ .fov = true });
    try testing.expectEqual(@as(u8, '&'), cellAt(fov, .{ .x = 3, .y = 1 }, 1)); // near: visible
    try testing.expectEqual(@as(u8, '.'), cellAt(fov, .{ .x = 26, .y = 1 }, 1)); // far: hidden
}

test "gold goes to dead ends when there are enough of them" {
    var seed: u64 = 0;
    var checked: usize = 0;
    while (seed < 500) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g: Game = .{ .rng = prng.random() };
        g.generateLevel();
        var dead_ends: usize = 0;
        for (0..H) |y| for (0..W) |x| {
            const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
            if (g.isDeadEnd(p) and !p.eql(g.hero)) dead_ends += 1;
        };
        if (dead_ends < loot_count) continue;
        checked += 1;
        g.spawnLoot();
        for (0..H) |y| for (0..W) |x| {
            if (g.map[y][x] != .gold and g.map[y][x] != .chest) continue;
            // A loot tile counts as a dead end if it has one open neighbor.
            const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
            var open: usize = 0;
            for (directions) |d| {
                if (g.tileAt(p.add(d)) != .wall) open += 1;
            }
            try testing.expectEqual(@as(usize, 1), open);
        };
    }
    try testing.expect(checked > 400); // almost every maze has enough dead ends
}

test "shortcuts open extra passages beyond a perfect maze" {
    var prng = std.Random.DefaultPrng.init(7);
    var g: Game = .{ .rng = prng.random() };
    for (&g.map) |*row| @memset(row, .wall);
    g.carveMaze();
    // A perfect maze has one floor tile per cell plus one per passage.
    const cells = maze_cols * maze_rows;
    const perfect_floor = cells + (cells - 1);
    var floor: usize = 0;
    for (g.map) |row| for (row) |t| {
        if (t != .wall) floor += 1;
    };
    try testing.expectEqual(@as(usize, perfect_floor), floor);

    g.carveShortcuts();
    floor = 0;
    for (g.map) |row| for (row) |t| {
        if (t != .wall) floor += 1;
    };
    try testing.expectEqual(@as(usize, perfect_floor + maze_loops), floor);
}

test "the same seed generates the same maze" {
    var prng_a = std.Random.DefaultPrng.init(42);
    var prng_b = std.Random.DefaultPrng.init(42);
    const a = Game.init(prng_a.random());
    const b = Game.init(prng_b.random());
    try testing.expectEqualSlices(u8, std.mem.asBytes(&a.map), std.mem.asBytes(&b.map));
    try testing.expectEqual(a.hero, b.hero);
}

test "different seeds generate different mazes" {
    var prng_a = std.Random.DefaultPrng.init(1);
    var prng_b = std.Random.DefaultPrng.init(2);
    const a = Game.init(prng_a.random());
    const b = Game.init(prng_b.random());
    try testing.expect(!std.mem.eql(u8, std.mem.asBytes(&a.map), std.mem.asBytes(&b.map)));
}

test "distanceMap counts steps and stops at walls" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    const dist = g.distanceMap(g.hero);
    try testing.expectEqual(@as(?u16, 0), dist[5][4]); // the hero
    try testing.expectEqual(@as(?u16, 1), dist[5][5]); // monsters do not block
    try testing.expectEqual(@as(?u16, null), dist[5][3]); // wall
    try testing.expectEqual(@as(?u16, 4), dist[5][2]); // up, left, left, down
    try testing.expect(g.isFullyConnected());
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
    try g.render(&w, .{});
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "@") != null);
}

test "a bite records the damage and marks the attacker" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.wait);
    try testing.expectEqual(@as(i32, monster_damage), g.damage_taken);
    try testing.expect(g.monsters[0].bit);
}

test "a turn without damage clears the hit state" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.wait); // bitten
    g.step(.right); // hero hits the monster...
    g.step(.right); // ...and kills it, so nobody bites this turn
    try testing.expectEqual(@as(usize, 0), g.monster_count);
    try testing.expectEqual(@as(i32, 0), g.damage_taken);
}

test "a turn without a bite clears the monster mark" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.wait); // bitten
    g.hero = .{ .x = 20, .y = 9 }; // teleport far away from the monster
    g.step(.wait);
    try testing.expect(!g.monsters[0].bit);
    try testing.expectEqual(@as(i32, 0), g.damage_taken);
}

fn renderToBuf(g: *const Game, buf: []u8, opts: RenderOptions) ![]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    try g.render(&w, opts);
    return w.buffered();
}

test "color render paints the hurt hero red and shows the damage" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.wait);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_red ++ "@") != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_cyan ++ "@") == null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_bite ++ "M") != null);
    try testing.expect(std.mem.indexOf(u8, out, "(-1 HP)") != null);
}

test "color render highlights the stairs in yellow" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_yellow ++ ">" ++ ansi_reset) != null);
    // Without color the stairs are plain text.
    const plain = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOfScalar(u8, plain, 0x1b) == null);
    try testing.expect(std.mem.indexOfScalar(u8, plain, '>') != null);
}

// Open room with the hero at (4,5) and a wall segment at x=10.
const fov_layout: Layout = .{
    "##############################",
    "#............................#",
    "#............................#",
    "#............................#",
    "#............................#",
    "#...@.....#..................#",
    "#..........#.................#",
    "#............................#",
    "#............................#",
    "#............................#",
    "#............................#",
    "##############################",
};

fn isVisible(vis: [H][W]bool, x: usize, y: usize) bool {
    return vis[y][x];
}

test "the hero sees up to view_radius tiles away" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, fov_layout);
    const vis = g.visibility();
    try testing.expect(isVisible(vis, 4, 5)); // the hero
    try testing.expect(isVisible(vis, 4, 0)); // 5 up (the border wall)
    try testing.expect(isVisible(vis, 9, 5)); // 5 to the right
    try testing.expect(!isVisible(vis, 4, 11)); // 6 down
    try testing.expect(!isVisible(vis, 8, 9)); // diagonal 4+4: outside the circle
}

test "walls block the view but are themselves visible" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fov_layout);
    g.hero = .{ .x = 7, .y = 5 };
    const vis = g.visibility();
    try testing.expect(isVisible(vis, 10, 5)); // the wall
    try testing.expect(!isVisible(vis, 11, 5)); // right behind it
    try testing.expect(!isVisible(vis, 12, 5));
    try testing.expect(isVisible(vis, 9, 5)); // in front of it
}

test "the hero and open neighbors are always visible in generated mazes" {
    var seed: u64 = 0;
    while (seed < 100) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        const g = Game.init(prng.random());
        const vis = g.visibility();
        for (0..H) |y| for (0..W) |x| {
            const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
            const d = p.add(.{ .x = -g.hero.x, .y = -g.hero.y });
            if (vis[y][x]) {
                try testing.expect(d.x * d.x + d.y * d.y <= view_radius * view_radius + view_radius);
            }
            if (p.manhattan(g.hero) <= 1) try testing.expect(vis[y][x]);
        };
    }
}

test "fov render hides what is out of sight" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, .{
        "##############################",
        "#@.......................M$>.#",
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
    var buf: [8192]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .fov = true });
    // Far monster, gold and stairs are hidden; the maze shape remains.
    try testing.expectEqual(@as(u8, '.'), cellAt(out, .{ .x = 25, .y = 1 }, 1));
    try testing.expectEqual(@as(u8, '.'), cellAt(out, .{ .x = 26, .y = 1 }, 1));
    try testing.expectEqual(@as(u8, '.'), cellAt(out, .{ .x = 27, .y = 1 }, 1));
    try testing.expectEqual(@as(u8, '#'), cellAt(out, .{ .x = 29, .y = 1 }, 1));
    try testing.expectEqual(@as(u8, '@'), cellAt(out, g.hero, 1));
    // Without fov everything is drawn.
    const all = try renderToBuf(&g, &buf, .{});
    try testing.expectEqual(@as(u8, 'M'), cellAt(all, .{ .x = 25, .y = 1 }, 1));
    try testing.expectEqual(@as(u8, '>'), cellAt(all, .{ .x = 27, .y = 1 }, 1));
    // Once the hero walks close, they show up.
    g.hero = .{ .x = 22, .y = 1 };
    const near = try renderToBuf(&g, &buf, .{ .fov = true });
    try testing.expectEqual(@as(u8, 'M'), cellAt(near, .{ .x = 25, .y = 1 }, 1));
    try testing.expectEqual(@as(u8, '$'), cellAt(near, .{ .x = 26, .y = 1 }, 1));
    try testing.expectEqual(@as(u8, '>'), cellAt(near, .{ .x = 27, .y = 1 }, 1));
}

test "fov color render dims tiles out of sight" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, fov_layout);
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .fov = true, .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_dim ++ "#" ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_dim ++ "." ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_cyan ++ "@" ++ ansi_reset) != null);
}

test "color render draws gold in green" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_green ++ "$" ++ ansi_reset) != null);
}

test "color render draws monsters in red" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_red ++ "M" ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_yellow ++ "M") == null);
}

test "color render highlights the hero in cyan" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_cyan ++ "@" ++ ansi_reset) != null);
}

test "plain render has no ANSI codes" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.wait);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOfScalar(u8, out, 0x1b) == null);
    try testing.expect(std.mem.indexOf(u8, out, "(-1 HP)") != null);
}

test "flash render uses a red background" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .flash = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_red_bg) != null);
}

test "hitting a monster records where the strike landed" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    const monster_pos = g.monsters[0].pos;
    g.step(.right);
    try testing.expectEqual(@as(?Pos, monster_pos), g.hit_pos);
    try testing.expect(!g.hit_killed);
    g.step(.right);
    try testing.expectEqual(@as(?Pos, monster_pos), g.hit_pos);
    try testing.expect(g.hit_killed);
}

test "a turn without an attack clears the strike" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.right);
    g.step(.wait);
    try testing.expectEqual(@as(?Pos, null), g.hit_pos);
    try testing.expect(!g.hit_killed);
}

/// Returns the character drawn at map cell `p` in a plain render.
fn cellAt(out: []const u8, p: Pos, shake: u2) u8 {
    var lines = std.mem.splitScalar(u8, out, '\n');
    _ = lines.next(); // header
    _ = lines.next(); // blank line
    var y: i32 = 0;
    while (lines.next()) |line| : (y += 1) {
        if (y == p.y) return line[@as(usize, shake) + @as(usize, @intCast(p.x))];
    }
    unreachable;
}

test "spark replaces a wounded monster with '*'" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    const monster_pos = g.monsters[0].pos;
    g.step(.right);
    var buf: [4096]u8 = undefined;
    try testing.expectEqual(@as(u8, '*'), cellAt(try renderToBuf(&g, &buf, .{ .spark = true }), monster_pos, 1));
    try testing.expectEqual(@as(u8, 'M'), cellAt(try renderToBuf(&g, &buf, .{}), monster_pos, 1));
}

test "spark marks a killed monster with 'X'" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    const monster_pos = g.monsters[0].pos;
    g.step(.right);
    g.step(.right);
    var buf: [4096]u8 = undefined;
    try testing.expectEqual(@as(u8, 'X'), cellAt(try renderToBuf(&g, &buf, .{ .spark = true }), monster_pos, 1));
    try testing.expectEqual(@as(u8, '.'), cellAt(try renderToBuf(&g, &buf, .{}), monster_pos, 1));
}

test "color spark uses its own highlight" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.right);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .spark = true, .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_spark ++ "*" ++ ansi_reset) != null);
}

test "turn events: gold, stairs, won and lost" {
    var prng = std.Random.DefaultPrng.init(1);

    var g = testGame(&prng, test_layout);
    g.step(.up);
    try testing.expectEqual(Events{ .gold = true }, g.events);

    g = testGame(&prng, test_layout);
    g.step(.down);
    try testing.expectEqual(Events{ .stairs = true }, g.events);

    g = testGame(&prng, test_layout);
    g.level = last_level;
    g.step(.down);
    try testing.expectEqual(Events{ .won = true }, g.events);

    g = testGame(&prng, test_layout);
    g.hp = 1;
    g.step(.wait);
    try testing.expectEqual(Events{ .lost = true }, g.events);
}

test "events are cleared on the next turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.step(.up); // gold
    g.step(.left); // empty floor
    try testing.expectEqual(Events{}, g.events);
}

// Pull in the tests of the other source files.
test {
    _ = sound;
}

test "shake shifts the map rows" {
    var prng = std.Random.DefaultPrng.init(1);
    const g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;
    const row = "##############################\n";
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .shake = 0 }), "\n\n" ++ row) != null);
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .shake = 1 }), "\n\n " ++ row) != null);
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .shake = 2 }), "\n\n  " ++ row) != null);
}
