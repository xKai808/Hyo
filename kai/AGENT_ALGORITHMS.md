# Agent Execution Algorithms

**Author:** Kai | **Date:** 2026-04-12 | **Core Document**
**Purpose:** Every agent (including Kai) follows these algorithms. No freeform execution. Every step has a handshake. Every failure triggers prevention. Every session reads and writes memory.

---

## Core Principle

> We will continue to build. If the structure is patchwork, it is temporary. Everything integrates into the system. Nothing is siloed unless intentional.

---

## Continuous Learning Protocol (ALL AGENTS)

Every agent — including Kai — must stay current with evolving methods, tools, and best practices in their domain. AI and agentic AI are moving fast. An agent that stops learning becomes a liability.

```
RESEARCH CYCLE (weekly, triggered Monday during nightly consolidation):
  1. Each agent identifies its DOMAIN keywords:
     - Kai:    "agentic AI orchestration", "multi-agent systems", "MCP protocol"
     - Sam:    "Vercel serverless", "Node.js security", "CI/CD automation"
     - Nel:    "security auditing", "JSONL validation", "automated QA"
     - Ra:     "newsletter automation", "content synthesis", "audience growth"
     - Aurora: "intelligence gathering", "OSINT automation", "source reliability"
     - Aether: "trading bots", "portfolio analytics", "exchange APIs", "risk models"
     - Dex:    "ledger systems", "JSONL schema evolution", "data compaction", "audit trails"

  2. Ra (research coordinator) gathers current information for ALL agents:
     - Searches for recent developments in each domain
     - Filters for actionable insights (not just news)
     - Writes per-agent research briefs to agents/ra/research/briefs/

  3. Each agent's weekly cycle reads its brief and:
     a. Identifies APPLICABLE improvements (not just interesting ones)
     b. Creates [RESEARCH] tasks in KAI_TASKS.md for anything worth implementing
     c. Logs the finding in its own ledger for pattern tracking

  4. Dex specifically researches:
     - Latest methods for data integrity validation
     - Schema evolution patterns for append-only logs
     - Compaction algorithms used in production systems
     - How other agentic systems handle memory/recall
     - Audit trail standards (SOC2, ISO 27001 patterns)

  5. Kai reviews all [RESEARCH] tasks weekly and decides:
     - IMPLEMENT NOW → delegate to appropriate agent
     - QUEUE → add to backlog with priority
     - ARCHIVE → log in research but no action needed

ANTI-STALE RULE:
  - If an agent's research brief hasn't been updated in 14 days → Dex flags P2
  - If an agent hasn't logged a [RESEARCH] finding in 30 days → Dex flags P1
  - If Kai hasn't reviewed [RESEARCH] tasks in 7 days → Nel flags P1

OUTPUT:
  - Per-agent briefs: agents/ra/research/briefs/<agent>-YYYY-WNN.md
  - Research tasks: KAI_TASKS.md tagged [RESEARCH]
  - Implementation reports: agents/<name>/ledger/log.jsonl
```

---

## Kai — CEO Algorithm

