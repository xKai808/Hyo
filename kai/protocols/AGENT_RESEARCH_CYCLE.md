# Agent Research & Improvement Cycle (ARIC) v1.0

**Author:** Kai | **Date:** 2026-04-15 | **Authority:** Constitutional — ALL agents, mandatory
**Trigger:** Scheduled (weekly per agent) + on-demand when weakness surfaces
**Origin:** Hyo directive (session 10 cont 3): "They need to conduct research for the answer/solution for improvements. and is that it? no! they need to execute."

**Research foundation:** Toyota Kata (Improvement Kata + Coaching Kata 5 questions), OODA Loop (Observe-Orient-Decide-Act), DMAIC (Define-Measure-Analyze-Improve-Control), Self-Evolving Agent architectures (verification-driven loops, error taxonomies, commit-only-if-improved), Hyo ERROR-TO-GATE protocol.

---

## Why This Exists

Agents were reporting "did research" and "made improvements" with no data, no specifics, no evidence. That is theater. This protocol ensures every agent:
1. Identifies real weaknesses using data, not gestalt
2. Conducts real research using external sources, not assumptions
3. Analyzes findings against our specific system, not generic best practices
4. Executes improvements with measurable outcomes
5. Reports what changed, not what was planned

---

## The Algorithm: 7 Phases, 38 Questions

Every agent runs this cycle. Every question must be answered with evidence, not opinion. Skipping a question is not allowed — if the answer is "I don't know," that IS the answer, and it becomes the first research task.

### PHASE 1: OBSERVE (What is the actual state?)

The agent examines its own domain with fresh eyes. Not from memory — from data.

```
1.1  "What are my domain's outputs from the last 7 days?"
     → List every artifact produced (reports, fixes, analyses, alerts).
     → Count them. Categorize them. Are they growing or shrinking?

1.2  "Which outputs actually reached a consumer (Hyo, HQ, another agent)?"
     → Trace each output to its consumer. If it didn't reach anyone, it's waste.

1.3  "What failed, errored, or was flagged in my domain in the last 7 days?"
     → Pull from: known-issues.jsonl, session-errors.jsonl, sentinel reports,
        healthcheck flags, ticket history. Real data. Not "I think things are fine."

1.4  "What is my domain's current health score?"
     → Define 3-5 measurable metrics specific to this agent's domain.
     → Measure them NOW. This is the baseline.
     → Examples:
        - Nel: % of checks passing, mean time to detect, false positive rate
        - Ra: source success rate, content diversity score, newsletter delivery rate
        - Sam: API response time, error rate, deployment success rate
        - Aether: real vs phantom P&L accuracy, analysis coverage %, strategy eval freshness
        - Dex: JSONL integrity %, stale file count, auto-repair success rate
```

### PHASE 2: ORIENT — INTERNAL (What are our structural weaknesses?)

Identify exactly 3 internal structural weaknesses. Not symptoms — structures.

```
2.1  "Looking at the data from Phase 1, what are the 3 biggest structural
      weaknesses in my domain?"
     → A structural weakness is a system design flaw, not a one-time bug.
     → "API key missing" is a symptom. "No secret rotation pipeline" is structural.
     → Each weakness must cite specific evidence from Phase 1 data.

2.2  "For each weakness: what is the ROOT CAUSE, not the symptom?"
     → Apply 5-Whys. Keep asking why until you hit a design decision or
        missing capability. That's the structural weakness.

2.3  "For each weakness: what is the COST of not fixing it?"
     → Quantify in: time wasted, data lost, errors caused, growth blocked.
     → If you can't quantify it, it might not be a real weakness.

2.4  "Which weakness, if fixed, would unlock the most improvement downstream?"
     → This is priority #1. The others are #2 and #3.
```

### PHASE 3: ORIENT — EXTERNAL (What can we build on top of?)

Identify exactly 2 external opportunities — capabilities that expand what the system can do vertically (deeper in our domain) or horizontally (into adjacent domains).

