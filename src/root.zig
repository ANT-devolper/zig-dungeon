//! Brewdungeon: pure game logic (no I/O), so it is easy to test.
const std = @import("std");

pub const sound = @import("sound.zig");

pub const W = 31;
pub const H = 13;
pub const max_monsters = 8;
/// The hero's max HP at the start of a run (offerings raise it, see
/// `Game.max_hp`).
pub const start_max_hp = 10;

const hero_damage = 2;
/// A sneak attack (hero invisible or time stopped) multiplies the hero's
/// whole damage, strength bonus included.
const sneak_multiplier = 2;
/// Monster HP on levels 1-3; they gain 1 HP every `monster_hp_step` levels.
const monster_hp = 3;
const monster_hp_step = 3;
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
/// Chance (in %) that a chest's potion is a vision potion.
const vision_chance = 10;
/// Rounds the hero sees the whole map after the round it was drunk in.
pub const vision_turns = 3;
/// Chance (in %) that a chest's potion is an invisibility potion.
const invisibility_chance = 10;
/// Rounds the hero stays invisible after the round it was drunk in.
pub const invisible_turns = 5;
/// Chance (in %) that a chest's potion is a mystery potion.
const mystery_chance = 10;
/// Chance (in %) that a mystery potion is good (a random chest potion);
/// otherwise it is a curse.
const mystery_good_chance = 50;
/// Curse durations, in rounds after the round the mystery was drunk in.
pub const slow_turns = 3;
pub const blind_turns = 5;
pub const confused_turns = 5;
/// Damage of the burning curse (it never kills: the hero keeps 1 HP).
const curse_damage = 2;
/// Field of view radius while blind.
const blind_radius = 2;
/// Chance (in %) that the shop shows up the first time its event is called
/// (on the stairs of every even level, see `Game.nextLevel`).
const shop_first_chance = 80;
/// Chance (in %) that the shop shows up on every later call.
const shop_chance = 50;
/// Chance (in %) that the shop event brings a fountain instead of a shop.
const fountain_chance = 30;
/// HP the fountain heals, once, for free.
const fountain_heal = 5;
/// Gold the fountain's offering costs, and the max HP it gives (once).
const offering_price = 40;
const offering_max_hp = 2;
/// Chance (in %) that a maze level holds a totem (never two levels in a row).
const totem_chance = 10;
/// Chance (in %) that a totem heals completely; otherwise it curses.
const totem_heal_chance = 60;

/// Potion kinds the hero can carry: three sizes of health potion, three
/// sizes of strength potion, plus the time stop, speed, vision,
/// invisibility and mystery potions, which are single kinds with no sizes.
pub const Potion = enum {
    small,
    medium,
    large,
    time_stop,
    speed,
    strength_small,
    strength_medium,
    strength_large,
    vision,
    /// The monsters lose track of the hero; attacking ends it.
    invisibility,
    /// 50% a random chest potion, 50% a curse (see `Curse`).
    mystery,

    pub const count = 11;

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
            .vision => "vision potion",
            .invisibility => "invisibility potion",
            .mystery => "???", // the name is a mystery too (a user choice)
        };
    }

    /// ANSI color of each kind (the shop's '!' and the inventory names):
    /// health green, strength brown, time stop yellow, vision purple,
    /// speed blue, invisibility gray.
    pub fn color(p: Potion) []const u8 {
        return switch (p) {
            .small, .medium, .large => ansi_green,
            .strength_small, .strength_medium, .strength_large => ansi_brown,
            .time_stop => ansi_yellow,
            .vision => ansi_purple,
            .invisibility => ansi_invisible,
            .speed => ansi_blue,
            .mystery => ansi_white,
        };
    }

    /// Shop price in gold: rarer potions cost more.
    pub fn price(p: Potion) u32 {
        return switch (p) {
            .small => 10,
            .medium => 15,
            .speed => 20,
            .time_stop => 25,
            .vision => 25,
            .invisibility => 25,
            .large => 30,
            .strength_small => 30,
            .strength_medium => 45,
            .strength_large => 70,
            .mystery => 10, // a gamble, cheap (a user choice)
        };
    }

    fn index(p: Potion) usize {
        return @backingInt(p);
    }
};
/// What a bad mystery potion does, each 1 time in 5 (user rules).
pub const Curse = enum {
    /// The monsters act twice per round for `slow_turns` rounds.
    slow,
    /// The hero's next action is lost.
    paralysis,
    /// `curse_damage` damage, but never below 1 HP.
    burn,
    /// The field of view shrinks to `blind_radius` for `blind_turns` rounds.
    blind,
    /// Move keys are inverted for `confused_turns` rounds.
    confused,
};

/// Chance (in %) that a monster that is not chasing takes a random step.
const wander_chance = 30;

pub const Tile = enum {
    wall,
    floor,
    gold,
    chest,
    stairs,
    /// Fountain level: heals `fountain_heal` once; it blocks like a wall.
    fountain,
    /// Fountain level: walking over it pays `offering_price` for max HP.
    offering,
    /// Maze level: walking over it heals completely or curses.
    totem,
};

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

/// What a monster is. Each kind has its own letter, HP, bite and sight.
pub const MonsterKind = enum {
    /// The plain `M`.
    monster,

    /// The letter drawn on the map.
    pub fn symbol(k: MonsterKind) u8 {
        return switch (k) {
            .monster => 'M',
        };
    }

    /// HP when it spawns on level `level`.
    pub fn maxHp(k: MonsterKind, level: u32) i32 {
        return switch (k) {
            .monster => Game.monsterHp(level),
        };
    }

    /// Damage of one bite.
    pub fn damage(k: MonsterKind) i32 {
        return switch (k) {
            .monster => monster_damage,
        };
    }

    /// Chase radius (Manhattan distance): it comes after the hero from
    /// this far away (user rules).
    pub fn sight(k: MonsterKind) i32 {
        return switch (k) {
            .monster => 4,
        };
    }

    pub fn biteMessage(k: MonsterKind) []const u8 {
        return switch (k) {
            .monster => "A monster bites you!",
        };
    }

    pub fn hitMessage(k: MonsterKind) []const u8 {
        return switch (k) {
            .monster => "You hit the monster.",
        };
    }

    pub fn defeatMessage(k: MonsterKind) []const u8 {
        return switch (k) {
            .monster => "You defeated a monster!",
        };
    }
};

