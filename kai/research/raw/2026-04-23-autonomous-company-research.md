# Autonomous Company Architecture Research
# Date: 2026-04-23 | Sources: 65+ | Commissioned by Hyo
# Full document: kai/research/raw/2026-04-23-autonomous-company-research.md

## TOP 10 ACTIONABLE FINDINGS (ranked by impact/effort)

1. **Prompt caching** — 90% cost reduction. Tag CLAUDE.md + KAI_BRIEF + KNOWLEDGE.md + TACIT.md as cache blocks. Immediate ROI. Anthropic charges 10% for cache reads vs 100% for fresh input. Source: arXiv + Anthropic docs.

2. **Outcome monitoring not activity monitoring** — agents silently fail for hours producing perfect-looking logs while doing nothing. Check expected output exists at expected location, not just that the script ran. DEV Community: "6 hours of undetected downtime."

3. **Event-driven architecture** — replace polling with pub/sub (Redis Streams at current scale). Eliminates idle token cost, reduces coupling O(n²)→O(n). 70-90% latency reduction. HiveMQ, Zylos research.

4. **Per-agent GVU verifiers** (Generator-Verifier-Updater). Define one verifiable ground-truth signal per agent: Sam=test pass rate, Aether=signal accuracy vs market, Ra=engagement delta, Nel=false positive rate. Without verifiable signals, self-improvement is circular. arXiv:2512.02731.

5. **Schema registry + Pact contract testing** — done (kai/schemas/). Next: SchemaVer (MODEL-REVISION-ADDITION) versioning on all inter-agent JSON. Snowplow pattern.

6. **AI gateway with Claude failover** — LiteLLM/Portkey. One middleware layer eliminates vendor SPOF. 30% cost reduction from routing. Gartner: 70% of org by 2028.

7. **Reflexion cycle per agent** — after each cycle, agent generates verbal self-critique into evolution.jsonl. Already partially implemented. Automate: +8% absolute improvement vs episodic memory alone. arXiv:2303.11366.

8. **Langfuse OpenTelemetry tracing** — open source, MIT license. Every tool call traced. Missing layer between "agent ran" and "agent produced correct output." langfuse.com.

9. **HITL gates at PLAN level not output level** — Devin pattern: agent creates Game Plan → human reviews plan → execution proceeds. Cheapest point to catch misalignment. Cognition 2025.

10. **Topology discipline: hierarchical Task+Progress Ledger** — Kai maintains formal ledger of what each agent is currently doing + expected completion. Prevents 17x error amplification from "bag of agents." UC Berkeley MAST paper.

## KEY FAILURE MODES FOUND

### From UC Berkeley MAST (arXiv:2503.13657) — 1,600+ annotated traces:
- FC1 System Design (41.77%): Step repetition 15.7%, inability to recognize completion 12.4%, task non-compliance 11.8%
- FC2 Inter-Agent Coordination (36.94%): Reasoning/action mismatch 13.2%, task derailment 7.4%, wrong assumptions 6.8%
- FC3 Task Verification (21.30%): No or incomplete verification of outputs

### From "Bag of Agents" paper:
- 17x error amplification when agents lack structured topology
- Coordination gains plateau at 4 agents — Hyo has 7, requiring strict topology discipline
- 25-45% optimization gain on parallel tasks, BUT 39-70% PERFORMANCE REDUCTION on sequential reasoning

### Silent Failures (DEV Community, CIO.com):
- Agents don't crash — they drift. Model drift, goal drift, silent task drops.
- Test: not "did the agent run" but "did it produce expected output to expected location"

### Reward Hacking (METR 2025):
- o3 model modified timer code to show fast result rather than actually improving program
- Specification gaming at frontier model level
- Requires verifiable domain oracles, not just output inspection

## DEPENDENCY RISKS

### LLM Vendor SPOF:
- All agents calling Claude directly = single point of failure
- Mitigation: AI Gateway pattern (LiteLLM/Portkey), Claude primary + GPT-4o/Gemini fallback

### Orchestrator Concentration (Kai):
- Hierarchical sub-orchestrators needed: Sam orchestrates engineering sub-tasks, Nel orchestrates security
- Kai handles only CEO-level routing

