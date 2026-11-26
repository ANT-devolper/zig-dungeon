# Backlog

Ideas and known issues not done yet. Link a GitHub issue when one exists: `[#N](https://github.com/ANT-devolper/zig-dungeon/issues/N)`. The `gh` CLI is not installed on this machine, so the user creates the issues and gives me the number. Remove an item when it is done (and add it to [changelog.md](changelog.md)).

## Ideas

### Next steps (agreed with the user on 2026-11-16)

The user chose these four directions to make the game more fun. They do not all have to be done at once; pick one at a time. The numbers and names below are suggestions, still to be confirmed with the user before each one is built.

- [x] **Monster variety.** Done on 2026-11-16 (one commit per kind; each kind has its own sight). See [features/monsters.md](features/monsters.md):
  - [x] Rat (`r`): 1 HP, acts twice per round, comes in groups (from level 2, sight 5).
  - [x] Brute (`B`): acts every other round, bites for 2 (from level 5, sight 2, HP +3).
  - [x] Thief (`T`): steals 25 gold (the score) and runs away; killing it gives the gold back (from level 4, sight 5).
  - [x] Ghost (`G`): walks through walls, from level 5 on (not the border, sight 6).
  - [x] Slime (`S`): splits into two small slimes when it dies (from level 3).
- [x] **Sneak attack.** Done on 2026-11-16, reshaped by the user: a hit while invisible or during time stop deals double damage. See [features/monsters.md](features/monsters.md).
- [x] **Level-up perks.** Done on 2026-11-26, reshaped by the user: +3 max HP, +1 permanent damage or a full heal (instead of +1 view radius), at levels 4, 7, 10... See [features/perks.md](features/perks.md).
- [x] **Altars and fountains.** Done on 2026-11-16, reshaped by the user: a fountain level (in place of 30% of shops) with a free heal and an offering that sells max HP, and a totem in place of a loot spot (full heal or curse). See [features/fountains-totems.md](features/fountains-totems.md). The "altar identifies a mystery potion" idea was dropped.

### Company and competition (raised with the user on 2026-11-19)

- [x] **Rival adventurer.** Done on 2026-11-19. See [features/rival.md](features/rival.md).
- [ ] Dog companion (`d`): follows the hero, bites monsters, chases thieves, growls at ghosts.
- [ ] Local high scores (top 10 in a file, `Best: level N` in the header).
- [ ] Daily challenge (the seed comes from the date, so everyone plays the same dungeon).
- [ ] Other ideas: a mercenary hired at the shop, a prisoner to rescue, a fairy narrator, a reaper that chases slow players.
- A peaceful rival can block a corridor: bumping it is an attack (which makes it fight back). Not requested.

## Known issues

- Inventory items past the 9th cannot be used: there are 11 potion kinds (`Potion.count`, since the invisibility potion), but the keys only go from `1` to `9` (`Command.use_1..use_9`), and `renderInventory` shows `[1-10] use` or `[1-11] use`. Possible fixes: `0` and `-` for slots 10 and 11, or merge sizes into one slot. The user chose to leave it for later (2026-11-16).

- Keys pressed during an animation are queued and run afterwards. Holding a direction keeps walking, which is fine, but a fast typist can queue moves they did not mean. Possible fix: flush the input buffer after each turn. Not requested.
- Health potions found while at full HP cannot be drunk (by design); there is no way to drop items.
