# Resolution Algorithm (RA-1)

**Version:** 1.0
**Author:** Kai (prompted by Hyo, session 8)
**Constitutional authority:** This protocol is part of AGENT_ALGORITHMS.md. All agents MUST follow it.
**Evolution:** This algorithm self-evolves. Every resolution report includes a "process improvements" section that feeds back into this document. Agents propose changes; Kai approves.

---

## Purpose

A closed-loop system for resolving issues that ensures:
1. Every problem is fully understood before action
2. Every fix is verified, not assumed
3. Every resolution is documented for recall
4. The system learns from every resolution and gets faster

This replaces patchwork fixing. No more "flag it and move on." No more "fix one symptom, miss the class."

---

## The Algorithm

```
┌─────────────────────────────────────────────────────────┐
│  RESOLUTION ALGORITHM (RA-1)                            │
│  Mandatory for ALL agents. No shortcuts. No patchwork.  │
└─────────────────────────────────────────────────────────┘

STEP 0: RECALL
  Before touching anything, check for prior art:
  - Search kai/ledger/resolutions/ for similar past resolutions
  - Search kai/ledger/known-issues.jsonl for related patterns
  - Search the resolving agent's evolution.jsonl for prior attempts
  IF a prior resolution exists:
    - Read it fully
    - Note what worked and what didn't
    - Do NOT repeat failed approaches
  OUTPUT: Prior resolution IDs (or "none found")

STEP 1: IDENTIFY
  Define the issue precisely. No ambiguity.
  - What is the reported issue/error/concern?
  - Who reported it? (Hyo, agent, healthcheck, simulation, user)
  - What is the EXPECTED behavior?
  - What is the ACTUAL behavior?
  - What is the IMPACT? (who/what is affected, severity)
  - What is the CLASS of failure? (not just this instance — what
    category does it belong to?)
  OUTPUT: Issue statement (1-3 sentences, precise)

STEP 2: ANALYZE ROOT CAUSE
  Don't fix the symptom. Find the root.
  - WHY did this happen? (not "what" — "why")
  - WHY wasn't it caught earlier? (which safety nets failed?)
  - Is this a ONE-OFF or a PATTERN?
  - If pattern: how many instances exist? Search the codebase.
  - What SYSTEM allowed this to happen? (the system is the bug, 
    not the symptom)
  OUTPUT: Root cause statement + class of failure identified

STEP 3: DEFINE ACTIONABLE TASKS
  Break the fix into discrete, verifiable tasks.
  Each task must have:
  - A clear completion criterion (how do we KNOW it's done?)
  - An owner (which agent or Kai)
  - A verification method (how do we test it?)
  Tasks fall into two categories:
  a) IMMEDIATE FIX — resolve this specific instance
  b) SYSTEMIC PREVENTION — prevent this class of failure
  Both are required. Fixing without prevention is patchwork.
  PRE-CHECK: For every detection task, confirm a corresponding
  remediation task exists. Detection without remediation is incomplete.
  If a system can flag a problem but not fix it, add a remediation task.
  OUTPUT: Numbered task list with owners and verification methods

STEP 4: EXECUTE TASKS
  For each task:
  a) Execute the fix
  b) Record what was done (exact changes, files modified, commands run)
  c) Record any unexpected findings during execution
  d) If execution fails → log WHY → adjust approach → retry
     (max 3 retries with different approaches before escalating)
  OUTPUT: Execution log per task

STEP 5: VERIFY EACH TASK
  For each completed task:
  a) Run the task's verification method
  b) Confirm EXPECTED behavior is now ACTUAL behavior
  c) Test the NEGATIVE case (does the system catch it if it regresses?)
  d) Verify the system can SELF-HEAL without human intervention.
     If fixing requires a session to be open, the fix is incomplete.
  e) If verification fails → return to STEP 4 with new approach
  OUTPUT: Verification results (PASS/FAIL per task)

STEP 6: RUN SIMULATION
  After all tasks verified individually:
  a) Run `dispatch simulate` (or relevant subset)
  b) Check for regressions — did fixing this break something else?
  c) Run the detecting system(s) against the fixed state
     (e.g., if healthcheck found it, run healthcheck again)
  d) If simulation reveals new issues → return to STEP 1 for each
  OUTPUT: Simulation results

STEP 7: GENERATE RESOLUTION REPORT
  Create a complete record at kai/ledger/resolutions/RES-<NNN>.md:

  Required sections:
  - ID: RES-<NNN>
  - Date: ISO with MT offset
  - Reporter: who/what surfaced the issue
  - Issue: from STEP 1
  - Root cause: from STEP 2
  - Class of failure: the category this belongs to
  - Prior art: related resolutions consulted (from STEP 0)
  - Tasks executed: from STEP 3-4
  - Verification results: from STEP 5
  - Simulation results: from STEP 6
  - What worked: approaches that succeeded
  - What failed: approaches that didn't work and WHY
  - Process improvements: how RA-1 itself should evolve based on this
  - Prevention: what systemic changes prevent this class of failure
  - Tags: searchable keywords for RECALL in future resolutions

  OUTPUT: Saved report at kai/ledger/resolutions/RES-<NNN>.md

STEP 8: UPDATE SYSTEM MEMORY
  a) Append to kai/ledger/known-issues.jsonl (pattern + prevention)
  b) Update the resolving agent's evolution.jsonl
  c) Update the resolving agent's PLAYBOOK.md if workflow changed
  d) Update AGENT_ALGORITHMS.md if cross-agent behavior changed
  e) IF process improvements were identified in STEP 7 →
     propose amendments to THIS algorithm (RESOLUTION_ALGORITHM.md)
  f) Update KAI_BRIEF.md and KAI_TASKS.md
  OUTPUT: All system memory updated

STEP 9: CLOSE
  a) Confirm: issue resolved, prevention in place, report saved
  b) Log closure to the agent's ledger
  c) Commit and push all changes
  OUTPUT: Resolution complete
```

