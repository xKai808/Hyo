# Agent Creation Protocol

**Version:** 4.0 | **Author:** Kai (CEO, hyo.world) | **Date:** 2026-04-28
**Status:** Battle-tested across 8 agents (Kai, Sam, Nel, Ra, Aurora, Aether, Dex, + Cipher/Sentinel sub-agents)
**v2.0 changes (session 8):** Added PLAYBOOK.md + evolution.jsonl to file structure. Runner template includes self-review (agent-gates.sh), self-evolution with reflection block. New section 6.5: Agent Autonomy & Growth. Testing protocol expanded to 11 points.
**v3.0 changes (session 14):** Questions replace reminders throughout. GROWTH.md is now required at creation. Test 12+13 added: simulation gate + live surface verify (PROTOCOL-001 — skipping these caused Hyo to catch errors Kai missed all session). ERROR-TO-GATE step 3b added: every creation error → ACTIVE ticket with owner+deadline (PROTOCOL-002). forKai inbox check wired into runner template. ARIC cycle made explicit in runner structure.
**v4.0 changes (2026-04-28):** Signal bus integration (kai-signal.sh) — agents emit signals on structural failures, not just dispatch flags. Chaos resilience requirement — every agent must have a fallback for each critical dependency (tested by chaos-inject.sh). Forward AAR chain — agents write forward-aar files at cycle end so next cycle inherits context instead of cold-starting. Self-improve state files added to skeleton. Scheduling model updated: agents are invoked by kai-autonomous.sh, not individual plists (Section 9). Testing protocol expanded to 15 points (Test 14: signal emission, Test 15: chaos fallback). Maintenance cadences updated: daily cross-agent review, weekly double-loop (Monday), chaos test (Saturday). Failure catalog: F11 + F12 added. License section strengthened for commercial licensing use.

This document is the complete, repeatable protocol for creating, integrating, testing, and operating an autonomous agent within a multi-agent system. It was developed through iterative production use — every step exists because skipping it caused a failure at some point.

This protocol is designed to be **portable and licensable**. The hyo.world implementation details are included as concrete examples, but every pattern applies to any autonomous multi-agent architecture running on bash + dispatch + a CEO orchestrator. Organizations licensing this protocol receive a proven operational blueprint — not theory — built from 8 production agents across 14+ sessions of real failure and recovery.

---

## Table of Contents

1. Pre-Creation (Define the Agent)
2. File Structure (Build the Skeleton) — includes PLAYBOOK.md + evolution.jsonl + GROWTH.md + forward-aar files
3. Manifest (Identity Card)
4. Runner Script (Execution Engine) — includes self-review, reflection, signal emission, growth phase
5. Dispatch Integration (Closed-Loop Communication)
6. Algorithm Documentation (Runbook)
6.5. **Agent Autonomy & Growth** (v2.0 — session 8)
6.6. **Signal Bus Integration** (v4.0 — 2026-04-28)
6.7. **Chaos Resilience** (v4.0 — 2026-04-28)
7. CEO/Dispatcher Integration (Routing)
8. Dashboard/UI Integration (Visibility)
9. Schedule (Automation) — updated v4.0: kai-autonomous.sh model
10. Testing Protocol (15-Point Validation) — expanded from 13 in v3.0
11. Migration Protocol (Renaming/Restructuring)
12. Post-Creation (Maintenance) — updated cadences v4.0
13. Appendix: Failure Catalog — F1–F12

---

## PRE-BUILD GATE: Marina Wyss Quick Reference Card

**MANDATORY. Run before writing any file. No exceptions.**

Before designing any agent or capability, answer all 10 questions from the Marina Wyss Complete Course Guide. A "NO" on any question means you are not ready to build — fix the gap first.

Full reference: `agents/sam/website/docs/research/marina-wyss-complete-course-guide.md`
Live URL: `https://www.hyo.world/docs/research/marina-wyss-complete-course-guide`

**10 Questions (all must be YES before building):**

1. **Perceive/Decide/Act loop** — Is there a clear perceive → decide → act cycle? (Ch.1)
2. **Autonomy level** — What level (1–5) is appropriate? Is this justified? (Ch.2)
3. **Context injection** — Will context include: role + task + memory (last 3 actions) + tools + knowledge? (Ch.3)
4. **Independent observability** — Is every step independently observable? If a step fails, can you identify exactly which one? (Ch.4)
5. **Tool interface separation** — Is the tool interface (name, description, typed schema) defined separately from the implementation? (Ch.5)
6. **Memory vs. knowledge** — Is dynamic memory (updated each run) separate from static knowledge (read-only during execution)? (Ch.6)
7. **Reflection** — Does the agent reflect after every action? Is the reflection structured? (Ch.7)
8. **Guardrails** — Are input validation, output filtering, and scope boundary enforcement in place? (Ch.8)
9. **GVU metric** — Is there ONE ground-truth metric that cannot be gamed (Generator-Verifier-Updater pattern)? (Ch.9)
10. **Planning before acting** — Does the agent plan before acting and replan on unexpected results? (Ch.10)

If any answer is NO: do not build. Design the missing piece first.

---

## 1. Pre-Creation: Define the Agent

Before writing a single file, answer these questions. If you can't answer all of them, the agent isn't ready to be built.

**Identity:**
- What is the agent's name? (Short, memorable, no spaces. Will become directory names, CLI commands, manifest keys.)
- What is the agent's one-sentence role? (If it takes more than one sentence, you're building two agents.)
- What does this agent own that no other agent owns? (Ownership must be exclusive. Overlapping ownership creates race conditions and confusion.)

**Boundaries:**
- What does this agent do that a human currently does manually? (This is the automation justification.)
- What does this agent NOT do? (Negative space is as important as positive. Document it.)
- Which other agents does it interact with? (Upstream: who gives it work. Downstream: who consumes its output.)

**Data:**
- What data does this agent read? (Input files, APIs, ledgers.)
- What data does this agent write? (Output files, metrics, reports.)
- What data does this agent own exclusively? (Its ledger, its logs, its state.)

**Schedule:**
- Does it run on a schedule? (Every N minutes, daily at time X, on-demand only.)
- Does it run in response to events? (Trade recorded, file changed, flag raised.)
- What happens if it misses a scheduled run? (Idempotent recovery? Silent skip? Escalation?)

**Example — Aether (Trading Intelligence):**
- Name: aether
- Role: Trading metrics collector, portfolio monitor, GPT-powered fact-checker
- Owns: Trade recording, weekly metrics, exchange API integration, all GPT/OpenAI calls
- Does NOT do: Execute trades (human only), manage infrastructure (Sam), audit security (Nel)
- Interacts with: Kai (receives delegations, reports results), Nel (gets audited), HQ dashboard (pushes metrics)
- Schedule: Every 15 minutes via launchd

