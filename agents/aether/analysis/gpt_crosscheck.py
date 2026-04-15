#!/usr/bin/env python3
"""
GPT-4o adversarial cross-check for AetherBot daily analysis.
Reads analysis files, sends to GPT, saves response.
"""
import json, os, sys, urllib.request, urllib.error
from pathlib import Path
from datetime import datetime

ROOT = Path(__file__).resolve().parent.parent.parent.parent  # Hyo/
SECURITY = ROOT / "agents" / "nel" / "security"
ANALYSIS_DIR = Path(__file__).resolve().parent

# Load key
key_path = SECURITY / "openai.key"
if not key_path.exists():
    # Try ~/security/hyo.env
    env_path = Path.home() / "security" / "hyo.env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("OPENAI_API_KEY="):
                key = line.split("=", 1)[1].strip()
                break
        else:
            print("ERROR: No OPENAI_API_KEY in hyo.env")
            sys.exit(1)
    else:
        print("ERROR: No openai.key or hyo.env found")
        sys.exit(1)
else:
    key = key_path.read_text().strip()

if "your" in key.lower() or len(key) < 20:
    print(f"ERROR: Key looks like a placeholder: {key[:20]}...")
    sys.exit(1)

# Determine which date to analyze
date_arg = sys.argv[1] if len(sys.argv) > 1 else "2026-04-14"
analysis_file = ANALYSIS_DIR / f"Analysis_{date_arg}.txt"

if not analysis_file.exists():
    print(f"ERROR: {analysis_file} not found")
    sys.exit(1)

analysis_text = analysis_file.read_text()

system_prompt = """You are GPT-4o, acting as the adversarial fact-checker for AetherBot daily analysis.
Your role: challenge the reasoning, find math errors, identify gaps, and surface anything the primary analyst (Claude) may have missed or gotten wrong.

Context: AetherBot is a real-money Kalshi BTC 15-minute binary options trading bot (KXBTC15M).
Current deployed version: v253/v254. Balance as of Tuesday EOD: $103.67.

Rules for your review:
1. Check all math (P&L sums, win rates, phantom gap calculations)
2. Challenge any conclusions not backed by specific log evidence
3. Flag any patchwork recommendations (reactive fixes to single trades)
4. Identify what the analyst missed or should have investigated deeper
5. Be direct. No hedging. If the analysis is solid, say so and explain why.
6. If you disagree with the recommendation, state your alternative and evidence.

Format your response as:
MATH CHECK: [pass/fail with specifics]
LOGIC CHECK: [any reasoning gaps]
MISSED PATTERNS: [what wasn't investigated]
RECOMMENDATION REVIEW: [agree/disagree with evidence]
OVERALL VERDICT: [1-2 sentences]"""

user_msg = f"""Review this AetherBot daily analysis for {date_arg}.
Challenge the reasoning, check the math, find what's missing.

{analysis_text}"""

payload = {
    "model": "gpt-4o",
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_msg}
    ],
    "temperature": 0.3,
    "max_tokens": 2000
}

req = urllib.request.Request(
    "https://api.openai.com/v1/chat/completions",
    data=json.dumps(payload).encode(),
    headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json"
    }
)

print(f"Sending {date_arg} analysis to GPT-4o...")
try:
    with urllib.request.urlopen(req, timeout=90) as resp:
        result = json.loads(resp.read())
        gpt_response = result["choices"][0]["message"]["content"]

        # Print to console
        print("\n" + "=" * 70)
        print(f"GPT-4o CROSS-CHECK — {date_arg}")
        print("=" * 70)
        print(gpt_response)

        # Save to file
        out_file = ANALYSIS_DIR / f"GPT_Review_{date_arg}.txt"
        out_file.write_text(
            f"{'=' * 70}\n"
            f"GPT-4o ADVERSARIAL CROSS-CHECK — {date_arg}\n"
            f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S MT')}\n"
            f"Model: gpt-4o | Temp: 0.3\n"
            f"{'=' * 70}\n\n"
            f"{gpt_response}\n"
        )
        print(f"\nSaved to: {out_file}")

except urllib.error.HTTPError as e:
    print(f"HTTP ERROR {e.code}: {e.read().decode()[:500]}")
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
