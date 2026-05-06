# Marina Wyss — AI Agents: Complete Course Guide
## Step-by-Step Reference for Building Production Agent Systems

**Source:** Marina Wyss, Senior Applied Scientist at Amazon (Gen AI)  
**Video:** "AI Agents in 38 Minutes — Complete Course from Beginner to Pro" (YouTube, Dec 9, 2025)  
**Transcript:** Full 38-minute coverage, 1,247 segments, obtained via youtube_transcript_api  
**Compiled:** 2026-05-05 by Kai (CEO, hyo.world)  
**Purpose:** Permanent reference guide — course content distilled into actionable outlines  

**Related Documents:**  
- Agent Economy Blueprint: `docs/legacy/core-original-design/Hyo_01_Overview.md`  
- Zero to Autonomous Blueprint: `kai/research/raw/2026-04-23-autonomous-company-research.md`  
- Aurora Economics (Agent Cost Model): `docs/aurora-economics.md`  

---

> Marina prepared 150 pages of research notes before recording this course, distilled from production experience building agents at Amazon and from books, papers, and deployed systems. This guide distills the course into permanent reference chapters with step-by-step outlines you can use to build, evaluate, and improve any agent system.

---

## Table of Contents

1. What Is an AI Agent?
2. The Autonomy Spectrum
3. Context Engineering — The Foundation of Agent Intelligence
4. Task Decomposition — The Most Important Skill
5. Tool Use — Interface vs. Implementation
6. Memory and Knowledge — Architecture and Separation
7. Reflection and Self-Critique
8. Guardrails — Keeping Agents Safe
9. Evaluation — Measuring Agent Quality
10. Planning — Multi-Step Execution
11. Multi-Agent Systems — Orchestrators and Subagents
12. Advanced Task Decomposition Patterns
13. Latency, Cost, and Production Tradeoffs
14. Observability — Logging WHY, Not Just WHAT
15. Security — Prompt Injection, Code Execution, Data Leakage
16. Connection to the Agent Economy

---

## Chapter 1: What Is an AI Agent?

### Marina's Definition (0:00–1:30)

An AI agent is a system that uses a language model to make decisions and take actions in order to complete a goal — often one that requires multiple steps and involves the external world.

The key distinction from a chatbot:

| Chatbot | Agent |
|---------|-------|
| Responds once per input | Takes sequences of actions |
| Reads only what you give it | Reaches out to external tools, APIs, files |
| Has no memory between turns (usually) | Maintains state across steps |
| Cannot change the world | Can write files, send emails, run code |

### Step-by-Step: How an Agent Works

1. **Receive a goal.** The goal is given as a prompt — either from a human or another system.
2. **Reason about what's needed.** The LLM generates a plan or next action based on the goal and all available context.
3. **Select a tool or action.** The model chooses from available tools (web search, calculator, code runner, file reader, etc.).
4. **Execute the action.** The tool runs and returns an observation.
5. **Incorporate the observation.** The result is added to the agent's context.
6. **Repeat.** Steps 2–5 repeat until the goal is complete or a stopping condition is met.
7. **Return the result.** The agent produces a final output and stops.

This loop is called the **ReAct loop**: Reason → Act → Observe → Reason again.

### Why Agents Fail at Step 1

Most agent failures happen at goal specification. If the goal is ambiguous, the agent will drift. Marina's principle: **specify success criteria, not just the task.** Instead of "research competitors," say "produce a table of 5 competitors with name, pricing, and differentiator — verified against their public website as of today."

---

## Chapter 2: The Autonomy Spectrum

### Marina's Framework (1:30–4:00)

Marina places agents on a spectrum from fully human-controlled to fully autonomous:

```
FULLY CONTROLLED                                    FULLY AUTONOMOUS
      |                                                      |
  Single LLM        Fixed Pipeline      Human-in-Loop      Agent with
   call (no          (predefined         (approvals at       full autonomy
   actions)          steps, no           key gates)          (acts alone)
                     branching)
```

**Fixed pipelines** (left side): You define every step. The LLM fills in slots. Good for predictable, well-understood workflows.

**Semi-autonomous** (middle): The agent plans and executes, but a human approves at key decision points. Good for high-stakes work where errors are costly.

**Fully autonomous** (right side): The agent decides, acts, and corrects without human approval loops. Good for well-defined tasks with reversible actions and strong evaluation.

### Step-by-Step: Choosing Your Autonomy Level

1. **Define the cost of failure.** Can an error be undone cheaply? If yes, lean autonomous. If no, add human gates.
2. **Identify irreversible actions.** Any action that can't be undone (send email, delete file, charge a card) requires human approval at minimum.
3. **Estimate task complexity.** Simple tasks with well-defined outputs → automate fully. Complex tasks with many decision branches → add reflection loops and human checkpoints.
4. **Start conservative.** Begin with human-in-loop, verify the agent's decisions are correct, then remove gates one at a time as confidence grows.
5. **Never remove all gates at once.** Production autonomy is earned step by step, not granted upfront.

### The Devin Pattern (Marina's Reference)

Marina cites the Devin coding agent pattern as best practice: the agent creates a **Game Plan** (list of steps with success criteria) → human reviews the Game Plan → agent executes. The human reviews PLAN, not outputs. Catching misalignment at the plan level costs nothing; catching it at the output level costs the full execution.

