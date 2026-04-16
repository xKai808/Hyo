#!/usr/bin/env python3
"""
GPT-4o dual-analysis pipeline for AetherBot daily analysis.

TWO PHASES (both mandatory, cannot skip):
  Phase 1: GPT receives the RAW LOG and writes its OWN independent analysis.
  Phase 2: GPT receives Kai's analysis and fact-checks, agrees/disagrees/pushes back.

GPT forms its own conclusions BEFORE seeing Kai's work.
This prevents confirmation bias and ensures genuine adversarial review.

Outputs:
  GPT_Independent_YYYY-MM-DD.txt  — GPT's own analysis from raw logs
  GPT_Review_YYYY-MM-DD.txt       — GPT's comparative review of Kai's analysis

History:
  v1 (2026-04-14): Single-phase review only. GPT never saw raw logs.
  v2 (2026-04-14): Two-phase pipeline. GPT analyzes raw logs independently first.
  Rewritten because Hyo caught that v1 was a shortcut — GPT was rubber-stamping
  Kai's work instead of forming independent conclusions. Never again.
"""
import json, os, sys, time, urllib.request, urllib.error
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parent.parent.parent.parent  # Hyo/
SECURITY = ROOT / "agents" / "nel" / "security"
ANALYSIS_DIR = Path(__file__).resolve().parent
LOGS_DIR = ROOT / "agents" / "aether" / "logs"

# ── Load OpenAI key ─────────────────────────────────────────────────────────
key = None
key_path = SECURITY / "openai.key"
if key_path.exists():
    key = key_path.read_text().strip()

if not key or "your" in key.lower() or len(key) < 20:
    env_path = Path.home() / "security" / "hyo.env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("OPENAI_API_KEY="):
                key = line.split("=", 1)[1].strip()
                break
    if not key or "your" in key.lower() or len(key) < 20:
        print("ERROR: No valid OpenAI API key found")
        sys.exit(1)

# ── Determine date and find files ───────────────────────────────────────────
date_arg = sys.argv[1] if len(sys.argv) > 1 else datetime.now().strftime("%Y-%m-%d")

analysis_file = ANALYSIS_DIR / f"Analysis_{date_arg}.txt"
if not analysis_file.exists():
    print(f"ERROR: {analysis_file} not found. Write Kai's analysis first.")
    sys.exit(1)

# Find raw log for this date
raw_log = None
raw_log_text = None
for pattern in [f"aether_{date_arg}*.log", f"aetherbot_{date_arg}*.log",
                f"*{date_arg}*.log", f"*{date_arg.replace('-', '')}*.log"]:
    matches = sorted(LOGS_DIR.glob(pattern))
    if matches:
        raw_log = matches[-1]  # Most recent match
        break

if not raw_log:
    # Also check for .txt logs
    for pattern in [f"*{date_arg}*.txt", f"*{date_arg.replace('-', '')}*.txt"]:
        matches = sorted(LOGS_DIR.glob(pattern))
        if matches:
            raw_log = matches[-1]
            break

