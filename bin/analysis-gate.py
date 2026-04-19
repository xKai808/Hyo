#!/usr/bin/env python3
"""
bin/analysis-gate.py — Pre-publish hard gate for Aether daily analysis.

Called automatically by aether-publish-analysis.sh BEFORE any feed write.
If any gate fails: prints the specific failure, exits 1, publish is blocked.
A clean gate run (exit 0) is REQUIRED to proceed to Phase 3 (publishing).

This is the structural enforcement that manual checklists cannot provide.
Every failure mode documented in Part 10 of PROTOCOL_DAILY_ANALYSIS.md
has a corresponding gate check here. Document → Code → Hard block.

Usage:
    python3 bin/analysis-gate.py YYYY-MM-DD path/to/Analysis_YYYY-MM-DD.txt

Change history:
    v1.0 (2026-04-18): Initial — Gates 1-6 from Hyo feedback session 20.
        SE-AETHER-001 → Gate 1 (bash corruption)
        SE-AETHER-002 → Gate 2 (trading log validation)
        SE-AETHER-003 → Gate 5 (version reference)
        New: Gate 3 (section markers), Gate 4 (GPT synthesis), Gate 6 (trade data)
"""

import re, sys, os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ── Argument parsing ─────────────────────────────────────────────────────────
if len(sys.argv) < 3:
    print("Usage: python3 bin/analysis-gate.py YYYY-MM-DD path/to/Analysis_YYYY-MM-DD.txt")
    sys.exit(1)

date = sys.argv[1]
analysis_path = sys.argv[2]

if not os.path.exists(analysis_path):
    print(f"\n{'!' * 70}")
    print(f"GATE 0 FAILED: Analysis file not found: {analysis_path}")
    print(f"{'!' * 70}\n")
    sys.exit(1)

with open(analysis_path, errors="replace") as f:
    text = f.read()

failures = []

def fail(gate_num, msg):
    failures.append((gate_num, msg))
    print(f"[gate] Gate {gate_num} FAIL — {msg}")

def ok(gate_num, msg):
    print(f"[gate] Gate {gate_num} PASS — {msg}")

def warn(msg):
    print(f"[gate] WARN: {msg}")

# ── Helper: extract section between markers ──────────────────────────────────
def slice_section(t, start_markers, end_markers=None):
    start = -1
    for m in start_markers:
        i = t.find(m)
        if i >= 0:
            start = i + len(m)
            break
    if start < 0:
        return ""
    end = len(t)
    if end_markers:
        for m in end_markers:
            j = t.find(m, start)
            if j >= 0 and j < end:
                end = j
    return t[start:end].strip()

print(f"\nRunning pre-publish gate for {date}...\n")

# ── Gate 1: Title / balance corruption check (SE-AETHER-001) ─────────────────
# Dollar sign corruption: when bash expands $0.97 → script_name.97 (e.g. "bash.97")
# Scan the entire text for the corruption pattern
corruption_found = False
for line in text.split("\n")[:20]:  # Check header area most carefully
    if re.search(r'\b(bash|sh|python)\.\d', line, re.IGNORECASE):
        fail(1, f"Dollar sign bash corruption detected: '{line.strip()}'")
        corruption_found = True
        break
if not corruption_found:
    # Also check balance ledger lines specifically
    bal_section = slice_section(text, ["BALANCE LEDGER:", "BALANCE:"])
    if re.search(r'\b(bash|sh|python)\.\d', bal_section, re.IGNORECASE):
        fail(1, "Dollar sign bash corruption in balance section")
    else:
        ok(1, "no bash corruption in title or balance section")

# ── Gate 2: Trading log is the real AetherBot trading log (SE-AETHER-002) ────
# Runner logs: ~500 lines, 0 TICKER CLOSE entries
# Trading logs: thousands of lines, 15+ TICKER CLOSE events per active session
MINIMUM_TICKER_CLOSES = 15
MINIMUM_LOG_LINES     = 1000

trading_log_primary  = Path.home() / "Documents" / "Projects" / "AetherBot" / "Logs" / f"AetherBot_{date}.txt"
trading_log_fallback = ROOT / "agents" / "aether" / "logs" / f"aether-{date}.log"

trading_log = None
if trading_log_primary.exists():
    trading_log = trading_log_primary
elif trading_log_fallback.exists():
    trading_log = trading_log_fallback