---

## Chapter 3: Context Engineering — The Foundation of Agent Intelligence

### Marina's Definition (6:45–9:00)

> "Context engineering is when you decide what information the agent has. This includes things like the background of the task, the agent's role, memory of past actions, and available tools... It's not the model alone, it's how you engineer the context around it. That's the practical foundation of intelligence in agents."

Context engineering is the highest-leverage skill in building agents. The model is fixed — you cannot change it. The context is yours to control. Everything the agent knows, believes, and can do comes from the context you construct.

### What Goes Into Context

Marina identifies these context components:

1. **System prompt / role:** Who is the agent? What are its responsibilities? What are its constraints?
2. **Task / goal:** What is being asked right now?
3. **Memory of past actions:** What has the agent already done in this session or previous sessions?
4. **Available tools:** What can the agent call? (Names, descriptions, input schemas)
5. **Relevant knowledge:** Background information the agent needs to complete the task accurately
6. **Examples:** Few-shot examples of good outputs or decisions
7. **Constraints:** What the agent must never do (safety rails, format requirements, cost limits)

### Step-by-Step: Building Good Context

1. **Start with the role.** Write 2–4 sentences describing who the agent is, what domain it operates in, and what its output looks like when successful.
2. **Inject the task.** Pass the specific goal with success criteria. "Success = X, not just Y."
3. **Add relevant memory.** Before the API call, load the last N actions from the session log. For improvement agents: load the last 3 attempts and what each one tried.
4. **List available tools.** Every tool needs: name, one-sentence description of when to use it, expected input types, expected output format.
5. **Add domain knowledge.** Static reference material: protocols, schemas, known failure modes. This is knowledge (static), not memory (dynamic).
6. **Add examples.** If you have 2–3 examples of ideal agent behavior, include them. Few-shot examples are often the single highest-leverage addition.
7. **State constraints explicitly.** "Never write to files outside /agents/{name}/. Never call external APIs without logging the call first."
8. **Test with and without each component.** Remove one piece of context at a time and see what breaks. This tells you exactly what each component is contributing.

### The Context Budget Problem

LLMs have limited context windows. With a large system prompt + task + memory + tools + knowledge, you can burn 30,000 tokens before the agent does any work. Marina's solutions:

- **Selective injection:** Don't load all memory — load only the relevant slices (last N entries, matching the current task type).
- **Summarization:** Compress old memory into summaries. Keep recent memory verbatim.
- **Tool registry instead of inline docs:** Reference a tool name and let the agent look up its schema, rather than inlining all schemas into every prompt.
- **Hierarchical context:** Load light context first. If the agent needs more, it requests it via a tool call.

---

## Chapter 4: Task Decomposition — The Most Important Skill

### Marina's Principle (7:13–10:00)

> "Figuring out these tasks is arguably the most important thing you'll learn about building agents. Start with how you'd do the task. Then, for each step, ask, 'Can an LLM do this?' If the answer is no, split it smaller until it is... Each step is small, checkable, and clear. When the output isn't good enough, you know exactly what step to improve."

### The Core Rule

If you cannot identify which step failed when the agent fails, your decomposition is wrong. Each step must be independently observable and independently improvable.

### Marina's Essay Example

Marina walks through decomposing "write a research essay" into atomic steps:

1. Generate an outline (LLM can do this)
2. Generate search terms for each section (LLM can do this)
3. Run web searches (tool call — deterministic)
4. Fetch and parse the relevant pages (tool call)
5. Draft each section based on the search results (LLM can do this)
6. Self-critique the draft: Is it accurate? Cited? Appropriately long? (LLM can do this)
7. Revise based on the critique (LLM can do this)
8. Format and finalize (LLM or template)

**Each step has one job. Each step's output feeds the next step. Each step is independently auditable.**

### Step-by-Step: Decomposing Any Task

1. **Write out how YOU would do the task.** Step by step, the way a smart human would. Don't think about LLMs yet.
2. **For each step, ask:** "Is this one clear thing? Can I tell in 30 seconds whether it succeeded?"
3. **For each step, ask:** "Can an LLM reliably do this, or does it require deterministic logic?"
   - LLM-suitable: generate, summarize, classify, draft, evaluate, critique
   - Tool-suitable: search, fetch, calculate, write file, call API, run test
4. **Split any step that is more than one thing.** "Research and summarize" = two steps.
5. **Split any step where failure is opaque.** If you can't tell which sub-task failed, split further.
6. **Define success criteria for each step.** Not "did it run" but "did it produce output X in format Y."
7. **Map dependencies.** Which steps must complete before others can start? Sequential dependencies = separate queue jobs.
8. **Set a timeout for each step.** A step that runs forever is not a step — it's a runaway process.

### The Monolith Problem

Marina's warning: collapsing multiple steps into one LLM call produces output that's impossible to debug. When the monolith fails, you don't know if research failed, if implementation failed, or if verification failed. You only know the whole thing is wrong.

The fix is not just decomposition — it's **temporal decomposition**: research must complete before implementation can start, and verification must complete before the ticket resolves. These are three separate queue jobs, each with its own timeout and success criteria.

---

