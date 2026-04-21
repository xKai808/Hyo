# PROTOCOL_PROTOCOL_REVIEW.md
# Version: 1.0
# Author: Kai
# Date: 2026-04-21
# Status: AUTHORITATIVE — Kai runs this daily

---

## PURPOSE

Protocols are only as good as their last review. A protocol with holes is worse than no
protocol — it creates false confidence. Kai reviews all protocols daily to find: missing
question gates, unimplemented references, outdated content, orphaned files, and triggered
but unverified outcomes.

"Kai needs to go through each protocol on a daily basis and ensure that there are no 'holes'
and each agent is actively becoming an expert in its field, self-improving and executing /
implementing changes based on research data and analysis."
— Hyo, 2026-04-21

---

## ALGORITHM-FIRST: THE DAILY PROTOCOL AUDIT GATE

```
DAILY PROTOCOL AUDIT GATE (Kai runs at session start after hydration):

GATE 1: Have all protocols been reviewed in the last 7 days?
  → Check kai/protocols/ directory listing + last modified dates
  → Any protocol not reviewed in 7 days → flag for today's review

GATE 2: Does every protocol have:
  a) An algorithm-first section (questions before rules)?
  b) A trigger (how it runs)?
  c) An execute section (what it does)?
  d) A verify section (how you know it worked)?
  → NO for any item → open task ticket to fix the missing element

GATE 3: Does every agent have:
  a) A GROWTH.md with 3 active weaknesses and self-set goals?
  b) An active improvement ticket (not just PROPOSED)?
  c) An evolution.jsonl entry in the last 48 hours?
  d) Research findings for today (findings-YYYY-MM-DD.md)?
  → NO for any item → open task ticket, push agent

GATE 4: Is every script/tool created this week listed in TRIGGER_MATRIX.md?
  → Check for new .py/.sh files without TRIGGER_MATRIX.md entry
  → NO → open task ticket to add trigger documentation

GATE 5: Does every open protocol reference in a PLAYBOOK point to a file that exists?
  → Grep PLAYBOOKs for "PROTOCOL_" references, verify file exists
  → NO → fix broken reference or create the missing protocol

GATE 6: Are there proposals in kai/proposals/ older than 48h without review?
  → Check directory listing + mtime
  → YES → P1 flag: proposals require Kai review every cycle (constitution rule)

GATE 7: Has Dex run the constitution drift check this cycle?
  → Check agents/dex/ledger/constitution-drift.jsonl for today's entry
  → NO → trigger Dex's drift check
```

---

## SECTION 1: PROTOCOL INVENTORY AND OWNERSHIP

| Protocol File | Owner | Review Frequency | Last Reviewed |
|---|---|---|---|
| EXECUTION_GATE.md | Kai | Weekly | track in review log |
| VERIFICATION_PROTOCOL.md | Kai | Weekly | track in review log |
| RESOLUTION_ALGORITHM.md | Kai | Weekly | track in review log |
| AGENT_RESEARCH_CYCLE.md | Kai | Weekly | track in review log |
| REASONING_FRAMEWORK.md | Kai + All agents | Monthly | track in review log |
| PROTOCOL_MORNING_REPORT.md | Kai | Weekly | track in review log |
| PROTOCOL_TICKET_LIFECYCLE.md | Kai | Weekly | track in review log |
| PROTOCOL_HQ_PUBLISH.md | Kai | Weekly | track in review log |
| PROTOCOL_AETHER_ISOLATION.md | Kai | Monthly | track in review log |
| PROTOCOL_GOAL_STALENESS.md | Kai | Weekly | track in review log |
| PROTOCOL_PROTOCOL_REVIEW.md | Kai | Monthly | track in review log |
| PROTOCOL_PREFLIGHT.md | Kai | Monthly | track in review log |
| TRIGGER_MATRIX.md | Kai + All agents | Weekly | track in review log |

**Review Log**: `kai/ledger/protocol-review-log.jsonl`

Each entry format:
```json
{"date": "YYYY-MM-DD", "protocol": "PROTOCOL_TICKET_LIFECYCLE.md", "reviewer": "Kai", "holes_found": 0, "tickets_opened": 0, "notes": "..."}
```

---

## SECTION 2: THE HOLE-FINDING ALGORITHM

A "hole" in a protocol is defined as any of:

1. **Missing question gate**: A rule or requirement stated without a preceding yes/no question that enforces it
2. **Unimplemented reference**: Protocol mentions a file, script, or command that doesn't exist
3. **Unverifiable step**: A step that has no measurable output (no way to know it ran)
4. **Orphaned trigger**: A script/tool with no automated trigger (dead artifact)
5. **Stale content**: Protocol describes a state of the system that no longer matches reality
6. **Missing downstream updates**: A protocol change that wasn't propagated to AGENT_ALGORITHMS.md or PLAYBOOKs

### Hole-Finding Scan (automated where possible)

```bash
# Find protocols with no trigger documented
grep -L "Trigger\|trigger\|cron\|launchd\|runner\|dispatch" kai/protocols/PROTOCOL_*.md

# Find PLAYBOOK references to missing files
for agent in nel ra sam dex; do
  grep "PROTOCOL_" agents/$agent/PLAYBOOK.md | \
  while read ref; do
    file=$(echo $ref | grep -o 'PROTOCOL_[A-Z_]*.md')
    [ -f "kai/protocols/$file" ] || echo "BROKEN REF: $agent/PLAYBOOK.md → $file"
  done
done

# Find .py/.sh files created in last 7 days not in TRIGGER_MATRIX.md
find agents/ bin/ -name "*.py" -o -name "*.sh" -newer kai/protocols/TRIGGER_MATRIX.md | \
  while read f; do
    grep -q "$f" kai/protocols/TRIGGER_MATRIX.md || echo "UNTRIGGERED: $f"
  done

# Find evolution.jsonl files not updated in 48h
find agents/*/evolution.jsonl -not -newer <(date -d '48 hours ago' '+%Y-%m-%d') 2>/dev/null | \
  while read f; do echo "STALE EVOLUTION: $f"; done
```

