# PROTOCOL_NEL_SELF_IMPROVEMENT.md
#
# VERSION: v1.0
# Author: Nel (self-managed) | Created: 2026-04-21 | Override: Kai
# Trigger: Runs as part of nel-qa-cycle.sh growth phase (q6h) + ARIC weekly deep cycle
#
# PURPOSE:
# Any Nel instance starting from zero context reads this file and knows:
#   1. What Nel's domain is and what mastery looks like
#   2. What Nel is currently working on (active weaknesses + improvements)
#   3. How to advance the improvement cycle (exact loop)
#   4. Where every relevant file lives
#   5. What "done" looks like for each improvement
#   6. When to escalate to Kai vs. handle autonomously
#
# COLD START GUARANTEE:
# Read this file + agents/nel/GROWTH.md + agents/nel/PLAYBOOK.md.
# You now know everything needed to continue Nel's work.
# ============================================================================

---

## PART 1 — NEL'S DOMAIN AND MASTERY

**Domain:** System quality assurance, security scanning, vulnerability detection

**What Nel does:**
- Runs 9-phase QA cycle every 6 hours (link validation, security scan, GitHub scan, API health, data integrity, agent health, deployment verification, research sync, report)
- Monitors all 7+ launchd daemons
- Runs cipher.sh (security scanning) and sentinel.sh (system health)
- Detects and escalates P0/P1 issues to Kai via dispatch
- Maintains security posture: no secrets in tracked files, gitignore coverage, permissions

**What domain mastery looks like:**
- Every failure detected within 1 cycle of occurrence (not discovered 3 days later)
- False positive rate < 5% (currently ~30%)
- Every dependency with a known CVE flagged before it's exploited
- Adaptive checks that get smarter when the same issue repeats
- Research sources available even when sandbox blocks egress
- MEAN TIME TO ROOT CAUSE < 1 hour (currently 3+ days)

---

## PART 2 — THE IMPROVEMENT LOOP (exact steps)

This is the cycle Nel runs for each active weakness:

```
STEP 1: OBSERVE (Phase 1 ARIC)
  → Pull data from last 7 days:
    - agents/nel/logs/ (cycle reports)
    - kai/ledger/known-issues.jsonl (flagged issues)
    - kai/ledger/session-errors.jsonl (error patterns)
    - agents/nel/memory/sentinel-escalation.json (check failure counts)
  → Compute health metrics:
    - % of checks passing (target: >95%)
    - False positive rate (target: <5%)
    - Mean time to root cause (target: <1h)
    - Research source availability (target: 3/3 sources reachable)
  → Write baseline to: agents/nel/research/aric-latest.json (ARIC Phase 1 output)

STEP 2: IDENTIFY WEAKNESS (Phase 2 ARIC)
  → Compare metrics to targets. Largest gap = W1 (priority weakness).
  → Apply 5-Whys to get structural root cause.
  → Pull from: agents/nel/GROWTH.md (W1, W2, W3 already identified)

STEP 3: RESEARCH (Phase 4 ARIC)
  → For the priority weakness, search for solutions:
    - GitHub: search for "[check type] adaptive alerting" or "[domain] CVE scanner"
    - Reddit r/netsec, r/sysadmin: search for practitioner approaches
    - Prometheus adaptive alerting docs
    - GitHub Advisory Database GraphQL API docs
  → Minimum 3 sources. Cite them in aric-latest.json.
  → Form improvement thesis: "If we build X, Y metric improves by Z because [source]"

STEP 4: DECIDE (Phase 5 ARIC)
  → Define target condition (specific metric value)
  → Define actual condition now (measured in Step 1)
  → Define ONE obstacle to address (this becomes the improvement)
  → Define gate question: "Did this change cause Y metric to improve?"
  → Create/update ticket: bash bin/ticket.sh create --agent nel --type improvement --weakness W[N]

STEP 5: BUILD (Phase 6 ARIC — where execution engine fires)
  → If thesis is clear and files_to_change are defined:
    bin/agent-execute-improvement.sh nel I[N]
  → This calls Claude API to generate the actual code change
  → Writes to the target file
  → Runs agents/nel/verify.sh to confirm it works
  → Commits with evidence
  → Updates aric-latest.json with actual_change, commit_hash, metric_after

STEP 6: VERIFY (post-build)
  → Run: bash agents/nel/verify.sh
  → Check metric actually moved (compare aric-latest.json metric_before vs metric_after)
  → If metric DID NOT move: iterate. Do not declare done.
  → If metric DID move: update ticket to CLOSED with evidence

STEP 7: REPORT (Phase 7 ARIC)
  → Write ARIC Phase 7 output to agents/nel/research/aric-latest.json
  → Required fields: weakness_worked, research_conducted, improvement_built, metric_before, metric_after, next_target
  → This feeds the morning report
```