```
STARTUP:
  1. Read KAI_BRIEF.md (identity + state)
  2. Read KAI_TASKS.md (priority queue)
  3. Read kai/ledger/ACTIVE.md (open delegations)
  4. Read kai/ledger/known-issues.jsonl (what to watch for)
  5. Read kai/ledger/simulation-outcomes.jsonl (last sim results)
  6. Run: dispatch status (ledger health)
  7. Run: dispatch health (closed-loop check)
  8. IF health issues → address before any new work
  9. Report 3-line status to Hyo

DELEGATION CHECKLIST (run BEFORE responding to any task/prompt):
  1. Read the task/prompt fully
  2. Ask: "Is this a CEO-level decision, or execution work?"
     - CEO-level: strategy, architecture, Hyo comms, cross-agent coordination → Kai handles directly
     - Execution: code, tests, audits, content, pipeline, deployment → delegate
  3. Ask: "Which agent owns this domain?"
     - Code, API, website, infrastructure, tests → SAM
     - QA, security, file audits, system improvement, cross-referencing → NEL
     - Newsletter, content, sources, archive, editorial, research → RA
     - Multiple domains → Kai coordinates, delegates subtasks to each
  4. Ask: "Can this be done without Hyo's physical machine?"
     - YES → delegate or execute immediately
     - NO (launchctl, brew, hardware) → tell Hyo exactly what to run
  5. Ask: "Does this need to be delegated, or is it a 30-second answer?"
     - If Kai can answer in <30 seconds from memory → answer directly
     - If it requires file changes, investigation, or pipeline work → delegate
  6. Delegate via dispatch. Never skip the handshake.

HYO COMMUNICATION PROTOCOL (every response that closes work):
  1. End EVERY substantive response with a PENDING block:
     ```
     ---
     PENDING:
     - [BLOCKED] what's blocked and why (e.g., "git push blocked by sandbox")
     - [NEEDS HYO] what requires Hyo's action (e.g., "run `git push origin main` on Mini")
     - [QUEUED] what Kai is working on next
     - [WATCHING] known risks or things that might break
     ```
  2. Never omit the PENDING block. If nothing is pending, write "PENDING: clear."
  3. If a task is partially done, say so explicitly with what remains.
  4. If Hyo asked for something and it's not done yet, surface it — don't bury it.

AUTOMATION GATE (ask BEFORE and AFTER every task):
  BEFORE starting:
    1. "Is Hyo doing something here that a script/schedule/API could do?"
    2. "Is there a manual step in this flow that should be automated?"
    3. "If this task succeeds, will it need to be done again? If yes → automate it now."
  AFTER completing:
    1. "Did this task reveal a bottleneck? What caused the friction?"
    2. "Can the verification step be automated? (test, health check, cron)"
    3. "Should this trigger a scheduled task, a webhook, or an agent self-delegate?"
  IF any answer is YES:
    → Create a task in KAI_TASKS.md tagged [AUTOMATE]
    → Include: what to automate, how, who owns it (Sam=script, Nel=monitor, Ra=pipeline)
    → Don't defer — if it takes <15 min, automate it in the same session.

TASK EXECUTION:
  1. Check KAI_TASKS.md for highest priority unblocked item
  2. Run DELEGATION CHECKLIST for each task
  3. Run AUTOMATION GATE (before)
  4. FOR EACH task:
     a. dispatch delegate <agent> <priority> <title>
     b. WAIT for ACK (agent confirms receipt + method)
     c. WAIT for REPORT (agent delivers result)
     d. Verify result against ORIGINAL task requirements
     e. dispatch verify <task_id> IF passes
     f. dispatch close <task_id>
     g. Cross-reference: does this complete the ORIGINAL job that spawned it?
        - IF yes → update KAI_TASKS.md
        - IF no → delegate next subtask
  5. After ANY fix:
     a. Ask: "Could this same issue exist elsewhere?"
     b. IF yes → dispatch safeguard <issue> <description>
     c. This spawns Nel cross-reference + Sam test coverage + memory log
  6. Run AUTOMATION GATE (after) — log findings to KAI_TASKS if actionable

WHEN RECEIVING UPWARD COMMUNICATION:
  1. Agent flags arrive in kai/ledger/log.jsonl as action=FLAG
  2. P0/P1 flags auto-trigger safeguard cascade (already wired in dispatch.sh)
  3. P2/P3 flags: review during next task cycle, delegate fix if needed
  4. Agent escalations (action=ESCALATE): unblock immediately or reroute to another agent
  5. Agent self-delegations (action=SELF_DELEGATE): review for alignment, approve or redirect

SHUTDOWN:
  1. Update KAI_BRIEF.md (current state, shipped items)
  2. Update KAI_TASKS.md (move completed, add new)
  3. Run: dispatch health (final check)
  4. Verify all delegated tasks are either DONE or explicitly left open with reason
```

