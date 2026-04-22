# PROTOCOL_TICKET_LIFECYCLE.md
# Version: 1.0
# Author: Kai
# Date: 2026-04-21
# Research basis: 42 sources (ITIL, Google SRE, PagerDuty, Jira, Linear, GitHub, KCS, ITSM.tools, Rootly, Atlassian, ServiceNow, Zendesk — full list in kai/research/briefs/2026-04-21.md)
# Status: AUTHORITATIVE — supersedes any informal ticket practices described elsewhere

---

## PURPOSE

Every discrepancy in the Hyo system opens a ticket. Every ticket closes. Every closed ticket
prevents the same error from recurring — not by adding a rule, but by amending an existing
algorithm or creating a new one based on yes/no questions placed where they will be asked.

This protocol defines the lifecycle from detection to verified closure, including the 5-cycle
escalation to Kai, the two-state RESOLVED → CLOSED distinction, and the prevention gate
requirement that ensures every ticket permanently reduces future error probability.

**The ticket lifecycle exists for three reasons, in priority order:**
1. Restore the system to correct behavior (resolution)
2. Prevent the same class of failure from recurring (prevention gate)
3. Build institutional memory so future agents avoid the same mistake (knowledge capture)

---

## ALGORITHM-FIRST PREAMBLE

Rules cannot be the first layer. Questions are the first layer. Rules enforce what questions reveal.

Before any ticket action, the acting agent runs the appropriate GATE (listed under each phase).
A gate is a yes/no question. If the answer is NO, progress stops until the condition is met.
Rules only activate when a gate would be violated. Gates PRECEDE rules. Rules ENFORCE gates.

---

## SECTION 1: TICKET CLASSIFICATION (BEFORE OPENING)

### Pre-Opening Algorithm — Run Before Creating ANY Ticket

```
GATE 1: Does a ticket for this exact issue already exist?
  → Search tickets.jsonl for matching description/component (last 30 days)
  → YES: Link to existing ticket, add note, do NOT create duplicate → STOP here
  → NO: Continue to GATE 2

GATE 2: Has this same failure occurred 3+ times?
  → Check kai/ledger/known-issues.jsonl for pattern matches
  → YES: ticket_type = "problem" (root cause investigation required, not just incident fix)
  → NO: ticket_type = "incident" if unplanned disruption, "task" if planned work,
         "improvement" if agent self-improving per GROWTH.md

GATE 3: Is there already a KEDB entry (known error) for this pattern?
  → Check agents/dex/ledger/known-errors.jsonl
  → YES: Apply documented workaround immediately, link ticket to KEDB entry, set status = BLOCKED
         (blocked on permanent fix), do NOT re-investigate root cause already documented
  → NO: Proceed to ticket creation

GATE 4: Is this fixable within the opening agent's domain?
  → YES: Open ticket, owner = opening agent
  → NO: Open ticket, owner = correct domain agent, notify via dispatch
```

### Ticket Types (Set at Creation — Immutable)

| Type | When | Lifecycle Differences |
|---|---|---|
| `incident` | Unplanned failure affecting output | Max 5 cycles; fast resolution priority |
| `problem` | Root cause of 3+ incidents | Requires KEDB entry before close |
| `task` | Planned work item | Max 10 cycles; no escalation timer |
| `improvement` | Agent growth work (GROWTH.md W1/W2/W3) | Max 10 cycles; no escalation timer |

---

## SECTION 2: TICKET CREATION — REQUIRED FIELDS

Every ticket MUST contain these fields at creation. Missing fields = ticket.sh rejects creation.

```json
{
  "id": "TASK-YYYYMMDD-<agent>-<NNN>",
  "ticket_type": "incident|problem|task|improvement",
  "title": "<verb> <object>: one sentence, specific",
  "description": "<what is wrong, what was expected, what was observed>",
  "affected_component": "<file path, API endpoint, agent name>",
  "created_by": "<agent|kai>",
  "owner": "<agent responsible for resolution>",
  "severity": "P0|P1|P2|P3",
  "status": "OPEN",
  "created_at": "<ISO MT timestamp>",
  "cycle_count": 0,
  "max_cycles": 5,
  "escalation_target": "kai",
  "root_cause_category": null,
  "why_did_this_happen": null,
  "prevention_gate_question": null,
  "prevention_gate_placed": false,
  "kedb_checked": true,
  "duplicate_checked": true,
  "sla_deadline": "<ISO — P0:30min, P1:1h, P2:4h, P3:24h>",
  "five_whys": [],
  "escalation_package": null,
  "resolution_evidence": null,
  "prevention_ticket_id": null,
  "closed_at": null,
  "postmortem_required": false
}
```

