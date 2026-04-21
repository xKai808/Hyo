# PROTOCOL_AGENT_REPORT.md — v1.0
# Agent Daily Report Writing Standard

**Applies to:** Nel, Ra, Sam, Dex, Aether  
**Updated:** 2026-04-21  
**Audience:** Domain experts reading in Hyo's HQ feed  
**Tone model:** A smart senior analyst briefing a CEO who reads fast and wants no theater

---

## 0. The Non-Negotiable Rule

**Every agent report answers 5 questions — in this order — before anything else:**

| # | Question | Required? | Max length |
|---|----------|-----------|------------|
| 1 | What actually shipped since yesterday? (real code, real output — not "ran the cycle") | Yes | 2 sentences |
| 2 | What is the highest-priority unresolved issue right now? | Yes | 1 sentence |
| 3 | What is the next concrete action? | Yes | 1 sentence |
| 4 | What type of action is that? (research / build / deploy / instrument / escalate) | Yes | 1 word |
| 5 | What's the evidence that priority is correct? (metric, ticket, source, trend) | Yes | 1 sentence |

If a report can't answer all 5 questions, it should not be published. The agent should either wait until it has real output, or explicitly state "nothing shipped — here is why."

---

## 1. Tone and Voice

**Write for a domain expert who reads fast.**

- Security (Nel): write for a CISO who has seen a thousand false positives  
- Newsletter (Ra): write for an editor who has produced at least 50 issues  
- Engineering (Sam): write for a senior engineer who has run production systems  
- Pattern detection (Dex): write for a data analyst who trusts numbers over narratives  
- Trading analysis (Aether): write for a portfolio manager who demands adversarial analysis, not arithmetic

**What this means in practice:**

❌ "Nel ran the daily security cycle and identified potential issues."  
✅ "Nel found 3 packages with known CVEs — lodash (HIGH, CVE-2021-23337), axios (MEDIUM, CVE-2023-45857), and node-fetch (MEDIUM, CVE-2022-0235). Upgrade paths confirmed, no active exploit indicators."

❌ "Ra completed the newsletter pipeline and produced content."  
✅ "Ra pulled 47 sources, published 8 newsletter sections, mean quality score 71/100. Weakest section: 'Macro' at 52/100 — only 2 sources, both >48h old. Needs 3 fresh sources for next run."

❌ "Sam deployed the API updates and monitored performance."  
✅ "Sam deployed 2 endpoints to Vercel (deploy d3f7a). /api/feed: p95 latency 340ms (+12% from baseline). /api/hq-state: 89ms (stable). One endpoint missing try/catch — logged as P2."

❌ "Dex performed pattern detection across system logs."  
✅ "Dex clustered 87 known issues into 12 root causes. Top cluster: nel/false-positive (23 occurrences). Second: sam/deploy-lag (18). Systemic fix for top cluster: add RENDER_BINDING_SKIP whitelist (1 hour of work)."

❌ "Aether conducted market analysis and identified opportunities."  
✅ "Aether analyzed ETH/BTC correlation shift (7-day r² dropped from 0.87 to 0.61). Three active positions showing strategy drift — BTC long entered at $67k now at correlation inflection. GPT adversarial check flagged: 'harvest efficiency declining 3 sessions.' Recommendation: reduce BTC position 20%."

---

## 2. Mandatory Report Structure

Every agent daily report published to HQ feed must include these sections. Order is fixed.

### Section A — BLUF (Bottom Line Up Front)
One paragraph, 3 sentences max. Written last, placed first.

```
[Shipped]: <what actually changed>
[Watching]: <highest-priority open issue + why it matters>
[Next]: <one concrete action + who or what will execute it>
```

### Section B — 5-Question Block
Answer all 5 questions from §0. Use plain prose, not bullet points.

### Section C — Research Findings
**At least 3 named sources with specific findings per claim.** No source = no finding.

Format:
```
[SOURCE: <publication/URL, date>] <specific finding in 1 sentence>
```

If fewer than 3 sources were reachable, state that explicitly and explain the fallback.

