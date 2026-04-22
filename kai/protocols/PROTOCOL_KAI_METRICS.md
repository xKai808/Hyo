# PROTOCOL_KAI_METRICS.md
**Version:** 1.0
**Date:** 2026-04-21
**Author:** Kai (CEO Orchestrator)
**Approved by:** Hyo
**Supersedes:** CCS (Context Continuity Score) — single metric, insufficient for Kai's complexity

---

## Why Kai Needs Its Own Metrics

Every other agent has one specialty. Kai has five distinct roles:

1. **CEO / Strategic Decision Maker** — prioritization, architecture, resource allocation
2. **Multi-Agent Orchestrator** — delegation, ACK management, cross-agent coordination
3. **Memory Keeper / Knowledge Manager** — KNOWLEDGE.md, TACIT.md, session continuity
4. **Agentic Self-Improver** — GROWTH.md cycle, autonomous improvement, flywheel runner
5. **Business Operator** — Aurora/AetherBot pipeline, reporting cadence, HQ publication

The prior CCS metric measured only session continuity drift. It captured 1 of 5 roles, ignored the other 4, and could not detect systematic CEO-level failure modes. Hyo approved replacement with a full 5-dimensional framework on 2026-04-21.

---

## Part I: Kai SICQ — Executive Process Compliance Score

**SICQ for all other agents** = flywheel cycle compliance (research written, fields structured, files changed, etc.)

**Kai SICQ** = executive operating protocol compliance. Kai's "self-improvement cycle" is orchestration — Kai improves by improving the system, not just by running the 5-step flywheel. Kai SICQ checks whether Kai is following the executive protocols that make that system improvement possible.

### Components (5 × 20 = 100 max)

| # | Component | Name | What It Checks | Data Source |
|---|-----------|------|----------------|-------------|
| 1 | HC | Hydration Compliance | KAI_BRIEF.md modified within 24h (proxy for full session hydration) | `stat KAI_BRIEF.md` |
| 2 | RDC | Research Depth Compliance | Kai's improvement research file for current weakness has ≥6 external URLs | `agents/kai/research/improvements/W*-DATE.md` |
| 3 | QGC | Queue Gate Compliance | Zero copy-paste / skip-verification / wrong-path errors in past 7 days | `kai/ledger/session-errors.jsonl` |
| 4 | DMW | Dual Memory Write | KNOWLEDGE.md modified within 7 days AND KAI_TASKS.md within 24h | file timestamps |
| 5 | ERR | Error Recall Rate | No same-category error appearing 3+ times in past 14 days | `kai/ledger/session-errors.jsonl` |

### Thresholds
- **≥80**: Healthy — Kai is following executive protocols
- **60–79**: Warning — 1-2 protocol failures; investigate
- **<60**: Critical — systemic protocol non-compliance; P1 ticket auto-opened

### Gates (from Kai SICQ to GROWTH.md)
- HC = 0 → add to GROWTH.md as evidence for W1 (Session Continuity Drift)
- RDC = 0 → add to GROWTH.md as evidence for W2 (Decision Quality)
- QGC = 0 → P1 ticket: "Kai violated queue execution protocol — copy-paste detected"
- DMW = 0 → add to GROWTH.md as evidence for W4 (Memory Consolidation Gaps)
- ERR = 0 → add to GROWTH.md as evidence for W1 (not learning from errors)