### Severity Selection Algorithm

```
GATE: What is the blast radius of this failure?
  → Total outage / data loss / security breach / money at risk → P0
  → Agent cannot complete its primary function → P1
  → Agent degraded but output still produced → P2
  → Minor quality issue, cosmetic, low-impact → P3

GATE: Does this affect Hyo directly or block a scheduled report?
  → YES → minimum P1
  → NO → use blast radius determination above
```

---

## SECTION 3: TICKET LIFECYCLE STATES

```
OPEN → ACTIVE → [BLOCKED] → RESOLVED → CLOSED
                    ↕              ↓
               ESCALATED       ARCHIVED (after 30 days closed)
```

### State Definitions

| State | Meaning | Who sets it |
|---|---|---|
| `OPEN` | Created, not yet worked | ticket.sh create |
| `ACTIVE` | Agent is actively working this cycle | Agent at cycle start |
| `BLOCKED` | Cannot proceed without external action | Agent when blocked |
| `RESOLVED` | Agent believes issue is fixed; evidence recorded | Agent after fix |
| `CLOSED` | Verification complete; prevention gate answered | ticket.sh close (after gate) |
| `ESCALATED` | Cycle limit exceeded; passed to Kai | ticket.sh auto-escalate |
| `ARCHIVED` | Closed >30 days; moved to tickets archive | Dex nightly compaction |

**RESOLVED and CLOSED are NEVER combined.** An agent resolves. The system verifies. Then it closes.

---

## SECTION 4: THE EXECUTION CYCLE

Each time an agent works on a ticket, one CYCLE elapses. The cycle algorithm:

```
CYCLE START GATE:
[ ] Is cycle_count < max_cycles? → NO → escalate immediately (do not begin cycle)
[ ] Has a KEDB entry been checked? → NO → check before proceeding
[ ] Is my approach different from the previous cycle's approach? → NO → do not retry same approach; escalate or change strategy
[ ] Does this action require authority outside my domain? → YES → escalate

CYCLE EXECUTION:
1. Set status = ACTIVE
2. Record what you are attempting (specific, not "investigating")
3. Attempt the fix
4. Record outcome (evidence — not "it worked", but "I ran X and got Y")
5. Increment cycle_count

CYCLE END GATE:
[ ] Did this cycle produce measurable progress toward resolution? → NO → increment skepticism; if 2 consecutive NO → escalate regardless of cycle_count
[ ] Is the issue resolved? → YES → set status = RESOLVED, record resolution_evidence → proceed to SECTION 5
[ ] Is cycle_count < max_cycles? → YES → plan next cycle (different approach) → NO → escalate
```

### SLA Enforcement Gates (run independently, not per cycle)

```
At 50% of SLA elapsed: notification logged to ticket notes
At 75% of SLA elapsed: warning dispatched to agent lead
At 90% of SLA elapsed: auto-escalate priority (P3→P2, P2→P1, P1→P0)
At 100% SLA elapsed: hierarchical escalation to Kai regardless of cycle_count
```

---

## SECTION 5: THE 5-CYCLE ESCALATION

### Escalation Trigger Algorithm

```
GATE: Has cycle_count reached max_cycles (default 5)?
  → YES → run escalation package algorithm → escalate

GATE: Have 2 consecutive cycles produced no measurable progress?
  → YES → escalate regardless of cycle_count

GATE: Is the ticket P0 and unresolved after 1 cycle?
  → YES → escalate immediately to Kai + notify Hyo if >30 minutes

GATE: Is the ticket blocked on an action outside agent's scope?
  → YES → escalate immediately (don't wait for cycle limit)
```

### Escalation Package (REQUIRED — Escalation Without This Is Rejected)

An escalation without full context is useless. The receiving tier (Kai) must get everything.

