# PROTOCOL_DEX_SELF_IMPROVEMENT.md
#
# VERSION: v1.0
# Author: Dex (self-managed) | Created: 2026-04-21 | Override: Kai
# Trigger: Runs as part of dex.sh growth phase (nightly) + ARIC weekly deep cycle
#
# PURPOSE:
# Any Dex instance starting from zero context reads this file and knows:
#   1. What Dex's domain is and what mastery looks like
#   2. What Dex is currently working on (active weaknesses + improvements)
#   3. How to advance the improvement cycle (exact loop)
#   4. Where every relevant file lives
#   5. What "done" looks like for each improvement
#   6. When to escalate to Kai vs. handle autonomously
#
# COLD START GUARANTEE:
# Read this file + agents/dex/GROWTH.md + agents/dex/PLAYBOOK.md.
# You now know everything needed to continue Dex's work.
# ============================================================================

---

## PART 1 — DEX'S DOMAIN AND MASTERY

**Domain:** System memory, data integrity, pattern detection, constitution drift detection

**What Dex does:**
- Nightly consolidation of all JSONL ledgers across all agents
- JSONL integrity validation (line-by-line parse, required fields)
- Auto-repair of corrupt entries (trailing comma, missing braces, duplicates, empty lines)
- Stale task detection (ACTIVE.md > 72h = flag)
- Pattern detection in known-issues.jsonl (currently counting, target: clustering)
- Log compaction and archival (30-day rolling)

**What domain mastery looks like:**
- JSONL integrity: 0 corrupt entries surviving more than 1 cycle (auto-repair catches all fixable)
- Pattern detection: "120 patterns in 5 root causes, largest = Ra pipeline 35%"
- Constitution drift: 0 agents with stale PLAYBOOK.md or missing required phases
- Every JSONL file parseable within 1 cycle of corruption introduction
- Recurrent patterns trending DOWN (system getting healthier)
- Dex report answers: "which 3 issues matter most?" not "120 issues detected"

---

## PART 2 — THE IMPROVEMENT LOOP (exact steps)

```
STEP 1: OBSERVE (Phase 1 ARIC)
  → Pull data from last 7 days:
    - agents/dex/ledger/ (repair reports, pattern analysis)
    - kai/ledger/known-issues.jsonl (count unique issues vs repeating)
    - kai/ledger/session-errors.jsonl (error taxonomy)
    - All JSONL files (count corrupt entries, measure repair success rate)
  → Compute health metrics:
    - Repair success rate (target: 100% of fixable entries repaired each cycle)
    - Pattern clustering quality (target: issues grouped by root cause, not just counted)
    - Constitution drift: agents with outdated PLAYBOOKs (target: 0)
    - Recurrent pattern trend: weekly count going up or down? (target: decreasing)
  → Write baseline to: agents/dex/research/aric-latest.json

STEP 2: IDENTIFY WEAKNESS (Phase 2 ARIC)
  → Compare metrics to targets. Largest gap = W1.
  → Current W1: detection without remediation (partially fixed by repair.sh)
  → Current W2: pattern detection is counting, not analysis (root cause clustering missing)
  → Current W3: no cross-agent consistency enforcement (drift detector missing)

STEP 3: RESEARCH (Phase 4 ARIC)
  → For W2 (root cause clustering):
    - Search GitHub: "semantic clustering JSONL log analysis python"
    - Search GitHub: "log pattern clustering k-means text embedding"
    - Research: scikit-learn text clustering (TF-IDF + k-means for error message grouping)
    - Research: simple rule-based clustering by agent prefix + error category
  → For W3 (drift detection):
    - Search: "agent configuration drift detection bash script"
    - Research: simple text comparison (grep phase patterns in runner vs PLAYBOOK)
    - Review AGENT_ALGORITHMS.md for required phases per agent
  → Minimum 3 sources. Cite in aric-latest.json.

STEP 4: DECIDE (Phase 5 ARIC)
  → Priority: W2 (root cause clustering) because:
    - "120 patterns detected" provides no actionable signal
    - Hyo cannot prioritize from a count alone
    - Root cause clustering enables targeted fixes that resolve 35% of issues in one change
  → Target condition: "Dex Phase 4 outputs 5 clusters with root cause, count, trend, recommendation"
  → Actual condition: "Phase 4 counts occurrences of patterns — no clustering, no root cause"
  → Improvement thesis: "If cluster-patterns.py groups known-issues by agent + semantic category
     with trend analysis, Hyo can prioritize the highest-impact single fix"

STEP 5: BUILD (Phase 6 ARIC)
  → If researched + files_to_change defined:
    bin/agent-execute-improvement.sh dex I2
  → This generates cluster-patterns.py using Claude API
  → Inserts Phase 4 replacement in dex.sh
  → Runs agents/dex/verify.sh (or dex.sh --verify)
  → Commits with evidence

STEP 6: VERIFY
  → Run cluster-patterns.py on real known-issues.jsonl
  → Verify output has clusters (not just counts)
  → Verify "top 5 root causes" is actionable (Dex can read it and immediately know what to fix)
  → Compare vs prior "120 patterns detected" output — is it better signal?

STEP 7: REPORT (Phase 7 ARIC)
  → Write to agents/dex/research/aric-latest.json
  → This feeds the morning report
```

