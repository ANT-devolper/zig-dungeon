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
/// Chance (in %) that a chest holds a potion instead of gold.
const chest_potion_chance = 85;
/// Chance (in %) that a chest's potion is a time stop potion.
const time_stop_chance = 10;
/// Free turns the monsters stay frozen after drinking time stop.
pub const time_stop_turns = 3;
/// Chance (in %) that a chest's potion is a speed potion.
const speed_chance = 15;
/// Rounds the hero stays fast (2 actions per round) after drinking speed.
pub const speed_turns = 10;
/// Chance (in %) that a chest's potion is a strength potion.
const strength_chance = 15;
/// Rounds the strength bonus lasts after the round it was drunk in.
pub const strength_turns = 3;

/// Potion kinds the hero can carry: three sizes of health potion, three
/// sizes of strength potion, plus the time stop and speed potions, which
/// are single kinds with no sizes.
pub const Potion = enum {
    small,
    medium,
    large,
    time_stop,
    speed,
    strength_small,
    strength_medium,
    strength_large,

    pub const count = 8;

    /// HP restored (only health potions heal).
    pub fn heal(p: Potion) i32 {
        return switch (p) {
            .small => 1,
            .medium => 3,
            .large => 5,
            else => 0,
        };
    }

    /// Extra attack damage (only strength potions give it).
    pub fn strength(p: Potion) i32 {
        return switch (p) {
            .strength_small => 1,
            .strength_medium => 2,
            .strength_large => 3,
            else => 0,
        };
    }

    /// Maps a roll in 0..99 to a health potion size: small 50%,
    /// medium 35%, large 15%. Only ever returns health potions.
    pub fn fromRoll(roll: u8) Potion {
        if (roll < 50) return .small;
        if (roll < 85) return .medium;
        return .large;
    }

    /// Maps a roll in 0..99 to a strength potion size, with the same
    /// split as `fromRoll`: small 50%, medium 35%, large 15%.
    pub fn strengthFromRoll(roll: u8) Potion {
        return switch (fromRoll(roll)) {
            .small => .strength_small,
            .medium => .strength_medium,
            else => .strength_large,
        };
    }

    /// Name used in messages.
    pub fn label(p: Potion) []const u8 {
        return switch (p) {
            .small => "small health potion",
            .medium => "medium health potion",
            .large => "large health potion",
            .time_stop => "time stop potion",
            .speed => "speed potion",
            .strength_small => "small strength potion",
            .strength_medium => "medium strength potion",
            .strength_large => "large strength potion",
        };
    }

    fn index(p: Potion) usize {
        return @backingInt(p);
    }
};
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
const ansi_blue = "\x1b[1;34m"; // frozen monsters (time stop)
const ansi_fast = "\x1b[1;30;46m"; // black on cyan: the hero while fast (speed)
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
    /// Use the item listed with that number in the inventory (keys 1-9).
    /// Uses a turn when it works.
    use_1,
    use_2,
    use_3,
    use_4,
    use_5,
    use_6,
    use_7,
    use_8,
    use_9,

    fn delta(c: Command) Pos {
        return switch (c) {
            .up => .{ .x = 0, .y = -1 },
            .down => .{ .x = 0, .y = 1 },
            .left => .{ .x = -1, .y = 0 },
            .right => .{ .x = 1, .y = 0 },
            else => .{ .x = 0, .y = 0 },
        };
    }

    /// The 0-based inventory slot a use command refers to, if it is one.
    pub fn slot(c: Command) ?usize {
        const i = @backingInt(c);
        const first = @backingInt(Command.use_1);
        if (i < first) return null;
        return i - first;
    }
};

