# PROTOCOL_AETHER_ISOLATION.md
# Version: 1.0
# Author: Kai
# Date: 2026-04-21
# Status: HARD RULE — NO EXCEPTIONS (Hyo directive 2026-04-21)

---

## PURPOSE

Aether is a special case. AetherBot operates with real money ($90.25 balance, real trades on
Kalshi). Code changes to AetherBot's analysis and trading systems are HIGH RISK. Errors in
AetherBot code are not software bugs — they are financial losses.

"Aether is a special case as it conducts its own daily analysis on AetherBot, which should be
isolated and no changes to the code version should NOT be made outside of the AetherBot daily
analysis. Aether will only identify 'weaknesses' that are external that may affect AetherBot's
performance. Macro, geopolitical, Kalshi disruptions, anything that may affect BTC."
— Hyo, 2026-04-21

---

## ALGORITHM-FIRST: THE AETHER ISOLATION GATE

Run this gate BEFORE ANY action that touches Aether-related files or Aether's scope.

```
AETHER ISOLATION GATE:

GATE 1: Is the proposed change touching AetherBot code?
  → AetherBot code = agents/aether/analysis/*.py, agents/aether/analysis/*.sh,
                     agents/aether/gpt_crosscheck.py, bin/analysis-gate.py,
                     agents/aether/aether.sh (the runner itself),
                     agents/aether/ANALYSIS_ALGORITHM.md, any file that directly
                     changes how AetherBot analyzes or reports
  → YES → STOP. Only Aether's own daily analysis cycle may make these changes.
          If Kai/other agent needs to request a change: open a task ticket for Aether,
          describe the needed change, let Aether's analysis cycle implement it.
  → NO → Continue to GATE 2

GATE 2: Is the proposed change identifying a weakness in Aether's domain?
  → ALLOWED weakness domains for Aether:
    * Macro economic conditions (Fed rates, inflation, recession signals)
    * Geopolitical events (war, sanctions, regulatory actions affecting crypto)
    * Kalshi platform disruptions (downtime, fee changes, rule changes, API changes)
    * Bitcoin/crypto market structure (volatility regime, correlation shifts, BTC dominance)
    * Market microstructure (spread widening, liquidity shifts, order flow changes)
    * Regulatory landscape (SEC/CFTC actions, exchange regulations)
  → NOT ALLOWED (internal AetherBot weaknesses):
    * Code bugs in AetherBot
    * Algorithm parameter tuning
    * Model performance metrics
    * Internal P&L calculation methods
    * Trade entry/exit timing logic
    * Position sizing decisions
  → Internal weakness identified → route to Aether's internal improvement process;
    do NOT surface as a cross-agent concern; Aether owns this
  → External weakness identified → can be researched and reported to Hyo/Aether

GATE 3: Is Kai/other agent being asked to change AetherBot behavior?
  → YES → REFUSE. Write a task ticket describing the needed change.
          Delegate to Aether. Aether decides and implements in its own analysis cycle.
  → NO → Continue

GATE 4: Is this change to Aether's documentation or non-code files?
  → Documentation = PLAYBOOK.md, GROWTH.md, ledger files, log files → ALLOWED
  → Code/protocol = ANALYSIS_ALGORITHM.md, any .py/.sh that runs → ONLY Aether touches
```

---

## SECTION 1: WHAT AETHER OWNS (EXCLUSIVELY)

These files and concerns belong ONLY to Aether. No other agent or Kai modifies them
without explicit Hyo permission or a properly delegated Aether task:

```
AETHER-EXCLUSIVE FILES:
  agents/aether/analysis/*.py              — Python analysis scripts
  agents/aether/analysis/*.sh              — Shell analysis scripts
  agents/aether/ANALYSIS_ALGORITHM.md     — The 7-gate decision tree
  agents/aether/docs/PRE_ANALYSIS_BRIEF.md — Operating doctrine
  agents/aether/docs/ANALYSIS_BRIEFING.txt — 14-section operating manual
  agents/aether/analysis/CANONICAL_ANALYSIS_TEMPLATE.txt — Gold standard
  agents/aether/AETHER_OPERATIONS.md      — 12-step protocol
  agents/aether/analysis/gpt_factcheck.py — GPT cross-check
  bin/analysis-gate.py                    — Quality gate for Aether publishes
  agents/aether/aether.sh                 — The runner (core logic)
```

```
AETHER-EXCLUSIVE CONCERNS (internal):
  - AetherBot version upgrades (v254, v255, etc.)
  - Trade strategy implementation
  - Position sizing algorithms
  - P&L calculation methods
  - Harvest system behavior
  - Stop loss / take profit logic
  - Entry/exit timing
  - Reconciliation between bot positions and Kalshi
```

---

## SECTION 2: AETHER'S FOCUS — EXTERNAL INTELLIGENCE ONLY

When Aether researches "weaknesses," it is ONLY researching external factors that affect
AetherBot's operating environment. Aether is an INTELLIGENCE LAYER for external context,
not an internal code reviewer.

### Aether's Research Domains

**Macro Economics:**
- Federal Reserve monetary policy signals
- Inflation / CPI / PCE data that affects crypto sentiment
- Recession indicators that shift market risk appetite
- Dollar strength (DXY) correlation with BTC

**Geopolitical:**
- Regulatory actions that affect prediction markets (Kalshi specifically)
- Government cryptocurrency bans, restrictions, or endorsements
- Exchange hacks, failures, or collapses (contagion risk)
- War / sanctions that shift global capital flows

