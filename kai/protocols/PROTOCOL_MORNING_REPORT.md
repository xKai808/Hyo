# PROTOCOL_MORNING_REPORT.md — Morning Report Protocol
#
# VERSION: v2.1
# Author: Kai | Updated: 2026-04-30 | Authority: Constitutional — mandatory
# Trigger: com.hyo.morning-report launchd plist at 05:00 MT daily
#
# HYO DIRECTIVE (2026-04-30, permanent): The morning report is an intelligence
# brief — what was researched externally, why, what changed as a result, what
# comes next. System health is a footnote. Will not be repeated.

---

## PART 0 — HYO_FEEDBACK META-ALGORITHM (CONSTITUTIONAL)

```
HYO_FEEDBACK_GATE:
GATE 1: Did Hyo suggest a change to a product or output? → YES → GATE 2
GATE 2: Is there a protocol governing that product? → YES → update it in the same session
GATE 3: Does the update include a gate for the issue raised? → YES → done

RULE: Hyo should never have to mention the same issue twice.
```

---

## PART 0b — HYO DIRECTIVE (2026-04-30 — CONSTITUTIONAL, PERMANENT)

Hyo's exact words: "I don't want [to know] if the systems are operating the way they're supposed to. That's basic fundamentals. I want to see what we've researched externally, why and what has been done as a result. I want forward thinking. Will not repeat this again."

### THE CONTENT GATE (non-negotiable, runs before every morning report publish):

```
GATE 1: Does the report lead with external research findings?
  → NO → BLOCKED. Rewrite. System health is NOT the lead.

GATE 2: Does each research item state WHY that topic was investigated?
  → NO → BLOCKED. Research without a why is incomplete.

GATE 3: Does each research item state WHAT CHANGED as a result?
  → NO → BLOCKED. Research without outcome is theater.

GATE 4: Does the report contain a forward-looking section?
  → NO → BLOCKED. Must point to what comes next.

GATE 5: Does system health appear as the PRIMARY content?
  → YES → BLOCKED. System health is a footnote — ≤3 lines, at the end.

All 5 gates must pass before publish. Every day.
```

---

## PART 1 — WHAT THE MORNING REPORT IS

The morning report is Hyo's **intelligence brief**, not a system dashboard.

Hyo already knows the queue is running. What Hyo wants every morning:

1. **What did we learn from the world?** External research, competitive intelligence, specific findings.
2. **Why were those specific things investigated?** Each topic traces to a strategic gap or question.
3. **What changed as a result?** Improvements built, decisions made, strategy adjusted.
4. **Where does this point?** Forward outlook — opportunities, next investigations, implications.

System health appears ONLY as a brief footer — 2-3 lines maximum.

---

## PART 2 — MANDATORY REPORT STRUCTURE (v2.0)

Every morning report MUST follow this order. Deviation = blocked by CONTENT GATE.

### Section 1: INTELLIGENCE — What We Learned
For each piece of external research conducted overnight:
- **Topic**: What was studied (specific — "OpenAI fine-tuning pricing" not "AI research")
- **Why**: What gap or question prompted this (weakness ID, ticket, or strategic question)
- **Finding**: Actual finding with specificity — numbers, names, conclusions
- **Source**: URL or named source (sourceless findings are blocked)
- **Result**: What changed — decision made, code written, queued for [date]

If no research was done: "No external research completed overnight." Do NOT substitute operational notes.

### Section 2: WHAT WE BUILT
For each improvement shipped overnight:
- **What**: Name and one-sentence description
- **Why it matters**: What problem it solves
- **Before → After**: Measurable delta (specific numbers or behaviors, not "improved")
- **Commit**: SHA reference
- **Agent**: Who built it

If nothing shipped: "No improvements shipped overnight." Honest > optimistic.

### Section 3: FORWARD OUTLOOK
- Strategic implications of this week's research trajectory
- Opportunities being tracked (with rationale)
- Next investigations queued — why each matters
- Any hypothesis confirmed or invalidated — what that changes

### Section 4: SYSTEM FOOTNOTE (≤3 lines, not the story)
```
System: [healthy | degraded | P0 active: <one sentence>]
Agents active: N | Queue: [up | down]
```

---

## PART 3 — WRITING STANDARD

Written for a CEO, not a system administrator. Every sentence passes: **"Would a smart non-technical executive find this meaningful?"**

