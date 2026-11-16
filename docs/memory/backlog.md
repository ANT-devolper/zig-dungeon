# Backlog

Ideas and known issues not done yet. Link a GitHub issue when one exists: `[#N](https://github.com/ANT-devolper/zig-dungeon/issues/N)`. The `gh` CLI is not installed on this machine, so the user creates the issues and gives me the number. Remove an item when it is done (and add it to [changelog.md](changelog.md)).

## Ideas

### Next steps (agreed with the user on 2026-11-16)

The user chose these four directions to make the game more fun. They do not all have to be done at once; pick one at a time. The numbers and names below are suggestions, still to be confirmed with the user before each one is built.

- [ ] **Monster variety.** New monster kinds that change how a fight plays, built on the existing round system (`monstersTurn`):
  - [ ] Rat (`r`): 1 HP, acts twice per round, comes in groups.
  - [ ] Brute (`B`): acts every other round, bites for 2.
  - [ ] Thief (`T`): steals gold (the score) and runs away; killing it gives the gold back.
  - [ ] Ghost (`G`): walks through walls, from level 5 on.
  - [ ] Slime (`S`): splits into two small slimes when it dies.
- [ ] **Sneak attack.** Hitting a monster that is wandering (has not started chasing, outside `chase_radius`) deals double damage. Uses the fog and field of view.
- [ ] **Level-up perks.** Every 3 levels (the same pace as monster HP), the stairs offer a choice with one key: +3 max HP, +1 permanent damage or +1 view radius. Fixes the late game, where `max_hp` (10) and the hero's damage (2) never grow while monster HP does.
- [ ] **Altars and fountains.** A rare special tile per level:
  - [ ] Fountain: heals or curses (a gamble like the `???` potion).
  - [ ] Altar: identifies a mystery potion in the inventory, or trades 30 gold for +1 max HP (a second use for gold besides the shop).

## Known issues

- The 10th inventory item cannot be used: there are 10 potion kinds (`Potion.count`), but the keys only go from `1` to `9` (`Command.use_1..use_9`), and `renderInventory` shows `[1-10] use`. Possible fixes: map `0` to slot 10, or merge sizes into one slot.

- Keys pressed during an animation are queued and run afterwards. Holding a direction keeps walking, which is fine, but a fast typist can queue moves they did not mean. Possible fix: flush the input buffer after each turn. Not requested.
- Health potions found while at full HP cannot be drunk (by design); there is no way to drop items.
