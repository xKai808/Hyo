# AGENT WORKFLOW SYSTEMS
Five algorithms with open-ended question checklists
Tailored by role: CEO, QA, Security, Research, Coding, UI/UX, Publishing
Version: 1.0 — April 2026

---

## SYSTEM 1 — THE LOOP ALGORITHM
### Pattern: Create → Verify → Simulate → Close/Reopen
### Best for: Kai (CEO), Aurora (Research), Ra (Publishing)
### Source inspiration: GitHub Agentic Workflows + ControlFlow

This system runs every task through a closed loop.
No task exits the loop until all gates pass.
Ticket stays OPEN until every question below is answered YES.

---

### PHASE 1: TASK CREATION

**Open-ended questions before starting:**

- What is the intended outcome of this task, and how will we know it succeeded?
- Who is affected by the output of this task, and have their needs been considered?
- What assumptions are being made that could invalidate the result?
- What is the minimum viable version of this task that still delivers value?
- What happens if this task is not completed today?

**Ticket fields:**
```
ID:           TASK-[YYYYMMDD]-[agent]-[sequence]
Title:        [action verb] + [object] + [outcome]
Owner:        [agent name]
Created by:   [who assigned it]
Priority:     P1 (blocking) / P2 (today) / P3 (this week)
Status:       OPEN
```

---

### PHASE 2: EXECUTION VERIFICATION

**Open-ended questions before marking work done:**

- Does the output match the stated acceptance criteria exactly?
- What edge cases were considered, and how were they handled?
- What did not work during execution, and why?
- Is there any state, file, or system that was modified unexpectedly?
- What would a skeptical reviewer find wrong with this output?

**Checklist (must be YES to proceed):**
```
[ ] Output exists and is readable
[ ] Output matches the task definition
[ ] No unintended side effects observed
[ ] All dependencies still function
[ ] Logs captured for this execution
```

---

### PHASE 3: SIMULATION

**Open-ended questions before marking simulation passed:**

- If this output is applied in production, what is the first thing that could break?
- What is the worst-case downstream effect of a flaw in this output?
- What would happen if this ran 100 times — would the result be consistent?
- What data or state does this depend on that could change unexpectedly?
- How would this behave under higher load or larger scale?

**Simulation checklist:**
```
[ ] Tested against at least one historical case
[ ] Tested against at least one edge case
[ ] Primary effects documented
[ ] Secondary effects documented
[ ] Tertiary effects documented
[ ] No regressions introduced
```

---

### PHASE 4: COMMUNICATION (TICKET UPDATE)

**Required before closing or escalating:**
```
Summary:      [1-2 sentences: what was done and what the result is]
Evidence:     [file path, log, screenshot, or metric]
Open issues:  [anything unresolved]
Next action:  [what happens next and who owns it]
Ticket status: CLOSED / OPEN (with reason)
```

**Open-ended questions for the ticket update:**
- What should the next agent know before picking up related work?
- What would I do differently if running this task again?
- Is there a pattern here that should be added to standing instructions?

---

### TICKET STATUS RULES:
```
CLOSED  → All phases passed. No open issues. Evidence filed.
OPEN    → Any phase failed. Any question unanswered. Escalation needed.
BLOCKED → Cannot proceed without external input. Notify Kai.
```

---
---

## SYSTEM 2 — THE ROLE GATE ALGORITHM
### Pattern: Each role has a gate. No output passes without its gate agent signing off.
### Best for: Kai → QA → Security → Publishing pipeline
### Source inspiration: Nevo subagent quality pipeline + GitHub AI Workflow Firewall

This system enforces that specific roles own specific gates.
No task can skip a gate. Each gate has its own question set.
Designed for outputs that go public (newsletter, Hyo site, communications).

---

### THE GATES IN ORDER:

```
GATE 1: RESEARCH (Ra/Aurora)     — Is the information accurate?
GATE 2: CODING (Nel/Sam)         — Does it work technically?
GATE 3: QA                       — Does it meet standards?
GATE 4: SECURITY                 — Is it safe to ship?
GATE 5: UI/UX (if applicable)    — Is it usable?
GATE 6: PUBLISHING (Aurora)      — Is it ready to go live?
GATE 7: CEO (Kai)                — Final approval
```

---

### GATE 1: RESEARCH — Open-ended questions

- Where did this information come from, and how recent is it?
- What conflicting information exists, and why was it discarded?
- What is the confidence level in this finding, and what would change it?
- Has this been cross-referenced against at least two independent sources?
- What question does this research leave unanswered?

**Gate verdict:** PASS / FAIL / NEEDS MORE DATA

---

### GATE 2: CODING — Open-ended questions

- Does the code do exactly what the spec says, nothing more, nothing less?
- What happens when this code receives unexpected or malformed input?
- Are there any hardcoded values that should be environment variables?
- What tests were run, and what was their pass rate?
- What would break in the existing codebase if this code shipped today?

**Gate verdict:** PASS / FAIL / REVISION NEEDED

---

### GATE 3: QA — Open-ended questions

- Does this output meet the acceptance criteria defined at task creation?
- What would a user encounter that was not anticipated during development?
- Are there any inconsistencies between this output and prior outputs?
- What is the rollback plan if this output causes a regression?
- Is the output complete, or are there missing pieces not yet flagged?

**Gate verdict:** PASS / FAIL / REVISION NEEDED

---

### GATE 4: SECURITY — Open-ended questions

- Does this output expose any credentials, keys, or personal data?
- What attack surface does this output create or expand?
- Are all external connections in this output explicitly permitted?
- Does this output follow the principle of least privilege?
- What would an adversary do with access to this output?

**Gate verdict:** PASS / FAIL / SECURITY HOLD

---

### GATE 5: UI/UX — Open-ended questions (when applicable)

- Does this interface make the user's intent obvious without instruction?
- Where would a first-time user get confused or stuck?
- Is the visual hierarchy guiding attention to what matters most?
- Does this work on mobile without degradation?
- What would someone with no context think this does?

**Gate verdict:** PASS / FAIL / REDESIGN NEEDED

---

### GATE 6: PUBLISHING — Open-ended questions

- Is the content accurate, complete, and free of errors?
- Does the tone match the platform and audience it is being published to?
- Are there any legal, brand, or compliance concerns in this content?
- Has the SEO or metadata been correctly configured?
- What is the URL, and does it match the content?

**Gate verdict:** PASS / FAIL / HOLD

---

### GATE 7: CEO (Kai) — Open-ended questions

- Does this output align with current strategic priorities?
- Is there anything in this output that could embarrass the company?
- Has the operator been notified if this is consequential?
- Is this the right time to ship this?

**Gate verdict:** APPROVED / HOLD / REJECTED

---
---

## SYSTEM 3 — THE SPRINT ALGORITHM
### Pattern: Batch tasks into sprints. Simulate first. Ship together.
### Best for: Nel/Sam (Coding), QA, multi-task builds
### Source inspiration: Paperclip + CrewAI parallel execution patterns

This system groups related tasks into a sprint.
All tasks are simulated before any are shipped.
Designed for AetherBot builds and Hyo backend work.

---

### SPRINT STRUCTURE:
```
Sprint ID:    SPRINT-[YYYYMMDD]-[focus area]
Owner:        [lead agent]
Tasks:        [list of TASK IDs in this sprint]
Sim target:   [what to simulate against]
Ship window:  [when this is allowed to go to production]
```

---

### SPRINT PHASE 1: PLANNING — Open-ended questions

- What is the one thing that absolutely must work at the end of this sprint?
- What is the most likely reason this sprint fails, and how do we prevent it?
- Which tasks can run in parallel, and which depend on each other?
- What shared state or data do these tasks interact with?
- What is explicitly out of scope for this sprint?

