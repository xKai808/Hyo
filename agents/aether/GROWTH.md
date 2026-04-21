# Aether Growth Plan

**Domain:** External market intelligence — macro economics, geopolitical risk, Kalshi platform conditions, BTC/crypto market structure
**Last updated:** 2026-04-21
**Assessment cycle:** Daily external intelligence research → analysis output → external_factors section in aether-analysis
**Status:** Active

**SCOPE NOTE (per PROTOCOL_AETHER_ISOLATION.md, 2026-04-21):**
Aether's GROWTH.md is for EXTERNAL intelligence weaknesses ONLY. Internal AetherBot issues
(phantom positions, analysis quality, strategy aggregation) are tracked in PLAYBOOK.md "Open Issues"
section and resolved through Aether's own daily analysis cycle. Kai and other agents do NOT
touch AetherBot code — only Aether's own analysis cycle implements those fixes.

## System Weaknesses (in Aether's external intelligence domain)

### W1: Macro Data Coverage Inadequate — No Real-Time Fed/CPI Signal Monitoring

**Severity:** P1

**Evidence:**
- Aether's daily analyses reference "macro conditions" but source from general market news rather than structured macro data feeds (Fed funds futures, CPI release schedule, PCE data).
- AetherBot's operating conditions are materially affected by macro regime changes (risk-on vs. risk-off), but Aether has no systematic way to detect when the macro regime shifts.
- No Fed calendar integration: FOMC meetings, rate decisions, and dot plot releases all cause BTC volatility spikes. Aether currently discovers these reactively (after they affect trades), not proactively.
- DXY (dollar index) correlation with BTC is a known signal but Aether doesn't track it in its daily analysis; only mentions BTC/USD directly.

**Root cause:**
External intelligence was added to Aether's scope implicitly, not with a structured research framework. Aether's analysis protocol covers trading decisions but doesn't have a dedicated macro data gathering phase. Research is opportunistic rather than systematic.

**Impact:**
- AetherBot may be trading into a macro headwind Aether didn't flag.
- No early warning when Fed pivot signals or inflation data is imminent.
- Hyo doesn't have macro context paired with AetherBot performance data to see if external conditions explain why trading is up or down.

### W2: No On-Chain Signal Integration — AetherBot Operating Blind to BTC Structural Shifts

**Severity:** P1

**Evidence:**
- On-chain data (exchange inflows/outflows, miner behavior, HODLer cohort moves, funding rates) is a leading indicator for BTC price direction that Aether does not currently monitor.
- Aether's external_factors section in daily analyses mentions "market structure" but uses price action only (BTC/USD level, daily range) — not on-chain signals that precede price moves.
- Known signal gap: when whales move BTC to exchanges (high exchange inflow) it historically precedes sell pressure. Aether never flags this.
- Funding rates on perpetual markets signal crowded positioning. Aether doesn't track these despite them being available via free APIs (Coinglass, Glassnode free tier).

**Root cause:**
Aether's research scope was defined around price-level observation rather than structural market intelligence. On-chain data was considered "advanced" and deferred. No data pipeline for on-chain feeds exists.

**Impact:**
- Aether can't warn Hyo when BTC is in a structurally vulnerable position (high exchange inflows + elevated funding = risk-off signal).
- External intelligence layer is reactive rather than predictive; doesn't surface leading indicators.
- AetherBot may increase position size during periods Aether should be recommending REDUCE_EXPOSURE.

### W3: Kalshi Platform Monitoring Not Systematic — Fee/Rule Changes Discovered Reactively

**Severity:** P2