## Chapter 5: Tool Use — Interface vs. Implementation

### Marina's Architecture (15:51–19:00)

> "Every tool has two parts: the interface for the agent — this includes a tool name, a plain English description of when to use it, and a typed input schema... And the implementation code, whatever you need like SQL queries, auth, retries, throttling, and parsing. The agent only sees the interface. All of the messy implementation details are hidden."

### The Two-Part Tool Contract

**Part 1: The Interface (what the agent sees)**
- Name: short, descriptive, unique
- Description: plain English, when to use this tool (not just what it does)
- Input schema: typed fields, required vs. optional, constraints
- Output format: what the agent can expect back (structure, types, possible errors)

**Part 2: The Implementation (hidden from the agent)**
- SQL queries, API calls, file I/O
- Authentication and credential handling
- Retry logic, rate limiting, throttling
- Error normalization (all errors return the same structure so the agent can parse them)
- Response parsing and formatting

### Step-by-Step: Building a Good Tool

1. **Name it for when to call it, not what it does.** `search_recent_news` not `query_api`.
2. **Write the description as a decision rule.** "Use this when you need information about events that happened in the last 7 days. Do not use for historical research."
3. **Define the input schema strictly.** Every field typed. Required fields marked. Include constraints ("query must be under 200 characters").
4. **Define the output schema.** What does a success look like? What does an error look like? Use the same structure for both so the agent can always parse the response.
5. **Handle every error internally.** The agent should never receive a raw stack trace. Catch exceptions, normalize to: `{success: false, error: "RATE_LIMITED", message: "...", retry_after: 5}`.
6. **Add async support.** For long-running tools, return immediately with a job ID. The agent polls for completion. This keeps the agent loop responsive.
7. **Build a tool registry.** Document every tool with name, description, schema, error codes, version, and owner. Agents load the registry before deciding what to call.
8. **Test tools in isolation.** Before wiring into an agent, call each tool with valid inputs, invalid inputs, and edge cases. Verify outputs match the documented schema.

### Marina's Tool Registry Standard

Marina is explicit: tools should be built and maintained like products, with:
- Versioning (when the interface changes, bump the version)
- Proper documentation (the registry IS the documentation)
- Tests (the tool is not trusted until it has test coverage)
- Ownership (someone is responsible for each tool)

> "It's useful to maintain an internal registry of vetted tools with docs, versions, and ownership."

---

## Chapter 6: Memory and Knowledge — Architecture and Separation

### Marina's Taxonomy (10:39–15:00)

Marina distinguishes four types of memory, each with different storage and update characteristics:

| Type | What It Is | How It's Stored | When It Updates |
|------|-----------|----------------|-----------------|
| **In-context** | Everything in the current prompt window | Model's active context | Per prompt |
| **External / Episodic** | Records of past actions and events | Files, databases, vector stores | After each action |
| **Semantic / Long-term** | Distilled facts and knowledge | Knowledge base, embeddings | After consolidation |
| **Procedural** | How to do things (skills, protocols) | Agent's system prompt or loaded files | When protocols are updated |

### The Memory vs. Knowledge Distinction

> "Memory is dynamic and is updated on each run. Knowledge, on the other hand, is static. This is reference material that you load up front, things like PDFs, CSVs, or documentation... You give it to the agent once and it can pull from that library whenever it needs to cite something accurately."

**Memory:** Changes with execution. Updated every cycle. Represents what happened recently.  
**Knowledge:** Stable reference material. Read-only during execution. Provides ground truth.

Conflating these causes consistency problems: if your "static knowledge layer" is being written to during agent execution, different agents running at different times will read different "facts."

### Step-by-Step: Designing Your Memory Architecture

1. **Separate memory from knowledge at the file/database level.** Memory is writable at runtime; knowledge is read-only at runtime.
2. **Define what goes in each layer:**
   - In-context: the current task, the last 3 actions, the relevant tool schemas
   - Episodic: every action taken (timestamped, structured)
   - Semantic: durable facts, preferences, learned patterns (promoted from episodic via nightly consolidation)
   - Procedural: protocols, playbooks, system prompts — loaded once per session
3. **Build a promotion pipeline.** Episodic events from the day → nightly consolidation extracts durable facts → semantic layer updated → next session starts with correct knowledge.
4. **Make semantic updates atomic.** Don't write directly to the knowledge base mid-cycle. Queue updates during execution; apply after the session completes.
5. **Add staleness checks.** Any semantic fact older than X days without re-verification should be flagged. Don't let stale facts silently persist.
6. **Use vector stores for retrieval.** For large knowledge bases, store as embeddings. Agent retrieves only the relevant slice using semantic search — not the whole document.
7. **Version your knowledge.** When the knowledge base changes significantly, bump a version. Agents that read the old version should know to re-load.

### RAG (Retrieval-Augmented Generation)

For large external knowledge (documentation, manuals, research corpora): store in a vector database. At query time, retrieve the top-N most relevant chunks and inject them into the prompt. The agent sees only what's relevant — not the entire 100-page document.

Marina's RAG implementation steps:
1. Chunk the source documents (overlap chunks at boundaries)
2. Embed each chunk using a consistent embedding model
3. Store embeddings + original text in a vector database
4. At agent query time: embed the query, retrieve top-N chunks by cosine similarity
5. Inject chunks into the prompt as context
6. Agent cites the chunks in its response