/// What the hero carries. Usable items are listed in the order they were
/// first picked up; when one runs out it leaves the list and the ones
/// below move up, so the numbers shown are always 1, 2, 3... with no gaps.
pub const Inventory = struct {
    gold: u32 = 0,
    /// How many of each potion, indexed by `Potion.index()`.
    potions: [Potion.count]u32 = @splat(0),
    /// Usable item kinds the hero has, in pick-up order (slot 0 is "1").
    slots: [Potion.count]Potion = undefined,
    slot_count: usize = 0,

    pub fn potionCount(inv: Inventory, p: Potion) u32 {
        return inv.potions[p.index()];
    }

    /// The listed items, in order.
    pub fn items(inv: *const Inventory) []const Potion {
        return inv.slots[0..inv.slot_count];
    }

    /// The item shown with number `slot + 1`, if any.
    pub fn itemAt(inv: *const Inventory, slot: usize) ?Potion {
        if (slot >= inv.slot_count) return null;
        return inv.slots[slot];
    }

    /// Adds one potion; a kind the hero did not have goes to the end.
    pub fn add(inv: *Inventory, p: Potion) void {
        if (inv.potions[p.index()] == 0) {
            inv.slots[inv.slot_count] = p;
            inv.slot_count += 1;
        }
        inv.potions[p.index()] += 1;
    }

    /// Removes one potion; when it runs out the items below move up.
    pub fn remove(inv: *Inventory, p: Potion) void {
        std.debug.assert(inv.potions[p.index()] > 0);
        inv.potions[p.index()] -= 1;
        if (inv.potions[p.index()] > 0) return;
        const i = std.mem.indexOfScalar(Potion, inv.items(), p).?;
        std.mem.copyForwards(Potion, inv.slots[i .. inv.slot_count - 1], inv.slots[i + 1 .. inv.slot_count]);
        inv.slot_count -= 1;
    }
};

pub const State = enum { playing, won, lost, quit };

