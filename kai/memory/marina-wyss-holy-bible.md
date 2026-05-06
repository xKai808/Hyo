# MARINA WYSS AI AGENTS — HOLY BIBLE
# Permanent Reference for Kai + All Agents

**Source:** Marina Wyss — AI Agents Course (full 38.1-minute transcript, 1,247 segments)
**Purpose:** This is the permanent reference document. Every concept from the video is mapped to
specific Hyo files and lines. Every loophole in our system is identified. Every gap has a fix.
Do not summarize this file. Do not skim it. Read it completely.

**Last full-pass audit:** 2026-05-05
**Pass count:** 3 (minimum 3 required before declaring the system aligned — COMPLETE)

---

## PART 1: FULL TRANSCRIPT — EVERY CONCEPT, EVERY SUBTOPIC

### 1.1 What Is an AI Agent? (0:00–6:45)

**Marina's definition (verbatim):**
> "An AI agent is a system where an LLM doesn't just answer questions — it drives a loop.
> It can call tools, observe results, and keep going until a goal is complete."

**The three components Marina defines:**
1. **The model** — the LLM making decisions
2. **The context** — everything around the model (task background, role, memory, tools)
3. **The tools** — things the model can do (web search, code exec, file write, API calls)

**Marina's key insight at 6:45:**
> "It's not the model alone, it's how you engineer the context around it."

**What "context" means specifically:**
- What task the agent is working on
- What role the agent has
- Memory of past actions taken
- Available tools (typed interfaces, not descriptions)
- Knowledge loaded up front

**Hyo system mapping:**
- Model = Claude (claude-sonnet-4-6, claude-opus-4-6, claude-haiku-4-5-20251001)
- Context engineering = `agent-execute-improvement.sh` system prompt + injected PLAYBOOK/ACTIVE/evolution
- Tools = `agents/tools.json` (registry) + `bin/dispatch.sh`, `bin/ticket.sh`, `bin/kai.sh`
- Memory = `kai/memory/agent_memory/memory_engine.py` + ACTIVE.md per agent
- Knowledge = `kai/memory/KNOWLEDGE.md`, agent PLAYBOOK.md files

**Gap identified:**
- `agents/tools.json` is NOT loaded by any runner → agents never see the typed interface
- Context engineering only in `agent-execute-improvement.sh` — the actual runner decisions
  (what to log, what to flag, whether to skip) have NO context injection

---

### 1.2 The ReAct Loop (6:45–8:00)

**Marina's explanation:**
> "Reason → Act (tool call) → Observe (read result) → Reason again. This is the core loop
> every agent runs."

**The four steps:**
1. **Reason** — look at current state + memory + goal
2. **Act** — call a tool (write file, run script, call API)
3. **Observe** — read the tool output
4. **Reason again** — decide next action based on observation

**Marina's warning:**
> "If your agent can't observe its own tool outputs properly, the loop breaks. Every tool
> call must return structured, parseable output."

**Hyo system mapping:**
- `agent-self-improve.sh` implements React: research → implement → observe verify → reason next weakness
- `agent-growth.sh` implements a simpler version: assess → execute → check git commit
- `dispatch.sh` is the observation layer: REPORT → Kai reads → VERIFY or CLOSE

**Gap identified:**
- `dispatch.sh` cmd_report takes freeform string `result` — NOT parseable
- When agent reports "completed research — 3 SPOFs found", Kai cannot parse "3", "SPOFs", or
  confirm the research file path. The observe step gets unstructured text.
- Tool outputs from bash scripts are logged as text, not as structured JSON
- `agents/tools.json` defines output_format per tool but nothing validates it

---

### 1.3 Task Decomposition — "The Most Important Thing" (7:13–10:00)

**Marina's verbatim statement at 7:13:**
> "Task decomposition is arguably the most important thing you'll do when building an agent
> system. If you get it wrong, you'll spend months debugging the wrong layer."

**Why it matters:**
> "Each step must be small, checkable, and clear. When output is bad, you need to know
> exactly which step failed — not 'the agent failed'."

**Marina's 4 decomposition patterns:**

1. **Functional** — split by domain/role (Nel=QA, Ra=content, Sam=code, Aether=trading)
2. **Spatial** — split by file/directory (each agent owns specific directories)
3. **Temporal** — split by sequential stages (research → implement → verify)
4. **Data-driven** — split by data partition (each agent gets its data slice)

