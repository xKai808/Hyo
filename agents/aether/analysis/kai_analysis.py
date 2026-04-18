#!/usr/bin/env python3
"""
Kai Daily Analysis Pipeline
============================
Uses official Anthropic and OpenAI Python libraries.
Runs automatically each day at 23:55 MTN.
"""

import os
import glob
import datetime
import requests
from anthropic import Anthropic
from openai import OpenAI

# ── CONFIGURATION ─────────────────────────────────────────────────────────────

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")
OPENAI_API_KEY    = os.environ.get("OPENAI_API_KEY")
TELEGRAM_TOKEN    = os.environ.get("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID  = os.environ.get("TELEGRAM_CHAT_ID")

LOG_DIR           = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
CURRENT_VERSION   = "v253"
NEXT_VERSION      = "v254"

anthropic_client  = Anthropic(api_key=ANTHROPIC_API_KEY)
openai_client     = OpenAI(api_key=OPENAI_API_KEY)

BALANCE_LEDGER = """
Date            End Balance     Day Net
-----------     -----------     -------
4/13 (Sun)      $86.44          -$3.81
4/14 (Mon)      $108.91         +$22.47
4/15 (Tue)      $116.16         +$7.25
4/16 (Wed)      $114.33         -$1.83
4/17 (Thu)      $113.88 (live)  in progress

Start (4/13):   $90.25 (est)
Weekly goal:    >$10-20/day sustained (path to >$100/day)
"""

OPEN_ISSUES = """
P0 ACTIVE  — Phantom Position Investigation (v254): phantom warnings at 39 and climbing. \
Local/API state drift degrades execution quality. Root cause: each failed harvest sync creates a new phantom.
P1 ACTIVE  — BDI=0 Hold Time Gate: <120s expiry losses confirmed pattern, gate not yet shipped.
P1 ACTIVE  — Harvest Miss Dual-Mode Fix: gate on anchor +/-0.02 depth, not held_px +/-0.05.
P2 MONITOR — PAQ_STRUCT_GATE: 3W/6L (33% WR), -$7.84 net. Watch for continued degradation.
P2 MONITOR — EVENING bps_premium regime sensitivity: performance varies with BTC direction.
P2 MONITOR — EU_MORNING post-04:15 loss clustering: track WR and net P&L for this window.
P3 PENDING — Weekend risk profile: reduced exposure, PAQ_MIN=4, no confirm_late.
"""

CLAUDE_SYSTEM = f"""You are the primary analyst for AetherBot, an automated trading bot on Kalshi
prediction markets trading KXBTC15M (BTC 15-minute contracts).

Analyze the daily session log and provide:
1. Full trade-by-trade ledger grouped by strategy family.
2. Stop/harvest event log.
3. Session window P&L: OVERNIGHT | EU_MORNING | NY_OPEN | NY_PRIME | NY_CLOSE | EVENING (all MTN).
4. Net P&L for the day. Update the balance ledger.
5. Simulation of any proposed change: primary, secondary, and tertiary effects against historical data.
6. ONE conclusion. ONE recommended action.

Rules:
- Come with a position, not a report.
- Never kill strategies from single-session data.
- All times MTN. Never UTC.
- Current version {CURRENT_VERSION}. Next build {NEXT_VERSION}.

Balance ledger:
{BALANCE_LEDGER}

Open issues:
{OPEN_ISSUES}
"""

GPT_SYSTEM = """You are the adversarial analyst for AetherBot — a Kalshi prediction market trading bot \
that generates the revenue sustaining multiple active projects. This analysis is a lifeline, not a report.

Your job is NOT to validate. Your job is to find what the primary analyst missed.

Interrogate these dimensions specifically:
1. STRATEGY DRIFT — Did any family's win rate, avg win, or avg loss shift >10% vs its trailing 5-session baseline? \
If yes, name it and explain what's changing.
2. RISK CONCENTRATION — Are >40% of trades or >50% of P&L exposure concentrated in one strategy or one session window? \
Name the concentration and the single-event risk it creates.
3. ENTRY QUALITY DEGRADATION — Are stop events increasing as a % of total trades? Is average hold time shortening? \
Are harvests executing at lower premiums than last week? Flag any degradation trend.
4. HARVEST EFFICIENCY — What % of harvests executed at max premium vs settled early? \
Any pattern of early exits costing recoverable P&L?
5. TIMING REGRESSION — Compare today's session window P&L vs the 5-session trailing average per window. \
Which windows are degrading? Which are improving? Is the pattern consistent with prior regressions?
6. OPEN ISSUE PROGRESS — For each open issue in the primary analysis: is the evidence confirming, disconfirming, \
or inconclusive vs prior sessions? State which.
7. SIMULATION GAPS — Did the primary analysis propose a change? If so: what second-order effect was not modeled? \
What would have to be true for the proposed change to backfire?
8. WHAT WOULD BREAK TOMORROW — Given today's data, what is the single highest-probability failure mode \
in the next 24h session? Be specific: which strategy, which session window, which condition.

Format: 8 numbered sections matching the above. No preamble. No agreement with the primary analysis unless \
you have tested it against the data. Every claim needs a number from the log."""

# ── HELPERS ───────────────────────────────────────────────────────────────────

def send_telegram(message: str):
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT_ID:
        print(f"[No Telegram] {message}")
        return
    try:
        requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage",
            data={"chat_id": TELEGRAM_CHAT_ID, "text": message},
            timeout=10
        )
    except Exception as e:
        print(f"Telegram error: {e}")