/// Things that happened during the last turn (used for sound effects).
/// Strikes and damage are tracked by `hit_pos`, `hit_killed` and `damage_taken`.
pub const Events = struct {
    gold: bool = false,
    chest: bool = false,
    drink: bool = false,
    time_stop: bool = false,
    speed: bool = false,
    strength: bool = false,
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
        '1'...'9' => |d| @fromBackingInt(@intCast(@backingInt(Command.use_1) + (d - '1'))),
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
    /// Potion found in that chest, if any.
    chest_potion: ?Potion = null,
    /// HP restored by a potion during the last turn (0 if none).
    healed: i32 = 0,
    /// Free turns left with the monsters frozen by a time stop potion.
    time_stop: u8 = 0,
    /// Time stop was drunk during the current round, which does not count.
    time_stop_fresh: bool = false,
    /// Rounds left with the hero fast (speed potion).
    speed: u8 = 0,
    /// Rounds left with the strength bonus (strength potions).
    strength: u8 = 0,
    /// Extra attack damage while `strength > 0`; drinking more adds up.
    strength_bonus: i32 = 0,
    /// Strength was drunk during the current round, which does not count.
    strength_fresh: bool = false,
    /// A fast hero already used the first of the 2 actions of this round.
    half_round: bool = false,
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
        g.chest_potion = null;
        g.healed = 0;
        for (g.monsters[0..g.monster_count]) |*m| m.bit = false;

        switch (cmd) {
            .quit => {
                g.state = .quit;
                g.message = "You fled the dungeon.";
                return;
            },
            .wait => g.message = "You wait...",
            .inventory => unreachable, // handled above
            .use_1, .use_2, .use_3, .use_4, .use_5, .use_6, .use_7, .use_8, .use_9 => {
                // Using nothing, or failing to drink, does not use a turn:
                // return before the monsters act.
                const item = g.inventory.itemAt(cmd.slot().?) orelse {
                    g.message = "You have no item with that number.";
                    return;
                };
                if (!g.drink(item)) return;
            },
            .up, .down, .left, .right => {
                const target = g.hero.add(cmd.delta());
                if (g.monsterAt(target)) |i| {
                    g.monsters[i].hp -= g.attackDamage();
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
                        g.events.chest = true;
                        // A chest holds either a potion or gold, never both.
                        if (g.rng.uintLessThan(u8, 100) < chest_potion_chance) {
                            const roll = g.rng.uintLessThan(u8, 100);
                            const kind: Potion = if (roll < time_stop_chance)
                                .time_stop
                            else if (roll < time_stop_chance + speed_chance)
                                .speed
                            else if (roll < time_stop_chance + speed_chance + strength_chance)
                                Potion.strengthFromRoll(g.rng.uintLessThan(u8, 100))
                            else
                                Potion.fromRoll(g.rng.uintLessThan(u8, 100));
                            g.inventory.add(kind);
                            g.chest_potion = kind;
                        } else {
                            g.chest_gold = g.rng.intRangeAtMost(u32, chest_gold_min, chest_gold_max);
                            g.inventory.gold += g.chest_gold;
                        }
                        g.setTile(target, .floor);
                        // render() appends what was inside: "(+N gold)" or "(small potion)".
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
                        g.half_round = false; // a new level starts a new round
                        return; // new level: monsters do not act this turn
                    },
                }
            },
        }

        // World rounds: a fast hero (speed) gets 2 actions per round; the
        // monsters and every effect counter advance once per round.
        if (g.speed > 0 and !g.half_round) {
            g.half_round = true; // first action of the round: the world waits
            return;
        }
        g.half_round = false;
        g.endRound();
    }

    /// The world's part of a round: effect counters tick and, unless time
    /// is stopped, the monsters act.
    fn endRound(g: *Game) void {
        const frozen = g.time_stop > 0;
        if (g.time_stop_fresh) {
            g.time_stop_fresh = false; // the round it was drunk in is free
        } else if (g.time_stop > 0) {
            g.time_stop -= 1;
        }
        if (g.speed > 0) g.speed -= 1;
        if (g.strength_fresh) {
            g.strength_fresh = false; // the round it was drunk in is free
        } else if (g.strength > 0) {
            g.strength -= 1;
            if (g.strength == 0) g.strength_bonus = 0;
        }
        if (!frozen) g.monstersTurn();
    }

    /// Damage the hero's attack deals, including any strength bonus.
    pub fn attackDamage(g: *const Game) i32 {
        return hero_damage + g.strength_bonus;
    }

    /// True while the monsters are frozen by a time stop potion.
    pub fn timeStopped(g: *const Game) bool {
        return g.time_stop > 0;
    }

    /// True while the hero is fast (speed potion).
    pub fn isFast(g: *const Game) bool {
        return g.speed > 0;
    }

    /// Drinks a potion the hero carries. Returns false (and uses no turn)
    /// when it is a health potion and the hero is already at full health.
    fn drink(g: *Game, kind: Potion) bool {
        if (kind == .time_stop) {
            g.inventory.remove(kind);
            g.time_stop = time_stop_turns; // drinking again resets, never adds
            g.time_stop_fresh = true;
            g.events.time_stop = true;
            g.message = "Time stops! The monsters are frozen.";
            return true;
        }
        if (kind == .speed) {
            g.inventory.remove(kind);
            g.speed = speed_turns; // drinking again resets, never adds
            g.events.speed = true;
            g.message = "You feel fast!";
            return true;
        }
        if (kind.strength() > 0) {
            g.inventory.remove(kind);
            g.strength_bonus += kind.strength(); // bonuses add up
            g.strength = strength_turns; // the counter resets, never adds
            g.strength_fresh = true;
            g.events.strength = true;
            g.message = switch (kind) {
                .strength_small => "You feel stronger! (+1 damage)",
                .strength_medium => "You feel stronger! (+2 damage)",
                else => "You feel stronger! (+3 damage)",
            };
            return true;
        }
        if (g.hp >= max_hp) {
            g.message = "You are already at full health.";
            return false;
        }
        g.inventory.remove(kind);
        const before = g.hp;
        g.hp = @min(max_hp, g.hp + kind.heal());
        g.healed = g.hp - before;
        g.events.drink = true;
        // render() appends the HP restored: "(+N HP)".
        g.message = switch (kind) {
            .small => "You drink a small health potion.",
            .medium => "You drink a medium health potion.",
            .large => "You drink a large health potion.",
            else => unreachable, // handled above
        };
        return true;
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
                    color = if (hurt) ansi_red else if (g.isFast()) ansi_fast else ansi_cyan;
                    break :blk '@';
                } else if (g.monsterAt(p)) |i| blk: {
                    color = if (g.timeStopped())
                        ansi_blue
                    else if (g.monsters[i].bit)
                        ansi_bite
                    else
                        ansi_red;
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
            if (opts.color) try w.writeAll(ansi_green);
            if (g.chest_potion) |p| {
                try w.print(" ({s})", .{p.label()});
            } else {
                try w.print(" (+{d} gold)", .{g.chest_gold});
            }
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.healed > 0) {
            if (opts.color) {
                try w.print(" {s}(+{d} HP){s}", .{ ansi_green, g.healed, ansi_reset });
            } else {
                try w.print(" (+{d} HP)", .{g.healed});
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
        try w.print("DUNGEON  Level {d}/{d}   HP {d}/{d}   Gold {d}", .{
            g.level, last_level, g.hp, max_hp, g.inventory.gold,
        });
        if (g.time_stop > 0) try w.print("   TIME STOP {d}", .{g.time_stop});
        if (g.speed > 0) try w.print("   SPEED {d}", .{g.speed});
        if (g.strength > 0) try w.print("   STRENGTH +{d} ({d})", .{ g.strength_bonus, g.strength });
        try w.writeAll("\n\n");
    }

    /// Draws the inventory screen to any Writer.
    pub fn renderInventory(g: *const Game, w: *std.Io.Writer, color: bool) std.Io.Writer.Error!void {
        try g.writeHeader(w);
        try w.writeAll("========== INVENTORY ==========\n\n");
        // Only what the hero actually has is listed.
        const inv = g.inventory;
        var empty = true;
        if (inv.gold > 0) {
            empty = false;
            try w.writeAll("  Gold ................... ");
            try writeAmount(w, color, inv.gold);
            try w.writeAll("\n\n");
        }

        // Usable items, numbered by position in pick-up order.
        const items = inv.items();
        for (items, 1..) |p, number| {
            const label = switch (p) {
                .small => "Small health potion  (+1 HP)",
                .medium => "Medium health potion (+3 HP)",
                .large => "Large health potion  (+5 HP)",
                .time_stop => "Time stop potion     (3 turns)",
                .speed => "Speed potion         (10 turns)",
                .strength_small => "Small strength potion  (+1 dmg, 3 turns)",
                .strength_medium => "Medium strength potion (+2 dmg, 3 turns)",
                .strength_large => "Large strength potion  (+3 dmg, 3 turns)",
            };
            try w.print("  {d}) {s} ..... x", .{ number, label });
            try writeAmount(w, color, inv.potionCount(p));
            try w.writeByte('\n');
        }
        if (items.len > 0) {
            empty = false;
            try w.writeByte('\n');
        }

        if (empty) try w.writeAll("  (empty)\n\n");
        try w.writeAll("===============================\n");
        if (items.len == 1) {
            try w.writeAll("[1] use (uses a turn)   ");
        } else if (items.len > 1) {
            try w.print("[1-{d}] use (uses a turn)   ", .{items.len});
        }
        try w.writeAll("[Enter] close\n> ");
    }

    /// A quantity in the inventory, green when colors are on.
    fn writeAmount(w: *std.Io.Writer, color: bool, n: u32) std.Io.Writer.Error!void {
        if (color) {
            try w.print("{s}{d}{s}", .{ ansi_green, n, ansi_reset });
        } else {
            try w.print("{d}", .{n});
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
    try testing.expectEqual(Command.inventory, parseCommand("i").?);
    try testing.expectEqual(Command.use_1, parseCommand("1").?);
    try testing.expectEqual(Command.use_3, parseCommand("3").?);
    try testing.expectEqual(Command.use_9, parseCommand("9").?);
    try testing.expectEqual(@as(?usize, 0), Command.use_1.slot());
    try testing.expectEqual(@as(?usize, 8), Command.use_9.slot());
    try testing.expectEqual(@as(?usize, null), Command.wait.slot());
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
    try testing.expect(std.mem.indexOf(u8, plain, "[Enter] close") != null);
    try testing.expect(std.mem.indexOfScalar(u8, plain, 0x1b) == null);

    var cw: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&cw, true);
    try testing.expect(std.mem.indexOf(u8, cw.buffered(), ansi_green ++ "30" ++ ansi_reset) != null);
}

test "inventory lists items in pick-up order, numbered from 1" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    // Picked up: medium, then small, then another medium.
    g.inventory.add(.medium);
    g.inventory.add(.small);
    g.inventory.add(.medium);
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "1) Medium health potion (+3 HP) ..... x2") != null);
    try testing.expect(std.mem.indexOf(u8, out, "2) Small health potion  (+1 HP) ..... x1") != null);
    // Items the hero does not have are not listed.
    try testing.expect(std.mem.indexOf(u8, out, "Large health potion") == null);
    try testing.expect(std.mem.indexOf(u8, out, "[1-2] use") != null);
}