if raw_log:
    full_log_text = raw_log.read_text()
    raw_log_len = len(full_log_text)

    # GPT-4o TPM limit is 30k tokens (~120k chars). We need room for the prompt
    # and response, so cap raw log at ~60k chars (~15k tokens).
    MAX_LOG_CHARS = 60000

    # Smart truncation: keep lines with trading-relevant keywords
    # The raw log often contains standby/daemon noise between actual trades
    if raw_log_len > MAX_LOG_CHARS:
        trade_keywords = [
            "BUY SNAPSHOT", "SETTLEMENT", "SETTLE", "POS WARNING",
            "HARVEST", "STOP", "CHOP", "TRAIL", "ticker_result",
            "BALANCE", "balance", "NET", "PAQ", "bps_premium",
            "WES_EARLY", "bps_late", "BCDP", "STRUCT_GATE",
            "BDI", "OB_PARSER", "NEW TICKER", "STABILIZ",
            "ENTRY", "EXIT", "FILLED", "expired", "won", "lost"
        ]
        lines = full_log_text.splitlines()
        relevant_lines = []
        for i, line in enumerate(lines):
            if any(kw in line for kw in trade_keywords):
                # Include context: 1 line before and after
                start = max(0, i - 1)
                end = min(len(lines), i + 2)
                for j in range(start, end):
                    if lines[j] not in relevant_lines[-3:] if relevant_lines else True:
                        relevant_lines.append(lines[j])

        filtered = "\n".join(relevant_lines)
        if len(filtered) > MAX_LOG_CHARS:
            filtered = filtered[:MAX_LOG_CHARS] + "\n... [TRUNCATED]"

        raw_log_text = (
            f"[FILTERED LOG — {raw_log_len} chars original, kept {len(filtered)} chars of trade-relevant lines]\n"
            f"[First 20 lines of original log for context:]\n"
            + "\n".join(lines[:20])
            + f"\n\n[Trade-relevant lines below:]\n"
            + filtered
            + f"\n\n[Last 20 lines of original log:]\n"
            + "\n".join(lines[-20:])
        )
        # Final safety cap
        if len(raw_log_text) > MAX_LOG_CHARS + 5000:
            raw_log_text = raw_log_text[:MAX_LOG_CHARS + 5000] + "\n... [HARD TRUNCATED]"
    else:
        raw_log_text = full_log_text
    print(f"Found raw log: {raw_log} ({raw_log_len} chars, sending {len(raw_log_text)} chars)")
else:
    print(f"WARNING: No raw log found for {date_arg} in {LOGS_DIR}")
    print("GPT will not be able to do independent analysis without raw logs.")
    print("Phase 1 will be skipped. Phase 2 (review only) will still run.")
    print("This is a DEGRADED mode — flag it in the report.")

analysis_text = analysis_file.read_text()


def _log_api_usage(provider, model, in_tok, out_tok, notes=""):
    """SE-011-003: Record API usage to kai/ledger/api-usage.jsonl. Non-fatal."""
    try:
        import subprocess, os
        _root = os.environ.get("HYO_ROOT") or os.path.expanduser("~/Documents/Projects/Hyo")
        subprocess.run(
            ["bash", os.path.join(_root, "bin", "api-usage.sh"), "log",
             provider, "aether", model, str(in_tok), str(out_tok), notes],
            check=False, timeout=5, capture_output=True
        )
    except Exception:
        pass


def call_gpt(system_prompt, user_msg, max_tokens=4000):
    """Call GPT-4o and return the response text."""
    payload = {
        "model": "gpt-4o",
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_msg}
        ],
        "temperature": 0.3,
        "max_tokens": max_tokens
    }
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json"
        }
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read())
        try:
            u = result.get("usage", {}) or {}
            _log_api_usage("openai", "gpt-4o",
                           int(u.get("prompt_tokens", 0) or 0),
                           int(u.get("completion_tokens", 0) or 0),
                           "gpt_crosscheck")
        except Exception:
            pass
        return result["choices"][0]["message"]["content"]


# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: GPT INDEPENDENT ANALYSIS (from raw logs only)
# ═══════════════════════════════════════════════════════════════════════════════

phase1_output = None

