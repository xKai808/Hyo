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
3/28 (Sat)      $89.87          —
3/29 (Sun)      $101.25         —
3/30 (Mon)      $90.18          +$6.05
3/31 (Tue)      $110.32         +$33.83
4/1  (Wed)      $119.02         +$13.08
4/2  (Thu)      $121.02         -$8.56
4/3  (Fri)      $111.55         -$7.12
4/4  (Sat)      $107.30         —
4/5  (Sun)      $76.18          —
4/6  (Mon)      $93.04          +$16.86
4/7  (Tue)      $104.02         +$10.98

Start (3/28):   $101.38
Goal:           >$10-20/day (path to >$100/day)
"""

OPEN_ISSUES = """
1. EU_MORNING (03:00-05:00 MTN): Track WR, net P&L, losses after 04:15 MTN.
2. PAQ_EARLY_AGG BDI=0 stop hold: confirmed problem, needs more evidence.
3. Harvest miss: fix is gate on anchor +/-0.02 depth, not held_px +/-0.05.
4. Weekend risk profile: $5 flat, PAQ_MIN=4, no confirm_late or confirm_standard.
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

GPT_SYSTEM = """You are Aether, fact-checker for AetherBot analysis.
Find logical errors, math errors, missed patterns, and simulation gaps.
Check primary, secondary, and tertiary effects. Be direct. Find gaps, not validation.
"""

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

def call_claude(messages: list) -> str:
    response = anthropic_client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        system=CLAUDE_SYSTEM,
        messages=messages
    )
    return response.content[0].text

def call_gpt(user_message: str) -> str:
    response = openai_client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": GPT_SYSTEM},
            {"role": "user", "content": user_message}
        ],
        max_tokens=4096
    )
    return response.choices[0].message.content

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
