# PROTOCOL_SYSTEM_MAINTENANCE.md
# Version: 1.0
# Author: Kai
# Date: 2026-04-21
# Status: AUTHORITATIVE — governs all maintenance and redundancy reduction work
#
# PURPOSE:
# Defines how Kai and agents perform system maintenance — identifying redundancy,
# reducing dead weight, and keeping the codebase clean — without introducing risk.
#
# Hyo directive (2026-04-21): "Attempt to identify redundancy and reduce it.
# This requires reading every file, schedule and parsing through every line beforehand.
# Cannot delete without full understanding. Need a scheduled maintenance protocol.
# How often? Nightly? → Yes, nightly."
#
# SCHEDULE: Nightly at 01:30 MT — after consolidate.sh (01:00) completes.

---

## ALGORITHM-FIRST: THE MAINTENANCE GATE

These gates run BEFORE any maintenance or cleanup action. A NO at any gate is a STOP.

```
PRE-MAINTENANCE ALGORITHM:

GATE 1: Have I read every file in scope for this maintenance pass?
  → NO → STOP. Read first. Every file. Every line. No exceptions.
  → YES → GATE 2

GATE 2: Do I have a complete list of consumers for each file I'm considering removing?
  (A "consumer" is: a script that imports/sources/references it, a cron that runs it,
   a protocol that documents it, an agent that depends on it)
  → NO → STOP. Trace all references first with: grep -r "filename" .
  → YES → GATE 3

GATE 3: Do I understand WHY each candidate file exists?
  (When was it created? What problem did it solve? Is that problem still present?)
  → NO → STOP. Check git log, evolution.jsonl, session notes.
  → YES → GATE 4

GATE 4: Have I confirmed the file has ZERO consumers and serves NO active purpose?
  → NO → the file is NOT redundant; leave it alone
  → YES → GATE 5

GATE 5: Is this a permanent deletion (file removed from repo)?
  → YES → escalate to Hyo — Kai does not permanently delete without approval
  → NO (disable, move, archive) → continue

GATE 6: Will the system still work after this change?
  → NO / UNCERTAIN → do not proceed; open a ticket to investigate further
  → YES (confirmed by simulation or dry-run) → proceed

POST-MAINTENANCE GATE:
GATE 7: After each maintenance action, does everything still run?
  → Run: dispatch health && kai verify
  → FAIL → revert immediately
  → PASS → log the action to maintenance-log.jsonl
```

---

## SECTION 1: WHAT COUNTS AS REDUNDANCY

### Redundant (safe to examine for removal or consolidation)

- **Duplicate logic**: Two functions or scripts that do the same thing, with one being a clear superset
- **Superseded configs**: Old launchd plists replaced by newer versions (verify old one is not loaded)
- **Dead scripts**: Scripts that have no trigger, no reference, and have not run in >30 days
- **Stale protocols**: Protocol files that reference tools, paths, or workflows that no longer exist
- **Duplicate data files**: Two copies of the same data maintained manually (vs. dual-path by design)
- **Obsolete logs**: Log files for processes that no longer run (but check: may be needed for history)

### NOT Redundant (do not touch without deep investigation)

- **Dual-path files** (`website/` and `agents/sam/website/`): This looks like duplication but is intentional design per KE-005. These are the same content in two git paths for Vercel compatibility. DO NOT remove either path.
- **Symlinks**: Every symlink has a reason. Read it before touching it.
- **Fallback configs**: Many scripts have fallback paths. The "unused" path may be the emergency fallback.
- **Archived data**: Files in `archive/YYYY/MM/` are permanent history — not redundant.
- **Protocol reference files**: A protocol that "nobody reads" is still the source of truth. Don't remove it — improve it.
- **Evolution and ledger files**: `evolution.jsonl`, `known-issues.jsonl`, etc. are memory. Never purge.

---

## SECTION 2: THE READ-FIRST RULE (non-negotiable)

**No maintenance action begins without a complete read pass.**

Before evaluating ANY file for redundancy:
1. `cat` the full file — not a summary, the full content
2. `grep -r "[filename without extension]" .` — find all references
3. Check `kai/protocols/TRIGGER_MATRIX.md` — is it listed?
4. Check `launchctl list | grep [relevant keyword]` (via queue) — is it running on schedule?
5. Check `git log --oneline --follow [filename]` — when was it last touched?

If any reference is found: the file has a consumer. It is not dead. Stop.

This rule exists because:
- Scripts reference other scripts by relative path — a "dead" script may be called by an active one
- Protocols are referenced by agents who read them at session start — they're "consumed" by reading
- Data files may be read by scripts that don't `import` them but open them by path

**The maintenance log records what was read, when, and what was decided:**
```bash
# Log every read during maintenance
echo '{"date":"YYYY-MM-DD","file":"path/to/file","action":"read","decision":"keep|archive|disable","reason":"..."}' \
    >> kai/ledger/maintenance-log.jsonl
```

---

## SECTION 3: WHAT KAI CAN DO WITHOUT ASKING