test "when an item runs out the ones below move up" {
    var inv: Inventory = .{};
    inv.add(.large);
    inv.add(.small);
    inv.add(.medium);
    try testing.expectEqualSlices(Potion, &.{ .large, .small, .medium }, inv.items());

    inv.remove(.large); // the first one runs out
    try testing.expectEqualSlices(Potion, &.{ .small, .medium }, inv.items());
    try testing.expectEqual(@as(?Potion, .small), inv.itemAt(0)); // now number 1

    inv.add(.large); // back again: goes to the end, with the next number
    try testing.expectEqualSlices(Potion, &.{ .small, .medium, .large }, inv.items());

    inv.add(.small); // a kind already listed keeps its place
    inv.remove(.small); // still has one left: stays listed
    try testing.expectEqualSlices(Potion, &.{ .small, .medium, .large }, inv.items());
    try testing.expectEqual(@as(?Potion, null), inv.itemAt(3));
}

test "inventory hides zero gold and shows (empty) when there is nothing" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    var buf: [4096]u8 = undefined;

    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    var out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "(empty)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Gold .") == null);
    try testing.expect(std.mem.indexOf(u8, out, "use (uses a turn)") == null);

    // Only a large potion: it is number 1.
    g.inventory.add(.large);
    w = .fixed(&buf);
    try g.renderInventory(&w, false);
    out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "1) Large health potion  (+5 HP) ..... x1") != null);
    try testing.expect(std.mem.indexOf(u8, out, "[1] use") != null);
    try testing.expect(std.mem.indexOf(u8, out, "(empty)") == null);
}