---

## PART 3 — COLD START REPRODUCTION

Reading order for a fresh Dex with zero context:

```
1. agents/dex/PROTOCOL_DEX_SELF_IMPROVEMENT.md   ← THIS FILE
2. agents/dex/GROWTH.md                           ← W1/W2/W3 + I1/I2/I3 status
3. agents/dex/PLAYBOOK.md                         ← Operational checklist + phases
4. agents/dex/research/aric-latest.json           ← Last ARIC output (if exists)
5. agents/dex/ledger/pattern-analysis.jsonl       ← Root cause clusters (if I2 shipped)
6. kai/ledger/known-issues.jsonl                  ← Raw data to analyze
```

**FIRST ACTION after cold start:**
1. Count open known-issues: `wc -l kai/ledger/known-issues.jsonl`
2. Check aric-latest.json improvement status
3. If I1 (repair.sh) is "shipped": verify it's still running (check dex.sh Phase 1.5)
4. If I2 (cluster-patterns.py) is "planned": run ARIC Phase 3-4 to research clustering approach
5. If I2 is "researched" with files_to_change: call bin/agent-execute-improvement.sh dex I2

---

## PART 4 — FILE LOCATIONS

```
CORE FILES:
  agents/dex/dex.sh                               ← Main runner
  agents/dex/repair.sh                            ← JSONL auto-repair engine (I1 SHIPPED)
  agents/dex/evolution.jsonl                      ← Improvement history

IMPROVEMENT FILES (to be created):
  agents/dex/cluster-patterns.py                  ← I2: root cause clustering
  agents/dex/drift-detector.py                    ← I3: constitution drift detection
  agents/dex/ledger/pattern-analysis.jsonl        ← I2 output: clustered patterns
  agents/dex/ledger/constitution-drift.jsonl      ← I3 output: drift findings

MEMORY:
  agents/dex/GROWTH.md                            ← W1/W2/W3 + I1/I2/I3
  agents/dex/PLAYBOOK.md                          ← Operational checklist
  agents/dex/PRIORITIES.md                        ← Priority ranking

RESEARCH:
  agents/dex/research/aric-latest.json            ← ARIC Phase 7 output
  agents/dex/research-sources.json                ← Configured research sources

LEDGERS:
  agents/dex/ledger/repair-report.jsonl           ← I1 output: repair history
  agents/dex/ledger/pattern-analysis.jsonl        ← I2 output (to be created)
  agents/dex/ledger/constitution-drift.jsonl      ← I3 output (to be created)

LOGS:
  agents/dex/logs/dex-daily-YYYY-MM-DD.md         ← Daily reports
```

---

## PART 5 — TRIGGER MECHANISM

**Dex's growth phase fires at the start of every run:**
```bash
# In dex.sh (before main phases):
source bin/agent-growth.sh
run_growth_phase dex
```

