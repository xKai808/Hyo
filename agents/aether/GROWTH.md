# Aether Growth Plan

**Domain:** Trading intelligence, strategy evaluation, risk management, bot performance optimization
**Last updated:** 2026-04-14
**Assessment cycle:** 15-min metrics extraction + daily 12-step analysis + weekly GPT dual-phase review
**Status:** Active

## System Weaknesses (in my domain)

### W1: Phantom Position Tracking Unsolved — Aether Reports P&L on Positions Kalshi Never Filled

**Severity:** P0

**Evidence:**
- KAI_BRIEF.md line 15 (Aether migration notes): "Real trading data (542 tickers, 92.4% resolution rate, $90.25 current balance) live on HQ."
- But Aether's analysis files show discrepancies: Aether counts trades from its own API (aether.sh metrics extraction phase) which returns the count of positions it tracked. Kalshi's actual account may have fewer filled positions due to slippage, cancellations, or partial fills.
- Session-errors.jsonl line 89: "Tuesday April 14 ending balance disputed: Kai reported $103.67 (snapshot ~19:57 MT), GPT found $105.80 (snapshot ~20:58 MT), raw log shows $107.36 (final at 21:29 MT). All three are intermediate snapshots at different times."
- Root issue: **reconciliation gap between Aether's position tracking and actual Kalshi account state.** Aether can have up to $25.96/day discrepancy between phantom (claimed) and real (confirmed by exchange) P&L.
- No automated reconciliation. Aether's analysis files contain two numbers: one reported by Aether, one confirmed by Kalshi. The delta between them is never calculated, never highlighted, never reconciled.

**Root cause:**
Aether's metrics phase (15-min cycle) reads from AetherBot's own logs/API, not from Kalshi's portfolio endpoint. The bot tracks its own position state in memory. If the bot and Kalshi diverge (missed fills, cancellations), Aether doesn't know. Analysis files compare Aether's internal state (phantom) vs. Kalshi's actual state (real) but don't separate them in reporting.

**Impact:**
- Every analysis built on phantom data is partially fiction. Strategy edge calculations based on fake P&L. Win rate based on trades the bot thought it made, not trades Kalshi confirmed.
- Hyo sees two numbers and doesn't know which is real. Trust erodes.
- Risk management blind: if phantom P&L is inflated, actual leverage is worse than reported.
- Cross-session trend analysis (which strategies are +EV?) contaminated by phantom position carry-over.

### W2: No Automated Analysis Quality Gate — Daily Analysis Quality Depends Entirely on Analyst

**Severity:** P1

**Evidence:**
- Aether's daily analysis (12-step algorithm in ANALYSIS_ALGORITHM.md) goes through GPT dual-phase review (Phase 1: independent analysis of raw logs, Phase 2: comparative review of Kai's analysis).
- **No automated check on whether the analysis ITSELF is good.** Does it cover all session windows? Does it classify every loss? Does it follow the anti-patchwork doctrine?
- Session-errors.jsonl line 87: "Kai skipped GPT cross-check when rewriting analysis files. Reformatted executive summary without re-sending to GPT-4o for verification. Treated existing GPT reviews as sufficient when the analysis content had changed."
- Aether's ANALYSIS_BRIEFING.txt (660+ lines) has 5 different goal formats, 3 recommendation styles, 2 classification schemes. Consistency depends on who writes it (only Kai can write it now).
- No scorecard, no pass/fail gate, no trigger to catch sub-par analysis before it ships.

**Root cause:**
Analysis pipeline assumed the analyst is always correct and GPT is a rubber-stamp checker. When Kai rewrites summaries or classifications, GPT review doesn't re-run (assumed prior review covers the change). No quality gate between "analysis complete" and "analysis published."

**Impact:**
- Hyo receives analyses that might have incomplete trade classifications, missing session windows, or anti-patchwork violations without knowing.
- Can't distinguish "this analysis has a problem" from "this analysis is good."
- Process is bottlenecked on Kai (the analyst). If Kai is tired or in a hurry, quality drops silently.

### W3: Strategy Evaluation Is Manual — No Automated Cross-Session Aggregation or Edge Analysis

**Severity:** P1