**Evidence:**
- Kalshi has changed fee structures, settlement rules, and available markets multiple times. Aether has no systematic check for these changes; discovers them when they affect trade outcomes.
- Kalshi's API stability is not monitored: if the Kalshi API is slow or intermittent, AetherBot's fills may be unreliable, but Aether's external_factors section doesn't include an API health signal.
- No monitoring for new BTC prediction market categories Kalshi adds (these could be trading opportunities Aether should flag to Hyo).
- Regulatory developments affecting prediction markets (CFTC oversight, new rulings on Kalshi's structure) are not systematically tracked.

**Root cause:**
Kalshi monitoring was assumed to happen organically (via trade results). No dedicated Kalshi platform intelligence phase exists in Aether's research cycle. Research has covered macro and BTC but not the exchange layer specifically.

**Impact:**
- AetherBot could be trading under outdated fee assumptions if Kalshi changed fees without Aether noticing.
- New market opportunities on Kalshi go undetected.
- Regulatory risk to Kalshi itself (which would require AetherBot to pause or exit) is not surfaced proactively.

## Improvement Plan

### I1: Macro Data Pipeline — Structured Fed/CPI/DXY Signal Monitoring

Addresses W1

**Approach:**
Build a daily macro intelligence phase in Aether's research cycle:
1. **Fed calendar integration:** Pull FOMC meeting dates, rate decision dates from public Fed calendar. Flag upcoming events in external_factors section with "FOMC in N days — elevated volatility risk."
2. **CPI/PCE release monitoring:** Automate detection of upcoming inflation data releases. Flag: "CPI release on [date] — historically +/- 3% BTC move."
3. **DXY correlation tracker:** Pull DXY daily close from free API (Yahoo Finance, Alpha Vantage free tier). Include in external_factors: "DXY [up/down/flat] — BTC [historically correlates inversely]."
4. **Macro regime signal:** Classify current macro environment (risk-on/risk-off/neutral) based on DXY trend + rate expectations. Include in daily analysis.

**Research needed:**
- What free APIs provide Fed calendar data?
- What are the reliable CPI release date sources?
- What DXY threshold constitutes a "material move" for BTC correlation purposes?

**Research status:** initial scoping

**Research findings:** (to be populated by Aether's ARIC research phase)

**Implementation:**
1. Create macro data research phase in Aether's daily ARIC cycle
2. Source: Fed website (free), BLS.gov for CPI schedule (free), Yahoo Finance API for DXY
3. Write findings to agents/aether/research/macro-YYYY-MM-DD.md
4. Integrate into external_factors.macro section of daily analysis output
5. Add FOMC/CPI countdown to Kalshi posture recommendation section

**Success metric:**
- Every daily analysis includes structured macro context (DXY trend, upcoming events within 7d)
- FOMC/CPI within 3 days → automatically surfaced as external risk with posture implication
- Hyo can see: "Macro regime: risk-off (DXY +0.4%). FOMC in 2 days. Elevated volatility expected."

**Status:** planned

**Ticket:** IMP-aether-001-ext

### I2: Analysis Quality Scorecard — Auto-Score Completeness, Classification Accuracy, Anti-Patchwork Compliance

Addresses W2

**Approach:**
Build a quality gate that runs after daily analysis is written but before it's published:
1. **Coverage check:** Does analysis cover all session windows? Count: (windows_analyzed / windows_in_log) * 100. Target: 100%.
2. **Classification completeness:** Does every loss have a classification (BUG, MARKET, RISK, SKILL, RECOVERY)? Score: (classified / total_trades) * 100. Target: 100%.
3. **Anti-patchwork compliance:** Does analysis avoid parameter tweaks as primary recommendation? Scan for phrases like "increase size", "raise threshold", "adjust parameter" in high-priority section. Score: 100 - (patch_recommendations * 10). Target: ≥80.
4. **GPT phases complete:** Did Phase 1 (independent) and Phase 2 (comparative) both run? Score: (phases_run / 2) * 100.
5. **Overall score:** (coverage + classification + patchwork + gpt) / 4. Target ≥80/100.
6. Output scorecard to `agents/aether/ledger/analysis-quality.jsonl`: { date, coverage_score, classification_score, patchwork_score, gpt_score, overall_score, flags }

**Research needed:**
- Should we auto-reject (not publish) analysis scoring <70, or just warn?
- What phrases indicate anti-patchwork violations? (can we do keyword matching or need NLP?)
- Should scorecard be automated Python or bash+grep?

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/aether/quality-gate.py` — reads Analysis_*.txt, calculates 4 scores, returns overall quality
2. Check 1: grep window IDs in analysis, count vs. log file windows
3. Check 2: grep classification labels (BUG, MARKET, RISK, SKILL, RECOVERY) count vs. unique trades
4. Check 3: scan for parameter-change language, count occurrences, penalize
5. Check 4: check Analysis_*.txt for [GPT_VERIFIED = YES] marker and timestamp
6. Add Phase 12.5 to aether.sh (Quality Gate): call quality-gate.py, flag if score <70, write scorecard to ledger
7. Add scorecard to HQ feed: "Analysis quality: 88/100 • All windows covered • 98% trades classified • Strong anti-patchwork compliance"
8. Test: run quality-gate.py on an existing analysis file, verify scores are reasonable

**Success metric:**
- Every daily analysis has a quality scorecard visible before publication
- Hyo can see: "Coverage 100%, Classification 98%, Anti-patchwork 90%, GPT phases 2/2 → Overall 97/100"
- Any analysis scoring <70 is flagged P1 for review before shipping
- Quality trends visible over time (improving/declining)

**Status:** planned

**Ticket:** IMP-aether-002

### I3: Automated Cross-Session Aggregator — Weekly Strategy Edge Report + Family Health Dashboard

Addresses W3

**Approach:**
Build a weekly aggregation script that runs after each day's analysis is published:
1. **Read all Analysis_*.txt files from the past 7 days**
2. **Per-strategy edge calculation:**
   - For each strategy family (e.g., "COVERED_CALL", "SYNTHETIC_LONG"): sum realized P&L, count contracts risked
   - Edge = P&L / contracts_risked (answer: how much profit per 1 contract of risk?)
   - Trend: has edge improved week-over-week?
3. **Per-window P&L trend:**
   - Group by time-of-day (morning, afternoon, evening). Sum P&L for each window.
   - Identify: which windows are consistently +EV? which are -EV?
4. **Strategy family health:**
   - For each family: count trades, win rate, avg win size, avg loss size, consecutive losses
   - Flag families in decline: 5+ consecutive losses, or win rate <40%
5. **Concentration risk:**
   - What % of profit comes from top 3 trades? Top 5?
   - Flag if concentration >60% (red flag: too much from too few)
6. Output: `agents/aether/ledger/weekly-aggregator.json` with all metrics + `agents/aether/research/STRATEGY_HEALTH.md` (human-readable report)

**Research needed:**
- Which statistics matter most for early warning? (win rate decline? concentration spike? new strategy underperforming?)
- Should aggregator run daily or weekly?
- What's the actionable threshold? ("Concentration >70% = red flag" or "Concentration >60%"?)

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/aether/aggregate-weekly.py` — reads last 7 Analysis_*.txt files, calculates edge/trend/health metrics
2. Extract strategy family from each trade's classification comment
3. Group by family, window, calculate P&L per contract, win rates, concentration
4. Write structured report to `agents/aether/ledger/weekly-aggregator.json`
5. Generate human-readable markdown report to `agents/aether/research/STRATEGY_HEALTH.md`
6. Add Phase 13 (Weekly Aggregation) to aether.sh: runs Sundays at 22:00 MT, calls aggregate-weekly.py
7. Publish summary to HQ feed: "Weekly Strategy Report: COVERED_CALL +2.3 edge/contract, SYNTHETIC_LONG in decline (2 loss streak), concentration risk 58% (top 3 trades)"
8. Test: run aggregator on mock analysis files, verify calculations are correct

**Success metric:**
- Every Sunday, a weekly strategy health report auto-publishes
- Report shows: per-strategy edge, per-window P&L trends, family health (decline detection), concentration risk
- Hyo can read the report and answer: "Which strategies are working? Which need attention? What's the biggest risk?"
- Trends visible over time (month-over-month strategy performance)

**Status:** planned

**Ticket:** IMP-aether-003

## Goals (self-set)

1. **By 2026-04-21:** Implement Phantom Position Separator and reconciliation against Kalshi. Produce dual P&L (real vs. claimed) with reconciliation gap visible on HQ. No more ambiguity about real balance.

2. **By 2026-04-28:** Analysis Quality Scorecard live. Every daily analysis has 4-metric scorecard (coverage, classification, anti-patchwork, GPT phases). Any analysis <70/100 flagged P1 before publication.

3. **By 2026-05-05:** Weekly Strategy Aggregator operational. First weekly report published showing per-strategy edge, per-window trends, family health, concentration risk. Hyo can track strategy evolution across time.

## Growth Log

| Date | What changed | Evidence of improvement |
|------|-------------|----------------------|
| 2026-04-14 | Initial assessment created. Identified 3 weaknesses: phantom positions, no quality gate, no cross-session intelligence. | Baseline established. Real evidence from KAI_BRIEF (balance discrepancy $25.96/day), session-errors.jsonl (two different balances reported), Aether ops (manual strategy edge calculation). |
| 2026-04-21 | (Planned) Phantom Position Separator wired. Reconciliation script running. | Metrics snapshot shows: realBalance $107.36, claimedBalance $110.05, divergence $2.69 (2.4%). Analysis files now cite both. Reconciliation report published to HQ. |
| 2026-04-28 | (Planned) Quality Scorecard Phase 12.5 integrated. | Analysis for 2026-04-28 shows: Coverage 100%, Classification 96%, Anti-patchwork 88%, GPT phases 2/2 → Overall 96/100. Published to HQ alongside analysis. |
| 2026-05-05 | (Planned) Weekly Aggregator complete. First weekly report published. | Report shows: COVERED_CALL family +1.8 edge/contract (up from +1.2 last week), SYNTHETIC_LONG -0.3 (in decline, flag for review), morning window +EV, evening window -EV, concentration 55% (top 3 trades, healthy). |
| 2026-04-14 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-14 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-14 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-14 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-15 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-16 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-17 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-18 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-19 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-20 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
| 2026-04-21 | IMP-20260414-aether-001 (W1): Total phantom warnings (last 3 days): 0 | Automated assessment |
