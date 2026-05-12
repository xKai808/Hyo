# Daily Bottleneck Audit — 2026-05-12

**Generated:** 2026-05-12T08:06:20Z
**Issues:** 0 | **Warnings:** 5

## Agent Health

| Agent  | Status |
|--------|--------|
| nel    | OK |
| sam    | OK |
| ra     | OK |
| aether | OK |
| dex    | WARN |

## Queue

- Pending: 0
- Failed: 53
- Completed: 9952

## Bottlenecks Found


- dex: no runner output for today (2026-05-12)
- sam: PRIORITIES.md stale for 20d
- ra: PRIORITIES.md stale for 20d
- aether: PRIORITIES.md stale for 20d
- dex: PRIORITIES.md stale for 20d

## Actions Taken

None

## Automation Gaps


- KAI_TASKS has 6 open [AUTOMATE] items — review for quick wins

---

*Next audit: 2026-05-13*

---

## Manual Findings — Kai (scheduled task supplement)

Generated: 2026-05-12T08:10:00Z

### Recurrence: HYO_ROOT default bug (3rd consecutive day)

`kai/queue/daily-audit.sh` line 13 defaults `ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"`.
In sandbox sessions `$HOME=/sessions/<id>`, so the fallback resolves to a nonexistent stub.
First run today produced **5 phantom FAILs, 8 phantom GAPs**; re-run with `HYO_ROOT` explicit
produced the real result above (0 issues, 5 warnings).

Prior flags for this exact bug:
- 2026-05-10: flag-kai-009 (still DELEGATED)
- 2026-05-11: flag-kai-011 → kai-002 (still DELEGATED)
- 2026-05-12: flag-kai-013 (today, just filed)

Fix is one line: `ROOT="${HYO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"`
— resolve relative to script location, not `$HOME`. Three days of phantom audits because
this hasn't been merged.

### Pathway breaks (input → processing → output → external → reporting)

| Agent | Break point | Evidence |
|---|---|---|
| ra | output→external | Newsletter pipeline: no `2026-05-12.input.md`, no script for today. Last input file is 2026-05-11. ra-002/003/004 stuck DELEGATED for 0/3/6 days; AUTO-REMEDIATE does not actually run the pipeline. |
| sam | processing→output | sam-005 DELEGATED since 2026-05-01 (11 days) — nel queue-drain investigation never started. |
| nel | reporting→memory | 16 queued flags in `agents/nel/ledger/ACTIVE.md`, oldest from 2026-04-28 (14 days untouched). |
| dex | input→processing | No runner output for today; flag-dex-001 from 2026-05-01 still queued. |

### Stale DELEGATED summary (>2 days)

```
nel:    2 items (oldest 2026-05-06, 6d)
sam:    1 item  (oldest 2026-05-01, 11d)
ra:     2 items (oldest 2026-05-06, 6d)
aether: 0
dex:    0
```

### Queue stats

- Pending: 0
- Failed: 53 (worth a Sam scan — failure cluster never investigated)
- Completed: 9,952

### KAI_TASKS [AUTOMATE] backlog: 6 open

The 6 open `[AUTOMATE]` items reference "Audit B2/B3/B7/B8/B12" — undated, but the audit
they reference is months old. Top-2 quick wins worth promoting:
- B12 sentinel: "no newsletter by 06:00 MT" — directly addresses today's recurring break
- B2 `kai hydrate`: would compress 9 hydration reads into 1; biggest token-cost win

### P0/P1 dispatched this audit

- flag-kai-013 (P1) — HYO_ROOT bug recurrence + auto-remediation no-op recurrence

### Root cause (one sentence)

**The auto-remediation pipeline records DELEGATED but does not execute the work**, so flags
keep accumulating without ever transitioning to COMPLETED — and the very fixes that would
break the loop (HYO_ROOT one-liner, newsletter sentinel, queue-drain investigation) are
themselves trapped in that same DELEGATED-forever state.