test "potion sizes: small 50%, medium 35%, large 15%" {
    var counts: [Potion.count]usize = @splat(0);
    for (0..100) |r| counts[Potion.fromRoll(@intCast(r)).index()] += 1;
    // Time stop has no sizes: it never comes out of the size roll.
    try testing.expectEqual([Potion.count]usize{ 50, 35, 15, 0, 0, 0, 0, 0 }, counts);
    try testing.expectEqual(@as(i32, 1), Potion.small.heal());
    try testing.expectEqual(@as(i32, 3), Potion.medium.heal());
    try testing.expectEqual(@as(i32, 5), Potion.large.heal());
    try testing.expectEqual(@as(i32, 0), Potion.time_stop.heal());
}

test "strength potions add 1, 2 and 3 damage and use the same size split" {
    var counts: [Potion.count]usize = @splat(0);
    for (0..100) |r| counts[Potion.strengthFromRoll(@intCast(r)).index()] += 1;
    try testing.expectEqual([Potion.count]usize{ 0, 0, 0, 0, 0, 50, 35, 15 }, counts);
    try testing.expectEqual(@as(i32, 1), Potion.strength_small.strength());
    try testing.expectEqual(@as(i32, 2), Potion.strength_medium.strength());
    try testing.expectEqual(@as(i32, 3), Potion.strength_large.strength());
    try testing.expectEqual(@as(i32, 0), Potion.large.strength());
    try testing.expectEqual(@as(i32, 0), Potion.strength_large.heal());
}

test "strength works at full health and shows its counter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, pocket_layout); // nothing next to the hero
    var buf: [8192]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "STRENGTH") == null);
    g.inventory.add(.strength_medium);
    g.step(.use_1);
    try testing.expect(g.events.strength);
    try testing.expectEqualStrings("You feel stronger! (+2 damage)", g.message);
    try testing.expectEqual(@as(u8, strength_turns), g.strength);
    try testing.expectEqual(@as(i32, hero_damage + 2), g.attackDamage());
    try testing.expectEqual(@as(u32, 0), g.inventory.potionCount(.strength_medium));
    try testing.expectEqual(@as(i32, max_hp), g.hp);
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "STRENGTH +2 (3)") != null);
}

test "strength lasts the drink round plus 3 rounds" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout); // a monster is next to the hero
    g.hp = 1000; // survive the bites
    g.monsters[0].hp = 100; // survive the hits
    g.inventory.add(.strength_small);
    g.step(.use_1); // the drink round is free
    for (0..strength_turns) |_| {
        const before = g.monsters[0].hp;
        g.step(.right);
        try testing.expectEqual(before - (hero_damage + 1), g.monsters[0].hp);
    }
    try testing.expectEqual(@as(u8, 0), g.strength);
    try testing.expectEqual(@as(i32, 0), g.strength_bonus);
    const before = g.monsters[0].hp;
    g.step(.right);
    try testing.expectEqual(before - hero_damage, g.monsters[0].hp);
}

test "strength bonuses add up and drinking again resets the counter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, pocket_layout);
    g.inventory.add(.strength_small); // number 1
    g.inventory.add(.strength_large); // number 2
    g.step(.use_1); // small: +1
    g.step(.wait);
    g.step(.wait);
    try testing.expectEqual(@as(u8, 1), g.strength);
    g.step(.use_1); // large is now number 1: +1 +3
    try testing.expectEqual(@as(u8, strength_turns), g.strength);
    try testing.expectEqual(@as(i32, 4), g.strength_bonus);
    try testing.expectEqual(@as(i32, hero_damage + 4), g.attackDamage());
    for (0..strength_turns) |_| g.step(.wait);
    try testing.expectEqual(@as(i32, hero_damage), g.attackDamage());
}

