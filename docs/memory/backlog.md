# Backlog

Ideas and known issues not done yet. Link a GitHub issue when one exists: `[#N](https://github.com/ANT-devolper/zig-dungeon/issues/N)`. The `gh` CLI is not installed on this machine, so the user creates the issues and gives me the number. Remove an item when it is done (and add it to [changelog.md](changelog.md)).

## Ideas

- (none yet)

## Known issues

- Keys pressed during an animation are queued and run afterwards. Holding a direction keeps walking, which is fine, but a fast typist can queue moves they did not mean. Possible fix: flush the input buffer after each turn. Not requested.
- Health potions found while at full HP cannot be drunk (by design); there is no way to drop items.