---

## Chapter 7: Reflection and Self-Critique

### Marina's Pattern (22:00–24:00)

> "Reflection adds a quality gate after initial generation. The agent produces an answer, then evaluates its own answer before returning it. Think of it as an internal code review."

Reflection is a second pass using the same (or a different) LLM to evaluate the first pass's output.

### Step-by-Step: Adding Reflection to an Agent

1. **Define what "good" looks like.** Create an explicit rubric: accuracy, completeness, format compliance, citation quality, appropriate length.
2. **Run the primary generation.** Agent produces an initial output.
3. **Run the reflection pass.** Feed the primary output + rubric to an LLM (can be cheaper model). Ask it to identify specific issues: "List any factual errors, missing citations, format violations, or unclear sections."
4. **Parse the reflection output.** Extract the list of issues.
5. **Branch on severity.** If issues are minor → revise inline. If issues are major → restart from step 2 with the issues injected as context.
6. **Set a max revision count.** Never let the reflection loop run forever. 2–3 revision cycles is typically the limit.
7. **Log both outputs.** Keep the original AND the revised output. This lets you measure whether reflection is actually improving quality.
8. **Measure the delta.** Marina's warning: reflection adds latency and cost. Test with and without reflection. If quality scores don't improve meaningfully, remove it.

### When NOT to Use Reflection

Marina is explicit that reflection is not always worth the cost:
- Simple, well-constrained tasks (formatting, extraction) rarely benefit
- High-volume pipelines where latency matters
- Cases where the evaluation rubric is unclear (reflection can't improve what it can't measure)

> "Make sure to test with and without reflection to ensure it's actually helping."

---

## Chapter 8: Guardrails — Keeping Agents Safe

### Marina's Framework (19:30–22:00, 35:10–37:00)

Guardrails are constraints that prevent agents from taking harmful or incorrect actions. Marina separates them into input guardrails (applied before the agent acts) and output guardrails (applied after the agent generates, before output is used).

### Input Guardrails

1. **Input validation:** Check that the task request is well-formed. Reject malformed inputs before the agent starts.
2. **Scope checks:** Is this task within the agent's authorized domain? An agent responsible for email should not accept requests to modify files.
3. **Injection detection:** Scan input text for patterns that look like prompt injection attempts. Flag for human review.
4. **Rate limiting:** Prevent runaway loops by limiting how many times an agent can call a tool or make an API call per minute.

### Output Guardrails

1. **Schema validation:** Does the output match the expected format? Reject and retry if not.
2. **Factual consistency check:** For outputs that make factual claims, spot-check against known ground truth (another LLM, a database lookup, a search).
3. **Toxicity / policy filtering:** Run output through a content classifier before returning to users.
4. **Size limits:** Enforce maximum output lengths to prevent runaway generation.
5. **Reversibility check:** Before executing any irreversible action (send, delete, charge), pause and verify intent.

### Step-by-Step: Implementing Guardrails

1. **List every action your agent can take.** For each action, classify: reversible (edit file) vs. irreversible (send email, delete, charge).
2. **Gate all irreversible actions.** Every irreversible action requires a human confirmation step OR a second LLM to verify before execution.
3. **Add input validation to every tool.** Each tool's `validate_input()` function runs before the tool's main logic. Fail fast.
4. **Add output validation to every generation step.** Each LLM call's output passes through a schema check before being used as input to the next step.
5. **Implement a circuit breaker.** If an agent makes the same tool call 3 times in a row with the same inputs and gets the same output, halt and alert. This is the dead-loop pattern.
6. **Log every guardrail trigger.** When a guardrail fires, log: what triggered it, what the input was, what action was prevented.
7. **Review guardrail logs weekly.** Frequent triggers on the same pattern = either the guardrail is wrong or the agent has a systemic flaw.

---

## Chapter 9: Evaluation — Measuring Agent Quality

### Marina's Framework (24:30–27:00)

> "It's important that you start evaluating right away, but also that you don't worry about having a perfect evaluation system from the get-go. You can get something working quickly and iterate over time."

Marina's hierarchy of evaluation, from cheapest to most expensive:

1. **Code-based checks** (free, instant): Does the output match a schema? Does it contain required fields? Does it have the right length?
2. **LLM-as-judge** (cheap, fast): Feed the output to an LLM with an evaluation rubric. Ask it to score 1–5 on specific dimensions.
3. **Human evaluation** (expensive, slow): Human reviews a sample of outputs and rates them.
4. **A/B testing in production** (requires traffic): Run two agent versions on real tasks; compare outcomes.

### Step-by-Step: Building Your Evaluation System

1. **Start with the simplest check that tells you something meaningful.** For a summarization agent: does the output cite the source? Is it under the length limit?
2. **Define your ground truth.** What does a perfect output look like? Create 5–10 labeled examples.
3. **Build an LLM judge.** Write an evaluation prompt that scores outputs against your rubric. Run it on a sample set. Compare to your human-labeled examples.
4. **Calibrate the judge.** If the LLM judge disagrees with your human labels on > 20% of cases, revise the evaluation rubric.
5. **Create an eval dataset.** Minimum 20 examples covering the full range of task types your agent handles.
6. **Run evals before and after every significant change.** Never deploy a change without running your eval set first.
7. **Track scores over time.** Plot evaluation scores by date. If scores trend downward, something regressed.
8. **Expand the eval set as you find failure modes.** Every production failure = add a new eval case.