```json
{
  "escalation_package": {
    "ticket_id": "TASK-...",
    "escalated_at": "<ISO>",
    "escalating_agent": "<agent>",
    "escalation_reason": "<specific: cycle_limit|no_progress|blocked|authority|sla_breach>",
    "cycles_attempted": 5,
    "attempts_summary": [
      {"cycle": 1, "approach": "...", "outcome": "...", "evidence": "..."},
      {"cycle": 2, "approach": "...", "outcome": "...", "evidence": "..."}
    ],
    "current_best_hypothesis": "<one sentence root cause guess>",
    "what_has_been_ruled_out": "...",
    "recommended_next_action": "<specific action Kai should take>",
    "blocking_question": "<the ONE question whose answer would unblock this>",
    "files_modified": [],
    "rollback_instructions": "<how to undo any changes made so far>"
  }
}
```

### Kai's Escalation Response Algorithm

When Kai receives an escalated ticket:

```
GATE 1: Is the escalation package complete (all fields populated)?
  → NO → reject escalation, require complete package from agent

GATE 2: Does Kai's domain knowledge resolve the blocking question?
  → YES → answer it, delegate specific action back to agent with answer
  → NO → escalate to Hyo with escalation package + Kai's additional context

GATE 3: Is this a cross-agent issue requiring coordination?
  → YES → delegate to multiple agents via dispatch, Kai orchestrates
  → NO → assign to single agent with unblocking action

GATE 4: Does this represent a systemic failure (3+ similar tickets)?
  → YES → open a Problem ticket, trigger KEDB investigation
  → NO → resolve as individual incident
```

**SLA Restart on Escalation**: When Kai receives an escalated ticket, the SLA clock restarts with P0=30min, P1=1h acknowledgment required. If Kai does not respond within this window, ticket auto-surfaces to Hyo.

---

## SECTION 6: RESOLUTION (RESOLVED STATE)

### Resolution Gate Algorithm

Before setting status = RESOLVED:

```
GATE 1: Is there measurable evidence that the issue is fixed?
  → "It should work" is NOT evidence
  → Evidence = output of a command, URL fetch result, file contents, log line
  → NO evidence → cannot set RESOLVED

GATE 2: Has the negative case been tested?
  → Would the original failure condition still trigger?
  → NO → simulate the original failure, confirm it is caught or prevented
  → Cannot RESOLVE without negative case test

GATE 3: Is the fix reversible if it causes new problems?
  → NO → document rollback procedure before RESOLVED
  → YES → note rollback method in resolution_evidence

GATE 4: For P0/P1: was the root cause identified?
  → NO → mark root_cause_category as "unknown", flag for Problem ticket
  → YES → populate five_whys and root_cause_category
```

### Five Whys (Required for P0/P1 before RESOLVED)

```
Q1: Why did the failure occur? → <answer>
Q2: Why did that happen? → <answer>
Q3: Why did that happen? → <answer>
Q4: Why did that happen? → <answer>
Q5: Why did that happen? → <root cause>
Root cause category: human | process | system | tooling | external
```

---

## SECTION 7: THE PREVENTION GATE (Required Before CLOSED)

This is the tertiary purpose of tickets: ensuring the same mistake never happens again.
Prevention must be an **addition to an existing algorithm or a new algorithm** — never just a rule.
The addition must be in the form of a yes/no question placed where it will be asked.

### Prevention Gate Algorithm (run BEFORE any ticket transitions to CLOSED)

```
GATE 1: Has the root cause been identified?
  → NO → ticket cannot close; set to BLOCKED on root cause investigation

GATE 2: Has a prevention action been created?
  → The prevention action MUST be one of:
    a) A yes/no question added to an existing gate in EXECUTION_GATE.md
    b) A yes/no question added to agent's PLAYBOOK.md Domain Reasoning section
    c) A yes/no question added to VERIFICATION_PROTOCOL.md
    d) A yes/no question embedded in the agent's runner script as a bash check
    e) A new algorithm created in kai/protocols/ that answers "will this recur?"
  → "Added a rule" is NOT a valid prevention action
  → NO prevention action → ticket cannot close

GATE 3: Has the prevention gate been placed in the correct location?
  → Verify the gate question exists in the target file (grep for it)
  → NO → ticket cannot close

GATE 4: Has the prevention gate been tested?
  → Simulate the original failure → does the gate now fire?
  → NO → ticket cannot close

GATE 5: For P0/P1: Has a postmortem ticket been created?
  → Postmortem ticket = new task ticket with: what_happened, timeline, impact,
    what_went_well, what_went_poorly, 3+ action items with owners and deadlines
  → NO → P0/P1 cannot close without postmortem ticket ID

GATE 6: Has knowledge been captured?
  → Add entry to kai/ledger/known-issues.jsonl with: pattern, prevention, ticket_id
  → For "problem" type tickets: add KEDB entry to agents/dex/ledger/known-errors.jsonl
  → Add lesson to agents/<owner>/evolution.jsonl
  → NO → ticket cannot close
```