pub const Monster = struct {
    pos: Pos,
    hp: i32,
    kind: MonsterKind = .monster,
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
const ansi_blue = "\x1b[1;34m"; // frozen monsters (time stop), speed potions
const ansi_fast = "\x1b[1;30;46m"; // black on cyan: the hero while fast (speed)
const ansi_dim = "\x1b[38;5;248m"; // light gray: out of sight
const ansi_bite = "\x1b[1;37;41m"; // white on red: the monster that just bit
const ansi_red_bg = "\x1b[41m";
const ansi_spark = "\x1b[1;37;45m";
const ansi_shopkeeper = "\x1b[1;38;5;208m"; // orange: the shopkeeper's '@'
const ansi_purple = "\x1b[1;38;5;129m"; // vision potions
const ansi_brown = "\x1b[1;38;5;130m"; // strength potions
const ansi_white = "\x1b[1;37m"; // mystery potions
const ansi_invisible = "\x1b[1;38;5;244m"; // gray: invisibility potions, the invisible hero

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

    /// The opposite move (confusion curse); other commands stay the same.
    fn reversed(c: Command) Command {
        return switch (c) {
            .up => .down,
            .down => .up,
            .left => .right,
            .right => .left,
            else => c,
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

pub const State = enum { playing, lost, quit };

/// Things that happened during the last turn (used for sound effects).
/// Strikes and damage are tracked by `hit_pos`, `hit_killed` and `damage_taken`.
pub const Events = struct {
    gold: bool = false,
    chest: bool = false,
    /// The clear reward was given (the last monster of the level died).
    reward: bool = false,
    drink: bool = false,
    time_stop: bool = false,
    speed: bool = false,
    strength: bool = false,
    vision: bool = false,
    invisible: bool = false,
    stairs: bool = false,
    buy: bool = false,
    curse: bool = false,
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

/// Reads one key press from any Reader. Returns null at the end of the input.
/// - Skips '\n', which only comes from redirected input (a file with one
///   command per line); Enter in a raw console is '\r'.
/// - The arrow keys arrive as escape sequences (`ESC [ A` or `ESC O A`) and
///   come out as the matching letter: up 'w', down 's', right 'd', left 'a'.
///   Other sequences (Ctrl+arrow, Insert, F-keys...) are skipped whole.
/// - An ESC followed by any other byte is dropped and that byte is returned.
pub fn readKey(in: *std.Io.Reader) std.Io.Reader.Error!?u8 {
    while (true) {
        const b = try takeKeyByte(in) orelse return null;
        if (b == '\n') continue;
        if (b != 0x1b) return b;

        const intro = try takeKeyByte(in) orelse return null;
        if (intro != '[' and intro != 'O') {
            if (intro == '\n') continue;
            return intro;
        }
        // Parameter bytes (digits, ';'...) until the final byte 0x40-0x7E.
        var params = false;
        const final = while (true) {
            const c = try takeKeyByte(in) orelse return null;
            if (c >= 0x40 and c <= 0x7e) break c;
            params = true;
        };
        if (params) continue;
        switch (final) {
            'A' => return 'w',
            'B' => return 's',
            'C' => return 'd',
            'D' => return 'a',
            else => continue,
        }
    }
}

/// One byte of input, or null at the end of it.
fn takeKeyByte(in: *std.Io.Reader) std.Io.Reader.Error!?u8 {
    return in.takeByte() catch |err| switch (err) {
        error.EndOfStream => null,
        else => |e| e,
    };
}

/// Hand-drawn level used by tests: '#' wall, '.' floor, '@' start,
/// '>' stairs, 'M' monster and '$' gold. Real levels are generated.
/// Map rows for tests and fixed levels; tiles past the given rows and
/// columns are wall.
pub const Layout = []const []const u8;

// Maze generator settings. Maze cells sit on odd coordinates and the even
// tiles between two cells are walls that can be opened. The odd 31x13 map
// fits 15x6 cells exactly, with a single wall line on every side.
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

// Shop level layout: one lit room in the middle of the map.
const shop_room = .{ .x0 = 9, .y0 = 3, .x1 = 21, .y1 = 9 };
const shopkeeper_pos: Pos = .{ .x = 15, .y = 3 };
/// Where the shop's items lie (`Game.shop_items` in the same order).
const shop_item_pos = [2]Pos{ .{ .x = 12, .y = 6 }, .{ .x = 18, .y = 6 } };
const shop_hero_start: Pos = .{ .x = 10, .y = 9 };
const shop_stairs: Pos = .{ .x = 20, .y = 9 };
// Fountain level: the same room, with the fountain in the middle and the
// offering above it.
const fountain_pos: Pos = .{ .x = 15, .y = 6 };
const offering_pos: Pos = .{ .x = 15, .y = 4 };

/// Map tile at the center of maze cell `c`.
fn cellTile(c: Pos) Pos {
    return .{ .x = 2 * c.x + 1, .y = 2 * c.y + 1 };
}

/// What one chest roll gives: a potion or gold, never both.
pub const ChestLoot = union(enum) { potion: Potion, gold: u32 };

/// Chest rolls the hero gets for killing every monster on level `level`:
/// one per monster HP tier (the same `monster_hp_step` as `monsterHp`),
/// so 1 on levels 1-3, 2 on 4-6, 3 on 7-9... with no cap.
pub fn rewardChests(level: u32) u32 {
    return (level - 1) / monster_hp_step + 1;
}

pub const Game = struct {
    map: [H][W]Tile = undefined,
    hero: Pos = .{ .x = 1, .y = 1 },
    hp: i32 = start_max_hp,
    /// Max HP: `start_max_hp`, raised by offerings at fountains.
    max_hp: i32 = start_max_hp,
    inventory: Inventory = .{},
    level: u32 = 1,
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
    /// Chest rolls given during the last turn for killing the last monster
    /// of the level (0 if none), and what they held: potion counts by
    /// `Potion.index()` and the total gold.
    reward_chests: u32 = 0,
    reward_potions: [Potion.count]u32 = @splat(0),
    reward_gold: u32 = 0,
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
    /// Rounds left seeing the whole map (vision potion).
    vision: u8 = 0,
    /// Vision was drunk during the current round, which does not count.
    vision_fresh: bool = false,
    /// Rounds left hidden from the monsters (invisibility potion).
    invisible: u8 = 0,
    /// Invisibility was drunk during the current round, which does not count.
    invisible_fresh: bool = false,
    /// The hero attacked during the last turn and lost the invisibility.
    revealed: bool = false,
    /// Damage of the sneak attack made during the last turn (0 if none).
    sneak_damage: i32 = 0,
    /// Curses from a bad mystery potion (see `Curse`). Like vision, each
    /// counter has a fresh flag: the round it was drunk in is free.
    slow: u8 = 0,
    slow_fresh: bool = false,
    blind: u8 = 0,
    blind_fresh: bool = false,
    confused: u8 = 0,
    confused_fresh: bool = false,
    /// The hero's next action is lost (paralysis curse).
    paralyzed: bool = false,
    /// What the mystery potion drunk during the last turn turned out to be.
    mystery_potion: ?Potion = null,
    mystery_curse: ?Curse = null,
    /// A fast hero already used the first of the 2 actions of this round.
    half_round: bool = false,
    /// The current level is a shop (see `loadShop`).
    in_shop: bool = false,
    /// Times the shop event was called (the first call has a higher chance).
    shop_calls: u32 = 0,
    /// A shop just showed up, so the next chance is skipped (no roll).
    shop_skip: bool = false,
    /// What the shop still sells, at `shop_item_pos` (null once bought).
    shop_items: [2]?Potion = @splat(null),
    /// Item bought during the last turn, if any.
    shop_bought: ?Potion = null,
    /// Item the hero stepped on without enough gold during the last turn.
    shop_refused: ?Potion = null,
    /// The current level is a fountain (see `loadFountain`).
    in_fountain: bool = false,
    /// The fountain already healed the hero (it heals once).
    fountain_used: bool = false,
    /// An offering was made during the last turn, or refused for lack of gold.
    offering_made: bool = false,
    offering_refused: bool = false,
    /// The last level that held a totem (never two levels in a row).
    last_totem_level: ?u32 = null,
    /// The curse a totem gave during the last turn, if any.
    totem_curse: ?Curse = null,
    events: Events = .{},
    rng: std.Random,

    /// Starts a new game on level 1, with random monsters and gold.
    pub fn init(rng: std.Random) Game {
        var g: Game = .{ .rng = rng };
        g.loadLevel(1);
        g.message = "Find the stairs (>)! Beware of the monsters (M).";
        return g;
    }

    /// Generates level `n` (1, 2, ... with no end), keeping HP and gold.
    pub fn loadLevel(g: *Game, n: u32) void {
        g.level = n;
        g.in_shop = false;
        g.in_fountain = false;
        g.shop_items = @splat(null);
        g.generateLevel();
        g.spawnLoot();
        g.spawnTotem();
        g.spawnMonsters(@min(max_monsters, 1 + n * 2));
    }

    /// Makes level `n` a shop: one lit room with the shopkeeper, two potions
    /// for sale (rolled like a chest's) and the stairs. No monsters, no loot.
    pub fn loadShop(g: *Game, n: u32) void {
        g.loadRoom(n);
        g.in_shop = true;
        for (&g.shop_items) |*item| item.* = g.randomPotion();
    }

    /// Makes level `n` a fountain: the shop's lit room with a fountain that
    /// heals once for free, an offering that sells max HP, and the stairs.
    pub fn loadFountain(g: *Game, n: u32) void {
        g.loadRoom(n);
        g.in_fountain = true;
        g.fountain_used = false;
        g.setTile(fountain_pos, .fountain);
        g.setTile(offering_pos, .offering);
    }

    /// The empty lit room shared by shops and fountains: the hero at the
    /// bottom left, the stairs at the bottom right, no monsters, no loot.
    fn loadRoom(g: *Game, n: u32) void {
        g.level = n;
        g.in_shop = false;
        g.in_fountain = false;
        g.shop_items = @splat(null);
        g.monster_count = 0;
        for (&g.map) |*row| @memset(row, .wall);
        var y: i32 = shop_room.y0;
        while (y <= shop_room.y1) : (y += 1) {
            var x: i32 = shop_room.x0;
            while (x <= shop_room.x1) : (x += 1) g.setTile(.{ .x = x, .y = y }, .floor);
        }
        g.hero = shop_hero_start;
        g.setTile(shop_stairs, .stairs);
    }

    /// True on a shop or fountain level: one lit room, no monsters.
    pub fn inRoom(g: *const Game) bool {
        return g.in_shop or g.in_fountain;
    }

    /// Takes the stairs: the next level, a shop or a fountain. The event is
    /// called on the stairs of every even level, unless one just showed up;
    /// when it fires, it is a fountain `fountain_chance`% of the time.
    fn nextLevel(g: *Game) void {
        const n = g.level + 1;
        if (g.inRoom() or g.level % 2 != 0) return g.loadLevel(n);
        if (g.shop_skip) {
            g.shop_skip = false; // the chance after a shop or fountain is skipped
            return g.loadLevel(n);
        }
        const chance: u8 = if (g.shop_calls == 0) shop_first_chance else shop_chance;
        g.shop_calls += 1;
        if (g.rng.uintLessThan(u8, 100) < chance) {
            g.shop_skip = true;
            if (g.rng.uintLessThan(u8, 100) < fountain_chance) {
                g.loadFountain(n);
            } else {
                g.loadShop(n);
            }
        } else {
            g.loadLevel(n);
        }
    }

    /// The hero bumps the fountain: it heals `fountain_heal` once, and not
    /// at full HP (then it stays for later).
    fn useFountain(g: *Game) void {
        if (g.fountain_used) {
            g.message = "The fountain is dry.";
        } else if (g.hp >= g.max_hp) {
            g.message = "You are already at full health.";
        } else {
            g.heal(fountain_heal);
            g.fountain_used = true;
            g.events.drink = true;
            g.message = "You drink from the fountain.";
        }
    }

    /// The hero stands on the offering: with enough gold it raises max HP
    /// (and heals the new points) and disappears.
    fn makeOffering(g: *Game, p: Pos) void {
        if (g.inventory.gold < offering_price) {
            g.offering_refused = true;
            g.message = "Not enough gold.";
            return;
        }
        g.inventory.gold -= offering_price;
        g.max_hp += offering_max_hp;
        g.hp += offering_max_hp;
        g.setTile(p, .floor);
        g.offering_made = true;
        g.events.buy = true;
        g.message = "You make an offering. You feel tougher!";
    }

    /// The hero stands on a totem: it heals completely
    /// (`totem_heal_chance`%) or casts a random curse, then disappears.
    fn touchTotem(g: *Game, p: Pos) void {
        g.setTile(p, .floor);
        if (g.rng.uintLessThan(u8, 100) < totem_heal_chance) {
            g.heal(g.max_hp);
            g.events.drink = true;
            g.message = "The totem glows. You are fully healed!";
        } else {
            const c = g.randomCurse();
            g.totem_curse = c;
            g.events.curse = true;
            g.applyCurse(c); // sets the message; render() adds "(a totem curse)"
        }
    }

    /// Heals up to `amount` HP, never past `max_hp`; records it in `healed`.
    fn heal(g: *Game, amount: i32) void {
        const before = g.hp;
        g.hp = @min(g.max_hp, g.hp + amount);
        g.healed = g.hp - before;
    }

    /// On a maze level, turns one loot spot into a totem `totem_chance`% of
    /// the time, never on two levels in a row.
    fn spawnTotem(g: *Game) void {
        if (g.last_totem_level) |last| {
            if (last + 1 == g.level) return;
        }
        if (g.rng.uintLessThan(u8, 100) >= totem_chance) return;
        var spots: [loot_count]Pos = undefined;
        var n: usize = 0;
        for (0..H) |y| for (0..W) |x| switch (g.map[y][x]) {
            .gold, .chest => if (n < spots.len) {
                spots[n] = .{ .x = @intCast(x), .y = @intCast(y) };
                n += 1;
            },
            else => {},
        };
        if (n == 0) return;
        g.setTile(spots[g.rng.uintLessThan(usize, n)], .totem);
        g.last_totem_level = g.level;
    }

    /// The shop item at `p`, if any (its index in `shop_items`).
    fn shopItemAt(g: *const Game, p: Pos) ?usize {
        if (!g.in_shop) return null;
        for (shop_item_pos, 0..) |ip, i| {
            if (ip.eql(p) and g.shop_items[i] != null) return i;
        }
        return null;
    }

    fn isShopkeeper(g: *const Game, p: Pos) bool {
        return g.in_shop and p.eql(shopkeeper_pos);
    }

    /// The hero stands on shop item `i`: buys it if the gold is enough.
    /// render() appends the item and price to the message.
    fn buy(g: *Game, i: usize) void {
        const p = g.shop_items[i].?;
        if (g.inventory.gold < p.price()) {
            g.shop_refused = p;
            g.message = "Not enough gold.";
            return;
        }
        g.inventory.gold -= p.price();
        g.inventory.add(p);
        g.shop_items[i] = null;
        g.shop_bought = p;
        g.events.buy = true;
        g.message = "You bought it!";
    }

    /// Rolls one chest and puts what it holds in the inventory. A chest
    /// holds either a potion or gold, never both. Chest tiles and the clear
    /// reward use it.
    fn openChest(g: *Game) ChestLoot {
        if (g.rng.uintLessThan(u8, 100) < chest_potion_chance) {
            const kind = g.randomPotion();
            g.inventory.add(kind);
            return .{ .potion = kind };
        }
        const gold = g.rng.intRangeAtMost(u32, chest_gold_min, chest_gold_max);
        g.inventory.gold += gold;
        return .{ .gold = gold };
    }

    /// The last monster of the level died: `rewardChests(level)` chest
    /// rolls go straight to the inventory. render() lists them.
    fn giveClearReward(g: *Game) void {
        g.reward_chests = rewardChests(g.level);
        for (0..g.reward_chests) |_| switch (g.openChest()) {
            .potion => |kind| g.reward_potions[kind.index()] += 1,
            .gold => |n| g.reward_gold += n,
        };
        g.events.reward = true;
    }

    /// Rolls a potion with the chest split (time stop, speed, strength,
    /// vision, health). Chests and the shop use it.
    fn randomPotion(g: *Game) Potion {
        const roll = g.rng.uintLessThan(u8, 100);
        return if (roll < time_stop_chance)
            .time_stop
        else if (roll < time_stop_chance + speed_chance)
            .speed
        else if (roll < time_stop_chance + speed_chance + strength_chance)
            Potion.strengthFromRoll(g.rng.uintLessThan(u8, 100))
        else if (roll < time_stop_chance + speed_chance + strength_chance + vision_chance)
            .vision
        else if (roll < time_stop_chance + speed_chance + strength_chance + vision_chance + invisibility_chance)
            .invisibility
        else if (roll < time_stop_chance + speed_chance + strength_chance + vision_chance + invisibility_chance + mystery_chance)
            .mystery
        else
            Potion.fromRoll(g.rng.uintLessThan(u8, 100));
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
        for (&g.map) |*row| @memset(row, .wall);
        for (layout, 0..) |row, y| {
            for (row, 0..) |c, x| {
                const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
                g.map[y][x] = switch (c) {
                    '#' => .wall,
                    '>' => .stairs,
                    '$' => .gold,
                    '&' => .chest,
                    '~' => .fountain,
                    '+' => .offering,
                    'Y' => .totem,
                    else => .floor,
                };
                switch (c) {
                    '@' => g.hero = p,
                    'M' => g.addMonster(p, .monster),
                    else => {},
                }
            }
        }
    }

    /// Monsters get tougher the deeper the hero goes.
    fn monsterHp(level: u32) i32 {
        return monster_hp + @as(i32, @intCast((level - 1) / monster_hp_step));
    }

    fn addMonster(g: *Game, p: Pos, kind: MonsterKind) void {
        if (g.monster_count == max_monsters) return;
        g.monsters[g.monster_count] = .{ .pos = p, .hp = kind.maxHp(g.level), .kind = kind };
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
            g.addMonster(p, .monster);
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
        g.reward_chests = 0;
        g.reward_potions = @splat(0);
        g.reward_gold = 0;
        g.healed = 0;
        g.shop_bought = null;
        g.shop_refused = null;
        g.offering_made = false;
        g.offering_refused = false;
        g.revealed = false;
        g.sneak_damage = 0;
        g.totem_curse = null;
        g.mystery_potion = null;
        g.mystery_curse = null;
        for (g.monsters[0..g.monster_count]) |*m| m.bit = false;

        // Paralysis (a curse) turns the next action into a lost turn;
        // quitting still works.
        const paralyzed = g.paralyzed and cmd != .quit;
        if (paralyzed) g.paralyzed = false;
        var action = if (paralyzed) Command.wait else cmd;
        // Confusion (a curse) inverts the move keys.
        if (g.confused > 0) action = action.reversed();

        switch (action) {
            .quit => {
                g.state = .quit;
                g.message = "You fled the dungeon.";
                return;
            },
            .wait => g.message = if (paralyzed) "You are paralyzed! You lose this turn." else "You wait...",
            .inventory => unreachable, // handled above
            .use_1, .use_2, .use_3, .use_4, .use_5, .use_6, .use_7, .use_8, .use_9 => {
                // Using nothing, or failing to drink, does not use a turn:
                // return before the monsters act.
                const item = g.inventory.itemAt(action.slot().?) orelse {
                    g.message = "You have no item with that number.";
                    return;
                };
                if (!g.drink(item)) return;
            },
            .up, .down, .left, .right => {
                const target = g.hero.add(action.delta());
                if (g.monsterAt(target)) |i| {
                    // A monster that cannot see the hero (invisible) or
                    // cannot act (time stop) takes a sneak attack.
                    const sneak = g.isSneaky();
                    // Attacking gives the hero away: the invisibility ends
                    // and the monsters act normally this round. Time stop
                    // goes on.
                    if (g.invisible > 0) {
                        g.invisible = 0;
                        g.invisible_fresh = false;
                        g.revealed = true;
                    }
                    const damage = g.attackDamage() * @as(i32, if (sneak) sneak_multiplier else 1);
                    if (sneak) g.sneak_damage = damage; // render() appends it
                    g.monsters[i].hp -= damage;
                    g.hit_pos = target;
                    const kind = g.monsters[i].kind;
                    if (g.monsters[i].hp <= 0) {
                        g.removeMonster(i);
                        g.hit_killed = true;
                        if (g.stairsRevealed()) {
                            g.giveClearReward();
                            // render() appends the reward.
                            g.message = "You defeated the last monster! The stairs are revealed.";
                        } else {
                            g.message = kind.defeatMessage();
                        }
                    } else {
                        g.message = kind.hitMessage();
                    }
                } else if (g.isShopkeeper(target)) {
                    g.message = "The shopkeeper smiles. Walk over an item to buy it.";
                } else switch (g.tileAt(target)) {
                    .wall => g.message = "A wall blocks the way.",
                    .fountain => g.useFountain(),
                    .offering => {
                        g.hero = target;
                        g.makeOffering(target);
                    },
                    .totem => {
                        g.hero = target;
                        g.touchTotem(target);
                    },
                    .floor => {
                        g.hero = target;
                        g.message = "";
                        if (g.shopItemAt(target)) |i| g.buy(i);
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
                        switch (g.openChest()) {
                            .potion => |kind| g.chest_potion = kind,
                            .gold => |n| g.chest_gold = n,
                        }
                        g.setTile(target, .floor);
                        // render() appends what was inside: "(+N gold)" or "(small potion)".
                        g.message = "You open the chest!";
                    },
                    .stairs => {
                        // The dungeon has no bottom: always one level deeper.
                        g.nextLevel();
                        g.events.stairs = true;
                        g.message = if (g.in_shop)
                            "You found a shop! Walk over an item to buy it."
                        else if (g.in_fountain)
                            "You found a fountain! Drink from it, or make an offering (+)."
                        else
                            "You go down the stairs...";
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
        if (g.vision_fresh) {
            g.vision_fresh = false; // the round it was drunk in is free
        } else if (g.vision > 0) {
            g.vision -= 1;
        }
        // Invisibility: read before the tick, so its last round still hides.
        const hidden = g.invisible > 0;
        tickCurse(&g.invisible, &g.invisible_fresh);
        // Slowness: the monsters get a second turn in every slow round.
        const slow = g.slow > 0 and !g.slow_fresh;
        tickCurse(&g.slow, &g.slow_fresh);
        tickCurse(&g.blind, &g.blind_fresh);
        tickCurse(&g.confused, &g.confused_fresh);
        if (!frozen) {
            g.monstersTurn(hidden);
            if (slow and g.state == .playing) g.monstersTurn(hidden);
        }
    }

    /// One round of a counter with a fresh flag (the drink round is free):
    /// curses and invisibility.
    fn tickCurse(counter: *u8, fresh: *bool) void {
        if (fresh.*) {
            fresh.* = false;
        } else if (counter.* > 0) {
            counter.* -= 1;
        }
    }

    /// Damage the hero's attack deals, including any strength bonus.
    pub fn attackDamage(g: *const Game) i32 {
        return hero_damage + g.strength_bonus;
    }

    /// True while the monsters are frozen by a time stop potion.
    pub fn timeStopped(g: *const Game) bool {
        return g.time_stop > 0;
    }

    /// True when a hit would be a sneak attack: the hero is invisible or
    /// time is stopped (a user rule).
    pub fn isSneaky(g: *const Game) bool {
        return g.invisible > 0 or g.timeStopped();
    }

    /// True while the hero sees the whole map (vision potion).
    pub fn hasVision(g: *const Game) bool {
        return g.vision > 0;
    }

    /// The stairs show through the field of view once the level is cleared.
    pub fn stairsRevealed(g: *const Game) bool {
        return g.monster_count == 0;
    }

    /// True while the hero is fast (speed potion).
    pub fn isFast(g: *const Game) bool {
        return g.speed > 0;
    }

    /// Drinks a potion the hero carries. Returns false (and uses no turn)
    /// when it is a health potion and the hero is already at full health.
    fn drink(g: *Game, kind: Potion) bool {
        if (kind.heal() > 0 and g.hp >= g.max_hp) {
            g.message = "You are already at full health.";
            return false;
        }
        g.inventory.remove(kind);
        if (kind == .mystery) g.drinkMystery() else g.applyPotion(kind);
        return true;
    }

    /// A mystery potion: a random chest potion or a random curse, 50/50.
    /// render() appends what it was: "(it was a <label>)" or "(it was a curse)".
    fn drinkMystery(g: *Game) void {
        if (g.rng.uintLessThan(u8, 100) < mystery_good_chance) {
            var p = g.randomPotion();
            while (p == .mystery) p = g.randomPotion();
            g.mystery_potion = p;
            g.applyPotion(p);
        } else {
            const c = g.randomCurse();
            g.mystery_curse = c;
            g.events.curse = true;
            g.applyCurse(c);
        }
    }

    /// One of the curses, each just as likely (mystery potions and totems).
    fn randomCurse(g: *Game) Curse {
        const curses = std.enums.values(Curse);
        return curses[g.rng.uintLessThan(usize, curses.len)];
    }

    /// The effect of a potion (already taken out of the inventory).
    fn applyPotion(g: *Game, kind: Potion) void {
        switch (kind) {
            .time_stop => {
                g.time_stop = time_stop_turns; // drinking again resets, never adds
                g.time_stop_fresh = true;
                g.events.time_stop = true;
                g.message = "Time stops! The monsters are frozen.";
            },
            .speed => {
                g.speed = speed_turns; // drinking again resets, never adds
                g.events.speed = true;
                g.message = "You feel fast!";
            },
            .vision => {
                g.vision = vision_turns; // drinking again resets, never adds
                g.vision_fresh = true;
                g.events.vision = true;
                g.message = "Your eyes glow! You see the whole map.";
            },
            .invisibility => {
                g.invisible = invisible_turns; // drinking again resets, never adds
                g.invisible_fresh = true;
                g.events.invisible = true;
                g.message = "You fade from sight! The monsters lose track of you.";
            },
            .strength_small, .strength_medium, .strength_large => {
                g.strength_bonus += kind.strength(); // bonuses add up
                g.strength = strength_turns; // the counter resets, never adds
                g.strength_fresh = true;
                g.events.strength = true;
                g.message = switch (kind) {
                    .strength_small => "You feel stronger! (+1 damage)",
                    .strength_medium => "You feel stronger! (+2 damage)",
                    else => "You feel stronger! (+3 damage)",
                };
            },
            .small, .medium, .large => {
                g.heal(kind.heal());
                g.events.drink = true;
                // render() appends the HP restored: "(+N HP)".
                g.message = switch (kind) {
                    .small => "You drink a small health potion.",
                    .medium => "You drink a medium health potion.",
                    else => "You drink a large health potion.",
                };
            },
            .mystery => unreachable, // drinkMystery never applies a mystery
        }
    }

    /// The effect of a bad mystery potion.
    fn applyCurse(g: *Game, c: Curse) void {
        switch (c) {
            .slow => {
                g.slow = slow_turns; // resets, never adds
                g.slow_fresh = true;
                g.message = "You feel slow... The monsters move twice as fast.";
            },
            .paralysis => {
                g.paralyzed = true;
                g.message = "You can't move! You lose your next action.";
            },
            .burn => {
                // Never kills: the hero keeps at least 1 HP.
                const loss = @min(curse_damage, g.hp - 1);
                g.hp -= loss;
                g.damage_taken += loss;
                g.message = "It burns!";
            },
            .blind => {
                g.blind = blind_turns;
                g.blind_fresh = true;
                g.message = "Your sight grows dim.";
            },
            .confused => {
                g.confused = confused_turns;
                g.confused_fresh = true;
                g.message = "You feel dizzy. Your moves are reversed!";
            },
        }
    }

    /// True while a curse from a mystery potion is active (the hero is red).
    pub fn isCursed(g: *const Game) bool {
        return g.slow > 0 or g.paralyzed or g.blind > 0 or g.confused > 0;
    }

    /// Every monster acts once. While the hero is `hidden` (invisible), no
    /// monster knows where the hero is: they only wander, even next to
    /// the hero, so a chase stops and nobody bites.
    fn monstersTurn(g: *Game, hidden: bool) void {
        for (g.monsters[0..g.monster_count]) |*m| {
            g.monsterAct(m, hidden);
            if (g.state != .playing) return;
        }
    }

    /// One action of one monster: bite when next to the hero, chase
    /// within its sight, otherwise wander now and then.
    fn monsterAct(g: *Game, m: *Monster, hidden: bool) void {
        const dist = m.pos.manhattan(g.hero);
        if (hidden) {
            if (g.rng.uintLessThan(u8, 100) < wander_chance) g.wander(m);
        } else if (dist == 1) {
            const dmg = m.kind.damage();
            g.hp -= dmg;
            g.damage_taken += dmg;
            m.bit = true;
            g.message = m.kind.biteMessage();
            if (g.hp <= 0) {
                g.hp = 0;
                g.state = .lost;
                g.events.lost = true;
                g.message = "You died. GAME OVER.";
            }
        } else if (dist <= m.kind.sight()) {
            g.moveMonsterToward(m, g.hero);
        } else if (g.rng.uintLessThan(u8, 100) < wander_chance) {
            g.wander(m);
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
        const r: i32 = if (g.blind > 0) blind_radius else view_radius;
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
        // A vision potion lifts the field of view: the whole map is drawn.
        // So does a shop: its room is lit.
        // So does a fountain level.
        const seen: ?[H][W]bool = if (opts.fov and !g.hasVision() and !g.inRoom()) g.visibility() else null;
        try g.writeHeader(w);
        for (0..H) |y| {
            try w.splatByteAll(' ', opts.shake);
            if (opts.flash) try w.writeAll(ansi_red_bg);
            for (0..W) |x| {
                const p: Pos = .{ .x = @intCast(x), .y = @intCast(y) };
                // Color to wrap this cell with, if any.
                var color: ?[]const u8 = null;
                // Once every monster is defeated, the stairs show from anywhere.
                const visible = if (seen) |s|
                    s[y][x] or (g.map[y][x] == .stairs and g.stairsRevealed())
                else
                    true;
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
                    // Red while cursed by a mystery potion, like when hurt.
                    // Gray while invisible.
                    color = if (hurt or g.isCursed())
                        ansi_red
                    else if (g.invisible > 0)
                        ansi_invisible
                    else if (g.isFast())
                        ansi_fast
                    else
                        ansi_cyan;
                    break :blk '@';
                } else if (g.isShopkeeper(p)) blk: {
                    color = ansi_shopkeeper;
                    break :blk '@';
                } else if (g.shopItemAt(p)) |i| blk: {
                    color = g.shop_items[i].?.color();
                    break :blk '!';
                } else if (g.monsterAt(p)) |i| blk: {
                    color = if (g.timeStopped())
                        ansi_blue
                    else if (g.monsters[i].bit)
                        ansi_bite
                    else
                        ansi_red;
                    break :blk g.monsters[i].kind.symbol();
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
                    .fountain => blk: {
                        color = if (g.fountain_used) ansi_dim else ansi_blue;
                        break :blk '~';
                    },
                    .offering => blk: {
                        color = ansi_yellow;
                        break :blk '+';
                    },
                    .totem => blk: {
                        color = ansi_purple;
                        break :blk 'Y';
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
        if (g.in_shop) try g.writeForSale(w);
        try w.print("\n{s}", .{g.message});
        if (g.sneak_damage > 0) {
            if (opts.color) try w.writeAll(ansi_yellow);
            try w.print(" (sneak attack: {d} damage)", .{g.sneak_damage});
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.shop_bought) |p| {
            if (opts.color) try w.writeAll(ansi_green);
            try w.print(" ({s}, -{d} gold)", .{ p.label(), p.price() });
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.mystery_potion) |p| {
            if (opts.color) try w.writeAll(ansi_green);
            try w.print(" (it was a {s})", .{p.label()});
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.mystery_curse != null) {
            if (opts.color) try w.writeAll(ansi_red);
            try w.writeAll(" (it was a curse)");
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.shop_refused) |p| {
            try w.print(" (the {s} costs {d} gold, you have {d})", .{ p.label(), p.price(), g.inventory.gold });
        }
        if (g.offering_made) {
            if (opts.color) try w.writeAll(ansi_green);
            try w.print(" (+{d} max HP, -{d} gold)", .{ offering_max_hp, offering_price });
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.offering_refused) {
            try w.print(" (the offering costs {d} gold, you have {d})", .{ offering_price, g.inventory.gold });
        }
        if (g.revealed) try w.writeAll(" (you are visible again)");
        if (g.totem_curse != null) {
            if (opts.color) try w.writeAll(ansi_red);
            try w.writeAll(" (a totem curse)");
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.events.chest) {
            if (opts.color) try w.writeAll(ansi_green);
            if (g.chest_potion) |p| {
                try w.print(" ({s})", .{p.label()});
            } else {
                try w.print(" (+{d} gold)", .{g.chest_gold});
            }
            if (opts.color) try w.writeAll(ansi_reset);
        }
        if (g.reward_chests > 0) try g.writeReward(w, opts.color);
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
            try w.writeAll("[w/a/s/d] move  [.] wait  [i] inventory  [q] quit\n");
        }
    }

    /// The clear reward after the kill message, e.g.
    /// " (reward: 2 chests: speed, small potion x2, +30 gold)".
    fn writeReward(g: *const Game, w: *std.Io.Writer, color: bool) std.Io.Writer.Error!void {
        if (color) try w.writeAll(ansi_green);
        try w.print(" (reward: {d} chest{s}:", .{ g.reward_chests, if (g.reward_chests == 1) "" else "s" });
        var first = true;
        for (std.enums.values(Potion)) |p| {
            const n = g.reward_potions[p.index()];
            if (n == 0) continue;
            try w.print("{s} {s}", .{ if (first) "" else ",", p.label() });
            if (n > 1) try w.print(" x{d}", .{n});
            first = false;
        }
        if (g.reward_gold > 0) try w.print("{s} +{d} gold", .{ if (first) "" else ",", g.reward_gold });
        try w.writeByte(')');
        if (color) try w.writeAll(ansi_reset);
    }

    /// The shop's line under the map: what is left and the prices.
    fn writeForSale(g: *const Game, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll("\nFor sale:");
        var any = false;
        for (g.shop_items) |item| {
            const p = item orelse continue;
            try w.print("{s} {s} {d} gold", .{ if (any) "," else "", p.label(), p.price() });
            any = true;
        }
        if (!any) try w.writeAll(" sold out");
        try w.writeByte('\n');
    }

    /// Status line shared by the map and the inventory screen.
    fn writeHeader(g: *const Game, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("DUNGEON  Level {d}{s}   HP {d}/{d}   Gold {d}", .{
            g.level,
            if (g.in_shop) " (SHOP)" else if (g.in_fountain) " (FOUNTAIN)" else "",
            g.hp,
            g.max_hp,
            g.inventory.gold,
        });
        if (g.time_stop > 0) try w.print("   TIME STOP {d}", .{g.time_stop});
        if (g.speed > 0) try w.print("   SPEED {d}", .{g.speed});
        if (g.strength > 0) try w.print("   STRENGTH +{d} ({d})", .{ g.strength_bonus, g.strength });
        if (g.vision > 0) try w.print("   VISION {d}", .{g.vision});
        if (g.invisible > 0) try w.print("   INVISIBLE {d}", .{g.invisible});
        if (g.slow > 0) try w.print("   SLOW {d}", .{g.slow});
        if (g.blind > 0) try w.print("   BLIND {d}", .{g.blind});
        if (g.confused > 0) try w.print("   CONFUSED {d}", .{g.confused});
        if (g.paralyzed) try w.writeAll("   PARALYZED");
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
                .vision => "Vision potion        (3 turns)",
                .invisibility => "Invisibility potion  (5 turns)",
                .mystery => "???",
            };
            if (color) {
                try w.print("  {d}) {s}{s}{s} ..... x", .{ number, p.color(), label, ansi_reset });
            } else {
                try w.print("  {d}) {s} ..... x", .{ number, label });
            }
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
        try w.writeAll("[other key] close\n");
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

// ---------------------------------------------------------- panic button

/// The panic key: on any screen it hides the game behind `renderDisguise`,
/// and only this key brings the game back.
pub const panic_key = ' ';

/// The fake prompt of the disguise: a made-up user and project.
const disguise_prompt = "PS C:\\Users\\dev\\projects\\gestao-qualidade> ";

/// Draws the panic screen: a PowerShell window that just ran a Python test
/// suite with `python -m pytest -v`. Plain text (no colors) and nothing
/// from the game. Ends on the prompt with no newline, so the cursor sits
/// after it.
pub fn renderDisguise(w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeAll(disguise_prompt ++ "git pull\n" ++
        \\Already up to date.
        \\
    ++ disguise_prompt ++ "python -m pytest -v\n" ++
        \\============================= test session starts ==============================
        \\platform win32 -- Python 3.12.4, pytest-8.3.2, pluggy-1.5.0 -- C:\Users\dev\projects\gestao-qualidade\.venv\Scripts\python.exe
        \\cachedir: .pytest_cache
        \\rootdir: C:\Users\dev\projects\gestao-qualidade
        \\configfile: pyproject.toml
        \\collected 18 items
        \\
        \\tests/test_inspecao.py::test_cria_inspecao_com_lote_valido PASSED         [  5%]
        \\tests/test_inspecao.py::test_rejeita_lote_sem_numero PASSED               [ 11%]
        \\tests/test_inspecao.py::test_inspecao_aprovada_fecha_lote PASSED          [ 16%]
        \\tests/test_inspecao.py::test_inspecao_reprovada_abre_nc PASSED            [ 22%]
        \\tests/test_nao_conformidade.py::test_nc_exige_causa_raiz PASSED           [ 27%]
        \\tests/test_nao_conformidade.py::test_nc_com_acao_corretiva_encerra PASSED [ 33%]
        \\tests/test_nao_conformidade.py::test_nc_vencida_aparece_no_painel PASSED  [ 38%]
        \\tests/test_nao_conformidade.py::test_prazo_padrao_e_trinta_dias PASSED    [ 44%]
        \\tests/test_plano_amostragem.py::test_tamanho_amostra_nivel_ii PASSED      [ 50%]
        \\tests/test_plano_amostragem.py::test_criterio_aceitacao_por_aql PASSED    [ 55%]
        \\tests/test_plano_amostragem.py::test_amostra_minima_lote_pequeno PASSED   [ 61%]
        \\tests/test_relatorios.py::test_indice_de_rejeicao_por_fornecedor PASSED   [ 66%]
        \\tests/test_relatorios.py::test_exporta_relatorio_csv PASSED               [ 72%]
        \\tests/test_relatorios.py::test_relatorio_vazio_sem_inspecoes PASSED       [ 77%]
        \\tests/test_calibracao.py::test_instrumento_vencido_bloqueia PASSED        [ 83%]
        \\tests/test_calibracao.py::test_proxima_calibracao_no_intervalo PASSED     [ 88%]
        \\tests/test_calibracao.py::test_certificado_obrigatorio PASSED             [ 94%]
        \\tests/test_calibracao.py::test_historico_de_calibracoes PASSED            [100%]
        \\
        \\============================== 18 passed in 1.37s ==============================
        \\
    ++ disguise_prompt);
}

// ---------------------------------------------------------- title screen

pub const TitleChoice = enum { play, quit };

/// The result of the last run, shown on the title screen.
pub const LastRun = struct { level: u32, gold: u32 };

/// The game's name, shown in a wall frame as wide as the map.
const title_name = "B R E W D U N G E O N";

/// The title screen's menu: Play or Quit.
pub const Title = struct {
    selected: TitleChoice = .play,

    /// Handles one key. Returns the confirmed choice, if any: Enter confirms
    /// the selected option, `p` and `q` pick one directly, `w`/`s` move
    /// (the up and down arrows arrive as `w`/`s`, see `readKey`).
    pub fn key(t: *Title, k: u8) ?TitleChoice {
        switch (std.ascii.toLower(k)) {
            'w' => t.selected = .play,
            's' => t.selected = .quit,
            '\r' => return t.selected,
            'p' => return .play,
            'q' => return .quit,
            else => {},
        }
        return null;
    }

    /// Draws the title screen to any Writer.
    /// Every line fits the game's width: the map's `W` columns plus the
    /// 1-column indent the map rows have.
    pub fn render(t: *const Title, w: *std.Io.Writer, color: bool, last: ?LastRun) std.Io.Writer.Error!void {
        const wall: [W]u8 = @splat('#');
        try w.print("\n {s}\n", .{&wall});
        try frameLine(w, "", color);
        try frameLine(w, title_name, color);
        try frameLine(w, "", color);
        try w.print(" {s}\n", .{&wall});
        try w.writeAll("\n");
        for (std.enums.values(TitleChoice)) |choice| {
            const name = switch (choice) {
                .play => "Play",
                .quit => "Quit",
            };
            if (choice == t.selected) {
                if (color) {
                    try w.print("           {s}> {s}{s}\n", .{ ansi_cyan, name, ansi_reset });
                } else {
                    try w.print("           > {s}\n", .{name});
                }
            } else {
                try w.print("             {s}\n", .{name});
            }
        }
        if (last) |run| {
            try w.print("\n   Last run: level {d}, {d} gold\n", .{ run.level, run.gold });
        }
        try w.writeAll("\n   [w/s] select  [Enter] confirm\n");
    }

    /// One line inside the frame: `#`, the text centered (yellow), `#`.
    fn frameLine(w: *std.Io.Writer, text: []const u8, color: bool) std.Io.Writer.Error!void {
        const inner = W - 2;
        const left = (inner - text.len) / 2;
        try w.writeAll(" #");
        try w.splatByteAll(' ', left);
        if (color and text.len > 0) {
            try w.print("{s}{s}{s}", .{ ansi_yellow, text, ansi_reset });
        } else {
            try w.writeAll(text);
        }
        try w.splatByteAll(' ', inner - left - text.len);
        try w.writeAll("#\n");
    }
};

// ---------------------------------------------------------------- tests

const testing = std.testing;

test "the title starts on Play and w/s move the cursor" {
    var t: Title = .{};
    try testing.expectEqual(TitleChoice.play, t.selected);
    try testing.expectEqual(@as(?TitleChoice, null), t.key('s'));
    try testing.expectEqual(TitleChoice.quit, t.selected);
    _ = t.key('s'); // already at the bottom
    try testing.expectEqual(TitleChoice.quit, t.selected);
    _ = t.key('W');
    try testing.expectEqual(TitleChoice.play, t.selected);
}

test "Enter confirms the selected option" {
    var t: Title = .{};
    try testing.expectEqual(@as(?TitleChoice, .play), t.key('\r'));
    _ = t.key('s');
    try testing.expectEqual(@as(?TitleChoice, .quit), t.key('\r'));
}

test "p and q pick Play and Quit directly" {
    var t: Title = .{};
    try testing.expectEqual(@as(?TitleChoice, .quit), t.key('q'));
    _ = t.key('s');
    try testing.expectEqual(@as(?TitleChoice, .play), t.key('P'));
}

test "other keys do nothing on the title" {
    var t: Title = .{};
    for ("adx1 .\t") |k| try testing.expectEqual(@as(?TitleChoice, null), t.key(k));
    try testing.expectEqual(TitleChoice.play, t.selected);
}

test "the title screen shows the name, the menu and the last run" {
    var buf: [4096]u8 = undefined;
    var t: Title = .{};
    var w: std.Io.Writer = .fixed(&buf);
    try t.render(&w, false, null);
    var out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "#    " ++ title_name ++ "    #") != null);
    try testing.expect(std.mem.indexOf(u8, out, "> Play\n             Quit\n") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Last run") == null);
    // It fits the game's width: the map's W columns plus the indent.
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |line| try testing.expect(line.len <= W + 1);
    _ = t.key('s');
    w = .fixed(&buf);
    try t.render(&w, true, .{ .level = 7, .gold = 120 });
    out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "Play\n           " ++ ansi_cyan ++ "> Quit") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Last run: level 7, 120 gold") != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_yellow ++ title_name ++ ansi_reset) != null);
}

fn testGame(prng: *std.Random.DefaultPrng, layout: Layout) Game {
    var g: Game = .{ .rng = prng.random() };
    g.loadLayout(layout);
    return g;
}

// Small test layout: hero in the middle, wall to the left,
// gold above, monster to the right and stairs below.
const test_layout: Layout = &.{
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

/// Reads every key from `bytes` with `readKey` until the end of the input.
fn readAllKeys(bytes: []const u8, out: []u8) ![]const u8 {
    var in: std.Io.Reader = .fixed(bytes);
    var n: usize = 0;
    while (try readKey(&in)) |k| : (n += 1) out[n] = k;
    return out[0..n];
}

test "readKey turns arrow keys into w a s d" {
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("wsda", try readAllKeys("\x1b[A\x1b[B\x1b[C\x1b[D", &buf));
    try testing.expectEqualStrings("wsda", try readAllKeys("\x1bOA\x1bOB\x1bOC\x1bOD", &buf));
}

test "readKey skips other escape sequences" {
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("d", try readAllKeys("\x1b[1;5A\x1b[2~d", &buf));
}

test "readKey keeps plain keys and skips newlines" {
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("wq\r", try readAllKeys("w\nq\r", &buf));
}

test "readKey drops a lone escape" {
    var buf: [16]u8 = undefined;
    try testing.expectEqualStrings("q", try readAllKeys("\x1bq", &buf));
    try testing.expectEqualStrings("", try readAllKeys("\x1b", &buf));
    try testing.expectEqualStrings("", try readAllKeys("\x1b[", &buf));
}

test "arrow keys move the cursor on the title screen" {
    var buf: [16]u8 = undefined;
    var t: Title = .{};
    for (try readAllKeys("\x1b[B", &buf)) |k| try testing.expectEqual(@as(?TitleChoice, null), t.key(k));
    try testing.expectEqual(TitleChoice.quit, t.selected);
    for (try readAllKeys("\x1b[A", &buf)) |k| _ = t.key(k);
    try testing.expectEqual(TitleChoice.play, t.selected);
}

test "the disguise looks like pytest running in PowerShell" {
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try renderDisguise(&w);
    const out = w.buffered();
    try testing.expect(std.mem.indexOf(u8, out, "gestao-qualidade> python -m pytest -v\n") != null);
    try testing.expect(std.mem.indexOf(u8, out, "test session starts") != null);
    try testing.expect(std.mem.indexOf(u8, out, " 18 passed in ") != null);
    try testing.expectEqual(@as(usize, 18), std.mem.count(u8, out, " PASSED "));
    try testing.expect(std.mem.startsWith(u8, out, "PS C:\\Users\\dev\\projects\\gestao-qualidade> "));
    try testing.expect(std.mem.endsWith(u8, out, "\nPS C:\\Users\\dev\\projects\\gestao-qualidade> "));
}

test "the disguise shows nothing from the game" {
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try renderDisguise(&w);
    const out = w.buffered();
    for ([_][]const u8{ "DUNGEON", "HP", "@", "Gold", "gold", "Level", "#####" }) |word| {
        try testing.expect(std.mem.indexOf(u8, out, word) == null);
    }
    for (out) |c| try testing.expect(c == '\n' or (c >= ' ' and c <= '~'));
}

test "space is the panic key, not a game command" {
    try testing.expectEqual(@as(u8, ' '), panic_key);
    try testing.expectEqual(@as(?Command, null), parseCommand(&.{panic_key}));
    var t: Title = .{ .selected = .quit };
    try testing.expectEqual(@as(?TitleChoice, null), t.key(panic_key));
    try testing.expectEqual(TitleChoice.quit, t.selected);
}

test "a single key acts at once, so the screens never ask for Enter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    // Each key is one command on its own, with no line ending.
    for ("wasd.qi19") |key| try testing.expect(parseCommand(&.{key}) != null);

    var buf: [4096]u8 = undefined;
    const map = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, map, "Enter") == null);
    try testing.expect(std.mem.indexOf(u8, map, "[q] quit\n") != null);

    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "Enter") == null);
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
    try testing.expectEqual(@as(i32, start_max_hp - monster_damage), g.hp);
}

test "nearby monster chases the hero" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, &.{
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
const pocket_layout: Layout = &.{
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
    var g = testGame(&prng, &.{
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
    try testing.expectEqual(@as(u32, 2), g.level);
    try testing.expectEqual(@as(u32, 30), g.inventory.gold);
    try testing.expectEqual(@as(i32, 7), g.hp);
    try testing.expectEqual(State.playing, g.state);
}

test "the stairs always lead one level deeper" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.level = 3; // the old last level
    g.step(.down);
    try testing.expectEqual(@as(u32, 4), g.level);
    try testing.expectEqual(State.playing, g.state);
    try testing.expect(g.events.stairs);
    g.loadLevel(99);
    try testing.expectEqual(@as(usize, max_monsters), g.monster_count);
}

test "monsters gain 1 HP every 3 levels" {
    try testing.expectEqual(@as(i32, 3), Game.monsterHp(1));
    try testing.expectEqual(@as(i32, 3), Game.monsterHp(3));
    try testing.expectEqual(@as(i32, 4), Game.monsterHp(4));
    try testing.expectEqual(@as(i32, 4), Game.monsterHp(6));
    try testing.expectEqual(@as(i32, 5), Game.monsterHp(7));
    var prng = std.Random.DefaultPrng.init(1);
    var g = Game.init(prng.random());
    for (g.monsters[0..g.monster_count]) |m| try testing.expectEqual(@as(i32, 3), m.hp);
    g.loadLevel(4);
    for (g.monsters[0..g.monster_count]) |m| try testing.expectEqual(@as(i32, 4), m.hp);
}

test "the header shows the level with no last level" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.level = 12;
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "Level 12   HP") != null);
}

test "opening the inventory does not use a turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.message = "before";
    const monster_before = g.monsters[0].pos;
    g.step(.inventory);
    try testing.expectEqual(@as(i32, start_max_hp), g.hp); // the adjacent monster did not bite
    try testing.expectEqual(monster_before, g.monsters[0].pos);
    try testing.expectEqualStrings("before", g.message);
    try testing.expectEqual(Events{}, g.events);
    try testing.expectEqual(State.playing, g.state);
    // A real turn does let the monster bite.
    g.step(.wait);
    try testing.expectEqual(@as(i32, start_max_hp - monster_damage), g.hp);
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
    try testing.expect(std.mem.indexOf(u8, plain, "[other key] close") != null);
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
    try testing.expectEqual([Potion.count]usize{ 50, 35, 15, 0, 0, 0, 0, 0, 0, 0, 0 }, counts);
    try testing.expectEqual(@as(i32, 1), Potion.small.heal());
    try testing.expectEqual(@as(i32, 3), Potion.medium.heal());
    try testing.expectEqual(@as(i32, 5), Potion.large.heal());
    try testing.expectEqual(@as(i32, 0), Potion.time_stop.heal());
}

test "strength potions add 1, 2 and 3 damage and use the same size split" {
    var counts: [Potion.count]usize = @splat(0);
    for (0..100) |r| counts[Potion.strengthFromRoll(@intCast(r)).index()] += 1;
    try testing.expectEqual([Potion.count]usize{ 0, 0, 0, 0, 0, 50, 35, 15, 0, 0, 0 }, counts);
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
    try testing.expectEqual(@as(i32, start_max_hp), g.hp);
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

test "chest potions: about 10% time stop, 15% speed, 15% strength, 10% vision, 10% invisibility, 10% mystery and 30% health" {
    var potions: usize = 0;
    var time_stops: usize = 0;
    var speeds: usize = 0;
    var strengths: usize = 0;
    var visions: usize = 0;
    var invisibles: usize = 0;
    var mysteries: usize = 0;
    var healths: usize = 0;
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
            .vision => visions += 1,
            .invisibility => invisibles += 1,
            .mystery => mysteries += 1,
            .small, .medium, .large => healths += 1,
        }
    }
    try testing.expect(time_stops >= 100 and time_stops <= 300); // 5%..15%
    try testing.expect(speeds >= 200 and speeds <= 400); // 10%..20%
    try testing.expect(strengths >= 200 and strengths <= 400); // 10%..20%
    try testing.expect(visions >= 100 and visions <= 300); // 5%..15%
    try testing.expect(mysteries >= 100 and mysteries <= 300); // 5%..15%
    try testing.expect(invisibles >= 100 and invisibles <= 300); // 5%..15%
    try testing.expect(healths >= 500 and healths <= 700); // 25%..35%
}

test "vision works at full health and shows its counter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.vision);
    g.step(.use_1);
    try testing.expect(g.events.vision);
    try testing.expectEqual(@as(u8, vision_turns), g.vision);
    try testing.expect(g.hasVision());
    try testing.expectEqual(@as(u32, 0), g.inventory.potionCount(.vision));
    try testing.expectEqual(@as(usize, 0), g.inventory.items().len);
    var buf: [8192]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "VISION 3") != null);
}

