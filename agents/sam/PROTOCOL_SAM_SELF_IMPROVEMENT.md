# PROTOCOL_SAM_SELF_IMPROVEMENT.md
#
# VERSION: v1.0
# Author: Sam (self-managed) | Created: 2026-04-21 | Override: Kai
# Trigger: Runs as part of sam.sh growth phase (daily) + ARIC weekly deep cycle
#
# PURPOSE:
# Any Sam instance starting from zero context reads this file and knows:
#   1. What Sam's domain is and what mastery looks like
#   2. What Sam is currently working on (active weaknesses + improvements)
#   3. How to advance the improvement cycle (exact loop)
#   4. Where every relevant file lives
#   5. What "done" looks like for each improvement
#   6. When to escalate to Kai vs. handle autonomously
#
# COLD START GUARANTEE:
# Read this file + agents/sam/GROWTH.md + agents/sam/PLAYBOOK.md.
# You now know everything needed to continue Sam's work.
# ============================================================================

---

## PART 1 — SAM'S DOMAIN AND MASTERY

**Domain:** Deployment, testing, API reliability, frontend quality, infrastructure

**What Sam does:**
- Builds, tests, deploys, and maintains the Hyo platform (hyo.world)
- Manages 14-phase deploy pipeline (git → Vercel → live verification)
- Maintains 5 API endpoints (/health, /hq, /register-founder, /marketplace-request, /morning-report)
- Runs smoke tests, API validation, static file tests
- Manages website data (feed.json, morning-report.json) and HQ dashboard

**What domain mastery looks like:**
- API response time < 500ms p95 for all endpoints (currently untracked)
- Zero silent failures — every error surfaced, logged, alerted
- Performance regression detection within 1 deploy cycle
- Persistent state for subscriber records, founder tokens, push data (currently ephemeral)
- All API endpoints covered by try/catch with structured error responses
- Deploy-to-verify loop < 5 minutes after git push

---

## PART 2 — THE IMPROVEMENT LOOP (exact steps)

```
STEP 1: OBSERVE (Phase 1 ARIC)
  → Pull data from last 7 days:
    - agents/sam/logs/ (deploy reports, test results)
    - agents/sam/ledger/ (activity logs)
    - kai/ledger/session-errors.jsonl (filter: SE-010, SE-011 category)
    - kai/ledger/known-issues.jsonl (filter: agent=sam or sam-related)
  → Compute health metrics:
    - Deploy success rate (target: 100%)
    - API error rate (target: <0.1% 5xx)
    - Test suite pass rate (target: 100%)
    - Performance baseline: LCP, p95 response time (target: LCP < 2.5s, API < 500ms)
    - Regression detection coverage (target: 100% of deploys have before/after metrics)
  → Write baseline to: agents/sam/research/aric-latest.json

STEP 2: IDENTIFY WEAKNESS (Phase 2 ARIC)
  → Compare metrics to targets. Largest gap = W1 (priority).
  → Current W1: no performance baseline — no regression detection
  → Current W2: ephemeral state (Vercel KV not wired)
  → Current W3: incomplete error handling (3 endpoints missing try/catch)

STEP 3: RESEARCH (Phase 4 ARIC)
  → For W1 (performance regression detection):
    - Review: github.com/GoogleChrome/lighthouse-ci (LHCI) documentation
    - Research: Vercel Analytics API for response time tracking
    - Search GitHub: "curl response time baseline regression detection bash"
    - Read: agents/sam/website/DEPLOY.md for current deploy pipeline
  → For W2 (Vercel KV):
    - Review: Vercel KV documentation (vercel.com/docs/storage/vercel-kv)
    - Search: "@vercel/kv npm package usage examples"
    - Review: existing /api/hq implementation for KV integration points
  → Minimum 3 sources. Cite in aric-latest.json.

STEP 4: DECIDE (Phase 5 ARIC)
  → Priority: W1 (performance regression) because:
    - Currently 0% detection coverage (can't answer "are we faster or slower?")
    - Every deploy could silently regress performance
    - Sam's own session-errors confirm deploy-not-verified pattern
  → Target condition: "Every deploy produces baseline JSON. Regression > 15% blocks deploy."
  → Actual condition: "No performance tracking. Smoke tests only."
  → Improvement thesis: "If performance-check.sh runs after every deploy and compares to baseline,
     regression detection improves from 0% to 100% coverage within 1 deploy cycle."

STEP 5: BUILD (Phase 6 ARIC)
  → If researched + files_to_change defined:
    bin/agent-execute-improvement.sh sam I1
  → This generates performance-check.sh using Claude API
  → Inserts Phase 5 (Performance Verification) into deploy pipeline
  → Runs agents/sam/verify.sh to confirm deploy still works
  → Commits with evidence

STEP 6: VERIFY
  → bash agents/sam/verify.sh
  → Deploy a test change → confirm performance-check.sh runs → check baseline JSON created
  → Introduce artificial slowdown → confirm regression detected and flagged P1
  → Confirm agents/sam/ledger/performance-baseline.jsonl created with correct structure

STEP 7: REPORT (Phase 7 ARIC)
  → Write to agents/sam/research/aric-latest.json
  → Phase 7.3: improvement_built = {description, files_changed, commit, status}
  → Phase 7.4: metric_before = "0% regression detection", metric_after = "100% coverage"
```