### The GVU Pattern (Generator-Verifier-Updater)

Marina's reference to per-agent verifiable signals: define ONE ground-truth metric per agent that cannot be gamed. This becomes the primary evaluation signal.

Examples:
- Coding agent → test pass rate (not "did it generate code")
- Research agent → citation validity rate (not "did it produce text")
- Trading agent → signal accuracy vs. actual market outcomes (not "did it generate analysis")

Without a verifiable ground-truth signal, evaluation is circular.

---

## Chapter 10: Planning — Multi-Step Execution

### Marina's Architecture (27:00–29:00)

Planning is the process by which an agent decides the sequence of actions needed to achieve a goal. Marina distinguishes two planning modes:

**Plan-then-execute:** Agent generates a complete plan upfront → executes each step in order → adjusts if a step fails.

**Interleaved planning:** Agent plans one step at a time, incorporates the result of each step before planning the next.

### When to Use Each

| Plan-then-execute | Interleaved |
|-------------------|-------------|
| Task is well-understood | Task outcome depends on intermediate results |
| Steps are independent | Each step informs the next |
| Plan can be verified by human before execution | High variance in execution paths |
| Lower latency (all steps known upfront) | Higher quality (adapts to new information) |

### Step-by-Step: Building a Planning System

1. **Define the goal with explicit success criteria.** The plan should be derivable from the success criteria.
2. **Generate the plan.** Prompt the LLM to produce a numbered list of steps, each with: what happens, what tool is called (if any), what success looks like.
3. **Validate the plan.** Check that each step is in the agent's capability set. Remove or replace any step that requires tools the agent doesn't have.
4. **Present the plan for human review** (for semi-autonomous systems). This is the Devin gate.
5. **Execute step by step.** For each step: run the action, collect the observation, check against the step's success criteria.
6. **Handle step failures gracefully.** If a step fails: retry (1–2 times), if still failing → generate a recovery plan using the error as context.
7. **Update the plan as you learn.** If an early step reveals new information that changes later steps, revise the remaining plan before proceeding.
8. **Record the full trace.** Every planned step, its actual execution, its result, and any deviations. This is your post-mortem data.

---

## Chapter 11: Multi-Agent Systems — Orchestrators and Subagents

### Marina's Framework (19:35–23:44)

Multi-agent systems use multiple specialized agents, each with a focused role, coordinated by an orchestrator.

**Orchestrator:** Receives the high-level goal. Breaks it into subtasks. Dispatches subtasks to specialized subagents. Collects results. Synthesizes the final output.

**Subagent:** Receives a specific, bounded subtask from the orchestrator. Has domain-specific tools and context. Returns a structured result.

### When NOT to Use Multi-Agent

> "If you have a simple task, skip multi-agent systems. They can slow things down and make debugging more difficult."

Multi-agent adds: coordination overhead, inter-agent communication latency, resource conflicts (two agents modifying the same file), and new failure modes (agent A succeeds, agent B fails, now what?).

Use multi-agent when:
- Tasks have genuine parallelism (different agents can work simultaneously)
- Specialization creates quality improvement (a domain expert agent does better than a generalist)
- Scale requires it (one agent cannot fit all required context)

### Step-by-Step: Designing a Multi-Agent System

1. **Map the task to subdomains.** What are the natural boundaries? (research vs. implementation vs. verification)
2. **Define each agent's scope.** What is the agent responsible for? What is it NOT responsible for?
3. **Define the interface between agents.** This is the most important step.
   - What does the orchestrator send to each subagent? (schema: required fields, types, IDs)
   - What does each subagent return to the orchestrator? (schema: status, output, errors)
   - Never let agents communicate via unstructured text. Every handoff is a typed contract.
4. **Prevent resource conflicts.** If two agents might touch the same file: one gets write access, the other gets read access only. Define this in the agent's permissions, not just in the prompt.
5. **Implement a coordination layer.** The orchestrator must track: which subagent is working on what, expected completion time, what to do if a subagent times out.
6. **Test each subagent independently before wiring them together.** Confirm each agent produces the correct output schema for a range of inputs.
7. **Test the full orchestration with synthetic failures.** What happens if subagent 2 fails after subagent 1 succeeds? Does the orchestrator handle this? Does it retry? Fail gracefully?

### Marina's Interface Rule

> "Define interfaces, not vibes. Each agent needs a clear schema for inputs and outputs. It needs to know things like what fields, what types, what IDs or references get passed along. Handoffs break more often than your models do."

If the output of agent A is an "unstructured blob" that agent B "hopefully parses correctly," you don't have an interface — you have a hope. When this system fails (and it will), you won't be able to tell where the failure occurred.

---

## Chapter 12: Advanced Task Decomposition Patterns

### Marina's Taxonomy (26:14–28:00)

Marina identifies four patterns for decomposing tasks in multi-agent and complex single-agent systems:

### Pattern 1: Functional Decomposition