**Example — Dex (System Memory Manager):**
- Name: dex
- Role: Ledger integrity, compaction, stale task detection, pattern recognition
- Owns: JSONL validation, archive compaction, cross-agent pattern detection
- Does NOT do: Create tasks (Kai), write code (Sam), gather intelligence (Ra)
- Interacts with: Every agent (reads their ledgers), Kai (reports findings), Nel (complementary auditing)
- Schedule: Daily at 23:00 MT (before nightly simulation)

---

## 2. File Structure: Build the Skeleton

Every agent follows the same directory structure. No exceptions. Consistency is what makes the system debuggable at 2 AM.

```
agents/<name>/
├── <name>.sh                    ← Runner script (the agent's brain)
├── PLAYBOOK.md                  ← Agent's own operational manual (agent owns, Kai can override)
├── PRIORITIES.md                ← Current operational priorities + research mandate
├── GROWTH.md                    ← 3 weaknesses, 3 systemic improvements, self-set goals (mandatory v3.0+)
├── evolution.jsonl              ← Append-only learning/growth log (written every run cycle)
├── self-improve-state.json      ← Self-improvement cycle state: stage, current_weakness, cycles, failure_count
├── ledger/
│   ├── ACTIVE.md                ← Open tasks assigned to this agent
│   ├── log.jsonl                ← Append-only event log
│   ├── forward-aar-YYYY-MM-DD.json  ← Forward After-Action Review (written at cycle end, read at next cycle start)
│   └── daily-assess-YYYY-MM-DD.json ← Daily ARIC assessment snapshot
├── logs/
│   ├── <name>-YYYY-MM-DD.log        ← Daily execution logs
│   └── self-review-YYYY-MM-DD.md    ← Self-review output (from agent-gates.sh)
└── [optional domain-specific files]
    ├── data/                    ← Agent-specific data files
    └── ...
```

**Note on scheduling (v4.0):** Individual launchd plists are no longer the primary scheduling mechanism. All agents are invoked by `bin/kai-autonomous.sh`, which runs every 5 minutes and fires agents on their configured schedule using time-keyed state checks. This eliminates plist management overhead and centralizes all scheduling in one place. See Section 9.

**Create the skeleton first, populate second:**
```bash
NAME="myagent"
mkdir -p agents/$NAME/ledger agents/$NAME/logs
touch agents/$NAME/$NAME.sh
chmod +x agents/$NAME/$NAME.sh
touch agents/$NAME/ledger/log.jsonl
touch agents/$NAME/evolution.jsonl
# v4.0 additions:
echo '{"stage":"research","current_weakness":"W1","cycles":0,"failure_count":0,"last_run":""}' \
  > agents/$NAME/self-improve-state.json
```

**ACTIVE.md template (auto-updated by runner step 13 — MEMORY UPDATE):**
```markdown
# <Name> — Active Tasks (auto-updated every cycle)
**Last updated:** <ISO timestamp MT>

## This Cycle
- [key metrics from this run]
- Assessment: [current assessment]

## Open Issues
- [any active issues]

## Reflection Summary
- Bottleneck: [from reflection]
- Domain growth: [from reflection]
```

**Memory update is constitutional (AGENT_ALGORITHMS.md step 13).** The runner MUST
write ACTIVE.md after every cycle. Healthcheck flags stale ACTIVE.md: >24h = P2, >48h = P1.
This is how Kai's memory stays current without requiring a session.

**PRIORITIES.md template:**
```markdown
# <Name> Agent — Operational Priorities

## P0 (Critical)
- [describe the thing that must never break]

## P1 (Important)
- [describe the thing that should run reliably]

## P2 (Improvement)
- [describe what would make this agent better]

## Success Criteria
- [how do you know this agent is working?]
```

**PLAYBOOK.md template:**
```markdown
# <Name> Agent — Playbook

_Agent owns this file. Kai can override. Update after every improvement._

## Mission
[One sentence. What this agent exists to do.]

## Operational Checklist
[Steps the agent runs every cycle — evolves as agent learns.]
1. [Step 1]
2. [Step 2]
...

## Domain Reasoning
[Domain-specific questions this agent asks. Extends the universal
reasoning framework (kai/protocols/REASONING_FRAMEWORK.md).
Start with 3-5 questions. Add more as the agent learns its domain.]

- "[Domain-specific question 1]"
- "[Domain-specific question 2]"
- "[Domain-specific question 3]"

## Reflection Extensions
[Questions the agent has discovered through reflection that aren't
in the constitution yet. File proposals for constitutional additions.]

## Improvement Queue
[Things this agent wants to improve about itself.]
- [ ] [improvement 1]

## Decision Log
[Significant autonomous decisions, with reasoning.]

## Current Self-Assessment
[Honest assessment of performance. Updated every cycle.]
```

---

## 3. Manifest: Identity Card

The manifest is a JSON file that describes the agent to the rest of the system. Think of it as the agent's passport — it contains everything another agent or human needs to know to interact with it.

**Location:** `agents/manifests/<name>.hyo.json`

**Required fields:**
```json
{
  "name": "<name>.hyo",
  "version": "1.0.0",
  "identity": {
    "handle": "@<name>",
    "role": "One-sentence description of what this agent does",
    "oneLiner": "Even shorter — used in dashboards and logs",
    "operator": "hyo.world"
  },
  "capabilities": [
    "capability-one",
    "capability-two"
  ],
  "inputs": [
    "list/of/files/this/agent/reads"
  ],
  "outputs": [
    {
      "name": "output-name",
      "path": "where/it/writes",
      "format": "markdown|jsonl|json|html"
    }
  ],
  "pipeline": {
    "entrypoint": "agents/<name>/<name>.sh",
    "schedule": "cron expression or 'on-demand'",
    "scheduleTimezone": "America/Denver",
    "runtime": "bash",
    "invocation": "kai <name> [subcommands]"
  },
  "monitors": [
    {
      "id": "monitor-name",
      "description": "What this monitors",
      "frequency": "how often",
      "priority": "P0|P1|P2|P3"
    }
  ],
  "credit": {
    "tier": "founding",
    "fees": "waived"
  }
}
```

**Validation check:** After writing the manifest, parse it:
```bash
python3 -c "import json; json.load(open('agents/manifests/<name>.hyo.json')); print('valid')"
```

---

## 4. Runner Script: Execution Engine

The runner is a bash script that IS the agent. It reads state, does work, writes results, and reports back to the CEO.