if raw_log_text:
    print(f"\n{'=' * 70}")
    print(f"PHASE 1: GPT independent analysis from raw logs — {date_arg}")
    print(f"{'=' * 70}")

    phase1_system = """You are GPT-4o, an adversarial trading analyst reviewing a live Kalshi BTC 15-minute binary options bot (KXBTC15M).
You are analyzing the RAW TRADING LOG. You have NOT seen anyone else's analysis. Form your own conclusions.

Context:
- AetherBot trades KXBTC15M (15-min BTC binary options on Kalshi), current version: v253/v254
- Strategies: bps_premium (backbone, high-volume), PAQ_EARLY_AGG (aggressive early entry), PAQ_STRUCT_GATE (low-ABS/deep book lane), bps_late (late-cycle), WES_EARLY (wide-entry-spread), BCDP_FAST_COMMIT (inactive)
- Harvest system: SPHI_DECAY strategy for partial exits before settlement. Harvests sell contracts before expiry to lock partial profit. "DONE" = successful sell, "MISS" = couldn't fill (usually yes_bids:ABSENT — OB parser bug)
- "POS WARNING: API 0 local N" = phantom positions (bot tracks N contracts locally but Kalshi API shows 0). Settlements on phantom positions produce inflated claimed P&L
- Session windows (MTN): OVERNIGHT (00:00-06:00), NY_OPEN (08:00-10:00), NY_PRIME (10:00-13:00), AFTERNOON (13:00-17:00), EVENING (17:00-00:00)

DO NOT just count trades and compare balances. Kai already does that. Your value is ADVERSARIAL INTELLIGENCE — finding what a single-pass analyst misses.

Your job — focus on THESE questions:
1. ENTRY QUALITY: For each strategy, are entry prices improving or degrading over the session? Is the bot chasing worse entries as the day goes on? Calculate average entry price per strategy per session window.
2. RISK CONCENTRATION: Is too much capital going to one strategy or one time window? What % of total risk was in the top 3 trades? Could a single bad 15-min candle wipe the day's gains?
3. STRATEGY EDGE: Which strategies are actually generating alpha vs. just churning volume? Calculate net P&L per contract risked for each strategy. A strategy with 90% WR but tiny wins and occasional big losses has negative edge.
4. HARVEST EFFICIENCY: For harvested trades, what % of max theoretical profit was captured? Are harvests firing too early (leaving money) or too late (missing fills)?
5. STOP QUALITY: For stopped trades, was the stop triggered by real adverse price action or by noise (BDI fluctuation, thin books)? Could wider stops have saved any losing trades?
6. TIMING PATTERNS: Which session windows are profitable? Which are negative? Is there a time-of-day the bot should sit out?
7. PHANTOM POSITION IMPACT: Separate phantom P&L from real P&L. What would the day look like if phantom positions are excluded entirely?
8. POSITION SIZING: Are position sizes scaling with conviction/edge, or are they uniform? Is the bot betting big on low-edge setups?
9. CROSS-TRADE DEPENDENCIES: Did any stop cascade (one stop triggering repositioning that also stopped)? Are there correlated losses?
10. ACTIONABLE RECOMMENDATION: The ONE most justified next step for the business, using this priority hierarchy:
    (1) Runtime correctness fix (stale state, wrong exit paths, NameErrors)
    (2) Instrumentation gap (can't see what happened — add logging/metrics)
    (3) Execution-layer fix (harvest fills, order placement, exchange response)
    (4) Family/session-scoped fix (gate by environment, not blanket restriction)
    (5) Threshold/parameter change (LAST RESORT — only when 1-4 are all clean)
    Do NOT default to "tighten parameter X." If the best answer is MONITOR or COLLECT MORE DATA, say that.
    Format: BUILD vXXX (exact change + log evidence) | COLLECT MORE DATA (what events + how many sessions) | MONITOR AND HOLD (trigger for revisit).

Format your response as:

INDEPENDENT ANALYSIS — [date]

BALANCE: Start $X.XX → End $X.XX | Actual Net: +/-$X.XX
TRADES: N total | NW / NL (X% WR)

ENTRY QUALITY ASSESSMENT:
• [Per-strategy entry price trends across session windows. Degrading or improving?]

RISK CONCENTRATION:
• [Top 3 trades by risk. % of total exposure. Single-point-of-failure analysis.]

STRATEGY EDGE (Net P&L per contract risked):
• [Per-strategy: total risked, total returned, edge per contract. Rank by real edge, not WR.]

HARVEST EFFICIENCY:
• [% of theoretical max captured. Trades where early harvest left >$1 on table. Trades where harvest missed entirely.]

STOP ANALYSIS:
• [Each stop: was it signal or noise? Could a different threshold have saved it?]

TIMING ANALYSIS:
• [Per-session-window P&L. Which windows to keep, which to avoid.]

PHANTOM IMPACT:
• [Real vs phantom P&L separation. Adjusted metrics excluding phantom.]

CRITICAL FINDING:
• [The ONE most justified next step using the priority hierarchy: correctness > execution > instrumentation > family-scoped > parameter change. Format as BUILD/COLLECT/MONITOR. Back with log data.]"""

    phase1_user = f"""Analyze this raw AetherBot trading log for {date_arg}.
Form your own independent conclusions. Do not assume anything — work from the data.

RAW LOG:
{raw_log_text}"""

    try:
        phase1_output = call_gpt(phase1_system, phase1_user, max_tokens=4000)
        print(phase1_output)

        # Save Phase 1 output
        p1_file = ANALYSIS_DIR / f"GPT_Independent_{date_arg}.txt"
        p1_file.write_text(
            f"{'=' * 70}\n"
            f"GPT-4o INDEPENDENT ANALYSIS — {date_arg}\n"
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S MT')}\n"
            f"Model: gpt-4o | Temp: 0.3 | Phase 1 of 2\n"
            f"Source: Raw log ({raw_log.name}, {len(raw_log_text)} chars)\n"
            f"{'=' * 70}\n\n"
            f"{phase1_output}\n"
        )
        print(f"\nSaved Phase 1 to: {p1_file}")

    except urllib.error.HTTPError as e:
        print(f"PHASE 1 HTTP ERROR {e.code}: {e.read().decode()[:500]}")
        print("Phase 1 failed. Continuing to Phase 2 in degraded mode.")
        phase1_output = None
    except Exception as e:
        print(f"PHASE 1 ERROR: {e}")
        print("Phase 1 failed. Continuing to Phase 2 in degraded mode.")
        phase1_output = None

