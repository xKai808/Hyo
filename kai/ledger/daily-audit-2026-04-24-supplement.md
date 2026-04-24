# Daily Bottleneck Audit — 2026-04-24 (Supplement)

**Generated:** 2026-04-24T08:09:00Z (02:09 MT)
**Auditor:** Kai (scheduled-task kai-daily-audit)
**Base report:** [daily-audit-2026-04-24.md](./daily-audit-2026-04-24.md) — Issues: 0, Warnings: 0
**Supplement issues raised:** 6 P1, 2 observations

This supplement extends the base audit with findings the automated `daily-audit.sh`
script did not surface. The base script reports 0 issues because all `ACTIVE.md`
files are fresh and no runner is missing — but the *quality* of those files,
the inbox, the ticket ledger, and the queue reveal real bottlenecks.

---

## Summary (4-line status)

1. **Shipped since last session:** agent ACTIVE.md updates (all 5 agents, within 2h), aether-001 P0 SLA-breached ticket logged, autonomous loop emitting RED health pages every ~15min.
2. **Top of KAI_TASKS:** 6 open `[AUTOMATE]` items. The "no newsletter by 06:00 MT sentinel" is itself flagging *before* 06:00 MT deadline has passed — false-positive pattern.
3. **Recommendation for next 15 minutes:** Let the 03:00 MT Ra pipeline run; verify newsletter + daily reports land by 06:00; patch the duplicate ticket write and the premature newsletter flag; triage 54 unread hyo-inbox items.
4. **Queue active:** Base audit reports OK for all 5 agents. Dispatcher queue has 0 pending, 23 failed (oldest 270h), 2007 completed (cleanup triggered but not reducing).

---

## Bottlenecks Found (real, systemic)

### B1 — [P1] Duplicate P0 ticket writes (tickets.jsonl non-idempotent)
`TASK-20260424-aether-001` ("Self-improve: empty research for aether/W1 — Claude Code returned nothing") appears **multiple times** in `kai/tickets/tickets.jsonl`. Every ticket re-check is re-appending the ticket instead of updating status. This inflates P0 counts (audit shows 6 open P0s; actually likely 1 unique), floods the SLA enforcer, and breaks any consumer that trusts the ledger as a set rather than a log.

- **Flag dispatched:** aether-002 (via flag-kai-001) — routed to aether because aether is the closest owner
- **Fix direction:** ticket write path must be upsert-by-id, not append. Audit `bin/ticket.sh` and any agent runner that re-opens the same ticket.

### B2 — [P1] Nel duplicate flag generation per cycle
`agents/nel/ledger/ACTIVE.md` has 7 queued flags (`flag-nel-001..007`); 5 of them are dupes of two patterns:
- 3× "Sentinel: 2 project(s) with test failures" (flag-nel-002, -005, -006)
- 3× "Found 20 broken documentation links" (flag-nel-001, -004, -007)
- 1× "No newsletter produced for 2026-04-24" (flag-nel-003) — created at 20:09 MT on 2026-04-23, *before* the 06:00 MT deadline for the 2026-04-24 newsletter had arrived.

Nel is re-raising the same flag every cycle instead of deduping against open flags. Fix: dedup by (title, created-within-24h) before creating.

- **Flag dispatched:** kai-001 (via flag-kai-002)

### B3 — [P1] Queue cleanup not reducing completed items
autonomous log Phase 5 at 02:01 MT says: `✗ Queue hygiene: 2006 items — triggering cleanup`. After the cleanup run, `kai/queue/completed/` contains **2007** items. Cleanup is not actually pruning. Either the cleanup command is no-op or it's running against the wrong path.

- **Flag dispatched:** kai-002 (via flag-kai-003)
- **Verify:** read `kai/queue/cleanup.sh` (if it exists); confirm threshold and the delete path.

### B4 — [P1] Hyo-inbox flooded (54 unread URGENT)
`kai/ledger/hyo-inbox.jsonl` has **54 unread** items. The majority are duplicate `ticket-sla-enforcer` pages (P0 SLA BREACH for the same TASK-20260424-aether-001, different "Xh overdue" variants) and the autonomous loop's `System health: RED (25/100)` paged every ~15 minutes.

Two classes of duplicate:
- **SLA enforcer:** writes a new URGENT line every recheck — should upsert per task_id and suppress re-pages within N minutes.
- **Autonomous health page:** writes URGENT every run where score < threshold — should debounce until score changes or 1h elapsed.

- **Flag dispatched:** kai-003 (via flag-kai-004)

