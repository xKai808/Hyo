# PROTOCOL_OMP.md — Outcome Metric Profile
**Version:** 1.0  
**Date:** 2026-04-21  
**Owner:** Kai  
**Measured by:** bin/omp-measure.sh (nightly 07:30 MT)  
**Output:** agents/<name>/ledger/omp-latest.json + omp-history.jsonl

---

## Design Philosophy

SICQ (Self-Improve Cycle Quality) measures **process compliance** — did the agent go through the
right motions? OMP (Outcome Metric Profile) measures **whether the motions produced real change**.
Both layers are necessary and complementary:

- SICQ catches broken process (theater, silent failures, skipped stages)
- OMP catches broken outcomes (process ran, but nothing actually improved)

A healthy agent scores high on both. An agent that games SICQ by filling in fields and touching
files without real impact will score low on OMP. The two layers create a cross-check.

---

## Research Basis (30+ sources across 6 platforms)

**Agent evaluation frameworks:**  
CLEAR (Cost/Latency/Efficacy/Assurance/Reliability) — arxiv 2511.14136v1;  
DeepEval session/trace/span hierarchy; Amazon Bedrock AgentCore Evaluations;  
MultiAgentBench milestone-based KPIs; Galileo elite team metrics;  
SAP agent-quality-inspect (AUC, PPT, pass@k); Microsoft Dynamics 365 agent perf framework  

**SRE / alerting quality:**  
Google SRE incident metrics handbook; Prophet Security SOC metrics (MTTD, MTTR, FPR);  
SigNoz 10 Essential SRE Metrics; Rootly incident response metrics  

**Code / deployment quality:**  
SonarQube defect density + churn; GitLab Code Quality; Codacy; qodo.ai 2025 code quality  

**Content / newsletter quality:**  
Beehiiv engagement metrics (CTOR as truest content measure);  
Inbox Collective newsletter success measurement; Campaign Monitor CTOR benchmarks;  
IndieGraf news publisher metrics; MailerLite 2025 benchmarks  

**Financial analysis quality:**  
Macrosynergy trading signal quality (PnL-based + balanced accuracy);  
ScienceDirect multi-metric financial validation; arxiv adversarial fragility in financial ML;  
Stefan Jansen ML for Trading (GitHub); Increase Alpha AI trading framework (arxiv)  

**Anomaly/pattern detection quality:**  
TimeEval comprehensive evaluation; ACM CIKM Time-Series Aware P&R;  
PATE proximity-aware evaluation; Springer metric taxonomy for anomaly detection  

