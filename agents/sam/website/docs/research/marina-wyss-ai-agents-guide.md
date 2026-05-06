# Marina Wyss — AI Agents Complete Course: Applied Analysis
**Author:** Kai (CEO, hyo.world)  
**Date:** 2026-05-05 (updated with full transcript)  
**Source:** Marina Wyss, Senior Applied Scientist at Amazon (Gen AI) — "AI Agents in 38 Minutes - Complete Course from Beginner to Pro," YouTube Dec 9, 2025 (145K views, 4.2K likes)  
**Classification:** Lab — Agent Architecture  
**Transcript:** Obtained via `youtube_transcript_api` — 1,247 segments, full 38-minute coverage

---

## What We Researched

Marina's course was initially inaccessible (egress proxy blocked all relevant domains). The transcript was obtained by running `youtube_transcript_api` directly on the Mini. All quotes below are verbatim from the transcript. This document reads the course as a diagnostic against the Hyo system: where does our implementation match what Marina teaches, where does it diverge, and what does that divergence cost us?

Marina prepared 150 pages of research notes before recording this video, distilled from courses, books, and her own agents built in production. The course covers basics (what agents are, spectrum of autonomy, context engineering, task decomposition) → intermediate (evaluation, memory, guardrails, reflection, tool use, planning, multi-agent) → advanced (task decomposition patterns, latency/cost/observability, security). Each section maps directly to things we've built — some correctly, some with documented gaps.

---

## Finding 1: Context Engineering Is the Foundation — And We Don't Do It

Marina introduces context engineering at 6:45 as the most important concept for making agents work: "Context engineering is when you decide what information the agent has. This includes things like the background of the task, the agent's role, memory of past actions, and available tools... It's not the model alone, it's how you engineer the context around it. That's the practical foundation of intelligence in agents."

The principle: context steers non-deterministic models toward consistent, high-quality outputs. Without deliberate context engineering, every agent call is a lottery.

**Applied to Hyo:** `agent-execute-improvement.sh` sends a Claude API call with: a ticket description, the improvement prompt, and nothing else. No PLAYBOOK.md. No ACTIVE.md. No evolution history. No GROWTH.md weaknesses. No list of what was tried last cycle. The agent receives minimal context and then makes decisions about how to improve the system. This is context engineering failure — the exact failure Marina describes.

The practical consequence: improvement tickets are attempted without the agent knowing (a) its own known failure modes, (b) what was tried before, (c) what the protocol constraints are, or (d) what tools and files are relevant. Every cycle starts cold. This explains why improvement cycles retry the same approaches even after failure — the agent isn't being told what failed.

**What this requires:** Before every improvement API call, inject: the agent's PLAYBOOK.md (its own protocol), the relevant ACTIVE.md section (current state), and the last 3 evolution.jsonl entries (what was recently attempted). This is context engineering. The agent needs its role, its history, and its constraints — not just the task.

---

## Finding 2: Task Decomposition Is "The Most Important Thing" — Ours Is at the Wrong Granularity

Marina at 7:13: "Figuring out these tasks is arguably the most important thing you'll learn about building agents. Start with how you'd do the task. Then, for each step, ask, 'Can an LLM do this?' If the answer is no, split it smaller until it is... Each step is small, checkable, and clear. When the output isn't good enough, you know exactly what step to improve."

She then describes what her agent would actually do for an essay: outline → search term generation → web search → page fetch → draft → self-critique → revise. Each step is independently auditable. Each step has one job.

**Applied to Hyo:** Our agent runners are the opposite. `ra.sh` runs `run_growth_phase` which calls `execute_next_improvement` which calls `agent-execute-improvement.sh` which makes a Claude API call that does: research a weakness, find relevant sources, implement a fix, write tests, commit code — all in one 60-second inference call. That's six distinct steps collapsed into one. When it fails, the exit code is the only diagnostic. There's no intermediate observation point.

Marina's diagnostic principle: "When the output isn't good enough, you know exactly what step to improve." With our current setup, when improvement execution fails, we know the entire block failed. We don't know which sub-step — research, implementation, or verification — was the actual failure. This makes debugging impossible and is why the same improvement tickets fail repeatedly: we don't know what specifically went wrong.

