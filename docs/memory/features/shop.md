# Shop

Code: `Game.nextLevel`, `Game.loadShop`, `Game.buy`, `shopItemAt`, `isShopkeeper`, `writeForSale`, `Potion.price`, `randomPotion`, the `shop_*` constants and fields in `src/root.zig`; `Sfx.buy` in `src/sound.zig`.

A shop is a level where the hero spends gold on potions. All the rules below are user rules.

## When it shows up

The **shop event** is called on the stairs of every even level (2, 4, 6...) in `nextLevel`, never from a shop:

1. If `shop_skip` is set (a shop just showed up), the event is **not called at all**: no roll, `shop_calls` does not grow, the flag clears and a normal level loads.
2. Otherwise `shop_calls += 1` and the roll is `shop_first_chance` (**80%**) on the first call, `shop_chance` (**50%**) on every later one. On success `shop_skip` is set and a second roll picks the room: **70% a shop, 30% a fountain** (`fountain_chance`, see [fountains-totems.md](fountains-totems.md)). Both use `loadRoom`; `inRoom()` is true for either.

Example: level 2's stairs roll 80% -> shop on level 3 -> level 4's stairs are skipped -> level 6's stairs roll 50%. If level 2's roll fails, level 4's stairs roll 50%.

The shop **counts as a level**: `level` goes up by one and monster HP (see [monsters.md](monsters.md)) uses the number as usual.

## The room

`loadShop(n)`: all wall, a lit floor room `shop_room` (x 9..21, y 3..9, centered on the 31x13 map), the shopkeeper at `shopkeeper_pos` (top middle), the 2 items at `shop_item_pos` (middle row), the hero at `shop_hero_start` (bottom left), the stairs at `shop_stairs` (bottom right). No monsters, no loot. `in_shop` is true until `loadLevel` clears it.

- Items are rolled with `randomPotion`, **the same split as a chest's potion** (see [potions.md](potions.md)); two items can be the same kind.
- The field of view is off in the shop (the room is lit).

## Buying

- Stepping on an item's tile moves the hero there and calls `buy`: with `gold >= price` the gold is paid, the potion goes to the inventory, the item disappears, `events.buy` plays `Sfx.buy`, and the message "You bought it!" gets "(<label>, -N gold)" appended by `render`.
- Without enough gold the item stays: "Not enough gold. (the <label> costs N gold, you have G)". Stepping off and on again retries.
- Bumping the shopkeeper blocks the move: "The shopkeeper smiles. Walk over an item to buy it."
- Each move is a normal turn (effect counters tick).

## Prices (`Potion.price`, user-approved table)

| Potion | Chance in a potion roll | Price |
|---|---|---|
| small health | 15% | 10 |
| mystery | 10% | 10 (a cheap gamble, user choice) |
| medium health | 10.5% | 15 |
| speed | 15% | 20 |
| time stop | 10% | 25 |
| vision | 10% | 25 |
| invisibility | 10% | 25 (user choice) |
| large health | 4.5% | 30 |
| small strength | 7.5% | 30 |
| medium strength | 5.25% | 45 |
| large strength | 2.25% | 70 |

The prices were set by rarity before the mystery and invisibility potions each took 10% from health. Since then medium health (10.5%) is rarer than speed (15%) but cheaper; the test checks the table itself (`"prices follow the user's table"`).

## Rendering

Header `Level N (SHOP)`; items `!` in their potion's color (`Potion.color`, see [potions.md](potions.md)); the shopkeeper `@` in orange (`ansi_shopkeeper`, 256-color 208); a `For sale: <label> N gold, ...` line (or `sold out`) between the map and the message.

## Tests

`"the shop event shows up 80% the first time and 50% after"`, `"after a shop shows up, the next chance is skipped"`, `"the shop event only runs on the stairs of even levels"`, `"the shop counts as a level and its stairs lead to the next one"`, `"a shop has a shopkeeper, two items and no monsters"`, `"walking over an item buys it when the gold is enough"`, `"an item stays when the gold is not enough"`, `"the shopkeeper blocks the way"`, `"prices follow the user's table"`.
