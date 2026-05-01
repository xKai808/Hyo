# Daily Bottleneck Audit — 2026-04-29 — SUPPLEMENT

**Generated:** 2026-04-29T08:09Z (sandbox audit; supplement to autorun)
**Severity:** CRITICAL — primary audit returned 0/0 but real state is RED

## Why a supplement

The scheduled `daily-audit.sh` autorun reported **5 issues / 8 warnings** with all
agents marked FAIL — entirely false. Re-running with `HYO_ROOT=` set explicitly
returned 0/0. Neither result reflects reality. The script is structurally blind
to the real bottlenecks. This supplement records what's actually broken.

## 1. Recurring audit-script bug (logged 5×, never fixed)

`kai/queue/daily-audit.sh:13` defaults `ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"`.
When the scheduled task fires inside the Cowork sandbox, `$HOME` resolves to a
dead path (e.g. `/sessions/<name>/Documents/...`) — every agent's ACTIVE.md
appears MISSING and the report is written to an unreachable location.

Logged in `kai/ledger/known-issues.jsonl`:
- 2026-04-20 (flag-kai-005)
- 2026-04-21 (flag-kai-001)
- 2026-04-22 (flag-kai-002) — explicit fix instructions provided
- 2026-04-25 (flag-kai-003)
- 2026-04-27 (flag-kai-003)
- 2026-04-29 (this run)

Six recurrences. Logged "prevention: Nel audit + Sam test coverage deployed" —
prevention does not work. Per CLAUDE.md "every error produces a gate, not just
a rule": this needs a structural fix, not another known-issues entry.

**Fix (paste into Sam queue):**
```bash
# kai/queue/daily-audit.sh — replace line 13
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${HYO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
```
This walks up from the script's own location; works in sandbox AND on Mini
without depending on `$HOME` or environment exports.

## 2. Audit script's other blind spots (real bottlenecks not detected)

The script reported "0 issues" while the system shows:

### 2a. 16 P0 tickets open (verified-state.json)
Report-missing tickets across three days for nel/sam/ra/aether plus kai schema:

| Day | Agents missing report |
|---|---|
| 2026-04-26 | ra, nel, sam (each 47–51h overdue, P0 SLA breach) |
| 2026-04-27 | nel, ra, sam, aether, kai (schema), dex (SICQ) |
| 2026-04-28 | nel, sam, ra, aether, kai (schema), dex (SICQ) |

The audit script checks "today's runner output" but does not surface
historical missing reports as P0. That's how 16 P0s went unnoticed by
the audit even after a clean run.

### 2b. System health RED, sustained overnight
`hyo-inbox.jsonl` shows 18× URGENT messages from `kai-autonomous`:
- 10× "System health: RED (score: 28/100)"
- 8× "System health: RED (score: 25/100)"

Audit script does not read kai-autonomous health score.

### 2c. Newsletter pipeline failure (last night)
6× URGENT messages from `kai-autonomous`:
- "Newsletter still missing at 21:40/21:55/22:10/22:25/22:40/22:55 MT.
  Ra pipeline re-queued. May need API keys checked."
The "may need API keys checked" is a [NEEDS HYO] action that has no
formal flag in any ACTIVE.md — only buried in inbox.

### 2d. SICQ all below minimum (verified-state.json)
- nel: 20/100 (CRITICAL)
- sam: 45/100, kai: 50/100, ra: 55/100, aether: 60/100
All under their floors. `system_healthy: false`. No mention in audit report.

### 2e. report_freshness for today
`published_today: [agent-reflection, self-improve-report]`
`missing_today: [aether-daily, morning-report, nel-daily, ra-daily, sam-daily]`
At 08:09Z the morning report (05:00 MT trigger, 07:00 MT completeness
check) is already overdue. Five daily reports missing. Audit reports OK.

## 3. Pathway breaks (input → processing → output → external → reporting)

| Stage | Status |
|---|---|
| Queue input (kai/queue/pending) | OK — 0 pending |
| Queue failures | DEGRADED — 34 failed (>30 day backlog including aurora-* from 04-21) |
| Agent runners | DEGRADED — runner outputs missing for 04-26/27/28 across nel/sam/ra/aether |
| HQ feed publication | DEGRADED — only 2 of 7 expected entries published today |
| External (Vercel/email) | UNKNOWN — newsletter API keys flagged for check overnight |
| Reporting (HQ) | DEGRADED — morning report not generated |

## 4. KAI_TASKS [AUTOMATE] open items (6, ages need verification)

Lines 241–270 of KAI_TASKS.md. **Highest priority given today's pattern:**

> Line 242: "Add 'no newsletter by 06:00 MT' sentinel check. In nel.sh
> Phase 1, check if today's newsletter .md exists. If not by 06:00, flag P1."

This [AUTOMATE] is the exact gate that would have caught last night's failure
before kai-autonomous spammed the inbox 6×. Promote to P1 next-action.

## 5. Stale items in pending queue
None. `kai/queue/pending/` is empty (clean).

## 6. [NEEDS HYO] flags
None tagged in agent ACTIVE.md files. But "API keys may need checking"
(re: newsletter, last night) is a de-facto Hyo action with no formal flag.
**Recommendation:** Ra should auto-flag `[NEEDS-HYO]` when API auth fails,
not only emit URGENT inbox messages.

## Actions Taken (this run)

1. Wrote this supplement.
2. Updated `kai/ledger/ACTIVE.md` with audit findings (separate edit).
3. Attempted to dispatch P1 flag for the recurring audit-script bug;
   result captured at the bottom of `kai/ledger/ACTIVE.md`.

## Recommended next session priorities (Kai)

1. **P0 — Patch `kai/queue/daily-audit.sh:13`** with SCRIPT_DIR-relative ROOT.
   Same change has been pending since 04-22. Stop logging, start patching.
2. **P0 — Burn down the 16 P0 ticket backlog.** Either close obsolete tickets
   (reports are 3 days stale, they cannot be retroactively published) or
   write a backfill script. The backlog is desensitizing the SLA enforcer.
3. **P1 — Implement KAI_TASKS line 242** (newsletter sentinel by 06:00 MT).
4. **P1 — Hyo action:** confirm Ra newsletter API key status (OPENAI/email).
5. **P1 — Audit script self-coverage:** the script should warn if its own
   ROOT differs from the canonical mount (sanity self-check at startup).
