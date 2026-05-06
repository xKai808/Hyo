# PROTOCOL_MORNING_REPORT.md
# Version: 3.0 | Owner: Kai | Revised: 2026-05-06
# Reason for revision: Hyo feedback — reports were operational noise, not CEO intelligence.
#
# AUDIENCE: Hyo. CEO. Not a sysadmin.
# GOAL: Answer "is the system improving?" in under 60 seconds.

---

## Core Principle

The morning report is NOT a system log. It is NOT a summary of what ran.
It answers one question: **Are the agents getting better?**

Everything else is Kai's problem to handle silently.

---

## The 5-Section Structure (v3)

### Section 1: PULSE (1 line)
System status: **Healthy / Degraded / Down**

- Healthy = queue active, no P0 tickets requiring Hyo
- Degraded = something needs Hyo's awareness but system is running
- Down = execution layer stalled, agents not running

If Healthy: just say "Healthy." Do NOT pad.
If Degraded/Down: one sentence. What happened, what Kai is doing.

### Section 2: WHAT IMPROVED
*The only backward-looking section. The real story.*

Show only agents where a metric actually moved since last cycle.

Format:
  Agent: [metric before] → [metric after]. What changed: [one sentence — WHY, not what ran].

Example:
  Nel: health score 65 → 71. Rebuilt check architecture to bypass Mini dependency.
  Sam: deploy reliability 87% → 94%. Added pre-deploy test gate.

If no agent improved overnight:
  "No agents shipped an improvement overnight. All cycles are in research phase."

What belongs here: shipped improvements with measurable before/after.
What does NOT belong: research progress, check results, intent, what ran.

### Section 3: WHAT'S BEING BUILT
*Forward-looking. Shows trajectory.*

One line per agent currently building something concrete:
  Agent: [what] — [target metric]

Example:
  Dex: building cross-reference validator — will catch file moves that break references.
  Aether: refining entry timing model — target: signal accuracy 67% → 75%.

If an agent has no active build: omit them. Never pad with "X is maintaining."

### Section 4: AETHER SIGNAL
*Mon–Fri only. One paragraph.*

The actual financial/market signal from Aether's analysis.
What should Hyo be aware of today?
If no analysis available: omit this section entirely.

### Section 5: YOUR ATTENTION
*Zero items on most days. Never fabricated.*

Only appears when Hyo's decision is actually required:
  [What]: description
  [Why Kai can't resolve]: reason
  [Options]: A / B / C

Threshold: P0 tickets requiring Hyo's authorization, spending above threshold,
           strategic direction choices only.

Never surface: failed checks, operational issues, internal system state.
Kai handles all of that. If Kai can handle it: handle it, do not mention it.

---

## What Does NOT Go In The Morning Report

  SICQ / OMP scores         → Kai's internal monitoring
  Failed check details      → Kai resolves these; never mentions to Hyo
  "Nel ran 4 checks"        → Operational noise; nowhere
  Research phase progress   → Research ≠ improvement; agent internal ledger
  Simulation warnings       → Kai's problem; Kai's diagnostic log
  Stale ARIC data warnings  → Kai's problem; Kai's diagnostic log
  "Queue ran X jobs"        → Nobody cares; nowhere
  Agent daily log summaries → Agent's HQ card
  Ra pipeline progress      → Process, not output; nowhere
  Kai daily CEO report      → ELIMINATED (duplicated morning report)

---

## Agent Ground-Truth Metrics (Marina Wyss GVU Pattern)

ONE metric per agent that cannot be gamed. WHAT IMPROVED tracks this.

  Nel    | health_score (target ≥70)   | CVEs caught before production
  Sam    | deploy_reliability (≥95%)   | Test coverage %
  Aether | signal_accuracy             | Position P&L delta
  Ra     | newsletter_delivery_rate    | Subscriber count
  Dex    | org_audit_score             | Stale files count
  Kai    | improvements_shipped_week   | Avg improvement cycle time

If a metric cannot be measured, it cannot be improved.
If it cannot be improved, it does not belong in the morning report.

---

## Agent Reflection Output Schema

Reflection must produce a behavioral change, not a narrative.
Required output written to agents/{name}/data/agent-card.json:

  {
    "agent": "nel",
    "date": "2026-05-06",
    "metric_name": "health_score",
    "metric_before": 65,
    "metric_after": 71,
    "what_changed": "Rebuilt check architecture to bypass Mini dependency",
    "commit": "abc123def",
    "next_target": {
      "metric": "health_score",
      "target": 75,
      "how": "Add supply chain CVE scan"
    }
  }

If metric_before == metric_after: nothing shipped.
Reflection happened internally but produces NO morning report entry.

What IS reflection:
  "My health score dropped because the Mini is unreachable for 3 of 4 checks.
   I changed the runner to use cached state when Mini is unreachable.
   Health score: 65 → 71."

What is NOT reflection:
  "I read 3 articles about CVEs." (research)
  "I ran my checks and 2 failed." (status)
  "I plan to work on my health score." (aspiration)

---

## What Goes On HQ (v3)

  Morning report            | Hyo | generate-morning-report.sh (v7)
  Aether analysis           | Hyo | Aether's daily run (Mon-Fri)
  Agent cards (live)        | Hyo | Each agent's nightly reflection → agent-card.json
  Research drops            | Hyo | Agents when they publish real research findings
  Newsletter                | Hyo | Ra's output (the newsletter itself)
  Decisions inbox           | Hyo | P0 items requiring Hyo's decision only

  Kai daily report          | ELIMINATED | Duplicated morning report
  Agent daily reports       | ELIMINATED | Operational → Kai's inbox only
  Ra content report         | ELIMINATED | Process, not output
  Agent reflections as Research entries | CHANGED | → agent-card.json updates

---

## The Reflection Loop (Correct Design)

Based on: Marina Wyss Chapter 7, Reflexion framework (Shinn et al., 2023)
Principle: Reflection output = behavioral change stored in memory affecting NEXT cycle.

Step-by-step:
  1. Read own GVU metric from last cycle
  2. Compare to target
  3. If delta ≤ 0: identify root cause (WHY, not what failed)
  4. Make ONE specific behavioral change (update PRIORITIES.md, modify runner, add gate)
  5. Write change to agent-card.json → updates HQ card
  6. Write before/after to episodic memory
  7. If metric moved: return structured output → morning report WHAT IMPROVED section

---

## Anti-Patterns

  Reporting failures to Hyo       | Hyo hired Kai to solve, not report | Kai resolves silently
  "Agent is researching"          | Research = phase A, not output      | Report when improvement ships
  SICQ scores in morning report   | Kai's internal metric               | Kai's internal monitoring only
  Padding empty sections          | Makes every morning feel like nothing happened | Empty = absent
  Listing what ran overnight      | Hyo needs what CHANGED, not what ran | Only list changes
  Kai daily report                | Kai IS the orchestrator; morning report IS Kai's report | Eliminated

---

*Version 3.0 — 2026-05-06*
*Principle: if Hyo can't act on it, it doesn't belong in the morning report.*