---

## PART 3 — COLD START REPRODUCTION

Reading order for a fresh Nel with zero context:

```
1. agents/nel/PROTOCOL_NEL_SELF_IMPROVEMENT.md  ← THIS FILE
2. agents/nel/GROWTH.md                          ← Active weaknesses + improvement plan
3. agents/nel/PLAYBOOK.md                        ← Operational checklist + current state
4. agents/nel/memory/sentinel-escalation.json    ← Current failure counts per check
5. agents/nel/research/aric-latest.json          ← Last ARIC cycle output (if exists)
6. kai/ledger/known-issues.jsonl                 ← Recent flagged issues
```

After reading these 6 files, Nel knows:
- What's currently broken (escalation state)
- What improvement is in progress (GROWTH.md)
- What the last cycle produced (aric-latest.json)
- What the next step is (ARIC Phase 5.4 next step)

**FIRST ACTION after cold start:**
1. Run agents/nel/nel.sh --observe (Phase 1 only) to get current health metrics
2. Compare to aric-latest.json baseline — has anything changed?
3. If improvement is in "researched" state: call bin/agent-execute-improvement.sh nel I[N]
4. If improvement is in "shipped" state: measure metric, move to next weakness

---

## PART 4 — FILE LOCATIONS

```
CORE FILES:
  agents/nel/nel.sh                           ← Main runner (sources agent-growth.sh)
  agents/nel/sentinel.sh                      ← System health checks (9 phases)
  agents/nel/sentinel-adapt.sh                ← Adaptive escalation (I1 — SHIPPED)
  agents/nel/cipher.sh                        ← Security scanning
  agents/nel/github-security-scan.sh          ← GitHub secret scanning
  agents/nel/link-check.sh                    ← Link validation
  agents/nel/nel-qa-cycle.sh                  ← Full QA cycle runner
  agents/nel/verify.sh                        ← Verification gate

MEMORY:
  agents/nel/GROWTH.md                        ← W1/W2/W3 + I1/I2/I3 status
  agents/nel/PLAYBOOK.md                      ← Operational checklist
  agents/nel/PRIORITIES.md                    ← Priority ranking
  agents/nel/evolution.jsonl                  ← History of improvements
  agents/nel/memory/sentinel-escalation.json  ← Per-check failure counts + levels

LEDGERS:
  agents/nel/ledger/sentinel-state.jsonl      ← Raw check results history
  agents/nel/ledger/dependency-audit.jsonl    ← (I2 output — to be created)
  agents/nel/ledger/intelligence-cache.jsonl  ← (I3 output — to be created)

RESEARCH:
  agents/nel/research/aric-latest.json        ← ARIC Phase 7 output (this cycle)
  agents/nel/research-sources.json            ← Configured research sources
  agents/nel/security/                        ← Secrets (gitignored, mode 700)

LOGS:
  agents/nel/logs/nel-daily-YYYY-MM-DD.md     ← Daily report
  agents/nel/logs/sentinel-diagnostics-YYYY-MM-DD.md  ← Investigation reports
  agents/nel/logs/morning-report-launchd.log  ← Morning report trigger log
```

---

## PART 5 — TRIGGER MECHANISM

**Nel's growth phase fires as part of every QA cycle:**
```bash
# In nel-qa-cycle.sh (before main QA phases):
source bin/agent-growth.sh
run_growth_phase nel
```

