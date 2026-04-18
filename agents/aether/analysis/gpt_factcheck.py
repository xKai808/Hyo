#!/usr/bin/env python3
"""
GPT-4o Fact-Check for AetherBot — Two-Phase Independence Gate
==============================================================
S18-017: Guarantees GPT independence before cross-review.

THREE modes:
  1. --phase1 (alias: --log): GPT sees RAW LOG ONLY.
     Output: GPT_Independent_DATE.txt
     Purpose: form an independent view before seeing Kai's analysis.

  2. --phase2: GPT sees Kai's analysis + Phase 1 independent output.
     Output: GPT_Review_DATE.txt
     GATE: aborts with exit 2 if GPT_Independent_DATE.txt is missing.
     Purpose: adversarial cross-check — compare independent view to Kai's.

  3. Default (no flag): legacy analysis fact-check (deprecated, use --phase2).
     Output: GPT_CrossCheck_DATE.txt

Independence gate rule:
  Phase 2 NEVER runs without Phase 1 output. This prevents GPT from being
  seeded with Kai's framing before forming its own view. aether.sh enforces
  this: run Phase 1 first, check exit code, only then run Phase 2.

Usage:
  python3 gpt_factcheck.py --phase1             # Phase 1: raw log → GPT_Independent
  python3 gpt_factcheck.py --phase1 2026-04-11  # specific date
  python3 gpt_factcheck.py --phase2             # Phase 2: analysis + Phase1 → GPT_Review
  python3 gpt_factcheck.py --phase2 2026-04-11  # specific date
  python3 gpt_factcheck.py --log                # alias for --phase1
  python3 gpt_factcheck.py                      # legacy: analysis fact-check only

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

# S18-017: Phase 2 — Cross-review prompt. GPT receives BOTH its own independent
# Phase 1 output AND Kai's analysis. It compares and surfaces divergences.
SYSTEM_PHASE2_CROSS_REVIEW = """You are Aether's adversarial cross-reviewer. You have two inputs:
1. Your OWN Phase 1 independent analysis (formed without seeing Kai's work)
2. Kai's analysis of the same session

Your job: find the GAPS between them.

Specifically:
- What did you find in Phase 1 that Kai MISSED or downplayed?
- What did Kai conclude that your Phase 1 analysis CONTRADICTS?
- Where did Kai frame something correctly that you initially misread?
- What is the highest-value insight from Phase 1 that Kai should incorporate?

Output structure:
CROSS-REVIEW VERDICT: [ALIGNED / DIVERGENT / CONTRADICTORY]

SECTION 1: AGREEMENTS
- List findings where Phase 1 and Kai's analysis agree (briefly)

SECTION 2: KAI MISSED (Phase 1 found this, Kai didn't)
- For each: quote the specific Phase 1 finding, describe what Kai said/didn't say,
  state why this matters

SECTION 3: CONTRADICTIONS (Phase 1 vs Kai conflict)
- For each: state both positions, which is more likely correct and why

SECTION 4: PHASE 1 ERRORS CORRECTED BY KAI
- Where Kai's deeper analysis reveals a Phase 1 mistake

SECTION 5: ACTION DELTA
- What Kai should add/change in their analysis based on this cross-review
- Be specific: "Kai's recommendation to X is [supported/undermined] by Phase 1's finding that Y"

Rules:
- Do NOT produce arithmetic summaries — find structural insights
- Every dollar GPT earns must produce something Kai didn't have
- If Kai and Phase 1 fully agree, say so concisely — don't pad
- All times MTN"""

SYSTEM_LOG_REVIEW = """You are Aether's daily analyst. You receive a raw AetherBot trading log
from a Kalshi KXBTC15M binary options session.

Log format (pipe-delimited):
  HH:MM:SS | YES price | NO price | seconds left | ABS spread | BPS change | PAQ (price-action quality) | CTX (context) STATE EXP (expansion) | BCDP (bid-change directional persistence)
  Special lines: NEW TICKER, STRIKE LOCKED, TICKER CLOSE, BUY/SELL actions, HARVEST, STOPLOSS, bal $X.XX
  Trade lifecycle: BUY SNAPSHOT (entry) → position management → TICKER CLOSE (outcome summary)

Your output must follow this EXACT structure (9 parts). This is non-negotiable:

PART 1: BALANCE LEDGER UPDATE
  - First balance line, last balance line, day net
  - Running balance ledger continuity (reference prior day if available)
  - Clearly mark confirmed EOD vs live/estimated figures

PART 2: TRADE-BY-TRADE LEDGER BY FAMILY
  - Group by strategy family (PAQ_EARLY_AGG, bps_premium, PAQ_STRUCT_GATE, etc.)
  - EVERY trade: timestamp, side, entry price, contracts, outcome (WIN/LOSS), net P&L
  - Include exit mechanism details (harvest, stop, BDI=0 hold, TIME_BDI_LOW, FLIP_EMERGENCY)
  - Strategy subtotal: net P&L, trade count, W/L, win rate
  - Day net at bottom

PART 3: SESSION WINDOW BREAKDOWN
  - EU_MORNING (03:00–05:00 MTN): individual trades + net + cross-session pattern
  - ASIA_OPEN (00:00–03:00 MTN): individual trades + net
  - NY_PRIME (09:00–15:00 MTN): individual trades + net (this is the profit engine)
  - EVENING (17:00–22:00 MTN): individual trades + net + regime assessment
  - For each window: is it net positive/negative? Is the pattern regime-driven or structural?

PART 4: STOP AND HARVEST EVENT LOG
  - Every harvest attempt: success or miss? Diagnose miss cause (Mode A: thin book, Mode B: stale book)
  - Every BDI=0 hold: what happened? seconds_left at trigger? Did position expire?
  - Every POS WARNING: API state vs local state discrepancy details
  - Every FLIP_EMERGENCY or EXIT_ESCALATED: was it correct?

PART 5: NEW FAMILIES OBSERVED
  - Any new strategy families appearing for the first time
  - DO NOT evaluate with <10 trades. Monitor and log only.

PART 6: STRATEGY WATCH STATUS
  - For any strategy with 3+ sessions of degrading performance:
    Separate mechanism failures (BDI=0 hold at expiry) from strategy failures (bad entries)
    Cross-check BTC regime before recommending gates
    State the kill threshold requirements (5+ sessions, no positive-EV environment, Hyo approval)
    DO NOT recommend killing a strategy from one bad session

PART 7: SYSTEMIC PATTERNS
  - Identify 2-4 patterns with cross-session evidence
  - Each pattern: evidence (timestamps + specifics), mechanism hypothesis, recommended action
  - Classify each: BUILD (code change) vs MONITOR (more data needed) vs NOTHING (market variance)

PART 8: RECOMMENDATION
  - ONE build recommendation with specific scope and priority
  - No entry changes unless backed by 5+ sessions of data
  - Name the NEXT DECISION POINT (what data do we need to see before the next change?)
  - The goal: find the ONE pattern that changes the next decision

PART 9: BALANCE LEDGER (running)
  - Updated cumulative balance table from inception through today

CRITICAL RULES:
- Do NOT recommend position caps or strategy kills from a single session
- Do NOT produce arithmetic summaries — produce adversarial intelligence
- Separate market variance from code bugs from mechanism failures
- Reference exact timestamps from the log. All times MTN.
- Every GPT dollar spent must produce an insight Kai didn't have. If your output is
  just "balance is X and trades were Y" — you have failed. Find what Kai missed."""


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


# ── Mode: Phase 1 — Independent Log Review ───────────────────────────────────
# S18-017: GPT sees ONLY the raw log. No Kai analysis. No framing.
# Output: GPT_Independent_DATE.txt
# This file is required before Phase 2 can run (independence gate).

def run_phase1_independent(target_date, key):
    """Phase 1: Send raw AetherBot log to GPT — independent, no Kai analysis seeding.
    Output: agents/aether/analysis/GPT_Independent_DATE.txt
    This file MUST exist before Phase 2 runs.
    """
    log_path = find_log_file(target_date)
    if not log_path:
        print(f"ERROR: No AetherBot log found for {target_date}")
        print(f"  Checked: {LOGS_DIR}/AetherBot_{target_date}.txt")
        print(f"  Checked: {LEGACY_LOGS_DIR}/AetherBot_{target_date}.txt")
        sys.exit(1)

    with open(log_path) as f:
        log_content = f.read()

    # Truncate if enormous (keep first 200 lines header + last 2000 lines for recency)
    if len(log_content) > 80000:
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
        f"[PHASE 1 — INDEPENDENT REVIEW]\n"
        f"Review this raw AetherBot log for {target_date}.\n"
        f"You have NOT seen any other analysis. Form your own view first.\n"
        f"Source file: {os.path.basename(log_path)}\n"
        f"Log size: {len(log_content):,} chars, "
        f"{log_content.count(chr(10))} lines\n\n"
        f"RAW LOG:\n{log_content}"
    )

    print(f"[Phase 1] Loaded: {log_path} ({len(log_content):,} chars)")
    print("[Phase 1] Sending to GPT-4o — INDEPENDENT review (no Kai analysis)...")

    try:
        review, usage = call_gpt(user_msg, key, SYSTEM_LOG_REVIEW, max_tokens=12000)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"API error HTTP {e.code}: {body[:300]}")
        sys.exit(1)

    print(f"[Phase 1] GPT-4o response: {len(review):,} chars")
    print(f"[Phase 1] Tokens: in={usage.get('prompt_tokens',0)} out={usage.get('completion_tokens',0)}")

    # Save to GPT_Independent_DATE.txt (independence gate file)
    independent_path = os.path.join(ANALYSIS_DIR, f"GPT_Independent_{target_date}.txt")
    # Also maintain backward-compat GPT_CrossCheck file
    crosscheck_path = os.path.join(ANALYSIS_DIR, f"GPT_CrossCheck_{target_date}.txt")
    now_str = datetime.datetime.now().strftime("%H:%M MTN")

    content = (
        f"{'='*78}\n"
        f"GPT-4o PHASE 1 — INDEPENDENT LOG REVIEW -- {target_date}\n"
        f"Generated: {now_str}\n"
        f"Source: {os.path.basename(log_path)} ({log_content.count(chr(10))} lines)\n"
        f"Tokens: in={usage.get('prompt_tokens',0)} out={usage.get('completion_tokens',0)}\n"
        f"NOTE: This file was generated WITHOUT Kai's analysis (independence gate).\n"
        f"{'='*78}\n\n"
        + review + "\n"
    )

    with open(independent_path, "w") as f:
        f.write(content)
    with open(crosscheck_path, "w") as f:
        f.write(content)

    print(f"[Phase 1] Saved: {independent_path}")
    print(f"[Phase 1] Also mirrored to: {crosscheck_path}")
    print("\n" + "=" * 60)
    print("GPT-4o PHASE 1 — INDEPENDENT REVIEW:")
    print("=" * 60)
    print(review)

    return independent_path


# ── Mode: Phase 2 — Cross-Review (Independence Gate) ─────────────────────────
# S18-017: GPT sees BOTH its Phase 1 output AND Kai's analysis.
# Gate: aborts with exit code 2 if GPT_Independent_DATE.txt doesn't exist.
# Output: GPT_Review_DATE.txt

def run_phase2_cross_review(target_date, key):
    """Phase 2: Cross-review using Phase 1 + Kai's analysis.
    GATE: exits with code 2 if GPT_Independent_DATE.txt is missing.
    Output: agents/aether/analysis/GPT_Review_DATE.txt
    """
    # ── Independence gate ──────────────────────────────────────────────────────
    independent_path = os.path.join(ANALYSIS_DIR, f"GPT_Independent_{target_date}.txt")
    if not os.path.exists(independent_path):
        print(f"[Phase 2] GATE BLOCKED: GPT_Independent_{target_date}.txt not found.")
        print(f"  Run Phase 1 first: python3 gpt_factcheck.py --phase1 {target_date}")
        print(f"  Phase 2 requires Phase 1 output to prevent analysis seeding.")
        sys.exit(2)  # exit 2 = gate blocked (distinct from error exit 1)

    # ── Load Phase 1 output ───────────────────────────────────────────────────
    with open(independent_path) as f:
        phase1_content = f.read()

    # ── Load Kai's analysis ───────────────────────────────────────────────────
    analysis_path = find_analysis_file(target_date)
    if not analysis_path:
        print(f"[Phase 2] WARNING: No Kai analysis found for {target_date}")
        print(f"  Checked candidates: Final_Analysis, Deep_Analysis, Analysis")
        kai_analysis = "[No Kai analysis available for this date]"
    else:
        with open(analysis_path) as f:
            kai_analysis = f.read()
        if len(kai_analysis) > 60000:
            kai_analysis = kai_analysis[:60000] + "\n[TRUNCATED]"
        print(f"[Phase 2] Loaded Kai analysis: {analysis_path} ({len(kai_analysis):,} chars)")

    print(f"[Phase 2] Loaded Phase 1: {independent_path} ({len(phase1_content):,} chars)")

    user_msg = (
        f"[PHASE 2 — CROSS-REVIEW] Date: {target_date}\n\n"
        f"You will compare your own Phase 1 independent analysis with Kai's analysis.\n"
        f"Find the gaps, contradictions, and missed insights.\n\n"
        f"{'='*78}\n"
        f"PHASE 1 — YOUR INDEPENDENT ANALYSIS:\n"
        f"{'='*78}\n"
        f"{phase1_content}\n\n"
        f"{'='*78}\n"
        f"KAI'S ANALYSIS:\n"
        f"{'='*78}\n"
        f"{kai_analysis}\n"
    )

    print("[Phase 2] Sending cross-review to GPT-4o...")

    try:
        cross_review, usage = call_gpt(
            user_msg, key, SYSTEM_PHASE2_CROSS_REVIEW, max_tokens=6000
        )
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        print(f"API error HTTP {e.code}: {body[:300]}")
        sys.exit(1)

    print(f"[Phase 2] GPT-4o response: {len(cross_review):,} chars")
    print(f"[Phase 2] Tokens: in={usage.get('prompt_tokens',0)} out={usage.get('completion_tokens',0)}")

    # Save to GPT_Review_DATE.txt
    review_path = os.path.join(ANALYSIS_DIR, f"GPT_Review_{target_date}.txt")
    now_str = datetime.datetime.now().strftime("%H:%M MTN")

    with open(review_path, "w") as f:
        f.write(f"{'='*78}\n")
        f.write(f"GPT-4o PHASE 2 — CROSS-REVIEW -- {target_date}\n")
        f.write(f"Generated: {now_str}\n")
        f.write(f"Independence gate: passed (GPT_Independent_{target_date}.txt present)\n")
        f.write(f"Kai analysis: {os.path.basename(analysis_path) if analysis_path else 'NOT FOUND'}\n")
        f.write(f"Tokens: in={usage.get('prompt_tokens',0)} out={usage.get('completion_tokens',0)}\n")
        f.write(f"{'='*78}\n\n")
        f.write(cross_review)
        f.write("\n")

    # Also append to Kai's analysis file if it exists (so the full picture is in one place)
    if analysis_path:
        with open(analysis_path, "a") as f:
            f.write(f"\n\n{'='*78}\n")
            f.write(f"GPT-4o PHASE 2 CROSS-REVIEW -- {now_str}\n")
            f.write(f"[Full review: GPT_Review_{target_date}.txt]\n")
            f.write(f"{'='*78}\n\n")
            f.write(cross_review[:3000])  # First 3000 chars inline, full in separate file
            if len(cross_review) > 3000:
                f.write(f"\n[... see GPT_Review_{target_date}.txt for complete review ...]\n")
            f.write("\n")

    print(f"[Phase 2] Saved: {review_path}")
    print("\n" + "=" * 60)
    print("GPT-4o PHASE 2 — CROSS-REVIEW:")
    print("=" * 60)
    print(cross_review)

    return review_path


# ── Backward-compat alias ─────────────────────────────────────────────────────
def run_log_review(target_date, key):
    """Backward-compatible alias for run_phase1_independent."""
    return run_phase1_independent(target_date, key)


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
    args = sys.argv[1:]

    # ── S18-017: Two-phase independence gate ──────────────────────────────────
    if "--phase1" in args or "--log" in args:
        # Phase 1: GPT sees raw log ONLY → GPT_Independent_DATE.txt
        flag = "--phase1" if "--phase1" in args else "--log"
        idx = args.index(flag)
        target_date = args[idx + 1] if idx + 1 < len(args) and not args[idx + 1].startswith("-") else today
        run_phase1_independent(target_date, key)

    elif "--phase2" in args:
        # Phase 2: GPT sees Phase1 + Kai analysis → GPT_Review_DATE.txt
        # GATE: exits 2 if GPT_Independent_DATE.txt missing
        idx = args.index("--phase2")
        target_date = args[idx + 1] if idx + 1 < len(args) and not args[idx + 1].startswith("-") else today
        run_phase2_cross_review(target_date, key)

    else:
        # Default: legacy analysis fact-check (still supported, use --phase2 for full independence)
        target_date = args[0] if args and not args[0].startswith("-") else today
        print(f"[LEGACY] Running analysis fact-check. Use --phase1/--phase2 for full independence.")
        run_analysis_factcheck(target_date, key)


if __name__ == "__main__":
    main()
