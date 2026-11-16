# Fountains and totems

Code: `Game.loadFountain`, `loadRoom`, `inRoom`, `useFountain`, `makeOffering`, `touchTotem`, `spawnTotem`, `randomCurse`, `heal`, `Game.max_hp`, the `fountain_*`, `offering_*` and `totem_*` constants, `fountain_pos`, `offering_pos` in `src/root.zig`.

Two new sources of healing, and a second use for gold besides the [shop](shop.md). All numbers are user rules (2026-11-16).

## Max HP

`Game.max_hp` starts at `start_max_hp` (10) and only offerings raise it. Every heal (potions, fountain, totem) goes through `Game.heal(amount)`, which caps at `max_hp` and records the real gain in `healed` (render appends `(+N HP)`). The header shows `HP hp/max_hp`.

## Fountain level

- **When:** in place of a shop. When the shop event fires on the stairs of an even level (80% the first time, 50% after, see [shop.md](shop.md)), `nextLevel` makes a second roll: `fountain_chance` (**30%**) a fountain, otherwise a shop. A fountain counts as a level and also sets `shop_skip`, so the next chance is skipped.
- **Room:** `loadRoom` (shared with `loadShop`): the same lit `shop_room`, hero at `shop_hero_start`, stairs at `shop_stairs`, no monsters, no loot, no field of view (`inRoom()`). The fountain `~` sits at `fountain_pos` (15,6) and the offering `+` at `offering_pos` (15,4). `in_fountain` is true; header `Level N (FOUNTAIN)`. Stairs message: "You found a fountain! Drink from it, or make an offering (+)."
- **Fountain `~`** (`useFountain`): it blocks like a wall, so the hero bumps it. It heals `fountain_heal` (**5**) HP **once, for free** (`fountain_used`), then says "The fountain is dry." and is drawn dimmed. At full HP it says "You are already at full health." and stays for later. Bumping it uses a turn. Plays `Sfx.drink` (`events.drink`).
- **Offering `+`** (`makeOffering`): the hero walks onto it like a shop item. With `offering_price` (**40**) gold or more: pays, `max_hp += offering_max_hp` (**2**), and the hero also heals those 2 points. The tile becomes floor, `events.buy` plays `Sfx.buy`, and render appends `(+2 max HP, -40 gold)`. Without enough gold it stays: "Not enough gold. (the offering costs 40 gold, you have G)". One per fountain.

## Totem `Y`

- **Spawn** (`spawnTotem`, called by `loadLevel` after `spawnLoot`): on a maze level, `totem_chance` (**10%**) turns one random loot spot (gold or chest) into a totem. Never on two levels in a row (`last_totem_level`). Shops and fountains have no loot, so they never hold one, but they still count as a level in between. Overall about 9% of levels.
- **Touch** (`touchTotem`): the hero walks onto it and it disappears. `totem_heal_chance` (**60%**): a full heal ("The totem glows. You are fully healed!", `Sfx.drink`). Otherwise one of the 5 mystery-potion curses (`randomCurse`, `applyCurse`, see [potions.md](potions.md)). `totem_curse` makes render append "(a totem curse)", and `events.curse` plays `Sfx.curse`. It works at full HP too: it is a gamble, like `???`.
- Drawn purple (`ansi_purple`), hidden in the fog like chests; it counts as a loot spot in `expectValidLevel`.

## Tests

`"the event shows a shop 70% of the time and a fountain 30%"`, `"a fountain counts as a level and skips the next chance"`, `"a fountain room has the fountain, the offering and no monsters"`, `"the fountain heals 5 HP once"`, `"the fountain heals at most up to max HP"`, `"the fountain does nothing at full health"`, `"the offering raises max HP by 2 for 40 gold"`, `"the offering stays when the gold is not enough"`, `"health potions heal up to the raised max HP"`, `"a totem heals completely 60% of the time and curses 40%"`, `"a totem curse says where it came from"`, `"totems show up on about 10% of levels and never two levels in a row"`, `"shops and fountains never hold a totem"`, `"the header shows the raised max HP"`, `"fountains, offerings and totems have their own symbols and colors"`. Test layouts: `~` fountain, `+` offering, `Y` totem.