### Research grounding
- **HC** tracks hydration compliance per CONTINUATION SESSION RULE (CLAUDE.md). Session 8 was a 9-hour loss from this failure.
- **RDC** implements the ≥6 external URL structural requirement (same as OMP RDI umbrella metric — Kai's own research must meet the same standard).
- **QGC** operationalizes the "NEVER give Hyo commands to copy/paste" rule (CLAUDE.md). SE-010 documented this as the #1 protocol violation.
- **DMW** tracks dual-write compliance: KNOWLEDGE.md (semantic) + KAI_TASKS.md (episodic). Separate stores prevent memory fragmentation.
- **ERR** implements error recall requirement: `session-errors.jsonl` exists to prevent repeating failures. If the same category appears 3+ times, Kai is not learning.

---

## Part II: Kai OMP — 5-Dimensional Outcome Metric Profile

**SICQ** = process compliance (are the right steps being taken?).
**OMP** = outcome quality (is it working?).

Kai's OMP has 5 role-specific metrics, one per role. No single composite score adequately captures CEO-level performance — each dimension can succeed or fail independently.

### Overview

| Metric | Name | Role | Weight | Healthy | Critical |
|--------|------|------|--------|---------|----------|
| DQI | Decision Quality Index | CEO / strategic decision maker | 0.25 | ≥0.80 | <0.60 |
| OSS | Orchestration Sync Score | Multi-agent orchestrator | 0.20 | ≥0.85 | <0.65 |
| KRI | Knowledge Retention Index | Memory keeper | 0.25 | ≥0.90 | <0.70 |
| AAS | Autonomous Action Score | Agentic self-improver | 0.15 | ≥0.75 | <0.50 |
| BIS | Business Impact Score | Business operator | 0.15 | ≥0.85 | <0.65 |

**Composite** = 0.25×DQI + 0.20×OSS + 0.25×KRI + 0.15×AAS + 0.15×BIS
(Weights reflect that decision quality and memory retention are the two most consequential failure modes for Kai.)

---

### Metric 1: DQI — Decision Quality Index

**Role:** CEO / Strategic Decision Maker

**Definition:** Percentage of Kai's decisions that were (a) documented with rationale and (b) not reversed by Hyo.

**Formula:**
```
DQI = (documented_decisions / total_decisions) × (1 - reversal_rate)
```

**Data source (primary):** `kai/ledger/decision-log.jsonl`
```json
{"ts": "2026-04-21T14:00:00-06:00", "type": "delegation", "decision": "...", "rationale": "...", "reversed": false}
```

**Data source (fallback):** `kai/ledger/session-errors.jsonl` — `reinterpret-instructions` and `wrong-path` categories = bad decision quality. Fallback formula: `DQI = 1 - (reinterpret_errors / WINDOW_DAYS)`

**Measurement window:** 14 days rolling

**Thresholds:**
- ≥0.80: Healthy — Kai is making well-documented, stable decisions
- 0.60–0.79: Warning — significant reversal rate or undocumented decisions
- <0.60: Critical — P1 ticket auto-opened; W2 in GROWTH.md gets evidence injected

**Research grounding:**
- Bain "Measuring Decision Effectiveness" (bain.com/insights): quality, speed, yield, effort model. Quality = "was it the right call?" measured by outcome, not just intent.
- Cloverpop DIQ (Decision Intelligence Quotient): quality measured at time of decision, not outcome. Documented rationale = quality proxy.
- McKinsey "Decision making in the age of urgency": 95% correlation between decision quality and financial performance.
- IIT Decision Quality Center: structured decision documentation = leading indicator of decision quality.
- KAINexus CEO transformation metrics: 28 metrics including decision cycle time and reversal rate.

**Linked weakness:** W2 (Decision Quality Is Not Measured)

**Linked goal:** G2 (decision quality score ≥80% over 14 days)

---

### Metric 2: OSS — Orchestration Sync Score

**Role:** Multi-Agent Orchestrator / Supervisor

**Definition:** Rate at which delegated tasks receive ACKs × (1 - rate of tasks delegated back to Kai).

**Formula:**
```
OSS = (ACK_received / tasks_dispatched) × (1 - delegation_back_to_kai_rate)
```

**Data source (primary):** `kai/ledger/dispatch.log`
- Count lines containing `DISPATCH` or `dispatched` → `tasks_dispatched`
- Count lines containing `ACK`, `acked`, or `completed` → `ACK_received`

**Data source (fallback):** Agent ACTIVE.md freshness as proxy for sync health.
- For each agent (nel, sam, ra, aether, dex): ACTIVE.md modified within 48h = synced
- `OSS = synced_agents / total_agents`

**Measurement window:** 14 days rolling

**Thresholds:**
- ≥0.85: Healthy — agents are receiving and acknowledging delegations
- 0.65–0.84: Warning — delegation or ACK gaps exist
- <0.65: Critical — P1 ticket; orchestration breakdown

**Research grounding:**
- Applied-AI-Research-Lab/Orchestrator-Agent-Trust (GitHub): confidence calibration metrics (ECE, OCR, CCC) for trust-aware orchestration. 85.63% overall accuracy with trust-aware routing.
- Databricks supervisor architecture: ACK pattern is foundational to reliable multi-agent systems.
- AgentIF (arxiv 2601.13671v1): Constraint Success Rate and Instruction Success Rate as orchestration quality measures.
- CLEAR Framework (arxiv 2511.14136): reliability = pass@k; assurance = policy adherence. Applied here as ACK rate = reliability proxy.
- GitHub philschmid/ai-agent-benchmark-compendium: 50+ agent benchmarks; coordination success rate is a first-class metric.

**Linked weakness:** W3 (Agent Coordination Latency — No Cross-Agent Signal)

**Linked goal:** G3 (P0 signal latency < 15 minutes)

---

### Metric 3: KRI — Knowledge Retention Index

**Role:** Memory Keeper / Knowledge Manager

**Definition:** Proportion of error categories that Kai has NOT repeated 3+ times in 14 days. High KRI = Kai learns from errors. Low KRI = Kai keeps making the same class of mistake.

**Formula:**
```
KRI = 1 - (repeated_categories / total_categories_seen)

Where:
  repeated_categories = count of error categories appearing 3+ times in past 14 days
  total_categories_seen = count of distinct error categories in past 14 days
```

**Data source:** `kai/ledger/session-errors.jsonl`

**Sliding window comparison:** Compare 7-day and 14-day category distributions. A category appearing in both windows with count ≥2 in the full 14-day window = not retained.

**Measurement window:** 14 days rolling

**Thresholds:**
- ≥0.90: Healthy — Kai is learning from errors (≤10% of error categories repeated)
- 0.70–0.89: Warning — multiple repeated error classes
- <0.70: Critical — systematic retention failure; P1 ticket

**Research grounding:**
- APQC Knowledge Management Metrics (apqc.org): knowledge retention rate as primary KM effectiveness measure. Industry target: ≥85% retention.
- KMInstitute: organizational learning rate = inverse of repeated-problem rate. Low repeat rate = high learning.
- TechTarget knowledge management effectiveness: problem-solving efficiency and reduction in duplicate work as proxy KPIs.
- ManageEngine/Knowmax: knowledge quality and utilization tracking. Error recurrence = knowledge quality failure.
- ISG OODA framework (isg-one.com): Orient phase = applying prior knowledge to current situation. KRI operationalizes the "Orient" phase for Kai.

**Linked weakness:** W1 (Session Continuity Drift) + W4 (Memory Consolidation Gaps)

**Linked goal:** G4 (memory consolidation covers 100% of git diffs)

---

### Metric 4: AAS — Autonomous Action Score

**Role:** Agentic Self-Improver

**Definition:** Proportion of improvements in Kai's GROWTH.md that are self-initiated expansion opportunities (E# items) vs reactive weakness responses (W# items), weighted by flywheel cycle completion rate.

**Formula:**
```
AAS = (E_items / total_items × 0.60) + (cycle_ratio × 0.40)

Where:
  E_items = count of E# entries in agents/kai/GROWTH.md
  total_items = count of W# + E# entries
  cycle_ratio = min(cycles_completed / (improvements_shipped × 2 + 1), 1.0)
```

**Rationale:** A Kai that only reacts to weaknesses is not autonomous — it's just responsive. Expansion opportunities (E#) represent Kai proactively identifying growth vectors beyond what's broken. The cycle ratio ensures the flywheel is actually completing cycles, not just identifying work.

**Data source:** `agents/kai/GROWTH.md` (item counts) + `agents/kai/self-improve-state.json` (cycle count)

**Measurement window:** Point-in-time (current GROWTH.md state)

**Thresholds:**
- ≥0.75: Healthy — Kai is self-directing with meaningful expansion work
- 0.50–0.74: Warning — mostly reactive, insufficient autonomous initiative
- <0.50: Critical — Kai is not functioning as an agentic self-improver; P1 ticket

**Research grounding:**
- arxiv 2502.15212v1 "Measuring AI Agent Autonomy": autonomy spectrum from fully-directed to self-directed. AAS operationalizes the self-direction dimension.
- RagaAI AAEF (Agentic Application Evaluation Framework): four pillars = tool utilization, memory management, strategic planning, component integration. AAS captures strategic planning pillar.
- arxiv 2512.12791v2 "Beyond Task Completion": assessment framework that goes beyond task success to evaluate whether agent is proactively improving vs just completing assigned work.
- McKinsey QuantumBlack (evaluations for agentic world): agentic evaluation must capture initiative, not just execution. Pass rate on assigned tasks ≠ agentic quality.
- arxiv 2412.17149v1 "Multi-AI agent autonomous optimization": self-directed improvement loops as a key capability dimension.

**Linked weakness:** W2 (Decision Quality) + W3 (Coordination Latency)

**Linked goal:** G5 (git review hook live — autonomous improvement shipped)

---

### Metric 5: BIS — Business Impact Score

**Role:** Business Operator (Aurora/AetherBot pipeline, reporting cadence)

**Definition:** Weighted average of report on-time delivery rate and HQ publish rate.

**Formula:**
```
BIS = (on_time_report_rate × 0.50) + (hq_publish_rate × 0.50)

Where:
  on_time_report_rate = morning report delivered ≤07:00 MT = 0.9; else 0.8 (default)
  hq_publish_rate = min(feed_entries_last_7_days / expected_21, 1.0)
  expected_21 = 7 days × 3 agents publishing daily
```

**Data source:** `website/data/morning-report.json` (timestamp) + `website/data/feed.json` (entry count)

**Measurement window:** 7 days rolling

**Thresholds:**
- ≥0.85: Healthy — business pipeline delivering reliably
- 0.65–0.84: Warning — report delays or publish gaps
- <0.65: Critical — business operations breakdown; P1 ticket

**Research grounding:**
- Google Cloud "KPIs that actually matter for production AI agents" (2025): SLA compliance, throughput consistency, and operational reliability as tier-1 business metrics for production AI.
- BCG "AI for RevOps — prediction to execution": business AI must be measured by whether it actually changes business outcomes (reports delivered, content published) not just whether it ran.
- ISG Agentic AI Measurement Framework (isg-one.com): OODA model — Act phase = business outcomes realized. BIS operationalizes the Act phase.
- getmonetizely.com "Agentic AI KPIs": uptime, task success rate, and delivery SLA compliance as the three most important agentic business metrics.
- moxo.com "Evaluating Agentic AI": operational efficiency measured by SLA adherence and output delivery consistency.

**Linked weakness:** W3 (Coordination Latency) — if agents aren't synced, reports are late or missing

---

## Part III: Integration

### Where metrics run

| What | When | How |
|------|------|-----|
| Kai SICQ | Every flywheel-doctor.sh run (09:00, 14:00 MT) | `compute_kai_sicq()` in flywheel-doctor.sh |
| Kai OMP (5 metrics) | Daily 07:30 MT (before morning report) | `measure_kai_omp()` suite in omp-measure.sh |
| Kai composite score | Same as OMP run | Weighted average of 5 metrics |
| Saturation check | OMP run | 21-day floor/ceiling detection |
| Threshold breach → ticket | OMP run | P1 if composite <0.55; P2 if <0.75 |

### Outputs

```
agents/kai/ledger/omp-latest.json      — full Kai OMP including kai_profile{DQI,OSS,KRI,AAS,BIS}
agents/kai/ledger/omp-history.jsonl    — time-series
kai/ledger/omp-summary.json            — all agents (kai section includes all 5 dimensions)
kai/ledger/sicq-latest.json            — Kai SICQ score and history
```

### Morning report display

```
🎯 OMP Outcome Quality (2026-04-21):
  Kai:
    DQI (CEO decisions):      0.82 ✓
    OSS (orchestration sync): 0.90 ✓
    KRI (knowledge retention): 0.85 ✓
    AAS (autonomous action):  0.72 ⚠
    BIS (business impact):    0.88 ✓
    → Composite: 0.84 ✓
```

### GROWTH.md weakness → metric linkage

Each Kai weakness in `agents/kai/GROWTH.md` must include a `**Linked Metric:**` field:
```
**Linked Metric:** DQI — current: 0.76, target: 0.80
```

This closes the loop: OMP measures → GROWTH.md tracks → flywheel improves → OMP measures again.

---

## Part IV: Self-Evolution

All five Kai metrics participate in the standard OMP self-evolution mechanism:

1. **MCS (Metric Calibration Score)**: If SICQ is high but cross-agent review says Kai's work is WEAK, MCS drops → P1 ticket fires → metric definition reviewed.
2. **Saturation detection**: If any Kai metric stays near floor or ceiling for 21+ days → P2 ticket to recalibrate thresholds.
3. **Quarterly review**: During cross-agent review, Dex reviews Kai's metric compliance as part of its "all-agent" review scope.
4. **Hyo feedback injection**: `kai inject-feedback kai "<summary>"` writes directly to W items in GROWTH.md with evidence against the relevant metric.

---

## Research Sources (30+)

### CEO Metrics
1. theceoproject.com — CEO metrics 2025
2. phocassoftware.com — CEO KPIs
3. consciousgovernance.com — CEO KPI frameworks
4. indeed.com — CEO KPI categories
5. kainexus.com — 28 CEO transformation metrics
6. boardpro.com — CEO performance appraisal
7. edstellar.com — 10 essential CEO KPIs

### Multi-Agent Orchestration
8. Databricks — supervisor agent architecture, ACK patterns
9. arxiv 2601.13671v1 — multi-agent orchestration architectures
10. Microsoft Azure — AI agent orchestration patterns
11. IBM — AI agent orchestration
12. GitHub Applied-AI-Research-Lab/Orchestrator-Agent-Trust — confidence calibration (ECE, OCR, CCC)
13. GitHub philschmid/ai-agent-benchmark-compendium — 50+ agent benchmarks
14. AgentIF — CSR and ISR metrics
15. CLEAR Framework (arxiv 2511.14136) — composite enterprise agentic AI evaluation

### Agentic AI Self-Improvement
16. McKinsey QuantumBlack Medium — evaluations for the agentic world
17. arxiv 2512.12791v2 — beyond task completion assessment framework
18. RagaAI AAEF — tool utilization, memory, strategic planning, integration
19. arxiv 2502.15212v1 — measuring AI agent autonomy spectrum
20. arxiv 2412.17149v1 — multi-AI agent autonomous optimization
21. Brookings — agentic AI evaluation considerations

### Decision Quality
22. Wikipedia — Decision Quality (DQ) framework overview
23. Bain.com — measuring decision effectiveness (PDF + articles)
24. McKinsey — decision making in the age of urgency
25. Cloverpop DIQ — Decision Intelligence Quotient
26. IIT Decision Quality Center — structured decision documentation

### Knowledge Management
27. KMInstitute — knowledge management KPIs
28. APQC — knowledge management metrics (retention, quality, utilization)
29. TechTarget — knowledge management effectiveness
30. ManageEngine / Knowmax — knowledge quality and utilization tracking

### Business Operations / Enterprise AI
31. Google Cloud — KPIs that actually matter for production AI agents (2025)
32. BCG — AI for RevOps, prediction to execution
33. ISG — Enterprise Measurement Framework for Agentic AI (OODA model)
34. getmonetizely.com — Agentic AI KPIs (uptime, SLA, delivery)
35. moxo.com — evaluating agentic AI (operational efficiency)
36. kore.ai, gurusup, lyzr — multi-agent orchestration performance KPIs