Kai can autonomously:
- **Move** files to archive folders (with GATE 1-6 passed)
- **Disable** a launchd plist by unloading it (not deleting) — must be re-loadable
- **Comment out** a cron or schedule entry (reversible)
- **Add a deprecation notice** to a file documenting why it's superseded
- **Consolidate** two scripts into one (preserving all functionality, with tests)
- **Update stale protocol references** to point to current paths/versions

Kai MUST escalate to Hyo before:
- **Permanently deleting** any file from the repo
- **Removing** a launchd plist from `~/Library/LaunchAgents/`
- **Removing** any entry from `feed.json` or archive
- **Consolidating** two systems that serve different users or have different failure modes
- **Any maintenance action that could silence a critical alert** (Telegram, email, etc.)

---

## SECTION 4: NIGHTLY MAINTENANCE PASS (01:30 MT)

**Schedule:** `com.hyo.system-maintenance` — 01:30 MT daily (after `consolidate.sh` at 01:00)

**What runs every night:**

### Phase 1: Audit dead files (10 min max)

```bash
# Find scripts not referenced in TRIGGER_MATRIX.md
# (TRIGGER_MATRIX lists all active artifacts)
python3 bin/maintenance-audit.py --check-dead-scripts
```

Flags any `.sh`, `.py` file in `bin/` or `agents/*/` that:
- Is not listed in `kai/protocols/TRIGGER_MATRIX.md`
- Has not been git-committed in >14 days
- Has zero grep references in the codebase

Flags go to `kai/ledger/maintenance-log.jsonl` as `"status": "flagged"` — they are NOT deleted.

### Phase 2: Stale protocol scan (5 min max)

```bash
python3 bin/maintenance-audit.py --check-stale-protocols
```

Flags any protocol file where:
- A referenced file path no longer exists
- A referenced script or tool is not in TRIGGER_MATRIX.md
- A "version" field is >60 days old without a bump

### Phase 3: Duplicate detection (5 min max)

```bash
python3 bin/maintenance-audit.py --check-duplicates
```

Finds files with identical content (sha256 match) that are not intentional dual-path.
Flags but never removes.

### Phase 4: Log nightly summary

```bash
# Appended to maintenance-log.jsonl after every nightly run
{
  "date": "YYYY-MM-DD",
  "dead_scripts_flagged": N,
  "stale_protocols_flagged": N,
  "duplicates_flagged": N,
  "actions_taken": [],
  "escalations_required": []
}
```

**No action is taken automatically.** The nightly pass ONLY flags. Kai reviews flags at session start (during hydration) and decides what to do, with human oversight for anything that touches live files.

---

## SECTION 5: HOW OFTEN — CADENCE

| Activity | Frequency | Who | Gate |
|---|---|---|---|
| Nightly dead-file scan | Nightly (01:30 MT) | maintenance-audit.py | Automated — flags only |
| Stale protocol scan | Nightly (01:30 MT) | maintenance-audit.py | Automated — flags only |
| Duplicate detection | Nightly (01:30 MT) | maintenance-audit.py | Automated — flags only |
| Maintenance flag review | Each Kai session | Kai | Manual — Kai reads maintenance-log.jsonl |
| Deep read pass (full codebase) | Monthly | Kai | Manual — read every file before any consolidation |
| Maintenance action execution | Ad hoc after review | Kai | GATES 1-7 required |
| Permanent deletion | Only with Hyo approval | Kai + Hyo | Escalation required |

**Answer to Hyo's question "how often?" → Nightly flagging. Manual review at each session. Deep passes monthly.**

---

## SECTION 6: MAINTENANCE LOG

Location: `kai/ledger/maintenance-log.jsonl`

Schema:
```json
{
  "date": "YYYY-MM-DD",
  "session": "S25",
  "file": "bin/some-old-script.sh",
  "action": "flagged | archived | disabled | consolidated | kept",
  "reason": "Not referenced in TRIGGER_MATRIX. Zero grep hits. Last commit 2026-03-01.",
  "reversible": true,
  "escalated_to_hyo": false,
  "hyo_decision": null
}
```

The log is append-only. It is the audit trail for all maintenance decisions.

---

## SECTION 7: FORBIDDEN ACTIONS

No matter what the situation is, Kai NEVER:
- Deletes `evolution.jsonl` files (agent memory)
- Deletes `known-issues.jsonl` or `session-errors.jsonl` (error memory)
- Removes any file from the `archive/` directories
- Removes any launchd plist from `~/Library/LaunchAgents/` without explicit Hyo instruction
- Deletes or truncates `feed.json`
- Removes any file from `agents/nel/security/` (secrets)

---

## VERSION HISTORY

| Version | Date       | Change |
|---------|------------|--------|
| v1.0    | 2026-04-21 | Initial protocol. Hyo directive: read everything first, no purging, nightly cadence. 6-gate pre-maintenance algorithm. 4-phase nightly audit. Maintenance log schema. Forbidden actions list. |

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
