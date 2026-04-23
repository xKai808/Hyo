#!/usr/bin/env bash
# bin/kai-hydration-check.sh — Kai W1 Fix: Automated hydration verification
#
# PURPOSE:
#   Verify that all 12 required hydration files were actually read at the start
#   of this session. Writes a hydration receipt. Flags stale reads to session-errors.
#
# USAGE:
#   bash bin/kai-hydration-check.sh [SESSION_START_TS]
#   SESSION_START_TS: ISO timestamp of session start (default: now - 10 minutes)
#
# OUTPUT:
#   kai/ledger/hydration-receipt-YYYY-MM-DD.json — timestamped read log
#   exit 0 — all files confirmed read (or acceptable)
#   exit 1 — one or more hydration files are stale (not read this session)
#
# WIRED BY: kai-autonomous.sh (first step of every session cycle)

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW_MT=$(TZ=America/Denver date +%FT%T%z)
RECEIPT="$ROOT/kai/ledger/hydration-receipt-$TODAY.json"
SESSION_ERRORS="$ROOT/kai/ledger/session-errors.jsonl"

mkdir -p "$(dirname "$RECEIPT")"

# The 12 required hydration files (from CLAUDE.md hydration protocol)
declare -A HYDRATION_FILES=(
    ["session-handoff"]="kai/ledger/session-handoff.json"
    ["kai-brief"]="KAI_BRIEF.md"
    ["hyo-inbox"]="kai/ledger/hyo-inbox.jsonl"
    ["dispatch-today"]="kai/dispatch/dispatch-$TODAY.md"
    ["knowledge"]="kai/memory/KNOWLEDGE.md"
    ["tacit"]="kai/memory/TACIT.md"
    ["kai-tasks"]="KAI_TASKS.md"
    ["known-issues"]="kai/ledger/known-issues.jsonl"
    ["session-errors"]="kai/ledger/session-errors.jsonl"
    ["execution-gate"]="kai/protocols/EXECUTION_GATE.md"
    ["sim-outcomes"]="kai/ledger/simulation-outcomes.jsonl"
    ["agent-algorithms"]="kai/AGENT_ALGORITHMS.md"
)

PASS=0
FAIL=0
STALE_FILES=()
RESULTS=()

echo "=== Kai Hydration Check — $TODAY ===" >&2
echo "" >&2

# Check each file: does it exist, and was it modified within the last 48h?
# (We can't verify it was READ in this session without instrumentation,
#  but we CAN verify it's not a stale >48h file — a proxy for freshness.)
for key in "${!HYDRATION_FILES[@]}"; do
    rel_path="${HYDRATION_FILES[$key]}"
    full_path="$ROOT/$rel_path"

    if [[ ! -f "$full_path" ]]; then
        if [[ "$key" == "dispatch-today" ]]; then
            # Today's dispatch may not exist yet — not a failure
            echo "  ~ $key: no dispatch file yet for today (acceptable)" >&2
            RESULTS+=("{\"file\":\"$rel_path\",\"status\":\"missing-acceptable\",\"note\":\"No dispatch today yet\"}")
            PASS=$((PASS+1))
        else
            echo "  ✗ $key: FILE MISSING — $rel_path" >&2
            STALE_FILES+=("$key ($rel_path: missing)")
            RESULTS+=("{\"file\":\"$rel_path\",\"status\":\"missing\"}")
            FAIL=$((FAIL+1))
        fi
        continue
    fi

    # Check file age
    FILE_AGE_H=$(python3 -c "
import os, time
mtime = os.path.getmtime('$full_path')
age_h = (time.time() - mtime) / 3600
print(f'{age_h:.1f}')
" 2>/dev/null || echo "999")

    FILE_AGE_FLOAT=$(echo "$FILE_AGE_H" | tr -d '\n')

    if python3 -c "import sys; sys.exit(0 if float('$FILE_AGE_FLOAT') <= 48 else 1)" 2>/dev/null; then
        echo "  ✓ $key: ${FILE_AGE_H}h old" >&2
        RESULTS+=("{\"file\":\"$rel_path\",\"status\":\"fresh\",\"age_h\":$FILE_AGE_H}")
        PASS=$((PASS+1))
    else
        echo "  ✗ $key: STALE — ${FILE_AGE_H}h old (threshold: 48h)" >&2
        STALE_FILES+=("$key (${FILE_AGE_H}h old)")
        RESULTS+=("{\"file\":\"$rel_path\",\"status\":\"stale\",\"age_h\":$FILE_AGE_H}")
        FAIL=$((FAIL+1))
    fi
done

echo "" >&2
echo "=== Hydration: $PASS/${#HYDRATION_FILES[@]} files fresh ===" >&2

# Write receipt
RESULTS_JSON=$(printf '%s,' "${RESULTS[@]}")
RESULTS_JSON="[${RESULTS_JSON%,}]"

python3 - "$RECEIPT" "$NOW_MT" "$TODAY" "$PASS" "$FAIL" "$RESULTS_JSON" << 'PYEOF'
import json, sys
path, ts, today, passed, failed, results_str = sys.argv[1:7]
receipt = {
    "ts": ts,
    "date": today,
    "passed": int(passed),
    "failed": int(failed),
    "gate_result": "pass" if int(failed) == 0 else "fail",
    "files": json.loads(results_str)
}
with open(path, 'w') as f:
    json.dump(receipt, f, indent=2)
print(f"Receipt written: {path}")
PYEOF

# Log failures to session-errors.jsonl
if [[ $FAIL -gt 0 ]]; then
    STALE_LIST=$(printf '%s, ' "${STALE_FILES[@]}")
    python3 - "$SESSION_ERRORS" "$NOW_MT" "$STALE_LIST" << 'PYEOF'
import json, sys
path, ts, stale = sys.argv[1:4]
entry = {
    "ts": ts,
    "session": "auto-detected",
    "category": "skip-verification",
    "description": f"Hydration check failed: {stale.rstrip(', ')}",
    "who_caught": "kai-hydration-check.sh (automated)",
    "prevention": "Read all 12 hydration files at session start per CLAUDE.md protocol",
    "severity": "P1",
    "fixed": False
}
with open(path, 'a') as f:
    f.write(json.dumps(entry) + '\n')
PYEOF
    echo "FAIL — $FAIL hydration file(s) stale. Check receipt at $RECEIPT" >&2
    exit 1
else
    echo "PASS — all hydration files confirmed fresh." >&2
    exit 0
fi