**Template structure:**
```bash
#!/usr/bin/env bash
# agents/<name>/<name>.sh — <Name> agent runner
#
# Usage:
#   bash <name>.sh              # normal run
#   bash <name>.sh [subcommand] # specific operation

set -uo pipefail

# ─── Paths ────────────────────────────────────────────────────────────────────
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
AGENT_HOME="$ROOT/agents/<name>"
LOGS="$AGENT_HOME/logs"
LEDGER="$AGENT_HOME/ledger"
SECRETS="$ROOT/agents/nel/security"

mkdir -p "$LOGS"

LOG="$LOGS/<name>-$(date +%Y-%m-%d).log"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S-06:00")

log() { echo "[$TS] $*" | tee -a "$LOG"; }

# ─── Growth Phase (MANDATORY — runs before domain work) ──────────────────────
# Sources bin/agent-growth.sh which reads GROWTH.md weaknesses and runs
# the self-improve cycle (research → implement → verify) if stage indicates.
# This ensures every agent improves itself every cycle, not just runs.
if [[ -f "$ROOT/bin/agent-growth.sh" ]]; then
  source "$ROOT/bin/agent-growth.sh"
  run_growth_phase "<name>" 2>> "$LOG" || log "Growth phase skipped or errored — continuing"
fi

# ─── Forward AAR: Read anchor from previous cycle ─────────────────────────────
# Prevents cold-start: each cycle inherits context from the last successful cycle.
FORWARD_AAR_CONTEXT=""
TODAY_AAR="$LEDGER/forward-aar-$(TZ=America/Denver date +%Y-%m-%d).json"
YESTERDAY_AAR="$LEDGER/forward-aar-$(TZ=America/Denver date -d 'yesterday' +%Y-%m-%d 2>/dev/null || TZ=America/Denver date -v-1d +%Y-%m-%d).json"
for aar_file in "$TODAY_AAR" "$YESTERDAY_AAR"; do
  if [[ -f "$aar_file" ]]; then
    FORWARD_AAR_CONTEXT=$(python3 -c "
import json
try:
  d = json.load(open('$aar_file'))
  goal = d.get('next_cycle_goal', {})
  print(f\"Previous cycle direction: {goal.get('direction','')}\")
  print(f\"Question to answer: {goal.get('question','')}\")
  print(f\"Success measure: {goal.get('success_measure','')}\")
except: pass
" 2>/dev/null)
    [[ -n "$FORWARD_AAR_CONTEXT" ]] && break
  fi
done

# ─── Phase 1: [Name of phase] ────────────────────────────────────────────────
phase_one() {
  log "Phase 1: [description]"
  # ... do work ...
  # Signal on structural failure (not just dispatch flag):
  # if [[ -z "$result" ]]; then
  #   bash "$ROOT/bin/kai-signal.sh" emit "<name>" research_failure "Phase 1 returned empty" 2>/dev/null || true
  # fi
  log "Phase 1 complete"
}

# ─── Self-Review (reasoning gates — from agent-gates.sh) ─────────────────────
source "$ROOT/kai/protocols/agent-gates.sh"
run_self_review "<name>" || true

# ─── Self-Evolution (metrics + AGENT REFLECTION) ─────────────────────────────
# See AGENT_ALGORITHMS.md SELF-EVOLUTION CYCLE for the full 12-step spec.
# Key: step 10 is AGENT REFLECTION — 7 questions the agent answers honestly.
# Evolution entries MUST include reflection answers (version 2.0 format).

EVOLUTION_FILE="$AGENT_HOME/evolution.jsonl"
PLAYBOOK="$AGENT_HOME/PLAYBOOK.md"

# [Collect agent-specific metrics here — customize per domain]

# Check PLAYBOOK staleness
PLAYBOOK_UPDATED="False"
PLAYBOOK_AGE="unknown"
if [[ -f "$PLAYBOOK" ]]; then
  PLAYBOOK_MTIME=$(stat -c %Y "$PLAYBOOK" 2>/dev/null || stat -f %m "$PLAYBOOK" 2>/dev/null || echo "0")
  PLAYBOOK_AGE=$(( ($(date +%s) - PLAYBOOK_MTIME) / 86400 ))
  [[ $PLAYBOOK_AGE -lt 7 ]] && PLAYBOOK_UPDATED="True"
fi

# STEP 10: AGENT REFLECTION (constitutional — AGENT_ALGORITHMS.md v2.0)
# Collect evidence-based signals. Answer from runtime data, not canned strings.
REFLECT_BOTTLENECK="none"         # (a) What bottleneck did I hit?
REFLECT_SYMPTOM_OR_SYSTEM="system" # (b) Did I fix a symptom or the system?
REFLECT_ARTIFACT_ALIVE="yes"       # (c) Does everything I created have a life?
REFLECT_DOMAIN_GROWTH="stagnant"   # (d) Am I growing in my domain?
REFLECT_LEARNING=""                # (e) What did I learn?
# (f) Did this change propagate to all governing docs?
# (g) Is this reflection complete?

# [Customize reflection signals per agent's domain — see existing runners for examples]

# Build v2.0 evolution entry (MUST include reflection per step 11)
EVOLUTION_ENTRY=$(python3 << PYEOF
import json
entry = {
  "ts": "$TS", "version": "2.0",
  "metrics": {},  # [fill with agent-specific metrics]
  "assessment": "cycle complete",
  "playbook_updated": $PLAYBOOK_UPDATED,
  "reflection": {
    "bottleneck": "$REFLECT_BOTTLENECK",
    "symptom_or_system": "$REFLECT_SYMPTOM_OR_SYSTEM",
    "artifact_alive": "$REFLECT_ARTIFACT_ALIVE",
    "domain_growth": "$REFLECT_DOMAIN_GROWTH",
    "learning": "$REFLECT_LEARNING"
  }
}
print(json.dumps(entry))
PYEOF
)
echo "$EVOLUTION_ENTRY" >> "$EVOLUTION_FILE"
log "Self-evolution logged with reflection"

# ─── Forward AAR Write (v4.0 — prevents cold-start next cycle) ───────────────
python3 << AAREOF 2>/dev/null || true
import json
from pathlib import Path
import os
today = os.popen("TZ=America/Denver date +%Y-%m-%d").read().strip()
aar = {
  "ts": "$TS",
  "agent": "<name>",
  "next_cycle_goal": {
    "direction": "[what the next cycle should focus on — inferred from this cycle's reflection]",
    "question": "[the open question this cycle raised that next cycle should answer]",
    "success_measure": "[how next cycle will know it answered the question]"
  }
}
Path("$LEDGER/forward-aar-{}.json".format(today)).write_text(json.dumps(aar, indent=2))
AAREOF
log "Forward AAR written for next cycle"

# ─── Phase N: Report ──────────────────────────────────────────────────────────
phase_report() {
  log "Writing report"
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    bash "$dispatch_bin" report <name> "summary of what happened" 2>> "$LOG" || true
  fi
}

# ─── Error trap ───────────────────────────────────────────────────────────────
trap_error() {
  local dispatch_bin="$ROOT/bin/dispatch.sh"
  if [[ -x "$dispatch_bin" ]]; then
    bash "$dispatch_bin" flag <name> P2 "<name>.sh exited with error" 2>/dev/null || true
  fi
}
trap trap_error ERR

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  log "=== <Name> agent run ==="
  phase_one
  # ... domain-specific phases ...
  # Self-review + self-evolution run after domain work, before report
  # STEP 13: MEMORY UPDATE (constitutional — writes ACTIVE.md)
  local agent_active="$AGENT_HOME/ledger/ACTIVE.md"
  mkdir -p "$(dirname "$agent_active")"
  cat > "$agent_active" << ACTIVEEOF
# <Name> — Active Tasks (auto-updated every cycle)
**Last updated:** $(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

## This Cycle
- [key metrics summary]
- Assessment: [assessment value]

## Open Issues
- [issues from this cycle]

## Reflection Summary
- Bottleneck: [reflection bottleneck]
- Domain growth: [reflection domain growth]
ACTIVEEOF
  log "Memory update: ACTIVE.md written"

  phase_report
  log "Run complete"
}

main "$@"
```