---

### SPRINT PHASE 2: EXECUTION — Open-ended questions

- Is each task self-contained enough that one failure does not block all others?
- What is the current status of each task, and are any blocked?
- Has any task uncovered a dependency that was not in the plan?
- Are we still building what we planned to build, or has scope crept?
- What corners are being cut that will need to be addressed later?

---

### SPRINT PHASE 3: SIMULATION — Open-ended questions

- Against which historical data or baseline is this sprint being tested?
- What is the primary effect of the changes in this sprint?
- What is the secondary effect on systems that interact with the changed code?
- What is the tertiary effect on users or downstream processes?
- If this sprint shipped and created a bug, how would we detect it and how fast?

**Simulation matrix:**
```
Change          Primary effect      Secondary effect    Tertiary effect
[task 1]        [direct impact]     [adjacent impact]   [downstream]
[task 2]        [direct impact]     [adjacent impact]   [downstream]
```

---

### SPRINT PHASE 4: SHIP/NO-SHIP DECISION — Open-ended questions

- Has every task in this sprint passed its individual verification?
- Has simulation passed with no unacceptable secondary or tertiary effects?
- Is the rollback path clear and tested?
- Does the operator need to approve before this ships?
- What will be monitored in the 24 hours after this sprint ships?

**Decision:**
```
SHIP      → all gates passed, no open issues
NO-SHIP   → any gate failed, document exactly why
PARTIAL   → some tasks ship, some rolled back (document which)
```

---
---

## SYSTEM 4 — THE ADVERSARIAL ALGORITHM
### Pattern: One agent builds. A separate agent tries to break it.
### Best for: QA, Security — mandatory for AetherBot builds
### Source inspiration: Nevo quality-arbiter pattern + Qualys Agent Val

This system requires a dedicated adversarial agent.
The builder cannot sign off on their own work.
The adversarial agent's job is to find failure before production does.

---

### THE ADVERSARIAL AGENT ROLE:

```
Name:        QA / Security Agent
Identity:    Skeptic. Assumes the build is broken until proven otherwise.
Mission:     Find every way this could fail before it ships.
Authority:   Can REJECT any output regardless of builder confidence.
Reports to:  Kai directly — not to the builder.
```

---

### ADVERSARIAL PHASE 1: ASSUMPTION ATTACK — Open-ended questions

- What does the builder assume is true that might not be?
- What input was this not tested with that a real user or system might provide?
- What happens if the external dependency this relies on returns unexpected data?
- What is the failure mode that the builder did not anticipate?
- If this breaks at 3am, what does the failure look like?

---

### ADVERSARIAL PHASE 2: SECURITY PROBE — Open-ended questions

- Can this output be used to extract information it should not expose?
- Does this create a path for an unintended actor to take an unintended action?
- Are there any credentials, keys, or tokens visible in this output or its logs?
- Does this trust any input without validation?
- What happens if an attacker crafts a malicious input to this system?

---

### ADVERSARIAL PHASE 3: REGRESSION CHECK — Open-ended questions

- Does this change break anything that was working before?
- Has the behavior of any shared function changed as a side effect?
- Are all existing tests still passing?
- Has anything that depends on this system been notified of the change?
- Is the version number correctly incremented?

---

### ADVERSARIAL VERDICT:
```
APPROVED    → No critical failures found. Document what was tested.
SOFT FAIL   → Issues found but non-blocking. Document and track.
HARD FAIL   → Critical issue found. Build does not ship. Return to builder.
```

**Hard fail requires:**
- Exact description of the failure
- Reproduction steps
- Severity (P1/P2/P3)
- Ticket updated and OPEN
- Builder notified with specific fix required

---
---