### B5 — [P1] All 5 agents in dead-loop (GUIDANCE tickets present)
Every agent ACTIVE.md has a `[GUIDANCE]` ticket with the text: *"Your last 3 cycles had the same assessment. What's preventing progress? What would you try differently?"* This was delegated at 07:52 UTC (01:52 MT) across all agents simultaneously — which means the dead-loop detector fired at once on everyone. Either (a) a real system-wide stagnation, or (b) the detector is over-sensitive / not resetting after a cycle with new output.

- **Flag dispatched:** kai-004 (via flag-kai-005)
- **Probe:** sample evolution.jsonl for each agent, look at the last 3 entries — are they actually identical, or just classified as such?

### B6 — [Observation] Kai has no runner; kai-targeted flags are dead-letters
Every flag routed to `kai` returns:
> WARN: no runner at agents/kai/kai.sh — kai cannot be event-triggered
> Queued re-check: recheck-flag-kai-N

Event-driven cascade works for every agent *except* Kai. The re-check queues, but no worker will process the self-referential flag. Kai's "flags to self" live in `ACTIVE.md` and get picked up only when a live Kai session reads it. In headless runs (this scheduled audit), the flag sits.

- **Decision:** either (a) stub `agents/kai/kai.sh` to write to `KAI_TASKS.md` + exit, or (b) change `bin/dispatch.sh` to write Kai-targeted flags directly to the task file.
- **Not dispatched** (would recurse). Logged here for the next interactive session.

### B7 — [Observation] Premature newsletter sentinel
Nel Phase 1 flags "No newsletter produced for 2026-04-24" at **20:09 MT on 2026-04-23** — before today's 03:00 MT pipeline had even run. The autonomous health-check script (runs every 15min) carries the same false-positive into its score, driving RED health and the repeated hyo-inbox pages in B4.

The `[AUTOMATE]` item in KAI_TASKS line 236 specifies the check should fire *"if not by 06:00 MT"* — the current implementation is firing 10 hours early.

- **Fix direction:** the sentinel must compare `today` to Mountain-time date AND enforce `$(TZ=America/Denver date +%H) -ge 06` before flagging.
- Not dispatched (ties into B4 cleanup; fix once, not twice).

---

## Automation Gaps

Base script flagged: *"KAI_TASKS has 6 open [AUTOMATE] items — review for quick wins"*.

Open `[AUTOMATE]` items (from KAI_TASKS.md grep):
1. L235 — Post-deploy API test via MCP
2. L236 — No-newsletter-by-06:00 sentinel **(see B7 — this is already built but broken)**
3. L237 — kai-context-save scheduled task (every 30 min)
4. L238 — `kai hydrate` command (concat hydration files)
5. L261 — Convert watch-deploy.sh → launchd KeepAlive agent
6. L264 — UTC timestamp check to Nel (flag Z-suffix in hq-state.json)

Recommendation: elevate L236 to P1 (it already exists and is mis-triggering) and L264 (timezone hygiene supports every other report).

---

## Queue State

- **Pending:** 0 (healthy)
- **Failed:** 23 items, oldest 270h (~11 days). Candidates for archive: `recheck-1776044635.json`, `install-mcp-{github,reddit,youtube}.json` (all 198h old, probably stale MCP install attempts).
- **Completed:** 2007 items — cleanup fires but doesn't reduce (B3).

---

## Actions Taken

- **Flags dispatched (5):** `flag-kai-001` through `flag-kai-005` via `bin/dispatch.sh flag kai P1 "..."`. One (`flag-kai-001`/ticket bug) routed to aether; the other four self-route to kai and will sit until a live Kai session reads `KAI_TASKS.md` (see B6).
- **Supplement written:** this file.
- **No writes** to agent runners, tickets.jsonl, hyo-inbox, or queue — those require human approval of the fix strategy (B1/B3/B4 especially).

---

## Success criteria check

- [x] Audit report written (base + this supplement)
- [x] P1 issues dispatched via `bin/dispatch.sh flag` (5)
- [x] No agent silent >48h without explanation (all ACTIVE.md ≤2h old)
- [x] Automation gaps identified and logged (6 items in KAI_TASKS, 2 flagged here as priority)
- [ ] P0s — **none triggered by this audit**. The only "open P0" count (6) is a tickets.jsonl dedup artifact — it's 1 real ticket (aether-001) written 6× (B1).

---

## Next audit
2026-04-25 (scheduled-task `kai-daily-audit`, 02:00 MT)