**Critical requirements:**
1. `set -uo pipefail` — fail fast on errors and undefined variables
2. `trap trap_error ERR` — report failures to dispatch
3. `dispatch report` at the end — close the loop
4. Mountain Time timestamps — consistency across all agents
5. Logs to `agents/<name>/logs/` — one file per day
6. Secrets only from `agents/nel/security/` — never hardcoded
7. `source agent-gates.sh` + `run_self_review` — reasoning gates every cycle
8. Self-evolution with v2.0 evolution entry (MUST include `reflection` block)
9. PLAYBOOK.md must exist and be referenced for staleness checks
10. Domain-specific reflection signals — not canned "none" strings
11. MEMORY UPDATE (step 13) — write ACTIVE.md after every cycle. Healthcheck flags stale ACTIVE.md (>24h=P2, >48h=P1). This is how Kai's memory stays fresh.
12. (v4.0) **Growth phase runs first** — `source bin/agent-growth.sh && run_growth_phase` before any domain work.
13. (v4.0) **Signal emission on structural failure** — every failure path emits a `kai-signal.sh emit` in addition to dispatch flag. No silent failures.
14. (v4.0) **Forward AAR write at cycle end** — write `ledger/forward-aar-DATE.json` with next cycle's direction, question, and success measure. This is how cycles compound instead of cold-starting.
15. (v4.0) **Chaos fallback branches** — every critical dependency has a fallback path in code (not just in the manifest).

---

## 5. Dispatch Integration: Closed-Loop Communication

Every agent MUST integrate with the dispatch system. This is non-negotiable. Without dispatch, the CEO can't verify the agent ran, can't detect failures, and can't track task lifecycles.

**Minimum dispatch calls every runner must make:**
```bash
# On success:
dispatch report <name> "what happened"

# On failure:
dispatch flag <name> P<level> "what went wrong"

# On finding something noteworthy:
dispatch flag <name> P<level> "what was found"
```

**Priority levels:**
- P0: System-breaking. Immediate attention required.
- P1: Important. Should be addressed within 24 hours.
- P2: Notable. Address when convenient.
- P3: Informational. Log for pattern detection.

**Task lifecycle through dispatch:**
```
1. Kai delegates:     dispatch delegate <name> "task description"
2. Agent acknowledges: dispatch ack <task_id>
3. Agent works:       (does the work)
4. Agent reports:     dispatch report <name> "results"
5. Kai verifies:      (checks the output)
6. Kai closes:        dispatch close <task_id>
```

---

## 6. Algorithm Documentation: Runbook

Every agent gets a section in the central algorithms file (`kai/AGENT_ALGORITHMS.md`). This is the source of truth for how the agent behaves.

**Template:**
```
## <Name> — <Role Description> Algorithm

STARTUP:
  1. Read agents/<name>/PRIORITIES.md
  2. Read agents/<name>/ledger/ACTIVE.md
  3. [Agent-specific initialization]

[PHASE/CYCLE/OPERATION descriptions]:
  1. [Step with specific action]
  2. [Step with conditional: IF condition → action]
  3. [Step with dispatch call]

FAILURE MODES:
  - [Failure scenario] → [recovery action]
  - [Failure scenario] → [escalation action]
```

---

## 6.5. Agent Autonomy & Growth (v3.0 — Sessions 8 + 14)

Agents are NOT runners. They are autonomous AI with domain specialties that must grow over time. This section defines how a new agent is set up for autonomy from day one.

**Core principle (v3.0):** Questions, not reminders. A reminder says "remember to do X." A gate question asks "did I do X?" and blocks until answered YES. Every agent protocol uses gate questions. Reminders get ignored. Gates don't.

The agent decides for itself. It reports to Kai. It does not ask permission except for cross-agent interface changes, spending, or constitutional edits.

**At creation, every agent must have:**

1. **PLAYBOOK.md** — the agent's own operational manual. The agent owns this file and evolves it every cycle. Kai can override but does not write it for the agent. Template in Section 2.

2. **GROWTH.md** (v3.0 — mandatory) — 3 identified weaknesses in the agent's domain, 3 planned systemic improvements with deadlines, self-set goals. The growth phase runs BEFORE main work every cycle (sourced via `bin/agent-growth.sh`). Growth is not optional. Gate: "Does the agent have a GROWTH.md with at least 3 weaknesses and 3 improvements?" NO → create it before declaring production-ready.

3. **Domain Reasoning questions** — in PLAYBOOK.md under "## Domain Reasoning". Start with 3-5 domain-specific questions the agent should ask every cycle. These extend the universal framework at `kai/protocols/REASONING_FRAMEWORK.md`. The agent adds more as it learns. Questions must be yes/no or open-ended — never reminders.

4. **Reflection block in evolution entries** — every evolution.jsonl entry must be v2.0 format with a `"reflection"` object. Evidence-based signals only — no canned strings. Answers: bottleneck, symptom-vs-system, artifact alive, domain growth, learning, propagation check.

5. **Self-review integration** — runner sources `kai/protocols/agent-gates.sh` and calls `run_self_review("<name>")`. Extends with domain-specific gate questions.

6. **forKai inbox** (v3.0) — runner must check `kai/ledger/forkai-inbox.jsonl` for unreviewed messages addressed to this agent. Gate: "Are there unreviewed forKai messages for this agent?" YES → surface them, respond, mark reviewed before main work.

7. **ERROR-TO-GATE** (v3.0) — when any error is found during creation or operation, the fix MUST include: (a) an ACTIVE ticket in tickets.jsonl with owner + deadline ≤48h for P0/P1, (b) a gate question placed where it will be asked. A log entry without a ticket is not owned. An owned problem without a gate will recur.

**Question framework (built into every agent):**
- Open-ended to EXPLORE: "What would happen if...?", "What am I not seeing?", "What would an expert do differently?"
- Yes/no to DECIDE: "Is this triggered?", "Did this reach the user?", "Am I solving the system or patching a symptom?"
- Never reminders. Never "remember to X." Always "did I X?" with a blocking NO path.
- Pattern: explore → narrow → execute → reflect → gate

**Event-driven response:**
- When dispatch routes a P0/P1 flag to this agent, the agent's runner is queued for immediate execution (not next schedule). The agent picks up the task, acts, and reflects in the same run.