else:
    print("\nSKIPPING PHASE 1 — no raw log available. DEGRADED MODE.")

# Rate limit cooldown between phases
print("\nWaiting 10s for rate limit cooldown...")
time.sleep(10)

# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 2: GPT COMPARATIVE REVIEW (reads Kai's analysis, fact-checks against
#           its own Phase 1 findings and/or the raw log)
# ═══════════════════════════════════════════════════════════════════════════════

print(f"\n{'=' * 70}")
print(f"PHASE 2: GPT comparative review of Kai's analysis — {date_arg}")
print(f"{'=' * 70}")

phase2_context = ""
if phase1_output:
    phase2_context = f"""You already analyzed the raw log independently. Here is YOUR OWN analysis from Phase 1:

--- YOUR INDEPENDENT ANALYSIS ---
{phase1_output}
--- END YOUR INDEPENDENT ANALYSIS ---

Now compare your findings against Kai's (Claude's) analysis below."""
else:
    phase2_context = """WARNING: You did not have access to the raw log for independent analysis.
This is DEGRADED MODE. You can only review the analysis on its internal logic,
not against the raw data. Flag this limitation in your review."""

phase2_system = f"""You are GPT-4o, acting as the adversarial second opinion for AetherBot daily trading analysis.

{phase2_context}

DO NOT just compare balances. You already did arithmetic in Phase 1. Phase 2 is about JUDGMENT.

Your job in Phase 2 — focus on these higher-order questions:

1. WHAT KAI MISSED: Using your independent findings, identify blind spots in Kai's analysis. Did Kai celebrate a winning day while ignoring that 60% of profit came from one lucky trade? Did Kai flag a risk without quantifying it? Did Kai make a recommendation without evidence?

2. STRATEGY RECOMMENDATIONS — AGREE OR OVERRIDE:
   For each of Kai's strategy-level conclusions, either:
   (a) AGREE and add supporting evidence from your Phase 1 analysis, or
   (b) OVERRIDE with a specific alternative, backed by data. "I disagree" without a counter-recommendation is worthless.

3. RISK ASSESSMENT Kai's analysis tends to focus on what happened. Your job is to ask: what COULD have happened? If BTC had moved 2% instead of 0.5%, which positions would have blown up? Calculate worst-case exposure for the largest positions.

4. ACTION CLASSIFICATION: For each finding from both analyses, classify using the priority hierarchy:
   (1) Runtime correctness fix — stale state, wrong paths, NameErrors
   (2) Instrumentation gap — can't diagnose root cause, need more logging
   (3) Execution-layer fix — harvest fills, order placement, exchange response
   (4) Family/session-scoped fix — gate by environment, not blanket restriction
   (5) Threshold/parameter change — LAST RESORT, only when 1-4 are clean
   Then tag each: build now / monitor / revisit later / do not change.
   Do NOT default to parameter tightening. That is patchwork.

5. MULTI-DAY TREND (if you have prior context): Is today's performance consistent with the last 2-3 days, or is there drift? Are the same strategies winning/losing? Are the same issues recurring?

6. VERDICT: Grade the day A/B/C/D/F with justification. A = strong edge execution, B = profitable but with concerns, C = break-even or lucky, D = losing but recoverable, F = systemic failure.

Format your response as:
COMPARATIVE REVIEW — [date]

MATH VERIFICATION: [1-2 lines only — pass/fail on balances. This is NOT the analysis.]

KAI'S BLIND SPOTS:
• [What Kai missed or glossed over — be specific]

STRATEGY OVERRIDES:
• [For each strategy Kai discussed: AGREE + evidence, or OVERRIDE + alternative]

RISK SCENARIO:
• [Worst-case: what would today look like with 2% adverse BTC move? Quantify.]

ACTION CLASSIFICATION:
• [Each finding tagged: correctness/instrumentation/execution/family-scoped/parameter]
• [Each tagged: build now / monitor / revisit later / do not change]
• [Parameter changes are LAST RESORT — only when categories 1-4 are clean]

DAY GRADE: [A/B/C/D/F] — [2-sentence justification]

CRITICAL RECOMMENDATION:
• [The ONE most justified next step. Format: BUILD vXXX (exact change + evidence + risk of waiting) | COLLECT MORE DATA (events needed + sessions) | MONITOR AND HOLD (trigger for next decision). Use priority hierarchy: correctness > execution > instrumentation > family-scoped > parameter.]"""

