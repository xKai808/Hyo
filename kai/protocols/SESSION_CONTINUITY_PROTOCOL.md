# SESSION_CONTINUITY_PROTOCOL.md
**Version:** 1.0
**Created:** 2026-04-21 (Session 27 cont. 9)
**Owner:** Kai
**Read by:** Kai at start and end of every session. Also read by `bin/session-close.sh` and the nightly memory verifier.

This protocol exists because today (Session 27) was a major success and Hyo wants it to continue without prompting. The goal: every new Kai session picks up exactly where the last one left off, with zero re-explanation, zero memory loss, and zero dropped context.

---

## WHY THIS EXISTS

Session continuity has broken in the past because:
1. Continuation sessions skipped hydration ("I have the compaction summary — that's enough"). It is never enough.
2. End-of-session checklists were completed partially or skipped when Hyo ended the conversation abruptly.
3. Memory writes happened but were never verified — the write "should have" worked.
4. Queue commit jobs were created but nobody confirmed they landed on main.
5. The next-session Kai had no machine-readable signal telling it what the most important thing to do was.

This protocol closes all five gaps.

---

## PART 1 — END OF EVERY SESSION (mandatory, even if Hyo ends abruptly)

Kai must run `bin/session-close.sh` at the end of every session. If Hyo ends the conversation before Kai can run it, the close script must run at the START of the next session before anything else.

The close script does these things in order and will not exit until all pass:

### 1. Write session-handoff.json
Location: `kai/ledger/session-handoff.json`
This is the machine-readable handoff. It is the FIRST thing the next Kai reads (before KAI_BRIEF, before KNOWLEDGE.md). It contains:
- What shipped this session (verified, not assumed)
- The single most important next action
- All open P0s
- Hyo actions pending (what only Hyo can do)
- Whether commits were queued and what they contain
- A memory freshness check (timestamps for KAI_BRIEF, KNOWLEDGE.md, KAI_TASKS, daily note)

Format: see `session-handoff.json` schema at bottom of this file.

### 2. Update KAI_BRIEF.md
- "Shipped today" section must reflect everything that actually shipped this session
- "Current state" must reflect where the system actually is (not where it should be)
- Open P0s listed explicitly
- Timestamp updated

### 3. Update KAI_TASKS.md
- ★ NEXT SESSION PRIORITY QUEUE block at top updated
- Items completed this session moved to Done
- New tasks that emerged added with correct priority
- Hyo-action items clearly marked [H]

### 4. Write daily note
Location: `kai/memory/daily/YYYY-MM-DD.md`
Format: `## [HH:MM] Session end — <one-line summary>`
Must include: what shipped, what's blocked, what's next.

### 5. Write memory engine event
```bash
HYO_ROOT=~/Documents/Projects/Hyo python3 ~/Documents/Projects/Hyo/kai/memory/agent_memory/memory_engine.py observe \
  --type session_end \
  --content "Session <ID> complete. Shipped: <summary>. Next: <top priority>." \
  --importance high
```

### 6. Queue git commit for all changed files
If anything was modified this session, a commit job must be in `kai/queue/pending/` before session ends.
The job must name every file changed.

### 7. Verify memory freshness (self-check)
Kai confirms:
- KAI_BRIEF.md modified within last 30 minutes: YES/NO
- KAI_TASKS.md modified within last 30 minutes: YES/NO
- Daily note written today: YES/NO
- session-handoff.json written: YES/NO
- At least one commit job queued: YES/NO

If any check is NO → go back and fix it. Do not exit session close until all are YES.

---

## PART 2 — START OF EVERY SESSION (mandatory, no exceptions)

The next Kai MUST do these steps in order before responding to Hyo with anything substantive.

### Step 0: Read session-handoff.json FIRST
Location: `kai/ledger/session-handoff.json`
This tells you in 30 seconds: what shipped last session, what the top priority is, what Hyo is waiting on, whether commits landed. Read it before touching any other file.

### Step 1: Run the full hydration protocol from CLAUDE.md
This is NON-NEGOTIABLE. The compaction summary does NOT replace it. Hydration reads files. The summary is prose that can be wrong, stale, or incomplete. Files are ground truth.