test "strength combines with speed and time stop: it counts rounds, not actions" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, pocket_layout);
    g.inventory.add(.speed); // number 1
    g.inventory.add(.time_stop); // number 2
    g.inventory.add(.strength_small); // number 3
    g.step(.use_1); // action 1: speed, first half of the round
    g.step(.use_2); // action 2: strength (now number 2), the round closes
    try testing.expectEqual(@as(u8, strength_turns), g.strength);
    g.step(.use_1); // action 3: time stop, the effects all stack
    try testing.expect(g.timeStopped() and g.isFast());
    try testing.expectEqual(@as(i32, hero_damage + 1), g.attackDamage());
    // Actions 4..8 keep the bonus: the counter drops only when a round closes.
    const expected = [_]u8{ 2, 2, 1, 1, 0 };
    for (expected) |left| {
        try testing.expectEqual(@as(i32, hero_damage + 1), g.attackDamage());
        g.step(.wait);
        try testing.expectEqual(left, g.strength);
    }
    try testing.expectEqual(@as(i32, hero_damage), g.attackDamage());
}

test "chest potions: about 10% time stop, 15% speed and 15% strength" {
    var potions: usize = 0;
    var time_stops: usize = 0;
    var speeds: usize = 0;
    var strengths: usize = 0;
    var seed: u64 = 0;
    while (potions < 2000) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, chest_layout);
        g.step(.right);
        const p = g.chest_potion orelse continue;
        potions += 1;
        switch (p) {
            .time_stop => time_stops += 1,
            .speed => speeds += 1,
            .strength_small, .strength_medium, .strength_large => strengths += 1,
            else => {},
        }
    }
    try testing.expect(time_stops >= 100 and time_stops <= 300); // 5%..15%
    try testing.expect(speeds >= 200 and speeds <= 400); // 10%..20%
    try testing.expect(strengths >= 200 and strengths <= 400); // 10%..20%
}

test "speed works at full health and shows its counter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.speed);
    g.step(.use_1);
    try testing.expect(g.events.speed);
    try testing.expectEqualStrings("You feel fast!", g.message);
    try testing.expectEqual(@as(u8, speed_turns), g.speed);
    try testing.expectEqual(@as(u32, 0), g.inventory.potionCount(.speed));
    try testing.expectEqual(@as(i32, max_hp), g.hp);
    var buf: [8192]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "SPEED 10") != null);
}

test "speed gives 2 actions per round for 10 rounds (20 actions)" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout); // a monster is next to the hero
    g.inventory.add(.speed);
    g.step(.use_1); // action 1: the first half of a round, nobody bites
    try testing.expectEqual(@as(i32, max_hp), g.hp);

    var bites: i32 = 0;
    for (2..21) |action| { // actions 2..20
        g.hp = max_hp - 1; // keep the hero alive and comparable
        g.step(.wait);
        const bitten = g.hp < max_hp - 1;
        if (bitten) bites += 1;
        // The round closes (and the monster acts) only on even actions.
        try testing.expectEqual(action % 2 == 0, bitten);
        if (action % 2 == 0) {
            try testing.expectEqual(@as(u8, @intCast(speed_turns - action / 2)), g.speed);
        }
    }
    try testing.expectEqual(@as(i32, 10), bites);
    try testing.expectEqual(@as(u8, 0), g.speed);

    // Back to normal: every action is a full round, every one bites.
    for (0..2) |_| {
        g.hp = 5;
        g.step(.wait);
        try testing.expectEqual(@as(i32, 5 - monster_damage), g.hp);
    }
}

test "speed and time stop combine: time stop counts rounds, not actions" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout); // a monster is next to the hero
    g.hp = 5;
    g.inventory.add(.speed); // number 1
    g.inventory.add(.time_stop); // number 2
    g.step(.use_1); // action 1: speed (first half of the round)
    g.step(.use_1); // action 2: time stop is now number 1; the round closes
    try testing.expectEqual(@as(u8, time_stop_turns), g.time_stop);

    // Actions 3..8: the time stop counter only drops on even actions.
    const expected = [_]u8{ 3, 2, 2, 1, 1, 0 };
    for (expected) |left| {
        g.step(.wait);
        try testing.expectEqual(left, g.time_stop);
        try testing.expectEqual(@as(i32, 5), g.hp); // frozen: no bite
    }
    g.step(.wait); // action 9: first half of a round
    try testing.expectEqual(@as(i32, 5), g.hp);
    g.step(.wait); // action 10: the round closes and time runs again
    try testing.expectEqual(@as(i32, 5 - monster_damage), g.hp);
}