test "vision shows the whole map for the drink round plus 3, then fov comes back" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, &.{
        "##############################",
        "#@.......................$>..#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#............................#",
        "#...........................M#", // not cleared: the stairs can hide
        "##############################",
    });
    const gold: Pos = .{ .x = 25, .y = 1 };
    const stairs: Pos = .{ .x = 26, .y = 1 };
    var buf: [8192]u8 = undefined;
    // Far away: hidden by the field of view.
    var out = try renderToBuf(&g, &buf, .{ .fov = true });
    try testing.expectEqual(@as(u8, '.'), cellAt(out, stairs, 1));

    g.inventory.add(.vision);
    g.step(.use_1); // the drink round is free
    for (0..vision_turns) |_| {
        out = try renderToBuf(&g, &buf, .{ .fov = true });
        try testing.expectEqual(@as(u8, '$'), cellAt(out, gold, 1));
        try testing.expectEqual(@as(u8, '>'), cellAt(out, stairs, 1));
        g.step(.wait);
    }
    try testing.expectEqual(@as(u8, 0), g.vision);
    out = try renderToBuf(&g, &buf, .{ .fov = true });
    try testing.expectEqual(@as(u8, '.'), cellAt(out, gold, 1));
    try testing.expectEqual(@as(u8, '.'), cellAt(out, stairs, 1));
    try testing.expect(std.mem.indexOf(u8, out, "VISION") == null);
}

