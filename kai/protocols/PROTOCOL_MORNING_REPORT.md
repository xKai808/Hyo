# PROTOCOL_MORNING_REPORT.md — Morning Report Protocol
#
# VERSION: v1.1
# Author: Kai | Date: 2026-04-21 | Authority: Constitutional — mandatory
# Trigger: com.hyo.morning-report launchd plist at 05:00 MT daily
#
# PURPOSE:
# This protocol specifies EXACTLY how the morning report is generated, what
# it must contain, how HQ renders it, and how to verify it worked.
# Any agent or session starting from zero context reads this file and can
# reproduce the morning report without any prior knowledge.
#
# GPT CRITIQUE (verbatim — incorporated into this design):
#   "Good dashboard. Weak action engine."
#   "Agents research weaknesses but never implement fixes."
#   "improvement_status: 'no active work' across all 5 agents."
#
# DESIGN RESPONSE:
# The morning report MUST distinguish between three states:
#   RESEARCH   — agent understands the problem, has sources, no code changed
#   DECISION   — agent has improvement thesis, ticket opened, work planned
#   EXECUTION  — agent has committed real code/config changes, pushed, verified
#
# A report full of RESEARCH statuses is a warning sign — not a progress report.
# A report full of EXECUTION entries is a healthy system.
# The goal: every agent in EXECUTION on at least one improvement per week.
#
# ============================================================================

---

## PART 0 — HYO_FEEDBACK META-ALGORITHM (v1.1 — CONSTITUTIONAL)

**This gate runs whenever Hyo provides feedback on any product or output.**

Hyo's feedback (2026-04-21): "This [the report] still reads 'stiff'. Ensure the protocol is updated to reflect these changes so it is consistently correct. This should not have to be mentioned moving forward — perhaps in the form of an algorithm? If Hyo suggests changes to a certain product, see if the protocol needs to be changed."

```
HYO_FEEDBACK_GATE — runs after any Hyo feedback on any product:

GATE 1: Did Hyo suggest a change to a product or output?
  → YES → continue to GATE 2
  → NO  → this gate doesn't apply

GATE 2: Is there a protocol governing the product Hyo mentioned?
  → YES → update the protocol IN THE SAME SESSION before declaring work done
  → NO  → create the protocol or add the standard to the nearest governing protocol

GATE 3: Does the protocol update include an explicit standard or gate for the issue raised?
  → YES → done — the fix will now propagate automatically on every future run
  → NO  → the update is insufficient; a principle without a gate gets skipped

RULE: Hyo should never have to mention the same issue twice.
The first feedback is information. The protocol update is the permanent fix.
```

**Scope:** This gate applies to ALL agents, ALL products. It is documented here because the morning report was the first product where Hyo raised it — but it lives in AGENT_ALGORITHMS.md and applies system-wide.

---

## PART 0b — WRITING STANDARD: HOW THE MORNING REPORT READS (v1.1)

**Hyo's feedback (2026-04-21):** "The report needs work as it still reads 'stiff'... needs to be readable for a human that is not an expert in that field."

The morning report is read by Hyo — a CEO, not an engineer. It must be written as a human brief, not a technical log.

### The standard: BLUF + inverted pyramid

**BLUF** (Bottom Line Up Front): Lead with what matters. Bury the technical details.

```
WRONG (technical log style):
  "Nel executed 3 security scans via cipher.sh. PASS: 2. FAIL: 1.
   The failure was in supply chain audit Phase 7. No CVEs detected.
   Improvement ticket IMP-nel-002 remains open."

RIGHT (human brief style):
  "Nel's most urgent gap: she can't detect vulnerabilities at runtime,
   only at audit time. That blind spot is what she's building toward closing.
   One scan failed yesterday — a supply chain check — but no active threats.
   She's not in firefighting mode. She's building."
```

### Rules for every agent section

1. **Lead with what changed** — not what ran. What's different from yesterday?
2. **Explain the "so what"** — don't just state findings. What does it mean for Hyo?
3. **Name the real issue** — not "tracking weakness W2" but what W2 actually is in plain English
4. **Progress in human terms** — not "improvement_status: in_progress" but "she built X, which means Y is no longer a problem"
5. **Max 2 technical terms per agent section** — anything requiring domain knowledge must be explained in the same sentence