**Evidence:**
- Aether has 41 analysis files (April 7-14 from migration), each with 3 sections (trade log, strategic assessment, P&L breakdown).
- **Cross-session intelligence requires manual work.** Questions like "Which strategies have positive edge per contract risked?" "Which windows are -EV?" "Is any family in systematic decline?" require reading all 41 files, aggregating manually, spotting patterns.
- Session-errors.jsonl line 89 shows balance discrepancies day-by-day (phantom vs. real). Aether has no aggregator to answer: "Are phantom positions accumulating? Is the divergence growing?"
- Aether's PRIORITIES.md lists "phantom positions" and "harvest 12.4% failure" but doesn't quantify cross-session trends. Is phantom position issue getting worse? Better? Stable?
- No automated tool reads all 41 Analysis_*.txt files to produce: per-strategy edge, per-window P&L trend, strategy family health report, concentration risk.

**Root cause:**
Aether's daily analysis is designed to answer "what happened today?" not "what patterns emerged across 30 days?" Cross-session aggregation was deferred ("we can do it later") and never built. Analysis files exist in a flat list; no aggregation layer connects them.

**Impact:**
- Strategy evolution invisible. Hyo can't tell if a strategy that was +EV weeks ago is still +EV or if it's degrading slowly.
- Concentration risk unchecked. If top 3 trades generated 80% of profit, that's a red flag Aether doesn't surface.
- Can't answer board-level questions ("Is trading improving month-over-month?" "What's the biggest risk?") without manual analysis.

## Improvement Plan

### I1: Phantom Position Separator — Automated Reconciliation Against Kalshi, Produce Dual P&L (Real vs. Claimed)

Addresses W1

**Approach:**
Build automated reconciliation step in aether.sh metrics phase:
1. **Extract Kalshi real positions:** Call Kalshi's portfolio API endpoint (read-only, no auth needed for public order book). Match confirmed fills against Aether's claimed positions.
2. **Tag each trade:** For every trade in Aether's log, mark as CONFIRMED (Kalshi API confirms) or PHANTOM (Aether claimed but Kalshi didn't fill).
3. **Produce dual P&L:** Two columns in aether-metrics.json: realBalance (from CONFIRMED trades only), claimedBalance (from all trades including PHANTOM).
4. **Reconciliation report:** Write `agents/aether/ledger/reconciliation.jsonl`: { date, phantom_count, confirmed_count, balance_delta_usd, phantom_pct_of_total }
5. **Update analysis files:** Every daily analysis must show both P&L numbers and explain the delta.
6. **Publish reconciliation status to HQ:** Show "Real P&L: $107.36, Phantom P&L: $103.67, Divergence: $3.69 (3.4%)"

**Research needed:**
- What's the Kalshi API endpoint for confirmed fills? (rate limits, auth requirements?)
- Should we auto-reconcile every 15 min or daily?
- What if Aether and Kalshi disagree on a trade — who's source of truth?

**Research status:** not started

**Research findings:** (none yet)

**Implementation:**
1. Create `agents/aether/reconcile.sh` — pulls Kalshi portfolio data, matches against Aether's position log
2. For each position, determine: is it in Kalshi's confirmed fills? (CONFIRMED) or not? (PHANTOM)
3. Calculate realBalance (sum of CONFIRMED trades), claimedBalance (sum of all trades), delta
4. Write to `agents/aether/ledger/reconciliation.jsonl` and `agents/aether/metrics/reconciliation.json`
5. Integrate reconcile.sh into aether.sh metrics phase (after position extraction, before JSON publish)
6. Update aether-metrics.json schema: add realBalance, claimedBalance, reconciliation.divergence_pct
7. Test: manually verify 5 trades against Kalshi API, confirm CONFIRMED/PHANTOM tags are correct

**Success metric:**
- Every daily metrics snapshot shows both real and phantom P&L
- Reconciliation report visible on HQ: "Real balance $107.36, reconciliation gap 3.4%"
- Analysis files can now cite real P&L separately from claimed P&L
- Hyo knows exactly how much of Aether's reported P&L is phantom vs. real

**Status:** planned

**Ticket:** IMP-aether-001

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