test "time stop drunk in the first half of a fast round still gives 3 free rounds" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.hp = 5;
    g.inventory.add(.speed);
    g.inventory.add(.time_stop);
    g.step(.use_1); // action 1: speed, first half
    g.step(.wait); // action 2: closes the round (the monster bites here)
    g.hp = 5;
    g.step(.use_1); // action 3: time stop in the first half of a round
    // Frozen rounds: (3,4) where it was drunk, then (5,6), (7,8), (9,10).
    for (4..12) |_| { // actions 4..11
        g.step(.wait);
        try testing.expectEqual(@as(i32, 5), g.hp);
    }
    g.step(.wait); // action 12: the round closes with time running
    try testing.expectEqual(@as(i32, 5 - monster_damage), g.hp);
}

test "drinking speed again resets the counter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.hp = 1000; // survive the bites
    g.inventory.add(.speed);
    g.inventory.add(.speed);
    g.step(.use_1);
    for (0..5) |_| g.step(.wait); // 3 rounds closed
    try testing.expectEqual(@as(u8, speed_turns - 3), g.speed);
    g.step(.use_1);
    try testing.expectEqual(@as(u8, speed_turns), g.speed);
}

test "a fast hero has a cyan background" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, pocket_layout); // nothing next to the hero
    var buf: [16384]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .color = true }), ansi_cyan ++ "@") != null);
    g.inventory.add(.speed);
    g.step(.use_1);
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_fast ++ "@" ++ ansi_reset) != null);
}

test "time stop freezes monsters on the drink turn and 3 more" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout); // a monster is next to the hero
    g.hp = 5;
    g.inventory.add(.time_stop);
    const monster_pos = g.monsters[0].pos;

    g.step(.use_1);
    try testing.expect(g.events.time_stop);
    try testing.expectEqualStrings("Time stops! The monsters are frozen.", g.message);
    try testing.expectEqual(@as(u8, 3), g.time_stop);
    try testing.expectEqual(@as(usize, 0), g.inventory.items().len);

    const expected_counter = [_]u8{ 2, 1, 0 };
    for (expected_counter) |left| {
        g.step(.wait);
        try testing.expectEqual(left, g.time_stop);
        try testing.expectEqual(@as(i32, 5), g.hp); // no bite
        try testing.expectEqual(monster_pos, g.monsters[0].pos);
    }

    g.step(.wait); // time runs again
    try testing.expectEqual(@as(i32, 5 - monster_damage), g.hp);
}

test "time stop works at full health" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.time_stop);
    g.step(.use_1);
    try testing.expect(g.events.time_stop);
    try testing.expectEqual(@as(u32, 0), g.inventory.potionCount(.time_stop));
    try testing.expectEqual(@as(i32, max_hp), g.hp);
}

test "frozen far-away monsters do not wander" {
    var prng = std.Random.DefaultPrng.init(3);
    var g = testGame(&prng, pocket_layout);
    g.inventory.add(.time_stop);
    const start = g.monsters[0].pos;
    g.step(.use_1);
    for (0..time_stop_turns) |_| g.step(.wait);
    try testing.expectEqual(start, g.monsters[0].pos);
}

test "the hero can hit a frozen monster, which does not strike back" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.time_stop);
    g.step(.use_1);
    g.step(.right); // attack the adjacent monster
    try testing.expectEqual(@as(i32, monster_hp - hero_damage), g.monsters[0].hp);
    try testing.expectEqual(@as(i32, max_hp), g.hp);
}

test "drinking time stop again resets the counter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.time_stop);
    g.inventory.add(.time_stop);
    g.step(.use_1);
    g.step(.wait);
    g.step(.wait);
    try testing.expectEqual(@as(u8, 1), g.time_stop);
    g.step(.use_1);
    try testing.expectEqual(@as(u8, time_stop_turns), g.time_stop);
}

test "time stop shows blue monsters and a header counter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    var buf: [8192]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "TIME STOP") == null);

    g.inventory.add(.time_stop);
    g.step(.use_1);
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_blue ++ "M" ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, "TIME STOP 3") != null);
}

test "inventory lists the speed potion in pick-up order" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.speed);
    g.inventory.add(.large);
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "1) Speed potion         (10 turns) ..... x1") != null);
    try testing.expect(std.mem.indexOf(u8, out, "2) Large health potion  (+5 HP) ..... x1") != null);
}

test "inventory lists strength potions in pick-up order" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.strength_large);
    g.inventory.add(.small);
    g.inventory.add(.strength_small);
    g.inventory.add(.strength_small);
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "1) Large strength potion  (+3 dmg, 3 turns) ..... x1") != null);
    try testing.expect(std.mem.indexOf(u8, out, "2) Small health potion  (+1 HP) ..... x1") != null);
    try testing.expect(std.mem.indexOf(u8, out, "3) Small strength potion  (+1 dmg, 3 turns) ..... x2") != null);
}

