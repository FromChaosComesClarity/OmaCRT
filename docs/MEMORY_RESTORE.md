# Restoring Claude Code's memory for OmaCRT

Same practice as the rest of this account's projects (see `Clarity`'s
`docs/MEMORY_RESTORE.md` for the original write-up). The repo carries the code;
**Claude Code's memory carries the reasoning** — why a design was picked over
its alternatives, what the hardware actually measured out to, which traps cost
real debugging time. None of that lives in git. Restore it with
[ClaudeMemKeeper](https://github.com/FromChaosComesClarity/ClaudeMemKeeper)
before the first real session on a new machine.

## Why this needs an app at all

Claude Code keys memory by the project's absolute path:

```
~/.claude/projects/<slug>/memory/
```

where `<slug>` is that path with every `/`, `_` and `.` turned into `-`. Clone
this repo to the same path on every machine and the slug matches automatically
— no translation needed. A different username or directory (the Mac side of a
two-machine setup, for instance) does need ClaudeMemKeeper's path-rewrite on
restore.

## Where this project's memory actually is right now

The brainstorm-and-research session that produced `docs/RESEARCH.md` ran with
the working directory at `~/Work` — a general scratch project, not this repo —
before this repo existed. That means the reasoning behind the options in
`docs/RESEARCH.md` (and anything decided in conversation but not yet written
into these docs) currently lives under:

```
~/.claude/projects/-home-jose-Work/memory/
```

not under an `OmaCRT`-specific slug. Once real implementation sessions start
from `~/Documents/DEVELOPMENT/CLAUDE/OmaCRT` (this directory), Claude Code will
begin a fresh `memory/` folder under the slug for *this* path, and the two
should be treated as one continuous project by whoever picks the work back up:
carry forward context by pointing a new session at both `docs/RESEARCH.md` and,
if needed, asking it to check the `-home-jose-Work` memory for anything about
"OmaCRT" not yet written down here.

## Restoring onto another machine

1. Clone this repo to the equivalent path on the new machine (same path =
   same slug = no rewrite needed; different path = let ClaudeMemKeeper's
   Settings-page rule handle it).
2. Open ClaudeMemKeeper, connect Google Drive (each machine authorizes
   separately), restore the snapshot that has this project's memory —
   check `manifest.json`'s file list for `-home-jose-Work` and/or
   `-<slug-for-this-repo's-path>` before trusting a snapshot is current.
3. Use **"Add only what is missing"** on a machine that already has its own
   fresh Claude Code install, so nothing gets clobbered.
4. If Drive is unreachable, use the offline fallback documented in
   `ClaudeMemKeeper`'s own README / other projects' `MEMORY_RESTORE.md` files —
   excluding `.credentials.json`, which is machine-bound and must never be
   copied across.

## Then

```bash
cd ~/Documents/DEVELOPMENT/CLAUDE/OmaCRT
claude
```

and open with:

> "Resume the OmaCRT project. Read your memory files for context."

If the memory didn't land, the giveaway is Claude having no idea what the
gamepad-daemon decision or the CRT burn-in plan were. Check that
`~/.claude/projects/-home-jose-Work/memory/` (and, going forward, this repo's
own slug) actually holds the expected `.md` files.

## What is deliberately never carried across

`.credentials.json` (Claude Code's own auth token — machine-bound; copying it
is how you get mystery logouts), live session runtime state, and caches. See
`ClaudeMemKeeper`'s README for the full exclusion list.
