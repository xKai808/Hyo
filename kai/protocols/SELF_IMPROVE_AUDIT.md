# Self-Improvement System Audit
**Author:** Kai  
**Date:** 2026-04-21  
**Scope:** Full structural audit of the agent self-improvement flywheel — failure modes, dependencies, echo chamber risks, quality measurement, and staleness prevention  
**Status:** Living document — update when the system changes

---

## 1. When Will It Miss?

### 1.1 Claude Code Is a Single Point of Failure
Every substantive action in the flywheel depends on Claude Code CLI: research_weakness(), claude_delegate(), identify_next_weakness(). If Claude Code is unavailable (API outage, rate limit, auth expiry, binary not found), the system silently no-ops. The research_weakness() fallback is agent-research.sh — which exists but does not use Claude Code and produces no structured output the implement stage can consume. The implement stage has zero fallback: if claude-code-delegate.sh fails, the system logs "SKIP" and advances to verify as if implementation succeeded. The verify stage then checks whether any commit happened system-wide today — and if any other agent committed anything, verify passes. The weakness is marked resolved without any real work having occurred.

**What this looks like from Hyo's view:** The morning report shows a weakness "resolved" for an agent. The improvement never happened.

### 1.2 The Verify Gate Is System-Wide, Not Weakness-Specific
`commits_today` is computed via `git log --oneline --since=<today>`. This is a global count. If Sam committed a deploy fix at 9am, Nel's weakness "W1: QA coverage gaps" verifies as PASSED at noon — even if Nel did nothing. The deep_ok checks (file freshness) use `-newer self-improve-state.json` which is also too loose: state.json is written at cycle start, so any file touched during the cycle (including log rotation) triggers deep_ok.

**Consequence:** The system can cycle through all weaknesses, marking each "resolved", while doing zero actual work on any of them. This is the highest-severity structural flaw.

### 1.3 Empty Research Advances the State Machine
When Claude Code's research phase returns an empty string (model timeout, context issue, bad prompt), research_output is empty and the research file is never written. research_weakness() returns 0 (success). The state machine advances to "implement". Next cycle: implement calls build_implementation_brief(), which greps the non-existent research file, returns empty string. The system logs "No implementation brief — skipping" and advances state to "verify". Verify passes (commits_today > 0). Knowledge is "persisted" with summary "Fixed via Claude Code delegate" when nothing was fixed.

**Three cycles, no work, weakness marked resolved.** The memory engine is now poisoned with a false resolution.

### 1.4 The Confidence Gate Is Inverted
`build_implementation_brief()` skips implementation only if `$confidence == "LOW"`. If Claude Code returns no CONFIDENCE field (which happens if its output format differs from expected), `$confidence` is empty. `[[ "" == "LOW" ]]` is false — so the system proceeds with unknown confidence. The correct behavior is "only proceed if HIGH or MEDIUM." The current behavior is "block only if explicitly LOW."

### 1.5 Failure Amnesia After MAX_RETRIES
When a weakness hits MAX_RETRIES=3, the state machine advances to the next weakness and resets failure_count to 0. This is correct. But the advanced-to weakness starts fresh with no memory that the previous weakness was not actually fixed — just abandoned. When the system cycles back to the originally-failing weakness (after exhausting all others), failure_count is again 0. The weakness that consistently fails gets tried forever in perpetuity, 3 attempts per cycle, with failure_count always resetting. There is no "permanently stuck" detection and no escalation to Hyo.

### 1.6 GROWTH.md Corruption Stops Everything
If GROWTH.md contains malformed markdown (unclosed block, bad header format), the Python parser in parse_weaknesses() silently returns `[]`. weakness_count == 0. The script logs "No weaknesses in GROWTH.md — nothing to improve" and exits. No ticket, no alert. Every subsequent cycle does the same. The agent's entire self-improvement pipeline is silently dead.

### 1.7 Research Files Are Date-Stamped — Midnight Boundary Bug
research_weakness() checks for a file at `agents/<name>/research/improvements/<WID>-<TODAY>.md`. If a cycle starts at 23:55, creates the research file, then the implement stage runs after midnight, the implement stage looks for `<WID>-<NEW_DATE>.md` — which doesn't exist. build_implementation_brief() returns empty. The cycle skips to verify. This is rare but guaranteed to happen given the nightly schedule.

### 1.8 The "Kai Runs Its Own Cycle" Problem
Kai is both the orchestrator that reads all agent reports and an agent running its own self-improve cycle. When Kai's cycle delegates to claude-code-delegate.sh to fix "session continuity drift" — it is modifying Kai's own protocols (AGENT_ALGORITHMS.md, kai/protocols/) while a Kai session might also be actively running and reading those files. There is no lock between claude-code-delegate.sh and the active Kai session. This creates potential read-while-write corruption on protocol files.