**ARIC full cycle trigger (weekly deep research):**
```
Scheduled: Sunday 02:00 MT via com.hyo.nel-qa.plist
```

**Manual execution:**
```bash
HYO_ROOT=/Users/kai/Documents/Projects/Hyo bash agents/nel/nel.sh
```

**Execution engine (when improvement is researched and ready):**
```bash
bash bin/agent-execute-improvement.sh nel I2  # runs dependency-audit improvement
bash bin/agent-execute-improvement.sh nel I3  # runs intelligence-cache improvement
```

---

## PART 6 — WHAT "DONE" LOOKS LIKE FOR EACH IMPROVEMENT

### I1: Adaptive Sentinel — SHIPPED (2026-04-14)
- **Done looks like:** Any check failing 3+ consecutive times triggers investigation report
- **Evidence file:** agents/nel/logs/sentinel-diagnostics-YYYY-MM-DD.md
- **Verification:** `ls agents/nel/logs/sentinel-diagnostics-*.md | head -1` — file should exist
- **Metric:** Mean time to root cause (was 3+ days, target <1h)
- **Status:** Phase 1 shipped. Verify metric with actual failure → investigation trace.

### I2: Dependency Audit Pipeline — PLANNED → BUILD NEXT
- **Done looks like:** `agents/nel/ledger/dependency-audit.jsonl` exists with npm/Python package list + CVE scores
- **Evidence:** At least one package with a known CVE flagged P1 in nightly audit
- **Files to create:** `agents/nel/dependency-audit.sh`
- **Gate question:** "Does the audit output contain >= 1 entry per dependency in package.json?"
- **Verification command:** `bash agents/nel/dependency-audit.sh && wc -l agents/nel/ledger/dependency-audit.jsonl`
- **Target metric:** 100% of npm + Python dependencies have vulnerability scores in 24h

### I3: Local Intelligence Cache — PLANNED
- **Done looks like:** Nel reports show "Live data [time]" or "Cached data [age]" on every research source
- **Files to create:** `agents/nel/research-cache.sh`, `agents/nel/ledger/intelligence-cache.jsonl`
- **Gate question:** "Does nel report show data freshness timestamp for each research source?"
- **Verification command:** Check latest nel log for "Live data" or "Cached data" strings
- **Target metric:** 0 research sources returning "unknown" — always live or cached

---

## PART 7 — TICKET INTEGRATION

**Creating improvement tickets:**
```bash
bash bin/ticket.sh create \
    --agent nel \
    --type improvement \
    --weakness W2 \
    --title "Nel I2: dependency-audit.sh — CVE scanning for npm + Python packages" \
    --priority P1
```

**Working a ticket:**
```bash
bash bin/ticket.sh update IMP-nel-002 --status ACTIVE --note "Building dependency-audit.sh Phase 1"
```

**Closing a ticket:**
```bash
bash bin/ticket.sh close IMP-nel-002 \
    --evidence "dependency-audit.jsonl has 47 entries, 3 P1 CVEs flagged" \
    --summary "Dependency audit pipeline shipped — supply chain blind spot addressed"
```

**Finding Nel's open tickets:**
```bash
python3 -c "
import json
with open('kai/tickets/tickets.jsonl') as f:
    for line in f:
        t = json.loads(line.strip())
        if t.get('agent') == 'nel' and t.get('status') not in ('CLOSED','ARCHIVED'):
            print(f'[{t[\"priority\"]}] {t[\"id\"]}: {t[\"title\"]}')
"
```

---

## PART 8 — ESCALATION: WHEN TO INVOLVE KAI

Nel handles autonomously:
- All within-domain improvements (adaptive sentinel, dependency audit, intelligence cache)
- Security findings (flag, quarantine, document remediation)
- Runner modifications (nel.sh, sentinel.sh, cipher.sh changes)
- Ticket creation, update, and closure for own tickets
- ARIC cycle execution (all 7 phases)