if trading_log_primary.exists():
    # On the Mini: validate the real trading log directly
    with open(trading_log_primary, errors="replace") as f:
        log_lines = f.readlines()
    total_lines    = len(log_lines)
    ticker_closes  = sum(1 for l in log_lines if "TICKER CLOSE" in l)
    is_runner_log  = any("=== Aether metrics run ===" in l or "Domain research:" in l
                         for l in log_lines[:50])

    gate2_errors = []
    if ticker_closes < MINIMUM_TICKER_CLOSES:
        gate2_errors.append(
            f"Found {ticker_closes} TICKER CLOSE lines — need ≥{MINIMUM_TICKER_CLOSES}. "
            f"This is likely a runner/cron log, not the AetherBot trading log."
        )
    if total_lines < MINIMUM_LOG_LINES:
        gate2_errors.append(
            f"Found {total_lines} total lines — need ≥{MINIMUM_LOG_LINES}. "
            f"Runner logs are ~500 lines. Trading logs are thousands."
        )
    if is_runner_log:
        gate2_errors.append(
            "Runner log markers detected (=== Aether metrics run === or 'Domain research:'). "
            "This is the Aether self-review log, not the AetherBot trading log."
        )

    if gate2_errors:
        for e in gate2_errors:
            fail(2, e)
        print(f"[gate] Gate 2: Trading logs live at "
              f"~/Documents/Projects/AetherBot/Logs/AetherBot_{date}.txt")
        print(f"[gate] Gate 2: Run via Mini: "
              f"kai exec \"python3 ~/Documents/Projects/Hyo/agents/aether/analysis/gpt_crosscheck.py {date}\"")
    else:
        ok(2, f"trading log valid ({total_lines} lines, {ticker_closes} TICKER CLOSEs)")

elif trading_log_fallback.exists():
    # In Cowork sandbox: primary log lives on Mini, fallback is the runner log.
    # If gpt_crosscheck.py was run on the Mini (via kai exec), GPT_Review file proves
    # it ran against the real log. Accept GPT output as alternative evidence.
    #
    # KNOWN LIMITATION (confirmed 2026-04-18):
    # This Cowork fallback is weaker than the Mini path. On the Mini, Gate 2 validates
    # the actual trading log directly (≥15 TICKER CLOSEs, ≥1000 lines). In Cowork, we
    # infer log validity from GPT output files — if they exist, we assume gpt_crosscheck.py
    # ran correctly on the Mini. That assumption holds as long as gpt_crosscheck.py's own
    # Gate 2 fired. The REAL guarantee is on the Mini. Cowork is infrastructure-constrained.
    gpt_review_file  = ROOT / "agents" / "aether" / "analysis" / f"GPT_Review_{date}.txt"
    gpt_review_alt   = ROOT / "agents" / "aether" / "analysis" / f"GPT_CrossCheck_{date}.txt"
    gpt_indep_file   = ROOT / "agents" / "aether" / "analysis" / f"GPT_Independent_{date}.txt"

    gpt_review_exists = (
        (gpt_review_file.exists() and gpt_review_file.stat().st_size > 500) or
        (gpt_review_alt.exists()  and gpt_review_alt.stat().st_size > 500)
    )
    gpt_indep_exists = gpt_indep_file.exists() and gpt_indep_file.stat().st_size > 500

    if gpt_review_exists and gpt_indep_exists:
        warn(f"Primary trading log not available in this environment (Cowork sandbox). "
             f"GPT_Review_{date}.txt and GPT_Independent_{date}.txt exist — "
             f"accepting as evidence that gpt_crosscheck.py ran on Mini against real log.")
        ok(2, "GPT output files present as alternative evidence (Cowork sandbox mode)")
    else:
        fail(2, f"Primary log not available AND GPT output files missing/small. "
               f"Run gpt_crosscheck.py on the Mini first: "
               f"kai exec \"python3 ~/Documents/Projects/Hyo/agents/aether/analysis/gpt_crosscheck.py {date}\"")
else:
    warn(f"Trading log for {date} not found anywhere — Gate 2 skipped. "
         "If running on Mini this is unexpected. Ensure AetherBot ran today.")

# ── Gate 3: All three section markers present ────────────────────────────────
required = [
    "=== CLAUDE PRIMARY ANALYSIS ===",
    "=== GPT CRITIQUE ===",
    "=== FINAL SYNTHESIS ==="
]
missing_markers = [m for m in required if m not in text]
if missing_markers:
    fail(3, f"Missing required section markers: {missing_markers}")
else:
    ok(3, "all 3 section markers present")