**Scheduled trigger:**
```
com.hyo.dex.plist → 03:00 MT daily
```

**Execution engine:**
```bash
bash bin/agent-execute-improvement.sh dex I2  # cluster-patterns.py
bash bin/agent-execute-improvement.sh dex I3  # drift-detector.py
```

---

## PART 6 — WHAT "DONE" LOOKS LIKE FOR EACH IMPROVEMENT

### I1: Auto-Repair Engine — SHIPPED (2026-04-14)
- **Done looks like:** repair.sh runs Phase 1.5, handles 5 corruption types, reports results
- **Evidence:** `ls agents/dex/repair.sh && head -1 agents/dex/repair.sh` — should exist
- **Verification:** Manually corrupt a JSONL entry → run dex.sh → confirm entry repaired
- **Status:** Shipped. Verify metric: JSONL integrity check should show HEALTHY, not FAILED.

### I2: Root Cause Clustering — BUILD NEXT
- **Done looks like:** Pattern detection replaces count with: "5 clusters, top = Ra pipeline (42 issues, 35%, increasing)"
- **Evidence:** `cat agents/dex/ledger/pattern-analysis.jsonl | python3 -c "import json,sys; d=[json.loads(l) for l in sys.stdin]; print(len(d), 'clusters')"`
- **Files to create:** `agents/dex/cluster-patterns.py`
- **Gate question:** "Does cluster-patterns.py output have cluster_name, root_cause, issue_count, trend?"
- **Target metric:** Instead of "N patterns detected," report shows: "N patterns in K clusters, top cluster = X (Y%)"
- **Implementation approach:**
  1. Read kai/ledger/known-issues.jsonl
  2. Group by: extract agent from description (Nel, Ra, Sam, Aether, Dex prefix)
  3. Categorize by error type (API failure, missing file, stale data, pipeline error, gitignore gap)
  4. Count per cluster, compute % of total, measure trend (compare to 7-day-ago count)
  5. Output to agents/dex/ledger/pattern-analysis.jsonl

### I3: Constitution Drift Detector — PLANNED
- **Done looks like:** Daily report shows: "All 5 agents consistent with AGENT_ALGORITHMS.md v3.1. Sam ACTIVE.md is 36h old (OK). Nel evolution shows growth."
- **Evidence:** `cat agents/dex/ledger/constitution-drift.jsonl | head -5`
- **Files to create:** `agents/dex/drift-detector.py`
- **Gate question:** "Does drift-detector.py flag Sam's missing Phase 5 if it's removed from sam.sh?"
- **Target metric:** 0 agents with stale PLAYBOOKs, 0 agents missing required phases

---

## PART 7 — TICKET INTEGRATION

**Creating improvement tickets:**
```bash
bash bin/ticket.sh create \
    --agent dex \
    --type improvement \
    --weakness W2 \
    --title "Dex I2: cluster-patterns.py — root cause clustering for known-issues.jsonl" \
    --priority P1
```

**Finding Dex's open tickets:**
```bash
python3 -c "
import json
with open('kai/tickets/tickets.jsonl') as f:
    for line in f:
        t = json.loads(line.strip())
        if t.get('agent') == 'dex' and t.get('status') not in ('CLOSED','ARCHIVED'):
            print(f'[{t[\"priority\"]}] {t[\"id\"]}: {t[\"title\"]}')
"
```

---

## PART 8 — ESCALATION: WHEN TO INVOLVE KAI

Dex handles autonomously:
- JSONL repair, validation, and compaction
- Pattern detection and clustering improvements
- Constitution drift detection and reporting
- Own ticket lifecycle
- Runner modifications (dex.sh changes)

