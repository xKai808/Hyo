# PROTOCOL_DAILY_ANALYSIS.md
# Aether Daily Analysis — Complete Agent Execution Protocol
#
# VERSION: 2.5
# Author: Kai | Last updated: 2026-04-18
# Status: AUTHORITATIVE — supersedes v2.4
# Changes from v2.4 (Hyo feedback session 20 — structural enforcement):
#   - NEW: bin/analysis-gate.py — 6-gate automated hard block between analysis and publish
#   - Part 12: split into 3 explicit phases (ANALYSIS / QUALITY GATE / PUBLISHING)
#     with required exit conditions and structural gate between Phase 2 and Phase 3
#   - Part 14: added Step 2.5 (VERIFY THE FIX WORKS) to discrepancy cycle
#   - Part 14: added post-publish verification checklist (4 items — a/b/c/d)
#   - gpt_crosscheck.py SE-AETHER-002: strengthened to MINIMUM_TICKER_CLOSES=15,
#     MINIMUM_TOTAL_LINES=1000 (was: trade_line_count < 5, too loose)
#   - aether-publish-analysis.sh: now calls analysis-gate.py as hard block before any feed write
# Root cause addressed: protocol documented bugs as fixed but code was not deployed/verified.
#   The gate script mechanically enforces what manual checklists cannot.
#
# PURPOSE:
# Any agent starting from zero context can read this document and produce
# a daily analysis that matches the gold standard, every time, without fail.
# Every file to read, every gate to pass, every section to write, every
# check to run before publishing — all specified here.
#
# USED BY: run_analysis.sh, kai_analysis.py, Aether, Kai, any substitute agent
# EMBEDDED IN: ANALYSIS_ALGORITHM.md (Phase 0 — read this protocol first)
# VERIFIED BY: Completion checklist in Part 9 — every report checked before publish
# ============================================================================

---

## PART 0 — HYDRATION ORDER (READ ALL FILES BEFORE STARTING)

**Non-negotiable. Every session. Zero exceptions.**
The quality of analysis is directly proportional to how thoroughly these files
are absorbed. Agents that skip files produce observation-level output.
Agents that read all files produce mechanism-level output. The difference is
the entire value of the pipeline.

Read in this exact order:

```
FILE 1: agents/aether/analysis/CANONICAL_ANALYSIS_TEMPLATE.txt
PURPOSE: The gold-standard example — APR 13–16 analysis. Shows exactly what data
         to capture and how deep to go. However, the template uses an older section
         structure (PART 1=Balance Ledger, PART 2=Trade-by-Trade, PART 3=Session
         Windows). The PUBLISHED FORMAT is defined in Part 5 of this protocol and
         includes the three section markers required by the publish script.
         Read the template for DATA DEPTH and ANALYSIS QUALITY.
         Read Part 5 of this protocol for PUBLISHED STRUCTURE.
         When in doubt: template for content, Part 5 for structure.

FILE 2: agents/aether/docs/ANALYSIS_BRIEFING.txt
PURPOSE: 14-section operating manual. Covers: what to extract from every log
         (Sections 3–5), trading philosophy (Section 4), strategy evaluation
         (Section 5), patchwork danger (Section 6), deletion bar (Section 7),
         recommendation format (Section 9), state hygiene (Section 10),
         GPT dual-phase pipeline (Section 14). Every analysis rule lives here.

FILE 3: agents/aether/ANALYSIS_ALGORITHM.md
PURPOSE: The 7-gate question-driven decision tree. These are the mandatory
         questions for Gates 1–7. Each gate answer requires log evidence.
         If you cannot answer a gate question, that IS the finding.

FILE 4: kai/memory/KNOWLEDGE.md
PURPOSE: The balance ledger (inject into every Claude system prompt),
         the 5 open issues (check every log for evidence on each),
         analysis standards (what Hyo has explicitly told Kai never to forget),
         correct model strings (never use strings not in this file).

FILE 5: agents/aether/docs/PRE_ANALYSIS_BRIEF.md
PURPOSE: Operating doctrine. 16-section checklist: how to think about
         AetherBot as a trading business, how to analyze each 15-min window,
         required distinctions (premature entry vs late entry vs execution
         failure vs correct abstention), anti-patchwork doctrine.

FILE 6: agents/aether/AETHER_OPERATIONS.md
PURPOSE: 12-step deep analysis protocol, strategy family baselines (PAQ 73% WR,
         bps_premium 86% WR across 9 days), build governance, conviction bucket
         tracking (HIGH+COUNTER, HIGH+ALIGNED), 11 active open issues.

FILE 7: kai/memory/TACIT.md
PURPOSE: How Hyo communicates. What is unacceptable. What Hyo values.
         Read before writing a single word of the report.
         "Hyo expects precision, not hedging. If the data says something, say it."
```

After reading all 7 files, you have the context to produce correct output.
Skipping any file creates a gap. Gaps are caught by the completion checklist.
Persistent gaps erode trust. Do not skip.

---

## PART 1 — PRE-LOG CONTEXT SETUP

Answer these before opening the log:

```
B1: What is today's date (MT)?
    TZ=America/Denver date +%Y-%m-%d

B2: Current deployed AetherBot version?
    From KNOWLEDGE.md. As of 2026-04-18: v253. Next build: v254.
    Never assume. Always read KNOWLEDGE.md.

B3: Running balance ledger?
    ★ SINGLE POINT OF FAILURE NOTE (GPT counterpart review 2026-04-18):
    KNOWLEDGE.md is frequently stale — it is updated manually after confirmed sessions
    and is often one session behind. Do NOT inject KNOWLEDGE.md's ledger blindly.
    Verify the last confirmed date matches your starting assumption before injecting.

    CURRENT LEDGER (as of last confirmed session — update this block after every session):
    ==================================================================================
    3/28 $89.87  | 3/29 $101.25 | 3/30 $90.18  | 3/31 $110.32
    4/1  $119.02 | 4/2  $121.02 | 4/3  $111.55 | 4/4  $107.30
    4/5  $76.18  | 4/6  $93.04  | 4/7  $104.02
    [4/8–4/12: logs unavailable — balance dropped to $90.25 by Apr 13 open]
    4/13 $86.44 confirmed
    4/14 $108.91 confirmed
    4/15 $115.79 estimated
    4/16 $113.96 confirmed (final from Kalshi — was unconfirmed during session)
    4/17 $115.19 UNCONFIRMED (last log entry before midnight — verify Kalshi app)
    ==================================================================================
    Starting balance (3/28): $101.38
    All-time net through Apr 17 (estimated): +$13.81
    Daily target: $100+/day net

    VERIFICATION STEP (mandatory before injecting):
    Does the last CONFIRMED line here match the last entry in KNOWLEDGE.md?
      YES → use this ledger
      NO  → the newer file is correct — reconcile and update this block before proceeding
    This block must be updated after every session in the same commit as the analysis.

B4: The 5 open issues (inject into every Claude system prompt):
    ISSUE 1 (P0): Harvest miss — Mode A (thin anchor depth, ±0.02 gate)
                  vs Mode B (deep book, ABSENT bids, stale orderbook timing).
                  v254 will instrument place_exit_order().
    ISSUE 2 (P1): BDI=0 stop hold fires when seconds_left ≤ 120 → expiry loss.
                  Fix: skip hold at <120s. 4 confirmed expiry losses Apr 13–16.
    ISSUE 3 (P1): POS WARNING | API 0 local N — fires during exit sequences.
                  May indicate phantom entries or settled-before-exit state.
    ISSUE 4 (P2): EU_MORNING post-04:15 losses clustering. 3 sessions confirm.
                  Need 2–3 more sessions before any gate decision.
    ISSUE 5 (P3): Weekend risk profile (target $5 flat, PAQ_MIN=4, disable
                  confirm_late/confirm_standard Sat/Sun). Not built.

B5: Raw log location:
    ~/Documents/Projects/AetherBot/Logs/AetherBot_YYYY-MM-DD.txt
    Use full file. No truncation. Every line must be available to Claude.

B6: SPARSE LOG GATE:
    wc -l "$LOG_FILE"
    If today's log has < 100 lines: use yesterday's log instead.
    See run_analysis.sh lines 96–121 for the automated gate.
```

