#!/usr/bin/env python3
"""
GPT-4o Fact-Check for AetherBot
================================
Two modes:
  1. Analysis fact-check (default): reads today's analysis, sends to GPT-4o
     for adversarial critique.
  2. Daily log review (--log): reads today's raw AetherBot log, sends to GPT-4o
     for independent analysis, pattern detection, and fact-checking of any
     trading decisions the bot made.

Usage:
  python3 gpt_factcheck.py                   # fact-check today's analysis
  python3 gpt_factcheck.py --log             # review today's raw log
  python3 gpt_factcheck.py --log 2026-04-11  # review a specific date's log

All paths use the post-migration agents/aether/ layout.
"""

import json, os, sys, datetime, urllib.request

# ── Paths (post-migration) ────────────────────────────────────────────────────
HYO_ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
AETHER_DIR = os.path.join(HYO_ROOT, "agents", "aether")
ANALYSIS_DIR = os.path.join(AETHER_DIR, "analysis")
LOGS_DIR = os.path.join(AETHER_DIR, "logs")
SECRETS_DIR = os.path.join(HYO_ROOT, "agents", "nel", "security")

# Legacy fallback for AetherBot log location (logger still writes here)
LEGACY_LOGS_DIR = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")

def load_key():
    """Load OpenAI API key from agents/nel/security/openai.key or .env fallback."""
    # Primary: dedicated key file
    key_file = os.path.join(SECRETS_DIR, "openai.key")
    if os.path.exists(key_file):
        with open(key_file) as f:
            key = f.read().strip()
            key = key.encode("ascii", "ignore").decode("ascii").strip()
            if key:
                return key

    # Fallback: .env in various locations
    for env_path in [
        os.path.join(HYO_ROOT, ".env"),
        os.path.expanduser("~/Documents/Projects/Kai/.env"),
    ]:
        if os.path.exists(env_path):
            with open(env_path) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("OPENAI_API_KEY="):
                        key = line[len("OPENAI_API_KEY="):]
                        key = key.encode("ascii", "ignore").decode("ascii").strip()
                        return key

    # Last resort: environment variable
    return os.environ.get("OPENAI_API_KEY", "")


# ── System prompts ────────────────────────────────────────────────────────────

SYSTEM_ANALYSIS = """You are Aether, the adversarial fact-checker for AetherBot analysis.

Your job is to find:
1. Logical errors or math errors in the analysis
2. Missed systemic patterns (NOT single-session reactions)
3. Simulation gaps — what would happen if a proposed change were applied across MULTIPLE sessions?
4. Whether conclusions are backed by multi-session evidence or just today's data
5. Session-boundary behavior: did conviction/sizing logic behave differently at window transitions?

Rules:
- Do NOT recommend position caps or strategy kills from a single session
- Look for STRUCTURAL issues in the bot's logic, not patchwork fixes
- If the analyst recommended a reactive change, call it out
- Be direct. Find gaps, not validation.
- All times MTN."""

SYSTEM_LOG_REVIEW = """You are Aether's GPT fact-checker. You receive a raw AetherBot trading log
from a Kalshi KXBTC15M binary options session.

Log format (pipe-delimited):
  HH:MM:SS | YES price | NO price | seconds left | ABS spread | BPS change | PAQ (price-action quality) | CTX (context) STATE EXP (expansion) | BCDP (bid-change directional persistence)
  Special lines: NEW TICKER, STRIKE LOCKED, TICKER CLOSE, BUY/SELL actions, HARVEST, STOPLOSS, bal $X.XX

Your job:
1. INDEPENDENT ANALYSIS: Summarize the day's trading activity — how many tickers, any positions taken, P&L, balance changes.
2. PATTERN DETECTION: Identify recurring patterns — BDI events, session boundary behavior, conviction scoring anomalies, harvest attempts, spread compression/expansion cycles.
3. FACT-CHECK DECISIONS: For every BUY, SELL, HARVEST, or STOPLOSS action in the log, evaluate whether the decision was sound given the surrounding price action. Flag questionable entries/exits.
4. RISK ASSESSMENT: Identify any positions held through low-liquidity periods (high spread, low PAQ), BDI=0 forced exits, or sizing issues.
5. RECOMMENDATIONS: Propose STRUCTURAL improvements (not patchwork). Focus on multi-session patterns, not single-trade reactions. The operator has explicitly rejected reactive caps/kills.

Known issues to watch for:
- Phantom positions (bot thinks it holds a position it doesn't)
- Harvest failure rate (~12% success — flag if harvest attempts look doomed)
- COUNTER signal sizing (historically catastrophic when oversized)
- Balance reconciliation gaps between reported and actual
- Session boundary anomalies when new tickers start

Output format:
== DAILY LOG REVIEW: {date} ==
1. Session Summary (trades, tickers, P&L, balance)
2. Pattern Analysis (recurring signals, anomalies)
3. Decision Fact-Check (each trade evaluated)
4. Risk Flags (positions, sizing, timing)
5. Structural Recommendations (multi-session improvements)

Be direct. Be specific. Reference exact timestamps from the log. All times MTN."""