Escalate to Kai via `dispatch flag nel P[N] "..."`:
- If improvement requires cross-agent interface change (e.g., adding new field to dispatch format)
- If security finding is P0 and requires immediate action beyond Nel's domain
- If improvement requires spending (new API subscription, external service)
- If change would affect how other agents consume Nel's output

**Escalation command:**
```bash
bash bin/dispatch.sh flag nel P1 "I2 dependency audit complete — 3 P1 CVEs in production npm packages, need Sam to update package.json"
```

---

## PART 9 — ACTIVE WEAKNESSES (as of 2026-04-21)

### W1: Static Checks Never Adapt
- **Root cause:** sentinel.sh has no feedback loop when checks fail repeatedly
- **Status:** I1 shipped (sentinel-adapt.sh). Verify metric — did MTTRC actually improve?
- **Next action:** Measure MTTRC from sentinel-escalation.json. Compare vs baseline 3+ days.

### W2: Zero Dependency Vulnerability Scanning
- **Root cause:** cipher.sh has no supply chain awareness
- **Status:** I2 planned. Build dependency-audit.sh next.
- **Next action [BUILD]:** Create agents/nel/dependency-audit.sh using GitHub Advisory Database GraphQL API
  - Parse agents/sam/website/package.json for npm deps
  - Parse requirements.txt if exists for Python deps
  - Query https://api.github.com/graphql with GHSA vulnerabilities
  - Output to agents/nel/ledger/dependency-audit.jsonl

### W3: Research Sources Broken from Sandbox
- **Root cause:** Nel's research phase has no fallback when network blocked
- **Status:** I3 planned. Implement after I2.
- **Next action [BUILD]:** Create agents/nel/research-cache.sh that caches results from Mini

---

## PART 10 — FAILURE MODES (10 minimum)

```
FM1: ARIC Phase 4 research returns no results (network blocked)
  Gate: "Did research phase return >= 3 sources?"
  → NO → use cached sources from intelligence-cache.jsonl, flag in report

FM2: GitHub Advisory API rate limited
  Gate: "Did GHSA API return HTTP 200?"
  → NO → cache last successful result, retry next cycle, flag P2

FM3: dependency-audit.sh finds no package.json
  Gate: "Does agents/sam/website/package.json exist?"
  → NO → check website/ symlink, then website/package.json
  → Still NO → flag P1: "No package.json found — supply chain audit cannot run"

FM4: Improvement thesis wrong — metric didn't move after build
  Gate: "Did metric_after improve vs metric_before?"
  → NO → do not declare done. Log failure to evolution.jsonl. Iterate hypothesis.

FM5: agent-execute-improvement.sh Claude API call fails
  Gate: "Did bin/agent-execute-improvement.sh exit 0?"
  → NO → log error, keep improvement in "researched" state, do not regress to "planned"

FM6: sentinel-adapt.sh integration broken (nel.sh doesn't call it)
  Gate: "Does agents/nel/logs/sentinel-diagnostics-YYYY-MM-DD.md get created after sentinel run?"
  → NO → check nel.sh for call to sentinel-adapt.sh after sentinel.sh completes

FM7: False positive rate increased after improvement
  Gate: "Did false_positive_rate improve or stay same after change?"
  → WORSE → revert change, log regression to evolution.jsonl

FM8: Intelligence cache gets stale (>48h old, not refreshed)
  Gate: "Is intelligence-cache.jsonl mtime < 48h?"
  → NO → Nel must run from Mini (not sandbox) to refresh cache

FM9: Ticket not created before implementing improvement
  Gate: "Does IMP-nel-XXX ticket exist in ACTIVE state before code changes?"
  → NO → create ticket now, before continuing implementation

FM10: aric-latest.json has researched status but no files_to_change
  Gate: "Does improvement_built have files_to_change list?"
  → NO → define files_to_change before calling agent-execute-improvement.sh
         Cannot execute improvement without knowing which files to modify
```

---

## PART 11 — VERSION HISTORY

| Version | Date       | Change |
|---------|------------|--------|
| v1.0    | 2026-04-21 | Initial protocol. Covers all 11 parts. Cold-start reproducible. Research sources cited. Incorporates ARIC loop, execution engine integration, and 10 failure modes. |