**Kalshi Platform:**
- Kalshi rule changes, fee structure changes, new market additions
- Kalshi API availability and stability
- Market maker behavior changes on Kalshi
- Settlement mechanism changes
- Leverage or margin requirement changes

**Bitcoin / Crypto Market Structure:**
- BTC volatility regime changes (low vol → high vol)
- Bitcoin dominance shifts
- Correlation breaks (BTC decoupling from equities)
- On-chain signals (exchange flows, miner behavior, HODLer behavior)
- Major protocol events (halving aftermath, ETF flows)

### What Aether Does NOT Research or Report

- Whether AetherBot's code has bugs (Aether's internal concern)
- Whether Kai/Nel/Ra/Sam/Dex are working correctly
- Infrastructure issues unless they directly impact Kalshi connectivity
- General software engineering practices

---

## SECTION 3: HOW AETHER REPORTS EXTERNAL WEAKNESS

External weaknesses Aether identifies feed into the daily analysis output:

```
In daily analysis (published to HQ as aether-analysis):
Section "external_factors": {
  "macro": "<current macro conditions and BTC implications>",
  "geopolitical": "<active geopolitical risks>",
  "kalshi_platform": "<platform stability assessment>",
  "market_structure": "<BTC/crypto volatility regime>",
  "flags": [
    {
      "severity": "P0|P1|P2",
      "description": "<specific external risk>",
      "implication": "<how this affects AetherBot's operating conditions>",
      "recommended_posture": "PAUSE_TRADING|REDUCE_EXPOSURE|MONITOR|NORMAL"
    }
  ]
}
```

### AetherBot Trading Posture Recommendations

Aether may recommend a posture change based on external factors. ONLY Hyo approves
posture changes that affect live trading.

```
POSTURE DECISION GATE:
[ ] Is there a P0 external risk (regulatory ban, platform outage, BTC crash >20%)? → YES → PAUSE TRADING (auto, no approval needed)
[ ] Is there a P1 external risk (major volatility regime change, geopolitical escalation)? → YES → RECOMMEND pause; Hyo decides
[ ] Is there a P2 risk (elevated uncertainty, macro crosscurrents)? → YES → include in analysis; no posture change
[ ] Is there no significant external risk? → NORMAL posture; continue
```

---

## SECTION 4: HOW OTHER AGENTS INTERACT WITH AETHER

### What Other Agents CAN Do

- **Read** Aether's analysis output (agents/aether/logs/, agents/aether/analysis/)
- **Reference** Aether's external factors in their own work (e.g., Nel checking if macro conditions affect security posture)
- **Open a task ticket** for Aether describing a needed change → Aether implements
- **Publish** Aether's analysis to HQ feed after quality gate passes (via aether.sh)

### What Other Agents CANNOT Do

- Modify any Aether-exclusive file directly
- Implement changes to AetherBot behavior on Aether's behalf
- Override Aether's analysis conclusions (even if Kai disagrees)
- Cancel or override AetherBot trades or positions
- Change AetherBot's running version outside of Aether's own deployment cycle

### What Kai CAN Do

- Review Aether's daily analysis for completeness (using PROTOCOL_DAILY_ANALYSIS.md gates)
- Flag gaps in Aether's external factor coverage (open task ticket for Aether)
- Escalate P0 external risks to Hyo immediately
- Coordinate with Aether on cross-agent dependencies (e.g., Sam's API health affects Aether's HQ dashboard)
- Gate: DOES the analysis meet the quality standard? → if NO → open ticket for Aether to fix

### What Kai CANNOT Do

- Implement changes to AetherBot analysis logic
- Update Aether's ANALYSIS_ALGORITHM.md without Aether's review
- Override Aether's 7-gate analysis decisions
- Deploy new AetherBot versions

---

## SECTION 5: AETHER GROWTH.MD — SCOPE CORRECTION

Aether's GROWTH.md weaknesses must ONLY be external factors. Internal AetherBot issues
(phantom positions, harvest failure, reconciliation gaps) are tracked in Aether's own
PLAYBOOK.md as "open issues" and resolved through Aether's daily analysis cycle.

### Correct GROWTH.md Weakness Structure for Aether

```
W1: External intelligence gap (example: macro data coverage inadequate)
W2: Market structure signal quality (example: no on-chain data integrated)
W3: Geopolitical risk detection (example: no regulatory monitoring for Kalshi)

NOT in GROWTH.md:
- AetherBot code issues (belong in PLAYBOOK.md "open issues")
- P&L calculation errors (belong in Aether's analysis cycle)
- Position reconciliation (belong in Aether's v255 roadmap)
```

---

## SECTION 6: TRIGGER AND ENFORCEMENT

**Trigger**: This protocol runs as GATE 2 of every Kai session's DELEGATION CHECKLIST when
the task involves Aether.

**Enforcement**:
- Nel's daily audit checks: "Did any non-Aether agent modify Aether-exclusive files?"
  → If YES → P0 flag (code isolation violation; financial risk)
- Dex's staleness check: "Has Aether's ANALYSIS_ALGORITHM.md been modified by a non-Aether commit?"
  → If YES → P1 flag

**Who updates this protocol?**
- Kai updates this protocol when Hyo changes Aether's scope
- Aether cannot unilaterally expand its own scope
- Any scope change requires Hyo approval

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
