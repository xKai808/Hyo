# Kai Context Protocol

**Version:** 1.0  
**Purpose:** Define when and how Kai saves context snapshots for session recovery.  
**Scope:** This is Kai's private session-management mechanism. **NOT a project consolidation.**

---

## Identity: Kai's Memory Layers

Kai has three layers of persistent memory:

1. **KAI_BRIEF.md** — Full session-continuity memory. Updated at end of every working session AND during nightly consolidation. Read first. Compounding narrative of what shipped, what's blocked, and current state.

2. **KAI_TASKS.md** — Priority task queue. Work from top down. Hyo can edit freely. Kai adds new tasks as they emerge.

3. **kai/context/LATEST.md** — Fast snapshot of the moment. Always points to the most recent `YYYY-MM-DD-HHMM.md` file. **NEW:** This is the bridge between sessions when context compression is imminent or when switching devices.

---

## When to Save Context

Run `kai save` in these scenarios:

1. **Before long operations** — Any task expected to take >10 minutes. Capture state now in case the operation times out or the session ends unexpectedly.

2. **End of every working session** — After any significant work. Establishes a checkpoint before moving to another device or restarting the CLI.

3. **Before context window approaches limit** — If you notice you're at >150k tokens in this conversation, save context. The next session will read this file first and pick up exactly where you left off.

4. **Before major deployments or risky changes** — Save state before running `kai deploy`, `kai consolidate`, or any high-stakes operation.

5. **On manual schedule** — Hyo can also request `kai save` at will.

---

## What Gets Captured

Each snapshot (`kai/context/YYYY-MM-DD-HHMM.md`) includes:

- **KAI_BRIEF excerpt** — The "Current state" section(s) from KAI_BRIEF.md (first 1024 chars, fast read).
- **Task queue summary** — Count of open tasks by priority (P0/P1/P2/P3) plus completed count.
- **Agent log status** — Most recent log for each agent (Sentinel, Cipher, Ra/Aurora, Consolidation) with timestamp and age.
- **Per-project task status** — Open/done task counts from `kai/consolidation/{project}/tasks.md`.
- **Recovery instructions** — How to use this snapshot to resume in a new session.

**Not included:** Full file contents (KAI_BRIEF.md and KAI_TASKS.md remain the authoritative sources). This is a summary, not a substitute.

---

## Recovery Flow (New Session)

When you're starting a new session and want to resume from a checkpoint:

1. **Read LATEST.md first** — This is the most recent snapshot. It gives you the lay of the land in <30 seconds.
   ```bash
   kai recover
   ```

2. **Then read full memory in order:**
   - KAI_BRIEF.md (complete state)
   - KAI_TASKS.md (complete task queue)
   - Most recent log in kai/logs/ (current activity)

3. **Hydrate and act.** Answer these three questions:
   - What shipped since the snapshot?
   - What's at the top of the task queue?
   - What should I work on in the next 15 minutes?

---

## Important: Not a Project Consolidation

**This protocol is orthogonal to project consolidations.**

- **kai/context/** — Kai's private session recovery. Fast snapshots. No git commits required. Only Kai reads these.
- **kai/consolidation/** — Shared per-project histories. Compounding logs (never overwritten). Multiple agents contribute. Synced to HQ dashboard and `website/docs/consolidation/`.

Do NOT mix these two systems:
- Context snapshots do not replace consolidation logs.
- Consolidation logs do not contain Kai-specific recovery markers.
- Each project's `consolidation/{project}/tasks.md` is NOT the same as KAI_TASKS.md. The former tracks the project; the latter tracks Kai's work across all projects.

---

## Commands

All context operations are subcommands of `kai`:

```bash
# Save a snapshot now
kai save

# View the latest snapshot (shorthand for: cat kai/context/LATEST.md)
kai recover

# View all snapshots (newest first)
ls -1t kai/context/*.md | head

# List old snapshots (older than 7 days are fair game for cleanup)
find kai/context -name "*.md" -mtime +7 -type f
```

---

## Automation & Scheduling

**No automatic context saves yet.** This is manual for now because:
- Context saves are <5 seconds and should be run by Kai (not scheduled agents).
- The goal is to ensure they happen *before* risky operations or context limits, not on a fixed schedule.

**Future:** If Kai's session length becomes predictable, we can add a scheduled task that runs `kai save` every N hours as a background safety mechanism.

---

## Technical Details

**File layout:**
```
kai/
├── context/
│   ├── 2026-04-12-0915.md    ← timestamped snapshots
│   ├── 2026-04-12-1430.md
│   ├── 2026-04-12-1900.md
│   └── LATEST.md             ← symlink (or copy) to the newest
├── context-save.sh           ← script that generates snapshots
├── CONTEXT_PROTOCOL.md       ← this file
└── ...
```

**Snapshot timestamp format:** `YYYY-MM-DD-HHMM` (UTC). Example: `2026-04-12-1430` means April 12, 2:30 PM UTC.

**LATEST.md:** Created as a symlink pointing to the newest snapshot. If symlinks fail (rare), falls back to a copy.

**Snapshot lifecycle:**
- Fresh snapshots are created on-demand with `kai save`.
- They persist indefinitely (no auto-cleanup).
- Snapshots older than 7 days are candidates for manual cleanup if disk space becomes a concern.

---

## Related Files

- **KAI_BRIEF.md** — Full session memory. Read first in any new session.
- **KAI_TASKS.md** — Task queue. Work from top down.
- **kai/logs/** — Agent run logs (Sentinel, Cipher, Ra, Consolidation). Linked in each snapshot.
- **kai/consolidation/** — Per-project compounding histories (orthogonal to this protocol).
- **bin/kai.sh** — Dispatcher that includes `kai save` and `kai recover` subcommands.

---

## Revision History

- **2026-04-12** — Kai Context Protocol v1.0. Introduced context snapshots for session recovery before context compression.