## SYSTEM 5 — THE MEMORY LOOP ALGORITHM
### Pattern: Every task feeds back into the agent's memory and standing instructions.
### Best for: All agents — especially Kai, Aether, QA
### Source inspiration: Nat Eliason's Felix nightly consolidation + GitHub Agentic Workflows lessons.md

This system treats every completed task as a learning event.
The agent gets smarter after every sprint.
Tacit knowledge is updated. Checklists are refined. Patterns are captured.

---

### END OF TASK — Open-ended questions (required for every task)

- What did this task reveal that was not in the original plan?
- What decision was made during this task that should become a standing rule?
- What took longer than expected, and why?
- What would have made this task easier if known at the start?
- Is there a pattern here that has appeared in previous tasks?

---

### NIGHTLY CONSOLIDATION (23:50 MTN) — Open-ended questions

- What is the single most important thing that happened today?
- What open issue carries the highest risk going into tomorrow?
- What decision made today should the operator know about?
- What should be added to tacit.md based on today's lessons?
- What standing instruction is now outdated and needs updating?

**Consolidation outputs:**
```
→ Daily note updated (Layer 2)
→ Tacit knowledge updated if new rule identified (Layer 3)
→ Initialization document updated if facts changed (Layer 1)
→ Open tickets reviewed and status confirmed
→ Tomorrow's priority set
```

---

### PATTERN LIBRARY (maintained by Kai)

When a pattern appears 3+ times, it becomes a standing rule.
Standing rules go into tacit.md immediately.

**Pattern template:**
```
Pattern name:    [short description]
First seen:      [date]
Occurrences:     [count]
Trigger:         [what condition activates this pattern]
Response:        [what the agent should do]
Added to:        tacit.md / Kai_Initialization_v2.md
```

---

### TICKET LIFECYCLE (applies to all five systems):

```
OPEN      Created. Work not started or in progress.
ACTIVE    Agent is currently working on this.
BLOCKED   Cannot proceed. Escalated to Kai or operator.
IN REVIEW Completed. Waiting for gate agent verification.
CLOSED    All gates passed. Evidence filed. No open issues.
ARCHIVED  Closed and older than 30 days. Moved to archive.
```

**Ticket remains OPEN if:**
- Any open-ended question is unanswered
- Any simulation gate has not passed
- Any agent has issued a FAIL verdict
- Operator approval is required and not yet given

**Ticket closes automatically when:**
- All phase questions answered
- All gate verdicts are PASS or APPROVED
- Evidence filed
- Communication sent

---

## QUICK REFERENCE — WHICH SYSTEM FOR WHICH AGENT

```
Kai (CEO)           → System 1 (Loop) + System 5 (Memory)
                      All tasks run through Loop. All learnings go to Memory.

QA                  → System 4 (Adversarial) primary
                      Acts as gate agent in System 2.

Security            → System 4 (Adversarial) + Gate 4 in System 2
                      Never approves own builds. Always independent.

Research (Ra/Aurora) → System 1 (Loop) + Gate 1 in System 2
                      Research must be verified before any other gate opens.

Coding (Nel/Sam)    → System 3 (Sprint) primary
                      All builds run through simulation before ship.

UI/UX               → System 2 (Role Gate) Gate 5
                      Reviews after QA, before publishing.

Publishing (Aurora) → System 2 (Role Gate) Gate 6
                      Last gate before operator approval.

Aether (AetherBot)  → System 3 (Sprint) for builds
                      System 5 (Memory) for daily analysis
                      System 4 (Adversarial) — QA reviews all v-number builds
```

---

## THE UNIVERSAL QUESTION SET
### Ask these for any task regardless of system or agent

1. What is the expected outcome, and how will we measure it?
2. What could go wrong, and how would we detect it?
3. What assumptions are we making that could be false?
4. Who needs to know about this, and when?
5. What does success look like 24 hours after this is done?
6. What should never happen as a result of this task?
7. Is there a simpler way to accomplish the same outcome?
8. What would we do differently next time?