Split by domain expertise. Each agent handles a different domain of knowledge.

```
Goal: Write a market report
→ Research Agent: gather data
→ Analysis Agent: interpret data
→ Writing Agent: format the report
→ Fact-check Agent: verify claims
```

**Use when:** Different parts of the task require fundamentally different capabilities or tools.

### Pattern 2: Spatial Decomposition

Split by the area of the system the agent operates on. Each agent owns a different part of the codebase, knowledge base, or data store.

```
Goal: Audit the entire codebase
→ Agent A: audits /src/auth/
→ Agent B: audits /src/api/
→ Agent C: audits /src/db/
→ Orchestrator: consolidates findings
```

**Use when:** The task scales beyond what one agent can process in a single context window.

### Pattern 3: Temporal Decomposition

Split by sequence. Each phase depends on the previous phase's output. Agents run serially.

```
Goal: Execute a self-improvement cycle
→ Phase A: Research weakness (produces research file)
→ Phase B: Implement fix (reads Phase A output)
→ Phase C: Verify fix (runs test, checks Phase B output)
```

**Use when:** Steps have strict dependencies. Phase B cannot start without Phase A's output. This is the most important pattern for improvement pipelines.

### Pattern 4: Data-Driven Decomposition

Split by data partition. Each agent processes a different slice of the dataset simultaneously.

```
Goal: Analyze 10,000 customer reviews
→ Agent A: reviews 1–2,500
→ Agent B: reviews 2,501–5,000
→ Agent C: reviews 5,001–7,500
→ Agent D: reviews 7,501–10,000
→ Orchestrator: aggregates findings
```

**Use when:** The task is embarrassingly parallel and the bottleneck is throughput.

### Step-by-Step: Choosing the Right Decomposition Pattern

1. **Is the task sequential?** (each step depends on the prior) → **Temporal decomposition**
2. **Does the task require different types of expertise?** → **Functional decomposition**
3. **Does the task span too much data for one context?** → **Spatial or data-driven decomposition**
4. **Can subsets of the task run in parallel?** → **Data-driven decomposition**
5. **Is there a mix?** (e.g., research is spatial, writing is functional) → Nest the patterns

---

## Chapter 13: Latency, Cost, and Production Tradeoffs

### Marina's Framework (29:00–33:00)

Every agent design involves tradeoffs between:
- **Latency:** How long does it take to complete?
- **Cost:** How much does each run cost in API calls, tool calls, compute?
- **Quality:** How good is the output?

Marina's principle: **you cannot optimize all three simultaneously.** Improving quality typically increases latency and cost. Reducing cost typically reduces quality. The right tradeoff depends on the use case.

### Cost Reduction Strategies

1. **Model tiering.** Use smaller, cheaper models for simple subtasks (classification, formatting, extraction). Reserve expensive models for generation, reasoning, and complex decision-making.
2. **Prompt caching.** Cache the system prompt and static knowledge sections. Pay once per cache entry, then pay 10% per cache hit instead of 100% per fresh input.
3. **Output caching.** For deterministic queries (same input → same output), cache the result. Don't re-run expensive LLM calls for inputs you've already processed.
4. **Batch processing.** Group multiple small tasks into a single larger prompt instead of making N separate API calls.
5. **Early stopping.** Add a gate at the beginning of each agent cycle: "Is there actually anything new to process?" If not, exit early without making any LLM calls.

### Latency Reduction Strategies

1. **Parallelize where possible.** Independent steps run concurrently, not sequentially. Use async where available.
2. **Stream outputs.** Begin displaying or processing output as it generates rather than waiting for completion.
3. **Precompute.** If you know what context the agent will need, prepare it before the agent starts.
4. **Lightweight reflection.** Use a smaller model for the reflection pass; reserve the full model for generation.
5. **Time-box reflection.** If the reflection pass doesn't complete in N seconds, skip it and return the primary output.

### Quality vs. Cost Matrix

| Task Type | Model | Reflection | Caching |
|-----------|-------|-----------|---------|
| Simple extraction | Haiku / mini | No | Yes |
| Complex reasoning | Sonnet / GPT-4 | Yes (1 pass) | No |
| Creative generation | Opus / GPT-4 | Yes (1–2 passes) | No |
| Fact-checking | Sonnet | Yes (1 pass) | Partial |
| Classification | Haiku | No | Yes |

---

## Chapter 14: Observability — Logging WHY, Not Just WHAT

### Marina's Standard (34:00–35:00)

> "You'll want to log not only what an agent did, but why it did it. For example, you might log things like 'agent chose to use web search instead of RAG because query contained recent' or 'reflection pass identified three issues: missing citation, vague date, or wrong tone.'"

The difference between what and why:
- **WHAT:** "Agent called web_search with query='bitcoin price'"
- **WHY:** "Agent chose web_search because query contained 'current' and 'price' — patterns that indicate real-time data need not satisfiable from knowledge base"

WHY logging is what makes post-mortems possible. Without it, you can see that the agent failed but not why it made the decision that caused the failure.

### Marina's Two Observability Levels

**Zoom-in (trace-level):** Every individual action, in order, with full context.
- Every prompt sent to every LLM call (including the full system prompt)
- Every tool call with inputs and outputs
- Every token count (input, output, cached)
- Every retry attempt with the reason for retry
- Every decision branch taken and why

