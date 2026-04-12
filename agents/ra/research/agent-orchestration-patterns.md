# Agent Orchestration Patterns: Research Report

**Date:** 2026-04-12  
**Scope:** Felix (Nat Eliason), OpenAI Agents SDK, Claude Agent SDK

---

## Executive Summary

Three systems demonstrate complementary approaches to multi-agent orchestration. **Nat Eliason's Felix** emphasizes nightly consolidation and persistent memory across runs. **OpenAI's Agents SDK** uses explicit handoffs with full conversation carryover. **Claude's Agent SDK** isolates subagent context while managing parallel execution and memory scopes. Key pattern: **closed-loop requires delegation structures, memory ledgers, and explicit reporting**.

---

## 1. Nat Eliason's Felix (OpenClaw)

### Delegation Structure
- **Hierarchy:** Felix (CEO agent) → Iris (support) and Remy (sales) sub-agents
- **Dispatch:** Nightly reprogramming cycle. Felix reviews sub-agent work output and optimizes their instructions the next day.
- **Interface:** Discord-based human visibility; Nat sends voice notes to Felix for dispatch.

### Memory & Ledger System
Three-layer memory architecture:
1. **Layer 1 (Knowledge Graph):** PARA system (Projects, Areas, Resources, Archives) stored in `~/life/` folder with durable facts and quick-lookup summary files.
2. **Layer 2 (Daily Notes):** Dated markdown per day; agents write observations into daily log during conversations.
3. **Layer 3 (Tacit Knowledge):** Extracted patterns, communication preferences, hard rules, lessons from past failures.

**Consolidation:** Nightly batch process extracts important facts from daily notes into Layer 1 knowledge graph. This prevents memory bottleneck and ensures agents start fresh each day with curated, essential context.

### Closed-Loop Mechanism
- **Reporting:** Sub-agents log activity to daily notes; Nat reviews via Slack summaries.
- **ACK Cycle:** Nightly reprogramming acknowledges sub-agent work and updates instructions.
- **Cost:** ~$400/month for operations; total revenue ~$177K+ in weeks.

**Adoptable Pattern:** Nightly consolidation (not continuous) reduces token waste while forcing pattern recognition. Daily logs → knowledge graph migration works.

---

## 2. OpenAI Agents SDK

### Delegation Structure
- **Primitives:** Three core concepts: Handoffs (explicit agent-to-agent transfer), Guardrails (input/output validation), Tracing (end-to-end observability).
- **Orchestration Model:** Triage agent receives input, determines intent, hands off to specialized agent (billing, support, technical, accounts).
- **Explicit Transfer:** Control passes explicitly with full conversation history visible to next agent.

### Memory & Context Management
- **Session-Based:** `RunContextWrapper` provides persistent state objects across runs (memory, notes, preferences evolve).
- **Handoff Carryover:** When `nest_handoff_history` is enabled, prior transcript collapses into assistant summary wrapped in `<CONVERSATION_HISTORY>` block. New turns append automatically.
- **Context Trimming:** Drop older turns, keep last N.
- **Context Summarization:** Compress prior messages into structured summaries injected into conversation.

### Closed-Loop Mechanism
- **Handoff Guarantee:** Control transfer is explicit and complete. Agent sees entire prior conversation.
- **Filtering:** `input_filter` on handoff allows next agent to receive curated input.
- **Tracing:** Built-in observability ensures you can audit full delegation chain.

**Adoptable Pattern:** Explicit handoffs with full context carryover work well for triage-and-delegate workflows. Conversation history is the ledger.

---

## 3. Claude Agent SDK

### Delegation Structure
- **Tool-Based:** Subagents invoked via Agent tool. Parent determines when to delegate based on subagent `description`.
- **Automatic Matching:** Claude matches task intent to subagent description; can also be explicitly named in prompt.
- **Fresh Context:** Each subagent runs in isolated conversation (no parent history in context).
- **No Recursion:** Subagents cannot spawn subagents; prevents nesting depth explosion.