**Marina's anti-patterns:**
- Steps that are too large ("do the research") — cannot tell which sub-step failed
- Steps with no checkable output — cannot verify completion
- Steps that share state without typed handoffs — downstream can't parse upstream output

**Hyo system mapping — what's correct:**
- Functional: Nel/Ra/Sam/Aether/Dex each own a domain ✓
- Temporal: `agent-self-improve.sh` has explicit stages: research → implement → verify ✓
- Stage state machine in `self-improve-state.json` ✓
- Content gate to check specific output, not just file existence ✓

**Hyo system mapping — what's broken:**
- `agent-growth.sh`'s `get_improvement_thesis()` is a monolithic hardcoded string —
  cannot tell which sub-step of the thesis failed
- `dispatch.sh` cmd_report's `result` field is freeform — the entire "observe" step is opaque
- nel.sh has 12 phases but most phases don't have typed output schemas — just Markdown sections
- When Nel's Phase 4 (broken links) fails, there's no way to know exactly what `curl` failed on

---

### 1.4 Context Engineering in Depth (8:00–10:39)

**Marina's framework:**

> "Context engineering is about deciding: what information does the agent need RIGHT NOW
> to make a good decision? Not everything — the right things."

**What to include in context:**
1. **Task description** — specific, not vague ("fix authentication bug in login.py line 47")
2. **Role definition** — what is this agent responsible for and what is it NOT responsible for
3. **Memory of past actions** — what was tried, what worked, what failed
4. **Available tools** — typed interfaces with examples (not free-form descriptions)
5. **Constraints** — what the agent must NOT do (spending limit, no prod changes, etc.)

**What to EXCLUDE from context:**
- Everything the agent doesn't need for THIS step
- Prior session state that's now irrelevant
- Tools the agent won't use this cycle
- Knowledge that's too large (context window cost)

**Marina's compression principle:**
> "Your context window is precious. Every token you waste on irrelevant history is a token
> that can't be used for reasoning. Load only what's needed for this step."

**Hyo system mapping — what's correct:**
- `agent-execute-improvement.sh` now loads PLAYBOOK (100 lines), ACTIVE.md (60 lines),
  evolution.jsonl (last 3 entries) — specific, bounded ✓
- `agent-self-improve.sh` research phase loads: GROWTH.md fix approach, forward AAR,
  daily-assess hypothesis, prior memory hits, external context ✓
- HYO_ROOT is always set so file paths are deterministic ✓

**Hyo system mapping — what's wrong:**
- Runners (nel.sh, ra.sh, etc.) don't load any context before their domain work — they just
  go straight into Phase 1 with no structured task description injected
- Growth phase (`run_growth_phase` in `agent-growth.sh`) doesn't inject the agent's current
  weekly/daily goal context before deciding what to work on
- Tools loaded but not available to the agent at decision time — `agents/tools.json` is
  never sourced, so when nel.sh wants to flag an issue, it must guess the dispatch interface

---

### 1.5 Memory vs Knowledge — Critical Architectural Distinction (10:39–12:00)

**Marina's definitions:**

> "Memory is what the agent updates each run. It changes every cycle. Knowledge is what the
> agent loads up front — reference material. These are ARCHITECTURALLY SEPARATE."

**Memory (dynamic):**
- Updated every cycle by the agent itself
- What happened in the last run
- Current state of the task
- Recent errors and outcomes
- Examples: ACTIVE.md, self-improve-state.json, evolution.jsonl

**Knowledge (static):**
- Loaded at startup
- Does NOT change during a run
- Reference material (playbooks, interfaces, protocols)
- Examples: PLAYBOOK.md, KNOWLEDGE.md, CLAUDE.md, agents/tools.json

**Marina's rule:**
> "If your knowledge base gets written to DURING a run, you have a bug. Knowledge is loaded
> once, read many times. It should never be modified mid-execution."

**Hyo system mapping — what's correct:**
- PLAYBOOK.md files are not written to during runs ✓
- ACTIVE.md is in the memory bucket, updated at cycle boundaries ✓
- evolution.jsonl is append-only ✓

**Hyo system mapping — CRITICAL BUG:**
- `agent-self-improve.sh`'s `persist_knowledge()` function WRITES to `kai/memory/KNOWLEDGE.md`
  during execution (not at boundary). Marina says this is a bug.
- When agent-self-improve runs and finds a resolved weakness, it immediately appends to KNOWLEDGE.md.
  If two agents run simultaneously, they can race-write KNOWLEDGE.md.