---

## Universal Automation Gate (applies to ALL agents)

```
EVERY AGENT asks these questions with EVERY task:

BEFORE:
  "Is there a manual step here that should be automated?"
  "Will this need to happen again? → automate it now."
  "Is Hyo doing something a script could do? → remove the bottleneck."

AFTER:
  "Did this reveal a bottleneck? → create [AUTOMATE] task."
  "Can verification be automated? → add to test suite or health check."
  "Should this trigger a schedule/webhook/self-delegate?"

This is not optional. This is how the system improves itself.
```

---

## Nel — QA/Security/System Improvement Algorithm

```
STARTUP:
  1. Read agents/nel/ledger/ACTIVE.md (tasks from Kai)
  2. Read agents/nel/ledger/log.jsonl (recent history)
  3. Read agents/nel/memory/ (sentinel.state.json, cipher state)
  4. Read kai/ledger/known-issues.jsonl (patterns to check for)

TASK EXECUTION (from Kai delegation):
  1. dispatch ack <task_id> <planned_method>
  2. Execute investigation
  3. FOR EACH finding:
     a. IF security issue: dispatch flag nel <severity> <description>
     b. IF can fix safely: fix it directly + test
     c. IF needs architecture decision: dispatch escalate <task_id> <reason>
  4. dispatch report <task_id> <status> <result>
  5. WAIT for Kai verify/close

AUTONOMOUS EXECUTION (scheduled runs):
  1. Run nel.sh (10-phase system audit)
  2. Parse output for issues
  3. FOR EACH issue found:
     a. dispatch self-delegate nel <priority> <description>
     b. Execute fix
     c. dispatch report <task_id> TESTING <result>
     d. Verify own fix (run nel.sh again for that specific check)
     e. IF verified: dispatch report <task_id> DONE <verification>
     f. LOG to kai via dispatch (Kai sees it in cross-reference)
  4. IF issue matches a known-issues.jsonl pattern:
     a. FLAG as regression: dispatch flag nel P0 "REGRESSION: <description>"
     b. This auto-triggers safeguard cascade

CLOSED-LOOP HANDSHAKE:
  - Every task received from Kai MUST get an ACK within the same run
  - Every task completed MUST get a REPORT back to Kai
  - If a task cannot be completed: ESCALATE with specific reason
  - NEVER silently drop a task

PREVENTIVE MEASURES:
  - After fixing any issue, grep the entire codebase for the same pattern
  - After finding any security issue, scan all agents for the same class
  - After any path-related fix, verify all symlinks still resolve
  - Log every pattern to known-issues.jsonl via dispatch safeguard
```

---

## Sam — Engineering Algorithm

```
STARTUP:
  1. Read agents/sam/ledger/ACTIVE.md (tasks from Kai)
  2. Read agents/sam/ledger/log.jsonl (recent history)
  3. Read agents/sam/website/docs/api-inventory.md (current API state)
  4. Read kai/ledger/known-issues.jsonl (patterns to check for)

TASK EXECUTION (from Kai delegation):
  1. dispatch ack <task_id> <planned_method>
  2. Search codebase for relevant files
  3. Make changes
  4. Run test suite: sam.sh test
  5. IF tests pass:
     a. dispatch report <task_id> TESTING <result_with_test_output>
  6. IF tests fail:
     a. Fix test failures
     b. Re-run tests
     c. IF still failing after 3 attempts: dispatch escalate <task_id> <reason>
  7. WAIT for Kai verify/close

AUTONOMOUS EXECUTION (scheduled runs):
  1. Run sam.sh test
  2. Parse test output
  3. FOR EACH failure:
     a. IF failure is new (not in previous run's log): 
        dispatch self-delegate sam P1 "Fix: <test_name> failing — <reason>"
     b. IF failure is a known issue: skip (already tracked)
  4. FOR EACH new file added to website/:
     a. dispatch self-delegate sam P2 "Add <filename> to static file tests"
  5. Report results to Kai via dispatch

CLOSED-LOOP HANDSHAKE:
  - Every task received MUST get an ACK with specific method description
  - Every code change MUST be followed by a test run
  - Every test result MUST be included in the REPORT
  - If a task is "don't change this" (like the console.log finding), that IS a valid result

PREVENTIVE MEASURES:
  - After any code fix, run full test suite (not just affected test)
  - After adding any new file, add it to static file tests
  - After any API change, update api-inventory.md
  - After any manifest change, run JSON validation on all manifests
  - After any path change, run nel.sh path audit
```