### KEDB Entry Format (Problem Tickets Only)

```json
{
  "kedb_id": "KE-<NNN>",
  "created_at": "<ISO>",
  "problem_ticket_id": "TASK-...",
  "description": "<one sentence: what breaks and under what conditions>",
  "root_cause": "<specific technical root cause>",
  "workaround": "<how to restore service quickly while permanent fix is pending>",
  "permanent_fix": "<what resolves this permanently>",
  "permanent_fix_ticket_id": "<if fix is in progress>",
  "detection_method": "<how was this originally detected>",
  "prevention_gate": "<the yes/no question that now prevents this from going undetected>",
  "status": "active_workaround | permanent_fix_in_progress | permanent_fix_deployed | archived"
}
```

---

## SECTION 8: CLOSURE (CLOSED STATE)

### Two-State Distinction

**RESOLVED** = the agent believes the issue is fixed. Evidence recorded.
**CLOSED** = verification complete. Prevention gate answered. Knowledge captured.

These are NEVER combined. An agent resolves their own work. The verification step confirms.

### Closure Gate Algorithm (ticket.sh close must enforce these)

```
GATE 1: Is status = RESOLVED? → NO → cannot close (must resolve first)
GATE 2: Is resolution_evidence populated? → NO → cannot close
GATE 3: Is prevention_gate_placed = true? → NO → cannot close
GATE 4: Is prevention_gate_question populated? → NO → cannot close
GATE 5: For P0/P1: Is postmortem_required = true → is postmortem_ticket_id populated? → NO → cannot close P0/P1
GATE 6: Has known-issues.jsonl been updated? → NO → cannot close
GATE 7: Has evolution.jsonl been updated with the lesson? → NO → cannot close
GATE 8: Auto-close timer: If status has been RESOLVED for >4h with no regression detected → auto-transition to CLOSED

If all gates pass: set status = CLOSED, record closed_at, log closure to evolution.jsonl
```

---

## SECTION 9: OUTSTANDING TICKET MANAGEMENT

Kai runs this algorithm DAILY as part of the Daily Bottleneck Audit.

### Daily Outstanding Ticket Scan

```bash
bash bin/ticket.sh list --status OPEN,ACTIVE,BLOCKED,RESOLVED --format json | python3 -c "
import json, sys, datetime
from datetime import timezone
tickets = json.load(sys.stdin)
now = datetime.datetime.now(timezone.utc)
for t in tickets:
    age_h = (now - datetime.datetime.fromisoformat(t['created_at'])).total_seconds() / 3600
    print(f'{t[\"id\"]} | {t[\"status\"]} | P{t[\"severity\"]} | {age_h:.0f}h | {t[\"title\"][:60]}')
"
```

### Outstanding Ticket Triage Algorithm

```
For each outstanding ticket:

GATE: Age > P0:1h, P1:4h, P2:24h, P3:72h?
  → YES → flag as stale, run escalation algorithm

GATE: Status = BLOCKED for > 2h?
  → YES → surface blocking dependency to Kai immediately

GATE: cycle_count >= max_cycles?
  → YES → auto-escalate to Kai (if not already done)

GATE: Status = RESOLVED for > 4h?
  → YES → auto-close (no regression detected)

GATE: Status = OPEN for > 1h with no ACTIVE transition?
  → YES → dispatch nudge to owner: "Ticket <id> has not been started — begin or escalate"

GATE: Same title/component ticket exists 3+ times in last 30 days?
  → YES → open Problem ticket, link all instances, trigger KEDB investigation
```

### Zombie Ticket Elimination (Dex runs weekly)

```
Tickets open > 90 days with no update:
  → Flag as ZOMBIE (P1)
  → Require Kai review: close/escalate/archive decision within 24h
  → Cannot silently remain open
```

---

## SECTION 10: LAYERED PREVENTION — ALGORITHM, NOT RULE

### The Prevention Hierarchy (from most to least effective)

When a ticket closes, the prevention action MUST use the highest applicable tier:

**Tier 1 — Automated Gate in Runner Script (strongest)**
```bash
# Example: prevent deploying without running tests
if ! npm test 2>/dev/null; then
  echo "[GATE] Tests must pass before deploy. Fix failures first."
  exit 1
fi
```

**Tier 2 — Question in EXECUTION_GATE.md Completion Flowchart**
Add a yes/no question to the flowchart that every agent runs at the end of every task.

**Tier 3 — Question in Agent PLAYBOOK.md Domain Reasoning Section**
```
Domain Reasoning Question: "Did I verify X before doing Y? YES/NO → NO = stop"
```

**Tier 4 — Question in VERIFICATION_PROTOCOL.md by Action Type**
Add a check under the relevant action category (git push, deployment, file update, etc.)

**Tier 5 — New Protocol File in kai/protocols/**
If the prevention requires a reusable multi-step algorithm, create a new protocol file.
Last resort — prefer adding to existing algorithms over creating new files.

### Prevention Gate Template

Every ticket's prevention_gate_question must follow this format:
```
"<Before [specific action]>, have I verified [condition that would have prevented this failure]? YES = proceed. NO = stop and [specific corrective action]."
```

Good: "Before committing to main, have I verified both website/ and agents/sam/website/ are staged? YES = proceed. NO = stage both paths first."

Bad: "Remember to stage both paths." ← This is a rule, not a gate.

---

## SECTION 11: INTEGRATION WITH EXISTING PROTOCOLS

This protocol connects to and does NOT replace:

- **RESOLUTION_ALGORITHM.md (RA-1)**: Steps 3-9 of RA-1 produce the ticket's fix. RA-1 is the work protocol; this is the tracking protocol. Run both in parallel.
- **EXECUTION_GATE.md**: The discrepancy audit gate (5 checks) is the trigger for opening tickets. Every discrepancy found → ticket opened.
- **ERROR-TO-GATE PROTOCOL** (AGENT_ALGORITHMS.md): The prevention gate requirement in Section 10 above IS the ERROR-TO-GATE PROTOCOL applied to the ticket lifecycle.
- **AGENT_RESEARCH_CYCLE.md (ARIC)**: Improvement tickets from ARIC/GROWTH.md use ticket_type = "improvement" and have max_cycles = 10 (more time; not urgent).

---

## SECTION 12: TICKET.SH COMMANDS (Updated)

| Command | Purpose | Required Gates |
|---|---|---|
| `create` | Open new ticket | GATE 1-4 (duplicate check, type, KEDB check, domain) |
| `cycle-start <id>` | Begin a work cycle | Cycle start gate |
| `cycle-end <id>` | End a work cycle | Cycle end gate, increment cycle_count |
| `resolve <id> --evidence <text>` | Mark as RESOLVED | Resolution gate (all 4 gates) |
| `close <id>` | Transition RESOLVED → CLOSED | Closure gate (all 8 gates) |
| `escalate <id>` | Send to Kai with package | Escalation package required |
| `add-prevention <id> --gate "<question>" --location <file>` | Record prevention gate | Verification that gate exists in file |
| `sla-check` | Scan for SLA breaches | Daily, automated |
| `outstanding` | List all non-CLOSED tickets | Kai daily |
| `kedb-add <id>` | Create KEDB entry for problem | Problem tickets only |
| `postmortem <id>` | Create postmortem task | P0/P1 on close |

---

## SECTION 13: TRIGGER, EXECUTE, VERIFY

**Trigger**: ticket.sh sla-check runs every 15 minutes via launchd (com.hyo.queue-worker processes it)
**Execute**: Every discrepancy found in any agent's run → ticket opened via `bash bin/ticket.sh create`
**Verify**: `bash bin/ticket.sh outstanding` produces empty output → all tickets resolved

**Daily Kai gate**: "Are there any open tickets older than their SLA threshold? YES → act. NO → proceed."

---

## APPENDIX: RESEARCH SOURCES

42 sources consulted. Full bibliography: kai/research/briefs/2026-04-21.md
Key frameworks applied: ITIL Problem Management, Google SRE Postmortem Culture, PagerDuty Escalation Policies, KCS Methodology, ITSM Known Error Database, 5 Whys Root Cause Analysis, Atlassian Definition of Done, AI Multi-Agent Orchestration patterns (QAT, Akira AI, MindStudio).

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