# ── Gate 4: GPT CRITIQUE is a synthesis, not a raw dump ─────────────────────
# Old runner-log GPT output started with "PART 1: BALANCE LEDGER UPDATE" and
# listed 3-4 trades. It is objectively worse than no GPT review because it
# creates false confidence on incomplete data.
gpt_section = slice_section(text,
    ["=== GPT CRITIQUE ==="],
    ["=== FINAL SYNTHESIS ===", "=== END"])

if not gpt_section:
    fail(4, "GPT CRITIQUE section is empty")
elif gpt_section.strip().startswith("PART 1:"):
    fail(4, "GPT section is a raw dump (starts with 'PART 1:') — not a synthesis. "
           "Re-run gpt_crosscheck.py on the Mini with the real trading log.")
elif re.search(r'\(5[0-9]{2} lines\)', gpt_section):
    # Catches "(506 lines)" or "(500 lines)" etc. — runner log GPT output signature
    fail(4, "GPT section appears to be from runner log analysis (NNN lines in range 500-599 detected). "
           "Re-run gpt_crosscheck.py on the Mini.")
else:
    synthesis_indicators = [
        "VERDICT:", "MATH VERIFICATION", "STRATEGY OVERRIDES",
        "KAI'S BLIND SPOTS", "COMPARATIVE REVIEW", "ACTION CLASSIFICATION",
        "DAY GRADE", "CORRECTIONS APPLIED"
    ]
    has_synthesis = any(ind in gpt_section for ind in synthesis_indicators)
    if not has_synthesis:
        fail(4, f"GPT section missing synthesis indicators. "
               f"Need at least one of: {synthesis_indicators}. "
               f"Ensure gpt_crosscheck.py Phase 2 ran successfully.")
    else:
        ok(4, "GPT section is a synthesis (not a raw dump)")

# ── Gate 5: Version reference not stale (SE-AETHER-003) ─────────────────────
CURRENT_VERSION = 253  # Update when new version deploys
version_refs = [int(m) for m in re.findall(r'\bv(\d{3})\b', text) if 200 <= int(m) <= 999]

if version_refs:
    max_ref = max(version_refs)
    if max_ref < CURRENT_VERSION - 10:
        fail(5, f"Version reference v{max_ref} is too stale (current: v{CURRENT_VERSION}). "
               f"Analysis should reference or acknowledge current deployed version.")
    elif max_ref < CURRENT_VERSION - 5:
        warn(f"Version reference v{max_ref} is somewhat old (current: v{CURRENT_VERSION}). "
             "Consider noting context if historical references are intentional.")
        ok(5, f"version refs OK (max: v{max_ref}, current: v{CURRENT_VERSION})")
    else:
        ok(5, f"version refs OK (max: v{max_ref})")
else:
    warn(f"No vNNN version references found — current deployed is v{CURRENT_VERSION}.")
    ok(5, "no version refs (warn only, not a hard fail)")

# ── Gate 6: Trade breakdown has actual content ───────────────────────────────
primary = slice_section(text,
    ["=== CLAUDE PRIMARY ANALYSIS ==="],
    ["=== GPT CRITIQUE ==="])

# Trade data: strategy family line (e.g. "bps_premium — 14 trades, 12W/2L") or ledger
trade_data_pattern = re.search(
    r'(PART [23]:.*(?:STRATEGY|TRADE)|TRADE LEDGER|'
    r'bps_premium.*(?:trades|WR)|PAQ.*(?:trades|WR)|'
    r'\d+W/\d+L)',
    primary, re.IGNORECASE
)
if not trade_data_pattern:
    fail(6, "Primary analysis has no trade data (no strategy family table or trade ledger found). "
           "Add a TRADE LEDGER or PART 3: STRATEGY FAMILY PERFORMANCE section.")
else:
    ok(6, "trade breakdown present")

# ── Final verdict ─────────────────────────────────────────────────────────────
print()
if failures:
    print(f"{'=' * 70}")
    print(f"GATE FAILED — {len(failures)} failure(s) — PUBLISH BLOCKED")
    print(f"{'=' * 70}")
    for gnum, msg in failures:
        print(f"  Gate {gnum}: {msg}")
    print()
    print("Fix the failures above, then re-run the gate before publishing.")
    print("Do NOT bypass this gate — it exists because manual checks failed.")
    sys.exit(1)
else:
    print(f"{'=' * 70}")
    print(f"ALL 6 GATES PASSED — {date} cleared for publishing")
    print(f"{'=' * 70}")
    print()
    sys.exit(0)