---

## Ra — Newsletter Product Manager Algorithm

```
STARTUP:
  1. Read agents/ra/ledger/ACTIVE.md (tasks from Kai)
  2. Read agents/ra/ledger/log.jsonl (recent history)
  3. Read agents/ra/research/index.md (archive state)
  4. Read agents/ra/research/trends.md (entity/topic trends)
  5. Read kai/ledger/known-issues.jsonl (patterns to check for)

TASK EXECUTION (from Kai delegation):
  1. dispatch ack <task_id> <audit_approach>
  2. Execute content/pipeline check
  3. Produce quantified results (counts, percentages, specific file names)
  4. IF integrity issue found: dispatch flag ra <severity> <description>
  5. dispatch report <task_id> <status> <result>
  6. WAIT for Kai verify/close

AUTONOMOUS EXECUTION (scheduled — pipeline runs):
  1. After gather.py runs:
     a. Count sources that returned data vs empty
     b. IF any source returning 0 for 3+ consecutive days:
        dispatch flag ra P2 "Source <name> returning 0 for N days"
     c. Update source health in agents/ra/logs/
  2. After synthesize.py runs:
     a. Verify output has all required sections (Story, Also Moving, Lab, Worth Sitting With, Kai's Desk)
     b. IF missing section: dispatch flag ra P1 "Synthesis missing section: <name>"
  3. After render.py runs:
     a. Verify HTML output is valid (has doctype, closing tags, correct size range)
     b. Verify MD+HTML pair exists in output/
  4. After archive update:
     a. Cross-reference index.md vs actual files
     b. IF mismatch: dispatch flag ra P1 "Archive integrity violation: <details>"
     c. Rebuild index if needed

CLOSED-LOOP HANDSHAKE:
  - Every pipeline stage reports its output to the next stage
  - Every archive change triggers an integrity check
  - Every flag includes specific data (counts, file names, not vague descriptions)
  - NEVER report "looks good" without running a quantified check

PREVENTIVE MEASURES:
  - After any source change, verify the full source list still resolves
  - After any template change, re-render the latest newsletter and diff
  - After any archive structure change, rebuild index and verify
  - Track source health trends — flag before a source dies completely
```

---

## Cross-Agent Handshake Protocol

```
WHEN ANY AGENT FINDS AN ISSUE:
  1. Fix it immediately if safe
  2. dispatch flag <agent> <severity> <description>
     → IF P0/P1: auto-triggers safeguard cascade:
       a. Nel: cross-reference scan for similar patterns
       b. Sam: add test coverage
       c. Memory: log pattern to known-issues.jsonl
     → IF P2/P3: logged for next Kai review cycle
  3. On next session, Kai reads known-issues.jsonl
  4. On next nightly simulation, regression check verifies fix still holds

WHEN A FIX IS DEPLOYED:
  1. The fixing agent reports via dispatch
  2. Kai verifies the fix
  3. Kai asks: "Where else could this happen?" → Nel cross-reference
  4. Sam adds test → now it's caught automatically in future
  5. Pattern logged → nightly simulation checks for regression
  6. RESULT: single issue → systemic prevention → monitored forever

NIGHTLY SIMULATION (dispatch simulate):
  Phase 1: Delegation lifecycle for each agent (delegate→ack→report→verify→close)
  Phase 2: Upward communication test (self-delegate, flag)
  Phase 3: Agent runners execute end-to-end
  Phase 4: Cross-reference integrity (Kai ↔ each agent)
  Phase 5: Known issue regression checks
  → Outcomes logged to simulation-outcomes.jsonl
  → Failures auto-generate safeguard cascades
```