### Tone: like a smart colleague briefing a CEO

NOT: "Ra executed Phase 3 of the ARIC cycle and gathered 47 sources across 6 entity categories."
YES: "Ra sourced 47 pieces of research overnight. The most relevant: [specific finding]. Here's why it matters for the newsletter."

NOT: "Aether P&L: +$0.12. Sessions: 3. Win rate: 67%."
YES: "Aether had a quiet day — three small positions, all profitable. The more interesting thing: she passed on two setups that most algorithms would have taken. That discipline is what the win rate actually measures."

### Executive summary standard

The executive summary is the first thing Hyo reads. It must answer in plain language:
- Is the system healthy right now? (one sentence)
- What's the single biggest thing to know? (one sentence)
- What should Hyo be aware of, if anything? (one sentence, or "Nothing urgent")

```
WRONG: "System online: true. Growth trajectory: expanding. Agents shipped: 2/5."

RIGHT: "System is healthy and getting better — two agents shipped real improvements
        overnight, not just research. The thing to watch: Ra's source coverage
        dropped for the third day in a row, which will start showing up in newsletter
        quality by end of week if not addressed."
```

---

## PART 1 — WHAT THE MORNING REPORT IS

The morning report is Hyo's CEO brief. It answers one question:

  "Is the system getting better? If yes, show me the evidence. If no, tell me why."