test "drinking vision again resets the counter to 3, never adds" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.vision);
    g.inventory.add(.vision);
    g.step(.use_1);
    g.step(.wait); // 3 -> 2
    try testing.expectEqual(@as(u8, 2), g.vision);
    g.step(.use_1);
    try testing.expectEqual(@as(u8, vision_turns), g.vision);
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
    try testing.expectEqual(@as(i32, start_max_hp), g.hp);
    var buf: [8192]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "SPEED 10") != null);
}

test "speed gives 2 actions per round for 10 rounds (20 actions)" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout); // a monster is next to the hero
    g.inventory.add(.speed);
    g.step(.use_1); // action 1: the first half of a round, nobody bites
    try testing.expectEqual(@as(i32, start_max_hp), g.hp);

    var bites: i32 = 0;
    for (2..21) |action| { // actions 2..20
        g.hp = start_max_hp - 1; // keep the hero alive and comparable
        g.step(.wait);
        const bitten = g.hp < start_max_hp - 1;
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
    try testing.expectEqual(@as(i32, start_max_hp), g.hp);
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
    g.monsters[0].hp = 10; // survives the sneak attack
    g.step(.use_1);
    g.step(.right); // attack the adjacent monster: a sneak attack (x2)
    try testing.expectEqual(@as(i32, 10 - hero_damage * sneak_multiplier), g.monsters[0].hp);
    try testing.expectEqual(@as(i32, start_max_hp), g.hp);
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
const chest_layout: Layout = &.{
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
    try testing.expectEqual(@as(i32, 2), g.healed); // capped at start_max_hp
    try testing.expectEqual(@as(i32, start_max_hp - monster_damage), g.hp);

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
    try testing.expectEqual(@as(i32, start_max_hp), g.hp);
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
    // A single solid border: the maze reaches the row and the column next
    // to it, so no line of the map is wasted.
    var floor_last_row = false;
    var floor_last_col = false;
    for (0..W) |x| {
        try testing.expectEqual(Tile.wall, g.map[0][x]);
        try testing.expectEqual(Tile.wall, g.map[H - 1][x]);
        if (g.map[H - 2][x] != .wall) floor_last_row = true;
    }
    for (0..H) |y| {
        try testing.expectEqual(Tile.wall, g.map[y][0]);
        try testing.expectEqual(Tile.wall, g.map[y][W - 1]);
        if (g.map[y][W - 2] != .wall) floor_last_col = true;
    }
    try testing.expect(floor_last_row and floor_last_col);

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
        .gold, .chest, .totem => loot += 1,
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
        for (1..13) |n| {
            if (n > 1) g.loadLevel(@intCast(n));
            try testing.expectEqual(@min(max_monsters, 1 + n * 2), g.monster_count);
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
        for (1..4) |n| {
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
    var g = testGame(&prng, &.{
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
const fov_layout: Layout = &.{
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
    var g = testGame(&prng, &.{
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

test "the stairs show through the fov once every monster is defeated" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, &.{
        "##############################",
        "#@M.......................$>.#",
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
    const before = try renderToBuf(&g, &buf, .{ .fov = true });
    try testing.expectEqual(@as(u8, '.'), cellAt(before, .{ .x = 27, .y = 1 }, 1));
    g.monsters[0].hp = 1; // one hit kills it
    g.step(.right);
    try testing.expectEqual(@as(usize, 0), g.monster_count);
    const after = try renderToBuf(&g, &buf, .{ .fov = true });
    try testing.expectEqual(@as(u8, '>'), cellAt(after, .{ .x = 27, .y = 1 }, 1));
    // Only the stairs: far gold stays hidden.
    try testing.expectEqual(@as(u8, '.'), cellAt(after, .{ .x = 26, .y = 1 }, 1));
}

test "killing the last monster says the stairs are revealed" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, &.{
        "##############################",
        "#.M.........................>#",
        "#@...........................#",
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
    // Add a far one by hand: it cannot bite yet.
    g.addMonster(.{ .x = 28, .y = 10 }, .monster);
    for (g.monsters[0..g.monster_count]) |*m| m.hp = 1;
    g.hero = .{ .x = 2, .y = 2 };
    g.step(.up);
    try testing.expectEqualStrings("You defeated a monster!", g.message);
    // Bring the other one next to the hero and kill it too.
    g.monsters[0].pos = g.hero.add(.{ .x = 0, .y = 1 });
    g.step(.down);
    try testing.expectEqualStrings("You defeated the last monster! The stairs are revealed.", g.message);
}

// One monster next to the hero, for the clear reward tests.
const reward_layout: Layout = &.{
    "##############################",
    "#@M.........................>#",
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

/// Sum of the potions in the clear reward.
fn rewardPotionCount(g: *const Game) u32 {
    var n: u32 = 0;
    for (g.reward_potions) |c| n += c;
    return n;
}

/// Sum of all the potions in the inventory.
fn inventoryPotionCount(g: *const Game) u32 {
    var n: u32 = 0;
    for (g.inventory.potions) |c| n += c;
    return n;
}

test "the clear reward grows by one chest every 3 levels" {
    const expected = [_]u32{ 1, 1, 1, 2, 2, 2, 3, 3, 3, 4 };
    for (expected, 1..) |e, level| try testing.expectEqual(e, rewardChests(@intCast(level)));
}

test "killing the last monster gives a chest reward straight to the inventory" {
    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, reward_layout);
        g.monsters[0].hp = 1;
        g.inventory.gold = 5;
        g.step(.right);
        try testing.expectEqual(@as(usize, 0), g.monster_count);
        try testing.expect(g.events.reward);
        try testing.expectEqual(@as(u32, 1), g.reward_chests);
        // One chest roll: a potion or 20-50 gold, never both.
        const potions = rewardPotionCount(&g);
        if (potions == 1) {
            try testing.expectEqual(@as(u32, 0), g.reward_gold);
        } else {
            try testing.expectEqual(@as(u32, 0), potions);
            try testing.expect(g.reward_gold >= chest_gold_min and g.reward_gold <= chest_gold_max);
        }
        // Straight to the inventory.
        try testing.expectEqual(potions, inventoryPotionCount(&g));
        try testing.expectEqual(5 + g.reward_gold, g.inventory.gold);
        for (std.enums.values(Potion)) |p| {
            try testing.expectEqual(g.reward_potions[p.index()], g.inventory.potionCount(p));
        }
        // Not a chest tile: no chest message state.
        try testing.expect(!g.events.chest);
    }
}

test "the clear reward rolls one chest per monster HP tier" {
    var prng = std.Random.DefaultPrng.init(3);
    var g = testGame(&prng, reward_layout);
    g.level = 7; // monsters have 5 HP: 3 chest rolls
    g.monsters[0].hp = 1;
    g.step(.right);
    try testing.expectEqual(@as(u32, 3), g.reward_chests);
    // Each roll is a potion or 20-50 gold.
    const potions = rewardPotionCount(&g);
    try testing.expect(potions <= 3);
    const gold_rolls = 3 - potions;
    try testing.expect(g.reward_gold >= gold_rolls * chest_gold_min and g.reward_gold <= gold_rolls * chest_gold_max);
    try testing.expectEqual(potions, inventoryPotionCount(&g));
    try testing.expectEqual(g.reward_gold, g.inventory.gold);
}

test "killing a monster that is not the last gives no reward" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, reward_layout);
    g.addMonster(.{ .x = 28, .y = 10 }, .monster); // far away
    g.monsters[0].hp = 1;
    g.step(.right);
    try testing.expectEqualStrings("You defeated a monster!", g.message);
    try testing.expect(!g.events.reward);
    try testing.expectEqual(@as(u32, 0), g.reward_chests);
    try testing.expectEqual(@as(u32, 0), inventoryPotionCount(&g));
    try testing.expectEqual(@as(u32, 0), g.inventory.gold);
}

test "the clear reward is shown after the kill message and cleared next turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, reward_layout);
    g.level = 4; // 2 chest rolls
    g.monsters[0].hp = 1;
    g.step(.right);
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "The stairs are revealed. (reward: 2 chests:") != null);
    for (std.enums.values(Potion)) |p| {
        if (g.reward_potions[p.index()] > 0) try testing.expect(std.mem.indexOf(u8, out, p.label()) != null);
    }
    if (g.reward_gold > 0) {
        var expected: [32]u8 = undefined;
        const gold = try std.fmt.bufPrint(&expected, "+{d} gold)", .{g.reward_gold});
        try testing.expect(std.mem.indexOf(u8, out, gold) != null);
    }

    // Next turn, the reward state is cleared.
    g.step(.wait);
    try testing.expectEqual(@as(u32, 0), g.reward_chests);
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "reward") == null);
}

test "the clear reward lists repeated potions with a count" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, reward_layout);
    g.reward_chests = 3;
    g.reward_potions[Potion.speed.index()] = 2;
    g.reward_gold = 30;
    var buf: [4096]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    var expected: [64]u8 = undefined;
    const text = try std.fmt.bufPrint(&expected, "(reward: 3 chests: {s} x2, +30 gold)", .{Potion.speed.label()});
    try testing.expect(std.mem.indexOf(u8, out, text) != null);
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