phase2_user = f"""Review this AetherBot daily analysis by Kai (Claude) for {date_arg}.
Compare against your own independent analysis. Fact-check, agree, disagree, push back.

KAI'S ANALYSIS:
{analysis_text}"""

try:
    phase2_output = call_gpt(phase2_system, phase2_user, max_tokens=3000)
    print(phase2_output)

    # Save Phase 2 output
    p2_file = ANALYSIS_DIR / f"GPT_Review_{date_arg}.txt"
    degraded = " (DEGRADED — no raw log for Phase 1)" if not phase1_output else ""
    p2_file.write_text(
        f"{'=' * 70}\n"
        f"GPT-4o COMPARATIVE REVIEW — {date_arg}{degraded}\n"
        f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S MT')}\n"
        f"Model: gpt-4o | Temp: 0.3 | Phase 2 of 2\n"
        f"Phase 1 available: {'YES' if phase1_output else 'NO — DEGRADED'}\n"
        f"{'=' * 70}\n\n"
        f"{phase2_output}\n"
    )
    print(f"\nSaved Phase 2 to: {p2_file}")

except urllib.error.HTTPError as e:
    print(f"PHASE 2 HTTP ERROR {e.code}: {e.read().decode()[:500]}")
    sys.exit(1)
except Exception as e:
    print(f"PHASE 2 ERROR: {e}")
    sys.exit(1)


# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

print(f"\n{'=' * 70}")
print(f"PIPELINE COMPLETE — {date_arg}")
print(f"{'=' * 70}")
if phase1_output:
    print(f"  Phase 1 (independent): GPT_Independent_{date_arg}.txt")
else:
    print(f"  Phase 1 (independent): SKIPPED — no raw log (DEGRADED)")
print(f"  Phase 2 (comparative): GPT_Review_{date_arg}.txt")
print()
print("NEXT STEPS FOR KAI:")
print("  1. Read both GPT outputs")
print("  2. Integrate GPT's independent analysis into the report")
print("  3. Respond to every point in the comparative review")
print("  4. If GPT disagrees, engage — change your mind or explain why not")
print("  5. Set GPT_VERIFIED: YES only after all of the above")