### Section D — Improvement Status
One of:
- **SHIPPED**: `<ticket_id> — <what changed> — commit <hash>`
- **IN PROGRESS**: `<ticket_id> — <current phase> — next action: <specific step>`
- **BLOCKED**: `<ticket_id> — <blocker> — escalated to Kai as P<N>`
- **IDLE**: `No open improvement tickets` (only acceptable if ticket ledger is genuinely empty)

### Section E — Metrics
Domain-specific numbers that show whether the agent is getting better or worse.

| Agent | Required metrics |
|-------|-----------------|
| Nel | health_score, checks_passed, checks_failed, CVEs_found, false_positive_rate |
| Ra | sources_pulled, sources_failed, quality_score (mean + min section), email_sent |
| Sam | deploys_completed, p95_latency_ms, error_rate, endpoints_without_tryCatch |
| Dex | issues_clustered, new_patterns_found, JSONL_corrupt_count, drift_flags |
| Aether | positions_analyzed, phantom_warnings, strategy_drift_flags, GPT_adversarial_flags |

### Section F — Weaknesses (Self-Assessment)
Three weaknesses, updated weekly or when new evidence appears. Not static.

Format:
```
W1: <weakness> — Evidence: <metric or observation> — Improvement: <ticket_id or "untracked">
W2: <weakness> — Evidence: <metric or observation> — Improvement: <ticket_id or "untracked">
W3: <weakness> — Evidence: <metric or observation> — Improvement: <ticket_id or "untracked">
```

---

## 3. What Counts as "Shipped"

**Shipped** means all four of the following are true:
1. A file was created or modified with real content (not a placeholder)
2. A git commit exists with the change
3. The change is pushed to origin/main
4. The change does something observable (produces output, changes behavior, fixes a metric)

**Not shipped:**
- "Ran the cycle" — that's operations
- "Identified the issue" — that's research
- "Wrote a plan" — that's a ticket
- "Updated GROWTH.md" — that's bookkeeping

If nothing shipped, say: "Nothing shipped today. [Reason]. Next action: [specific next step]."

---

## 4. Research Standards

Every research finding must meet all of the following:
- Named source with URL or publication name + date
- Specific finding (not "there are concerns about X")
- Relevance stated (why does this matter for this agent's domain?)

**Minimum:** 3 sources per finding. If sources were unavailable, state why and use cached data with age disclosed.

**Gestalt is not research.** "Based on general knowledge..." = 0 sources = not a valid finding.

---

## 5. Format Constraints

- No more than 600 words for the full report (excluding Section E metrics table)
- No bullet points at the top level (use prose for BLUF and 5-question block)
- Technical terms are fine — write for domain experts, not generalists
- Numbers are mandatory — a report without at least 4 specific numbers is not domain-expert-level
- Every improvement ticket reference must include the ticket ID (IMP-YYYYMMDD-agent-NNN)

---

## 6. Anti-Patterns (Immediate Rejection Criteria)

A report that hits any of the following must be regenerated before publish:

| Anti-pattern | Example |
|---|---|
| **Vague shipped claim** | "Completed daily cycle" |
| **Findings without sources** | "There is increasing DeFi risk" |
| **Missing improvement status** | No mention of open IMP tickets |
| **Theater numbers** | "Processed 1,247 data points" with no context |
| **Stale weakness list** | Same W1/W2/W3 as last week with no new evidence |
| **Missing BLUF** | Report starts with "Today Nel ran..." |
| **No concrete next action** | "Will continue monitoring" |

---

## 7. Enforcement

**Dex** runs a daily PROTOCOL_AGENT_REPORT compliance check:
- Scans last 24h of published HQ entries for all agents
- Checks for presence of all 6 sections, minimum source count, shipped claim validity
- Flags violations as P2 tickets (P1 if same agent fails 3+ consecutive reports)

**Morning report** references each agent's improvement_status from aric-latest.json:
- If `status: shipped` → "Nel shipped [description]"
- If `status: in_progress` → "Nel is building [description] — no code yet"
- If `status: researched` → "Nel has the research, execution pending"
- If `cycle_date` > 2 days old → "Nel ARIC stale — last cycle [date]"

**Kai weekly review** reads all 5 agent reports and gives written feedback per agent. Feedback is saved to `kai/memory/feedback/` and referenced in the following week's Kai daily report.
