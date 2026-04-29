#!/usr/bin/env bash
# bin/verify-improvement-content-gate.sh — Content gate for self-improve verify phase
#
# Skepticism research finding: pipeline gaming — gates check file existence, not content.
# A plausible-looking research file can pass all four stages while the weakness is unfixed.
# This gate closes that vulnerability by running the specific test case written at research time.
#
# Usage:
#   bash bin/verify-improvement-content-gate.sh <agent> <weakness_id>
#   Exit 0 = content gate passed
#   Exit 1 = content gate BLOCKED (file exists but test case fails or is missing)
#   Exit 2 = no test case file found (warn only — not a block, test case may not exist yet)
#
# Test case format (written at research time to agents/<agent>/research/improvements/TEST-<WID>-<DATE>.json):
#   {
#     "weakness_id": "W1",
#     "test_description": "What this test proves",
#     "test_type": "file_content|command_output|metric_check|manual",
#     "test_command": "bash -c '...'",  -- for command_output type
#     "expected_pattern": "regex to match in output",
#     "expected_file": "path/to/file",  -- for file_content type
#     "expected_file_contains": "string that must appear",
#     "metric_key": "sicq_score",        -- for metric_check type
#     "metric_min": 70
#   }
#
# VERSION: v1.0 | 2026-04-28 | Skepticism research — Change 1 of 3

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
AGENT="${1:?Usage: verify-improvement-content-gate.sh <agent> <weakness_id>}"
WID="${2:?Missing weakness_id}"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
LOG="$ROOT/agents/$AGENT/logs/content-gate.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }

# Find test case file — look for today's first, then any recent
TEST_FILE=""
for f in "$ROOT/agents/$AGENT/research/improvements/TEST-${WID}-${TODAY}.json" \
          "$ROOT/agents/$AGENT/research/improvements/TEST-${WID}-"*.json; do
  [[ -f "$f" ]] && TEST_FILE="$f" && break
done

if [[ -z "$TEST_FILE" ]]; then
  log "WARN: No test case file found for $AGENT/$WID — content gate skipped (exit 2)"
  log "  Expected: agents/$AGENT/research/improvements/TEST-${WID}-${TODAY}.json"
  log "  ACTION: Write a test case during the research phase next cycle to close the pipeline-gaming vulnerability"
  exit 2
fi

log "Running content gate for $AGENT/$WID — test case: $TEST_FILE"

TEST_TYPE=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('test_type','manual'))" 2>/dev/null || echo "manual")
TEST_DESC=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('test_description',''))" 2>/dev/null || echo "")

log "  Test type: $TEST_TYPE"
log "  Description: $TEST_DESC"

case "$TEST_TYPE" in

  file_content)
    EXPECTED_FILE=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('expected_file',''))" 2>/dev/null || echo "")
    EXPECTED_CONTAINS=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('expected_file_contains',''))" 2>/dev/null || echo "")

    if [[ -z "$EXPECTED_FILE" || ! -f "$ROOT/$EXPECTED_FILE" ]]; then
      log "FAIL: Expected file not found: $EXPECTED_FILE"
      exit 1
    fi

    if [[ -n "$EXPECTED_CONTAINS" ]]; then
      if grep -q "$EXPECTED_CONTAINS" "$ROOT/$EXPECTED_FILE" 2>/dev/null; then
        log "PASS: '$EXPECTED_CONTAINS' found in $EXPECTED_FILE"
        exit 0
      else
        log "FAIL: '$EXPECTED_CONTAINS' NOT found in $EXPECTED_FILE"
        log "  This means the improvement was not actually implemented correctly."
        exit 1
      fi
    fi
    log "PASS: file exists (no content pattern specified)"
    exit 0
    ;;

  command_output)
    TEST_CMD=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('test_command',''))" 2>/dev/null || echo "")
    EXPECTED_PATTERN=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('expected_pattern',''))" 2>/dev/null || echo "")

    if [[ -z "$TEST_CMD" ]]; then
      log "FAIL: test_command is empty in test case file"
      exit 1
    fi

    OUTPUT=$(cd "$ROOT" && eval "$TEST_CMD" 2>&1 || true)
    log "  Command output (first 200 chars): ${OUTPUT:0:200}"

    if [[ -n "$EXPECTED_PATTERN" ]]; then
      if echo "$OUTPUT" | grep -qE "$EXPECTED_PATTERN"; then
        log "PASS: Output matches expected pattern '$EXPECTED_PATTERN'"
        exit 0
      else
        log "FAIL: Output does NOT match expected pattern '$EXPECTED_PATTERN'"
        log "  This means the improvement did not produce the expected behavior."
        exit 1
      fi
    fi
    log "PASS: command ran successfully (no pattern check)"
    exit 0
    ;;

  metric_check)
    METRIC_KEY=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('metric_key',''))" 2>/dev/null || echo "")
    METRIC_MIN=$(python3 -c "import json; d=json.load(open('$TEST_FILE')); print(d.get('metric_min',0))" 2>/dev/null || echo "0")

    # Read from verified-state.json
    VERIFIED_STATE="$ROOT/kai/ledger/verified-state.json"
    if [[ -f "$VERIFIED_STATE" ]]; then
      METRIC_VAL=$(python3 -c "
import json
with open('$VERIFIED_STATE') as f:
    d = json.load(f)
# Flatten nested and look for key
def find(d, key):
    if isinstance(d, dict):
        if key in d: return d[key]
        for v in d.values():
            r = find(v, key)
            if r is not None: return r
    return None
v = find(d, '$METRIC_KEY')
print(v if v is not None else 'NOT_FOUND')
" 2>/dev/null || echo "NOT_FOUND")

      if [[ "$METRIC_VAL" == "NOT_FOUND" ]]; then
        log "WARN: Metric '$METRIC_KEY' not found in verified-state.json — cannot check"
        exit 2
      fi

      if python3 -c "exit(0 if float('$METRIC_VAL') >= float('$METRIC_MIN') else 1)" 2>/dev/null; then
        log "PASS: $METRIC_KEY = $METRIC_VAL >= minimum $METRIC_MIN"
        exit 0
      else
        log "FAIL: $METRIC_KEY = $METRIC_VAL < minimum $METRIC_MIN"
        exit 1
      fi
    else
      log "WARN: verified-state.json not found — metric check skipped"
      exit 2
    fi
    ;;

  manual)
    log "WARN: Test type is 'manual' — human verification required"
    log "  Description: $TEST_DESC"
    log "  Content gate cannot auto-verify manual tests. Treating as passed (exit 0)."
    log "  ACTION: Convert to file_content or command_output type for automated gating."
    exit 0
    ;;

  *)
    log "WARN: Unknown test type '$TEST_TYPE' — content gate skipped"
    exit 2
    ;;

esac
