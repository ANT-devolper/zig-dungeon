# Inventory

Code: `Inventory` (`add`, `remove`, `items`, `itemAt`, `potionCount`), `Game.renderInventory`, `Command.use_1..use_9`, `Command.slot()` in `src/root.zig`; the `i` screen loop in `src/main.zig`.

- `Game.inventory` holds `gold` (the score), `potions[Potion.count]` (counts indexed by `Potion.index()`) and `slots`/`slot_count`, the usable items **in pick-up order**.
- **Numbers are positions, not fixed per kind** (a user rule). `add` appends a kind the hero did not have; `remove` drops a kind that runs out and shifts the rest up, so the numbers are always 1..n with no gaps.
- **Always go through `add`/`remove`**, never write `potions` directly, or `slots` gets out of sync.
- `renderInventory` lists only what the hero has (zero gold hidden), shows "(empty)" when there is nothing, offers `[1-n] use` and `[other key] close`.
- Keys `1`-`9` parse to `Command.use_1..use_9` (`slot()` gives the 0-based slot). They work from the map too. A number with no item uses no turn.
- **The `i` screen** (`Command.inventory`) is a pause screen: `main.zig` draws `renderInventory` and reads one key. A number runs `step(.use_N)` plus `afterTurn`; Ctrl+C quits; any other key closes the screen **without** calling `Game.step`. `step(.inventory)` is a no-op as a safety net.
- Drinking: see [potions.md](potions.md).