**Zoom-out (metric-level):** Aggregate signals across many runs.
- Success rate by task type
- Average quality score (from LLM judge or human eval)
- Hallucination rate
- Tool error rate by tool
- Latency percentiles (p50, p95, p99)
- Cost per successful task

### Step-by-Step: Implementing WHY Logging

1. **At every tool selection, log the reason.** "Selected tool X because input contained pattern Y."
2. **At every LLM call, log what it was asked to decide.** Capture the actual prompt (or a hash of it) and the decision it returned.
3. **At every branch point, log which branch and why.** "Took early-exit branch because no new inputs found since last run."
4. **At every retry, log the reason.** "Retrying because output failed schema validation: missing field 'citations'."
5. **At every reflection pass, log what issues were identified.** Not just "reflection ran" but "reflection found: missing citation in paragraph 3, vague claim in paragraph 5."
6. **Correlate actions across steps with a trace ID.** Every step in a single agent execution shares a trace ID. This lets you reconstruct the full execution path in sequence.
7. **Export logs to a searchable store.** JSONL works at low volume; use OpenTelemetry-compatible stores (Langfuse, Jaeger) at production volume.
8. **Create a dashboard for zoom-out metrics.** Plot quality, cost, success rate over time. Regressions show up as trend breaks.

### User Behavior Signals (Marina's Addition)

> "Are they using your agent as you intended or have they found creative workarounds? Where do they get stuck? Do they rephrase and retry? That's a signal the first attempt didn't work."

Log:
- How often users rephrase the same request (retry signal)
- Where users abandon multi-step flows (drop-off signal)
- Which outputs users manually correct (quality signal)

Every correction is data. Track corrections → identify patterns → fix the underlying capability gap.

---

## Chapter 15: Security — Prompt Injection, Code Execution, Data Leakage

### Marina's Framework (35:10–37:00)

> "You're not just protecting against external attackers. You actually have to protect against your own system making dangerous decisions or being manipulated into harmful actions."

The four main security threats:

1. **Prompt injection:** Malicious text in the agent's input or tool output that overrides the agent's instructions.
2. **Unsafe code execution:** Agent generates code that, when executed, has unintended side effects.
3. **Data leakage:** Agent exposes sensitive data through tool calls, logs, or outputs.
4. **Resource exhaustion:** Agent runs in an unbounded loop, consuming unlimited compute, API credits, or disk.

### Prompt Injection Defense

Prompt injection is when content from an untrusted source (web page, email, file, tool output) contains instructions that hijack the agent's behavior.

Step-by-step defense:
1. **Treat all tool outputs as untrusted data.** Never execute instructions found in tool results without explicit human confirmation.
2. **Separate instruction space from data space.** Instructions are in the system prompt. Tool results are in the data section. The model should know the difference.
3. **Use explicit instruction markers.** `<system>` for instructions, `<data>` for tool results. Train the agent to distinguish.
4. **Sanitize inputs.** Strip HTML, special characters, and any patterns that look like system prompts from tool outputs before injecting into context.
5. **Log all tool outputs.** Any attempt to override agent behavior via tool output will appear in the trace.

### Code Execution Safety

> "Sandbox execution. Use Docker or a restricted runner environment. Isolate code execution completely from your main application. Resource limits. Set timeouts, memory caps, CPU limits. Block dangerous imports, network access unless explicitly needed, and file system writes outside of a designated temp directory. Whitelist libraries only."

Step-by-step:
1. **Run generated code in a sandbox.** Not in the same process as the agent. Not in the same filesystem. A separate container or subprocess with restricted permissions.
2. **Set a timeout.** Generated code that runs longer than N seconds is killed.
3. **Set memory limits.** Generated code that consumes more than X MB is killed.
4. **Whitelist allowed imports.** Build an allowlist of safe libraries. Reject code that imports anything outside the allowlist.
5. **Restrict filesystem writes.** Generated code can only write to `/tmp/` or a designated sandbox directory. Block writes to the agent's own directory or any system path.
6. **Block network calls** unless explicitly needed. Generated code should not be able to make HTTP requests by default.
7. **Review the generated code before execution** for anything on a known-bad pattern list (subprocess, os.system, eval, exec, __import__).

### Data Leakage Prevention

1. **Classify data before it enters the agent's context.** Tag sensitive fields (PII, credentials, financial data).
2. **Redact sensitive data from logs.** Never log API keys, passwords, or PII in plaintext.
3. **Scope tool permissions.** A research agent should not have write access to the production database.
4. **Audit tool calls for data exposure.** Review what data each tool can return and whether that data should be in the agent's context.
5. **Separate environments.** Agents that touch production data should not be able to call tools that post to external services.

### Resource Exhaustion Prevention

Marina's specific reference to disk fills and infinite loops:
1. **Gate every recursive or looping operation.** Before any cycle begins: check available disk space, check how many times this loop has run this session, check if new inputs exist.
2. **Hard exit on resource thresholds.** If disk < 5GB, stop. If loop count > N, stop. These are exits, not warnings.
3. **Log every resource check.** When the gate triggers, log why: "Exiting — disk at 4.2GB (threshold 5GB)."
4. **Set token budgets per task.** An agent that uses more than N tokens on a single task is probably stuck. Exit and alert.