**Banned phrases:**
- "System is healthy" as a lead
- "Agent ran successfully"
- "[DATA FROM YYYY-MM-DD]" embedded in content — stale data belongs in system footnote only
- "No active work this cycle" without explaining why and what's blocked
- Any sentence that could apply to any day without modification

**Required quality:**
- Every finding is specific: numbers, names, dates, URLs
- Every "why" traces to a real strategic question or weakness ID
- Every result is verifiable: commit SHA, ticket ID, or explicit "queued for [date]"

---

## PART 4 — DATA SOURCES

| Section | Data Source | Verification |
|---|---|---|
| Intelligence | agents/<name>/research/aric-latest.json → research_conducted[] | Each finding must have source URL |
| What We Built | agents/<name>/research/aric-latest.json → improvement_built{} | commit SHA must exist in git log |
| Forward Outlook | agents/<name>/research/aric-latest.json → next_target, external_opportunity | Tickets must exist |
| System Footnote | kai/ledger/verified-state.json | File must be <2h old |

If ARIC data is missing: note it in system footnote only. Do NOT populate intelligence from GROWTH.md guesses.

### SYNTHESIS PHASE (mandatory — v2.1)

Raw ARIC findings are technical agent output. They are NOT suitable for Hyo directly.

After collecting intelligence_items, `generate-morning-report.sh` calls `bin/morning-report-synthesize.py` which:
1. Passes all raw items to Claude in a single call
2. Gets back Aurora-style prose: category tag, bold topic, one plain-English takeaway, one Watch signal
3. Writes synthesized output into `intelligence[]` — same schema, new fields: `category`, `topic`, `takeaway`, `watch`

If synthesis fails (Claude bin missing, timeout, API error): fallback to raw items — report still publishes.
If no intelligence_items at all: summary states "No external research completed overnight" — no fabrication.

**Output quality standard**: Each intelligence item must read like The Economist, not a GitHub README.
Example good item:
- CATEGORY: AI-MODELS
- TOPIC: Mistral 128B Pricing
- TAKEAWAY: Mistral's 128B model undercuts GPT-4o by 40% at mid-tier, accelerating pricing pressure on Anthropic incumbents.
- WATCH: Whether enterprise adoption signals move faster than benchmark comparisons.

---

## PART 5 — SCHEMA (feed.json sections for morning-report type)

```json
{
  "summary": "One paragraph research-led executive brief",
  "intelligence": [
    {
      "topic": "Specific external topic studied",
      "why": "Gap or strategic question that drove investigation",
      "finding": "Specific finding with source citation",
      "source": "URL or named source",
      "result": "What changed or what is queued",
      "agent": "which agent"
    }
  ],
  "shipped": [
    {
      "what": "Name of improvement",
      "why": "Problem it solves",
      "before": "State before",
      "after": "State after",
      "commit": "SHA",
      "agent": "who built it"
    }
  ],
  "outlook": "Forward-looking paragraph",
  "systemFootnote": "System: healthy | Agents active: N | Queue: up"
}
```

Required key: `summary`. All others: strongly recommended.

---

## PART 6 — STALE DATA HANDLING

If agent ARIC data is >24h old:
- Do NOT populate intelligence section with stale data
- Do NOT use [DATA FROM DATE] markers in body text — that pattern is banned
- DO include one line in system footnote: "N agents have stale ARIC data (>24h)"
- DO note in outlook if staleness is strategically relevant

---

## PART 7 — VERIFICATION GATE (post-publish)

```
□ Intelligence section leads (system health does NOT appear first)
□ At least one intelligence item has a source URL
□ System footnote is ≤3 lines
□ No [DATA FROM DATE] patterns in body
□ feed.json today field = current system date
□ HQ renders the report in the feed
□ No 404 on any linked content
```

Failure on any check → open P1 ticket immediately.

---

## PART 8 — VERSION HISTORY

| Version | Date | Change |
|---|---|---|
| v1.0 | 2026-04-19 | Initial protocol |
| v1.1 | 2026-04-21 | HYO_FEEDBACK gate, writing standard, BLUF format |
| v2.0 | 2026-04-30 | Full redesign per Hyo directive. Intelligence brief, not system dashboard. CONTENT GATE added. System health relegated to footnote. New sections: intelligence[], shipped[], outlook, systemFootnote. |
| v2.1 | 2026-04-30 | Synthesis phase added. Raw ARIC findings rewritten by Claude into Aurora-style prose (category, topic, takeaway, Watch). bin/morning-report-synthesize.py. HQ renderer updated to display synthesized format. |