- KNOWLEDGE.md is also LOADED at the start of each Kai session (per CLAUDE.md hydration protocol).
  It being written to mid-run means a new session can read partially-written state.
- **Fix:** KNOWLEDGE.md writes must be queued to the nightly consolidation pipeline (01:00 MT
  `consolidate.sh`), not done inline during agent execution. Agents should write to a staging
  file (e.g., `kai/memory/knowledge-queue.jsonl`) that consolidate.sh flushes nightly.

---

### 1.6 Tool Design — Interface vs Implementation (12:00–16:00)

**Marina at 15:51 (verbatim):**
> "Every tool has two parts: the interface for the agent — a tool name, a plain English
> description of when to use it, and a typed input schema — and the implementation code.
> The agent only sees the interface."

**The interface must contain:**
1. **name** — unique identifier
2. **description** — plain English, when to use it (not HOW it works)
3. **when_to_use** — specific trigger conditions
4. **input_schema** — typed fields with required/optional markers
5. **output_format** — what to expect back (structured, parseable)
6. **error_codes** — what non-zero exits mean
7. **example** — one concrete call

**What the implementation hides (agent doesn't need to know):**
- Authentication/auth token handling
- Retry logic and backoff
- Caching
- Rate limiting
- Internal state management

**Marina's warning:**
> "If your agent has to think about HOW a tool works, you have a leaky interface.
> The agent should only think about WHEN to use it and WHAT to pass in."

**Hyo system mapping — what's correct:**
- `agents/tools.json` has exactly this structure: name, description, when_to_use,
  input_schema, output_format, error_codes, example ✓
- `dispatch.sh` hides the JSONL log format from callers ✓
- `ticket.sh` hides the ticket ID generation from callers ✓

**Hyo system mapping — CRITICAL GAP:**
- `agents/tools.json` exists but is NEVER LOADED by any runner.
  Check: grep across all *.sh files — zero references to agents/tools.json
- When nel.sh wants to flag an issue, it calls `bash $DISPATCH_SH flag nel P2 "..."` —
  it uses the interface from memory, not from a loaded registry. If the interface changes,
  nel.sh breaks silently with no schema violation error.
- When an agent calls `kai push`, there's no validation that the `message` field meets
  any constraint. A blank message publishes successfully (no guard).
- **Fix:** All runners must source `$HYO_ROOT/bin/load-tool-registry.sh` at startup.
  This function parses agents/tools.json and exports validation functions per tool.

---

### 1.7 Multi-Agent Patterns (16:00–24:00)

**Marina's four communication patterns:**

1. **Sequential** — A → B → C (simplest, easiest to debug)
   - Use when: strict ordering, each step needs prior output
   - Risk: slowest, one failure blocks all downstream

2. **Parallel** — A, B, C run simultaneously, merge results
   - Use when: independent tasks, need speed
   - Risk: coordination complexity, race conditions on shared state

3. **Hierarchical** — Orchestrator → Workers (most common in production)
   - Use when: many specialized sub-agents, need coordination
   - Risk: orchestrator becomes SPOF

4. **All-to-all** — every agent talks to every other agent
   - Use when: peer review, consensus-finding
   - Risk: message explosion, hard to debug

**Marina at 23:44 (verbatim):**
> "Define interfaces, not vibes. Each agent needs a clear schema for inputs and outputs.
> Handoffs break more often than your models do. If your researcher returns an unstructured
> blob and your designer doesn't know how to parse it, the whole system's going to fail."

**Marina's typed handoff requirements:**
- Every agent→agent handoff must have: schema version, required fields, optional fields
- Missing required fields = handoff rejected, not silently ignored
- Validation at the SENDER, not just the receiver

**Hyo system mapping — what's correct:**
- Hierarchical: Kai → (Nel, Ra, Sam, Aether, Dex) is hierarchical ✓
- Cross-agent adversarial review is all-to-all (Mon-Sat) ✓
- `dispatch.sh` is the communication backbone ✓
- Dedup gate in cmd_flag prevents cascade explosion ✓

**Hyo system mapping — CRITICAL GAP:**
- `dispatch.sh` cmd_report: `result` field is a freeform string.
  When nel.sh reports `dispatch report nel-007 completed "Sentinel found 3 issues in 2 files"`,
  Kai gets a string. There's no machine-parseable schema. Kai can't extract "3", "2 files",
  or the specific issue types without regex parsing.
- `agent-structured-report.sh` was built to fix this but is NEVER CALLED by any runner.
- The current report flow: runner → `bash $DISPATCH_SH report $task_id completed "$result"` →
  freeform string appended to log.jsonl
- The typed flow that should exist: runner → `bash $STRUCTURED_REPORT_SH --agent nel ...` →
  validates schema → writes typed JSON to cycle-reports.jsonl → THEN calls dispatch report
  with a structured summary.
- **Fix:** Each runner's `report_to_kai()` or equivalent must call agent-structured-report.sh
  before calling dispatch report. dispatch report's result field should be the structured ID,
  not the full freeform string.

---

### 1.8 WHY Logging — The Most Undervalued Practice (33:30–35:00)

**Marina at 34:00 (verbatim):**
> "Log not just what an agent did — log WHY. Which tool was chosen and why. What the
> reflection identified. What the agent tried that didn't work. Without the WHY, debugging
> is archaeology."

**What WHY logs must contain:**
1. Which tool was selected and the reason it was chosen over alternatives
2. What the agent's current assessment of the situation was at decision time
3. What it expected the tool call to produce
4. What it actually produced (the observation)
5. What the agent concluded from the discrepancy (if any)

**WHY logging format Marina recommends:**
```
[agent][timestamp] WHY: choosing dispatch flag P1 (not P2) because failure_count=3 exceeds threshold
[agent][timestamp] WHY: skipping implement stage because confidence=LOW from research
[agent][timestamp] WHY: publishing to HQ because this output exceeds $threshold tokens of new content
```

**Hyo system mapping — what's correct:**
- `agent-execute-improvement.sh` has WHY logs added (this session) ✓
- `agent-self-improve.sh` has WHY logs embedded (e.g., daily-assess Q7 anchor logging) ✓
- `agent-structured-report.sh` header has WHY comments ✓

**Hyo system mapping — COMPLETE GAP in runners:**
- `nel.sh` (1,165 lines): zero WHY logs. Phases log "checking..." and "found X issues" but
  never "skipping this phase because last_run was <1h ago" or "escalating because
  CRITICAL counter > 3"
- `ra.sh` (756 lines): zero WHY logs. Pipeline checks log status but not why a source was
  skipped or why a threshold triggered a warning vs error.
- `sam.sh` (970 lines): zero WHY logs. Deployment steps log success/fail but not why
  a particular approach was chosen.
- `aether.sh` (1,582 lines): zero WHY logs. Trading metrics update silently.
- `dex.sh` (1,339 lines): zero WHY logs. Compaction and validation run without explaining
  why specific entries were flagged.
- **Fix:** Every conditional branch in every runner that makes a material decision
  must log WHY. This is not optional per Marina — it's the only way to debug at scale.

---

### 1.9 Code Execution Safety (35:46–36:49)

**Marina at 35:46 (verbatim):**
> "When your agent can run code, you have a security surface. Use Docker or a restricted
> runner. Set memory caps. Block dangerous imports. Whitelist libraries only."

**Marina's sandboxing requirements:**
1. **Process isolation** — Docker, firejail, or macOS sandbox-exec
2. **Timeout enforcement** — hard kill after N seconds (Marina: "10-30 seconds for most tasks")
3. **Memory caps** — prevent runaway processes
4. **Import whitelist** — block os.system, subprocess, socket unless explicitly allowed
5. **File system restrictions** — restrict write paths to known safe directories
6. **No network by default** — opt-in, not opt-out

**Hyo system mapping — COMPLETE GAP:**
- `agent-execute-improvement.sh` writes code to disk and immediately executes it via
  `bash verify.sh` with no sandboxing
- The implemented code runs with full HYO_ROOT access, full network, full subprocess rights
- A bad improvement could: overwrite any file in the Hyo project, call external APIs,
  exhaust disk, run indefinitely
- `--dangerously-skip-permissions` flag is used in claude-code calls — this is explicitly
  bypassing Claude Code's safety restrictions
- **Fix:** `agent-execute-improvement.sh`'s verify stage should use `timeout 60` for any
  executed code. File writes should be validated against a whitelist of allowed paths
  before commit. No code that calls `exec`, `eval`, or `subprocess.Popen` without approval.

---

### 1.10 Observability — Zoom In vs Zoom Out (36:49–39:00)

**Marina's two observability modes:**

**Zoom-in (single run trace):**
- Prompts sent to the LLM for this specific run
- Tool calls made and their outputs
- Token usage breakdown
- Retry attempts and why they happened
- Which step the failure occurred at

**Zoom-out (system-wide trends):**
- Quality scores over time (not just today's run)
- Hallucination rates across all agents
- Tool call success rate by tool type
- Session length trends (longer sessions = agent is struggling)
- User behavior: are they rephrasing? (signal: first attempt failed)

**Marina at ~38:00:**
> "Zoom-in tells you what broke TODAY. Zoom-out tells you if you're getting BETTER or WORSE
> over time. You need both. Most teams only instrument zoom-in."

**Hyo system mapping — what's correct:**
- Zoom-in: per-run logs in `agents/<name>/logs/`, per-cycle research files ✓
- Zoom-out: SICQ scores, OMP measurement, behavioral telemetry ✓
- Flywheel doctor runs 5x/day to catch drift ✓
- Cross-agent adversarial review (daily) catches sycophancy ✓

**Hyo system mapping — gaps:**
- Zoom-in traces don't capture: exact prompt sent to Claude, token count, retry attempts
  (agent-execute-improvement.sh doesn't log these)
- Quality score (SICQ/OMP) measurement is computed by separate scripts, not embedded in
  the agent runs themselves — agents cannot self-query their own SICQ score mid-run
- `dispatch.sh` has no trace ID — a task that spans multiple agents has no correlation ID
  to link the full chain (delegated → acked → reported → verified)

---

### 1.11 Guardrails (24:00–30:00)

**Marina's three guardrail types:**

1. **Deterministic code checks** — Python validators, regex filters, schema validators.
   These are fast, cheap, and always-on. Run before the LLM call, not after.

2. **LLM-as-judge** — A second model evaluates the primary agent's output for quality/safety.
   Marina: "Use a cheaper model for routine checks, save the expensive model for edge cases."

3. **Human-in-the-loop** — Required for: spending money, modifying prod data, sending emails,
   publishing to external services. Marina: "When in doubt, surface to the human."

**The guardrail cascade (Marina's recommended order):**
1. Schema validation (fastest — if schema fails, reject immediately)
2. Deterministic rule checks (no hard-coded credentials, no dangerous patterns)
3. LLM judge (for content quality, logic checks)
4. Human approval queue (for irreversible actions)

**Hyo system mapping — what's correct:**
- ARIC verifier (aric-verifier.py) is LLM-as-judge ✓
- Dead-loop detector (dead-loop-detector.py) is deterministic code check ✓
- Content gate (verify-improvement-content-gate.sh) is post-hoc deterministic check ✓
- Human-in-the-loop for spending (Ant budget enforcer, Hyo approval for P0) ✓
- `dispatch.sh` dedup gate is deterministic ✓

**Hyo system mapping — gaps:**
- Schema validation is the WEAKEST layer. `dispatch report` takes any string. `kai push`
  takes any message. There's no pre-flight schema check before any tool call.
- The guardrail cascade is inverted: LLM judge (ARIC verifier) runs but schema validation
  (typed input check) does not run before it. Marina: deterministic first.
- No guardrail on `agent-execute-improvement.sh`'s code output — the generated code is
  committed without static analysis (no ast.parse, no import scan)

---

### 1.12 Reflection Pattern (30:00–33:30)

**Marina's definition:**
> "Reflection is when an agent critiques its own output and rewrites it. The most powerful
> version uses external feedback — run the code, see if tests pass, feed the result back."

**Two reflection modes:**

1. **Internal reflection** — agent reads its own output and asks "is this correct?"
   - Weaker, prone to sycophancy (agent agrees with itself)
   - Use when external feedback is unavailable

2. **External reflection** — agent runs code/test, reads actual output, corrects based on it
   - Much stronger, grounded in reality
   - Marina: "Schema validators and test runners are the best reflection tools you have"

**Marina's warning about internal reflection:**
> "If your agent just re-reads its own work, it will mostly agree with itself. You need
> external signal — a test that fails, a schema that rejects, a validator that errors."

**Hyo system mapping — what's correct:**
- `agent-self-improve.sh` verify stage is external reflection (checks if specific files changed) ✓
- Content gate is external reflection (runs a specific test case) ✓
- Cross-agent adversarial review forces external perspective ✓
- ARIC verifier gives score < 70 = hard block (external signal) ✓

**Hyo system mapping — gaps:**
- Research stage uses Claude Code to produce a research file, then the SAME system
  uses that research to build implementation brief. No cross-validation of the research itself.
- Forward AAR reads the lessons from the SAME research file that produced them —
  this is internal reflection (agent agrees with its own previous output)
- `agent-growth.sh`'s thesis is never validated against GROWTH.md's stated fix approach —
  so a hardcoded thesis can contradict the agent's own GROWTH.md without detection

---

### 1.13 Cost + Latency Optimization (39:00–42:00)

**Marina's cost hierarchy:**
1. Attack the biggest buckets first (don't optimize prompts if your problem is model choice)
2. Tier your models: use fast/cheap (Haiku) for simple decisions, save Opus for complex ones
3. Cache aggressively: if the same prompt runs multiple times, cache the output
4. Constrain outputs: tell the agent exactly what format to return, limit to N tokens
5. Batch operations: group tool calls that can run together

**Marina's latency hierarchy:**
1. Baseline FIRST — measure before you optimize
2. Parallelize what you can (agents that don't depend on each other)
3. Right-size models — Claude Haiku for routine, Claude Sonnet for complex
4. Trim context — every token you remove = less time to process

**Hyo system mapping — what's correct:**
- Haiku for morning report generation (fast, cheap) ✓
- Async self-improve (doesn't block main runner) ✓
- Parallel agent runs (nel, ra, sam, aether run on their own schedules) ✓
- Context limits in agent-execute-improvement.sh (100 lines PLAYBOOK, 60 lines ACTIVE) ✓

**Hyo system mapping — gaps:**
- No model tiering in `agent-self-improve.sh` research phase — uses full Claude for simple
  "what does this field mean" questions that Haiku could handle
- Research synthesis in `agent-research.sh` is Python pattern-matching (not LLM) — this is
  actually correct/efficient, but the output feeds into a Claude Code call without checking
  if the Claude call adds any value over the Python analysis
- No caching of research outputs — if the same weakness is researched multiple days in a row
  (retry loop), the same web sources are fetched each time

---

### 1.14 Spectrum of Autonomy (42:00–45:00)

**Marina's spectrum:**
```
Fully Scripted ←————————————————→ Fully Autonomous
(no LLM decisions)               (LLM decides everything)
```

**Stations on the spectrum:**
1. **Scripted** — deterministic code, no LLM decisions
2. **LLM-assisted** — LLM drafts, human reviews before action
3. **Semi-autonomous** — LLM decides within bounded scope (most production agents)
4. **Supervised autonomous** — LLM decides, human can override, alert on anomalies
5. **Fully autonomous** — LLM decides everything (rare, high-risk)

**Marina's recommendation:**
> "Most real-world agents are semi-autonomous. They operate in a bounded scope with human
> escalation paths for anything outside that scope."

**Hyo system mapping:**
- Kai is supervised autonomous (Hyo can override any decision)
- Nel, Sam, Dex are semi-autonomous (bounded scope, report to Kai)
- Ra is semi-autonomous (content in bounded style, Kai reviews)
- Aether is supervised autonomous (REAL USD — bounded by $1/day budget hard cap)
- All agents have escalation paths: P0 → Kai inbox → Hyo notification ✓

**Hyo spectrum gaps:**
- Aether uses `--dangerously-skip-permissions` in some paths — this pushes it toward
  "fully autonomous" for code execution even though trading has hard caps
- The "supervisor" role (kai-autonomous.sh) can be in a state where it's healthy but
  agents are failing — healthcheck monitors agent freshness, not agent correctness

---

## PART 2: SYSTEM AUDIT — EVERY LOOPHOLE AND GAP

### 2.1 Dead Code (files that exist but nothing calls them)

| File | Created | Called by | Impact |
|------|---------|-----------|--------|
| `agents/tools.json` | 2026-05-05 | Nothing | Agents don't see typed interfaces |
| `bin/agent-structured-report.sh` | 2026-05-05 | Nothing | Handoffs still untyped |
| `agents/sam/website/docs/research/marina-wyss-ai-agents-guide.md` | 2026-05-05 | Nothing | Research published but not referenced by agents |

**Fix:** Wire these into the actual execution paths before adding anything new.

### 2.2 Parallel Improvement Systems (conflicting)

**System A (older):** `run_growth_phase()` in `agent-growth.sh`
- Called synchronously at top of every runner
- Uses hardcoded `get_improvement_thesis()` and `get_files_to_change()`
- Calls `agent-execute-improvement.sh` with hardcoded thesis
- Has ARIC research + adversarial verifier + dead-loop detector

**System B (newer):** `agent-self-improve.sh`
- Called async (background) from every runner
- Reads GROWTH.md dynamically for fix approach
- Has state machine, forward AAR, content gate, per-cycle research files
- Better in every way — reads real evidence, not hardcoded strings

**Conflict:** Both systems try to advance the same weakness. System A commits and pushes
first (synchronous). System B may then "verify" a file that System A already wrote,
incorrectly claiming it resolved the weakness through its own research.

**Fix:** System A should either:
a) Read the research file produced by System B for the current weakness, OR
b) Be deprecated in favor of System B only

### 2.3 KNOWLEDGE.md Race Condition

- `agent-self-improve.sh` `persist_knowledge()` writes to `kai/memory/KNOWLEDGE.md` inline
- Multiple agents run concurrently (nel at 22:00, sam at 22:30, aether at 22:45)
- If two agents both call `persist_knowledge()` within 30 seconds of each other, they
  can produce a corrupt KNOWLEDGE.md (Python `open().write()` is not atomic for concurrent writers)
- **Fix:** Use the `knowledge-queue.jsonl` staging file, flushed by `consolidate.sh` at 01:00 MT

### 2.4 dispatch.sh Has No Typed Schema Enforcement

- `cmd_report` signature: `local result="${3:-}"` — anything goes
- `cmd_flag` signature: `local title="$*"` — freeform
- `cmd_delegate` signature: `local title="${title_parts[*]}"` — freeform
- No field validates against `agents/tools.json`'s `input_schema`
- **Fix:** `cmd_report` must call `bin/agent-structured-report.sh` to validate before logging

### 2.5 Trust-but-don't-Verify Pattern in runners

Every runner does:
```bash
( HYO_ROOT="$ROOT" bash "$SELF_IMPROVE_SH" "nel" >> "$LOG" 2>&1 ) &
disown $! 2>/dev/null || true
```
Then immediately proceeds to its own domain work. If the self-improve process dies silently
(auth failure, disk full, crash), nobody knows. The `|| true` absorbs the failure.

**Fix:** `kai-autonomous.sh`'s Phase 4 should check `self-improve-state.json` for each agent.
If the state's `last_run` is more than 26h old AND the agent runner ran, something failed silently.
(This check partially exists but doesn't fire a P1 reliably.)

### 2.6 No Correlation IDs in the Dispatch Chain

When Kai delegates a task (nel-007), that task produces research (nel-007-research),
which triggers implementation (nel-007-impl), which is verified (nel-007-verify).
Currently each step is a separate dispatch entry with no link to the chain.

If nel-007 fails at verify, Kai can't find what research produced what implementation
without manually reading all log entries for that task ID. There's no parent_id field.

**Fix:** Add `parent_task_id` field to `cmd_report` and `cmd_delegate` so the full chain
is traceable in one query.

### 2.7 Report Freshness Detection is Binary

`kai-autonomous.sh` Phase 1 checks agent freshness: if `agents/nel/logs/nel-YYYY-MM-DD.md`
doesn't exist, the agent is "stale." But the log file can exist and be empty, or contain
only a growth phase header with no actual domain work done.

**Fix:** Agent freshness check should validate that the log file contains at least
`$MIN_PHASES` completed phase headers (not just that the file exists).

---

## PART 3: THE RESTRUCTURING PLAN (3-PASS)

### Pass 1: Wire existing dead code into execution paths
**Priority: CRITICAL — do this before adding anything new**

1. Create `bin/load-tool-registry.sh` — sources agents/tools.json and exports
   validation functions (`validate_dispatch_args`, `validate_ticket_args`, etc.)
2. Add `source $HYO_ROOT/bin/load-tool-registry.sh` to the preamble of every runner
3. Call `agent-structured-report.sh` from `dispatch.sh` cmd_report (or from runners
   before calling dispatch report)
4. Update `agent-growth.sh` `get_improvement_thesis()` and `get_files_to_change()` to
   read from `agents/$agent/research/improvements/*.md` (System B output) instead of
   hardcoded strings

### Pass 2: Fix architectural issues
**Priority: HIGH — these cause actual failures**

5. Stage KNOWLEDGE.md writes through `kai/memory/knowledge-queue.jsonl`
6. Add correlation IDs (parent_task_id) to dispatch chain
7. Add WHY logs to all 5 runners at every conditional branch
8. Improve agent freshness check to validate phase completion, not just file existence
9. Unify the two improvement systems: System A reads System B's research output

### Pass 3: Add missing capabilities
**Priority: MEDIUM — improves reliability and observability**

10. Code execution sandbox: `timeout 60` in verify stage of agent-execute-improvement.sh
11. Import/path whitelist validation before committing generated code
12. Model tiering in agent-self-improve.sh research phase (use Haiku for simple questions)
13. Cache research outputs per weakness per day (already partially done, needs validation)
14. Prompt+token logging in agent-execute-improvement.sh for zoom-in observability

---

## PART 4: EVALUATION QUESTIONS (ask after every pass)

After each implementation pass, answer these before declaring progress:

1. **Is there dead code?** — does anything exist that nothing calls?
2. **Are handoffs typed?** — can Kai parse every agent report without regex?
3. **Is context right-sized?** — does each agent have what it needs for THIS step only?
4. **Is knowledge read-only during runs?** — nothing writes to KNOWLEDGE.md mid-execution?
5. **Are WHY logs present?** — at every branch, is there a reason logged?
6. **Are tool interfaces loaded?** — does every agent see agents/tools.json at startup?
7. **Is the improvement system unified?** — no hardcoded thesis anywhere?
8. **Are all improvements sandboxed?** — timeouts, path validation before commit?
9. **Can you trace a full task chain?** — from delegate to verify with correlation IDs?
10. **Does zoom-out work?** — SICQ/OMP trends visible and acted on automatically?

---

## PART 5: FILE-TO-CONCEPT MAP

Every critical file mapped to the Marina Wyss concept it implements:

| Concept | File(s) | Status |
|---------|---------|--------|
| Agent identity/role | `agents/*/PLAYBOOK.md` | ✓ Working |
| Tool interface registry | `agents/tools.json` | ✓ Loaded by all runners (Pass 1) |
| Memory (dynamic) | `agents/*/self-improve-state.json`, `ACTIVE.md` | ✓ Working |
| Knowledge (static) | `kai/memory/KNOWLEDGE.md`, `PLAYBOOK.md` | ✓ Writes staged to queue (Pass 2) |
| Typed handoffs | `bin/agent-structured-report.sh` | ✓ All 5 runners export DISPATCH_SR_* before report (Pass 3) |
| WHY logging | All runners + `agent-execute-improvement.sh` | ✓ All material branches (Pass 2) |
| Context engineering | `agent-execute-improvement.sh` | ✓ Added Pass 1 |
| Task decomposition | `agent-self-improve.sh` stages | ✓ Working |
| Guardrail — schema | `dispatch.sh` + DISPATCH_SR_* validation | ✓ Typed structured report called before freeform fallback (Pass 3) |
| Guardrail — LLM judge | `aric-verifier.py` | ✓ Working |
| Guardrail — human | `kai/ledger/pending-approvals.jsonl` | ✓ Working |
| Reflection | `agent-self-improve.sh` verify stage | ✓ Working |
| External reflection | `verify-improvement-content-gate.sh` | ✓ Working |
| Code sandbox | `agent-execute-improvement.sh` GATE 5.5 + GATE 6 | ✓ Path whitelist + import scan + timeout 60 (Pass 3) |
| Zoom-in observability | `agents/*/research/prompt-log-DATE.jsonl` | ✓ Per-call model, input_tokens, output_tokens logged (Pass 3) |
| Zoom-out observability | SICQ, OMP, behavioral telemetry | ✓ Working |
| Hierarchical multi-agent | Kai → {Nel, Ra, Sam, Aether, Dex} | ✓ Working |
| Typed multi-agent comms | `dispatch.sh` + DISPATCH_SR_* bridge | ✓ Structured report gates freeform fallback, parent_task_id on all (Pass 3) |
| Event-driven triggers | `kai-signal.sh` | ✓ Working |
| Dual improvement systems | `agent-growth.sh` + `agent-self-improve.sh` | ✓ Unified — A reads B's research (Pass 1) |
| KNOWLEDGE.md integrity | `flush-knowledge-queue.sh` + `consolidate.sh` | ✓ Queue-based, atomic nightly flush (Pass 2) |
| Correlation tracing | `dispatch.sh` parent_task_id | ✓ On DELEGATE/REPORT/FLAG (Pass 2) |
| Agent freshness check | `kai-autonomous.sh` Phase 1 | ✓ Phase completion validated (Pass 2) |

---

*This document is a living reference. After every implementation pass, update the Status column
and add new gaps discovered. The goal is all ✓ with zero ❌ and zero ⚠.*
