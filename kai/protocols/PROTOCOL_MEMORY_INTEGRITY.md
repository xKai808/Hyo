# PROTOCOL_MEMORY_INTEGRITY.md
# Memory Integrity — Source Tagging, Staleness, and Contamination Prevention
# Version: 1.0 — 2026-04-23
# Owner: Kai
# Enforced by: bin/memory-integrity-check.sh (daily), session hydration (every session)

---

## WHY THIS EXISTS

On 2026-04-23, Kai ran a failure audit and concluded "Claude Code Mini is logged out"
based on 48 delegate-failure files. Hyo confirmed this was wrong — Mini was logged in.
The inference was incorrect. If it had been written to KNOWLEDGE.md before Hyo caught it,
the next session would have inherited a wrong fact and potentially acted on it
(e.g., asking Hyo to log in when nothing was broken).

Root cause: KNOWLEDGE.md, TACIT.md, and session-handoff.json accept everything equally —
verified reads, inferences, and stale observations — with no way to distinguish them.
The nightly consolidation pipeline then promotes all three to permanent memory.

This protocol makes the distinction structural, not behavioral.

---

## STEP 1: SOURCE TAGGING (at write time)

Every fact written to KNOWLEDGE.md or session-handoff.json must be tagged with one of:

```
[FACT-READ]      Read directly from a file or command output. Citation required.
                 Example: [FACT-READ kai/ledger/api-usage.jsonl 2026-04-23] Cost today: $0.12
                 
[FACT-COMPUTED]  Calculated from verified facts. Calculation must be shown.
                 Example: [FACT-COMPUTED 620K-89K 2026-04-23] Context reduced 86% (620K → 89K tokens)
                 
[FACT-STATED]    Hyo said this directly. Highest trust. Date required.
                 Example: [FACT-STATED Hyo 2026-04-23] Hard cap: <$1/day API credit. Ant owns it.

[INFERENCE]      Conclusion drawn from observation. NOT a fact. Must name the observation.
                 Example: [INFERENCE from 48-delegate-files 2026-04-23] Mini may be logged out
                 INFERENCE entries are NEVER acted upon without live verification first.
                 
[UNVERIFIED]     Written without source. Treat as suspect until re-tagged.
```

**Rule:** If you cannot cite the source, tag it `[UNVERIFIED]`. Do not write untagged facts.

---

## STEP 2: FOUR QUESTIONS BEFORE EVERY MEMORY WRITE

These are not guidelines. They are stop-gates. Answer each before writing to
KNOWLEDGE.md, TACIT.md, session-handoff.json, or any agent PLAYBOOK.

---

**Q1: Did I read this from a file or see it in command output — or did I conclude it?**

- If read directly → [FACT-READ], cite the file path and date. Write it.
- If calculated from reads → [FACT-COMPUTED], show the calculation. Write it.
- If Hyo stated it → [FACT-STATED Hyo DATE]. Write it.
- If concluded from an observation → [INFERENCE]. Do NOT write it as fact.
  Write only: what the raw observation was, and that the conclusion is unverified.

*The 2026-04-23 failure: "48 files = Mini logged out" was an inference written as fact.
The correct write would have been: [FACT-READ kai/ledger/] 48 delegate-failed files exist,
latest contains "Not logged in". [INFERENCE]: Mini may be logged out — NOT VERIFIED.*

---

**Q2: Does this contradict anything already in memory?**

- If YES → do not overwrite silently. Write: [CONTRADICTS prior claim from DATE: quote].
  Leave both. Surface it at session start for resolution.
- If NO → proceed to Q3.

---

**Q3: Is this claim still true right now, or was it true at some point in the past?**

- If verified within the last 24h → write with today's date.
- If verified 1–7 days ago → write with original date, flag for re-verification next cycle.
- If older than 7 days or unknown → tag as [STALE: DATE] and do not act on it
  until re-verified this session with a live read.

---

**Q4: If the next session's Kai reads this and acts on it — what is the worst-case outcome if it's wrong?**

- If the answer is "nothing serious" → write it.
- If the answer is "Kai asks Hyo to do something unnecessary" or "Kai skips a real problem"
  → do not write it as fact. Write it as [INFERENCE] with explicit uncertainty.
  High-stakes claims (system health, agent status, cost figures) require Q1 to pass before writing.

---

## STEP 3: DAILY INTEGRITY CHECK (automated)

`bin/memory-integrity-check.sh` runs as part of `bin/daily-maintenance.sh` (01:30 MT daily).

It scans KNOWLEDGE.md and session-handoff.json for:

1. **Untagged facts** — any line making a factual claim without a [FACT-*] or [INFERENCE] tag
   → flags to kai/ledger/memory-integrity.log, does NOT auto-delete (Kai reviews)

2. **Stale facts** — [FACT-*] entries older than 7 days without re-verification
   → appends [STALE] marker to the entry in-place

3. **[INFERENCE] entries** — any inference that has persisted >48h without verification
   → escalates to Hyo inbox: "Inference X has not been verified for 48h. Verify or remove."

4. **Contradiction check** — scans for entries that directly contradict each other
   → flags pairs to memory-integrity.log for human review

Output: `kai/ledger/memory-integrity.log` — checked at session start as part of hydration.

---

## STEP 4: SESSION BOUNDARY PROTOCOL

At the START of every session:

1. Read `kai/ledger/memory-integrity.log` — resolve any flagged issues BEFORE reading KNOWLEDGE.md
2. Treat any `[STALE]` or `[INFERENCE]` entry as UNCONFIRMED. Re-verify before acting.
3. If session-handoff.json is >48h old, treat all claims in it as [STALE] until verified.

At the END of every session:

1. Run `bin/memory-integrity-check.sh` before writing to KNOWLEDGE.md
2. Every fact written to KNOWLEDGE.md this session must be tagged
3. Session-handoff.json must be computed from LIVE READS (files), not from memory

---

## WHAT THIS PREVENTS

| Failure mode | Prevention |
|---|---|
| Wrong inference enters permanent memory | [INFERENCE] tag prevents acting on it; 48h expiry removes it |
| Stale fact treated as current | [STALE] tag + daily check flags it automatically |
| Silent contradiction (new fact overwrites old) | Gate Q2 forces explicit contradiction notation |
| Unverified audit finding becomes "known fact" | All audit outputs default to [INFERENCE] unless cited |
| Compaction summary carries wrong claims forward | [INFERENCE] entries marked as such in handoff; next session sees the tag |

---

## THE SPECIFIC FAILURE THIS ADDRESSES

The 2026-04-23 audit claimed "48 delegate failures = Mini logged out."
Under this protocol:
- The observation ("48 files, latest: 'Not logged in'") → [FACT-READ]
- The conclusion ("Mini is logged out") → [INFERENCE from 48-delegate-files]
- The inference would NOT be written to KNOWLEDGE.md
- If it had been, it would expire in 48h and require Hyo to verify before acting

Hyo's correction ("We are logged in") would immediately:
- Remove the [INFERENCE] entry
- Add [FACT-STATED Hyo 2026-04-23] Mini was logged in when Hyo confirmed at session end

---

## PROTOCOL VERSION HISTORY

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-04-23 | Initial — source tagging, 3 gates, daily check, session boundary protocol |