test "turn events: gold, stairs and lost" {
    var prng = std.Random.DefaultPrng.init(1);

    var g = testGame(&prng, test_layout);
    g.step(.up);
    try testing.expectEqual(Events{ .gold = true }, g.events);

    g = testGame(&prng, test_layout);
    g.step(.down);
    try testing.expectEqual(Events{ .stairs = true }, g.events);

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
    const row = @as([W]u8, @splat('#')) ++ "\n"; // the top wall row
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .shake = 0 }), "\n\n" ++ row) != null);
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .shake = 1 }), "\n\n " ++ row) != null);
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .shake = 2 }), "\n\n  " ++ row) != null);
}

/// Counts how often the stairs of level 2 lead to the event (a shop or a
/// fountain) over 1000 seeds, with the event already called `calls` times.
fn countShops(calls: u32) usize {
    var shops: usize = 0;
    var seed: u64 = 0;
    while (seed < 1000) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, test_layout);
        g.level = 2;
        g.shop_calls = calls;
        g.step(.down); // the stairs
        if (g.inRoom()) shops += 1;
    }
    return shops;
}

test "the shop event shows up 80% the first time and 50% after" {
    const first = countShops(0);
    try testing.expect(first >= 750 and first <= 850);
    const later = countShops(1);
    try testing.expect(later >= 450 and later <= 550);
}