---

## Chapter 16: Connection to the Agent Economy

### The Context These Principles Operate In

Marina's course teaches you how to build agents that work. The broader question — where those agents fit in the emerging economy — is the domain of the **Agent Economy Blueprint** (see `docs/legacy/core-original-design/Hyo_01_Overview.md`) and the **Zero to Autonomous Blueprint** (see `kai/research/raw/2026-04-23-autonomous-company-research.md`).

### What the Agent Economy Requires from Agents

For agents to participate in a trust economy — to be hired, verified, reviewed, and paid — they must demonstrate properties that Marina's course directly enables:

**Identity and verifiability:** An agent must be able to prove what it did and why (Chapter 14 observability). Without logs of agent reasoning and tool calls, there is no audit trail. Without an audit trail, there is no trust.

**Consistent interfaces:** An agent that communicates via unstructured text cannot be reliably integrated by other agents or platforms (Chapter 5 tool interfaces, Chapter 11 multi-agent handoffs). Typed schemas are the prerequisite for the agent marketplace.

**Predictable behavior:** An agent that behaves differently based on what it saw last (no memory architecture) or what prompt it received (no evaluation baseline) cannot be trusted with consequential tasks (Chapters 6, 9).

**Resource accountability:** An agent economy requires cost transparency. An agent that cannot report its resource consumption (tokens, tool calls, latency) cannot bill accurately or be audited (Chapter 13 observability).

**Safety at scale:** As agents gain autonomy and interact with the real world, the security properties in Chapter 15 become not just best practices but prerequisites for participation.

### Key Findings from the Zero to Autonomous Blueprint

From the 2026-04-23 research (65+ sources, production deployments):

1. **Outcome monitoring, not activity monitoring.** The ZtA Blueprint finding: agents that produce perfect-looking logs while doing nothing are impossible to catch without checking expected output exists at the expected location. Marina's Chapter 14 addresses this directly: log what was produced, not just that the agent ran.

2. **Per-agent ground-truth verifiers.** The GVU pattern (Chapter 9): every agent needs one metric that cannot be gamed. Without verifiable signals, self-improvement is circular.

3. **Topology discipline.** The UC Berkeley MAST paper (cited in ZtA Blueprint): 17x error amplification when agents lack structured topology. Marina's Chapter 11 (multi-agent orchestration with typed interfaces) is the direct mitigation.

4. **Event-driven over polling.** The ZtA Blueprint recommends pub/sub over polling for agent coordination. Marina's async tool support (Chapter 5) and parallel execution (Chapter 13) are the implementation path.

5. **HITL at plan level, not output level.** Devin pattern (Chapter 2, Chapter 10): catch misalignment at the game plan review, not after full execution. Cheapest point to intervene.

### The Trust Layer

For agents to be trusted by other agents and by humans in an economy, every principle in this course must be implemented and demonstrable. Marina's course is not just a technical curriculum — it is the minimum viable specification for an agent that can participate in the agent economy without being a liability to the system.

---

## Quick Reference Card

### Decision Framework for Any Agent Design

```
1. GOAL → Is it specific? Does it have success criteria?
           If NO → clarify before building anything

2. AUTONOMY → What actions are irreversible?
               All irreversible actions → require human gate

3. CONTEXT → What does the agent need to know?
              Role + Task + Memory (last 3) + Tools + Knowledge

4. DECOMPOSITION → Can you tell which step failed when it fails?
                   If NO → decompose further

5. TOOLS → Does each tool have: name, description, schema, error handling?
            If NO → incomplete; do not wire to agent

6. MEMORY → Is static knowledge separate from dynamic memory?
             If NO → separate before running multi-agent

7. EVALUATION → What is the ground-truth metric for this agent?
                If you can't define it → agent cannot self-improve

8. REFLECTION → Did you test quality with and without it?
                If NO → don't add it until you can measure the benefit

9. OBSERVABILITY → Does every decision log its reason (WHY)?
                   If NO → post-mortems are impossible

10. SECURITY → Is generated code sandboxed? Are resource gates in place?
               If NO → DO NOT run autonomously
```

### Marina's Most-Cited Principles

- "Context engineering is the practical foundation of intelligence in agents."
- "Each step is small, checkable, and clear. When the output isn't good enough, you know exactly what step to improve."
- "Define interfaces, not vibes."
- "Log not only what an agent did, but why it did it."
- "Sandbox execution. Set timeouts, memory caps, CPU limits."
- "Start evaluating right away. Don't wait for a perfect evaluation system."
- "If you have a simple task, skip multi-agent systems."
- "Test with and without reflection to ensure it's actually helping."

---

*This guide was compiled from the full transcript of Marina Wyss's "AI Agents in 38 Minutes — Complete Course from Beginner to Pro" (YouTube, Dec 9, 2025, 145K views, 4.2K likes). All quoted text is verbatim from the 1,247-segment transcript. Cross-referenced with: Agent Economy Blueprint (Hyo_01_Overview.md v1.0), Zero to Autonomous Blueprint (2026-04-23-autonomous-company-research.md, 65+ sources), and Aurora Economics model (aurora-economics.md).*