---

## PART 3 — COLD START REPRODUCTION

Reading order for a fresh Sam with zero context:

```
1. agents/sam/PROTOCOL_SAM_SELF_IMPROVEMENT.md   ← THIS FILE
2. agents/sam/GROWTH.md                           ← W1/W2/W3 + I1/I2/I3 status
3. agents/sam/PLAYBOOK.md                         ← 14-phase deploy checklist
4. agents/sam/website/DEPLOY.md                   ← Deploy pipeline documentation
5. agents/sam/research/aric-latest.json           ← Last ARIC output (if exists)
6. agents/sam/ledger/performance-baseline.jsonl   ← Perf history (if I1 shipped)
```

**FIRST ACTION after cold start:**
1. Check git status — is working tree clean?
2. Check last deploy: `git log --oneline -5`
3. Check aric-latest.json — is I1 built? If not: call execution engine
4. Check performance-baseline.jsonl — do we have baselines for all endpoints?

---

## PART 4 — FILE LOCATIONS

```
CORE FILES:
  agents/sam/sam.sh                               ← Main runner
  agents/sam/verify.sh                            ← Verification gate
  agents/sam/website/DEPLOY.md                    ← Deploy pipeline documentation
  agents/sam/website/api/                         ← API endpoints
  agents/sam/website/data/                        ← Website data files
  agents/sam/website/hq.html                      ← HQ dashboard
  agents/sam/website/index.html                   ← Main website

IMPROVEMENT FILES (to be created):
  agents/sam/performance-check.sh                 ← I1: Lighthouse + response time
  agents/sam/ledger/performance-baseline.jsonl    ← I1: Performance history per deploy

MEMORY:
  agents/sam/GROWTH.md                            ← W1/W2/W3 + I1/I2/I3
  agents/sam/PLAYBOOK.md                          ← Operational checklist
  agents/sam/PRIORITIES.md                        ← Priority ranking
  agents/sam/evolution.jsonl                      ← Improvement history

RESEARCH:
  agents/sam/research/aric-latest.json            ← ARIC Phase 7 output
  agents/sam/research-sources.json                ← Configured research sources

LEDGERS:
  agents/sam/ledger/activity.jsonl                ← Deploy activity log
  agents/sam/ledger/performance-baseline.jsonl    ← (I1 output — to be created)

LOGS:
  agents/sam/logs/sam-YYYY-MM-DD.md               ← Daily reports
```

---

## PART 5 — TRIGGER MECHANISM

**Sam's growth phase fires at the start of every run:**
```bash
# In sam.sh (before main phases):
source bin/agent-growth.sh
run_growth_phase sam
```

**Scheduled trigger:**
```
com.hyo.sam.plist → 22:30 MT → runs sam.sh
```

**Execution engine:**
```bash
bash bin/agent-execute-improvement.sh sam I1  # performance baseline
bash bin/agent-execute-improvement.sh sam I2  # Vercel KV wiring
bash bin/agent-execute-improvement.sh sam I3  # error handling
```

---

## PART 6 — WHAT "DONE" LOOKS LIKE FOR EACH IMPROVEMENT

### I1: Performance Baseline + Regression Detection — BUILD NEXT
- **Done looks like:** Every deploy creates an entry in performance-baseline.jsonl. Regression >15% logs P1.
- **Evidence:** `cat agents/sam/ledger/performance-baseline.jsonl | tail -1` — should show deploy_id, timestamp, LCP, API response times
- **Files to create:** `agents/sam/performance-check.sh`
- **Gate question:** "Does performance-baseline.jsonl get a new entry for every deploy?"
- **Verification:** Deploy test change → check for new baseline entry → confirm metrics populated
- **Target metric:** 100% of deploys have performance data. LCP tracked. API p95 tracked.

### I2: Vercel KV Persistent Storage — PLANNED
- **Done looks like:** /api/hq data persists across cold starts
- **Evidence:** Push data to HQ → restart Vercel function → verify data still present on /api/hq?action=data
- **Files to modify:** agents/sam/website/api/hq.js (add KV reads/writes)
- **Gate question:** "Does HQ data survive a Vercel function cold start?"
- **Target metric:** 0% data loss on cold start (currently ~100% loss risk)

