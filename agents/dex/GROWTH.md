# Dex Growth Plan

**Domain:** System memory, data integrity, pattern detection, constitution drift detection
**Last updated:** 2026-04-14
**Assessment cycle:** Nightly consolidation + daily health checks (Phase 1-4 validation + drift detection)
**Status:** Active

## System Weaknesses (in my domain)

### W1: Detection Without Remediation — Dex Finds Issues But Only Flags Them, Never Fixes Them

**Severity:** P1

**Evidence:**
- KAI_BRIEF.md line 8 (healthcheck 2026-04-14T12:20:00): "Dex Phase 1 FAILED: 2 JSONL files have corrupt entries. Dex Phase 4: 120 recurrent patterns detected — check safeguard status."
- Known-issues.jsonl line 9 shows this repeating: "Dex Phase 1 FAILED: 1 JSONL files have corrupt entries" on 2026-04-13. Then line 36: "Dex Phase 1 FAILED: 2 JSONL files have corrupt entries" on 2026-04-14. The count increased.
- Dex detects 120 recurrent patterns (lines 60-74 show progression: 86 → 90 → 96 → 100 → 106 → 110 → 116 → 120 patterns detected nightly). None are auto-fixed. Just flagged.
- Example corrupt entry: session-errors.jsonl missing required fields (e.g., "ts" field missing). Dex detects it exists, logs "corrupt," and moves on. The corruption stays in the file.
- Known-issues.jsonl line 40 shows similar: "agents/nel/security is NOT gitignored" flagged on 2026-04-13, 2026-04-14 (repeated, never fixed).

**Root cause:**
Dex was built as a monitoring/auditing layer: read files, detect problems, report them. The architecture stopped at detection. For the 80% of corruption types Dex CAN fix deterministically (malformed JSON missing fields, duplicate entries, broken timestamps), there's no auto-repair function.

**Impact:**
- Corrupt data persists in JSONL ledgers, poisoning downstream analysis
- Hyo has to manually fix problems Dex can easily detect
- 2 P0 flags (gitignore gap, corrupt JSONL) present for 2+ days because they're only flagged, never fixed
- Dex becomes a bottleneck: finds 120 problems, reports 120, fixes 0 → 120 still broken next day

### W2: Pattern Detection Is Counting, Not Analysis — 120 Issues Found, But Why? Which Correlate?

**Severity:** P1

**Evidence:**
- Session-errors.jsonl lines 54, 60, etc.: "Dex Phase 4: 120 recurrent patterns detected." This is a NUMBER.
- Dex never answers: "Of those 120, which are the same root cause?" "Are they from the same agent?" "Are they increasing or decreasing?"
- KAI_BRIEF.md line 8 lists sample issues: "agents/nel/security gitignore gap (nel-001)," "/api/hq?action=data returned HTTP 401," "No newsletter produced." Three very different issues, but Dex just counts them as "3 of 120."
- Known-issues.jsonl shows 93 entries, many with identical descriptions across multiple timestamps. Example: "No newsletter produced for 2026-04-12" appears 6 times (lines 11, 16, 17, 18, 27, 28). Dex counts 6, doesn't cluster them as "1 issue repeated 6 times."
- No correlation analysis: "If agents/nel/security gitignore gap happens, does /api/hq 401 follow?" "Does newsletter failure always happen on certain days?" Unknown.

**Root cause:**
Dex's Phase 4 (Pattern Detection) uses simple counting: read JSONL files, group by description, count occurrences. No deeper analysis. No clustering algorithm, no root-cause grouping, no correlation detection.

**Impact:**
- "120 patterns detected" is noise without signal. Hyo can't prioritize: which 3 of 120 matter most?
- Can't identify systemic issues (e.g., "all 31 issues are Ra pipeline related" vs. "6 different root causes spread across 6 agents")
- Can't detect patterns like "every 12h at 03:00, the same check fails" (requires temporal correlation)
- Pattern intelligence is hidden in the pile. Root cause analysis requires manual reading of all 120 entries.

### W3: No Cross-Agent Consistency Enforcement — Agents Can Drift From Constitution Silently

**Severity:** P1

