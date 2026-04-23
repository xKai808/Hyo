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
HYO_ROOT          = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
METRICS_FILE      = os.path.join(HYO_ROOT, "agents/sam/website/data/aether-metrics.json")
KNOWLEDGE_FILE    = os.path.join(HYO_ROOT, "kai/memory/KNOWLEDGE.md")

anthropic_client  = Anthropic(api_key=ANTHROPIC_API_KEY)
openai_client     = OpenAI(api_key=OPENAI_API_KEY)


def _load_dynamic_context() -> tuple[str, str, str, str]:
    """
    Load balance ledger, open issues, current version, and next version
    dynamically from aether-metrics.json and KNOWLEDGE.md.

    Falls back to safe defaults if files are unavailable so the pipeline
    never fails just because a data file is missing.

    Returns: (current_version, next_version, balance_ledger, open_issues)
    """
    current_version = "v253"
    next_version    = "v254"

    # ── Balance ledger from aether-metrics.json ──────────────────────────────
    balance_ledger = ""
    try:
        with open(METRICS_FILE, "r") as f:
            m = json.load(f) if hasattr(json, 'load') else {}
            import json as _json
            m = _json.load(open(METRICS_FILE))
        daily = m.get("daily_pnl", {})
        week_start = m.get("week", {}).get("start_balance", None)
        current_bal = m.get("week", {}).get("current_balance", None)

        lines = ["Date            End Balance     Day Net",
                 "-----------     -----------     -------"]
        for entry in sorted(daily, key=lambda x: x.get("date", "")):
            d = entry.get("date", "")
            bal = entry.get("balance", 0)
            net = entry.get("pnl", 0)
            sign = "+" if net >= 0 else ""
            lines.append(f"{d}  ${bal:.2f}{'':8} {sign}${net:.2f}")

        if week_start:
            lines.append(f"\nStart of week:  ${week_start:.2f}")
        if current_bal:
            lines.append(f"Current:        ${current_bal:.2f}")
        lines.append("Daily target:   $10–20 net (path to $100+/day)")
        balance_ledger = "\n".join(lines)
    except Exception as e:
        print(f"[balance-ledger] Could not load from aether-metrics.json: {e} — using KNOWLEDGE.md fallback")

    # ── Fallback: extract balance ledger from KNOWLEDGE.md ───────────────────
    if not balance_ledger:
        try:
            with open(KNOWLEDGE_FILE, "r") as f:
                knowledge = f.read()
            import re
            section = re.search(r"## BALANCE LEDGER.*?\n([\s\S]+?)(?=\n---|\n##|$)", knowledge)
            if section:
                balance_ledger = section.group(1).strip()
        except Exception as e2:
            print(f"[balance-ledger] KNOWLEDGE.md fallback also failed: {e2}")
            balance_ledger = "(Balance ledger unavailable — check aether-metrics.json)"

    # ── Open issues from KNOWLEDGE.md ────────────────────────────────────────
    open_issues = ""
    try:
        with open(KNOWLEDGE_FILE, "r") as f:
            knowledge = f.read()
        import re
        # Extract the open issues section
        section = re.search(r"### Open AetherBot issues.*?\n([\s\S]+?)(?=\n---|\n###|\n##|$)", knowledge)
        if section:
            open_issues = section.group(1).strip()
        # Also extract version numbers
        v_match = re.search(r"current deployed version: (v\d+).*?next.*?(v\d+)", knowledge, re.IGNORECASE)
        if v_match:
            current_version = v_match.group(1)
            next_version    = v_match.group(2)
    except Exception as e:
        print(f"[open-issues] Could not load from KNOWLEDGE.md: {e}")

    if not open_issues:
        open_issues = "(Open issues unavailable — check kai/memory/KNOWLEDGE.md)"

    return current_version, next_version, balance_ledger, open_issues


# Load dynamic context at startup (refreshed each analysis run)
import json as _json_mod
CURRENT_VERSION, NEXT_VERSION, BALANCE_LEDGER, OPEN_ISSUES = _load_dynamic_context()