test "after a shop shows up, the next chance is skipped" {
    // Find a game whose level 2 stairs lead to a shop.
    var seed: u64 = 0;
    while (true) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, test_layout);
        g.level = 2;
        g.step(.down);
        if (!g.in_shop) continue;
        try testing.expectEqual(@as(u32, 3), g.level);
        try testing.expectEqual(@as(u32, 1), g.shop_calls);
        g.nextLevel(); // the shop's stairs: level 4, no call
        g.nextLevel(); // level 4's stairs: skipped, no roll
        try testing.expect(!g.in_shop);
        try testing.expectEqual(@as(u32, 5), g.level);
        try testing.expectEqual(@as(u32, 1), g.shop_calls);
        g.nextLevel(); // level 5 is odd: no call
        g.nextLevel(); // level 6's stairs: the event is called again
        try testing.expectEqual(@as(u32, 2), g.shop_calls);
        break;
    }
}

test "the shop event only runs on the stairs of even levels" {
    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = Game.init(prng.random());
        g.nextLevel(); // 1 -> 2
        try testing.expect(!g.in_shop);
        g.level = 3;
        g.nextLevel(); // 3 -> 4
        try testing.expect(!g.in_shop);
        try testing.expectEqual(@as(u32, 0), g.shop_calls);
    }
}

test "the shop counts as a level and its stairs lead to the next one" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.loadShop(3);
    try testing.expectEqual(@as(u32, 3), g.level);
    // Walk along the bottom row to the stairs.
    for (0..@intCast(shop_stairs.x - shop_hero_start.x)) |_| g.step(.right);
    try testing.expect(!g.in_shop);
    try testing.expectEqual(@as(u32, 4), g.level);
    try testing.expectEqual(@as(usize, max_monsters), g.monster_count);
}

test "a shop has a shopkeeper, two items and no monsters" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.loadShop(3);
    try testing.expectEqual(@as(usize, 0), g.monster_count);
    try testing.expect(g.shop_items[0] != null and g.shop_items[1] != null);
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .fov = true, .color = true });
    try testing.expect(std.mem.indexOf(u8, out, "Level 3 (SHOP)") != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_shopkeeper ++ "@" ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_cyan ++ "@" ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, "!" ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, "For sale: ") != null);
    // The room is lit: the far stairs show through the field of view.
    try testing.expect(std.mem.indexOf(u8, out, ansi_yellow ++ ">" ++ ansi_reset) != null);
}