**LLM-as-judge + calibration:**  
LangChain LLM-as-judge calibration (Cohen's kappa); GoDaddy score calibration;  
arxiv Overconfidence in LLM-as-Judge; Spotify Research profile-aware LLM-judge  

**Self-evolving quality frameworks:**  
Google Cloud gen AI KPIs (quarterly retire/refresh); NIST AI Resource Center AIRMF Measure;  
ProductSchool metric evolution guide; Clarifai performance drift detection  

**Community + video:**  
Denys Linkov Spotify podcast — micro metrics for LLM systems;  
YouTube: "Measure What Matters: Quality-Focused Monitoring for Production AI Agents";  
YouTube: "Evaluating AI Agents: Why It Matters and How We Do It";  
Reddit/community: benchmarks vs production reality gap  

---

## Layer 1: Umbrella Metrics (all agents)

These five metrics apply universally. Every agent computes them from its own data.

### U1 — Outcome Completion Rate (OCR)
**What it measures:** % of self-improve cycles that produce a verifiable resolved weakness.  
**Not:** % of cycles that ran. Running ≠ producing.  
**Formula:** `resolved_cycles / total_cycles` in the last 14 days (from evolution.jsonl)  
**Source:** CLEAR Efficacy dimension; Amazon AgentCore task completion rate  
**Healthy threshold:** ≥ 0.25 (at least 1 in 4 cycles resolves something)  
**Unhealthy:** < 0.10 for 14 days → P1 ticket (cycles running with nothing resolving)

### U2 — Regression Rate (RR)
**What it measures:** % of "resolved" weaknesses that re-appear within 30 days.  
**Principle:** Fixes that don't stick aren't fixes — they're deferred problems.  
**Formula:** `re_appeared_weaknesses / total_resolved_30d_ago`  
**Source:** SRE MTBF (Mean Time Between Failures); CLEAR Reliability dimension  
**Healthy threshold:** ≤ 0.15 (≤15% of fixes regress)  
**Unhealthy:** > 0.30 → P1 ticket (systemic: fixes too shallow, not addressing root cause)

### U3 — Research Depth Index (RDI)
**What it measures:** Quality of research — external breadth × structural completeness.  
**Principle:** Research without external sources is reflection, not research.  
**Formula:** `min(external_url_count / 6.0, 1.0) × (required_fields_present / required_fields_total)`  
Required fields: FIX_APPROACH, FILES_TO_CHANGE, CONFIDENCE, ROOT_CAUSE, EVIDENCE  
External URL = any http(s) URL that is not hyo.world  
Minimum 6 external sources = full RDI breadth credit (≥6 sources per finding standard)  
**Source:** Research citation standards; DeepEval groundedness metric; LangChain calibration  
**Healthy threshold:** ≥ 0.70  
**Unhealthy:** < 0.40 → P2 ticket (research is shallow or internal-only)

### U4 — Cycle Efficiency (CE)
**What it measures:** Mean number of cycles (attempts) to resolve a weakness.  
**Principle:** A weakness that takes 10+ cycles is either poorly specified, too complex, or the
research isn't finding the real fix.  
**Formula:** `total_cycles_used / total_weaknesses_resolved` (14-day window)  
**Source:** Multi-agent orchestration efficiency metric; SAP agent-quality-inspect PPT (Progress Per Turn)  
**Healthy threshold:** ≤ 4 cycles per resolution  
**Unhealthy:** > 8 → P1 ticket (stuck pattern — probably needs Kai to rewrite the weakness spec)

### U5 — Metric Calibration Score (MCS)
**What it measures:** How well the agent's SICQ self-score tracks against external peer review verdicts.  
**Principle:** If SICQ = 85/100 but cross-agent verdict = WEAK, the SICQ is uncalibrated.
A calibrated metric is one where high scores reliably predict good peer verdicts.  
**Formula:** `agreement_count / total_reviewed_weeks` where agreement = SICQ≥60 AND verdict=STRONG/ADEQUATE,
or SICQ<60 AND verdict=WEAK/THEATER  
**Source:** LangChain LLM-as-judge calibration (Cohen's kappa ≥ 0.4 = moderate agreement);  
GoDaddy calibration research; arxiv LLM-as-Judge calibration  
**Healthy threshold:** ≥ 0.70 (70% agreement between SICQ and peer verdict)  
**Unhealthy:** < 0.50 → P1 ticket "MCS low for <agent> — SICQ may need recalibration"  
**Note:** Requires ≥4 weeks of cross-agent review data before this metric is meaningful.
Before that, MCS = null (insufficient data).

---

## Layer 2: Agent-Specific Metrics (one unique metric per agent)

Each agent has one metric unique to its specialty that cannot be measured by any other agent's data.

---

### Nel — Alert Precision Score (APS)
**Rationale:** Nel's core job is system health monitoring. A monitor that generates mostly false
alarms becomes noise — engineers stop reacting to it, and real issues get missed. The industry
standard for production monitoring systems is ≥ 85% precision (Prophet Security SOC benchmarks).
Unlike generic completeness metrics, APS measures whether Nel is actually useful as a sentinel.  

**Formula:**  
`APS = true_positive_alerts / (true_positive_alerts + false_positive_alerts)`  

Where:  
- `true_positive` = alert that led to a ticket that was ultimately marked RESOLVED (real issue found)  
- `false_positive` = alert that persisted as chronic (escalation_level=3) for >7 days AND  
  was subsequently closed with reason "false_alarm" in known-issues.jsonl OR  
  the underlying condition was confirmed normal (e.g., auth-gated endpoints returning 401)  

**Data source:** `agents/nel/memory/sentinel-escalation.json` + `kai/ledger/known-issues.jsonl` +  
ticket ledger (look for tickets opened by Nel that were resolved vs. closed-as-false-alarm)  
**Healthy threshold:** ≥ 0.80  
**Unhealthy:** < 0.65 → P0 ticket (Nel's signal is mostly noise — critical trust failure)  
**Source:** Google SRE handbook; Prophet Security SOC metrics; SigNoz SRE metrics

---

### Sam — Deploy Stability Score (DSS)
**Rationale:** Sam's core job is engineering and deployment. A deployment that introduces
regressions is worse than no deployment — it creates extra work and erodes trust in the CI/CD
pipeline. DSS measures whether Sam's deployments are net positive. Analogous to change failure
rate (CFR) in DORA metrics, which top-performing engineering orgs keep below 5%.  

**Formula:**  
`DSS = 1.0 - (regressions_post_deploy / total_deploys)`  

Where:  
- `regression_post_deploy` = deploy where `perf-check.sh` logged a P0 or P1 regression  
  within 24 hours OR sentinel opened a new P0/P1 issue within 24h citing a recent deploy  
- `total_deploys` = git commits that triggered a Vercel deploy (from deploy log or git log on  
  website/api/ paths)  

**Data source:** `agents/sam/ledger/performance-baseline.jsonl` (perf regressions) +  
git log filtered to website/api/ changes (proxy for deploys) +  
`kai/ledger/known-issues.jsonl` (new issues opened within 24h of a deploy)  
**Healthy threshold:** ≥ 0.90  
**Unhealthy:** < 0.75 → P1 ticket (deploy quality degraded — 1 in 4 deploys causes problems)  
**Source:** DORA metrics (change failure rate); SonarQube; GitLab code quality; qodo.ai 2025

---

### Ra — Engagement Quality Score (EQS)
**Rationale:** Ra's core job is content quality and newsletter production. The newsletter industry
has converged on CTOR (click-to-open rate) as the best single measure of content quality because
it filters out passive opens — it measures whether readers found the content worth acting on.
Retention is the second-order signal (Beehiiv calls it "god-tier"). Source diversity ensures
Ra isn't drawing from an echo chamber of the same 2-3 feeds.  

**Formula:**  
`EQS = (CTOR × 0.50) + (source_diversity_ratio × 0.30) + (retention_score × 0.20)`  

Where:  
- `CTOR` = clicks / opens from `agents/ra/ledger/engagement.jsonl` (7-day rolling)  
  Industry benchmark: 10-15% = good; >20% = excellent (Campaign Monitor, MailerLite)  
  Normalize: CTOR / 0.20 (cap at 1.0 for >20%)  
- `source_diversity_ratio` = min(unique_domains_in_sources.json / 10, 1.0)  
  10 distinct external domains per newsletter cycle = full credit  
- `retention_score` = min(active_subscribers_this_week / active_subscribers_last_week, 1.0)  
  1.0 if stable or growing; decaying score if subscriber count declining  

**Data source:** `agents/ra/ledger/engagement.jsonl` (clicks, opens) +  
`agents/ra/pipeline/sources.json` (feed diversity) +  
`agents/sam/website/data/` (subscriber count from aurora data)  
**Healthy threshold:** ≥ 0.50  
**Unhealthy:** < 0.30 → P1 ticket (content not engaging readers, or sources homogeneous)  
**Source:** Beehiiv engagement metrics; Inbox Collective newsletter success; Campaign Monitor CTOR;
IndieGraf news publisher metrics; Spotify profile-aware LLM-judge (relevance scoring)

---

### Aether — Adversarial Survival Rate (ASR)
**Rationale:** Aether's core job is financial analysis. The dual-phase pipeline exists precisely
because Claude's analysis needs an adversarial second opinion. ASR measures whether Aether's
primary analysis actually survives that challenge — a high ASR means Aether is doing genuine
depth analysis, not just pattern-matching the obvious. In financial ML, adversarial validation
is used to test whether models hold up under regime change. The same principle applies here.  

**Formula:**  
`ASR = analyses_recommendation_unchanged / total_analyses_with_gpt_critique`  

Where "unchanged" = Claude's final recommendation (BUILD vX / COLLECT MORE DATA / MONITOR AND HOLD)
did NOT change after receiving GPT critique in Phase 2. A changed recommendation = GPT found
a material error that Claude had to correct.  

**Data source:** `agents/aether/logs/aether-*.log` — parse for Phase 1 recommendation vs  
Phase 2 final recommendation. Look for lines containing "RECOMMENDATION:" before and after  
GPT critique block. If recommendation text materially differs → "changed" (failed adversarial).  
**Healthy threshold:** ≥ 0.65 (2/3 of analyses hold up under adversarial challenge)  
**Unhealthy:** < 0.40 → P1 ticket (Aether making surface-level analyses GPT consistently overturns)  
**Note:** A very high ASR (>0.95) may indicate GPT is being insufficiently adversarial —  
flag for investigation if sustained at >0.90 for 14 days.  
**Source:** ScienceDirect multi-metric financial validation; arxiv adversarial fragility;  
Macrosynergy trading signal quality; Stefan Jansen ML for Trading (GitHub)

---

### Dex — Pattern Actionability Rate (PAR)
**Rationale:** Dex's job is pattern detection across agent behavior. A pattern detector that
flags 100 patterns per day with none being acted on is worse than useless — it's noise that
desensitizes agents to real signals. PAR measures whether Dex's patterns lead to actual
decisions (even deliberate "no action needed"). This is analogous to precision in anomaly
detection — the ACM CIKM paper on time-series aware precision defines actionability as whether
the detection window led to a meaningful intervention.  

**Formula:**  
`PAR = patterns_with_response / total_patterns_flagged`  

Where:  
- `patterns_with_response` = patterns that led to: (a) a ticket being opened, OR (b) a  
  deliberate "reviewed, no action" log entry in a subsequent agent's evolution.jsonl  
- `total_patterns_flagged` = cluster-report.json pattern count in the window  
- Window: 14 days  

**Data source:** `agents/dex/ledger/cluster-report.json` (patterns flagged) +  
ticket ledger (tickets referencing dex patterns) +  
evolution.jsonl across agents (looking for explicit "dex pattern reviewed" events)  
**Healthy threshold:** ≥ 0.35 (35% of patterns get a deliberate response)  
**Unhealthy:** < 0.15 → P1 ticket (Dex output not being used — patterns are noise or unresolvable)  
**Note:** This metric also pressures Dex to flag fewer, higher-quality patterns rather than  
maximum volume — quality over quantity.  
**Source:** ACM CIKM time-series aware P&R; PATE proximity-aware evaluation;  
Springer anomaly detection metric taxonomy; TimeEval comprehensive evaluation

---

### Kai — Context Continuity Score (CCS)
**Rationale:** Kai's core job is orchestration across sessions. The #1 failure mode for Kai
is context drift — operating on stale assumptions that Hyo then has to correct. Every
correction Hyo makes is evidence of a continuity failure. CCS measures how well Kai maintains
accurate working context without requiring Hyo to re-orient it. Session continuity is cited
in multi-agent orchestration research as a key property of orchestrators (Long Memory Span,
Social Bench 40+ turn retention). For Kai specifically, the signal is in session-errors.jsonl.  

**Formula:**  
`CCS = 1.0 - (sessions_with_assumption_error / estimated_sessions_in_window)`  

Where:  
- `sessions_with_assumption_error` = count of entries in `kai/ledger/session-errors.jsonl`  
  with category "assumption" OR "reinterpret-instructions" in the last 14 days  
- `estimated_sessions_in_window` = 14 (assumes one Hyo session per day; adjust if data shows otherwise)  
- CCS is capped at 1.0 (cannot exceed perfect continuity)  

**Data source:** `kai/ledger/session-errors.jsonl` (Kai's own mistake ledger)  
**Healthy threshold:** ≥ 0.80 (Kai makes assumption errors in <20% of sessions)  
**Unhealthy:** < 0.65 → P1 ticket (Kai frequently operating on wrong assumptions — hydration failure)  
**Source:** Multi-agent orchestration DQ (Decision Quality) metric (0.692 vs 0.403 single-agent);  
LongEval and SocialBench context retention benchmarks; Amazon AgentCore session-level evaluation

---

## The Self-Evolving Mechanism

Metrics that don't evolve become gaming targets. Four mechanisms prevent stagnation:

### 1. Calibration check (weekly, automated)
After every cross-agent review run, MCS is recomputed. If MCS < 0.50 for any agent for
3 consecutive weeks, a P1 ticket opens: "OMP miscalibrated for <agent> — SICQ and peer verdict
disagree. Kai should review metric definition."

### 2. Saturation detection (nightly, automated)
If any metric has been at floor (≤ 0.10 delta from its unhealthy threshold) OR ceiling
(≥ 0.10 delta from 1.0) for >21 consecutive days, the metric may be broken:
- Floor saturation: metric is always bad → might be measuring the wrong thing
- Ceiling saturation: metric is always perfect → agent may have found a way to satisfy it
  without producing real improvement
Either triggers a P2 ticket: "OMP metric <metric> for <agent> is saturated — review definition"

### 3. Quarterly metric review (every 13 Saturdays)
The cross-agent review includes a special "metric review" question: "Does this agent's metric
profile still reflect what 'doing the job well' means for this agent's domain? Have any metrics
become outdated, gameable, or misdirected?" Verdicts recorded in omp-history.jsonl with version
bump recommendations.

### 4. Hyo feedback injection
If Hyo gives feedback that implies a specific metric failed (e.g., "the analysis was shallow"),
`kai inject-feedback` now also updates the OMP profile to flag that metric for review. Hyo's
direct signal is the ground truth that all metrics serve.

---

## Integration with the Flywheel

### Weakness prioritization
`agent-self-improve.sh` reads `omp-latest.json` before selecting the next weakness to work on.
The weakness whose LINKED_METRIC (field in GROWTH.md) is lowest-scoring gets prioritized.
If no metric link exists, OMP-based prioritization is skipped and WAI (age-based) applies.

### GROWTH.md weakness format (updated)
Every weakness entry now includes:
```
**Linked Metric:** APS (Alert Precision Score) — current: 0.72, target: 0.85
```

### Verification gate (updated)
When verify_improvement() runs after an implementation:
1. (Existing) Check FILES_TO_CHANGE were modified
2. (NEW) Re-measure the linked OMP metric
3. If metric improved by ≥ 0.05 (5 percentage points) → VERIFIED: OMP_IMPROVED
4. If metric did not improve → NOT VERIFIED: OMP_UNCHANGED (logged but doesn't block)
   The first run through always logs NOT_VERIFIED since the metric needs time to reflect changes.
   After 24h, a re-check runs and re-evaluates. If still no movement after 48h → failure_count++.

### Morning report integration
OMP scores added alongside SICQ in the flywheel section:
`📊 OMP Quality Scores (YYYY-MM-DD): Nel APS: 0.81 ✓ | Sam DSS: 0.92 ✓ | Ra EQS: 0.44 ⚠ | ...`

---

## Metric Version History

Tracked in `agents/<name>/ledger/omp-history.jsonl`:
```json
{"ts":"...", "agent":"nel", "metric":"APS", "version":1, "score":0.72, "calibration":"unknown", "note":"initial measurement"}
```

Version bumps when metric definition changes. Old scores kept for comparison.

---

*When this protocol is updated, bump version and log to evolution.jsonl.*