# ── Load the protocol (SE-AETHER-PROTOCOL-001) ───────────────────────────────
# The protocol defines the COMPLETE execution spec for AetherBot daily analysis.
# It must be injected into every Claude system prompt so the automated pipeline
# follows the same standards as manual/interactive sessions.
# Canonical location: agents/aether/PROTOCOL_DAILY_ANALYSIS.md (root is a symlink)
_PROTOCOL_FILE = os.path.join(HYO_ROOT, "agents/aether/PROTOCOL_DAILY_ANALYSIS.md")
try:
    with open(_PROTOCOL_FILE, "r") as _f:
        _PROTOCOL_CONTENT = _f.read()
    _protocol_lines = len(_PROTOCOL_CONTENT.splitlines())
    print(f"[protocol] Loaded {_PROTOCOL_FILE} ({_protocol_lines} lines)")
except Exception as _pe:
    _PROTOCOL_CONTENT = "(PROTOCOL FILE UNAVAILABLE — kai_analysis.py could not load agents/aether/PROTOCOL_DAILY_ANALYSIS.md)"
    print(f"[protocol] WARNING: Could not load protocol: {_pe!r} — using fallback instructions only")

CLAUDE_SYSTEM = f"""MANDATORY: You are executing the AetherBot daily analysis pipeline.
Follow PROTOCOL_DAILY_ANALYSIS.md (loaded below) exactly for all output format, section markers,
trade ledger structure, GPT critique requirements, and the 25-point completion checklist.

{_PROTOCOL_CONTENT}

=== AUTOMATED PIPELINE DYNAMIC CONTEXT ===
Current deployed version: {CURRENT_VERSION}
Next build: {NEXT_VERSION}

Balance ledger:
{BALANCE_LEDGER}

Open issues:
{OPEN_ISSUES}

REMINDER: Output MUST include all three section markers:
  === CLAUDE PRIMARY ANALYSIS ===
  === GPT CRITIQUE ===
  === FINAL SYNTHESIS ===
The post-publish quality gate (analysis-gate.py) blocks publishing if these are absent.
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
    """
    Select the best available AetherBot log with sparse-log gate.

    SPARSE LOG GATE (SE-019): If today's log has <100 lines, it's a midnight
    stub (AetherBot creates next-day file at 23:59:xx). Fall back to yesterday's
    full log. This mirrors the gate in run_analysis.sh so both paths agree on
    which log to analyze.
    """
    SPARSE_THRESHOLD = 100  # lines

    # Support backfill: AETHER_LOG_DATE=2026-04-17 python3 kai_analysis.py
    _date_override = os.environ.get("AETHER_LOG_DATE")
    if _date_override:
        today_date = _date_override
        _d = datetime.datetime.strptime(_date_override, "%Y-%m-%d")
        yesterday_date = (_d - datetime.timedelta(days=1)).strftime("%Y-%m-%d")
    else:
        today_date = datetime.datetime.now().strftime("%Y-%m-%d")
        yesterday_date = (datetime.datetime.now() - datetime.timedelta(days=1)).strftime("%Y-%m-%d")

    today_path = os.path.join(LOG_DIR, f"AetherBot_{today_date}.txt")
    yesterday_path = os.path.join(LOG_DIR, f"AetherBot_{yesterday_date}.txt")

    def line_count(path):
        try:
            with open(path, "r") as f:
                return sum(1 for _ in f)
        except Exception:
            return 0

    # Prefer today's log if it has enough data
    if os.path.exists(today_path) and line_count(today_path) >= SPARSE_THRESHOLD:
        chosen = today_path
    elif os.path.exists(yesterday_path):
        today_count = line_count(today_path) if os.path.exists(today_path) else 0
        yesterday_count = line_count(yesterday_path)
        if yesterday_count > today_count:
            print(f"[sparse-gate] Today has {today_count} lines < {SPARSE_THRESHOLD} — using yesterday ({yesterday_count} lines)")
            chosen = yesterday_path
        elif os.path.exists(today_path):
            chosen = today_path
        else:
            chosen = yesterday_path
    elif os.path.exists(today_path):
        chosen = today_path
    else:
        # Fall back to most recent available log
        all_logs = sorted(glob.glob(os.path.join(LOG_DIR, "AetherBot_*.txt")), reverse=True)
        if not all_logs:
            return None, None
        chosen = all_logs[0]
        print(f"[sparse-gate] No today/yesterday log — using most recent: {os.path.basename(chosen)}")

    with open(chosen, "r") as f:
        return f.read(), os.path.basename(chosen)

def get_historical_logs(limit=5):
    logs = sorted(glob.glob(os.path.join(LOG_DIR, "AetherBot_*.txt")), reverse=True)
    historical = {}
    for path in logs[1:limit+1]:
        date = os.path.basename(path).replace("AetherBot_", "").replace(".txt", "")
        with open(path, "r") as f:
            historical[date] = f.read()[:3000]
    return historical


import time as _time

class ClaudeQuotaExceeded(Exception):
    """Raised when Anthropic API returns a usage-limit 400 error.
    Triggers automatic GPT-4o fallback in run_analysis().
    Gate question: 'Is this a quota error?' YES → raise ClaudeQuotaExceeded → GPT fallback.
    """
    pass

def _retry_api(fn, *, what='api', attempts=4, base_sleep=3.0):
    last = None
    for i in range(attempts):
        try:
            return fn()
        except Exception as e:
            # Detect Anthropic quota error — no retry, fail fast, trigger fallback
            err_str = str(e)
            if what == 'claude' and ('specified API usage limits' in err_str or
                                     'You have reached your' in err_str):
                print(f'[{what}] QUOTA EXCEEDED — Anthropic API limit hit. Triggering GPT-4o fallback.')
                raise ClaudeQuotaExceeded(f'Anthropic quota: {err_str[:200]}')
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

    # STEP 2: Claude primary analysis (with GPT-4o quota fallback)
    print("\nStep 2: Sending to Claude...")
    send_telegram("Kai: Claude analyzing...")

    log_payload = (
        f"Today's log ({log_filename}) — last 8000 chars:\n\n{log_content[-8000:]}\n\n"
        f"Historical data for simulation:\n{historical_context}"
    )
    claude_messages = [{"role": "user", "content": log_payload}]

    GPT_FALLBACK_MODE = False
    try:
        claude_analysis = call_claude(claude_messages)
        print(f"Claude: {len(claude_analysis):,} chars")
    except ClaudeQuotaExceeded as _qe:
        print(f"[fallback] Anthropic quota exceeded — switching to GPT-4o for all steps.")
        print(f"[fallback] Quota resets: check KNOWLEDGE.md or Anthropic console for date.")
        send_telegram("Kai: Anthropic API quota exceeded — using GPT-4o fallback for full analysis.")
        GPT_FALLBACK_MODE = True
        # GPT-4o primary analysis using Claude system prompt as context
        claude_analysis = call_gpt(
            f"[GPT-4o FALLBACK — Claude API at quota]\n\n"
            f"System context: {CLAUDE_SYSTEM[:2000]}\n\n"
            f"{log_payload}"
        )
        print(f"GPT-fallback primary: {len(claude_analysis):,} chars")

    # STEP 3: GPT fact-check / critique
    print("\nStep 3: Sending to GPT...")
    send_telegram("Kai: GPT fact-checking...")

    gpt_critique = call_gpt(
        f"Review this analysis for errors and simulation gaps:\n\n{claude_analysis}"
    )
    print(f"GPT: {len(gpt_critique):,} chars")

    # STEP 4: Final synthesis (Claude if available, GPT if quota exceeded)
    print("\nStep 4: Final synthesis...")
    send_telegram("Kai: Synthesizing final recommendation...")

    if GPT_FALLBACK_MODE:
        final_synthesis = call_gpt(
            f"[FINAL SYNTHESIS — GPT-4o fallback]\n\n"
            f"Primary analysis:\n{claude_analysis}\n\n"
            f"GPT critique:\n{gpt_critique}\n\n"
            f"VERDICT: Provide ONE final recommendation: build {NEXT_VERSION} with exact specs, "
            f"or collect more data. Include: VERDICT, DAY GRADE, CORRECTIONS APPLIED."
        )
        print(f"GPT synthesis: {len(final_synthesis):,} chars")
    else:
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
    _out_date = os.environ.get("AETHER_LOG_DATE") or datetime.datetime.now().strftime("%Y-%m-%d")
    output_path = os.path.join(output_dir, f"Analysis_{_out_date}.txt")
    with open(output_path, "w") as f:
        f.write(f"=== CLAUDE PRIMARY ANALYSIS ===\n{claude_analysis}\n\n")
        f.write(f"=== GPT CRITIQUE ===\n{gpt_critique}\n\n")
        f.write(f"=== FINAL SYNTHESIS ===\n{final_synthesis}\n")

    print(f"Saved: {output_path}")
    print("Pipeline complete.")

if __name__ == "__main__":
    run_analysis()