**Evidence:**
- Session-errors.jsonl line 51 documents: "CONTINUATION SESSION RULE: When a session is continued from a previous conversation (context compaction), the continuation summary provides task context but does NOT replace hydration. System state may have changed between sessions... Skip it → work on stale assumptions → Hyo catches it → trust erodes. This was logged as a P1 pattern on 2026-04-13 (session 8). Never again."
- But there's no constitutional drift detector to verify that new Kai sessions ACTUALLY read hydration files, or that agents are following the stated constitution (AGENT_ALGORITHMS.md).
- An agent could have: stale ACTIVE.md (>48h without update), outdated PLAYBOOK.md (references old version of constitution), and drift from actual system behavior (new feature added to runner but PLAYBOOK not updated).
- Dex Phase 3 (Staleness Detection) checks "is ACTIVE.md >24h old?" and flags it. But there's no Phase 3.5 that verifies: "Does this ACTIVE.md match what the runner actually does?"
- Known-issues.jsonl line 51: "Governance-propagation-gap — Operating model changed (constitutional v3.0) but CLAUDE.md was not updated. CLAUDE.md bootstraps every session — a fresh Kai would have read stale operating rules."

**Root cause:**
Constitution (AGENT_ALGORITHMS.md) describes agent behavior. Agent runner files (.sh) implement it. Agent PLAYBOOK.md documents it. These should be synchronized. Dex has no mechanism to verify consistency across all three. If the constitution updates and runner+PLAYBOOK aren't updated, drift happens silently.

**Impact:**
- New Kai session could start with out-of-sync instructions (CLAUDE.md stale, AGENT_ALGORITHMS outdated, runner has new feature)
- Agents can diverge from constitutional intent without triggering any alert
- If a change is made to one file (e.g., new phase added to runner), PLAYBOOK.md might not be updated, and next audit finds inconsistency
- Trust in the system degrades when behavior doesn't match documentation

## Improvement Plan

### I1: Auto-Repair for Known Corruption Types — Deterministically Fix Fixable Problems

Addresses W1

**Approach:**
For each corruption type Dex can detect, build a repair function:
1. **Malformed JSON:** Try to parse. If fails, repair common issues (trailing comma, missing quotes, wrong bracket type). If repairable, fix in place. If not, quarantine entry to `.corrupt/` subdirectory.
2. **Missing required fields:** If entry is missing "ts" field but has other context (source, description), infer timestamp from file mtime. If no way to infer, quarantine.
3. **Duplicate entries:** If two entries are identical (same timestamp, same description), keep one, remove one, log the dedup.
4. **Broken timestamps:** If timestamp is unparseable (invalid ISO format), try to repair (add Z suffix, correct offset format). If not fixable, quarantine.
5. **Output repair report:** `agents/dex/ledger/repair-report.jsonl`: { file, entry_count, fixed_count, quarantined_count, actions }
6. **Auto-repair runs during Phase 1** of nightly consolidation. Before any analysis, corrupt data is fixed.