def get_today_log():
    date = datetime.datetime.now().strftime("%Y-%m-%d")
    path = os.path.join(LOG_DIR, f"AetherBot_{date}.txt")
    if not os.path.exists(path):
        yesterday = (datetime.datetime.now() - datetime.timedelta(days=1)).strftime("%Y-%m-%d")
        path = os.path.join(LOG_DIR, f"AetherBot_{yesterday}.txt")
    if not os.path.exists(path):
        return None, None
    with open(path, "r") as f:
        return f.read(), os.path.basename(path)

def get_historical_logs(limit=5):
    logs = sorted(glob.glob(os.path.join(LOG_DIR, "AetherBot_*.txt")), reverse=True)
    historical = {}
    for path in logs[1:limit+1]:
        date = os.path.basename(path).replace("AetherBot_", "").replace(".txt", "")
        with open(path, "r") as f:
            historical[date] = f.read()[:3000]
    return historical


import time as _time
def _retry_api(fn, *, what='api', attempts=4, base_sleep=3.0):
    last = None
    for i in range(attempts):
        try:
            return fn()
        except Exception as e:
            last = e
            sleep_s = base_sleep * (2 ** i)
            print(f'[{what}] attempt {i+1}/{attempts} failed: {e!r} — sleeping {sleep_s:.1f}s')
            _time.sleep(sleep_s)
    raise RuntimeError(f'{what} failed after {attempts} attempts: {last!r}')

def _log_api_usage(provider: str, model: str, in_tok: int, out_tok: int, notes: str = "") -> None:
    """SE-011-003: Record API usage to kai/ledger/api-usage.jsonl via bin/api-usage.sh.
    Non-fatal — never let logging break the pipeline."""
    try:
        import subprocess as _sp
        _root = os.environ.get("HYO_ROOT") or os.path.expanduser("~/Documents/Projects/Hyo")
        _sp.run(
            ["bash", os.path.join(_root, "bin", "api-usage.sh"), "log",
             provider, "aether", model, str(in_tok), str(out_tok), notes],
            check=False, timeout=5, capture_output=True
        )
    except Exception as _e:
        print(f"[api-usage] logging failed (non-fatal): {_e!r}")

def call_claude(messages: list) -> str:
    def _do():
        response = anthropic_client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            system=CLAUDE_SYSTEM,
            messages=messages
        )
        try:
            _u = getattr(response, "usage", None)
            _in = int(getattr(_u, "input_tokens", 0) or 0) if _u else 0
            _out = int(getattr(_u, "output_tokens", 0) or 0) if _u else 0
            _log_api_usage("anthropic", "claude-sonnet-4-6", _in, _out, "kai_analysis.call_claude")
        except Exception:
            pass
        return response.content[0].text
    return _retry_api(_do, what="claude")