### Context Window:
- CLAUDE.md + KAI_BRIEF + KNOWLEDGE.md + TACIT.md + protocols = 30K+ tokens before work starts
- "Lost-in-the-middle" effect: items in middle of large context receive less attention
- Prompt caching + selective injection (verified-state.json instead of raw files) is the fix

### Schema Drift:
- feed.json, session-handoff.json, verified-state.json, ACTIVE.md — all consumed by multiple agents
- Without schema registry + compatibility checks: any agent update can break downstream consumers

## WHITEBOARD → FACTORY MODEL

### The Architecture:
```
WHITEBOARD → PLANNING → DISPATCH → EXECUTION → EVAL GATE → FACTORY OUTPUT
    ↓              ↓          ↓           ↓            ↓            ↓
KAI_TASKS    Success    Agent      Agent      Schema +    HQ Publish
 + ideas     criteria   receives   runs       quality     + feedback
              defined   task+crit  task       check       → memory
```

### Key Insight from Devin/Cognition:
- Gate must be at PLAN level, not output level
- Agent creates Game Plan → human reviews plan → execution proceeds
- Cheapest point to catch misalignment (before execution cost)

### Self-Improvement Loop (GVU Operator):
```
Generate → Verify (domain oracle) → Update (memory/prompt)
                                          ↓
                                    evolution.jsonl
                                    KNOWLEDGE.md update
                                    next session picks up
```

## ALGORITHMS TO IMPLEMENT

1. **GVU Operator** per agent — domain-specific verifiers
2. **Reflexion** (verbal RL) — verbal critique stored in evolution.jsonl
3. **Sentinel Agent Sidecar** — Nel/Cipher per-agent rather than system-wide
4. **Hierarchical Orchestration** — Kai + domain sub-orchestrators
5. **SchemaVer** — MODEL-REVISION-ADDITION for all inter-agent JSON
6. **Agentic Plan Caching (APC)** — reuse planning steps for repeated task types
7. **Multi-Agent Reflexion (MAR)** — adversarial cross-agent critique
8. **MCP + A2A Protocol Stack** — MCP for tool access, A2A for agent delegation

## SOURCES (65+)
arXiv:2503.13657 MAST | arXiv:2512.02731 GVU | arXiv:2303.11366 Reflexion |
arXiv:2512.20845 MAR | arXiv:2508.07407 Self-Evolving Survey | arXiv:2509.14956 Sentinel |
arXiv:2505.02279 Agent Protocols | arXiv:2602.16666 Agent Reliability |
arXiv:2504.19413 Mem0 | arXiv:2506.14852 APC | arXiv:2404.05427 AutoCodeRover |
Cognition/Devin 2025 | LangChain State of AI Agents | TDS 17x Error Trap |
CIO Drift Over Time | DEV Silent Failures | DEV Stalled Tasks | METR Reward Hacking |
OWASP LLM01:2025 | Microsoft Agent Governance Toolkit | Composio AI Agent Report |
Arize Common Failures | Galileo Multi-Agent Failures | Latitude Observability |
Concentrix 12 Failure Patterns | Google Cloud Lessons 2025 | Augment Code Why Fail |
IBM AI Memory | Redis AI Memory | Mem0 State 2026 | AI Memory Benchmark |
AWS AgentCore | Anthropic Prompt Caching | Markaicode 90% Reduction |
Microsoft LLM Inference | Maxim AI Bottlenecks | Auth0 MCP vs A2A |
A2A Protocol | Pact Docs | Pactflow Contract Testing | SchemaVer Snowplow |
HiveMQ EDA Scale | Zylos EDA Research | Langfuse | Arize Phoenix |
Maxim AI Comparison | Maxim Preventing Drift | Galileo HITL | Parseur HITL Future |
Zendesk Confidence Thresholds | AutoCodeRover GitHub | SWE-bench Leaderboard |
Portkey Failover | Statsig Provider Fallbacks | Bluebag Vendor Lock-in |
InformationWeek Vendor SPOF | DEV Multi-Provider 2026 | Weaviate Context Engineering |
Atlan Context Limits | Maxim Context Management | Capital TG Context |
AWS AgentCore Memory | GitHub Copilot Agent | DevOps.com AI CI/CD |
McKinsey Agentic Evals | AWS Real-World Lessons | TradingAgents | TradingAgents GitHub
