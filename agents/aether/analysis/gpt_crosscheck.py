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
        return result["choices"][0]["message"]["content"]


# ═══════════════════════════════════════════════════════════════════════════════
# PHASE 1: GPT INDEPENDENT ANALYSIS (from raw logs only)
# ═══════════════════════════════════════════════════════════════════════════════

phase1_output = None

if raw_log_text:
    print(f"\n{'=' * 70}")
    print(f"PHASE 1: GPT independent analysis from raw logs — {date_arg}")
    print(f"{'=' * 70}")

    phase1_system = """You are GPT-4o, an independent trading analyst for AetherBot.
You are analyzing the RAW TRADING LOG for a Kalshi BTC 15-minute binary options bot (KXBTC15M).
You have NOT seen anyone else's analysis. Form your own conclusions.

Context:
- AetherBot trades KXBTC15M (15-min BTC binary options on Kalshi)
- Current version: v253/v254
- Strategies: bps_premium (backbone), PAQ_EARLY_AGG (high-variance), PAQ_STRUCT_GATE (low-ABS lane), bps_late, WES_EARLY, BCDP_FAST_COMMIT
- Harvest system: SPHI_DECAY strategy for partial exits before settlement
- Known issue: "POS WARNING: API 0 local N" = phantom positions (bot thinks it holds contracts that Kalshi doesn't show)
- Session windows (MTN): OVERNIGHT (00-03), EU_MORNING (03-05), ASIA_OPEN (05-07), NY_OPEN (07-09:30), NY_PRIME (09:30-12), AFTERNOON (12-17), EVENING (17-21)

Your job:
1. Count all trades from BUY SNAPSHOT entries
2. Track balance changes from ticker/settlement lines
3. Identify the starting and ending balance (ground truth)
4. Calculate actual P&L from balance change (not from settlement claims)
5. Note any POS WARNING lines and count them
6. Identify the biggest winner and biggest loser
7. Assess harvest success (DONE vs MISS counts)
8. Identify which strategies performed best/worst
9. Note any patterns, anomalies, or concerns
10. Give your honest recommendation

Format your response as:

INDEPENDENT ANALYSIS — [date]

BALANCE: Start $X.XX → End $X.XX | Actual Net: +/-$X.XX
TRADES: N total | NW / NL (X% WR)
BTC: $X → $X (+/-X%)

KEY FINDINGS:
• [3-5 bullet points of what you found in the raw data]

STRATEGY PERFORMANCE:
• [Per-strategy breakdown with trade counts and net P&L where calculable]

CONCERNS:
• [Anything that worries you — phantom positions, large losses, patterns]

RECOMMENDATION:
• [Your honest recommendation based solely on what the raw data shows]"""

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

phase2_system = f"""You are GPT-4o, acting as the adversarial fact-checker for AetherBot daily analysis.

{phase2_context}

Your job in Phase 2:
1. Compare Kai's analysis against your own independent findings (if available)
2. Check all math (P&L sums, win rates, phantom gap calculations)
3. Fact-check: does Kai's analysis match what the raw data actually shows?
4. Identify anything Kai missed that you found in the raw data
5. Identify anything Kai got wrong — numbers, conclusions, recommendations
6. If you AGREE with the recommendation, say so and explain why
7. If you DISAGREE, state your alternative and the evidence from the raw data
8. Be direct. No hedging. If the analysis is solid, say so.

Format your response as:
COMPARATIVE REVIEW — [date]

MATH CHECK: [pass/fail with specifics — compare against your own calculations]
FACT CHECK: [does Kai's analysis match the raw data? discrepancies?]
LOGIC CHECK: [any reasoning gaps or conclusions not backed by evidence]
MISSED PATTERNS: [what Kai missed that you found in the raw data]
WHERE I DISAGREE: [specific points of disagreement, if any]
WHERE I AGREE: [specific points of agreement]
RECOMMENDATION REVIEW: [agree/disagree with Kai's recommendation, with evidence]
OVERALL VERDICT: [2-3 sentences]"""

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