def call_gpt(user_message: str) -> str:
    def _do():
        response = openai_client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": GPT_SYSTEM},
                {"role": "user", "content": user_message}
            ],
            max_tokens=4096
        )
        try:
            _u = getattr(response, "usage", None)
            _in = int(getattr(_u, "prompt_tokens", 0) or 0) if _u else 0
            _out = int(getattr(_u, "completion_tokens", 0) or 0) if _u else 0
            _log_api_usage("openai", "gpt-4o", _in, _out, "kai_analysis.call_gpt")
        except Exception:
            pass
        return response.choices[0].message.content
    return _retry_api(_do, what="gpt")

# ── MAIN PIPELINE ─────────────────────────────────────────────────────────────

def run_analysis():
    print("=" * 60)
    print("KAI DAILY ANALYSIS PIPELINE")
    print(datetime.datetime.now().strftime("%Y-%m-%d %H:%M MTN"))
    print("=" * 60)

    send_telegram("Kai: Starting daily AetherBot analysis...")

    log_content, log_filename = get_today_log()
    if not log_content:
        send_telegram("Kai: No log file found. Analysis aborted.")
        return

    print(f"Log loaded: {log_filename} ({len(log_content):,} chars)")

    historical = get_historical_logs(limit=5)
    historical_context = ""
    for date, content in historical.items():
        historical_context += f"\n\n=== HISTORICAL: {date} ===\n{content}"

    print(f"Historical logs: {len(historical)} sessions")

    # STEP 2: Claude primary analysis
    print("\nStep 2: Sending to Claude...")
    send_telegram("Kai: Claude analyzing...")

    claude_messages = [{
        "role": "user",
        "content": (
            f"Today's log ({log_filename}) — last 8000 chars:\n\n{log_content[-8000:]}\n\n"
            f"Historical data for simulation:\n{historical_context}"
        )
    }]

    claude_analysis = call_claude(claude_messages)
    print(f"Claude: {len(claude_analysis):,} chars")

    # STEP 3: GPT fact-check
    print("\nStep 3: Sending to GPT...")
    send_telegram("Kai: GPT fact-checking...")

    gpt_critique = call_gpt(
        f"Review this analysis for errors and simulation gaps:\n\n{claude_analysis}"
    )
    print(f"GPT: {len(gpt_critique):,} chars")

    # STEP 4: Claude final synthesis
    print("\nStep 4: Claude final synthesis...")
    send_telegram("Kai: Synthesizing final recommendation...")

    claude_messages.append({"role": "assistant", "content": claude_analysis})
    claude_messages.append({
        "role": "user",
        "content": (
            f"GPT critique:\n\n{gpt_critique}\n\n"
            f"Synthesize. ONE final recommendation: "
            f"build {NEXT_VERSION} with exact specs, or collect more data."
        )
    })

    final_synthesis = call_claude(claude_messages)
    print(f"Synthesis: {len(final_synthesis):,} chars")

    # STEP 5: Surface to Hyo
    print("\nStep 5: Sending to Telegram...")

    summary = final_synthesis[:3500] + "..." if len(final_synthesis) > 3500 else final_synthesis
    send_telegram(f"Kai Analysis — {log_filename}\n\n{summary}")
    send_telegram(
        f"Analysis complete.\n\n"
        f"/approve — build {NEXT_VERSION}\n"
        f"/hold — collect more sessions"
    )

    # Save outputs
    output_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Kai analysis")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, f"Analysis_{datetime.datetime.now().strftime('%Y-%m-%d')}.txt")
    with open(output_path, "w") as f:
        f.write(f"=== CLAUDE PRIMARY ANALYSIS ===\n{claude_analysis}\n\n")
        f.write(f"=== GPT CRITIQUE ===\n{gpt_critique}\n\n")
        f.write(f"=== FINAL SYNTHESIS ===\n{final_synthesis}\n")

    print(f"Saved: {output_path}")
    print("Pipeline complete.")

if __name__ == "__main__":
    run_analysis()