---

## PART 2 — THE 7-GATE ANALYSIS (PHASE 1: KAI/CLAUDE PRIMARY)

**These are gates, not tasks.** A gate passes only when the answer is supported
by specific evidence from the raw log. If the evidence doesn't exist, that is
the finding. Write it as: "Cannot determine — [what data is missing]."

---

### GATE 1 — GROUND TRUTH

Run this before any other analysis. Everything downstream depends on this.

```
Q1.1: What is the FIRST balance line in today's log?          → $____
Q1.2: What is the LAST balance line in today's log?           → $____
Q1.3: What time (MT) was the last balance line?               → ____
Q1.4: NET = Q1.2 − Q1.1 =                                    → $____
Q1.5: Does this match the bot's claimed settlement sums?      → YES / NO
      If NO → phantom gap = $____  ← this is the #1 finding
```

**GATE RULE:**
If Q1.5 = NO and gap > $5: all downstream P&L figures must be flagged UNRELIABLE.
Do not report claimed P&L as real. The analysis headline is the balance change.

Do not pass Gate 2 until Q1.1–Q1.5 are answered with log evidence.

---

### GATE 2 — TRADE LEDGER

For every trade that settled today, answer all 8 questions:

```
Q2.1: What strategy family triggered this trade?
Q2.2: What side (YES/NO) and at what entry price?
Q2.3: How many contracts? What was the total risk ($)?
Q2.4: How did it exit? (SETTLEMENT / HARVEST / STOP / FORCED_EXIT / HOLD)
Q2.5: If harvested: how many contracts harvested vs total? At what prices?
Q2.6: If stopped: what triggered it? (BDI, trail, time, chop?)
Q2.7: Net P&L from balance change (not claimed settlement figure)?
Q2.8: Balance before and after this trade?
```

**OUTPUT: Table 1 — Trade-by-Trade Ledger**

Format (matches CANONICAL_ANALYSIS_TEMPLATE.txt exactly):
```
[STRATEGY FAMILY NAME]
  HH:MM  YES/NO @ 0.XX  Nc  WIN/LOSS  +/-$X.XX  (exit note if relevant)
  HH:MM  YES/NO @ 0.XX  Nc  WIN/LOSS  +/-$X.XX
  [Family] net:  +/-$X.XX  (N trades, NwW/NlL, WR%)

[NEXT FAMILY]
  ...

SESSION NET: $X.XX
```

- Group by strategy family
- Sort families by net P&L (highest first)
- No trade skipped
- No aggregates without individual lines

---

### GATE 3 — STRATEGY ASSESSMENT

For each strategy that traded today:

```
Q3.1: Trades taken?
Q3.2: Entry price range?
Q3.3: Net P&L?
Q3.4: Win rate?
Q3.5: ★ EDGE PER CONTRACT RISKED = net P&L ÷ total contracts risked across all trades
      This is the real measure. Not win rate.
      90% WR at -$0.02/contract = losing money.
      50% WR at +$0.15/contract = best strategy in the book.

      WORKED EXAMPLE (real numbers — Apr 13–16, 9-session baseline):
      ---------------------------------------------------------------
      bps_premium: 79 trades, +$42.35 net.
        A typical bps_premium trade is 5 contracts at $0.60 entry = $3.00 risk.
        79 trades × ~5 contracts = ~395 contracts risked total.
        Edge per contract = $42.35 ÷ 395 = +$0.107/contract. POSITIVE EDGE.

      PAQ_EARLY_AGG: 95 trades, +$35.81 net.
        A typical PAQ trade is 4 contracts at $0.50 entry = $2.00 risk.
        95 trades × ~4 contracts = ~380 contracts risked total.
        Edge per contract = $35.81 ÷ 380 = +$0.094/contract. POSITIVE EDGE.

      What this tells you:
        - bps_premium has slightly higher edge per contract ($0.107 vs $0.094)
          despite lower overall WR because its avg win size is larger.
        - If a strategy runs 20 trades and shows +$0.03/contract edge, that's marginal.
          Watch it, don't build on it. PAQ threshold for confidence: > $0.08/contract
          sustained over 3+ sessions is meaningful. < $0.03/contract = noise range.
        - When edge-per-contract drops session over session (e.g., $0.12 → $0.07 → $0.02)
          that is a degradation signal even if WR holds steady. Flag it at Gate 3 Q3.6.

      IMPORTANT: "total contracts" means every contract BUY submitted, win or loss.
      A 10-contract trade that wins is 10 contracts. A 10-contract trade that loses
      is also 10 contracts. Do not only count winning contracts.

Q3.6: Improving or degrading vs yesterday and day before?
      Degrading 2+ consecutive days → flag for investigation.
Q3.7: Harvest attempts? Successes? Miss rate? Trend vs yesterday?
```

**OUTPUT: Table 2 — Strategy Summary**

Columns: Family | Trades | W/L | WR% | Net P&L | Edge/Contract | Status

Sort by edge-per-contract. Not win rate.

Status badge logic:
- ALERT: WR < 40% OR net P&L < −$5
- WATCH: WR < 60% OR net P&L < $0
- MONITOR: trades < 5 (sample too small to conclude)
- ACTIVE: meets all other criteria

---

### GATE 4 — SESSION WINDOW BREAKDOWN

