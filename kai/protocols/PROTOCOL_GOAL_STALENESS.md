# PROTOCOL_GOAL_STALENESS.md
# Version: 1.0
# Author: Kai
# Date: 2026-04-21
# Status: AUTHORITATIVE — Kai runs this daily as part of Daily Bottleneck Audit

---

## PURPOSE

Agents set goals. Goals go stale. Stale goals mean agents are executing tasks without a
strategic direction — becoming reactive instead of growing. Kai is responsible for detecting
stale short, medium, and long-term goals and pushing agents to continue executing.

"Kai needs to identify if an agent has a stale short, medium or long term goal and run an
algorithm/protocol to ensure that they are being pushed and continues to execute successfully."
— Hyo, 2026-04-21

This protocol defines the algorithm for detecting staleness, the questions that precede any
push, and the simulation gate that verifies the push is working.

---

## ALGORITHM-FIRST: THE GOAL STALENESS GATE

```
GOAL STALENESS GATE (Kai runs daily):

For each agent (nel, ra, sam, dex — NOT aether's internal goals):

GATE 1: Does the agent have active goals in GROWTH.md?
  → Read agents/<agent>/GROWTH.md Goals section
  → NO goals defined → P2 flag: "Agent has no self-set goals; run ARIC to define them"

GATE 2: When was each goal last progressed?
  → Check agents/<agent>/evolution.jsonl for entries referencing each goal
  → Check agents/<agent>/ledger/ACTIVE.md for active goal work
  → Check kai/tickets/tickets.jsonl for improvement tickets linked to the goal

GATE 3: Is the short-term goal (< 2 weeks) overdue?
  → Short-term goal deadline passed with no completion evidence → STALE (P1)

GATE 4: Is the medium-term goal (2-8 weeks) stale (no progress for > 14 days)?
  → No evolution.jsonl entry referencing this goal in 14 days → STALE (P2)

GATE 5: Is the long-term goal (> 8 weeks) stale (no progress for > 30 days)?
  → No evolution.jsonl entry referencing this goal in 30 days → STALE (P2)

GATE 6: Is an agent showing the same goal assessment 3+ consecutive cycles?
  → "Same assessment" = nearly identical text in evolution.jsonl entries
  → YES → DEAD-LOOP detected (P1); trigger Kai Guidance Protocol

GATE 7: Is an agent's improvement ticket (GROWTH.md W1/W2/W3) in PROPOSED status > 14 days?
  → YES → STALE (P2); escalate to active work or close as "won't do" with reason
```

---

## SECTION 1: GOAL TIMEFRAME DEFINITIONS

### Short-Term Goals (< 2 weeks)
- Scope: specific feature, specific script, specific fix
- Evidence of completion: commit hash, test result, published output
- Staleness threshold: overdue by > 3 days = STALE
- Action: P1 ticket opened, Kai asks guidance question

### Medium-Term Goals (2-8 weeks)
- Scope: capability area (e.g., "source health monitoring for Ra")
- Evidence of progress: at least one shipped component per week
- Staleness threshold: no progress in 14 days = STALE
- Action: P2 ticket opened, Kai checks for blockers

### Long-Term Goals (> 8 weeks)
- Scope: strategic capability (e.g., "full editorial feedback loop for Ra")
- Evidence of progress: at least one shipped component per 2 weeks
- Staleness threshold: no progress in 30 days = STALE
- Action: P2 flag, Kai reviews whether goal is still valid

---

## SECTION 2: DETECTING STALENESS — THE DAILY SCAN

Kai runs this scan as part of the Daily Bottleneck Audit (see AGENT_ALGORITHMS.md):

```python
#!/usr/bin/env python3
# Pseudocode for goal staleness scan (implemented in bin/goal-staleness-check.py)

import json, datetime, pathlib

ROOT = pathlib.Path.home() / "Documents/Projects/Hyo"
NOW = datetime.datetime.now(datetime.timezone.utc)

AGENTS = ["nel", "ra", "sam", "dex"]  # NOT aether (external scope only)

for agent in AGENTS:
    growth_file = ROOT / f"agents/{agent}/GROWTH.md"
    evolution_file = ROOT / f"agents/{agent}/evolution.jsonl"

    # Parse goals from GROWTH.md "## Goals" section
    goals = parse_goals(growth_file)  # returns list of {title, deadline, timeframe}

    # Get last evolution entry date
    last_evolution = get_last_evolution_date(evolution_file)

    for goal in goals:
        # Check if goal appears in any evolution entry in the relevant window
        window = {"short": 3, "medium": 14, "long": 30}[goal["timeframe"]]
        last_progress = get_last_goal_progress(evolution_file, goal["title"])
        days_stale = (NOW - last_progress).days if last_progress else 9999

        if days_stale > window:
            severity = "P1" if goal["timeframe"] == "short" else "P2"
            print(f"STALE GOAL [{severity}]: {agent} | {goal['title']} | {days_stale}d no progress")
            # Open ticket
```

### Implementation: bin/goal-staleness-check.py

This script runs daily at 06:00 MT (before morning report generation) and:
1. Scans each agent's GROWTH.md for goals and deadlines
2. Checks evolution.jsonl for recent goal-referencing entries
3. Checks tickets.jsonl for open improvement tickets
4. Flags stale goals with severity
5. Outputs findings for morning report

---

## SECTION 3: THE PUSH ALGORITHM — KAI GUIDANCE PROTOCOL

When a goal is stale, Kai does NOT do the agent's work. Kai asks questions.
This is the Kai Guidance Protocol applied to goal staleness.

### Step 1: Diagnose the Staleness Type