test "walking over an item buys it when the gold is enough" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.loadShop(3);
    g.shop_items = .{ .speed, .vision };
    g.inventory.gold = 50;
    g.hero = shop_item_pos[0].add(.{ .x = 0, .y = 1 });
    g.step(.up);
    try testing.expect(g.hero.eql(shop_item_pos[0]));
    try testing.expectEqual(@as(u32, 30), g.inventory.gold);
    try testing.expectEqual(@as(u32, 1), g.inventory.potionCount(.speed));
    try testing.expectEqual(@as(?Potion, null), g.shop_items[0]);
    try testing.expect(g.events.buy);
    var buf: [8192]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "You bought it! (speed potion, -20 gold)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "For sale: vision potion 25 gold\n") != null);
}

test "an item stays when the gold is not enough" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.loadShop(3);
    g.shop_items = .{ .speed, .vision };
    g.inventory.gold = 5;
    g.hero = shop_item_pos[0].add(.{ .x = 0, .y = 1 });
    g.step(.up);
    try testing.expect(g.hero.eql(shop_item_pos[0]));
    try testing.expectEqual(@as(u32, 5), g.inventory.gold);
    try testing.expectEqual(@as(?Potion, .speed), g.shop_items[0]);
    try testing.expectEqual(@as(usize, 0), g.inventory.items().len);
    try testing.expect(!g.events.buy);
    var buf: [8192]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "Not enough gold. (the speed potion costs 20 gold, you have 5)") != null);
    // Stepping off and on again with enough gold buys it.
    g.step(.down);
    g.inventory.gold = 20;
    g.step(.up);
    try testing.expectEqual(@as(u32, 0), g.inventory.gold);
    try testing.expectEqual(@as(u32, 1), g.inventory.potionCount(.speed));
}

test "the shopkeeper blocks the way" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.loadShop(3);
    const start = shopkeeper_pos.add(.{ .x = 0, .y = 1 });
    g.hero = start;
    g.step(.up);
    try testing.expect(g.hero.eql(start));
    try testing.expectEqualStrings("The shopkeeper smiles. Walk over an item to buy it.", g.message);
}

test "prices follow the user's table" {
    // Health S, M, L, time stop, speed, strength S, M, L, vision, invisibility, mystery.
    const prices = [Potion.count]u32{ 10, 15, 30, 25, 20, 30, 45, 70, 25, 25, 10 };
    for (std.enums.values(Potion), 0..) |p, i| try testing.expectEqual(prices[i], p.price());
    // The rarest potion is the most expensive.
    for (std.enums.values(Potion)) |p| try testing.expect(p.price() <= Potion.strength_large.price());
}

test "each potion kind has its color in the shop and the inventory" {
    try testing.expectEqualStrings(ansi_purple, Potion.vision.color());
    for ([_]Potion{ .small, .medium, .large }) |p| try testing.expectEqualStrings(ansi_green, p.color());
    for ([_]Potion{ .strength_small, .strength_medium, .strength_large }) |p| try testing.expectEqualStrings(ansi_brown, p.color());
    try testing.expectEqualStrings(ansi_yellow, Potion.time_stop.color());
    try testing.expectEqualStrings(ansi_blue, Potion.speed.color());

    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.loadShop(3);
    g.shop_items = .{ .vision, .strength_large };
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_purple ++ "!" ++ ansi_reset) != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_brown ++ "!" ++ ansi_reset) != null);

    g.inventory.add(.time_stop);
    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, true);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), ansi_yellow ++ "Time stop potion") != null);
}

const corridor_layout: Layout = &.{
    "##############################",
    "#@..............M............#",
    "##############################",
};

test "a mystery potion is good half the time and a curse the other half" {
    var good: usize = 0;
    var curses: [std.enums.values(Curse).len]usize = @splat(0);
    var seed: u64 = 0;
    while (seed < 2000) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, pocket_layout);
        g.hp = 5;
        g.inventory.add(.mystery);
        g.inventory.add(.vision);
        g.step(.use_1);
        try testing.expectEqual(@as(u32, 0), g.inventory.potionCount(.mystery));
        try testing.expectEqual(@as(u32, 1), g.inventory.potionCount(.vision)); // untouched
        if (g.mystery_potion) |p| {
            try testing.expect(p != .mystery);
            try testing.expect(g.mystery_curse == null);
            good += 1;
        } else {
            curses[@backingInt(g.mystery_curse.?)] += 1;
            try testing.expect(g.events.curse);
        }
    }
    try testing.expect(good >= 900 and good <= 1100);
    for (curses) |n| try testing.expect(n >= 140 and n <= 260); // about 200 each
}

test "a mystery potion works at full health and says what it was" {
    var prng = std.Random.DefaultPrng.init(3);
    var g = testGame(&prng, pocket_layout);
    g.inventory.add(.mystery);
    g.step(.use_1);
    try testing.expectEqual(@as(usize, 0), g.inventory.items().len);
    var buf: [8192]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "(it was a ") != null);
    try testing.expectEqualStrings("???", Potion.mystery.label());
    try testing.expectEqual(@as(u32, 10), Potion.mystery.price());
}

test "slowness makes the monsters act twice per round for 3 rounds" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, corridor_layout);
    g.applyCurse(.slow);
    try testing.expect(g.isCursed());
    // Within chase range, so it walks toward the hero every turn.
    g.monsters[0].pos.x = 5;
    g.step(.wait); // the drink round: one monster turn
    try testing.expectEqual(@as(i32, 4), g.monsters[0].pos.x);
    try testing.expectEqual(@as(u8, 3), g.slow);
    g.monsters[0].pos.x = 5;
    g.step(.wait); // slow round: two monster turns
    try testing.expectEqual(@as(i32, 3), g.monsters[0].pos.x);
    try testing.expectEqual(@as(u8, 2), g.slow);
    g.step(.wait);
    g.step(.wait);
    try testing.expectEqual(@as(u8, 0), g.slow);
    try testing.expect(!g.isCursed());
    g.monsters[0].pos.x = 5;
    g.step(.wait); // back to one turn per round
    try testing.expectEqual(@as(i32, 4), g.monsters[0].pos.x);
}

test "paralysis turns the next action into a lost turn" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, pocket_layout);
    g.applyCurse(.paralysis);
    var buf: [8192]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "PARALYZED") != null);
    const start = g.hero;
    g.step(.right);
    try testing.expect(g.hero.eql(start));
    try testing.expectEqualStrings("You are paralyzed! You lose this turn.", g.message);
    try testing.expect(!g.paralyzed);
    g.step(.right);
    try testing.expectEqual(start.x + 1, g.hero.x);
}

test "the burning curse does 2 damage but never kills" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, pocket_layout);
    g.applyCurse(.burn);
    try testing.expectEqual(@as(i32, start_max_hp - 2), g.hp);
    try testing.expectEqual(@as(i32, 2), g.damage_taken);
    g.hp = 2;
    g.damage_taken = 0;
    g.applyCurse(.burn);
    try testing.expectEqual(@as(i32, 1), g.hp);
    try testing.expectEqual(@as(i32, 1), g.damage_taken);
    g.damage_taken = 0;
    g.applyCurse(.burn);
    try testing.expectEqual(@as(i32, 1), g.hp);
    try testing.expectEqual(@as(i32, 0), g.damage_taken);
    try testing.expectEqual(State.playing, g.state);
}

test "blindness shrinks the field of view for 5 rounds" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fov_layout);
    try testing.expect(isVisible(g.visibility(), 4, 2)); // 3 up
    g.applyCurse(.blind);
    try testing.expect(!isVisible(g.visibility(), 4, 2));
    try testing.expect(isVisible(g.visibility(), 4, 3)); // 2 up
    for (0..5) |_| g.step(.wait);
    try testing.expectEqual(@as(u8, 1), g.blind);
    g.step(.wait);
    try testing.expectEqual(@as(u8, 0), g.blind);
    try testing.expect(isVisible(g.visibility(), 4, 2));
}

test "confusion inverts the move keys for 5 rounds" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fov_layout);
    g.applyCurse(.confused);
    const start = g.hero;
    g.step(.up); // goes down
    try testing.expectEqual(start.y + 1, g.hero.y);
    g.step(.left); // goes right
    try testing.expectEqual(start.x + 1, g.hero.x);
    for (0..4) |_| g.step(.wait);
    try testing.expectEqual(@as(u8, 0), g.confused);
    const now = g.hero;
    g.step(.up);
    try testing.expectEqual(now.y - 1, g.hero.y);
}

test "the hero is red while cursed" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, pocket_layout);
    var buf: [16384]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{ .color = true }), ansi_cyan ++ "@") != null);
    g.applyCurse(.confused);
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_red ++ "@") != null);
    try testing.expect(std.mem.indexOf(u8, out, "CONFUSED 5") != null);
}

// Fountain and offering tests: the fountain to the left of the hero, the
// offering to the right, then a totem.
const fountain_layout: Layout = &.{
    "########",
    "#~@+Y..#",
    "########",
};

const totem_layout: Layout = &.{
    "####",
    "#@Y#",
    "####",
};

test "the event shows a shop 70% of the time and a fountain 30%" {
    var shops: usize = 0;
    var fountains: usize = 0;
    var seed: u64 = 0;
    while (seed < 2000) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, test_layout);
        g.level = 2;
        g.step(.down); // the stairs
        if (g.in_shop) shops += 1;
        if (g.in_fountain) fountains += 1;
        try testing.expect(!(g.in_shop and g.in_fountain));
    }
    const percent = fountains * 100 / (shops + fountains);
    try testing.expect(percent >= 25 and percent <= 35);
}

test "a fountain counts as a level and skips the next chance" {
    var seed: u64 = 0;
    while (true) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, test_layout);
        g.level = 2;
        g.step(.down);
        if (!g.in_fountain) continue;
        try testing.expectEqual(@as(u32, 3), g.level);
        try testing.expect(std.mem.indexOf(u8, g.message, "fountain") != null);
        try testing.expect(g.shop_skip);
        g.nextLevel(); // the fountain's stairs: level 4, no call
        try testing.expect(!g.inRoom());
        try testing.expectEqual(@as(u32, 4), g.level);
        g.nextLevel(); // level 4's stairs: skipped, no roll
        try testing.expect(!g.inRoom());
        try testing.expectEqual(@as(u32, 1), g.shop_calls);
        break;
    }
}

test "a fountain room has the fountain, the offering and no monsters" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.loadFountain(3);
    try testing.expect(g.in_fountain and !g.in_shop);
    try testing.expectEqual(@as(usize, 0), g.monster_count);
    try testing.expectEqual(Tile.fountain, g.tileAt(fountain_pos));
    try testing.expectEqual(Tile.offering, g.tileAt(offering_pos));
    try testing.expectEqual(Tile.stairs, g.tileAt(shop_stairs));
    try testing.expect(g.hero.eql(shop_hero_start));
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .fov = true });
    try testing.expect(std.mem.indexOf(u8, out, "Level 3 (FOUNTAIN)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "~") != null); // the room is lit
    try testing.expect(std.mem.indexOf(u8, out, "+") != null);
}

test "the fountain heals 5 HP once" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    const start = g.hero;
    g.hp = 2;
    g.step(.left);
    try testing.expect(g.hero.eql(start)); // the fountain blocks
    try testing.expectEqual(@as(i32, 7), g.hp);
    try testing.expectEqual(@as(i32, 5), g.healed);
    try testing.expect(g.events.drink);
    g.step(.left);
    try testing.expectEqual(@as(i32, 7), g.hp);
    try testing.expectEqualStrings("The fountain is dry.", g.message);
}

test "the fountain heals at most up to max HP" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    g.hp = start_max_hp - 2;
    g.step(.left);
    try testing.expectEqual(@as(i32, start_max_hp), g.hp);
    try testing.expectEqual(@as(i32, 2), g.healed);
}

test "the fountain does nothing at full health" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    g.step(.left);
    try testing.expectEqualStrings("You are already at full health.", g.message);
    try testing.expect(!g.fountain_used); // still there for later
    g.hp = 4;
    g.step(.left);
    try testing.expectEqual(@as(i32, 9), g.hp);
}

test "the offering raises max HP by 2 for 40 gold" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    g.inventory.gold = 50;
    g.hp = 6;
    g.step(.right);
    try testing.expectEqual(@as(u32, 10), g.inventory.gold);
    try testing.expectEqual(@as(i32, start_max_hp + 2), g.max_hp);
    try testing.expectEqual(@as(i32, 8), g.hp);
    try testing.expectEqual(Tile.floor, g.tileAt(g.hero)); // used up
    try testing.expect(g.events.buy);
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "(+2 max HP, -40 gold)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "HP 8/12") != null);
}