**Algorithm evolution:**
- When the agent's reflection discovers a gap, the agent files a proposal at `kai/proposals/` using `file_proposal()` from agent-gates.sh. PLAYBOOK changes can be self-approved. Constitutional changes need Kai review. See ALGORITHM EVOLUTION LIFECYCLE in `kai/AGENT_ALGORITHMS.md`.

**Dead-loop protection:**
- Healthcheck Check 8 monitors for dead-loops (same assessment/bottleneck 3+ cycles). If detected, Kai sends a guidance question — not an answer. The agent finds the answer.

---

## 6.6. Signal Bus Integration (v4.0 — 2026-04-28)

Every agent participates in the signal bus (`bin/kai-signal.sh`). Dispatch flags report what happened. Signals trigger what happens next. These are complementary, not substitutes.

**When to emit a signal vs. a dispatch flag:**
- Dispatch flag: status communication (the agent ran and this happened)
- Signal: trigger request (a structural failure occurred and the system needs to respond)

**Signal types every agent must wire:**

| Signal type | Emit when | Urgency | Who handles |
|---|---|---|---|
| `research_failure` | Phase 1 research returns empty/nil | P2 | Self-improve cycle reset |
| `api_exhausted` | API returns 429/quota error | P0 | Immediate Kai attention |
| `publish_failure` | HQ push returns non-200 | P1 | Sam retries + Kai flags |
| `verification_failure` | Post-action check fails | P1 | Agent re-queued |
| `stale_detection` | Own ACTIVE.md >48h old | P2 | Self-improve state reset |
| `quality_degradation` | SICQ or OMP drops >15 pts | P1 | Self-improve cycle triggered |
| `chaos_discovery` | Dep removal caused silent failure | P1 | P1 ticket opened by signal handler |
| `knowledge_gap` | Research finds something critical | P3 | KNOWLEDGE.md update queued |

**Signal emission pattern (add to runner on any structural failure):**
```bash
# Emit signal on structural failure (not just dispatch flag)
if [[ -f "$ROOT/bin/kai-signal.sh" ]]; then
  bash "$ROOT/bin/kai-signal.sh" emit "<agent_name>" research_failure \
    "Research returned empty for weakness $WEAKNESS on $(date +%Y-%m-%d)" \
    2>> "$LOG" || true
fi
```

**Gate question:** "For every structural failure path in this runner, does the error trap emit a signal in addition to the dispatch flag?" NO → add signal emission before declaring production-ready.

**Signal poll:** `bin/kai-autonomous.sh` polls signals every 5 minutes. Agents do not need to poll. They only emit.

---

## 6.7. Chaos Resilience (v4.0 — 2026-04-28)

Every Saturday at 05:00 MT, `bin/chaos-inject.sh` deliberately removes one dependency from each agent for ≤5 minutes and measures whether the agent detects the failure, uses a fallback, and alerts Kai. An agent that fails silently when its dependency is removed is a SPOF (single point of failure).

**At creation, every agent must have a fallback for each critical dependency:**

1. **Identify critical dependencies** — these are the things in the manifest's `inputs` field plus any binary/env dependencies the runner uses. For each one, ask: "If this disappears, does the agent crash silently or gracefully degrade?"

2. **File dependency manifest** — add to the manifest JSON:
```json
"chaos_dependencies": [
  {
    "name": "primary-data-source",
    "type": "file_dep",
    "path": "path/to/file.json",
    "fallback": "use yesterday's cached copy",
    "fallback_path": "path/to/cache/YYYY-MM-DD.json"
  },
  {
    "name": "API_KEY",
    "type": "env_dep",
    "fallback": "skip API call, use last known result",
    "fallback_path": "ledger/last-known-result.json"
  }
]
```

3. **Implement fallbacks in the runner** — every phase that reads a critical dependency must have a fallback branch:
```bash
if [[ -f "$PRIMARY_DATA" ]]; then
  data=$(cat "$PRIMARY_DATA")
else
  # Fallback: yesterday's cached data
  YESTERDAY=$(TZ=America/Denver date -d "yesterday" +%Y-%m-%d 2>/dev/null || TZ=America/Denver date -v-1d +%Y-%m-%d)
  data=$(cat "${LEDGER}/cache-${YESTERDAY}.json" 2>/dev/null || echo '{}')
  log "FALLBACK: primary data missing, using yesterday's cache"
  bash "$ROOT/bin/kai-signal.sh" emit "$AGENT_NAME" chaos_discovery \
    "Primary data missing — fallback activated" 2>/dev/null || true
fi
```

4. **Chaos test will verify:**
   - Agent detects the missing dependency (does not crash silently)
   - Agent uses the declared fallback
   - Agent emits a signal or dispatch flag (alerted = yes)
   - Agent restores correctly when the dependency returns

**Gate question:** "For every dependency in the chaos_dependencies manifest, does the runner have a tested fallback branch?" NO → add fallbacks before declaring production-ready.

**SPOF conditions (chaos-inject.sh will flag these as P1):**
- Expected fallback not triggered when primary is removed
- Silent failure (no log, no signal, no dispatch flag)
- Agent crashes instead of degrading gracefully

---

## 7. CEO/Dispatcher Integration: Routing

The CEO dispatcher (`bin/kai.sh`) must know how to invoke the agent.

**Add to the case statement:**
```bash
<name>)  bash "$ROOT/agents/<name>/<name>.sh" "$@" ;;
```

**Add to the help text:**
```
kai <name>                Run the <Name> agent
```

**Add to the agent list in push help:**
```
agent: ra|aurora|sentinel|cipher|sim|consolidation|aether|dex|<name>
```

---

## 8. Dashboard/UI Integration: Visibility

If the agent produces data that should be visible in a dashboard:

1. Create a Vercel API endpoint: `website/api/<name>.js`
2. Add a view section in `website/hq.html`
3. Add navigation entry in the sidebar
4. Wire the data loading function
5. Mirror changes to `agents/sam/website/` if that copy exists

**API endpoint template (Vercel serverless):**
```javascript
export default function handler(req, res) {
  const { action } = req.query;
  
  if (req.method === 'GET' && action === 'metrics') {
    return res.json(globalThis.__<name> || { status: 'no data' });
  }
  
  if (req.method === 'POST' && action === 'metrics') {
    // Validate token
    const token = req.headers['x-founder-token'];
    // Store data
    globalThis.__<name> = req.body;
    return res.json({ ok: true });
  }
  
  return res.json({ agent: '<name>', status: 'operational' });
}
```

---

## 9. Schedule: Automation (v4.0 — kai-autonomous.sh model)

**v4.0 scheduling model:** All agents are invoked by the central orchestrator `bin/kai-autonomous.sh`, which runs every 5 minutes via a single launchd plist (`com.hyo.kai-autonomous.plist`). Adding a new agent to the schedule means adding a `check_and_dispatch` call to kai-autonomous.sh — not creating a new plist.

This eliminates per-agent plist management overhead, centralizes scheduling in one auditable file, and enables the signal bus to trigger agents event-driven without scheduler involvement.