# ── GPT call ──────────────────────────────────────────────────────────────────

def call_gpt(content, key, system_prompt, model="gpt-4o", max_tokens=4000):
    data = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": content}
        ],
        "max_tokens": max_tokens,
        "temperature": 0.3
    }, ensure_ascii=False).encode("utf-8")

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=data,
        headers={
            "Authorization": "Bearer " + key.encode("ascii", "ignore").decode("ascii"),
            "Content-Type": "application/json; charset=utf-8"
        }
    )

    resp = urllib.request.urlopen(req, timeout=120)
    result = json.loads(resp.read())
    reply = result["choices"][0]["message"]["content"]
    usage = result.get("usage", {})
    # SE-011-003: Record API usage (non-fatal)
    try:
        import subprocess
        _root = os.environ.get("HYO_ROOT") or os.path.expanduser("~/Documents/Projects/Hyo")
        subprocess.run(
            ["bash", os.path.join(_root, "bin", "api-usage.sh"), "log",
             "openai", "aether", model,
             str(int(usage.get("prompt_tokens", 0) or 0)),
             str(int(usage.get("completion_tokens", 0) or 0)),
             "gpt_factcheck"],
            check=False, timeout=5, capture_output=True
        )
    except Exception:
        pass
    return reply, usage


# ── Find today's log file ────────────────────────────────────────────────────

def find_log_file(target_date):
    """Find AetherBot log for target_date. Check post-migration path first, then legacy."""
    filename = f"AetherBot_{target_date}.txt"

    # Post-migration path
    path1 = os.path.join(LOGS_DIR, filename)
    if os.path.exists(path1):
        return path1

    # Legacy path (logger still writes here on the Mini)
    path2 = os.path.join(LEGACY_LOGS_DIR, filename)
    if os.path.exists(path2):
        return path2

    return None


def find_analysis_file(target_date):
    """Find analysis file for target_date in agents/aether/analysis/."""
    candidates = [
        f"Final_Analysis_{target_date}.txt",
        f"Deep_Analysis_{target_date}.txt",
        f"Analysis_{target_date}.txt",
    ]
    for name in candidates:
        path = os.path.join(ANALYSIS_DIR, name)
        if os.path.exists(path):
            return path

    # Legacy fallback
    legacy_dir = os.path.expanduser("~/Documents/Projects/AetherBot/Kai analysis")
    for name in candidates:
        path = os.path.join(legacy_dir, name)
        if os.path.exists(path):
            return path

    return None


# ── Mode: Daily Log Review ────────────────────────────────────────────────────

def run_log_review(target_date, key):
    """Send today's raw AetherBot log to GPT for independent analysis + fact-check."""
    log_path = find_log_file(target_date)
    if not log_path:
        print(f"ERROR: No AetherBot log found for {target_date}")
        print(f"  Checked: {LOGS_DIR}/AetherBot_{target_date}.txt")
        print(f"  Checked: {LEGACY_LOGS_DIR}/AetherBot_{target_date}.txt")
        sys.exit(1)

    with open(log_path) as f:
        log_content = f.read()

    # Truncate if enormous (keep last ~80k chars which has recent activity)
    if len(log_content) > 80000:
        # Keep header (first 200 lines) + tail (most recent activity)
        lines = log_content.split("\n")
        header = "\n".join(lines[:200])
        tail = "\n".join(lines[-2000:])
        log_content = (
            header
            + f"\n\n[... {len(lines) - 2200} lines truncated — showing first 200 + last 2000 ...]\n\n"
            + tail
        )
        print(f"Log truncated from {len(lines)} lines to ~2200 lines")

    user_msg = (
        f"Review this raw AetherBot log for {target_date}.\n"
        f"Source file: {os.path.basename(log_path)}\n"
        f"Log size: {len(log_content):,} chars, "
        f"{log_content.count(chr(10))} lines\n\n"
        f"RAW LOG:\n{log_content}"
    )

    print(f"Loaded: {log_path} ({len(log_content):,} chars)")
    print("Sending to GPT-4o for daily log review...")

    try:
        review, usage = call_gpt(user_msg, key, SYSTEM_LOG_REVIEW, max_tokens=4000)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"API error HTTP {e.code}: {body[:300]}")
        sys.exit(1)

    print(f"GPT-4o response: {len(review):,} chars")
    print(f"Tokens: in={usage.get('prompt_tokens',0)} out={usage.get('completion_tokens',0)}")

    # Save to GPT_CrossCheck file
    crosscheck_path = os.path.join(ANALYSIS_DIR, f"GPT_CrossCheck_{target_date}.txt")
    now_str = datetime.datetime.now().strftime("%H:%M MTN")

    with open(crosscheck_path, "w") as f:
        f.write(f"{'='*78}\n")
        f.write(f"GPT-4o DAILY LOG REVIEW + FACT-CHECK -- {target_date}\n")
        f.write(f"Generated: {now_str}\n")
        f.write(f"Source: {os.path.basename(log_path)} ({log_content.count(chr(10))} lines)\n")
        f.write(f"Tokens: in={usage.get('prompt_tokens',0)} out={usage.get('completion_tokens',0)}\n")
        f.write(f"{'='*78}\n\n")
        f.write(review)
        f.write("\n")

    print(f"Saved: {crosscheck_path}")
    print("\n" + "=" * 60)
    print("GPT-4o DAILY LOG REVIEW:")
    print("=" * 60)
    print(review)

    return crosscheck_path