**Advanced decomposition patterns Marina covers (26:14):** functional (by domain), spatial (by file/directory), temporal (sequential stages where each depends on the prior), and data-driven (by data partition). The temporal pattern is most relevant to our improvement pipeline: research must complete before implementation can start, and verification must complete before the ticket resolves. These should be three separate queue jobs, not one monolithic call with a 60-second timeout.

---

## Finding 3: The Tool Interface Must Be Separated From Implementation — Ours Is Not

Marina at 15:51: "Every tool has two parts: the interface for the agent — this includes a tool name, a plain English description of when to use it, and a typed input schema... And the implementation code, whatever you need like SQL queries, auth, retries, throttling, and parsing. The agent only sees the interface. All of the messy implementation details are hidden."

She adds: "Tools should be built like products with versioning, proper documentation, and sufficient tests. It's useful to maintain an internal registry of vetted tools with docs, versions, and ownership."

**Applied to Hyo:** Our agent tools are shell commands available in `$PATH`. The "interface" is whatever the tool's `--help` output says. There is no registry. There is no typed schema. When an agent calls `kai push sam "message"`, it receives whatever `kai.sh` sends back, which is either success or an unstructured error string. The agent cannot distinguish "pushed successfully" from "HYO_HQ_PASSWORD not set — skipping verification." Both are exit code 0.

Marina's specific requirement for good tools: "Good tools also consider things like error handling, self-recovery, and rate limiting... And they should have async support so the agent or other agents can keep working while long tool requests complete." Our tools are synchronous, have no retry logic, and return unstructured stdout that agents cannot reliably parse.

The `tools.json` registry was identified as a gap in the prior version of this document. Marina's course confirms it's not optional — it's the mechanism by which agents know what tools exist, when to use them, and how to interpret their outputs. Without it, agents are guessing at tool behavior from unstructured help text.

---

## Finding 4: Memory vs. Knowledge — We're Using Them Interchangeably

Marina at 10:39: "Memory is dynamic and is updated on each run. Knowledge, on the other hand, is static. This is reference material that you load up front, things like PDFs, CSVs, or documentation... You give it to the agent once and it can pull from that library whenever it needs to cite something accurately."

The distinction is architectural: memory changes with each execution cycle and represents what the agent learned from running; knowledge is the fixed reference layer that the agent reads but doesn't write.

**Applied to Hyo:** KNOWLEDGE.md is being used as both. The nightly `consolidate.sh` writes new facts into KNOWLEDGE.md from daily notes. TACIT.md is updated when Hyo gives feedback. This means our "static knowledge layer" changes every night. Agents reading KNOWLEDGE.md at session start are reading a document that was different yesterday and will be different tomorrow.

Marina's architecture implies these should be separate: the agent's procedural knowledge (how to do things — PLAYBOOK.md) is static and loaded once; the agent's episodic memory (what happened recently — ACTIVE.md, evolution.jsonl) is dynamic and loaded fresh each run. The nightly consolidation promotes episodic to semantic — which is correct — but KNOWLEDGE.md should be treated as a read-only reference during execution, not a file that grows dynamically mid-cycle.

The practical consequence: an agent running at 02:00 MT reads a KNOWLEDGE.md from yesterday's consolidation. An agent running at 01:10 MT reads a KNOWLEDGE.md from the day before. The "static knowledge layer" has different content depending on when the agent runs. This undermines the consistency that Marina says the knowledge layer is supposed to provide.

---

## Finding 5: "Define Interfaces, Not Vibes" — Our Agent Handoffs Are Vibes

Marina at 23:44 on multi-agent best practices: "Define interfaces, not vibes. Each agent needs a clear schema for inputs and outputs. It needs to know things like what fields, what types, what IDs or references get passed along. Handoffs break more often than your models do. If your researcher returns an unstructured blob and your designer doesn't know how to parse it, the whole system's going to fail."

And at 19:35, on why to avoid multi-agent systems for simple tasks: "Multi-agent systems introduce a whole new layer of complexity... resource conflicts if two agents try to modify the same file. There's communication overhead between agents and complex task dependencies."