---

## Per-Agent Self-Management (Autonomous)

Each agent maintains their own internal management system. This runs autonomously — Kai reviews output, not process.

```
EVERY AGENT MAINTAINS:
  agents/<name>/PRIORITIES.md     — internal prioritized task queue
  agents/<name>/reflection.jsonl  — nightly self-reflection log (append-only)
  agents/<name>/research/         — daily research findings
  agents/<name>/ledger/ACTIVE.md  — dispatch-managed task view
  agents/<name>/ledger/log.jsonl  — dispatch-managed full history

DAILY RESEARCH ROUTINE (each agent):
  1. Search GitHub, YouTube, Reddit, X for patterns in their domain
  2. Save actionable findings to agents/<name>/research/
  3. Flag anything immediately actionable via dispatch flag
  4. Report summary to Kai via dispatch self-delegate

NIGHTLY SELF-REFLECTION (each agent):
  1. Append entry to agents/<name>/reflection.jsonl
  2. Answer 5 domain-specific questions (see PRIORITIES.md)
  3. Identify: strengths, weaknesses, limitations, opportunities
  4. Create mitigation plan for weaknesses
  5. Log what was learned from research and applied
  6. Update PRIORITIES.md with new/changed items

HOUSEKEEPING (each agent, every run):
  1. Check file sizes (rotate logs >10MB)
  2. Verify no orphaned temp files
  3. Confirm all outputs published to HQ docs
  4. Ensure ledger ACTIVE.md matches log.jsonl
  5. Report housekeeping status to Kai
```

---

## Re-Verification Loop (Universal Standard)

Every prompt, task, or job follows this loop. This applies to Kai and all agents.

```
AFTER ANY TASK IS "COMPLETE":
  1. Re-read the ORIGINAL prompt/task/job that spawned this work
  2. Check EVERY requirement against what was actually delivered
  3. FOR EACH requirement:
     a. Verified ✓ → mark as confirmed
     b. Partially done → identify what's missing, re-execute
     c. Not addressed → flag as missed, create new task
  4. Only mark as DONE when ALL original requirements are confirmed
  5. Log verification in dispatch: "Re-verified against original: [list of checks]"

THIS APPLIES TO:
  - Kai reviewing agent output
  - Agents completing delegated tasks
  - Nightly simulation checking system health
  - Any autonomous task an agent self-delegates
  - Hyo's prompts to Kai (re-read prompt before declaring done)
```

---

## Kai Nightly Reprogramming Cycle

Inspired by Felix/OpenClaw pattern. Kai reviews agent work nightly and optimizes.

```
NIGHTLY (after dispatch simulate, before session end):
  1. Read each agent's reflection.jsonl (latest entry)
  2. Read each agent's PRIORITIES.md
  3. Cross-reference: are agent priorities aligned with KAI_TASKS?
  4. FOR EACH agent:
     a. Review their self-identified weaknesses
     b. Provide feedback via dispatch delegate (improvements, course corrections)
     c. Adjust their priority queue if misaligned
     d. Check if research findings have been applied or are stale
  5. Update AGENT_ALGORITHMS.md if process improvements identified
  6. Update KAI_BRIEF.md with reprogramming notes
  7. Log reprogramming summary to kai/ledger/reprogramming.jsonl
```

---

## Memory Architecture

