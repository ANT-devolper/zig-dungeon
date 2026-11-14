# Workflow

The way of working agreed with the user.

1. **Read memory first.** For any question or change, read [README.md](README.md) and the relevant page before opening code.
2. **Plan.** Bigger changes (new mechanics, input/screen changes) go through plan mode: read, write the plan, wait for approval. Ask the user when a game rule is a choice (for example a potion's chance and which share it takes).
3. **Implement.** Logic in `src/root.zig`, terminal code in `src/term.zig`, sounds in `src/sound.zig`, `src/main.zig` stays a thin shell. Follow the existing patterns (a new potion mirrors strength/time stop; see the checklist in [features/potions.md](features/potions.md)).
4. **Test.** Every behavior change has a test in `src/root.zig` named with a sentence. Run `zig fmt --check src/ build.zig`, `zig build test --summary all` and `zig build -Dtarget=x86_64-linux`. Terminal changes also get a smoke test with input and output redirected to files (never a pipe).
5. **Document.** In the same change: README for player-facing rules, these memory pages, `changelog.md`, `decisions.md`, `backlog.md`.
6. **The user tests** with `zig build run`. I cannot play in a real console, so I say what to check. **End the reply with the proposed commit message** (subject and body, in a code block), without committing, so the user decides whether to commit (a user rule).
7. **Commit only when the user asks.** Conventional Commits, lowercase imperative subject, a **body** (what and why, wrapped at about 72 columns), no AI attribution lines. Stage only the files of the change. **Show the full commit message (subject and body) and the hash in the reply.**
8. **Never push.** The user pushes on their own (a user rule). After a commit, do not offer to push.

Unpushed commits may be reworded (for example to add a body) without a force push. Never rewrite pushed commits without asking.