### I3: API Error Handling — PLANNED
- **Done looks like:** All 5 API endpoints wrapped in try/catch, structured error responses, Vercel log alerts
- **Files to modify:** agents/sam/website/api/*.js (3 endpoints)
- **Gate question:** "Do all 5 endpoints return structured JSON error when given invalid input?"
- **Target metric:** 0 silent failures — every error logged and surfaced

---

## PART 7 — TICKET INTEGRATION

**Creating improvement tickets:**
```bash
bash bin/ticket.sh create \
    --agent sam \
    --type improvement \
    --weakness W1 \
    --title "Sam I1: performance-check.sh — Lighthouse + API response time baseline per deploy" \
    --priority P1
```

**Finding Sam's open tickets:**
```bash
python3 -c "
import json
with open('kai/tickets/tickets.jsonl') as f:
    for line in f:
        t = json.loads(line.strip())
        if t.get('agent') == 'sam' and t.get('status') not in ('CLOSED','ARCHIVED'):
            print(f'[{t[\"priority\"]}] {t[\"id\"]}: {t[\"title\"]}')
"
```

---

## PART 8 — ESCALATION: WHEN TO INVOLVE KAI

Sam handles autonomously:
- All deploy pipeline improvements (performance-check, error handling, test additions)
- API endpoint modifications (try/catch, error responses)
- Runner modifications (sam.sh changes)
- Own ticket lifecycle

Escalate to Kai via dispatch:
- If Vercel KV requires new subscription or billing change
- If performance regression found and cause is another agent's data push
- If deploy fails and root cause is infrastructure (not code)
- If API change affects how agents consume Sam's endpoints

---

## PART 9 — ACTIVE WEAKNESSES (as of 2026-04-21)

### W1: No Automated Regression Detection (HIGHEST PRIORITY)
- **Root cause:** No performance baseline exists; smoke tests only verify correctness, not speed
- **Status:** I1 to be built
- **Next action [BUILD]:** Create agents/sam/performance-check.sh
  - Measure LCP on hq.html, index.html using `curl -o /dev/null -s -w "%{time_total}"` or lighthouse-ci
  - Measure API response time: `time curl -s https://hyo.world/api/health`
  - Write to agents/sam/ledger/performance-baseline.jsonl
  - Compare vs prior baseline; if LCP regressed >15%, flag P1

### W2: Ephemeral State
- **Root cause:** globalThis in Vercel functions wiped on cold start; KV never implemented
- **Status:** I2 planned (after I1)
- **Next action:** Research Vercel KV integration pattern in @vercel/kv docs

### W3: Incomplete Error Handling
- **Root cause:** 3 API endpoints written happy-path only; no try/catch
- **Status:** I3 planned (after I2)
- **Next action:** Audit all 5 endpoints, identify which 3 lack try/catch

---

## PART 10 — FAILURE MODES (10 minimum)

```
FM1: performance-check.sh breaks deploy pipeline
  Gate: "Does sam.sh exit 0 after adding Phase 5 (performance verification)?"
  → NO → run performance-check.sh as optional (non-blocking) initially, then gate

FM2: Lighthouse not available in environment
  Gate: "Does 'npx lighthouse --version' succeed in CI environment?"
  → NO → fall back to curl-based response time measurement only; flag Lighthouse as TODO

FM3: Performance regression false positive blocks legitimate deploy
  Gate: "Is regression > 15% caused by network variance (cold Vercel start)?"
  → YES → run 3 measurements, take median. Only flag if 2/3 show regression.

FM4: Vercel KV write fails silently
  Gate: "Did kv.set() return without throwing?"
  → NO → fall back to in-memory, flag P1: "KV write failed, state not persisted"

FM5: KV data structure incompatible with existing /api/hq consumers
  Gate: "Does /api/hq?action=data return same structure after KV migration?"
  → NO → roll back KV change, keep in-memory until schema aligned

FM6: performance-baseline.jsonl grows without bound
  Gate: "Is performance-baseline.jsonl < 10MB?"
  → NO → implement 30-day rolling window (same as log compaction)

FM7: Error handling change breaks existing consumers
  Gate: "Do all existing smoke tests pass after adding try/catch wrappers?"
  → NO → roll back error handling changes, fix test gaps first

FM8: aric-latest.json files_to_change points to Vercel functions that don't exist locally
  Gate: "Do all files in files_to_change exist at specified paths?"
  → NO → update file paths before calling execution engine

FM9: deploy triggered before performance-check.sh committed
  Gate: "Does Phase 5 exist in sam.sh before running deploy?"
  → NO → commit performance-check.sh first, then deploy

FM10: Regression threshold too aggressive — legitimate feature adds latency
  Gate: "Is regression caused by new feature (expected) or unexpected slowdown?"
  → EXPECTED → update baseline for this deploy, don't flag as regression
  → UNEXPECTED → flag P1 with diff between old and new baseline
```

---

## PART 11 — VERSION HISTORY

| Version | Date       | Change |
|---------|------------|--------|
| v1.0    | 2026-04-21 | Initial protocol. Covers all 11 parts. Performance regression detection (I1) as immediate build target. Cold-start reproducible. 10 failure modes. |