```
DIAGNOSIS GATE:

Q1: Is the goal blocked on an external dependency (API key, infrastructure, Hyo decision)?
  → YES → the goal is not stale; it is BLOCKED
  → Action: ensure the blocking dependency has a ticket open with Hyo as resolver
  → Action: update goal status to BLOCKED in GROWTH.md

Q2: Is the goal unclear or too broad (no concrete next step)?
  → YES → the goal is not stale; it is UNDEFINED
  → Action: ask the agent: "What is the single most concrete next step toward this goal?"
  → Action: help the agent narrow the goal to a testable increment

Q3: Is the agent in a dead-loop (same assessment 3+ consecutive cycles)?
  → YES → trigger KAI GUIDANCE PROTOCOL (open-ended questions first, yes/no to decide)
  → See dead-loop questions in Section 4

Q4: Is the goal still valid given current system state?
  → Has the system already solved this problem another way?
  → Has the priority shifted such that this goal is now less important?
  → YES → archive the goal in GROWTH.md with reasoning; do not leave it stale
```

### Step 2: Guidance Questions (NOT Answers)

Kai NEVER tells an agent what to do. Kai asks questions that help the agent find the answer.

**When goal is stale with no obvious blocker:**
- "What specific obstacle are you hitting that's preventing progress on [goal]?"
- "What is the smallest thing you could ship toward this goal in the next cycle?"
- "If you had to demo progress on [goal] to Hyo in 1 hour, what would you show?"
- "Is there a dependency in [goal] that makes the whole goal impossible right now?"

**When goal is too broad:**
- "What does 'done' look like for [goal]? How would you verify it?"
- "What is phase 1 of [goal] that could be shipped independently?"
- "Which of these sub-tasks would have the most impact if completed first?"

**When agent seems to have forgotten the goal:**
- "Your GROWTH.md lists [goal] as your [timeframe] target — has the priority changed?"
- "What is currently taking priority over [goal]? Is that the right trade-off?"

### Step 3: Escalation to Hyo

If Kai's guidance questions have not produced progress in 2 cycles:
- Surface to Hyo in morning report / ceo-report
- Include: goal name, agent, days stale, guidance attempts made, current blocker
- Let Hyo decide: revise goal, unblock, or deprioritize

---

## SECTION 4: DEAD-LOOP DETECTION

A dead-loop occurs when an agent's evolution.jsonl shows the same assessment, same bottleneck,
or same description for 3+ consecutive entries — without progress.

### Dead-Loop Detection Algorithm

```python
# From agent's evolution.jsonl, extract last 5 entries
# Compute similarity between consecutive assessments
# If similarity > 80% for 3+ consecutive entries: dead-loop detected

def is_dead_loop(evolution_entries, threshold=0.80, consecutive=3):
    if len(evolution_entries) < consecutive:
        return False
    recent = evolution_entries[-consecutive:]
    similarities = []
    for i in range(len(recent) - 1):
        sim = jaccard_similarity(tokenize(recent[i]), tokenize(recent[i+1]))
        similarities.append(sim)
    return all(s > threshold for s in similarities)
```

### Dead-Loop Questions (Kai Guidance Protocol)

When dead-loop detected, Kai asks ONLY open-ended questions (explore) first:
1. "What would happen if you approached [bottleneck] from a completely different direction?"
2. "What are you NOT seeing about this problem? What assumption might be wrong?"
3. "If [bottleneck] is impossible to fix right now, what can you build around it?"
4. "Who (or what system) would benefit most from [goal] being completed? Can they help?"

Then yes/no questions (decide):
5. "Is [current approach] producing any measurable progress? YES/NO"
6. "Is there a simpler version of [goal] you could complete first? YES/NO"
7. "Does this dead-loop indicate the goal itself is wrong? YES/NO"

---

## SECTION 5: SIMULATION GATE

After pushing an agent on a stale goal, Kai runs a simulation to verify the push worked.

```
SIMULATION GATE (run 24h after push):

Q1: Did the agent update their evolution.jsonl with new content (not a copy of the previous)?
  → NO → push failed; try different guidance questions

Q2: Did the agent open a ticket or begin work on the next increment of the goal?
  → NO → push failed; escalate to Hyo if 2nd failure

Q3: Does the agent's ACTIVE.md now list concrete work toward this goal?
  → NO → push failed; re-check if goal is blocked vs. stale

Q4: Is the agent's approach different from the previous cycle?
  → NO → dead-loop continues; escalate to Hyo

PASS: All YES → push worked; continue monitoring per GOAL STALENESS GATE schedule
FAIL: Any NO → repeat guidance or escalate
```

---

## SECTION 6: TRIGGER, EXECUTE, VERIFY

**Trigger**: `bin/goal-staleness-check.py` runs at 06:00 MT daily (before morning report)
**Execute**: Script scans GROWTH.md + evolution.jsonl for each agent, flags stale goals
**Verify**: morning-report includes goal staleness status per agent

**Implementation needed (ticket created)**:
- `bin/goal-staleness-check.py` (detect + flag)
- Integration with generate-morning-report.sh (display staleness in report)
- GROWTH.md standardized "## Goals" section with machine-parseable format

**Gate for Kai**: "Are any agents showing stale goals in today's staleness check? YES → run push algorithm before any other work. NO → proceed."

---

## SECTION 7: GROWTH.MD GOAL FORMAT (Standardized)

To enable machine parsing, all GROWTH.md files must use this goal format:

```markdown
## Goals (self-set)

| Goal | Timeframe | Target Date | Status | Last Progress |
|------|-----------|-------------|--------|---------------|
| [Short description] | short/medium/long | YYYY-MM-DD | active/blocked/done/archived | YYYY-MM-DD |
```

**Kai adds this standardization gate to daily protocol review**: "Does each agent's GROWTH.md have parseable goals in the standard table format? NO → open task ticket to update."

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