test "inventory lists the time stop potion without a size" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.small);
    g.inventory.add(.time_stop);
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "1) Small health potion  (+1 HP) ..... x1") != null);
    try testing.expect(std.mem.indexOf(u8, out, "2) Time stop potion     (3 turns) ..... x1") != null);
}

/// Open floor with a chest right of the hero.
const chest_layout: Layout = .{
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
};

test "85% of the chests hold a potion, and then no gold" {
    var with_potion: usize = 0;
    const trials = 1000;
    for (0..trials) |seed| {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, chest_layout);
        g.step(.right);
        if (g.chest_potion) |p| {
            with_potion += 1;
            try testing.expectEqual(@as(u32, 1), g.inventory.potionCount(p));
            try testing.expectEqualSlices(Potion, &.{p}, g.inventory.items());
            // Only the item: no gold with it.
            try testing.expectEqual(@as(u32, 0), g.chest_gold);
            try testing.expectEqual(@as(u32, 0), g.inventory.gold);
            // The message names the potion, without gold.
            var buf: [4096]u8 = undefined;
            var expected: [32]u8 = undefined;
            const text = try std.fmt.bufPrint(&expected, "({s})", .{p.label()});
            const out = try renderToBuf(&g, &buf, .{});
            try testing.expect(std.mem.indexOf(u8, out, text) != null);
            try testing.expect(std.mem.indexOf(u8, out, "gold)") == null);
        } else {
            try testing.expectEqual(@as([Potion.count]u32, @splat(0)), g.inventory.potions);
            try testing.expectEqual(@as(usize, 0), g.inventory.items().len);
            try testing.expect(g.chest_gold >= chest_gold_min);
        }
    }
    try testing.expect(with_potion >= 800 and with_potion <= 900);
}

test "drinking heals, caps at max HP and uses a turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout); // a monster is next to the hero
    g.hp = 4;
    g.inventory.add(.medium); // number 1
    g.inventory.add(.large); // number 2

    g.step(.use_1);
    try testing.expectEqual(@as(i32, 3), g.healed);
    try testing.expect(g.events.drink);
    try testing.expectEqual(@as(u32, 0), g.inventory.potionCount(.medium));
    // 4 + 3, then the adjacent monster bites: the turn passed.
    try testing.expectEqual(@as(i32, 4 + 3 - monster_damage), g.hp);
    // The medium potion ran out, so the large one is now number 1.
    try testing.expectEqual(@as(?Potion, .large), g.inventory.itemAt(0));

    g.hp = 8;
    g.step(.use_1);
    try testing.expectEqual(@as(i32, 2), g.healed); // capped at max_hp
    try testing.expectEqual(@as(i32, max_hp - monster_damage), g.hp);

    var buf: [4096]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "(+2 HP)") != null);

    // Next turn the drink state is cleared.
    g.step(.left);
    try testing.expectEqual(@as(i32, 0), g.healed);
    try testing.expect(!g.events.drink);
}

test "using a number with no item uses no turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.hp = 5;
    g.inventory.add(.small);
    g.step(.use_2); // only number 1 exists
    try testing.expectEqualStrings("You have no item with that number.", g.message);
    try testing.expectEqual(@as(i32, 5), g.hp); // the adjacent monster did not bite
    try testing.expect(!g.events.drink);
    try testing.expectEqual(@as(u32, 1), g.inventory.potionCount(.small));
}

test "drinking at full health keeps the potion and uses no turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.small);
    g.step(.use_1);
    try testing.expectEqualStrings("You are already at full health.", g.message);
    try testing.expectEqual(@as(u32, 1), g.inventory.potionCount(.small));
    try testing.expectEqual(@as(i32, max_hp), g.hp);
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

test "a chest without a potion gives 20 to 50 gold" {
    // Find a seed whose chest holds gold (only 15% of them do).
    var seed: u64 = 0;
    var prng = std.Random.DefaultPrng.init(seed);
    var g = testGame(&prng, chest_layout);
    g.inventory.gold = 5;
    g.step(.right);
    while (g.chest_potion != null) {
        seed += 1;
        prng = std.Random.DefaultPrng.init(seed);
        g = testGame(&prng, chest_layout);
        g.inventory.gold = 5;
        g.step(.right);
    }
    try testing.expectEqual(Pos{ .x = 2, .y = 1 }, g.hero);
    try testing.expect(g.chest_gold >= chest_gold_min and g.chest_gold <= chest_gold_max);
    try testing.expectEqual(5 + g.chest_gold, g.inventory.gold);
    try testing.expectEqual(@as(usize, 0), g.inventory.items().len);
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
