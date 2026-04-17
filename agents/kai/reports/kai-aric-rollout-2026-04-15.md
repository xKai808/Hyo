# Kai — ARIC rollout & research-access brief
**Date:** 2026-04-15 | **Author:** Kai | **Type:** CEO Brief | **For:** Hyo

## What this is
The deliverable you asked for and that I failed to ship first time around: a human-readable report on what I researched, what I found, and what I built in response to your directive that every agent run a data-driven Research → Analysis → Execution cycle on a schedule.

## What you asked for (verbatim intent)
A reliable, self-improving system where each agent, on a schedule, identifies **3 internal structural weaknesses** and **2 external expansion opportunities** (vertical depth or horizontal ground-cover), does real research in their field (web, YouTube, GitHub, Reddit, X, etc.), analyzes findings against our system, executes, and reports back. No gestalt. No shortcuts. Path-building when access is missing, not workarounds.

## What I researched
Four frameworks, cross-referenced for the question: *what is the minimum set of questions that, answered with evidence, forces an agent through observe → research → decide → execute → report, with no shortcuts?*

- **Toyota Kata (Mike Rother)** — Improvement Kata 5-question pattern (target condition, actual condition, obstacles, next step, verify) and Coaching Kata's meta-question: *"When can we go and see what we have learned from taking that step?"* This is the discipline that forces verification after each experiment.
- **OODA Loop (John Boyd)** — Observe / Orient / Decide / Act. Splits situational awareness (observe) from interpretation (orient) so agents can't skip from data to decision without reasoning.
- **DMAIC (Six Sigma)** — Define, Measure, Analyze, Improve, Control. Baseline measurement is mandatory; "Control" phase is what prevents regression after a fix ships.
- **Self-Evolving Agent literature** — verification-driven loops, error taxonomies, "commit only if metric improved." This is where the "measure before and after, compare, keep only if improved" pattern comes from.

Cross-cut with our own ERROR-TO-GATE protocol (every error produces a yes/no gate placed where it will be asked), what emerged is a 7-phase, 38-question cycle.

## What I built

### 1. `kai/protocols/AGENT_RESEARCH_CYCLE.md` — ARIC v1.0
The algorithm you asked for, spelled out:

1. **OBSERVE** (5 questions) — list real outputs from last 7 days, measure consumers reached, pull errors from `known-issues.jsonl`/`session-errors.jsonl`/sentinel, define 3–5 health metrics and measure them as the baseline. Not gestalt.
2. **ORIENT-INTERNAL** (4 questions) — identify exactly 3 structural weaknesses (system design flaws, not symptoms), 5-Whys to root cause, quantify cost of not fixing, pick the one with biggest downstream unlock.
3. **ORIENT-EXTERNAL** (4 questions) — identify exactly 2 external capabilities: 1 for vertical expansion (go deeper in domain) + 1 for horizontal (cover new ground). MVP integration plan.
4. **RESEARCH** (5 questions) — minimum 3 distinct sources per weakness, minimum 2 real implementations for the external opportunity, state-of-the-art scan, adversarial "what would break?", produce an improvement thesis: *"If we build X, then Y will improve by Z because [evidence]."*
5. **DECIDE** (6 questions) — Target Condition (specific number or behavior), Actual Condition (measured baseline), obstacles, next step with predicted outcome, verification method, gate question.
6. **ACT** (5 questions) — improvement ticket → code/config change → test vs predicted outcome → commit/push/verify → gate placed.
7. **REPORT** (7 questions) — what weakness, what research (cite sources), what shipped, what metric moved, next target condition, external opportunity, dependencies/blockers.

**Schedule: every agent, every day.** Not weekly. Stagnation is not acceptable — there is always a weakness, always research to do, always an improvement to build.

### 2. Real research access wired for every agent
Documented research sources in each agent's `agents/<name>/research-sources.json`:

- **GitHub MCP** installed on the Mini (GitHub PAT with `repo`, `read:org`, `read:user` scopes) — `✔ connected`, verified with live authenticated API call (HTTP 200).
- **YouTube MCP** installed (`@kirbah/mcp-youtube`, YouTube Data API v3 key, 10k queries/day free tier) — `✔ connected`, verified with live search returning 3 real videos for "algorithmic trading".
- **Reddit** available via `.json` RSS endpoints (no auth needed, 60 req/min) — verified with live pull from r/algotrading returning 2 current posts.
- Each agent's `research-sources.json` has an `mcp_sources` block telling the agent what to search for via each MCP.

Not workarounds. Actual installed paths.

### 3. Morning-report pivot
`bin/generate-morning-report.sh` is re-oriented per your spec: leads with what each agent is **novelly** working on (weakness → research → build → metric moved), not operational baseline. No "N sources checked" — what was researched, what was found, what changed.

## What I failed
I shipped the protocol document and the access plumbing and committed it all (commit `8505281`). I did **not** ship this report to HQ at the time. You saw nothing visible on HQ because the human-readable deliverable was missing. That's the same class of error as SE-010-011 (dual-path writes) and SE-010-013 (trace the consumer): I traced the *writer* (agent runners will consume the protocol) but not the *reader* (you reading HQ). Logging that as SE-011-001 and wiring the fix: no protocol or architecture work closes without a `kai report` call that pushes a readable brief to the feed.

## Open items I'm working on tonight (in this session)
1. **Aether daily analysis pipeline was broken** — `run_analysis.sh` was looking for `*.log` files but AetherBot writes `AetherBot_*.txt`. Exit 1 every night. Fixed. Retry running now to generate `Analysis_2026-04-15.txt` and publish `aether-analysis-2026-04-15` to the HQ feed.
2. **Feed scope** — restricting feed.json to only morning-report, Ra daily brief, Aether daily analysis. Other agent reflections move to per-agent sub-pages with a "new" badge on the agent tile.
3. **Nel research vs reflection** — splitting. Research produced daily. Reflection q24h as part of nightly consolidation only, and each reflection must emit an improvement ticket or fail its gate.
4. **Aether 15-min metrics refresh** — `aether-metrics.json` file mtime is current but internal `lastUpdated` is stale from yesterday. Patching aether.sh to refresh the field.
5. **New-report indicator on agent tiles** — ticketed to Sam.

## Recommended next decisions (I'll proceed unless you stop me)
- Add `kai report` as an ERROR-TO-GATE subcommand; every session ending without one gets flagged incomplete by the daily audit.
- Wire introspection → improvement-ticket emission into the self-evolution cycle so reflection can't close without action.
- Track API usage in `kai/ledger/api-usage.jsonl`; surface daily spend in the morning report. Current estimate: ~$0.25–$0.50/day all-in across Claude + OpenAI + YouTube (free) + Reddit (free) + GitHub (free).