```
3.1  "What capabilities exist in the wider ecosystem that my domain
      doesn't use yet?"
     → Search: GitHub repos, MCP servers, APIs, tools, frameworks, libraries.
     → Not "what's cool" — what would solve a real problem from Phase 2
        or enable a capability we don't have.

3.2  "Which ONE external capability would let us go deeper in our domain?"
     → This is vertical expansion. Example:
        - Nel: CVE database API → supply chain vulnerability scanning
        - Ra: Readership analytics API → editorial feedback loop
        - Sam: Lighthouse CI → automated performance regression detection
        - Aether: Kalshi position confirmation API → phantom position resolution
        - Dex: Schema validation library → JSONL schema evolution

3.3  "Which ONE external capability would let us cover more ground?"
     → This is horizontal expansion. Example:
        - Nel: Container scanning → expand beyond file-level security
        - Ra: Podcast RSS → expand beyond text newsletter
        - Sam: Mobile performance testing → expand beyond desktop
        - Aether: Multi-exchange support → expand beyond Kalshi
        - Dex: Cross-project memory → expand beyond single repo

3.4  "What would it take to integrate each? What's the MVP?"
     → Not a dream list. A concrete integration plan with steps.
```

### PHASE 4: RESEARCH (What do experts know that we don't?)

This is where agents actually learn. No shortcuts. Real sources.

```
4.1  "For my #1 internal weakness: what do practitioners in my field
      recommend as the solution?"
     → Search: GitHub issues, Stack Overflow, Reddit threads, blog posts,
        academic papers, conference talks, tool documentation.
     → Minimum 3 distinct sources. Cite them.

4.2  "For my #1 external opportunity: what existing implementations exist?"
     → Find at least 2 real implementations (open source repos, production
        systems, case studies). Study how they work.

4.3  "What is the state of the art in my domain right now?"
     → Search for: "[domain] best practices 2026", "[domain] tools comparison",
        "[domain] architecture patterns".
     → What are other systems doing that we aren't?

4.4  "What would break if I implemented the top solution from 4.1?"
     → Adversarial thinking. What are the risks? What dependencies?
     → What would the OODA loop's Orient phase surface about our context
        that makes this solution not directly applicable?

4.5  "Based on all research: what is my IMPROVEMENT THESIS?"
     → One sentence: "If we build [X], then [Y metric] will improve by [Z]
        because [evidence from research]."
     → This is not a guess. It's a hypothesis backed by data.

RESEARCH SOURCES (ordered by priority):
  1. GitHub (repos, issues, discussions) — via github MCP or gh CLI
  2. WebSearch — broad web search
  3. Reddit (r/devops, r/sysadmin, r/programming, r/machinelearning) — via reddit MCP
  4. YouTube (conference talks, tutorials) — via youtube MCP
  5. X/Twitter (practitioner discourse) — via x MCP
  6. Anthropic docs, Vercel docs — via existing tools
  7. Academic papers (arxiv, Google Scholar) — via web search

  If a source is unavailable: log it as a BLOCKER, not a workaround.
  The goal is to BUILD ACCESS, not accept limitation.

EXTERNAL SOURCE GATE (mandatory — runs before writing research_conducted[]):
  Before writing any item to research_conducted[], answer:
  □ Does this source have an http:// or https:// URL?
  □ Is this source something outside the Hyo codebase (not GROWTH.md,
    session-errors.jsonl, ACTIVE.md, PLAYBOOK.md, aether.sh, or any local file)?
  □ Does the finding cite something we learned from the external world —
    not something we already knew from our own logs?

  If any answer is NO: do not write that item to research_conducted[].
  Write it to research_analysis{} instead as internal context.
  research_conducted[] is for external intelligence ONLY.
  Internal self-assessment goes in research_analysis{}.

  RATIONALE: The morning report distills research_conducted[] for Hyo.
  Internal bookkeeping dressed as research produces a CEO brief that reads
  like a dev log. Hyo has already said this is unacceptable. Don't repeat it.
```

### PHASE 5: DECIDE (What exactly will we build?)

```
5.1  "What is my Target Condition?"
     → Improvement Kata Q1: Define the specific measurable state we want
        to reach. Not "make it better." A number. A capability. A behavior.

5.2  "What is the Actual Condition now?"
     → Improvement Kata Q2: The measured baseline from Phase 1.4.
     → The gap between 5.1 and 5.2 is the improvement.

5.3  "What Obstacles prevent reaching the Target Condition?
      Which ONE am I addressing first?"
     → Improvement Kata Q3: List all obstacles. Pick ONE.
     → This becomes the improvement ticket.

5.4  "What is my Next Step? What do I expect will happen?"
     → Improvement Kata Q4: One concrete experiment/build.
     → State the expected outcome BEFORE executing.
     → This is scientific method: hypothesis → experiment → verify.

5.5  "How will I VERIFY that the improvement worked?"
     → Define the measurement. Define the threshold.
     → "I'll know it worked when [metric] goes from [baseline] to [target]."

5.6  "What is the gate question for this improvement?"
     → ERROR-TO-GATE: What yes/no question prevents regression?
     → Place it in the PLAYBOOK or runner.
```