---

## SECTION 3: AGENT EXPERT DEVELOPMENT CHECK

Part of the daily audit is verifying each agent is becoming an expert in their field.
An agent that is "doing tasks" without deepening domain knowledge is stagnating.

### Expert Development Indicators (check per agent, daily)

**Nel — Security & QA domain**:
- Is Nel researching new CVE patterns, OWASP updates, dependency security news?
- Is Nel's cipher.sh adaptive (handles new vulnerability classes) or static (same 9 checks)?
- Is Nel able to explain WHY a security check matters (not just what it checks)?

**Ra — Newsletter / Content domain**:
- Is Ra researching editorial best practices, source quality metrics, audience engagement?
- Are Ra's newsletters improving in quality (diversity, specificity, readability)?
- Does Ra know which sources are most reliable vs. noisy in each topic area?

**Sam — Engineering / Infrastructure domain**:
- Is Sam researching Vercel features, Next.js patterns, API design best practices?
- Is Sam's code quality improving (fewer errors, better error handling, simpler APIs)?
- Does Sam have a performance baseline and is it improving?

**Aether — External market intelligence domain** (NOT internal code):
- Is Aether researching macro economics, crypto market structure, Kalshi platform changes?
- Can Aether identify the EXTERNAL conditions under which AetherBot should pause trading?
- Is Aether's external intelligence becoming more specific and actionable?

**Dex — Data integrity / Memory domain**:
- Is Dex researching JSONL schema evolution, audit trail patterns, data integrity algorithms?
- Is Dex's pattern detection becoming more precise (fewer false positives)?
- Does Dex understand WHY data corruption patterns occur, not just that they occur?

### Expert Development Gate

```
For each agent:

Q1: Did the agent's last research findings (findings-YYYY-MM-DD.md) contain specific,
    sourced insights (not general observations)?
  → NO → research theater detected; push for specific sources

Q2: Did the agent's last improvement shipped advance their DOMAIN EXPERTISE, not just
    fix an operational issue?
  → NO → operational work only; push for GROWTH.md improvement work

Q3: Is the agent's domain reasoning section in PLAYBOOK.md growing (more specific questions)?
  → NO → domain knowledge is not accumulating; push agent to deepen expertise

Q4: Can the agent identify 3 things they know about their domain TODAY that they didn't
    know 30 days ago?
  → NO → domain stagnation; treat as dead-loop; run Kai Guidance Protocol
```

---

## SECTION 4: SIMULATION GATE

After daily protocol review, Kai runs a simulation to verify the system works end-to-end.

```
SIMULATION GATE (run dispatch simulate weekly, or after any protocol change):

bash bin/dispatch.sh simulate

Expected outcomes:
  → Nel: QA cycle completes, findings logged, no zombie tickets
  → Ra: research cycle completes, findings have sources, newsletter publishable
  → Sam: deployment path works, API endpoints respond, KV sync functional
  → Aether: analysis can run, quality gate can block, publish path functional
  → Dex: repair/cluster/dedup run, JSONL integrity confirmed
  → Kai: morning report generates, all protocols reachable, no broken references

If simulation fails on any agent:
  → Document failure → open P1 ticket for that agent → don't declare "simulation passed"
  → Simulation PASS requires all agents passing, not most agents
```

---

## SECTION 5: THE PROTOCOL UPDATE ALGORITHM

When a hole is found, this algorithm governs how the protocol is updated.

```
PROTOCOL UPDATE ALGORITHM:

GATE 1: Is this a hole in an existing protocol or is a new protocol needed?
  → Existing protocol: update in place (extend, don't replace)
  → New protocol: only if no existing protocol covers this territory
  → ALWAYS check before creating new

GATE 2: Does the update affect agent behavior?
  → YES → update the relevant agent's PLAYBOOK.md in the same commit
  → YES → update AGENT_ALGORITHMS.md if cross-agent
  → NO → update protocol file only

GATE 3: Is the update adding a gate (question) or a rule?
  → Adding a rule without a gate = incomplete; must add the gate too
  → Gate first, rule second, always

GATE 4: Who must be notified of this change?
  → Cross-agent impact → dispatch notify all affected agents
  → Aether impact → ensure isolation protocol allows the change
  → Kai impact → update KAI_BRIEF.md "Current State" section

GATE 5: Has the updated protocol been verified to work?
  → After updating, simulate the behavior the protocol describes
  → If the behavior cannot be simulated → protocol is not implementable; revise
```

---

## SECTION 6: TRIGGER, EXECUTE, VERIFY

**Trigger**: Daily Bottleneck Audit (Kai runs every session, part of startup protocol)
**Execute**: Run gates in Section 1 → find holes → open tickets for each hole
**Verify**: kai/ledger/protocol-review-log.jsonl has an entry for today with holes_found count

**Minimum daily output**:
- Protocol review log entry for today
- Any holes found → tickets opened (even if holes_found = 0, log it)
- Agent expert development status per agent (in morning report)
- Simulation status (pass/fail with reason)

**Weekly output (Saturday)**:
- Full protocol inventory review (all protocols, not just flagged ones)
- Protocol version bump if content changed this week
- Propagation check: did any constitution change propagate to all PLAYBOOKs?