It is NOT:
- A log of what agents did operationally (that's the operational log)
- A list of what's planned (that's the task queue)
- A summary of checks that passed (that's the health check)

It IS:
- Evidence of actual improvements shipped since last report
- The single highest-priority unresolved issue per agent
- The next concrete action per agent (research, instrument, build, or deploy)
- Why that action is the priority (evidence, not opinion)
- An executive summary showing system improvement trajectory

---

## PART 2 — MANDATORY 5 QUESTIONS PER AGENT

Every agent section in the morning report MUST answer these 5 questions.
If the answer is "N/A" or "none," that is a finding, not an acceptable answer.

```
Q1. What shipped since the last report?
    → Concrete deliverable. With proof.
    → "Committed sentinel-adaptive.sh to 44f9a3b (pushed)" — GOOD
    → "Worked on adaptive sentinel" — BAD (no evidence)
    → If nothing shipped: "Nothing shipped. Last shipment: [date]."
       Do NOT hide this. It is the most important signal.

Q2. What is the single highest-priority unresolved issue?
    → ONE issue. Not a list. The most important one.
    → Must be specific. Not "improve quality" — "5 source failures per day
       undetected because health-check.py doesn't run before gather"
    → Must come from data (ARIC Phase 1 output), not opinion.

Q3. What is the next concrete action?
    → ONE action. Not a plan, not a list. The next step.
    → Must be specific enough to do in the next 6 hours.
    → "Add pre-gather source health validation to newsletter.sh Phase 0" — GOOD
    → "Improve source handling" — BAD

Q4. What type is that action?
    → Exactly one of: research | instrumentation | build | deployment
    → research:         reading, gathering sources, understanding the problem
    → instrumentation:  adding metrics/logging/monitoring to see the problem
    → build:            writing code or config that changes behavior
    → deployment:       shipping the change to production
    → If the action is "research" for more than 3 consecutive reports → red flag.
       Research without execution is theater.

Q5. What evidence justifies that priority?
    → Cite specific data from Phase 1 (ARIC).
    → "source-health.jsonl shows Yahoo Finance returning 0 records for 7
       consecutive days. Known-issues line 3 confirms. Ra newsletter
       coverage score: 62% (target 80%)." — GOOD
    → "It seems important" — BAD
```

---

## PART 3 — REPORT JSON SCHEMA

Path: `agents/sam/website/data/morning-report.json` (canonical)
Mirror: `website/data/morning-report.json` (symlink — same file)

```json
{
  "generated": "2026-04-21T05:00:00-06:00",
  "date": "2026-04-21",
  "version": "v6-action-engine",
  "executive_summary": {
    "system_online": true,
    "execution_layer": {
      "alive": true,
      "stall_hours": 0,
      "queue_depth": 0,
      "last_worker_ts": "2026-04-21T04:55:00",
      "detail": ""
    },
    "simulation_warning": null,
    "growth_trajectory": "expanding|maintaining|declining",
    "trajectory_confidence": "2/5 agents with shipped work",
    "biggest_risk": "one sentence, specific",
    "biggest_win": "one sentence with commit reference",
    "hyo_attention": null,
    "api_spend_today": "$0.45 (3 calls) — claude=$0.45",
    "api_calls_today": 3,
    "synthesis_ran": true,
    "agents_shipped": 0,
    "agents_building": 0,
    "agents_researching": 0,
    "agents_stalled": 0,
    "critical_blocked": []
  },
  "agents": {
    "nel": {
      "novel_work": "...",
      "weakness_identified": "...",
      "research_conducted": "source1; source2",
      "research_findings": "finding1; finding2",
      "research_count": 3,
      "improvement_status": "shipped|in_progress|planned|researched|stalled",
      "improvement_description": "what changed",
      "improvement_commit": "44f9a3b",
      "metric_before": "...",
      "metric_after": "...",
      "metric_moved": true,
      "external_opportunity_type": "vertical|horizontal|none",
      "external_opportunity_desc": "...",
      "has_aric_data": true,
      "aric_cycle_date": "2026-04-21",
      "shipped_since_last": "sentinel-adaptive.sh shipped (44f9a3b). Handles 4-level escalation.",
      "highest_priority_issue": "Dependency audit scanner missing — supply chain blind spot.",
      "next_action": "Build dependency-audit.sh Phase 7 for cipher.sh",
      "action_type": "build",
      "priority_evidence": "cipher.sh has 0 supply chain checks per GROWTH.md W2. 47 npm packages unscanned.",
      "improvement_status_detail": "I1 shipped 2026-04-14. I2 planned, ticket IMP-nel-002. I3 planned."
    }
  }
}
```

### Required fields per agent (enforced by generator script)

```
shipped_since_last        — string — what shipped with proof; "Nothing shipped." if empty
highest_priority_issue    — string — the ONE most important unresolved issue
next_action               — string — ONE concrete next step
action_type               — enum: research | instrumentation | build | deployment
priority_evidence         — string — data citation justifying priority
improvement_status_detail — string — all 3 improvements (I1/I2/I3) with status
improvement_commit        — string | null — git commit hash if shipped
```

### Required executive summary fields (new in v6)

```
agents_shipped       — int — count of agents with improvement_status = "shipped" today
agents_building      — int — count with status "in_progress" (real files changed)
agents_researching   — int — count with status "researched" (no code changed yet)
agents_stalled       — int — count with status "stalled" (no active work 3+ cycles)
critical_blocked     — list — agents blocked with reason (empty = healthy)
```

---

## PART 4 — HQ RENDERING SPECIFICATION

HQ renders agent cards from the morning-report feed entry. Each agent card must show:

```
AGENT NAME (color-coded by agent)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[status badge: SHIPPED | BUILDING | RESEARCHING | STALLED]

▶ Shipped: {shipped_since_last}
▶ Priority: {highest_priority_issue}
▶ Next: {next_action} [{action_type}]
▶ Evidence: {priority_evidence}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Agent color table

| Agent | Color   | Hex      | Badge color if STALLED |
|-------|---------|----------|------------------------|
| nel   | teal    | #2ec4b6  | #ff6b6b (red)          |
| ra    | gold    | #d4a853  | #ff6b6b                |
| sam   | blue    | #4a9eff  | #ff6b6b                |
| aether| purple  | #9b59b6  | #ff6b6b                |
| dex   | green   | #2ecc71  | #ff6b6b                |
| kai   | orange  | #e67e22  | #ff6b6b                |

### Executive summary card

```
SYSTEM HEALTH — {date}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Shipped: {agents_shipped}/5 | Building: {agents_building}/5
Researching: {agents_researching}/5 | Stalled: {agents_stalled}/5

Growth: {growth_trajectory} ({trajectory_confidence})
Win: {biggest_win}
Risk: {biggest_risk}
API: {api_spend_today}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## PART 5 — TRIGGER MECHANISM

### launchd plist: com.hyo.morning-report

Location: `~/Library/LaunchAgents/com.hyo.morning-report.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hyo.morning-report</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/kai/Documents/Projects/Hyo/bin/generate-morning-report.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HYO_ROOT</key>
        <string>/Users/kai/Documents/Projects/Hyo</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>5</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/Users/kai/Documents/Projects/Hyo/agents/nel/logs/morning-report-launchd.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/kai/Documents/Projects/Hyo/agents/nel/logs/morning-report-launchd-err.log</string>
    <key>TimeZone</key>
    <string>America/Denver</string>
</dict>
</plist>
```

**Verify trigger is loaded:**
```bash
launchctl list | grep morning-report
# Expected: non-zero PID or 0 exit code
```

---

## PART 6 — COLD START REPRODUCTION

If a fresh agent with zero memory needs to generate a morning report from scratch:

```bash
# Step 1: Verify data exists per agent
for agent in nel ra sam aether dex; do
    echo -n "$agent: "
    ls /Users/kai/Documents/Projects/Hyo/agents/$agent/research/aric-latest.json 2>/dev/null \
        && echo "ARIC data present" || echo "ARIC data MISSING — use GROWTH.md fallback"
done

# Step 2: Run the generator
HYO_ROOT=/Users/kai/Documents/Projects/Hyo \
    bash /Users/kai/Documents/Projects/Hyo/bin/generate-morning-report.sh

# Step 3: Verify output
python3 -c "
import json
r = json.load(open('/Users/kai/Documents/Projects/Hyo/agents/sam/website/data/morning-report.json'))
print('date:', r.get('date'))
print('version:', r.get('version'))
for name, data in r.get('agents', {}).items():
    missing = [f for f in ['shipped_since_last','highest_priority_issue','next_action','action_type','priority_evidence'] if f not in data]
    print(f'{name}: missing={missing or \"none\"}, action_type={data.get(\"action_type\",\"MISSING\")}')
"
```

---

## PART 7 — VERIFICATION CHECKLIST (4-point check after generation)

Run after EVERY morning report generation:

```
GATE 1: Does morning-report.json have the required new fields?
  python3 -c "
  import json
  r = json.load(open('agents/sam/website/data/morning-report.json'))
  for name, data in r.get('agents', {}).items():
      for f in ['shipped_since_last','next_action','action_type','priority_evidence']:
          assert f in data, f'{name} missing {f}'
  print('PASS: all required fields present')
  "
  → FAIL = do not declare done. Fix generate-morning-report.sh.

GATE 2: Is the mirror in sync?
  diff agents/sam/website/data/morning-report.json website/data/morning-report.json \
      && echo "PASS: mirror in sync" || echo "FAIL: mirror out of sync"
  → FAIL = cp agents/sam/website/data/morning-report.json website/data/morning-report.json

GATE 3: Is the feed entry present for today?
  python3 -c "
  import json
  from datetime import datetime
  today = datetime.now().strftime('%Y-%m-%d')
  feed = json.load(open('agents/sam/website/data/feed.json'))
  mr = [r for r in feed.get('reports', []) if r.get('type') == 'morning-report' and r.get('date') == today]
  print('PASS' if mr else 'FAIL: no morning-report entry for today in feed.json')
  "
  → FAIL = run feed publish step manually

GATE 4: Does the live site show the report?
  curl -s https://hyo.world/api/hq?action=data | python3 -c "
  import json, sys
  d = json.load(sys.stdin)
  print('PASS' if d else 'FAIL: no data returned from live API')
  "
  → FAIL = check Vercel deployment status
```

---

## PART 8 — FAILURE MODES AND GATES

```
FM1: ARIC data missing for all agents
  Gate: "Does any agent have aric-latest.json?"
  → YES (>=1) → generate with available data, note missing agents
  → NO (0)    → generate from GROWTH.md fallback for all agents,
                 flag executive summary: "No ARIC cycles completed — all data is growth-plan only"

FM2: aric-latest.json shows researched but no actual_change field
  Gate: "Does improvement_built have a commit hash?"
  → YES → status = "shipped"
  → NO  → status = "researched" (not "shipped"!) — this is the research theater trap

FM3: All agents show action_type = "research" for 3+ consecutive reports
  Gate: "Has any agent action_type been 'build' or 'deployment' in the last 3 reports?"
  → NO → flag in executive summary: "RESEARCH THEATER DETECTED: no agent in build/deploy
          phase for 3+ consecutive reports. ARIC execution engine may be stalled."

FM4: executive_summary.agents_stalled >= 3
  Gate: "Are 3 or more agents stalled?"
  → YES → hyo_attention = "3+ agents stalled. System is in maintenance mode, not growth mode."
           This goes to hyo-inbox.jsonl as unread message.

FM5: JSON write fails
  Gate: "Did python3 exit 0?"
  → NO  → log to nel/logs/morning-report-error.log, skip commit, flag to dispatch

FM6: git commit fails
  Gate: "Did git commit exit 0?"
  → NO  → leave JSON in place (it was written), flag P1 to dispatch:
           "morning report generated but not committed — manual commit required"

FM7: git push fails
  Gate: "Did git push exit 0?"
  → NO  → flag P0 to dispatch (unreachable origin means Vercel won't update)

FM8: Mirror path doesn't exist
  Gate: "Does agents/sam/website/data/ directory exist?"
  → NO  → skip mirror (website/ symlink is canonical), log warning

FM9: Feed.json missing
  Gate: "Does website/data/feed.json exist?"
  → NO  → create empty feed structure, then add morning report entry

FM10: Synthesis ran but $0 API spend detected
  Gate: "api_calls_today > 0 if aric_claimed > 0?"
  → NO  → simulation_warning field populated (already implemented in v5)
```

---

## PART 9 — HOW TO KNOW "DONE"

The morning report is DONE when:
1. `agents/sam/website/data/morning-report.json` exists with today's date
2. All 5 agent sections have the 5 required fields (shipped_since_last, highest_priority_issue, next_action, action_type, priority_evidence)
3. `executive_summary.agents_shipped`, `agents_building`, `agents_researching`, `agents_stalled` are all populated
4. Feed.json has an entry with type="morning-report" and today's date
5. Mirror at `website/data/morning-report.json` matches
6. Git commit and push succeeded
7. 4-point verification checklist in Part 7 all passed

---

## PART 10 — RESEARCH SOURCES CONSULTED (v1.0)

- [Standup format: shipped/blocked/action — Asana](https://asana.com/resources/stand-up-meeting)
- [SITREP format — Joint Chiefs CJCSM 3150.05F](https://www.jcs.mil/Portals/36/Documents/Library/Manuals/CJCSM%203150.05F.pdf)
- [Self-improving agents — EvoAgentX GitHub](https://github.com/EvoAgentX/EvoAgentX)
- [LLM agent implement own improvements — arxiv AgentForge](https://arxiv.org/html/2604.13120v1)
- [SRE self-healing automation — unite.ai](https://www.unite.ai/agentic-sre-how-self-healing-infrastructure-is-redefining-enterprise-aiops-in-2026/)
- [Toyota Kata improvement cycle — Kanban Tool](https://kanbantool.com/kanban-guide/toyota-kata)

---

## PART 11 — VERSION HISTORY

| Version | Date       | Change |
|---------|------------|--------|
| v1.0    | 2026-04-21 | Initial protocol. Adds 5 mandatory questions, new JSON fields, action_type classification, executive summary agent counts, 10 failure modes, HQ color table, cold start reproduction. Incorporates GPT critique verbatim. |
| v1.1    | 2026-04-21 | HYO_FEEDBACK_GATE (Part 0): constitutional meta-algorithm — Hyo feedback → protocol update in same session, every time. WRITING STANDARD (Part 0b): BLUF + inverted pyramid, plain English, human CEO audience. "NOT this / THIS" examples for every agent section and executive summary. Max 2 technical terms per section rule. |

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