### Memory & Ledger System
- **Three Scopes:** Persistent memory directories at `user` (cross-project), `project` (version-controlled), or `local` (gitignored).
- **Memory Interface:** Subagent system prompt includes first 200 lines of `MEMORY.md` file in memory directory; instructions to curate if larger.
- **Context Isolation:** Only final subagent message returns to parent; intermediate tool calls stay isolated. Dramatically preserves parent context.
- **Parallel Execution:** Multiple subagents can run concurrently, reducing review time from minutes to seconds.

### Closed-Loop Mechanism
- **Reporting:** Parent receives final message verbatim as Agent tool result. Intermediate noise stays isolated.
- **ACK Pattern:** Parent can ask subagent to update memory after task completion: "Save what you learned to your memory."
- **Task Descriptions:** Clear descriptions are the "interface" — they tell Claude *when* to delegate, making routing automatic.

**Adoptable Pattern:** Context isolation + persistent memory directories create a clean separation between exploration (subagent) and integration (parent). Ideal for research, analysis, and multi-step workflows. Memory curation must be explicit.

---

## Comparative Analysis

| Dimension | Felix (OpenClaw) | OpenAI SDK | Claude SDK |
|-----------|------------------|-----------|-----------|
| **Delegation Trigger** | Nightly review + manual voice notes | Handoff (explicit) | Task description (implicit) |
| **Memory Strategy** | Three-layer consolidation + daily logs | Session state + handoff history | Persistent memory dirs + MEMORY.md |
| **Context Carryover** | Fresh start each day; layer access | Full conversation history on handoff | Isolated (only final message) |
| **Parallelization** | Sequential (nightly) | Sequential handoffs | Parallel subagents |
| **Interface for Human** | Discord + Slack summaries | Tracing/observability | Task descriptions + results |
| **Closed-Loop** | Nightly ACK + reprogramming | Explicit handoff guarantee | Memory updates + parent review |

---

## Practical Patterns for Hyo

### Recommended Hybrid Approach

1. **Adopt Claude SDK's memory scopes** (`project`, `user`, `local`) for persistent knowledge across sessions.
2. **Use explicit reporting** (like OpenAI's tracing): Every agent task returns a summary; parent audits summaries.
3. **Implement daily/nightly consolidation** (Felix pattern): Extract key decisions and patterns into a shared ledger (e.g., `agents/kai/ledger/known-issues.jsonl`, `simulation-outcomes.jsonl`).
4. **Keep context isolation**: Subagents explore; parent integrates. Don't pass full histories unless needed.
5. **Task descriptions as delegation interface**: Write clear agent descriptions so automation matches tasks to the right worker.

### Ledger Systems to Implement
- **Execution ledger:** Every agent task → date, agent, input, output, duration, cost.
- **Issue patterns:** Known regressions, failure modes (Nel scans for these).
- **Simulation outcomes:** Nightly validation of full delegation chain.
- **Memory consolidation:** Rules for when to migrate daily logs to persistent knowledge.

### Closed-Loop Protocol (from rules)
Every delegation:
- **Request:** Task + context
- **Execution:** Agent works in isolated context
- **Report:** Final output + any decisions
- **ACK:** Parent confirms receipt, integrates or rejects
- **Log:** Outcome recorded in ledger

---

## Sources

- [Felix Craft — How to Hire an AI](https://felixcraft.ai/)
- [Nat Eliason on Building a Million Dollar Zero Human Company](https://www.bankless.com/podcast/building-a-million-dollar-zero-human-company-with-openclaw-nat-eliason)
- [Full Tutorial: Use OpenClaw to Build a Business That Runs Itself](https://creatoreconomy.so/p/use-openclaw-to-build-a-business-that-runs-itself-nat-eliason)
- [OpenAI Agents SDK Documentation](https://openai.github.io/openai-agents-python/)
- [Context Engineering - OpenAI Agents SDK](https://developers.openai.com/cookbook/examples/agents_sdk/session_memory)
- [Claude Agent SDK - Subagents](https://code.claude.com/docs/en/agent-sdk/subagents)
- [Claude Code - Create Custom Subagents](https://code.claude.com/docs/en/sub-agents)