**Applied to Hyo:** The `dispatch report` mechanism is supposed to close the loop between agents and Kai. When Ra runs, it's supposed to produce a structured report that Kai can read and act on. What actually happens: Ra appends to a markdown file using heredoc syntax, the queue worker marks the job complete, and Kai reads whatever markdown happened to accumulate. There is no schema. There is no required fields list. There is no type validation. The "report" format varies depending on what phase Ra got to before the timeout killed the process.

The 60 `claude-delegate-failed-*.txt` artifacts are the concrete evidence of this failure: each file is a failed delegation with no defined recovery schema. Kai doesn't know whether the failure was in the delegation itself, the agent runner, the tool call, or the output formatting. Without a defined interface, the failure is opaque.

Marina's second pitfall from 23:09: redundant work. "Multiple agents may redo the same searches or call the same tools." Our PHASE 1 staleness self-heal in `kai-autonomous.sh` can queue the same agent 96+ times per day because there's no coordination layer checking whether a job for that agent is already queued or running. This is the coordination failure Marina describes, caused by not having clear interface contracts.

---

## Finding 6: Observability Requires Logging WHY, Not Just WHAT

Marina at 34:00: "You'll want to log not only what an agent did, but why it did it. For example, you might log things like 'agent chose to use web search instead of RAG because query contained recent' or 'reflection pass identified three issues: missing citation, vague date, or wrong tone.'"

She distinguishes zoom-in and zoom-out metrics. Zoom-in: "your full trace — prompts, tool calls, token usage, retry attempts, and every decision point. Basically, everything required to reproduce an error and see exactly where it went wrong." Zoom-out: "automated quality checks, often with an LLM judge, hallucination rates, success and ROI measures, and trend lines that show whether changes are helping or hurting."

**Applied to Hyo:** Our logs record outputs, not reasoning. `agents/ra/logs/ra-2026-05-05.md` records what Ra produced — research files, ticket counts, LLM outputs — but not why Ra chose to research a particular topic, which tool it selected and why, or what it observed that led to the next step. When Ra dead-loops, the log shows repeated identical outputs but doesn't show the reasoning chain that caused the repetition. This makes post-mortems impossible beyond "something ran repeatedly."

Marina's user behavior observability (35:02) is also missing: "Are they using your agent as you intended or have they found creative workarounds? Where do they get stuck? Do they rephrase and retry? That's a signal the first attempt didn't work." For Hyo, the equivalent would be: when Hyo sends a correction via `hyo-inbox.jsonl`, does Kai track whether the same correction recurs in future sessions? Recurring corrections are the "rephrase and retry" signal. We don't track this.

---

## Finding 7: Security — Our Agent Has Unrestricted File System Access

Marina at 35:10: "You're not just protecting against external attackers. You actually have to protect against your own system making dangerous decisions or being manipulated into harmful actions." The four threats: prompt injection, unsafe code generation, data leakage, and resource exhaustion.

On code execution (35:46): "Sandbox execution. Use Docker or a restricted runner environment. Isolate code execution completely from your main application. Resource limits. Set timeouts, memory caps, CPU limits. Block dangerous imports, network access unless explicitly needed, and file system writes outside of a designated temp directory. Whitelist libraries only."

**Applied to Hyo:** `agent-execute-improvement.sh` executes code in the Hyo project directory with full user permissions. There is no sandbox. There are no memory caps. File system writes are unrestricted. An improvement ticket that says "implement X" results in Claude-generated code executing in `~/Documents/Projects/Hyo` with read/write access to every file in the project. The prompt injection risk Marina names is real: a malicious pattern in a research file that an agent reads and then acts on could cause arbitrary code execution with no guardrail.

The resource exhaustion threat is what caused the 151GB disk fill. Ra ran improvement cycles that appended to a log file without a size check. Marina's guardrail: "Set timeouts, memory caps." We added a disk gate in `kai-autonomous.sh` after the incident. Marina's framing: this is a security control, not just an operations fix. The gate should be designed with the same rigor as injection protection.

---

## What Marina Rejected (and Why It Applies)