### PHASE 6: ACT (Build it. Ship it.)

```
6.1  "Did I create an improvement ticket with:
      type=improvement, weakness link, approach, success metric?"
     → If NO → create it now. Do not proceed without a ticket.

6.2  "Did I implement the change?"
     → Code written, config changed, pipeline modified — whatever the fix is.
     → Not a plan. Not a proposal. The actual change.

6.3  "Did I test the change against the expected outcome from 5.4?"
     → Run it. Measure it. Does the metric move?
     → If NO → diagnose why. Iterate. Do not declare done.

6.4  "Did I commit, push, and verify?"
     → Completion Gate: committed → pushed → verified → memory updated.
     → Every NO loops back.

6.5  "Did I place the gate question from 5.6 in the right location?"
     → ERROR-TO-GATE: gate exists, is placed, is blocking.
```

### PHASE 7.5: ADVERSARIAL CHALLENGE (Before execution — independent verifier gate)

This phase runs BEFORE Phase 6 execution and BEFORE Phase 7 reporting.
The verifier is architecturally separate from the generator (GVU Variance Inequality, arXiv:2512.02731).
A generator that self-verifies produces noise > signal. This phase forces external challenge.

**Implementation:** `bin/aric-verifier.py` — exits 0 (APPROVED), 1 (REQUIRES_REVISION), 2 (ERROR)
**Threshold:** Score ≥ 70/100 required to proceed. Below threshold → execution blocked, ticket remains OPEN for revision.
**Dead-Loop Guard:** `bin/dead-loop-detector.py` runs simultaneously — records cycle fingerprint, warns/stops if identical fingerprints ≥ 3/6 in ring buffer.

```
7.5-Q1  "Is there evidence this improvement actually ran? (files_changed not empty)"
        → No files_changed → BLOCKS execution (score: 5/20). Talking about doing is not doing.

7.5-Q2  "Does the research cite 3+ concrete external sources?"
        → < 3 sources → BLOCKS execution (score: 6/20). No source, no finding.

7.5-Q3  "Is there a specific weakness being addressed, with a metric before?"
        → No weakness or no metric_before → BLOCKS (score: 4/20). Measure before you fix.

7.5-Q4  "Does the improvement plan describe concrete file changes, not vague intent?"
        → Vague plan → BLOCKS (score: 5/20). "Add better error handling" ≠ "Edit api/ingest.js line 42."

7.5-Q5  "Is the cycle_date fresh? (< 3 days)"
        → Stale cycle date (> 3 days) → caps all scores at 10/20. Stale data = stale plan.

GATE: Total score ≥ 70 → APPROVED (Phase 6 proceeds)
      Total score < 70 → REQUIRES_REVISION (Phase 6 blocked, ticket stays OPEN)

SOURCES:
  - arXiv:2512.02731 (GVU Operator — Generator/Verifier separation)
  - arXiv:2212.08073 (Constitutional AI — external critique-revision loop)
  - arXiv:2410.04663 (D3 Debate-Deliberate-Decide — adversarial multi-agent evaluation)
  - arXiv:2512.20845 (MAR — prevents cognitive entrenchment via genuinely separate evaluators)
  - TokenFence.dev circuit breaker pattern (dead-loop fingerprint ring buffer)
```

### PHASE 7: REPORT (What changed? What's next?)

This is what appears in the morning report. Not Phase 1 data. Not "conducted research." The OUTCOME.

```
7.1  "What weakness did I work on? (one sentence, with evidence)"

7.2  "What did I research? (specific sources, specific findings)"

7.3  "What did I build as a result? (specific change, with file/commit reference)"

7.4  "What metric moved? (baseline → current, with measurement method)"

7.5  "What is my next Target Condition? (Improvement Kata — the cycle continues)"

7.6  "What external opportunity am I pursuing? (vertical or horizontal)"

7.7  "What do I need from Kai or other agents? (dependencies, blockers, suggestions)"
```

---

## Schedule

