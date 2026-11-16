# Backlog

Ideas and known issues not done yet. Link a GitHub issue when one exists: `[#N](https://github.com/ANT-devolper/zig-dungeon/issues/N)`. The `gh` CLI is not installed on this machine, so the user creates the issues and gives me the number. Remove an item when it is done (and add it to [changelog.md](changelog.md)).

## Ideas

### Next steps (agreed with the user on 2026-11-16)

The user chose these four directions to make the game more fun. They do not all have to be done at once; pick one at a time. The numbers and names below are suggestions, still to be confirmed with the user before each one is built.

- [ ] **Monster variety.** New monster kinds that change how a fight plays, built on the existing round system (`monstersTurn`):
  - [x] Rat (`r`): 1 HP, acts twice per round, comes in groups (from level 2, sight 5).
  - [ ] Brute (`B`): acts every other round, bites for 2.
  - [x] Thief (`T`): steals 25 gold (the score) and runs away; killing it gives the gold back (from level 4, sight 5).
  - [ ] Ghost (`G`): walks through walls, from level 5 on.
  - [x] Slime (`S`): splits into two small slimes when it dies (from level 3).
- [x] **Sneak attack.** Done on 2026-11-16, reshaped by the user: a hit while invisible or during time stop deals double damage. See [features/monsters.md](features/monsters.md).
- [ ] **Level-up perks.** Every 3 levels (the same pace as monster HP), the stairs offer a choice with one key: +3 max HP, +1 permanent damage or +1 view radius. Fixes the late game, where `max_hp` (10) and the hero's damage (2) never grow while monster HP does.
- [x] **Altars and fountains.** Done on 2026-11-16, reshaped by the user: a fountain level (in place of 30% of shops) with a free heal and an offering that sells max HP, and a totem in place of a loot spot (full heal or curse). See [features/fountains-totems.md](features/fountains-totems.md). The "altar identifies a mystery potion" idea was dropped.

## Known issues

- Inventory items past the 9th cannot be used: there are 11 potion kinds (`Potion.count`, since the invisibility potion), but the keys only go from `1` to `9` (`Command.use_1..use_9`), and `renderInventory` shows `[1-10] use` or `[1-11] use`. Possible fixes: `0` and `-` for slots 10 and 11, or merge sizes into one slot. The user chose to leave it for later (2026-11-16).

- Keys pressed during an animation are queued and run afterwards. Holding a direction keeps walking, which is fine, but a fast typist can queue moves they did not mean. Possible fix: flush the input buffer after each turn. Not requested.
- Health potions found while at full HP cannot be drunk (by design); there is no way to drop items.