# ── Mode: Analysis Fact-Check (original) ──────────────────────────────────────

def run_analysis_factcheck(target_date, key):
    """Original mode: fact-check today's analysis file."""
    analysis_path = find_analysis_file(target_date)

    if not analysis_path:
        print(f"No analysis found for {target_date}")
        sys.exit(1)

    with open(analysis_path) as f:
        analysis = f.read()

    if len(analysis) > 100000:
        analysis = analysis[:100000] + "\n[TRUNCATED — see full file]"

    user_msg = (
        "Review this AetherBot daily analysis for errors, missed patterns, "
        "and simulation gaps.\n\n"
        "Focus on systemic issues, not single-session reactions. The operator "
        "has explicitly rejected patchwork fixes (caps, kills) based on one bad trade.\n\n"
        "Key question: Is there a STRUCTURAL issue in how conviction scoring "
        "behaves at session boundaries that would show up across multiple sessions?\n\n"
        f"ANALYSIS:\n{analysis}"
    )

    print(f"Loaded: {analysis_path} ({len(analysis):,} chars)")
    print("Sending to GPT-4o for fact-check...")

    try:
        critique, usage = call_gpt(user_msg, key, SYSTEM_ANALYSIS)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"API error HTTP {e.code}: {body[:300]}")
        sys.exit(1)

    print(f"GPT-4o response: {len(critique):,} chars")
    print(f"Tokens: in={usage.get('prompt_tokens',0)} out={usage.get('completion_tokens',0)}")

    # Append critique to analysis file
    with open(analysis_path, "a") as f:
        f.write(f"\n\n{'='*78}\n")
        f.write(f"GPT-4o FACT-CHECK -- {datetime.datetime.now().strftime('%H:%M MTN')}\n")
        f.write(f"{'='*78}\n\n")
        f.write(critique)
        f.write("\n")

    # Also save standalone cross-check file
    crosscheck_path = os.path.join(ANALYSIS_DIR, f"GPT_CrossCheck_{target_date}.txt")
    with open(crosscheck_path, "w") as f:
        f.write(f"{'='*78}\n")
        f.write(f"GPT-4o INDEPENDENT CROSS-CHECK -- {target_date}\n")
        f.write(f"Source: {os.path.basename(analysis_path)}\n")
        f.write(f"{'='*78}\n\n")
        f.write(critique)
        f.write("\n")

    print(f"Critique appended to {analysis_path}")
    print(f"Standalone saved to {crosscheck_path}")
    print("\n" + "=" * 60)
    print("GPT-4o CRITIQUE:")
    print("=" * 60)
    print(critique)

    return crosscheck_path


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    key = load_key()
    if not key:
        print("ERROR: No OpenAI API key found.")
        print(f"  Checked: {os.path.join(SECRETS_DIR, 'openai.key')}")
        print("  Checked: OPENAI_API_KEY env var")
        sys.exit(1)

    today = datetime.datetime.now().strftime("%Y-%m-%d")

    if "--log" in sys.argv:
        # Daily log review mode
        idx = sys.argv.index("--log")
        target_date = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else today
        run_log_review(target_date, key)
    else:
        # Default: analysis fact-check
        target_date = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("-") else today
        run_analysis_factcheck(target_date, key)


if __name__ == "__main__":
    main()