**To schedule a new agent, add to `bin/kai-autonomous.sh`:**
```bash
# ─── <Name> agent (daily at HH:MM MT) ────────────────────────────────────────
check_and_dispatch HH MM "<name>-daily" \
  "HYO_ROOT=$HYO_ROOT bash $HYO_ROOT/agents/<name>/<name>.sh" \
  "<name>-daily-$(date +%Y%m%d)"
```

The `check_and_dispatch` function handles:
- Time-keyed state files (prevents double-firing within the same day/week)
- Logging all invocations to `kai/ledger/orchestrator.log`
- Background execution with stdout → daily log file
- Idempotency: if the state key file exists, skip

**State key patterns:**
```bash
# Daily: only fires once per calendar day
"<name>-daily-$(date +%Y%m%d)"

# Weekly (specific day): only fires once per ISO week
"<name>-weekly-$(date +%Y-%W)"

# Weekly (any day): keyed to ISO week
"<name>-$(date +%Y%m%d)"  # still daily if you want Mon-Sat

# First run this month:
"<name>-monthly-$(date +%Y%m)"
```

**Current system schedule (for reference — all driven by kai-autonomous.sh):**
| Time (MT) | Day | Script | State key pattern |
|---|---|---|---|
| 04:30 | Mon–Sat | agent-self-improve.sh all | self_improve_run_YYYYMMDD |
| 05:00 | Saturday | chaos-inject.sh | chaos_inject_YYYYMMDD |
| 05:00 | Daily | generate-morning-report.sh | morning_report_YYYYMMDD |
| 05:30/09:30/13:30/17:30/21:30 | Daily | flywheel-doctor (SICQ/OMP) | flywheel_doctor_HHYYYMMDD |
| 06:45 | Mon–Sat | cross-agent-review.sh | cross_agent_review_YYYYMMDD |
| 07:15 | Monday | double-loop-review.sh | double_loop_review_YYYY-WW |
| 16:30 | Mon–Sat | agent-self-improve.sh all | self_improve_run_midday_YYYYMMDD |
| 22:00–23:30 | Daily | Agent runners (nel, sam, aether) | per-agent-daily-YYYYMMDD |
| 03:00 | Daily | Ra newsletter pipeline | ra_newsletter_YYYYMMDD |
| 02:00 | Saturday | weekly-maintenance.sh | weekly_maintenance_YYYYWW |

**Existing launchd plist (one plist, one orchestrator):**
```xml
<!-- com.hyo.kai-autonomous.plist — the only plist you need to install -->
<key>StartInterval</key>
<integer>300</integer>  <!-- every 5 minutes -->
```