Windows (all MT):
- ASIA_OPEN:  00:00–03:00
- EU_MORNING: 03:00–05:00  ← track post-04:15 separately (Issue #4 evidence)
- NY_PRIME:   09:00–15:00  ← the profit engine — protect it at all costs
- EVENING:    17:00–22:00  ← regime-sensitive, check BTC direction first

For each window:

```
Q4.1: List EVERY trade with timestamp, strategy, side, contracts, outcome, P&L.
      Individual trades. Not aggregates. Every one.
Q4.2: Window net P&L?
Q4.3: Which strategies won? Which lost?
Q4.4: Cross-session pattern: net positive across 3+ sessions?
      YES → working. Do not gate based on one bad session.
      NO  → regime-driven (BTC direction) or structural (strategy problem)?
            Separate these before making any recommendation.
Q4.5: EU_MORNING specifically: split at 04:15 MT. Net P&L for each half.
Q4.6: EVENING specifically: BTC spot direction at entry vs settlement.
      If all losses share the same directional pattern → regime event, not strategy.
```

**OUTPUT: Table 3 — Session Window Summary**

Columns: Window | Trades | W/L | Net P&L | Note

Include EU_MORNING pre/post 04:15 sub-rows if any EU_MORNING trades exist.

**CRITICAL RULE:** If a window turns negative, ask "what was BTC doing?" FIRST.
Not "should we gate this window?" Market variance is not a code bug.
Separating the two is mandatory before any recommendation.

---

### GATE 5 — RISK ASSESSMENT

```
Q5.1: Maximum drawdown today?
      (Lowest balance point relative to starting balance)
Q5.2: % of today's P&L from the single best trade?
      > 50% → the day was LUCKY, not SKILLED. Flag it.
Q5.3: Largest single-trade loss? Could it recur tomorrow? What prevents it?
Q5.4: If BTC moved 2% adverse during the largest open position — loss would be?
Q5.5: Correlated losses? (Multiple stops within same 15-minute window)
      YES → overexposed to single-candle risk.
Q5.6: Current balance vs weekly starting balance?
      Trend: improving / flat / declining?
```

**GATE RULE:** If drawdown > 15% of starting balance, OR worst-case > 20%:
→ P0 risk flag. Recommend position size reduction before next session.

---

### GATE 6 — STOP AND HARVEST MECHANISM ANALYSIS

**This gate separates mechanism failures from strategy failures.**
A mechanism failure (code bug) gets a build ticket.
A strategy loss (market read) gets monitored.
Never conflate them. This separation is the core value of the analysis.

```
Q6.1: HARVEST ATTEMPTS
      Total: ____  |  Successful (DONE): ____  |  Failed (MISS): ____
      Success rate: ____%

Q6.2: HARVEST MISS MODE CLASSIFICATION — two distinct failure modes:
      Mode A: anchor_depth low, int_bdi low — depth filter too tight
              Signature: low int_bdi (<200), low anchor_depth
              Fix: anchor ±0.02 depth filter
      Mode B: int_bdi high (>200), anchor_depth high, yet yes_bids/no_bids ABSENT
              Signature: deep internal book, but exchange returns ABSENT bids
              This is a race condition: OB polled, book changed, order lands on stale data
              Fix: log time delta from last OB poll to order placement on every harvest attempt
      Mode A count: ____  |  Mode B count: ____
      List each Mode B instance: int_bdi=____, anchor_depth=____, bids=ABSENT

Q6.3: Successful harvests: % of theoretical maximum profit captured?
      < 60% → harvests firing too early
      > 90% → barely adding value (may as well let settle)

Q6.4: BDI=0 HOLD EVENTS (Issue #2)
      Total BDI=0 holds: ____
      With seconds_left > 120: ____  (outcome: ____)
      With seconds_left ≤ 120: ____  (outcome: ____)
      ★ Every ≤120s hold that led to expiry = mechanism failure. Log each one.

Q6.5: POS WARNING EVENTS (Issue #3)
      Total: ____
      Context: fired during BUY_SNAPSHOT (entry) or during EXIT sequence?
      Seconds remaining at each fire: ____
      Did position appear on next poll? (determines: API lag vs phantom entry)
      If entry-time POS WARNING with >300s remaining → wait 2 polls before exit logic

Q6.6: EXIT MECHANISM EVENTS
      FLIP_EMERGENCY fires: ____ (was each one correct? check subsequent price)
      EXIT_ESCALATED fires: ____ (how many resolved? how many expired?)
      CONTRACT_VELOCITY exits: ____ (fill rate?)

Q6.7: Estimated $ impact from mechanism failures (not strategy losses): ____
      This is the actionable number — losses from code that could be fixed.
```

---

### GATE 7 — OPEN ISSUES CHECK

For each of the 5 open issues:

```
Q7.1: Did today's data provide new evidence on this issue?
Q7.2: Can this issue be CLOSED based on today's data?
Q7.3: Did any NEW issue emerge today that isn't in the list?
Q7.4: Is the same diagnostic appearing again (recurring)?
      YES → the fix either hasn't been deployed or isn't working.
```

For each issue, write: "Evidence today: [what was found / nothing new / CLOSED]"

---

## PART 3 — GPT DUAL-PHASE PIPELINE (PHASE 2)

**Mandatory. Non-negotiable. Every day. No exceptions.**

### Why this exists — failure history so it never repeats:
- v0: Kai skipped GPT entirely. Hyo caught it. "Why am I typing it if you don't use it?"
- v1: GPT saw the finished analysis, not the raw log. Rubber-stamping, not review.
- v2 (current): GPT sees raw log FIRST → forms independent conclusions →
  THEN sees Kai's analysis → fact-checks it. This is the only correct approach.

Single-model analysis is blind to its own errors. GPT caught:
- Apr 17 09:33: stolen-winner claim was wrong (contract resolved NO at 0.001)
- Prior session: $2.13 balance discrepancy Kai missed
That is real money. The pipeline exists for exactly this.

### Phase 2a — GPT INDEPENDENT ANALYSIS

**GPT input:** the RAW TRADING LOG only. Not Kai's analysis.

GPT must answer WITHOUT seeing Kai's work:

```
G1: ENTRY QUALITY — prices improving or degrading through the session?
    Plot entry prices chronologically. Is the bot chasing worse entries after losses?
    (Tilt detection)

G2: RISK CONCENTRATION — % of total risk in the top 3 trades?
    Could one bad candle wipe the day's gains?

G3: STRATEGY EDGE — net P&L per contract risked, per strategy.
    Which strategies have real edge vs volume churn?

G4: HARVEST EFFICIENCY — % of max theoretical profit captured?
    Are harvests firing at the right moment?

G5: STOP QUALITY — for each stop: signal or noise?
    Would a different threshold have saved the trade?

G6: PHANTOM SEPARATION — exclude phantom positions entirely.
    Is the bot actually profitable on real fills only?

G7: TIMING PATTERNS — which windows are +EV vs −EV?

G8: CRITICAL FINDING — the ONE most justified next step for the business.
    Priority hierarchy (must follow this order):
    (1) Runtime correctness fix
    (2) Instrumentation gap
    (3) Execution-layer fix
    (4) Family/session-scoped fix
    (5) Threshold/parameter change (LAST resort, only after 1–4 are clean)
    "Monitor more" is not a finding. Specific action required.
```

Output: `agents/aether/analysis/GPT_Independent_YYYY-MM-DD.txt`

### Phase 2b — GPT COMPARATIVE REVIEW

**GPT input:** Kai's primary analysis + GPT's Phase 2a findings (both)

```
G9:  What did Kai MISS that GPT found independently?
G10: What did Kai get WRONG? (specific: math errors, wrong expiry prices,
     overclaims, misidentified mechanisms)
G11: For each of Kai's strategy recommendations: AGREE or OVERRIDE?
     Override requires specific alternative evidence — not just disagreement.
G12: RISK SCENARIO — what would today look like with 2% adverse BTC?
G13: ACTION CLASSIFICATION — for each finding, tag as one of:
     runtime correctness fix | instrumentation | execution-layer fix |
     stop/risk engine fix | entry-engine fix | session/regime handling | no change
     Then classify: build now / monitor / revisit later / do not change
G14: DAY GRADE — A/B/C/D/F with exactly 2-sentence justification
G15: CRITICAL RECOMMENDATION — single most justified next step using the
     priority hierarchy (correctness > execution > instrumentation >
     family-scoped > parameter change)
     Format must be one of:
     BUILD vXXX (exact changes + evidence + risk of waiting)
     COLLECT MORE DATA (what events + how many sessions)
     MONITOR AND HOLD (what's uncertain + specific trigger for next decision)
```

Output: `agents/aether/analysis/GPT_CrossCheck_YYYY-MM-DD.txt`

### How to run:
```bash
cd ~/Documents/Projects/Hyo/agents/aether/analysis
python3 gpt_crosscheck.py YYYY-MM-DD
```
This runs both phases automatically. Read BOTH output files before writing synthesis.

---

## PART 4 — FINAL SYNTHESIS (PHASE 3)

Read both GPT phase outputs. Then answer these decision questions:

```
C1: Did GPT find a factual error in the primary analysis?
    YES → correct it. Log the correction in the GPT CRITIQUE section.
    NO  → note agreement.

C2: Did GPT find a pattern the primary analysis missed?
    YES → is it actionable? Does it change the recommendation?

C3: Did GPT disagree with a strategy recommendation?
    YES → who has better evidence? Adopt the stronger position.
          Do not average two positions. Take the one with better data.

C4: Did GPT's risk scenario reveal exposure not quantified in primary?
    YES → update risk assessment

C5: What is GPT's day grade? Does the primary analysis agree?
    If they differ by 2+ grades → investigate before publishing.
    Something is fundamentally different in how the data is being read.
```

Then answer the FINAL OUTPUT questions:

```
F1: THE ONE most justified next step for the business?
    Must be specific. Must follow priority hierarchy.
    "Monitor more" is invalid. "Tighten threshold X" is only valid after
    correctness, execution, instrumentation, and family-scoped fixes are clean.
    Required format: BUILD / COLLECT MORE DATA / MONITOR AND HOLD (see Part 6)

F2: The ONE thing that went best today that must be PROTECTED?
    Don't accidentally break what's working while fixing what isn't.

F3: Any HALT conditions met?
    - Phantom gap > $10 and increasing
    - Drawdown > 15% in single session
    - Same P0 issue recurring 3+ sessions with no fix deployed
    If YES → recommend HALT. Specify the exact conditions to resume trading.

F4: What data do we need TOMORROW that we don't have today?
    This determines what to instrument before the next session.

F5: If Hyo reads this and asks "so what?" — the answer in one sentence?
    If you cannot write this sentence, the analysis is not done.
    Find what's missing and write it.
```

---

## PART 5 — REPORT FORMAT SPECIFICATION

### File structure:
```
analysis/Analysis_YYYY-MM-DD.txt
```

### Required section markers (the publish script parses these exactly):
```
=== CLAUDE PRIMARY ANALYSIS ===

[primary analysis — see structure below]

=== GPT CRITIQUE ===

[GPT Phase 2a + 2b content — see structure below]

=== FINAL SYNTHESIS ===

[final synthesis — see structure below]
```

Do not alter these marker strings. The publish script (`aether-publish-analysis.sh`)
uses exact string matching to extract sections.

### TYPOGRAPHY RULES (non-negotiable):

```
ALLOWED:
  - Plain text section labels: "PART 1:", "PART 2:", "BALANCE LEDGER:", "TRADE LEDGER:"
  - Underline dividers: "=================================================================================="
  - Bullet points: "  - item" or "  • item"
  - Inline dashes for trade entries: "  HH:MM  YES @ 0.XX  Nc  WIN  +$X.XX"
  - CAPS for labels: "EU_MORNING", "MODE B", "POS WARNING"
  - Numbered lists for corrections: "1. [text]"

NOT ALLOWED:
  - Markdown headers: # ## ### (the publish script renders these as literal text)
  - Markdown bold/italic: **text** or *text* (renders literally)
  - Markdown tables: | col | col | (renders literally, not as formatted table)
  - Numbered Q-and-A framework per trade: "(1) Was the read correct? (2) ..."
  - Per-trade headers with colons: "Trade 1: PAQ_EARLY_AGG"

Reference the canonical template for correct formatting.
Reference Analysis_2026-04-17.txt for correct published format.
```

---

### PRIMARY ANALYSIS structure:

```
BALANCE LEDGER:
  [Prior date]: $X.XX → $X.XX  net ±$X.XX  (confirmed / UNCONFIRMED)
  [Today date]: $X.XX → $X.XX  net ±$X.XX  (confirmed / UNCONFIRMED)
  [If gap exists: "PHANTOM GAP: $X.XX — all P&L below is UNRELIABLE"]

TRADE LEDGER:
  ★ REQUIRED SECTION — Output from Gate 2. Full accounting of every trade.
  Format: Group by strategy family. For each family:
    [FAMILY NAME]
      HH:MM  YES/NO @ 0.XX  Nc  WIN/LOSS  ±$X.XX  (exit note)
      HH:MM  YES/NO @ 0.XX  Nc  WIN/LOSS  ±$X.XX
      [Family] net:  ±$X.XX  (N trades, NwW/NlL, WR%)
    [NEXT FAMILY] ...
    SESSION NET: $X.XX
  Do NOT skip this section. Do not aggregate without individual lines.
  This is Gate 1 + Gate 2 verification in one place.

PART 1: THE REAL STORY
  2–4 paragraphs of mechanism-level narrative.
  What actually happened? What was the defining event?
  For 2-day windows: session comparison table.
  End with: what NOT to do in response to this data.

PART 2: IMPORTANT WINDOWS / KEY TRADE ANALYSIS
  For each trade worth interpreting:
  "APR XX HH:MM — [strategy], [side], [outcome]"
  Then 2–4 sentences of mechanism-level analysis.
  NO numbered sub-questions framework (e.g. "(1) Was the read correct?")
  NO per-trade headers with colons.
  Plain timestamped entries in prose.

PART 3: STRATEGY FAMILY PERFORMANCE ([N]-DAY)
  [FAMILY NAME] — N trades, W/L, WR%, net $X.XX
  2–4 sentences: what the data shows, what it means, what not to do.
  Include explicit "Do not touch/gate X" if evidence supports it.

PART 4: EU_MORNING ASSESSMENT (only if EU_MORNING had trades today)
  Split: pre-04:15 vs post-04:15 net P&L
  Evidence count update for Issue #4.

PART 5: STOP AND HARVEST EVENTS
  5.1 MODE B INSTANCES (each with: int_bdi, anchor_depth, ABSENT confirmation)
  5.2 POS WARNING EVENTS (each with: context entry vs exit, seconds_left)
  5.3 BDI=0 TIME GATE STATUS (Issue #2 evidence: ≤120s events)

SESSION NET TABLE:
  ★ REQUIRED — must appear as standalone block at the END of PRIMARY ANALYSIS
  EU_MORNING    $X.XX
  ASIA_OPEN     $X.XX
  NY_PRIME      $X.XX
  EVENING       $X.XX
  SESSION TOTAL $X.XX

  2-DAY ANALYSIS FORMAT: If today's log was sparse and yesterday's log was
  used, the SESSION NET TABLE shows BOTH days with a combined total:
    EU_MORNING    Apr-N: $X.XX  /  Apr-N+1: $X.XX  =  $X.XX (2-day)
    ASIA_OPEN     Apr-N: $X.XX  /  Apr-N+1: $X.XX  =  $X.XX (2-day)
    NY_PRIME      Apr-N: $X.XX  /  Apr-N+1: $X.XX  =  $X.XX (2-day)
    EVENING       Apr-N: $X.XX  /  Apr-N+1: $X.XX  =  $X.XX (2-day)
    2-DAY TOTAL:  $X.XX
  When writing narrative in PART 1 and PART 2, it is acceptable to discuss
  both days inline. The standalone SESSION NET TABLE still must appear at the
  end. Do not embed the table only in the PART 1 narrative — it must also
  exist as the final standalone block before the GPT CRITIQUE marker.
```

---

### GPT CRITIQUE structure:

★ IMPORTANT: The GPT CRITIQUE section is Kai's SYNTHESIS of GPT's findings — NOT
a copy-paste of GPT's output. GPT produces raw analysis files. Kai reads both files
and writes a structured summary in the format below. If you paste GPT's numbered
list directly into this section, you have failed. Synthesize, don't dump.

```
VERDICT: [1-sentence summary of GPT's overall judgment on the primary analysis]

CORRECTIONS APPLIED:
1. [Specific factual error found, with evidence from raw log]
2. [Another correction if applicable]
[If no corrections: "No factual errors found — primary analysis confirmed."]

CONFIRMED CORRECT:
- [What GPT independently confirmed as accurate]
- [Another confirmation]

DISCIPLINE GPT APPLIED:
[1–2 sentences: what standard GPT held the analysis to, and why it matters]
```

---

### FINAL SYNTHESIS structure:

```
[1 executive paragraph: AetherBot's edge status today, plain language]

CONFIRMED v[XXX] SCOPE:
  — or —
RECOMMENDATION: BUILD v[XXX] / COLLECT MORE DATA / MONITOR AND HOLD
[numbered list of confirmed scope items with specific evidence]

MONITOR — not build-ready:
- [items needing more data — specific what's needed + how many sessions]

DO NOT CHANGE:
- [what must not be touched + specific reason backed by data]

NEXT DECISION POINT:
"[The specific question whose answer determines the next action]"
→ YES: [what happens]
→ NO: [what happens]

LEDGER NOTE:
[Today's EOD: confirmed or UNCONFIRMED — verify Kalshi app]
```

---

## PART 6 — THE ONE RECOMMENDATION FORMAT

Every analysis ends with exactly one recommendation. No multiple recommendations.
No hedging. No "we might consider." Take a position.

```
RECOMMENDATION: BUILD v[XXX]
What changes: [exact description — function name, logic change, not "improve X"]
Why now: [specific log evidence — timestamps, trade IDs, dollar amounts]
Risk if we wait: [dollar amount lost per session by not acting]

  ★ INSTRUMENTATION BUILDS: When the build is logging/diagnostics only
  (not a direct P&L improvement), state the risk differently:
  Risk if we wait: [N sessions of continued Mode B/POS WARNING without
  root cause. Est. $X.XX/session in unresolved mechanism failures.]
  Example: "Risk if we wait: 2–3 more sessions of harvest failures at
  ~$0.50–$1.00/session cost before Mode B root cause is confirmed."
```

```
RECOMMENDATION: COLLECT MORE DATA
What we need: [specific event types — e.g., "3 more BDI=0 holds with ≤120s
              remaining in EVENING window" — not "more sessions"]
How many sessions: [exact number]
What to watch for: [exact log pattern that triggers the build decision]
```

```
RECOMMENDATION: MONITOR AND HOLD
What's stable: [specific strategies/mechanisms working — must protect these]
What's uncertain: [what needs more data — why is it uncertain?]
Next trigger: [the specific event or count that moves this to BUILD or COLLECT]
```

**Invalid recommendations — never write:**
- "We should consider improving the harvest logic."
- "It might be worth looking at..."
- "The strategy seems to be degrading."
- "We could tighten the threshold."
- "Let's keep watching."

---

## PART 7 — ANALYSIS DEPTH STANDARD AND PHILOSOPHICAL ORIENTATION

★ GPT COUNTERPART NOTE (2026-04-18): An agent running the 7 gates mechanically will
produce a complete checklist-passing report and still answer the wrong question when
something genuinely ambiguous comes up. The philosophy below is what prevents that.
It is embedded here — not referenced elsewhere — because the prior version required
reading 3 external files to get it. That is a single point of failure. This is the fix.

---

### PHILOSOPHY — HOW TO THINK ABOUT AETHERBOT (from ANALYSIS_BRIEFING.txt Sections 4-7)

THE CORE MANDATE:
Every market situation and environment is a potential opportunity.
Not entering a trade is not inherently safe. Missed wins are a real cost,
tracked on the same ledger as losses. "Working as designed" is the floor, not
the ceiling. The goal is to find opportunities, not to reduce exposure.

No build ships without log evidence.
No gate is added, removed, or tightened based on theory alone.
No strategy is killed without exhausting session/environment segmentation first.

If you see a loss pattern, the first question is ALWAYS:
  "Which session window and market regime is this happening in?"
  NOT: "Should we remove this strategy?"

SEQUENCE OF PRIORITIES (when multiple problems exist, work in this order):
  FIRST:  Runtime correctness bugs (stale state, wrong exit paths, NameErrors)
  SECOND: Execution layer problems (harvest path, order placement, exchange response)
  THIRD:  Strategy gates (entry conditions, session windows, risk sizing)
  FOURTH: Performance optimization (fine-tuning working strategies)
Do not evaluate strategy questions while execution bugs are open.
A strategy cannot be evaluated if the execution layer is broken.

THE KILL DECISION STANDARD:
A strategy qualifies for killing/deletion only when ALL of the following are true:
  (a) Evaluated across at least 3 distinct session types (EU_MORNING, OVERNIGHT, NY_PRIME)
  (b) No session or regime shows positive EV
  (c) Losses are NOT explainable by an execution bug or wrong configuration
      (the strategy logic itself is flawed — not just misconfigured)
  (d) There is no substitute covering the opportunities it was designed for
  (e) Hyo has explicitly approved the decision

Before recommending kill, always check in order:
  1. Session gating — restrict to windows where it wins
  2. Regime gating — add BDI/ABS/PAQ condition filtering losing environments
  3. Risk reduction — reduce to $3-5 while gathering more data
  4. Dormancy — set inactive for 7 days and re-evaluate
Dormancy is preferable to deletion while the dataset is small.
"PAQ_STRUCT_GATE is 33% WR over 3 sessions" → DOES NOT MEET THE KILL BAR.
The answer is: segment by session window first. Gate only the losing environments.

THE PATCHWORK TEST (run this before recommending any build):
  - Is this fix addressing the root cause or just blocking the symptom?
  - How many trades in the last 10 sessions would this gate have fired on?
    If < 3: it's a reaction to noise, not a real pattern.
  - Does this new condition interact with any existing condition in an unintended way?
  - If we removed this condition in 30 days, would anyone notice?
    YES → might be real. NO → it's noise. Don't add it.

PATCHWORK EXAMPLE (from real history — what not to do):
  Problem: Harvest orders not firing even when BDI is high.
  Patchwork response: Lower the BDI threshold. Add time-based harvest.
                      Force exit after N seconds if no harvest fires.
  Root cause: _ob_parsed inside execute_partial_harvest is empty because
              all prices are filtered by held_px ±0.05 gate. The book is
              there — the filter is discarding it.
  Correct fix: Gate on anchor ±0.02 depth, not held_px ±0.05.
The patchwork response would have added code on top of a broken filter.
The correct fix repairs the filter itself. Every patchwork fix deferred is a
root cause fix that still needs to be written later — but now on top of more code.

Surface patchwork concerns explicitly in every analysis where a new gate is proposed.
Always ask: "Is this fixing the mechanism or masking the symptom?"

---

### DEPTH STANDARD — OBSERVATION vs MECHANISM

Every observation must reach mechanism level before it is surfaced.

**OBSERVATION LEVEL — WRONG:**
> "There were losses in EVENING on April 16."

**MECHANISM LEVEL — RIGHT:**
> "All four EVENING losses on Apr 16 are bps_premium NO positions entered
> between 19:45 and 21:15 MT. BTC moved from 74,750 to 74,800+ directionally
> against NO positions during this window. The same families in the same window
> produced +$5.14 on Apr 17 when BTC was stable at 77,000–77,500. This is
> one session of regime-driven losses, not a strategy failure. No gates should
> change. Track BTC spot direction at EVENING entry vs settlement for the next
> 3 sessions before drawing any conclusion."

**The test:** Can you name (a) the specific trades, (b) the specific mechanism,
(c) what specifically would change if you acted? If not — go deeper.

---

## PART 8 — ANTI-PATTERNS

| Pattern | Example | Why it's wrong |
|---|---|---|
| Reporting claimed P&L as real | "Bot made +$24 today" | Gate 1 required first |
| WR without edge-per-contract | "80% WR, great strategy!" | May be losing money |
| Missing day-carrier trade | Treating +$1.50 day as solid | Q5.2: >50% from one trade = lucky |
| GPT doing arithmetic | "Your balance was $X" | GPT must catch what Kai missed |
| Publishing without checklist | "Should be fine" | Part 9 is not optional |
| Multiple recommendations | "First... also..." | One recommendation only |
| "Monitor more" as recommendation | "Let's keep watching" | F1 requires specific action |
| Numbered trade framework | "(1) Was the read correct?" | Explicitly rejected by Hyo |
| Observation-level EVENING analysis | "Losses in EVENING" | BTC regime check first |
| Overclaiming without expiry check | "Stolen winner at 09:33" | Check expiry price in raw log |
| Markdown in published analysis | ## headers, **bold**, \| tables | Renders as literal text; use plain text only |
| GPT output dumped into critique | Numbered list of GPT's 8 points | Synthesize into VERDICT/CORRECTIONS/CONFIRMED/DISCIPLINE |

---

## PART 9 — COMPLETION CHECKLIST

**Run before publishing. Every item must pass. If any fails — fix, then recheck.**

```
SECTION INTEGRITY
[ ] S1: Report has all three section markers (exactly):
        "=== CLAUDE PRIMARY ANALYSIS ===", "=== GPT CRITIQUE ===",
        "=== FINAL SYNTHESIS ==="
[ ] S2: PRIMARY ANALYSIS contains: balance ledger, TRADE LEDGER, Parts 1–5,
        session net table (standalone at end — not just embedded in narrative)
[ ] S3: GPT CRITIQUE contains: verdict, corrections applied, confirmed correct,
        discipline applied
[ ] S4: FINAL SYNTHESIS ends with ONE recommendation in the exact 3-field format
        Must use label "RECOMMENDATION: BUILD/COLLECT/MONITOR" — not "CONFIRMED SCOPE"
        or "DIRECTION FORWARD" or any other variant
[ ] S5: Recommendation has: specific code/event changes, specific log evidence
        (timestamps + dollar amounts), specific risk of inaction
        Instrumentation builds: risk stated as sessions × estimated mechanism cost

DATA INTEGRITY
[ ] D1: Gate 1 answered: first balance, last balance, net, gap check
[ ] D2: If phantom gap > $5 — all P&L figures are labeled UNRELIABLE
[ ] D3: Every strategy-table trade is accounted for in the ledger
[ ] D4: EOD balance labeled UNCONFIRMED if not yet verified against Kalshi
[ ] D5: All timestamps are MT (not UTC)

DEPTH STANDARD
[ ] D6: PART 1 reaches mechanism level (not observation level)
[ ] D7: For every EVENING loss — BTC regime assessed before any strategy conclusion
[ ] D8: Every strategy recommendation backed by specific log evidence
[ ] D9: Mode B harvest misses separated from Mode A in Gate 6 output
[ ] D10: Each POS WARNING event classified (entry vs exit context)

GPT PIPELINE
[ ] G1: GPT_Independent_YYYY-MM-DD.txt exists with substantive Phase 2a content
[ ] G2: GPT_CrossCheck_YYYY-MM-DD.txt exists with substantive Phase 2b content
[ ] G3: GPT CRITIQUE section includes any corrections GPT applied
[ ] G4: Kai responded to every GPT correction — agree or disagree with evidence
[ ] G5: If GPT found a factual error — it is corrected in primary analysis

PUBLISHING
[ ] P1: Analysis file at: agents/aether/analysis/Analysis_YYYY-MM-DD.txt
[ ] P2: aether-publish-analysis.sh run for this date
[ ] P3: feed.json contains entry with id "aether-analysis-YYYY-MM-DD"
[ ] P4: Entry present in BOTH paths:
        agents/sam/website/data/feed.json AND website/data/feed.json
[ ] P5: Vercel deploy confirmed live (fetch the URL, not just "should work")
[ ] P6: Commit pushed to origin main (not just committed locally)
[ ] P7: aether-metrics.json updated with today's confirmed EOD balance
[ ] P8: Feed entry title reflects correct date range and net P&L
        For 2-day analyses: title must show "Apr N-N+1" and 2-day net
        For single-day: title must show correct day's net (not prior day's)
        Verify by reading the title from the feed entry after publish

OPEN ISSUES UPDATE
[ ] I1: KNOWLEDGE.md balance ledger updated with today's confirmed EOD
[ ] I2: Each of the 5 open issues — today's evidence noted
[ ] I3: Any issue with closure evidence — flagged for Kai decision

FINAL GATE
[ ] FINAL: F5 answered — "If Hyo asks 'so what?' the answer is: ___________"
           If you cannot complete that sentence — the analysis is not done.
```

---

## PART 10 — FAILURE MODES AND RECOVERY

**Sparse log (< 100 lines):**
Use yesterday's log. Label with the correct date. run_analysis.sh handles this
automatically (sparse log gate, lines 96–121).

**GPT API failure:**
Label GPT sections as "GPT_VERIFIED: FAILED — [error detail]". Publish primary
analysis with the gap noted. File P1 ticket to rerun. Do not silently skip.

**Phantom gap > $10:**
Gate 1 fails. Analysis headline = "phantom gap of $X — investigation required."
Do not proceed to strategy analysis until gap is explained or labeled as unknown.

**Trade outcome contradicts narrative:**
STOP. Re-read raw log for that trade's full sequence. Verify the contract price
at expiry. Never claim "stolen winner" without checking the expiry price in raw log.
(This mistake was made on Apr 17 09:33 — expiry price was 0.001, resolved NO.)

**Same window appears negative two days in a row:**
Before any recommendation: check BTC spot direction at entry vs settlement on
both days. If directional pattern matches both days → regime event. If no pattern
→ structural problem. Only structural problems lead to gate changes.

**More than 3 consecutive sessions: same P0 issue with no fix deployed:**
Activate HALT condition (F3). Recommend pausing trading until fix ships.

**2-day analysis: feed entry title shows wrong P&L (FIXED in v2.2):**
Root cause: publish script used re.search (FIRST balance match = Day 1). Fixed in v2.3
to re.findall[-1] (LAST match = most recent day). No manual patching required.
If title still looks wrong: check that the FINAL SYNTHESIS has an explicit session balance
line (e.g. "$114.33 → $115.19") that is the LAST such line in the file.
(First logged 2026-04-18. Fixed in aether-publish-analysis.sh.)

**SE-AETHER-001: Dollar sign corruption when manually patching titles via bash:**
NEVER manually set dollar amounts in bash-interpolated strings passed to scripts.
`$0.97` in a double-quoted bash string expands `$0` to the script/program name (e.g. "bash"),
producing "bash.97" on the live site. If a manual title patch is absolutely required:
  python3 - <<'PYEOF'
  import json
  correct_title = "AetherBot Daily Analysis — Apr 16-17 (-$0.97 2-day | Apr 17 +$0.86)"
  for p in ["agents/sam/website/data/feed.json", "website/data/feed.json"]:
      d = json.load(open(p))
      for r in d["reports"]:
          if r["id"] == "aether-analysis-YYYY-MM-DD":
              r["title"] = correct_title
      json.dump(d, open(p,"w"), indent=2)
  PYEOF
Use a Python heredoc with single-quoted <<'PYEOF' so bash cannot expand anything inside.
(Logged 2026-04-18 from GPT counterpart review. SE-AETHER-001.)

**SE-AETHER-002: GPT crosscheck reads Aether runner log instead of AetherBot trading log:**
CRITICAL — this is the most dangerous failure mode. The fallback logs directory
(agents/aether/logs/) contains TWO types of files:
  - aether-YYYY-MM-DD.log → Aether RUNNER log (cron/self-review daemon output, NO trade data)
  - AetherBot_YYYY-MM-DD.txt → AetherBot TRADING log (PRIMARY, only on Mini)
Pattern `*{date}*.log` in the fallback matches the runner log. GPT receives 1K lines of
metrics/self-review output, sees "4 trades" from the 00:15 metrics cycle, and reports
"NY_PRIME: No trades recorded" and "EVENING: No trades recorded" — factually wrong.
This produces false confidence: a GPT crosscheck on half the data is worse than no check.

FIX (deployed v2.3): gpt_crosscheck.py now has a trading log validation gate. If the
found log has < 5 lines containing KXBTC15M/PAQ_/BDI=/TICKER CLOSE, it refuses to run
and prints the correct command for running on the Mini.

GATE QUESTION: Before running gpt_crosscheck.py, answer: "Is this running on the Mini
where ~/Documents/Projects/AetherBot/Logs/ exists?" If NO → run via kai exec.
  kai exec "python3 ~/Documents/Projects/Hyo/agents/aether/analysis/gpt_crosscheck.py YYYY-MM-DD"
(Logged 2026-04-18 from GPT counterpart review. SE-AETHER-002.)

**SE-AETHER-003: Published analysis only references old version without stating current:**
Every published analysis must state the current deployed bot version explicitly. If the
analysis discusses historical context (e.g., "v247 containment fix"), it must also state:
"Current deployed version: v253" in the report header or balance section. A report that
only says "v247 is live-confirmed" looks like a stale template to any reader and erodes
trust in the data quality.
Gate in aether-publish-analysis.sh (v2.3): version reference gate logs a WARNING if the
highest version referenced in the analysis is more than 5 builds behind the configured
CURRENT_VERSION constant. Update that constant when a new version deploys.
(Logged 2026-04-18 from GPT counterpart review. SE-AETHER-003.)

---

## PART 11 — REFERENCE PATHS

```
This protocol:          agents/aether/PROTOCOL_DAILY_ANALYSIS.md (here)
Gold standard:          agents/aether/analysis/CANONICAL_ANALYSIS_TEMPLATE.txt
Operating manual:       agents/aether/docs/ANALYSIS_BRIEFING.txt
7-gate algorithm:       agents/aether/ANALYSIS_ALGORITHM.md
Operating doctrine:     agents/aether/docs/PRE_ANALYSIS_BRIEF.md
Permanent knowledge:    kai/memory/KNOWLEDGE.md
Hyo communication:      kai/memory/TACIT.md
Deep protocol:          agents/aether/AETHER_OPERATIONS.md
GPT pipeline:           agents/aether/analysis/gpt_crosscheck.py
Publish script:         bin/aether-publish-analysis.sh
Run script:             agents/aether/analysis/run_analysis.sh
v254 build spec:        agents/aether/analysis/v254_Build_Spec.md
```

---

## PART 12 — SESSION EXECUTION SEQUENCE (3 PHASES)

The pipeline has three hard phases. Do not start Phase 3 without Phase 2 exit code 0.
"Should work" is never verification. Every step ends with a specific observable outcome.

---

### PHASE 1: ANALYSIS
*Exit condition: Analysis_YYYY-MM-DD.txt exists, all 3 section markers present,
GPT_Review_DATE.txt and GPT_Independent_DATE.txt exist with substantive content.*

```bash
DATE=$(TZ=America/Denver date +%Y-%m-%d)

# Step 1: Confirm trading log exists and has real data
LOG="$HOME/Documents/Projects/AetherBot/Logs/AetherBot_${DATE}.txt"
wc -l "$LOG"
# Must be ≥1000 lines with ≥15 TICKER CLOSE events. If not, use yesterday's.
grep -c "TICKER CLOSE" "$LOG"

# Step 2: Read KNOWLEDGE.md for balance ledger and open issues
grep -A 20 "BALANCE LEDGER" ~/Documents/Projects/Hyo/kai/memory/KNOWLEDGE.md
grep -A 30 "Open AetherBot issues" ~/Documents/Projects/Hyo/kai/memory/KNOWLEDGE.md

# Step 3: Run GPT dual-phase BEFORE writing primary analysis
# Must run on Mini — trading log lives at ~/Documents/Projects/AetherBot/Logs/
cd ~/Documents/Projects/Hyo/agents/aether/analysis
python3 gpt_crosscheck.py "$DATE"

# Step 4: Read GPT outputs — understand what GPT found before writing analysis
cat "GPT_Independent_${DATE}.txt"
cat "GPT_Review_${DATE}.txt"

# Step 5: Write Analysis_YYYY-MM-DD.txt
# Required: 3 section markers, trade ledger, GPT synthesis with responses
# Template: CANONICAL_ANALYSIS_TEMPLATE.txt (data depth)
# Structure: Part 5 of this protocol (published format)
```

---

### PHASE 2: QUALITY GATE
*Exit condition: python3 bin/analysis-gate.py returns exit code 0.*
*DO NOT PROCEED TO PHASE 3 WITHOUT EXIT CODE 0.*

```bash
cd ~/Documents/Projects/Hyo
python3 bin/analysis-gate.py "$DATE" "agents/aether/analysis/Analysis_${DATE}.txt"

# If exit code 1: the specific failure is printed. Fix it. Re-run gate.
# If exit code 0: "ALL 6 GATES PASSED — cleared for publishing" → proceed.
```

The 6 gates and what they catch:
- Gate 1: bash/dollar corruption in title or balance (SE-AETHER-001)
- Gate 2: trading log is real AetherBot log, not runner log (SE-AETHER-002)
- Gate 3: all 3 required section markers present
- Gate 4: GPT CRITIQUE is a synthesis, not a raw dump
- Gate 5: version references not stale (SE-AETHER-003)
- Gate 6: trade breakdown has actual data

---

### PHASE 3: PUBLISHING
*Only enters after Phase 2 exit code 0. Publish script calls gate internally.*
*Exit condition: live URL returns feed entry with clean title, trades, GPT sections.*

```bash
# Step 5.5: VERIFY THE ARCHIVE — confirm the canonical record is in place BEFORE publishing
# Canonical analysis archive: agents/aether/analysis/Analysis_YYYY-MM-DD.txt
# This is the permanent record. Every analysis must be here before it reaches the feed.
ARCHIVE_FILE="agents/aether/analysis/Analysis_${DATE}.txt"
if [[ ! -f "$ARCHIVE_FILE" ]]; then
  echo "ARCHIVE MISSING: $ARCHIVE_FILE not found — do NOT proceed to publish"
  echo "Check: ~/Documents/Projects/AetherBot/Kai analysis/Analysis_${DATE}.txt"
  echo "Copy with: cp \"~/Documents/Projects/AetherBot/Kai analysis/Analysis_${DATE}.txt\" $ARCHIVE_FILE"
  exit 1
fi

# GPT output files are also part of the archive record:
#   agents/aether/analysis/GPT_Independent_YYYY-MM-DD.txt  ← Phase 1 GPT output
#   agents/aether/analysis/GPT_Review_YYYY-MM-DD.txt       ← Phase 2 GPT output
# These are committed in Step 7 along with the main analysis.

# Step 6: Publish (gate runs again internally as hard block)
cd ~/Documents/Projects/Hyo
bash bin/aether-publish-analysis.sh "$DATE" \
  "agents/aether/analysis/Analysis_${DATE}.txt"

# Step 7: DUAL-PATH commit (DUAL-PATH GATE will block if mirror not staged)
git add "agents/aether/analysis/Analysis_${DATE}.txt" \
        "agents/aether/analysis/GPT_Independent_${DATE}.txt" \
        "agents/aether/analysis/GPT_Review_${DATE}.txt" \
        agents/sam/website/data/feed.json \
        website/data/feed.json \
        agents/sam/website/data/aether-metrics.json \
        website/data/aether-metrics.json
git commit -m "aether: daily analysis ${DATE}"
git push origin main

# Step 8: Post-publish verification — VERIFY THESE FOUR THINGS IN THE LIVE FEED
# Fetch the live feed entry and confirm ALL FOUR pass:
curl -sL "https://hyo.world/data/feed.json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
e = next((r for r in d['reports'] if r['date'] == '${DATE}'), None)
if not e:
    print('FAIL: entry not in live feed'); sys.exit(1)
s = e.get('sections', {})

# a. Title has no bash corruption and shows correct P&L
assert 'bash.' not in e.get('title',''), f'FAIL a: bash corruption in title: {e[\"title\"]}'
assert any(c in e.get('title','') for c in ['+', '-', '(\$']), f'FAIL a: no P&L in title: {e[\"title\"]}'

# b. Trade Breakdown section has actual trade data (not just the header)
trades = s.get('trades', '')
assert len(trades) > 100, f'FAIL b: trade section too short ({len(trades)} chars)'
assert 'STRATEGY FAMILY' in trades or 'trades,' in trades or 'WR' in trades, 'FAIL b: no trade data'

# c. GPT section starts with synthesis, not raw dump
gpt = s.get('gptReview', s.get('gptIndependent', ''))
assert not gpt.strip().startswith('PART 1:'), 'FAIL c: GPT section is a raw dump'
assert any(x in gpt for x in ['MATH VERIFICATION','VERDICT:','COMPARATIVE REVIEW','KAI']), 'FAIL c: GPT section lacks synthesis'

# d. Version referenced is not stale
import re
refs = [int(m) for m in re.findall(r'v(\d{3})', json.dumps(e)) if 200 <= int(m) <= 999]
if refs: assert max(refs) >= 248, f'FAIL d: stale version ref v{max(refs)}'

print('PASS a: title clean —', e['title'])
print('PASS b: trade section has data —', len(trades), 'chars')
print('PASS c: GPT section is a synthesis')
print('PASS d: version refs OK —', refs)
print()
print('POST-PUBLISH VERIFICATION: ALL 4 PASS')
"

# If any FAIL: file a ticket against the gate script. Fix the gate. Republish.
# A post-publish failure means the gate had a gap — fix the gate, not just the report.
```

---

## PART 13 — SIMULATION RESULTS

**Simulation run: 2026-04-18 | Analyses checked: Apr 14, 15, 16, 17**

Each analysis was checked against the Part 9 completion checklist (35 items).
Results document which items pass/fail and what drove protocol updates.

```
ANALYSIS: Apr 14 (Analysis_2026-04-14.txt)
  S1: FAIL — section labels are "KAI'S ANALYSIS" / "GPT'S ANALYSIS" not protocol markers
  S2: PARTIAL — has trade ledger but no standalone session net table
  S4: PASS — has MONITOR AND HOLD recommendation with 3 fields
  D1: PASS — Gate 1 answered with balance ledger
  D4: PASS — UNCONFIRMED labeled
  G1/G2: PASS — GPT dual-phase files referenced
  Verdict: Pre-protocol format. Acceptable for archive. Not the active standard.

ANALYSIS: Apr 15 (Analysis_2026-04-15.txt)
  S1: FAIL — has one marker but sparse log made full structure impossible
  D1: FAIL — full balance ledger not established (sparse log: EVENING window only)
  S2: FAIL — no trade ledger (sparse log case)
  Verdict: Sparse log case. Protocol Part 1 B6 covers this — use yesterday's log.
  The failure is the LOG was sparse, not the protocol. No protocol change needed here.

ANALYSIS: Apr 16 (Analysis_2026-04-16.txt)
  S1: FAIL — old markdown format with no protocol markers
  Entire format: FAIL — written in old format before this protocol was created
  Verdict: Pre-protocol. Archived. Not the active standard.

ANALYSIS: Apr 17 (Analysis_2026-04-17.txt)
  S1: PASS — all three section markers present
  S2: FAIL — no TRADE LEDGER section (narrative analysis of selected trades only)
  S4: FAIL — uses "CONFIRMED v254 SCOPE:" not "RECOMMENDATION: BUILD v254"
  D1: PASS — balance ledger with UNCONFIRMED label
  D3: FAIL — no explicit trade-by-trade table to verify against ledger
  D4: PASS — UNCONFIRMED labeled correctly
  D6-D10: PASS — mechanism level, BTC regime assessed, Mode B separated
  G1-G5: PASS — GPT dual-phase applied, corrections documented
  P1-P6: PASS — published, verified, committed
  FINAL: PASS — F5 answered
  Issues found: 4 checklist failures → drove 5 protocol updates in v2.1
```

**Fixes applied to protocol v2.1 based on this simulation:**
1. Added TRADE LEDGER as required section in Part 5 PRIMARY ANALYSIS structure
2. Clarified CANONICAL_ANALYSIS_TEMPLATE vs protocol format conflict (Part 0 note)
3. Added 2-day window SESSION NET TABLE format to Part 5
4. Added instrumentation-build "risk if we wait" format to Part 6
5. Updated S2, S4, S5 checklist items to be more specific

---

**Second simulation pass: Apr 18 analysis vs v2.1 checklist**

```
ANALYSIS: Apr 18 (Analysis_2026-04-18.txt)
  Context: Sparse log — only final tick visible (23:59:58). Correctly handled
  with INSUFFICIENT DATA flags throughout. Analytical reasoning was strong.

  S1: PASS — all three section markers present
  S2: FAIL — no TRADE LEDGER (acceptable for sparse log), but SESSION NET TABLE
      missing as standalone block
  S3: FAIL — GPT CRITIQUE is raw numbered dump from GPT, not structured synthesis
      (VERDICT/CORRECTIONS/CONFIRMED/DISCIPLINE format not followed)
  S4: FAIL — recommendation label is "ONE Final Recommendation" + bold text,
      not "RECOMMENDATION: BUILD v254" in plain text
  S5: FAIL — no "Risk if we wait" dollar/session estimate
  D1: PASS — balance noted as CANNOT BE CALCULATED (correct for sparse log)
  D6: PASS — mechanism-level reasoning about BDI gate and BCDP pattern
  TYPOGRAPHY: FAIL — uses markdown headers (##, ###) and tables throughout
  GPT CRITIQUE FORMAT: FAIL — should be Kai's synthesis, not GPT's raw output
```

**Fixes applied to protocol v2.1 (second pass):**
6. Added GPT CRITIQUE synthesis rule (Gap 8) — not a dump, a synthesis
7. Added TYPOGRAPHY RULES section to Part 5 (Gap 9) — explicit no-markdown rule

**Protocol is now v2.1 with all 9 gaps addressed.**
Next simulation should run against the first analysis written using this protocol.

---

**GPT counterpart verification — v2.3 review (2026-04-18):**

GPT reviewed v2.3 and identified 3 remaining gaps:
  Gap A: Philosophy from ANALYSIS_BRIEFING.txt Sections 4-7 not embedded — referenced only
  Gap B: Balance ledger in Part 1 B3 pointed to KNOWLEDGE.md (frequently stale)
  Gap C: Gate 3 Q3.5 edge-per-contract metric had no worked example or threshold guidance

**Protocol v2.4 applied all three fixes:**
  - Part 7: Full philosophy embedded (opportunity mandate, kill standard, patchwork test)
  - Part 1 B3: Balance ledger embedded with verification step and staleness warning
  - Gate 3 Q3.5: Worked example with real numbers, thresholds, degradation signal pattern

**GPT counterpart final verdict on v2.4:**
  "Yes, with this version an agent starting from zero context can reproduce analysis
   at the gold standard level for the mechanical and philosophical components. This is
   production-ready as a standalone document."

**One remaining non-blocking gap noted:**
  CANONICAL_ANALYSIS_TEMPLATE.txt (FILE 1 in Part 0) is still an external dependency.
  An agent without access to it relies on the Part 7 depth standard examples alone.
  Those examples are good but can't fully substitute for a complete gold standard analysis.
  Assessment: Non-blocking. Protocol is functional without it. The depth standard
  examples in Part 7 provide sufficient orientation for a capable agent.
  Mitigation: If FILE 1 is unavailable, the agent should use Analysis_2026-04-17.txt
  (the most recent full-format analysis) as the practical reference instead.

---

## PART 14 — PROTOCOL UPDATE RULES

This document is only updated by Kai. It grows — it never shrinks requirements.

### MANDATORY: Discrepancy → Ticket → Protocol Update (non-negotiable)

**If ANY discrepancy, bug, or incorrect output is found at ANY point in the pipeline:**

```
1. FILE A TICKET IMMEDIATELY
   bash ~/Documents/Projects/Hyo/bin/ticket.sh \
     --type bug \
     --title "[AETHER-PUBLISH] <description>" \
     --severity P1 \
     --description "<what failed, what the correct behavior is>"

2. FIX THE ISSUE
   Re-run Part 9 checklist. Every item must pass before declaring fixed.

2.5 VERIFY THE FIX WORKS (mandatory — skipping this is how "fixed" bugs recur)
   After applying the fix, run a test publish using a prior analysis file:
     python3 bin/analysis-gate.py <date> agents/aether/analysis/Analysis_<date>.txt
   Then run the full publish against a recent analysis:
     bash bin/aether-publish-analysis.sh <date> agents/aether/analysis/Analysis_<date>.txt
   Confirm the SPECIFIC failure does NOT recur.
   If it does: the fix is incomplete. Do NOT bump the version. File a follow-up ticket.
   Only bump the version AFTER the gate passes on a real publish run.

   SE-AETHER-001 and SE-AETHER-002 were both documented as "fixed" in v2.3.
   Neither was actually fixed. This step was added because v2.3 bumped the
   version without running a verification publish. That mistake produced the
   bash.97 title and 506-line GPT review that Hyo saw in the Apr 17 report.
   Never document a fix as done until the gate confirms it.

3. UPDATE THIS PROTOCOL
   Add the failure to Part 10 (if a new failure mode).
   Add the anti-pattern to Part 8 (if a new class of error).
   Add/update checklist item in Part 9 (if the checklist would have caught it).
   Add gate check to bin/analysis-gate.py (if a mechanical check is possible).
   Add simulation results to Part 13 (if tested against existing analyses).
   Bump the VERSION number above.

4. COMMIT PROTOCOL UPDATE WITH THE FIX
   git add agents/aether/PROTOCOL_DAILY_ANALYSIS.md agents/aether/ANALYSIS_ALGORITHM.md \
           bin/analysis-gate.py
   Include in the SAME commit as the fix — not a separate commit.

The goal: agent starting from zero next session reads this protocol
and cannot make the same mistake. A fix without a verified gate is
a temporary patch. It will recur. This is why we do Step 2.5.
```

### When to update (non-discrepancy):
- A new open issue is confirmed → add to B4 in Part 1
- A new failure mode is discovered → add to Part 10
- Format changes (approved by Hyo) → update Part 5
- Balance ledger changes → update KNOWLEDGE.md (this protocol reads from there)
- A new anti-pattern is observed → add to Part 8
- Simulation run against new analyses → add results to Part 13

When NOT to update:
- To reduce checklist requirements
- To add exceptions to the depth standard
- To remove items from the hydration order

After any update:
1. Bump the VERSION number at the top
2. Note what changed in `agents/aether/evolution.jsonl`
3. Update `agents/aether/ANALYSIS_ALGORITHM.md` if the gate structure changed

---

*This protocol is the single source of truth for AetherBot daily analysis.*
*Any conflict with a prior spec: this document wins.*
*Version 2.5 — 2026-04-18*
*Status: Production-ready with mechanical enforcement.*
*v2.4 was verified by GPT adversarial review (two passes).*
*v2.5 adds bin/analysis-gate.py as a hard block between analysis and publish.*
*Meta-change: protocol now enforces requirements mechanically, not just documents them.*
*Fallback if unavailable: use Analysis_2026-04-17.txt as the practical format reference.*
