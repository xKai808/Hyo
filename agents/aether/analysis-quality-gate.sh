#!/usr/bin/env bash
# agents/aether/analysis-quality-gate.sh
#
# Aether W2 Improvement — Automated Analysis Quality Gate
# Shipped: 2026-04-21 | Protocol: agents/aether/PROTOCOL_DAILY_ANALYSIS.md v2.5
#
# PURPOSE:
#   Automatically validate that a daily analysis file meets the required
#   quality standards before it is published to HQ. Catches: missing sections,
#   no GPT cross-check, incomplete trade classification, patchwork violations.
#
# USAGE:
#   bash agents/aether/analysis-quality-gate.sh [DATE]
#   bash agents/aether/analysis-quality-gate.sh 2026-04-21
#   bash agents/aether/analysis-quality-gate.sh  # defaults to today
#
# OUTPUT:
#   exit 0 — analysis passes all quality checks
#   exit 1 — quality gate FAIL (analysis has problems, block publish)
#   stdout  — human-readable pass/fail report
#   agents/aether/ledger/quality-gate.jsonl — machine-readable history
#
# INTEGRATION:
#   Called by run_analysis.sh Phase 3 (before HQ publish)
#   If this exits 1, run_analysis.sh must NOT push to HQ feed
#   Gate question: "Did analysis-quality-gate.sh exit 0?" NO → block publish
#
# QUALITY CHECKS (12 required, all must pass):
#   QC01: Analysis file exists and is non-empty
#   QC02: File size > 500 bytes (not a stub)
#   QC03: Contains "Session" or "Window" section (at least 1 window analyzed)
#   QC04: Contains P&L numbers ($ or %)
#   QC05: Contains "GPT" or "Cross-check" or "adversarial" (GPT review present)
#   QC06: Contains strategy classification (at least 1 strategy name)
#   QC07: Contains "Risk" or "risk" section
#   QC08: No "TODO" or "PLACEHOLDER" (draft markers not present)
#   QC09: Contains recommendation (HOLD/BUY/SELL/REDUCE or explicit recommendation)
#   QC10: Balance mentioned ($ amount present in balance context)
#   QC11: Date in filename matches date in file content (no stale copy)
#   QC12: File was modified today (not a carryover from previous day)

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DATE="${1:-$(date +%Y-%m-%d)}"
LEDGER="$ROOT/agents/aether/ledger/quality-gate.jsonl"
NOW_ISO=$(TZ=America/Denver date +%FT%T%z 2>/dev/null || date -u +%FT%TZ)
TODAY=$(date +%Y-%m-%d)

mkdir -p "$(dirname "$LEDGER")"

# ---- Locate analysis file for date ------------------------------------
# Try multiple naming patterns used by aether.sh
find_analysis_file() {
    local date="$1"
    local candidates=(
        "$ROOT/agents/aether/logs/aether-${date}.log"
        "$ROOT/ANALYSIS_BRIEFING.txt"
        "$ROOT/agents/aether/analysis/Analysis_${date}.txt"
        "$ROOT/agents/aether/analysis/aether-${date}.md"
    )
    for f in "${candidates[@]}"; do
        [[ -f "$f" ]] && echo "$f" && return 0
    done
    # Last resort: newest file in logs/ containing the date
    local found
    found=$(find "$ROOT/agents/aether/logs" -name "*${date}*" -type f 2>/dev/null | sort -r | head -1)
    [[ -n "$found" ]] && echo "$found" && return 0
    return 1
}

ANALYSIS_FILE=$(find_analysis_file "$DATE" 2>/dev/null || true)

# ---- Quality check runner --------------------------------------------
PASS=0
FAIL=0
RESULTS=()

qcheck() {
    local id="$1"
    local desc="$2"
    local result="$3"  # "pass" or "fail"
    local detail="${4:-}"
    RESULTS+=("{\"id\":\"$id\",\"desc\":\"$desc\",\"result\":\"$result\",\"detail\":\"$detail\"}")
    if [[ "$result" == "pass" ]]; then
        PASS=$((PASS+1))
        echo "  ✓ $id: $desc" >&2
    else
        FAIL=$((FAIL+1))
        echo "  ✗ $id FAIL: $desc${detail:+ — $detail}" >&2
    fi
}

echo "=== Aether Analysis Quality Gate — $DATE ===" >&2
echo "" >&2

# QC01: File exists
if [[ -z "$ANALYSIS_FILE" ]]; then
    qcheck "QC01" "Analysis file exists" "fail" "No analysis file found for $DATE in expected locations"
    # Can't do further checks without file
    for id in QC02 QC03 QC04 QC05 QC06 QC07 QC08 QC09 QC10 QC11 QC12; do
        qcheck "$id" "Check skipped — no file" "fail" "prerequisite QC01 failed"
    done