---

## Recall Protocol

Resolution reports are useless if they're never read. Here's when to recall:

```
MANDATORY RECALL (always search resolutions before these):
  - Starting ANY issue resolution (STEP 0 above)
  - Session hydration (scan recent resolutions for context)
  - Agent self-evolution phase (check if resolutions changed workflow)
  - Before modifying any file that was part of a prior resolution
  - When a healthcheck/Nel/simulation flags something

HOW TO RECALL:
  Quick: grep -l "<keyword>" kai/ledger/resolutions/RES-*.md
  Full:  python3 kai/protocols/recall.py "<keyword or class>"
  Recent: ls -t kai/ledger/resolutions/ | head -5

RECALL TRIGGERS (automatic, wired into agent runners):
  - Agent detects an issue → recall similar issues before acting
  - Agent starts a new task → recall related resolutions
  - Weekly evolution review → recall all resolutions from past week
  - Nightly simulation → recall resolutions related to any failures
```

---

## Evolution Protocol

This algorithm MUST evolve. Here's how:

```
EVOLUTION TRIGGERS:
  1. Every resolution's STEP 7 "process improvements" section
  2. Hyo feedback (explicit or pattern-detected)
  3. Weekly review of resolution metrics (time-to-resolve, retry count)
  4. Agent proposals (any agent can propose amendments)

EVOLUTION PROCESS:
  1. Proposed change logged to kai/protocols/evolution.jsonl
  2. Kai reviews: APPROVE / MODIFY / REJECT
  3. If approved: update this file, bump version, log change
  4. All agents pick up changes on next hydration/run

AGENT SPECIALIZATION:
  As agents accumulate resolutions, patterns emerge. Each agent 
  SHOULD build domain-specific extensions to this algorithm in 
  their PLAYBOOK.md. Examples:
  - Nel: security-specific resolution steps (scan, patch, verify, re-scan)
  - Sam: deploy-specific steps (build, test, stage, deploy, verify live)
  - Ra: content-specific steps (source, synthesize, render, verify output)
  - Aether: trading-specific steps (backtest, paper-trade, verify, go-live)

  These extensions INHERIT from RA-1 (they add steps, not replace them).
  The core loop (identify → analyze → fix → verify → simulate → report)
  is always preserved.

METRICS TO TRACK (per resolution):
  - Time from detection to resolution
  - Number of retries before success
  - Whether RECALL found useful prior art
  - Whether the same class of failure recurs
  - Whether the prevention measures held
```

---

## Quick Reference (for agents)

```
Issue detected
     │
     ▼
 STEP 0: RECALL prior resolutions
     │
     ▼
 STEP 1: IDENTIFY precisely (what, expected, actual, impact, class)
     │
     ▼
 STEP 2: ROOT CAUSE (why, why not caught, pattern or one-off)
     │
     ▼
 STEP 3: DEFINE TASKS (immediate fix + systemic prevention)
     │
     ▼
 STEP 4: EXECUTE ──────── fail? ──→ retry (max 3) ──→ escalate
     │
     ▼
 STEP 5: VERIFY each task ── fail? ──→ back to STEP 4
     │
     ▼
 STEP 6: SIMULATE ──── new issues? ──→ STEP 1 for each
     │
     ▼
 STEP 7: REPORT (save to kai/ledger/resolutions/RES-<NNN>.md)
     │
     ▼
 STEP 8: UPDATE MEMORY (known-issues, evolution, playbook, brief)
     │
     ▼
 STEP 9: CLOSE (confirm, commit, push)
```
