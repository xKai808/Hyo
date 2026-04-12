# Ledger Agent — Operational Priorities

**Last updated:** 2026-04-12  
**Agent:** ledger.hyo v1.0.0

---

## Priority 0 (P0) — Critical

### P0: JSONL Integrity Validation
- **Goal:** Ensure all .jsonl ledger files are structurally sound and can be reliably parsed
- **Scope:** kai/ledger/*.jsonl, agents/*/ledger/log.jsonl, known-issues.jsonl, simulation-outcomes.jsonl
- **Cadence:** Daily (Phase 1 of ledger.sh)
- **Success criteria:**
  - All JSONL files parse without errors
  - All entries have required fields: ts, action/type, agent
  - No truncated or corrupt lines
- **Failure handling:** Dispatch P0 flag to Kai immediately; do not proceed with other phases until fixed
- **Tool:** ledger.sh Phase 1 (INTEGRITY)

---

## Priority 1 (P1) — High

### P1: Stale Task Detection
- **Goal:** Identify tasks that have been delegated but not updated for >72 hours, escalate for unblocking or closure
- **Scope:** All ACTIVE.md files in kai/ledger/, agents/*/ledger/
- **Cadence:** Daily (Phase 2 of ledger.sh)
- **Definition of stale:** Delegated timestamp >72 hours ago with no recent status update
- **Action:** Flag stale tasks to Kai via dispatch escalate for follow-up
- **Success criteria:**
  - All open tasks with age >72h are identified and flagged
  - Kai receives actionable list for unblocking
- **Tool:** ledger.sh Phase 2 (STALE TASKS)

### P1: Log Compaction Automation
- **Goal:** Archive old log entries (>30 days) into dated archive files to keep active logs lean and queryable
- **Scope:** log.jsonl files in all ledgers (kai, nel, ra, sam, ledger)
- **Cadence:** Weekly (Phase 3 of ledger.sh, runs during daily execution but targets 30-day threshold)
- **Archive naming:** log-archive-YYYY-MM.jsonl (one per month per ledger)
- **Retention:** Keep active log trimmed to ~7-14 days of entries
- **Success criteria:**
  - All entries >30 days old are moved to archive
  - Recent entries remain in active log.jsonl for fast queries
  - Archive files are readable and indexed
- **Tool:** ledger.sh Phase 3 (COMPACTION)

---

## Priority 2 (P2) — Medium

### P2: Pattern Detection & Recurrence Tracking
- **Goal:** Cross-reference known-issues.jsonl with recent log entries to detect if resolved issues have re-occurred
- **Scope:** known-issues.jsonl vs recent entries in all agent logs
- **Cadence:** Daily (Phase 4 of ledger.sh)
- **Detection method:** Substring matching on description/title fields; flag if same pattern found in logs within 7-day window
- **Action:** Flag recurrence to Kai with details on safeguard status (when was prevention deployed, is it still active)
- **Success criteria:**
  - All known patterns are tracked
  - Recurrences are detected within 24h of happening
  - Safeguard cascade is triggered if pattern recurs
- **Tool:** ledger.sh Phase 4 (PATTERNS)

---

## Priority 3 (P3) — Low

### P3: Enhanced Pattern Detection & Regression Tracking
- **Goal:** Improve pattern detection algorithm to detect higher-order patterns (N-grams, sequence patterns, similar error messages)
- **Scope:** Full cross-agent log analysis
- **Cadence:** Weekly (separate enhanced analysis, not part of daily ledger.sh)
- **Methods:**
  - Fuzzy string matching for similar error messages (Levenshtein distance)
  - Sequence analysis: tasks that always fail in same order
  - Causality detection: flag task A always causes task B to fail
- **Integration:** Results feed into safeguard recommendations
- **Success criteria:**
  - Detects patterns missed by substring matching
  - Provides actionable root-cause insights
  - Reduces false positives via fuzzy matching
- **Status:** Future enhancement (backlog)

---

## Operational Guidelines

### Daily Execution (ledger.sh)
1. **Phase 1: Integrity** — Must pass. If corrupt entries found, dispatch P0 flag and halt.
2. **Phase 2: Stale Tasks** — Scan and flag. Prepare list for Kai escalation.
3. **Phase 3: Compaction** — Archive old entries. Run even if phases 1-2 flag issues.
4. **Phase 4: Patterns** — Detect and flag. Trigger safeguard cascade if needed.
5. **Phase 5: Report** — Write final report and dispatch summary to Kai.

### Trigger Conditions
- **P0 flag:** Integrity failure (corrupt JSON, missing required fields)
- **P1 flag:** >0 stale tasks OR >0 recurrent patterns
- **Safeguard cascade:** When known pattern recurs → Nel audit + Sam test coverage + memory log update

### Integration with dispatch.sh
- `dispatch flag ledger <severity> <title>` — escalate issues to Kai
- `dispatch report <task_id> <status> <result>` — acknowledge completion and provide details
- `dispatch safeguard <issue_id> <description>` — trigger parallel prevention (Nel + Sam + memory)

### Known Limitations & Mitigations
- **Limitation:** Substring matching for patterns can produce false positives
  - *Mitigation:* Manual review by Kai before declaring pattern recurrence
- **Limitation:** Stale task detection relies on ACTIVE.md being kept current
  - *Mitigation:* Kai is responsible for updating ACTIVE.md; Ledger flags if detected as stale
- **Limitation:** Compaction timing can be affected by large log files
  - *Mitigation:* Run compaction during low-activity hours (03:00 MT daily)

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **JSONL integrity** | 100% pass rate | Daily Phase 1 report |
| **Stale task detection** | <24h latency | Time from task becomes stale to flag sent |
| **Compaction execution** | 100% of eligible entries archived | Entries in log.jsonl aged <30 days |
| **Pattern detection accuracy** | >90% precision | Manual review of flagged patterns |
| **Dispatch responsiveness** | Kai response <2h to P1 flags | Mean time from flag to action |

---

## Contact & Escalation

**Agent:** ledger.hyo v1.0.0  
**Reports to:** Kai (CEO)  
**Escalation path:** dispatch flag → Kai review → dispatch safeguard (if needed)  
**Schedule:** Daily 03:00 MT (after nightly consolidation)  
**Manual invocation:** `kai ledger [validate|stale|compact|patterns|report]`