test "the offering stays when the gold is not enough" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    g.inventory.gold = 30;
    g.step(.right);
    try testing.expectEqual(@as(u32, 30), g.inventory.gold);
    try testing.expectEqual(@as(i32, start_max_hp), g.max_hp);
    try testing.expectEqual(Tile.offering, g.tileAt(g.hero));
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    try testing.expect(std.mem.indexOf(u8, out, "Not enough gold. (the offering costs 40 gold, you have 30)") != null);
}

test "health potions heal up to the raised max HP" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    g.max_hp = 12;
    g.hp = 10;
    g.inventory.add(.large);
    g.step(.use_1);
    try testing.expectEqual(@as(i32, 12), g.hp);
    try testing.expectEqual(@as(i32, 2), g.healed);
}

test "a totem heals completely 60% of the time and curses 40%" {
    var heals: usize = 0;
    var curses: usize = 0;
    var seed: u64 = 0;
    while (seed < 1000) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, totem_layout);
        g.hp = 3;
        g.step(.right);
        try testing.expectEqual(Tile.floor, g.tileAt(g.hero)); // it disappears
        if (g.totem_curse != null) {
            curses += 1;
            try testing.expect(g.events.curse);
        } else {
            heals += 1;
            try testing.expectEqual(g.max_hp, g.hp);
            try testing.expectEqual(g.max_hp - 3, g.healed);
        }
    }
    try testing.expect(heals >= 550 and heals <= 650);
    try testing.expectEqual(@as(usize, 1000), heals + curses);
}

test "a totem curse says where it came from" {
    var seed: u64 = 0;
    while (true) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, totem_layout);
        g.step(.right);
        if (g.totem_curse == null) continue;
        var buf: [16384]u8 = undefined;
        const out = try renderToBuf(&g, &buf, .{});
        try testing.expect(std.mem.indexOf(u8, out, "(a totem curse)") != null);
        break;
    }
}

test "totems show up on about 10% of levels and never two levels in a row" {
    var with_totem: usize = 0;
    var levels: usize = 0;
    var seed: u64 = 0;
    while (seed < 300) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = Game.init(prng.random());
        var prev = false;
        for (1..21) |n| {
            if (n > 1) g.loadLevel(@intCast(n));
            var count: usize = 0;
            for (g.map) |row| for (row) |t| {
                if (t == .totem) count += 1;
            };
            try testing.expect(count <= 1);
            const has = count == 1;
            try testing.expect(!(has and prev));
            if (has) with_totem += 1;
            levels += 1;
            prev = has;
        }
    }
    const percent = with_totem * 100 / levels;
    try testing.expect(percent >= 6 and percent <= 12);
}

test "shops and fountains never hold a totem" {
    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, test_layout);
        g.loadShop(3);
        for (g.map) |row| for (row) |t| try testing.expect(t != .totem);
        g.loadFountain(5);
        for (g.map) |row| for (row) |t| try testing.expect(t != .totem);
    }
}

test "the header shows the raised max HP" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    g.max_hp = 14;
    g.hp = 11;
    var buf: [16384]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "HP 11/14") != null);
}

test "fountains, offerings and totems have their own symbols and colors" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, fountain_layout);
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, ansi_blue ++ "~") != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_yellow ++ "+") != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_purple ++ "Y") != null);
}

// Invisibility tests. In the pocket the monster cannot move at all (walls
// and the hero all around), so only biting matters.
const invisible_pocket_layout: Layout = &.{
    "#####",
    "#@M##",
    "#####",
};

// An open room: the monster starts 3 tiles to the right of the hero,
// inside the chase radius.
const invisible_room_layout: Layout = &.{
    "###########",
    "#.........#",
    "#.........#",
    "#..@..M...#",
    "#.........#",
    "#.........#",
    "###########",
};

test "an invisibility potion hides the hero for the drink round and 5 more" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    g.step(.use_1);
    try testing.expect(g.events.invisible);
    try testing.expectEqual(@as(i32, start_max_hp), g.hp); // the drink round is hidden
    try testing.expectEqual(@as(u8, invisible_turns), g.invisible);
    for (0..invisible_turns) |i| {
        g.step(.wait);
        try testing.expectEqual(@as(i32, start_max_hp), g.hp);
        try testing.expectEqual(@as(u8, @intCast(invisible_turns - 1 - i)), g.invisible);
    }
    g.step(.wait); // visible again: the monster bites
    try testing.expectEqual(@as(i32, start_max_hp - monster_damage), g.hp);
}

test "a monster next to an invisible hero does not bite" {
    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, invisible_room_layout);
        g.monsters[0].pos = g.hero.add(.{ .x = 1, .y = 0 });
        g.inventory.add(.invisibility);
        g.step(.use_1);
        for (0..invisible_turns) |_| g.step(.wait);
        try testing.expectEqual(@as(i32, start_max_hp), g.hp);
    }
}

test "monsters within chase range do not come after an invisible hero" {
    // Visible, the monster 3 tiles away always steps closer. Invisible, it
    // only wanders: it steps at most 30% of the time, in a random direction.
    var closer: usize = 0;
    var seed: u64 = 0;
    while (seed < 400) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, invisible_room_layout);
        g.inventory.add(.invisibility);
        const before = g.monsters[0].pos.manhattan(g.hero);
        g.step(.use_1);
        if (g.monsters[0].pos.manhattan(g.hero) < before) closer += 1;
    }
    try testing.expect(closer < 400 * 15 / 100); // about 30% / 4 = 7.5%
}

test "a monster that was chasing stops when the hero turns invisible" {
    var closer: usize = 0;
    var seed: u64 = 0;
    while (seed < 400) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, invisible_room_layout);
        g.inventory.add(.invisibility);
        const start = g.monsters[0].pos.manhattan(g.hero);
        g.step(.wait);
        const chasing = g.monsters[0].pos.manhattan(g.hero);
        try testing.expectEqual(start - 1, chasing); // it was chasing
        g.step(.use_1);
        g.step(.wait);
        if (g.monsters[0].pos.manhattan(g.hero) < chasing) closer += 1;
    }
    try testing.expect(closer < 400 * 30 / 100);
}

test "attacking a monster ends the invisibility" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    g.monsters[0].hp = 10; // survives the sneak attack
    g.step(.use_1);
    g.step(.right); // hit the monster
    try testing.expectEqual(@as(u8, 0), g.invisible);
    try testing.expect(g.revealed);
    // Seen again, the monster bites back in the same round.
    try testing.expectEqual(@as(i32, start_max_hp - monster_damage), g.hp);
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{});
    // The bite replaces the hit message; the notes are still appended.
    try testing.expect(std.mem.indexOf(u8, out, "A monster bites you! (sneak attack: 4 damage) (you are visible again)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "INVISIBLE") == null);
}

test "drinking invisibility again resets the counter to 5" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    g.inventory.add(.invisibility);
    g.step(.use_1);
    g.step(.wait);
    g.step(.wait);
    try testing.expectEqual(@as(u8, invisible_turns - 2), g.invisible);
    g.step(.use_1);
    try testing.expectEqual(@as(u8, invisible_turns), g.invisible);
}

test "invisibility works at full health" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    g.step(.use_1);
    try testing.expectEqual(@as(u32, 0), g.inventory.potionCount(.invisibility));
    try testing.expectEqualStrings("You fade from sight! The monsters lose track of you.", g.message);
}

test "the header shows INVISIBLE N and the hero is gray" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    g.step(.use_1);
    var buf: [16384]u8 = undefined;
    const out = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, out, "INVISIBLE 5") != null);
    try testing.expect(std.mem.indexOf(u8, out, ansi_invisible ++ "@") != null);
    try testing.expectEqualStrings(ansi_invisible, Potion.invisibility.color());
}

test "the inventory lists the invisibility potion" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try g.renderInventory(&w, false);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "1) Invisibility potion  (5 turns) ..... x1") != null);
}

test "an invisible hero's hit is a sneak attack for double damage" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    g.monsters[0].hp = 5;
    g.step(.use_1);
    try testing.expect(g.isSneaky());
    g.step(.right);
    try testing.expectEqual(@as(i32, 1), g.monsters[0].hp); // 5 - 2 x 2
    try testing.expectEqual(@as(i32, 4), g.sneak_damage);
}

test "a hit during time stop is a sneak attack for double damage" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.time_stop);
    g.monsters[0].hp = 5;
    g.step(.use_1);
    g.step(.right);
    try testing.expectEqual(@as(i32, 1), g.monsters[0].hp);
    try testing.expectEqual(@as(i32, 4), g.sneak_damage);
}

test "a sneak attack doubles the strength bonus too" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.strength_small);
    g.inventory.add(.time_stop);
    g.monsters[0].hp = 10;
    g.step(.use_1); // strength +1
    g.step(.use_1); // time stop (the strength potion's slot is gone)
    g.step(.right);
    try testing.expectEqual(@as(i32, 10 - (hero_damage + 1) * 2), g.monsters[0].hp);
}

test "invisibility and time stop together still only double the damage" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.invisibility);
    g.inventory.add(.time_stop);
    g.monsters[0].hp = 10;
    g.step(.use_1);
    g.step(.use_1);
    g.step(.right);
    try testing.expectEqual(@as(i32, 10 - hero_damage * 2), g.monsters[0].hp);
}

test "a normal hit is not a sneak attack" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.step(.right);
    try testing.expectEqual(@as(i32, monster_hp - hero_damage), g.monsters[0].hp);
    try testing.expectEqual(@as(i32, 0), g.sneak_damage);
    var buf: [16384]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "sneak") == null);
}

test "a sneak attack kills a 3 HP monster in one hit" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, test_layout);
    g.inventory.add(.invisibility);
    g.step(.use_1);
    g.step(.right); // the monster next to the hero has monster_hp (3)
    try testing.expect(g.hit_killed);
    try testing.expectEqual(@as(usize, 0), g.monster_count);
}

test "a sneak attack ends the invisibility but not the time stop" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.time_stop);
    g.monsters[0].hp = 20;
    g.step(.use_1);
    g.step(.right);
    try testing.expect(g.timeStopped());
    g.step(.right); // still frozen: another sneak attack
    try testing.expectEqual(@as(i32, 4), g.sneak_damage);
    try testing.expectEqual(@as(i32, 20 - 8), g.monsters[0].hp);
}

test "the message shows the sneak attack damage" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    g.inventory.add(.time_stop);
    g.monsters[0].hp = 10;
    g.step(.use_1);
    g.step(.right);
    var buf: [16384]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "You hit the monster. (sneak attack: 4 damage)") != null);
    const colored = try renderToBuf(&g, &buf, .{ .color = true });
    try testing.expect(std.mem.indexOf(u8, colored, ansi_yellow ++ " (sneak attack: 4 damage)") != null);
}

/// Puts a monster of `kind` `dist` tiles to the right of the hero in a
/// corridor and runs one round, over 50 seeds. True if it came one tile
/// closer every time (it chased). A monster out of sight may still wander
/// toward the hero now and then, but never 50 times in a row.
fn alwaysChasesFrom(kind: MonsterKind, dist: i32) bool {
    var seed: u64 = 0;
    while (seed < 50) : (seed += 1) {
        var prng = std.Random.DefaultPrng.init(seed);
        var g = testGame(&prng, &.{
            "##############################",
            "#@...........................#",
            "##############################",
        });
        g.addMonster(.{ .x = 1 + dist, .y = 1 }, kind);
        g.step(.wait);
        if (g.monsters[0].pos.x != dist) return false;
    }
    return true;
}

test "a monster chases from 4 tiles away" {
    try testing.expect(alwaysChasesFrom(.monster, 4));
    try testing.expect(!alwaysChasesFrom(.monster, 5));
    try testing.expectEqual(@as(i32, 4), MonsterKind.monster.sight());
}

test "monsters are drawn with their kind's letter" {
    var prng = std.Random.DefaultPrng.init(1);
    var g = testGame(&prng, invisible_pocket_layout);
    try testing.expectEqual(MonsterKind.monster, g.monsters[0].kind);
    var buf: [16384]u8 = undefined;
    try testing.expect(std.mem.indexOf(u8, try renderToBuf(&g, &buf, .{}), "#@M##") != null);
}