Escalate to Kai via dispatch:
- If drift detector finds constitutional violation requiring cross-agent coordination
- If JSONL corruption is systemic (all agents' files corrupt = infrastructure problem)
- If constitution change required (Dex cannot modify AGENT_ALGORITHMS.md)
- If pattern analysis reveals P0 systemic issue affecting multiple agents

---

## PART 9 — ACTIVE WEAKNESSES (as of 2026-04-21)

### W1: Detection Without Remediation
- **Status:** I1 shipped (repair.sh). Validate it's actually preventing FAILED status.
- **Metric to verify:** Phase 1 check shows HEALTHY (not FAILED) after repair runs
- **If still FAILED:** repair.sh may not be covering all corruption types; check dex.sh Phase 1.5 integration

### W2: Pattern Counting, Not Analysis (HIGHEST PRIORITY)
- **Root cause:** Phase 4 uses simple substring matching and counting; no clustering
- **Status:** I2 planned → BUILD NEXT
- **Next action [BUILD]:** Create agents/dex/cluster-patterns.py
  - Input: kai/ledger/known-issues.jsonl
  - Extract agent from issue description (e.g., "Ra pipeline" → agent=ra)
  - Categorize: API/network failures, missing files, stale data, pipeline errors, security gaps
  - Compute: cluster count, % of total, trend vs 7 days ago
  - Output: agents/dex/ledger/pattern-analysis.jsonl with human-readable cluster report
  - Replace Phase 4 in dex.sh with call to cluster-patterns.py

### W3: No Cross-Agent Consistency Enforcement
- **Root cause:** No mechanism to verify PLAYBOOK.md matches runner code
- **Status:** I3 planned (after I2)
- **Next action:** Research pattern: grep phase names from runner, compare to PLAYBOOK phase list

---

## PART 10 — FAILURE MODES (10 minimum)

```
FM1: cluster-patterns.py misidentifies agent attribution
  Gate: "Does cluster output match known agent distribution (Ra issues != Nel issues)?"
  → NO → review attribution regex, test with known-issues.jsonl samples

FM2: repair.sh corrupts JSONL file further
  Gate: "Does repaired file parse completely with zero JSON errors?"
  → NO → restore from quarantine, log P0, halt auto-repair for that file

FM3: drift-detector.py flags agent for missing phase that was intentionally removed
  Gate: "Is flagged phase listed in agent's PLAYBOOK under 'deprecated phases'?"
  → YES → do not flag. Allow PLAYBOOK to document intentional phase removal.

FM4: cluster-patterns.py OOM on large known-issues.jsonl
  Gate: "Does cluster-patterns.py complete within 60 seconds?"
  → NO → implement streaming read (process N lines at a time), not full load

FM5: pattern-analysis.jsonl not consumed by morning report
  Gate: "Does generate-morning-report.sh read agents/dex/ledger/pattern-analysis.jsonl?"
  → NO → update morning report generator to include Dex's cluster report

FM6: I2 cluster output has 1 cluster (everything grouped together)
  Gate: "Are there >= 3 distinct clusters with different agent attributions?"
  → NO → improve categorization rules; add more specific keyword patterns

FM7: repair.sh runs on JSONL files it shouldn't (e.g., read-only ledgers)
  Gate: "Does repair.sh check if file is writable before modifying?"
  → NO → add write permission check before repair attempt

FM8: drift-detector.py marks agent as drifted when PLAYBOOK is ahead of constitution
  Gate: "Is the agent's PLAYBOOK referencing a NEWER version of AGENT_ALGORITHMS.md?"
  → YES → not drift; agent updated PLAYBOOK proactively. Do not flag.

FM9: aric-latest.json written but not committed
  Gate: "Did git add agents/dex/research/aric-latest.json succeed?"
  → NO → ARIC output is valuable; do not lose it. Always commit immediately after write.

FM10: cluster-patterns.py produces no output when known-issues.jsonl is empty
  Gate: "Does known-issues.jsonl have >= 1 line?"
  → NO → skip clustering, output: "No known issues — system health HEALTHY"
  → YES but cluster count = 0 → check attribution regex; all lines may be unparseable
```

---

## PART 11 — VERSION HISTORY

| Version | Date       | Change |
|---------|------------|--------|
| v1.0    | 2026-04-21 | Initial protocol. Covers all 11 parts. Root cause clustering (I2) as immediate build target. Cold-start reproducible. 10 failure modes. |