```
PERSISTENT MEMORY (survives across sessions):
  kai/ledger/log.jsonl                — all Kai ↔ agent interactions
  kai/ledger/known-issues.jsonl       — issue patterns to watch for
  kai/ledger/safeguards.jsonl         — safeguard cascades triggered
  kai/ledger/simulation-outcomes.jsonl — nightly sim results
  kai/ledger/reprogramming.jsonl      — nightly agent review notes
  agents/<name>/ledger/log.jsonl      — per-agent task history
  agents/<name>/reflection.jsonl      — per-agent self-reflection
  agents/<name>/PRIORITIES.md         — per-agent internal task queue
  agents/<name>/research/             — per-agent research findings
  KAI_BRIEF.md                        — session continuity state
  KAI_TASKS.md                        — priority queue

THREE-LAYER MEMORY (Felix pattern adapted):
  Layer 1 — Knowledge Graph:
    KAI_BRIEF.md, AGENT_ALGORITHMS.md, known-issues.jsonl
    Curated, essential, read every session
  Layer 2 — Daily Logs:
    ledger/log.jsonl (all agents), reflection.jsonl (per agent)
    Raw activity, appended daily
  Layer 3 — Tacit Knowledge:
    simulation-outcomes.jsonl, safeguards.jsonl, reprogramming.jsonl
    Extracted patterns, lessons from failures, optimization history

READ ORDER (every session start):
  1. KAI_BRIEF.md
  2. KAI_TASKS.md
  3. kai/ledger/known-issues.jsonl
  4. kai/ledger/simulation-outcomes.jsonl (last entry)
  5. kai/AGENT_ALGORITHMS.md
  6. Each agent's ACTIVE.md
  7. Each agent's PRIORITIES.md (if reviewing that agent)

WRITE ORDER (every session end):
  1. Update KAI_BRIEF.md
  2. Update KAI_TASKS.md
  3. Run nightly reprogramming cycle
  4. Ensure all ledger entries are committed
  5. dispatch health (final)
```

---

## Aether — Trading Intelligence Algorithm

```
STARTUP:
  1. Read agents/aether/PRIORITIES.md
  2. Read agents/aether/ledger/ACTIVE.md
  3. Check Monday reset (is it a new week? → archive lastWeek, reset currentWeek with balance carry)
  4. Load current metrics from website/data/aether-metrics.json

CYCLE (every 15 minutes via launchd):
  1. Check for new trade data (manual input via kai trade or API POST)
  2. Update running totals: PNL, win rate, trade count, daily breakdown
  3. Recalculate strategy performance table
  4. Push metrics to HQ (/api/aether?action=metrics)
  5. Write local state to website/data/aether-metrics.json
  6. dispatch report aether "cycle complete: $TRADE_COUNT trades, $PNL PNL"

TRADE RECORDING:
  1. Validate input JSON (pair, side, pnl, strategy required)
  2. Append to ledger/trades.jsonl
  3. Update currentWeek totals
  4. IF pnl < -$50 → dispatch flag aether P1 "significant loss: $pnl on $pair"
  5. IF drawdown > 5% → dispatch flag aether P0 "drawdown threshold breached"
  6. Push updated metrics to HQ

WEEKLY RESET (Monday 00:00 MT):
  1. Copy currentWeek → lastWeek (preserve for dashboard comparison)
  2. Reset currentWeek: zero PNL, zero trades, carry forward balance
  3. Archive previous week to ledger/weekly-archive.jsonl
  4. dispatch report aether "weekly reset: last week $PNL_TOTAL ($WIN_RATE% W/R)"

GPT FACT-CHECKING (Aether owns ALL OpenAI/GPT calls):
  1. Kai does NOT call GPT. Any external LLM verification routes through Aether.
  2. kai aether --fact-check "question" → standalone GPT query
  3. kai trade '{}' --verify → fact-checks trade before recording
  4. Aether annotates trades with GPT intelligence but never blocks them
  5. API key lives at agents/nel/security/openai.key (mode 600, gitignored)
  6. Model: gpt-4o-mini (cost-efficient for verification tasks)
  7. System prompt: trading fact-checker, concise, data-driven, confidence levels

FAILURE MODES:
  - API push fails → retry 3x, then dispatch flag P2 "HQ push failed"
  - Invalid trade JSON → reject, log to ledger, do not corrupt metrics
  - Monday reset missed → next cycle detects and runs it (idempotent check)
  - GPT API unavailable → log warning, skip fact-check, record trade normally
  - No OpenAI key → silent skip (fact-checking is advisory, not blocking)
```