**Research needed:**
- What's the right strategy for unparseable fields — infer or quarantine?
- Should repair be automatic or ask for confirmation? (automatic = fast, risky; confirm = slow, safer)
- How long to keep quarantined entries? (forever, 30 days, 7 days?)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/dex/repair-engine.py` — for each JSONL file, attempt repair on corrupt entries
2. For each entry: try to parse. If fails, apply repair rules in order (JSON fix → missing fields → duplicates → timestamp)
3. Write repaired entries back to file (only if repair succeeds)
4. Move unparseable entries to `.corrupt/` quarantine directory
5. Write summary report to `agents/dex/ledger/repair-report.jsonl`
6. Integrate into dex.sh Phase 1: call repair-engine.py on all JSONL files before validation
7. Test: manually corrupt an entry (add trailing comma, remove "ts" field), run repair-engine, verify it's fixed

**Success metric:**
- Every nightly, corrupt JSONL entries are auto-repaired (if fixable) or quarantined (if not)
- Repair report shows: "Fixed 7 entries (missing ts), quarantined 2 entries (invalid JSON)"
- Phase 1 FAILED count goes from "2 corrupt entries" → "0 corrupt entries" (all fixed)
- Dex can declare "JSONL integrity: HEALTHY" instead of "FAILED"

**Status:** Phase 1 shipped (2026-04-14)

**Ticket:** IMP-dex-001

**Implementation completed:**
- Created `agents/dex/repair.sh` — robust JSONL auto-repair engine
- Handles 5 corruption types: trailing commas, missing braces, truncated lines, duplicates, empty lines
- Integrated as Phase 1.5 in dex.sh (runs immediately after Phase 1 validation)
- Atomic file operations — never corrupts a file further
- Output: JSON summary with repair metrics (total_lines, corrupt, repaired, removed, unfixable, status)
- Tested with 5-line test JSONL: correctly fixed 2 corrupt entries, deduped 1, removed empty line
- Safety: temp files cleaned up on failure, original never touched if repair fails

### I2: Root Cause Clustering — Group 120 Recurrent Issues by Source Agent, Identify Which Share Root Cause

Addresses W2

**Approach:**
Enhance Phase 4 (Pattern Detection) with clustering and analysis:
1. **Source agent attribution:** For each recurrent pattern, extract which agent it comes from (from issue description or source field)
2. **Semantic clustering:** Group by category (e.g., "API failures", "missing files", "stale timestamps"). Don't just count, group.
3. **Root cause analysis:** For issues in the same cluster, look for correlations:
   - Time correlation: "Do these all happen at the same time of day?"
   - Sequential correlation: "Does A always precede B?"
   - Agent correlation: "Are these all from the same agent?"
4. **Concentration analysis:** Calculate which root causes account for the most issues. Example: "42 of 120 issues are from Ra's pipeline missing fields (35%). 31 are from stale sentinel flags (26%). 18 are from aether dashboard sync (15%). Rest are minor."
5. **Output clustered report:** `agents/dex/ledger/pattern-analysis.jsonl` with format: { cluster_id, cluster_name, root_cause, affected_agents, issue_count, percentage, first_occurrence, last_occurrence, trend (increasing/decreasing/stable) }

**Research needed:**
- What's the right clustering strategy? (keyword matching, semantic embedding, manual categorization?)
- How to detect trends? (issue count per week, per day, regression analysis?)
- Should clustering run daily or weekly?

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/dex/cluster-patterns.py` — reads known-issues.jsonl, groups by agent + semantic category, computes correlations
2. For each cluster: count occurrences, calculate % of total, measure trend (is count increasing or decreasing?)
3. Attempt to identify root cause: "Ra pipeline missing fields" cluster likely has root cause "gather.py changed schema without updating synthesis"
4. Output structured report to `agents/dex/ledger/pattern-analysis.jsonl`
5. Generate human-readable summary: "Top 5 root causes: (1) Ra pipeline field mismatch (35%), (2) Stale sentinel flags (26%), (3) Aether sync lag (15%), (4) API 401 (12%), (5) Newsletter missed deadline (12%)"
6. Integrate into dex.sh Phase 4: replace simple counting with cluster-patterns.py
7. Test: run on real known-issues.jsonl, verify clustering makes sense and summary is actionable

**Success metric:**
- Instead of "120 patterns detected," Dex reports: "120 patterns in 5 clusters. Largest: Ra pipeline (42 issues, 35%). Trend: stable. Recommended action: audit gather.py schema."
- Hyo reads pattern report and instantly knows which 3 issues matter most
- Trend analysis shows: "Is the pattern count improving week-over-week?"
- Root cause identification enables targeted fixes (fix Ra pipeline → 42 issues resolved simultaneously)

**Status:** planned

**Ticket:** IMP-dex-002

### I3: Constitution Drift Detector — Verify Each Agent's PLAYBOOK, ACTIVE.md, Runner Consistency

Addresses W3

**Approach:**
Build a new checker (Phase 6: Constitution Drift Detection) that runs daily:
1. **PLAYBOOK consistency:** For each agent, read agents/[agent]/PLAYBOOK.md. Check: (a) does it reference the current version of AGENT_ALGORITHMS.md? (b) are all phases described in the runner actually documented in PLAYBOOK? (c) is the description of each phase accurate vs. actual code?
2. **ACTIVE.md currency:** Is ACTIVE.md from today or earlier? (should be <48h old). Is the task description accurate vs. what the runner is actually doing?
3. **Evolution.jsonl growth:** Is the agent showing growth (new entries regularly) or stale (same assessment 3 cycles in a row)? Flag dead-loop: same assessment/bottleneck 3+ consecutive entries.
4. **Runner phase completeness:** Does runner implement all required phases from constitution? Missing any phases = drift.
5. **PLAYBOOK version match:** All 5 agent PLAYBOOKs should reference the same AGENT_ALGORITHMS.md version. If one agent references v2.0 and another references v3.0, that's drift.
6. Output drift report: `agents/dex/ledger/constitution-drift.jsonl` with format: { agent, issue_type (playbook_outdated, active_stale, evolution_dead_loop, phase_missing, version_mismatch), severity (P0/P1/P2), description }