**If you need sub-5-minute intervals** (e.g., Aether's 15-minute market polling), the agent manages its own interval check internally — not via a separate plist. Example:
```bash
# Agent checks its own last-run time and skips if too recent
LAST_RUN=$(cat "$LEDGER/last-run.txt" 2>/dev/null || echo "0")
NOW=$(date +%s)
if (( NOW - LAST_RUN < 900 )); then  # 900s = 15 min
  exit 0
fi
echo "$NOW" > "$LEDGER/last-run.txt"
```

---

## 10. Testing Protocol: 15-Point Validation (v4.0)

Run ALL 15 tests before declaring an agent production-ready. No exceptions.
Gate question: "Did I pass all 15 tests?" NO → fix failures before shipping.

### Test 1: Manifest Validation
```bash
python3 -c "import json; d=json.load(open('agents/manifests/<name>.hyo.json')); print('PASS' if 'name' in d and 'capabilities' in d else 'FAIL')"
```
- Valid JSON
- Required fields present
- No stale references to old names
- Paths point to correct directories

### Test 2: Runner Script Syntax
```bash
bash -n agents/<name>/<name>.sh && echo "PASS" || echo "FAIL"
```

### Test 3: File Structure Completeness
```bash
for f in agents/<name>/<name>.sh agents/<name>/PRIORITIES.md agents/<name>/ledger/ACTIVE.md agents/<name>/ledger/log.jsonl; do
  [[ -f "$f" ]] && echo "PASS: $f" || echo "FAIL: $f missing"
done
[[ -d agents/<name>/logs ]] && echo "PASS: logs/" || echo "FAIL: logs/ missing"
[[ -x agents/<name>/<name>.sh ]] && echo "PASS: executable" || echo "FAIL: not executable"
```

### Test 4: Dispatcher Integration
```bash
grep -q "<name>" bin/kai.sh && echo "PASS" || echo "FAIL: not in kai.sh"
```

### Test 5: API Endpoint (if applicable)
```bash
[[ -f website/api/<name>.js ]] && node -c website/api/<name>.js && echo "PASS" || echo "FAIL or N/A"
```

### Test 6: Dashboard Integration (if applicable)
```bash
grep -c "<name>" website/hq.html  # Should be > 0 if dashboard view exists
grep -c "oldname" website/hq.html  # Should be 0 — no stale references
```

### Test 7: Dispatch Integration
```bash
grep -c "dispatch" agents/<name>/<name>.sh  # Should be >= 2 (report + flag)
```

### Test 8: Algorithm Documented
```bash
grep -q "## <Name>" kai/AGENT_ALGORITHMS.md && echo "PASS" || echo "FAIL"
```

### Test 9: PLAYBOOK, GROWTH, Evolution Files Exist
```bash
[[ -f agents/<name>/PLAYBOOK.md ]] && echo "PASS: PLAYBOOK" || echo "FAIL: PLAYBOOK missing"
[[ -f agents/<name>/evolution.jsonl ]] && echo "PASS: evolution" || echo "FAIL: evolution.jsonl missing"
[[ -f agents/<name>/GROWTH.md ]] && echo "PASS: GROWTH.md" || echo "FAIL: GROWTH.md missing"
[[ -f agents/<name>/self-improve-state.json ]] && echo "PASS: self-improve-state.json" || echo "FAIL: self-improve-state.json missing"
grep -q "Domain Reasoning" agents/<name>/PLAYBOOK.md && echo "PASS: domain reasoning section" || echo "FAIL: no Domain Reasoning in PLAYBOOK"
python3 -c "import json; d=json.load(open('agents/<name>/self-improve-state.json')); print('PASS: state valid')" || echo "FAIL: self-improve-state.json invalid JSON"
```

### Test 10: Self-Review & Reflection Integration
```bash
grep -q "agent-gates.sh" agents/<name>/<name>.sh && echo "PASS: sources agent-gates" || echo "FAIL: no agent-gates.sh"
grep -q "run_self_review" agents/<name>/<name>.sh && echo "PASS: runs self-review" || echo "FAIL: no self-review call"
grep -q "reflection" agents/<name>/<name>.sh && echo "PASS: reflection block" || echo "FAIL: no reflection in evolution"
```

### Test 11: Autonomy Readiness
```bash
grep -q "Improvement Queue" agents/<name>/PLAYBOOK.md && echo "PASS: improvement queue" || echo "FAIL: no improvement queue"
grep -q "Decision Log" agents/<name>/PLAYBOOK.md && echo "PASS: decision log" || echo "FAIL: no decision log"
grep -q "Self-Assessment" agents/<name>/PLAYBOOK.md && echo "PASS: self-assessment" || echo "FAIL: no self-assessment"
```

### Test 12: Simulation Clean (PROTOCOL-001 — mandatory)
```bash
bash bin/dispatch.sh simulate 2>&1 | tail -5
# Gate: "Are there NEW failures not present before this agent was created?"
# YES → fix them. NO → continue.
```
- Run dispatch simulate after wiring the agent in
- No new failures introduced by the new agent's files, runners, or data
- Pre-existing known failures are acceptable (they have tickets)
- This test must run and pass. "I'll run it later" = FAIL.

### Test 13: Live Surface Verify (PROTOCOL-001 — mandatory)
```bash
curl -s https://www.hyo.world/hq | grep -o "<agent-name>\|<agent-output>"
# Gate: "Does the agent's output appear on the live HQ surface?"
# NO → trace the path: data file → feed.json entry → HQ renderer → live URL
```
- Agent's first report appears in HQ feed
- readLink resolves (no 404)
- Report typography matches other reports (Plus Jakarta Sans, JetBrains Mono)
- Live ETag updated after push
- "Vercel shows READY" is not sufficient — grep the live content.

### Test 14: Signal Emission Wiring (v4.0 — mandatory)
```bash
# Verify the runner contains at least one kai-signal.sh emit call
grep -q "kai-signal.sh emit" agents/<name>/<name>.sh && echo "PASS: signal emission present" || echo "FAIL: no signal emission found"

# Verify growth phase is sourced
grep -q "agent-growth.sh" agents/<name>/<name>.sh && echo "PASS: growth phase present" || echo "FAIL: no growth phase sourced"

# Verify forward AAR write is present
grep -q "forward-aar" agents/<name>/<name>.sh && echo "PASS: forward AAR write present" || echo "FAIL: no forward AAR write"
```
- Gate: "Does every structural failure path in this runner emit a signal?" NO → add signal calls before shipping.
- This is what separates an agent that fails silently from one that triggers system-level response.

### Test 15: Chaos Resilience (v4.0 — mandatory)
```bash
# Verify chaos_dependencies is declared in the manifest
python3 -c "
import json
d = json.load(open('agents/manifests/<name>.hyo.json'))
deps = d.get('chaos_dependencies', [])
print(f'PASS: {len(deps)} chaos dependencies declared' if deps else 'FAIL: no chaos_dependencies in manifest')
"

# Verify at least one fallback branch exists in runner
grep -q "FALLBACK\|fallback" agents/<name>/<name>.sh && echo "PASS: fallback branch present" || echo "FAIL: no fallback branch found"
```
- Gate: "For every dependency listed in chaos_dependencies, does the runner have a fallback branch in code?" NO → add fallbacks before shipping.
- chaos-inject.sh will test this on Saturday. Better to find SPOFs in testing than production.

**Scoring:** All 15 must PASS. Any FAIL blocks production deployment.
Tests 12, 13, 14, and 15 are the most commonly skipped — all are mandatory every time, without exception (PROTOCOL-001, session 14; PROTOCOL-003, v4.0).

---

## 11. Migration Protocol: Renaming/Restructuring

When an agent needs to be renamed (e.g., "aetherbot" → "aether"):

**Phase 1: Create new files**
1. Create new directory structure under the new name
2. Copy each file, renaming content (agent name, paths, variables, function names)
3. Create new manifest with updated name
4. If API endpoint exists: create new endpoint file with renamed content
5. If dashboard references exist: update HTML, CSS classes, data attributes, function names

**Phase 2: Update cross-cutting files**
These files reference agents by name and must be updated:
- `bin/kai.sh` (dispatcher routing + help text)
- `kai/AGENT_ALGORITHMS.md` (algorithm section header + content)
- `KAI_BRIEF.md` (shipped items, scheduled tasks, operational model)
- `KAI_TASKS.md` (any tasks referencing the agent)
- `CLAUDE.md` (project layout, hydration protocol)
- `agents/nel/nel.sh` (consolidation targets)
- `agents/nel/consolidation/consolidate.sh` (project list)
- All files in `agents/nel/logs/` and `website/docs/` that mention the agent
- `NFT/HyoRegistry_Notes.md` (if agent is registered)

**Phase 3: Delete old files**
Only after verifying zero orphaned references:
```bash
grep -r "oldname" . --include="*.sh" --include="*.js" --include="*.json" --include="*.md" --include="*.html"
```
If this returns zero results, delete the old directory and manifest.

**Phase 4: Full test protocol**
Run all 8 tests from Section 10 on the renamed agent.

---

## 12. Post-Creation: Maintenance (v4.0)

**Every cycle (automated — built into the runner):**
- Growth phase runs first (`agent-growth.sh`) — self-improve cycle progresses
- Self-review via agent-gates.sh (trigger validation, visibility, recall)
- Self-evolution with reflection (7 questions, evidence-based answers)
- Evolution entry written with reflection block (v2.0 format)
- Forward AAR written to `ledger/forward-aar-DATE.json`
- PLAYBOOK.md updated if anything changed

**Daily:**
- Agent runs on schedule (verify via logs or dispatch status)
- No P0/P1 flags raised
- Reflection answers in evolution.jsonl are not all "none" — agent is actually reflecting
- SICQ/OMP scores computed by flywheel-doctor (5x/day at 05:30/09:30/13:30/17:30/21:30 MT)
- Cross-agent review runs Mon–Sat (06:45 MT) — checks for regression across agents

**Weekly (Monday):**
- Double-loop review fires at 07:15 MT (double-loop-review.sh)
  - Q1: Are agents working on the right problems?
  - Q2: What assumptions are stale?
  - Q3: Which agents have hit a capability ceiling?
  - Q4: What capability gap needs filling?
  - Q5: Are we measuring the right things?
  - Q6: What should we stop doing?
- Review PRIORITIES.md — are priorities still correct?
- Check ledger/ACTIVE.md — any stale tasks?
- Check evolution.jsonl — is domain_growth "active" or "stagnant"?
  If stagnant 3+ weeks → Kai sends guidance question (dead-loop protocol)

**Weekly (Saturday):**
- Chaos injection test fires at 05:00 MT (chaos-inject.sh)
  - One dependency removed per agent for ≤5 min
  - SPOF found → P1 ticket opened automatically
  - Weekly maintenance at 02:00 MT (compaction, log rotation, archive)
- Run full 15-point test protocol on any agent that had code changes this week

**On a recurring basis (not monthly — interval depends on agent activity):**
- Review manifest — capabilities still accurate?
- Review proposals — has the agent filed any algorithm evolution proposals?
  (No proposals in 30 days from an active agent → either the system is perfect
  or the agent isn't reflecting deeply enough. Investigate.)
- Dex (or equivalent memory manager) runs compaction on the agent's ledger weekly via weekly-maintenance.sh

**On every code change:**
- Run `bash -n` syntax check
- Run dispatch integration check (grep for dispatch calls)
- Verify signal emission still present (grep for `kai-signal.sh emit`)
- Verify forward AAR write still present (grep for `forward-aar`)
- Verify no broken references (grep for the agent name in changed files)
- **PROPAGATION CHECK:** If this changes agent behavior, update PLAYBOOK.md,
  evolution.jsonl, and AGENT_ALGORITHMS.md if cross-agent. If this changes
  how new agents should be built, update THIS PROTOCOL.

---

## 13. Appendix: Failure Catalog

Failures we've hit in production, documented so they never happen again.

**F1: SDK schema mismatch**
- Symptom: "Tool X expected a Zod schema or ToolAnnotations, but received an unrecognized object"
- Cause: MCP SDK v1.29.0 requires Zod schemas, not plain JS objects
- Fix: Import `{ z } from "zod"` and use `z.string()`, `z.number().optional()`, etc.
- Prevention: Always check SDK version requirements before building tool definitions

**F2: Orphaned references after rename**
- Symptom: Dashboard shows old agent name, dispatch routes to nonexistent path
- Cause: Incomplete search during rename — missed files in docs/, logs/, website/
- Fix: `grep -r "oldname" . --include="*.{sh,js,json,md,html}"` before deleting old files
- Prevention: Section 11 of this protocol. Run the orphan scan. Every time.

**F3: Silent task drops**
- Symptom: Task delegated but never completed, no error, no flag
- Cause: Agent runner didn't integrate with dispatch — no ACK, no report
- Fix: Add dispatch report/flag calls (Section 5)
- Prevention: Test 7 in the testing protocol catches this

**F4: Dispatch flag with wrong agent name**
- Symptom: Flag appears in wrong agent's ledger, can't trace back to source
- Cause: Copy-paste from another agent's runner without updating the agent name
- Fix: Grep the runner for `dispatch.*<oldname>` and fix
- Prevention: Test 7 specifically checks that dispatch calls use the correct agent name

**F5: Missing error trap**
- Symptom: Agent crashes silently, no dispatch flag, no one knows
- Cause: No `trap trap_error ERR` in the runner
- Fix: Add the error trap (see runner template in Section 4)
- Prevention: Test 7 checks for dispatch flag calls, which implies trap exists

**F6: Hardcoded secrets**
- Symptom: API key committed to git
- Cause: Secret written directly in script instead of reading from secrets directory
- Fix: Move to agents/nel/security/, gitignore, mode 600
- Prevention: Nel's cipher.sh scans for this. Also: never accept a key as a variable — always read from file at runtime.

**F7: Timezone drift**
- Symptom: Monday reset fires on Sunday, logs show wrong dates
- Cause: Using system timezone instead of explicit `TZ="America/Denver"`
- Fix: Prefix all date commands with `TZ="America/Denver"`
- Prevention: Runner template includes this. Nel checks for UTC timestamps.

**F8: Dashboard loads stale data**
- Symptom: HQ shows old metrics even after agent runs
- Cause: Dashboard reads from static JSON file but agent pushes to API — API uses in-memory store that resets on cold start
- Fix: Agent writes to static JSON (file-based persistence) AND pushes to API (live updates)
- Prevention: Dual-write pattern in Aether's runner. Both paths must be present.

**F9: Governance propagation gap (Session 8 P0)**
- Symptom: New agent built from stale protocol — missing PLAYBOOK, reflection, autonomy model
- Cause: Operating model changed (constitutional v3.0) but creation protocol wasn't updated. End-of-session checklist didn't include propagation check.
- Fix: v2.0 of this protocol. Propagation check added to Kai's reflection loop (question 6) and agent's reflection loop (question f).
- Prevention: Reflection question 6/f: "Did this change how the system operates? Did ALL governing docs get updated?" Applied every cycle, not just when remembered. The spec is not the implementation. The creation protocol is not the constitution. ALL must be current.

**F10: Spec without implementation (Session 8 P0)**
- Symptom: Constitution says agents should reflect, but runner code writes evolution entries without reflection
- Cause: Updated the spec (AGENT_ALGORITHMS.md) but didn't verify the execution layer (runner bash code) matches
- Fix: All 5 runners updated with reflection blocks
- Prevention: Trigger Validation Gate must always chase to the execution layer. "Is it mentioned?" ≠ "Does code run it?"

**F11: No signal emission on structural failure (v4.0)**
- Symptom: Agent research phase returns empty, ARIC cycle stalls for days with no system response. No one notices until the morning report is consistently hollow.
- Cause: Runner dispatched a flag but did not emit a `kai-signal.sh emit` signal. Dispatch flags are status — they don't trigger the improvement system. Signals do.
- Fix: Add signal emission to every structural failure path (empty research, API exhausted, verification failed). Template in Section 4.
- Prevention: Test 14 in the testing protocol. Gate question: "For every failure path, does an emit call exist?" NO = FAIL.

**F12: No fallback for dependency removed by chaos (v4.0)**
- Symptom: chaos-inject.sh removes an input file or env var; agent crashes silently. No log. No signal. No dispatch flag. SPOF logged as P1. Weekly chaos test catches it but production load is now a question mark.
- Cause: Agent was built assuming its primary data source is always present. No fallback branch exists in code.
- Fix: For every critical dependency in the manifest, add a fallback branch that (a) logs "FALLBACK activated", (b) uses yesterday's cached data or a safe default, (c) emits a `chaos_discovery` signal so the system knows it degraded.
- Prevention: Test 15 in the testing protocol. Gate question: "For every chaos_dependencies entry, is there a fallback branch in code?" NO = FAIL. chaos-inject.sh will also catch this on Saturday — but it's better to catch it at creation than in weekly testing.

---

## License

**This protocol is proprietary to hyo.world.**

It may be licensed for use in other autonomous agent systems. The protocol represents a condensed operational blueprint built from production failures across 8 agents, 4 months, and 15+ sessions of real autonomous operation — not academic theory.

**What licensees receive:**
- Complete, repeatable creation protocol (this document)
- All supporting scripts referenced herein (agent-growth.sh, kai-signal.sh, chaos-inject.sh, agent-gates.sh, kai-autonomous.sh, weekly-maintenance.sh)
- Agent templates (PLAYBOOK.md, GROWTH.md, evolution.jsonl, PRIORITIES.md)
- Failure catalog — 12 documented production failures with root cause and prevention
- Protocol versioning history from v1.0 through current production version

**Licensing model:** Per-organization license. No per-agent fees. Contact hyo.world for licensing inquiries and pricing.

**Not included in standard license:** hyo.world-specific API integrations, Aether trading analysis, Ra newsletter pipeline, HQ dashboard frontend. These are available as add-on packages.

---

*Built through production failures, not theory. Every line exists because something broke without it.*
*v4.0 — 2026-04-28 — 15-point testing, chaos resilience, signal bus, forward AAR chain.*