---

## 2. What Is It Too Reliant On?

### 2.1 Claude Code CLI — No Circuit Breaker
Every cycle, every agent, every stage calls Claude Code. There is no health check before calling it, no retry with backoff, no "Claude Code unavailable — defer to tomorrow" mode. Rate limits on the Claude API will cause silent failures across all agents simultaneously. There is no alerting when Claude Code returns empty consistently across N cycles.

**What's needed:** A `check_claude_health()` gate that verifies Claude Code responds before each cycle. If health check fails: log P1 ticket, skip cycle, do not advance state machine, try again next cycle. This is different from the current "try → empty → advance anyway" behavior.

### 2.2 GROWTH.md as Unvalidated Markdown
GROWTH.md is the single source of truth for every agent's self-improvement work. It is written by: (1) the human (Hyo, in the initial bootstrap), (2) Kai in sessions, (3) claude-code-delegate.sh autonomously. There is no schema validation. There is no backup. There is no integrity check. A bad autonomous write can corrupt the entire file and silently kill the pipeline.

**What's needed:** A GROWTH.md validator that runs before parse_weaknesses(): check that at least one `### W\d+:` or `### E\d+:` block exists, check that required fields (Severity, Status, Evidence) are present, create a backup before every autonomous write.

### 2.3 The Memory Engine as Silent Failure Point
query_memory() swallows all errors and returns `[]` if the SQLite database is unavailable, locked, or corrupted. The system proceeds without prior knowledge context. The memory engine is also the long-term learning store — if it silently fails, the system loses the compounding benefit (each cycle should build on prior cycles' knowledge). A failing memory engine makes the system amnesiac, but the cycle still completes "successfully" with no signal that learning is broken.

### 2.4 Single-Agent Identity — No Cross-Domain View
Each agent diagnoses only its own domain. Nel can identify QA coverage gaps in Nel's logs. Nel cannot identify that Sam's deploy pipeline has a structural weakness that causes Nel's QA to generate false positives (which was exactly what happened in session 27). Cross-agent weaknesses — the ones with the highest system-level impact — are invisible to any individual agent and invisible to the flywheel.

---

## 3. Echo Chamber Risks

This is the most important long-term structural concern. The current system has four echo chamber dynamics that compound each other.

### 3.1 Agents Diagnose Their Own Weaknesses
The identify_next_weakness() prompt says: "You are $agent. You just resolved weakness $resolved_id. Identify the NEXT highest-impact weakness." Claude Code reads the agent's own logs, its own GROWTH.md, its own tickets — and produces a new weakness from the perspective of the agent. This is identical to asking a person to identify their own blind spots. People (and models prompted to be people) systematically underestimate what they can't see.

**Structural symptom:** Agents will identify weaknesses in what they already do (QA coverage gaps, log completeness, research citation rate) rather than weaknesses in what they're not doing at all (no adversarial testing, no external benchmarking, no cross-agent collaboration).

### 3.2 Research Is Internal-Only
research_weakness() calls Claude Code with a prompt that includes the weakness title and evidence from local files. Claude Code's only external resource is its training data (knowledge cutoff). There is no web search, no external benchmark fetch, no community standard comparison. A weakness like "research quality is poor" is researched using the same research approach that produced poor research — a closed loop.

**What an external lens would add:** "How do other multi-agent AI systems handle QA? What benchmarks exist for LLM agent reliability? What does the literature say about this class of weakness?" The current system cannot ask these questions.

### 3.3 Success Is Defined by the System Itself
verify_improvement() checks: did git commits happen today? Did files get updated? These are process metrics, not outcome metrics. A change that makes the morning report shorter, faster to generate, or less accurate still passes verification. A change that introduces a subtle regression in Aether's analysis passes verification. The system cannot detect outcome degradation because it has no outcome baseline and no external evaluator.

**The only outcome measurement that matters is Hyo.** Hyo's corrections, Hyo's satisfaction, Hyo's flags. Currently: Hyo feedback → session-errors.jsonl (manual). There is no automatic path from Hyo's feedback to GROWTH.md. The most valuable signal in the system (the CEO's judgment) is not wired into the improvement cycle.

### 3.4 Memory Compounds Same-Direction Learning
The memory engine stores what worked and feeds it back into future research queries. This is good for efficiency but creates directional bias: solutions that worked before get surfaced as priors, making it more likely the next fix resembles past fixes. There is no mechanism to say "we've tried pattern X three times, try something structurally different." The system can develop local optima — running the same class of solution on different manifestations of the same underlying problem.

---

## 4. Quantifying Quality — Daily QA Framework

The system currently has no quality score. Everything is binary (ran / didn't run, resolved / not resolved). The following scoring framework would make quality measurable and comparable across days.

### 4.1 Self-Improve Cycle Quality Score (SICQ — 0 to 100)

Computed per agent per day. Published to HQ as part of the morning report.

| Component | Points | Pass Condition |
|-----------|--------|----------------|
| Research file written | 20 | File exists at `improvements/<WID>-<DATE>.md` |
| Research specificity | 20 | File contains FIX_APPROACH, FILES_TO_CHANGE, CONFIDENCE fields |
| Implementation executed | 20 | `claude-code-delegate.sh` returned RESULT=success (not just "state advanced") |
| Verified file change | 20 | Specific file listed in FILES_TO_CHANGE was actually modified (not just any commit) |
| Knowledge persisted | 20 | KNOWLEDGE.md contains a new entry for this weakness this date |

An agent scoring below 60/100 on SICQ for 3 consecutive days gets a P1 ticket. Below 40/100 for 7 days: Kai flags to Hyo as "self-improve system broken for this agent."

### 4.2 Weakness Aging Index (WAI)

Every weakness has an age: days since it entered GROWTH.md with status "active." Healthy ages: under 14 days for P0, under 30 days for P1, under 60 days for P2. Thresholds:

- WAI > 7 days (P0 weakness not advancing): P0 escalation to Kai signal bus
- WAI > 14 days (no stage change): stale flag in morning report
- WAI > 30 days with zero cycles: permanently stuck detection → Kai reviews and either removes, rewrites, or escalates to Hyo

### 4.3 Flywheel Efficiency Rate (FER)

`FER = weaknesses_resolved / total_cycles_run` over a rolling 30-day window.

A healthy FER is approximately 1 resolved weakness per 3-5 cycles (research → implement → verify). FER below 1/10 indicates the system is spinning. FER above 1/1 indicates auto-resolution without real work (theater). Both are alerts.

### 4.4 Knowledge Compounding Rate (KCR)

Lines added to KNOWLEDGE.md per week that originated from the self-improve pipeline (tagged with the weakness ID). Declining KCR over 2 consecutive weeks: learning is slowing. Zero KCR for any week: pipeline is silently failing.

### 4.5 Research Quality Index (RQI)

`RQI = (research_files_with_all_required_fields / research_files_written) × (files_advancing_to_implement / research_files_written)`

This captures both completeness (did the research meet the format standard?) and conversion (did the research lead to implementation?). A research file that's well-formed but never implemented is theater. A research file that leads to implementation but is missing fields suggests the format is being bypassed.

---

## 5. Preventing Staleness Without Self-Reinforcement

The hardest problem: the system maintaining its own relevance over time. Five mechanisms are needed.

### 5.1 Wire Hyo's Feedback Directly Into GROWTH.md (Highest Priority)

Currently: Hyo gives feedback → session-errors.jsonl (if Kai remembers to write it) → nowhere.
Required: Hyo feedback → auto-inject as W-item into the relevant agent's GROWTH.md.

Implementation: In the session, when Hyo makes a correction, Kai immediately runs:
```bash
HYO_ROOT=... bash bin/ticket.sh create --agent <relevant_agent> \
  --title "Hyo correction: <feedback summary>" \
  --type improvement --priority P1
```
AND appends a new W-item to that agent's GROWTH.md with `**Status:** active — injected from Hyo feedback YYYY-MM-DD`. This is the only truly external signal in the system and must be treated as highest-priority input.

### 5.2 Cross-Agent Adversarial Review (Weekly)

Saturday architecture review (already in Kai's E3 expansion opportunity) should include: Nel reviews Sam's last 7 improvements, Sam reviews Nel's. The reviewing agent reads the other's research files, GROWTH.md, and commits — then writes a one-paragraph assessment: "This improvement was real / this improvement was theater / this is the weakness they should have addressed instead." This is structural adversarial pressure that no individual agent can self-generate.

### 5.3 External Benchmark Injection (Monthly)

Kai runs a monthly external benchmark fetch on the 1st of each month:
- Fetch current state-of-the-art benchmarks for each agent's domain (LLM reliability scores, newsletter open rates for Ra, trading strategy performance curves for Aether, security audit scores for Nel)
- Compare agent's current self-reported performance against external baseline
- Any gap > 20% between self-assessed and external benchmark → new E-item in GROWTH.md labeled "External gap: <domain>"

This forces the system to periodically calibrate against reality outside itself.

### 5.4 Protocol Version Pinning in Research Files

Every research file should record which version of agent-self-improve.sh generated it:
```
PROTOCOL_VERSION: 1.0
GENERATED_BY: agent-self-improve.sh
```
When the protocol is updated (version bump), all research files generated under the old version are marked stale and must be regenerated. This prevents the system from implementing a fix that was designed for an older version of itself.

### 5.5 Decay Detection — Automated Staleness Signals

Add to kai-autonomous.sh (daily 07:30 MT, before morning report):

- If KNOWLEDGE.md last modified > 7 days: P2 alert "learning pipeline stalled"
- If no weakness resolved in any agent for > 14 days: P1 alert "flywheel stopped compounding"  
- If any weakness WAI > threshold (per severity): P1 ticket auto-created
- If SICQ average across all agents < 40 for 3 consecutive days: P0 "self-improve system in failure mode"
- If `self-improve.log` has not grown in 48 hours: P1 "cycle not running" ticket

---

## 6. Expansion Room — What the System Can Become

The current system is good at fixing known weaknesses in what agents already do. It is blind to three categories of growth:

**Category 1: What agents aren't doing at all.** Nel identifies QA gaps in its QA process. Nel never identifies that it has no process for testing cross-agent interfaces. The identify_next_weakness prompt only reads existing logs and tickets — things that already happened. A gap analysis against a target capability map would surface what's missing entirely.

**Category 2: What agents should stop doing.** No agent ever identifies "this thing I do is wasteful, inaccurate, or counterproductive." The flywheel only adds. A quarterly "sunset audit" where Claude Code reads each agent's full runner and flags steps that have never produced a meaningful output would complement the current growth-only model.

**Category 3: Emergent capabilities at agent intersections.** The most valuable improvements are often not improvements to one agent but new collaborations between agents. Nel + Ra could co-produce a weekly system health newsletter. Aether + Kai could co-produce a strategy confidence report that cross-references market signals with system stability. The current flywheel has no representation of inter-agent opportunity space.

---

## 7. Summary Priority Table

| Issue | Severity | Category | Fix Complexity |
|-------|----------|----------|----------------|
| Verify gate is system-wide, not weakness-specific | P0 | Correctness | 2h |
| Empty research advances state machine | P0 | Correctness | 1h |
| Hyo feedback not wired to GROWTH.md | P0 | Echo chamber | 3h |
| Confidence gate inverted (proceed if missing) | P1 | Correctness | 30m |
| No SICQ quality score (can't measure system quality) | P1 | Measurement | 4h |
| Claude Code health check missing | P1 | Reliability | 1h |
| Failure amnesia after MAX_RETRIES | P1 | State machine | 1h |
| GROWTH.md no validation or backup | P1 | Reliability | 2h |
| Cross-agent adversarial review (echo chamber) | P2 | Echo chamber | 6h |
| Memory engine silent failure | P2 | Reliability | 1h |
| Research files internal-only (no external source) | P2 | Echo chamber | ongoing |
| WAI and decay detection | P2 | Measurement | 3h |
| External benchmark injection (monthly) | P3 | Expansion | 8h |
| Protocol version pinning in research files | P3 | Staleness | 1h |
| Cross-agent intersection opportunities | P3 | Expansion | architectural |

---

## 8. What to Build Next

In priority order, the first three fixes close the P0 correctness holes before anything else:

**Fix 1:** Rewrite verify_improvement() to check whether the specific FILES_TO_CHANGE from the research file were modified (not just "any commit today"). Fall back to the current check only when no research file exists.

**Fix 2:** Add an empty-research gate: if research_output is empty OR research file was not written, do NOT advance state to implement. Keep stage at "research", increment failure_count, log P1 ticket. Never advance on nothing.

**Fix 3:** Wire Hyo feedback → GROWTH.md. Add `inject_hyo_feedback_to_growth()` to AGENT_ALGORITHMS.md and execute it whenever Hyo gives a correction in a Cowork session. The correction becomes a P1 W-item in the relevant agent's GROWTH.md within the session it was given.

Once those three are in, add the SICQ daily quality score — that's the instrument that tells whether fixes 1-3 actually worked and whether the system is healthy on any given day.

---

*This audit is versioned. When any item in Section 7 is resolved, mark it resolved here with date and commit. When new failure modes are discovered, add them here before adding to session-errors.jsonl.*