```
DAILY CYCLE (every agent, every day, no exceptions):
  Every agent runs the full ARIC cycle (Phases 1-7) every day.
  Not Phase 1 only. Not "observe and defer." The full cycle.
  If an agent has nothing new to research → that's a Phase 2 failure.
  There is always a weakness to investigate, always research to do,
  always an improvement to build. Stagnation is not acceptable.

  Agents don't all need to work on the SAME weakness every day.
  The cycle is: observe → pick the most important thing → research it
  → decide → build → report. Tomorrow, observe again — did it work?
  Pick the next thing. This is continuous improvement, not a weekly event.

REPORTING:
  Phase 7 output feeds directly into the morning report.
  Morning report shows: what was researched, what was built, what moved.
  NOT: "agent ran health checks" or "agent checked N sources."
```

---

## Morning Report Structure (v4 — Growth-Driven)

The morning report Hyo reads must answer these questions:

```
FOR EACH AGENT:
  1. "What novel work is [agent] doing right now?"
     → Not scheduled work. Not operational baseline. What NEW thing.
     → If nothing → flag it. "No novel work" IS the report, and it means
        something is wrong.

  2. "What weakness did they identify and what did they research?"
     → Specific weakness, specific research sources, specific findings.
     → Not "identified 3 weaknesses." WHAT weaknesses. WHAT findings.

  3. "What improvement did they build or are they building?"
     → Specific code change, config change, new capability.
     → Current status: shipped / in progress / blocked (with reason).

  4. "What metric moved as a result?"
     → Before → After. If not measured yet, when will it be.

  5. "What external expansion are they pursuing?"
     → Vertical or horizontal. Specific tool/API/capability.

EXECUTIVE SUMMARY (Kai → Hyo):
  - System growth trajectory: are we expanding or maintaining?
  - Biggest risk right now (one sentence)
  - Biggest win this cycle (one sentence)
  - What Kai is working on that agents can't do themselves
  - Blockers that need Hyo's attention (if any — only if truly needed)
```

---

## Research Access (as of 2026-04-15)

```
INSTALLED AND CONNECTED (on Mini — Claude Code MCP):
  ✅ GitHub MCP (@modelcontextprotocol/server-github)
     → Capabilities: search repos, read issues, search code, read PRs, security advisories
     → Auth: GitHub PAT with repo, read:org, read:user scopes

  ✅ YouTube MCP (@kirbah/mcp-youtube)
     → Capabilities: search videos, get transcripts, channel search
     → Auth: YouTube Data API v3 key (10k queries/day free)

AVAILABLE WITHOUT AUTH (RSS/JSON feeds in research-sources.json):
  ✅ Reddit (via .json feeds — no API key needed)
     → r/netsec, r/cybersecurity, r/algotrading, r/CryptoCurrency,
       r/dataengineering, r/LocalLLaMA, r/webdev, r/node,
       r/Newsletters, r/emailmarketing, r/artificial
     → Rate limit: 60 req/min unauthenticated (plenty for daily ARIC)

AVAILABLE FROM COWORK SANDBOX:
  ✅ WebSearch / WebFetch (limited by egress rules)

NOT YET INSTALLED:
  - Exa MCP (connect from registry — zero install, adds semantic web search)
  - X/Twitter MCP ($100/mo — deferred, low ROI)

AGENT MCP USAGE:
  Each agent's research-sources.json has a "mcp_sources" section
  documenting which MCP tools to use and what to search for.
  Phase 4 research should use MCP tools for deep dives beyond RSS surface hits.
```

---

## Integration Points

This protocol is wired into:

1. **AGENT_ALGORITHMS.md** — Constitutional reference to ARIC
2. **Each agent's PLAYBOOK.md** — Agent-specific Phase 2/3 questions
3. **bin/agent-growth.sh** — `run_growth_phase` calls Phase 1 (OBSERVE) daily
4. **Agent runners** — Daily ARIC trigger (all agents, every day)
5. **generate-morning-report.sh** — Reads Phase 7 output for report
6. **CLAUDE.md** — Operating rule: ARIC is mandatory, scheduled, no shortcuts
7. **kai/queue/** — MCP server installation tasks for Mini

---

## Evolution

This protocol evolves via the Algorithm Evolution Lifecycle in AGENT_ALGORITHMS.md.
Agents can propose new questions for their domain-specific phases.
Kai reviews proposals. The question set gets smarter over time.

The meta-question that drives evolution:
  "When can we go and see what we Have Learned from taking that step?"
  — Coaching Kata Q5 (Mike Rother, Toyota Kata)

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