Marina on evaluating early: "It's important that you start evaluating right away, but also that you don't worry about having a perfect evaluation system from the get-go. You can get something working quickly and iterate over time." This is the opposite of our current approach — we have an elaborate SICQ/OMP scoring system built before we verified the scores correlate with actual quality. The prior skepticism brief (kai-skepticism-2026-04-28.md) documented this gap. Marina's advice is the correct sequence: evaluation first, refinement second.

On reflection: "The drawback is that it adds latency and cost because you're doing multiple passes. So, make sure to test with and without reflection to ensure it's actually helping." We added the adversarial verifier (aric-verifier.py) without establishing a baseline. We don't know if it improves output quality because we never measured quality before adding it.

On multi-agent complexity: "If you have a simple task, skip multi-agent systems. They can slow things down and make debugging more difficult." Five agents (Ra, Nel, Sam, Aether, Dex) was the right call for specialization. But within each agent's runner, the multi-step improvement pipeline is itself a mini multi-agent system (research → implement → verify) with no inter-step contracts. Marina's warning about simple tasks applies to our improvement sub-system: it's not simple enough to run as a single undivided task.

---

## Seven Implementation Changes From the Actual Transcript

**Change 1: Context injection into improvement execution** (Finding 1)  
Before every `agent-execute-improvement.sh` call: inject the agent's PLAYBOOK.md + last 3 evolution.jsonl entries + ACTIVE.md current state. The agent needs its role, history, and constraints — not just the ticket.

**Change 2: Split improvement into 3 queue jobs** (Finding 2)  
Phase A: research (produce a research file). Phase B: implement (read research file, write code). Phase C: verify (run the test, confirm). Each is a separate queue job. Each has a timeout. Phase B only starts if Phase A produced output. This replaces the current 60-second monolithic call.

**Change 3: tools.json registry** (Finding 3)  
Document every callable tool with: name, description, typed input schema, expected output format, error codes. Agents load the registry before deciding what to call. This is what Marina means by "interface."

**Change 4: Separate static knowledge from dynamic memory** (Finding 4)  
KNOWLEDGE.md becomes read-only during agent execution. Nightly promotion from episodic → semantic still happens, but agents flag reads of KNOWLEDGE.md with a staleness check. If the last consolidation was >36h ago, log a warning.

**Change 5: Structured dispatch report schema** (Finding 5)  
Define a required JSON schema for all agent reports: `{agent, cycle_id, phases_completed, outputs_written, errors, next_cycle_intent}`. Reports that don't conform to the schema are treated as failures, not successes. Queue worker validates schema before marking complete.

**Change 6: WHY logging in every agent runner** (Finding 6)  
After every tool selection, log: which tool was chosen and why (one sentence). After every LLM call, log: what the model was asked to decide, what it decided. This is what makes post-mortems possible.

**Change 7: Code execution sandbox** (Finding 7)  
`agent-execute-improvement.sh` runs in a restricted environment: no writes outside `agents/<name>/` directory, no network calls, 30s timeout for code execution. Implementation: `firejail` or `sandbox-exec` wrapper around the Python subprocess. This is not optional given that agents have write access to the production codebase.

---

## Sources

1. Marina Wyss, "AI Agents in 38 Minutes - Complete Course from Beginner to Pro" — [YouTube, Dec 9, 2025](https://www.youtube.com/watch?v=sNvuH-iTi4c). Full transcript obtained 2026-05-05.
2. Kai Research Brief: Self-Evolving Agent Systems (kai-self-improve-2026-04-28.md) — ReAct, event-triggered improvement, double-loop review.
3. Kai Research Brief: Skepticism on Self-Improving Agent Systems (kai-skepticism-2026-04-28.md) — SICQ as Goodhart's Law proxy, sycophancy at 58%, specification gaming.
4. Hyo Project Overview (docs/legacy/core-original-design/Hyo_01_Overview.md) — agent economy framing and trust layer positioning.

---

*Research conducted 2026-05-05. Full transcript obtained. Seven implementation changes identified. Prior version disclosed access limitation — this version is sourced from verified transcript content. Protocol: docs/AGENT_CREATION_PROTOCOL.md v4.0.*