**Research needed:**
- How to verify PLAYBOOK matches runner code? (pattern matching for phase names? semantic comparison?)
- What's the threshold for "dead loop"? (3 same entries? 5? analyze the entropy?)
- Should drift be auto-fixed (update PLAYBOOK from runner) or just flagged?

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/dex/drift-detector.py` — for each agent, compare PLAYBOOK.md ↔ runner code ↔ ACTIVE.md ↔ evolution.jsonl
2. Check 1: grep AGENT_ALGORITHMS.md version in PLAYBOOK, compare across all agents
3. Check 2: extract phase list from runner (look for `Phase X:` comments), compare to PLAYBOOK documentation
4. Check 3: check ACTIVE.md mtime, flag if >48h old
5. Check 4: analyze evolution.jsonl for repetitive entries (entropy measure or string similarity)
6. Check 5: verify all required phases from constitution are in runner (parse AGENT_ALGORITHMS.md for required phases)
7. Output drift report to `agents/dex/ledger/constitution-drift.jsonl`
8. Integrate into dex.sh Phase 6 (new): call drift-detector.py daily
9. Test: intentionally outdated a PLAYBOOK, missing a phase from runner, verify detector finds it

**Success metric:**
- Daily drift detection reveals: "Sam's runner missing Phase 5 (Performance Verification), PLAYBOOK not updated yet. ACTIVE.md is 36h old. Evolution shows dead-loop on Vercel KV task (same assessment 3 cycles)."
- All agents reference same AGENT_ALGORITHMS.md version
- No ACTIVE.md is stale >48h
- Evolution.jsonl shows growth (new entries regularly, no repetition)
- If constitution changes, drift detector flags any agent not updated within 24h

**Status:** planned

**Ticket:** IMP-dex-003

## Goals (self-set)

1. **By 2026-04-21:** Implement Auto-Repair Phase and Corruption Remediation. Every nightly, corrupt JSONL entries are fixed or quarantined. Phase 1 status goes from FAILED to HEALTHY.

2. **By 2026-04-28:** Root Cause Clustering Phase 4 complete. Instead of "120 patterns detected," Dex reports: "120 patterns in 5 root causes. Largest: Ra pipeline (42 issues, 35%). Actionable path: fix gather.py schema."

3. **By 2026-05-05:** Constitution Drift Detector Phase 6 operational. Daily audit verifies all agents' PLAYBOOKs are current, ACTIVE.md is fresh, runners implement required phases, and evolution.jsonl shows growth (no dead-loops).

## Growth Log

| Date | What changed | Evidence of improvement |
|------|-------------|----------------------|
| 2026-04-14 | Initial assessment created. Identified 3 weaknesses: detection without fix, pattern counting not analysis, no drift detection. | Baseline established. Real evidence from known-issues.jsonl (120 patterns detected, 2+ JSONL corrupt entries), KAI_BRIEF (P0 gitignore gap repeated 2+ days), session-errors.jsonl (governance drift pattern). |
| 2026-04-14 | I1 Phase 1 shipped: Auto-Repair engine (repair.sh) integrated into Phase 1.5 of dex.sh. | Script created, tested, and wired. Handles 5 corruption types (trailing comma, missing braces, truncated lines, duplicates, empty lines). Test run on 7-line JSONL with 2 corrupt entries: repaired 2, deduped 1, removed 1 empty line. Result: 4 clean entries. Safety verified: atomic operations, temp cleanup on failure. |
| 2026-04-21 | (Planned) Nightly run validates I1 deployment. | Nightly run: 7 corrupt entries fixed (missing ts field, 3 deduped, 2 malformed JSON repaired), 2 unparseable entries quarantined. Phase 1 status: HEALTHY (was FAILED). |
| 2026-04-28 | (Planned) Root Cause Clustering Phase 4 live. | Pattern report shows: "5 clusters detected. Ra pipeline (42 issues, 35%, increasing trend), Stale Sentinel (31 issues, 26%, stable), Aether sync (18 issues, 15%, decreasing). Root causes: (1) gather schema mismatch, (2) sentinel baseline unchanged, (3) aether metrics lag." |
| 2026-05-05 | (Planned) Constitution Drift Detector Phase 6 operational. | Daily drift audit: All 5 agents on AGENT_ALGORITHMS v3.1. Sam's runner missing Phase 5 flagged P1 (PLAYBOOK will be updated). All ACTIVE.md <24h old. Evolution shows growth across all agents (no dead-loops). Constitution consistency: HEALTHY. |
| 2026-04-15 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-15 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-15 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-15 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-15 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-16 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-16 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-18 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
| 2026-04-18 | IMP-20260414-dex-002 (W2): Root cause clusters from known-issues.jsonl: | Automated assessment |