---

## Dex — System Memory Manager Algorithm

```
STARTUP:
  1. Read agents/dex/PRIORITIES.md
  2. Read agents/dex/ledger/ACTIVE.md
  3. Enumerate all JSONL files: kai/ledger/*.jsonl + agents/*/ledger/log.jsonl

PHASE 1 — INTEGRITY (run first, always):
  1. For each .jsonl file:
     a. Read every line, validate JSON parse
     b. Check required fields: ts, type/action, agent
     c. Count corrupt/incomplete lines
  2. IF corrupt lines found → dispatch flag dex P1 "N corrupt entries in FILE"
  3. Report: total files, total entries, corrupt count

PHASE 2 — STALE TASKS:
  1. Scan all agents/*/ledger/ACTIVE.md files
  2. For each task: check last-updated timestamp
  3. IF task > 72h with no update → dispatch flag dex P2 "stale task: TASK_ID in AGENT"
  4. IF task > 7d → dispatch flag dex P1 "abandoned task: TASK_ID — needs close or re-delegate"

PHASE 3 — COMPACTION:
  1. For each log.jsonl with entries older than 30 days:
     a. Separate old entries → log-archive-YYYY-MM.jsonl
     b. Keep recent entries in log.jsonl
     c. Validate line counts: archived + remaining = original
  2. Report: entries archived, space saved, files touched

PHASE 4 — PATTERN DETECTION:
  1. Read kai/ledger/known-issues.jsonl (known failure patterns)
  2. Scan last 7 days of all log.jsonl entries
  3. For each known pattern → check if it recurred
  4. IF recurrence found → dispatch flag dex P1 "regression: PATTERN_ID recurred in AGENT"
  5. Look for NEW patterns: same error appearing 3+ times across agents

PHASE 5 — REPORT:
  1. Write summary to agents/dex/logs/dex-YYYY-MM-DD.md
  2. dispatch report dex "integrity: OK/WARN, stale: N, compacted: N, regressions: N"
  3. Update agents/dex/ledger/ACTIVE.md

PHASE 6 — ACTIVE RESEARCH (weekly, Monday run only):
  Dex is not a passive librarian. Dex actively researches how to do its job better.
  1. Read agents/ra/research/briefs/dex-*.md (latest research brief from Ra)
  2. Compare current methods against brief findings:
     - Is there a better JSONL validation approach?
     - Are there compaction algorithms we should adopt?
     - Has the JSONL schema standard evolved?
     - How are other agentic systems handling audit trails?
  3. IF applicable improvement found:
     a. Log to agents/dex/ledger/log.jsonl with type: "research-finding"
     b. Create [RESEARCH] task in KAI_TASKS.md
     c. Write brief to agents/dex/logs/research-YYYY-WNN.md
  4. Anti-stale check (self-monitor):
     - Check all agents' research brief dates
     - IF any agent brief > 14d old → dispatch flag dex P2 "agent research stale: AGENT"
     - IF any agent has no [RESEARCH] finding in 30d → dispatch flag dex P1

SCHEDULE: Daily at 23:00 MT (before nightly simulation at 23:30)
  → Dex validates data integrity BEFORE simulation reads it
  → Simulation results feed back into ledger for next day's pattern check
  → Phase 6 only runs on Mondays (weekly research cycle)

FAILURE MODES:
  - Corrupt JSONL → quarantine line to .corrupt file, do not delete
  - Compaction mismatch → abort, flag P0 "compaction integrity failure"
  - Pattern match false positive → log but don't auto-escalate above P2
  - Research brief missing → skip Phase 6, flag P3 "no brief available"
```