else
    qcheck "QC01" "Analysis file exists" "pass" "$ANALYSIS_FILE"
    CONTENT=$(cat "$ANALYSIS_FILE" 2>/dev/null || true)
    SIZE=${#CONTENT}

    # QC02: File size
    [[ $SIZE -gt 500 ]] && qcheck "QC02" "File size > 500 bytes" "pass" "${SIZE}B" \
                         || qcheck "QC02" "File size > 500 bytes" "fail" "only ${SIZE}B — likely stub"

    # QC03: Window/session section
    if echo "$CONTENT" | grep -qiE "session|window|morning|afternoon|evening|overnight"; then
        qcheck "QC03" "Contains session/window analysis" "pass"
    else
        qcheck "QC03" "Contains session/window analysis" "fail" "no session or window references found"
    fi

    # QC04: P&L numbers
    if echo "$CONTENT" | grep -qE '\$[0-9]+\.[0-9]+|[0-9]+\.[0-9]+%|\+[0-9]|\-[0-9]'; then
        qcheck "QC04" "Contains P&L numbers" "pass"
    else
        qcheck "QC04" "Contains P&L numbers" "fail" "no dollar amounts or percentages found"
    fi

    # QC05: GPT cross-check
    if echo "$CONTENT" | grep -qiE "GPT|cross.check|adversarial|independent.*review|gpt-4"; then
        qcheck "QC05" "GPT cross-check present" "pass"
    else
        qcheck "QC05" "GPT cross-check present" "fail" "no GPT/adversarial review referenced — QC05 blocks publish"
    fi

    # QC06: Strategy classification
    if echo "$CONTENT" | grep -qiE "strategy|YES-momentum|NO-fade|ladder|binary|spread|scalp|harvest"; then
        qcheck "QC06" "Strategy classification present" "pass"
    else
        qcheck "QC06" "Strategy classification present" "fail" "no strategy names or classifications found"
    fi

    # QC07: Risk section
    if echo "$CONTENT" | grep -qiE "risk|exposure|concentration|max.loss|drawdown"; then
        qcheck "QC07" "Risk section present" "pass"
    else
        qcheck "QC07" "Risk section present" "fail" "no risk/exposure language found"
    fi

    # QC08: No draft markers
    if echo "$CONTENT" | grep -qiE "TODO|PLACEHOLDER|FIXME|TBD|draft"; then
        MARKERS=$(echo "$CONTENT" | grep -iE "TODO|PLACEHOLDER|FIXME|TBD|draft" | head -2 | tr '\n' '|')
        qcheck "QC08" "No draft markers" "fail" "found: $MARKERS"
    else
        qcheck "QC08" "No draft markers" "pass"
    fi

    # QC09: Recommendation present
    if echo "$CONTENT" | grep -qiE "HOLD|REDUCE|INCREASE|recommend|BUY|SELL|continue|pause|stop"; then
        qcheck "QC09" "Recommendation present" "pass"
    else
        qcheck "QC09" "Recommendation present" "fail" "no actionable recommendation found"
    fi

    # QC10: Balance mentioned
    if echo "$CONTENT" | grep -qiE "balance|portfolio|\\\$[0-9]+"; then
        qcheck "QC10" "Balance/portfolio mentioned" "pass"
    else
        qcheck "QC10" "Balance/portfolio mentioned" "fail" "no balance or portfolio reference"
    fi

    # QC11: Date in content matches filename date
    if echo "$CONTENT" | grep -q "$DATE"; then
        qcheck "QC11" "Date matches content" "pass"
    else
        qcheck "QC11" "Date matches content" "fail" "file date $DATE not found in content — possible stale copy"
    fi

    # QC12: File modified today
    FILE_DATE=$(date -r "$ANALYSIS_FILE" +%Y-%m-%d 2>/dev/null || stat -f %Sm -t %Y-%m-%d "$ANALYSIS_FILE" 2>/dev/null || echo "unknown")
    if [[ "$FILE_DATE" == "$TODAY" ]]; then
        qcheck "QC12" "File modified today" "pass" "mtime=$FILE_DATE"
    else
        qcheck "QC12" "File modified today" "fail" "mtime=$FILE_DATE — file is from a previous day"
    fi
fi

# ---- Write to ledger -------------------------------------------------
RESULTS_JSON=$(printf '%s,' "${RESULTS[@]}")
RESULTS_JSON="[${RESULTS_JSON%,}]"
ENTRY=$(python3 -c "
import json, sys
entry = {
    'ts': '$NOW_ISO',
    'date': '$DATE',
    'analysis_file': '$ANALYSIS_FILE',
    'passed': $PASS,
    'failed': $FAIL,
    'total': $((PASS+FAIL)),
    'gate_result': 'pass' if $FAIL == 0 else 'fail',
    'checks': $RESULTS_JSON
}
print(json.dumps(entry))
" 2>/dev/null || echo "{}")
echo "$ENTRY" >> "$LEDGER"

# ---- Summary ---------------------------------------------------------
echo "" >&2
echo "=== Quality Gate: $PASS/$((PASS+FAIL)) checks passed ===" >&2

if [[ $FAIL -eq 0 ]]; then
    echo "PASS — analysis meets quality standards. Publish authorized." >&2
    exit 0
else
    echo "FAIL — $FAIL check(s) failed. DO NOT PUBLISH to HQ until fixed." >&2
    echo "Fix failures above, then re-run: bash agents/aether/analysis-quality-gate.sh $DATE" >&2
    exit 1
fi