Files in order:
1. KAI_BRIEF.md
2. kai/ledger/hyo-inbox.jsonl (urgent Hyo messages)
3. kai/dispatch/ (today + yesterday dispatch transcripts)
4. kai/memory/KNOWLEDGE.md
5. kai/memory/TACIT.md
6. Memory engine recall query
7. KAI_TASKS.md
8. kai/ledger/known-issues.jsonl
9. kai/ledger/session-errors.jsonl
10. kai/protocols/EXECUTION_GATE.md
11. kai/protocols/VERIFICATION_PROTOCOL.md
12. kai/ledger/simulation-outcomes.jsonl

### Step 2: Run the hydration self-test (5 yes/no gates)

Before responding to Hyo, Kai must be able to answer YES to all 5:

```
HYDRATION GATE — answer before ANY response to Hyo:

G1: Can I name the current open P0(s) without re-reading?
    → If NO: re-read KAI_BRIEF. Do not proceed.

G2: Can I state the single top priority for this session in one sentence?
    → If NO: re-read ★ NEXT SESSION PRIORITY QUEUE in KAI_TASKS. Do not proceed.

G3: Do I know what Hyo is waiting to do herself (H-items)?
    → If NO: re-read P0 ACTION REQUIRED FROM HYO in KAI_TASKS. Do not proceed.

G4: Do I know which commits are still pending vs landed on main?
    → If NO: run `cd ~/Documents/Projects/Hyo && git log --oneline -5` via kai exec. Do not proceed.

G5: Have I checked session-errors.jsonl for patterns that match today's work?
    → If NO: read the last 10 entries. Do not proceed.
```

All 5 YES → proceed. Any NO → fix the gap, then re-run the gate.

### Step 3: Run `dispatch health` and `dispatch status`
Verify closed-loop integrity (agents running, queue healthy, no critical daemon down).

### Step 4: Write the 4-line status to Hyo
Only after Steps 0-3 are complete:
1. What shipped last session
2. Top priority this session
3. Recommendation for next 15 minutes
4. Queue active: yes/no

---

## PART 3 — NIGHTLY MEMORY INTEGRITY CHECK

Runs nightly at **06:45 MT** via `kai-autonomous.sh` (after morning report, before Hyo wakes up).
Script: `bin/session-prep.sh`

What it checks:
1. KAI_BRIEF.md was modified today (within 24h)
2. Daily note exists for today
3. session-handoff.json exists and is from today
4. KAI_TASKS.md ★ NEXT SESSION PRIORITY QUEUE block is present
5. All queued commits from yesterday's session landed on main (git log check)
6. simulation-outcomes.jsonl has a result from last night's 06:30 run
7. Ra runner last exit code (from logs) — flag if exit-2 again

If any check fails:
- Write a `**[PREP_FAILURE]**` entry to today's daily note
- Append to `kai/ledger/session-handoff.json` under `prep_failures`
- If P0 level: write to hyo-inbox.jsonl so Kai sees it immediately at session start

---

## PART 4 — WHAT "PICKING UP WHERE WE LEFT OFF" MEANS (concrete checklist)

When Hyo opens a new session, the first Kai response should demonstrate:

✓ Knows what shipped last session (not from memory — from KAI_BRIEF)
✓ Knows the #1 task without being told
✓ Knows which H-items are waiting on Hyo
✓ Knows current system health (agents up, P0s, queue status)
✓ Has NOT forgotten any correction or decision Hyo made this week

The test: if Hyo asks "what are we working on?" — Kai answers in 2 sentences without asking a clarifying question.

---

## PART 5 — MEMORY FAILURE RECOVERY PROTOCOL

If something was supposed to be remembered but wasn't:

1. **Do not apologize more than one sentence.** Own it, then fix it.
2. **Identify the layer that failed.** Was it:
   - KNOWLEDGE.md (permanent facts — nightly consolidation failed to promote)
   - TACIT.md (Hyo preferences — not updated after session)
   - KAI_BRIEF.md (current state — end-of-session write skipped)
   - session-handoff.json (machine handoff — close script didn't run)
   - Daily note (raw event — write skipped or partial)
3. **Write the missing information to ALL relevant layers now.** Not just the one that failed.
4. **Add a gate to prevent recurrence.** Not a rule — a yes/no gate that will be checked next time.
5. **Log it to session-errors.jsonl** with category `memory-failure`.

The nightly consolidation (01:00 MT) handles promotion from daily notes → KNOWLEDGE.md.
The session close (Part 1) ensures daily notes are written.
The morning prep (Part 3) verifies everything landed.
This is a closed loop — a break anywhere gets detected and flagged.

---

## SCHEMA — session-handoff.json

```json
{
  "session_id": "27c9",
  "ended_at": "2026-04-21T21:30:00-06:00",
  "written_by": "kai-session-close",
  "top_priority": "Diagnose Ra runner exit-2 (TASK-20260421-ra-P0-runner-exit2)",
  "shipped_this_session": [
    "Schedule resequenced: flywheel 04:30, doctor 05:30, OMP 06:00, morning-report 07:00",
    "SYSTEM_SCHEDULE.md created — master timing reference",
    "AGENT_ALGORITHMS.md: QUALITY METRIC SYSTEM section added",
    "7 tickets opened for persistent simulation failures",
    "session-handoff.json protocol created (this file)"
  ],
  "open_p0s": [
    "Ra runner exit-2 since Apr 13 (TASK-20260421-ra-P0-runner-exit2)",
    "ACTIVE.md missing all agents — Phase 1 health check blind (TASK-20260421-infra-P1-active-md-missing)"
  ],
  "hyo_actions_pending": [
    "RESEND_API_KEY in Vercel (Aurora retention email blocked)",
    "Stripe webhook registration in Stripe dashboard",
    "bore.pub tunnel restart on Mini (queue at 30-120x slower without it)"
  ],
  "commits_queued": [
    "s27c8-kai-metrics-commit.json — omp-measure.sh, flywheel-doctor.sh, PROTOCOL_KAI_METRICS.md, GROWTH.md, KNOWLEDGE.md",
    "s27c9-schedule-algorithms-commit.json — kai-autonomous.sh, SYSTEM_SCHEDULE.md, AGENT_ALGORITHMS.md",
    "s27c9-tickets-commit.json — tickets.jsonl",
    "s27c9-brief-commit.json — KAI_BRIEF.md, KAI_TASKS.md"
  ],
  "commits_to_verify": [
    "Confirm all 4 queue jobs ran: git log --oneline -8"
  ],
  "memory_freshness": {
    "kai_brief_updated": "2026-04-21T21:22:00-06:00",
    "kai_tasks_updated": "2026-04-21T21:25:00-06:00",
    "daily_note_written": "2026-04-21T21:22:00-06:00",
    "knowledge_md_updated": "2026-04-21",
    "session_handoff_written": "2026-04-21T21:30:00-06:00"
  },
  "prep_failures": [],
  "system_tonight": {
    "22:00": "Nel runner (healthy)",
    "22:30": "Sam runner (healthy)",
    "22:45": "Aether daily (healthy)",
    "23:00": "Aether analysis (Mon-Fri, healthy)",
    "23:30": "Kai CEO report (healthy)",
    "03:00": "Ra runner — EXPECT EXIT-2 (8th consecutive failure)"
  },
  "notes": "Today was a major success. Do not start a new task before checking git log for the 4 queued commits. If they landed, proceed to Ra runner diagnosis. If not, investigate queue worker status first."
}
```

---

## ENFORCEMENT

- `bin/session-close.sh` runs this protocol automatically
- `bin/session-prep.sh` verifies nightly at 06:45 MT
- CLAUDE.md hydration protocol references session-handoff.json as Step 0
- `kai-autonomous.sh` schedules session-prep.sh
- Any session that does not have session-handoff.json from yesterday triggers a P1 alert in hyo-inbox.jsonl

This is not optional. It runs every session. If it didn't run last session, run it now before starting anything else.
