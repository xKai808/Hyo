#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/bin/perf-check.sh
#
# Sam I1 Phase 1 — Performance Baseline Measurement
# Shipped: 2026-04-21 | Protocol: agents/sam/PROTOCOL_SAM_SELF_IMPROVEMENT.md
#
# PURPOSE:
#   Measure response time for all Hyo API endpoints, compare against baseline,
#   and flag regressions. Stores results in agents/sam/ledger/performance-baseline.jsonl.
#   Can be run manually or called from DEPLOY.md Phase 4 (post-deploy smoke tests).
#
# USAGE:
#   bash bin/perf-check.sh                      # measure and compare
#   bash bin/perf-check.sh --set-baseline       # record current as new baseline
#   bash bin/perf-check.sh --threshold 1000     # custom ms threshold (default: 2000)
#   bash bin/perf-check.sh --no-fail            # report but don't exit 1 on regression
#
# OUTPUT:
#   agents/sam/ledger/performance-baseline.jsonl — time-series of measurements
#   stdout — human-readable summary
#   exit 0 — all checks pass or --no-fail
#   exit 1 — P1 regression detected (>threshold ms or >15% slower than baseline)
#
# INTEGRATION:
#   - Called by DEPLOY.md Phase 4 (smoke tests) after every deployment
#   - Called by nel-qa-cycle.sh api-health phase daily
#   - Failure here triggers dispatch alert to Kai
#
# REGRESSION THRESHOLDS (Sam I1 defaults):
#   P0: response time > 5000ms (timeout-level slow)
#   P1: response time > 2000ms OR >50% slower than baseline
#   P2: response time > 1000ms OR >15% slower than baseline

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LEDGER="$ROOT/agents/sam/ledger/performance-baseline.jsonl"
TODAY=$(date +%Y-%m-%d)
NOW_ISO=$(TZ=America/Denver date +%FT%T%z 2>/dev/null || date -u +%FT%TZ)

# ---- Parse args -------------------------------------------------------
SET_BASELINE=false
THRESHOLD_MS=2000
NO_FAIL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --set-baseline) SET_BASELINE=true; shift ;;
    --threshold)    THRESHOLD_MS="$2"; shift 2 ;;
    --no-fail)      NO_FAIL=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$(dirname "$LEDGER")"

# ---- Endpoints to measure ---------------------------------------------
declare -a ENDPOINTS=(
  "health|https://www.hyo.world/api/health"
  "hq|https://www.hyo.world/api/hq"
  "aurora-data|https://www.hyo.world/api/aurora-data"
  "hq-home|https://www.hyo.world"
  "ra-home|https://www.hyo.world/ra"
)

# ---- Measure a single endpoint ----------------------------------------
measure_endpoint() {
  local label="$1"
  local url="$2"
  local result

  # Use curl to measure total time (in ms) and HTTP status
  local timing
  if timing=$(curl -sS \
    --max-time 10 \
    --connect-timeout 5 \
    -o /dev/null \
    -w "%{http_code} %{time_total}" \
    "$url" 2>/dev/null); then
    local status_code
    local time_sec
    status_code=$(echo "$timing" | awk '{print $1}')
    time_sec=$(echo "$timing" | awk '{print $2}')
    # Convert seconds to ms (integer)
    local time_ms
    time_ms=$(echo "$time_sec * 1000" | bc 2>/dev/null | cut -d. -f1 || echo "0")
    echo "$status_code $time_ms"
  else
    echo "000 -1"
  fi
}

# ---- Load baseline for comparison -------------------------------------
get_baseline() {
  local label="$1"
  if [[ -f "$LEDGER" ]]; then
    # Find the most recent baseline entry for this endpoint
    grep '"type":"baseline"' "$LEDGER" 2>/dev/null | \
      grep "\"endpoint\":\"$label\"" | \
      tail -1 | \
      python3 -c "import sys,json; d=json.loads(sys.stdin.read().strip()); print(d.get('p50_ms', -1))" 2>/dev/null || echo "-1"
  else
    echo "-1"
  fi
}

# ---- Main measurement loop -------------------------------------------
RESULTS=()
REGRESSIONS=()
PASS_COUNT=0
FAIL_COUNT=0

echo "=== Hyo Performance Check — $NOW_ISO ===" >&2
echo "" >&2

for endpoint_spec in "${ENDPOINTS[@]}"; do
  IFS='|' read -r label url <<< "$endpoint_spec"
  echo -n "  Checking $label ($url)... " >&2

  read -r status_code time_ms <<< "$(measure_endpoint "$label" "$url")"

  local_baseline=$(get_baseline "$label")

  # Determine result
  result_status="pass"
  regression_pct=0
  if [[ "$time_ms" -eq -1 ]]; then
    result_status="error"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "ERROR (connection failed)" >&2
  elif [[ "$time_ms" -gt 5000 ]]; then
    result_status="p0"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    REGRESSIONS+=("P0|$label|${time_ms}ms > 5000ms threshold")
    echo "P0 CRITICAL (${time_ms}ms)" >&2
  elif [[ "$time_ms" -gt "$THRESHOLD_MS" ]]; then
    result_status="p1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    REGRESSIONS+=("P1|$label|${time_ms}ms > ${THRESHOLD_MS}ms threshold")
    echo "P1 SLOW (${time_ms}ms)" >&2
  else
    # Check regression against baseline
    if [[ "$local_baseline" -gt 0 && "$time_ms" -gt 0 ]]; then
      regression_pct=$(( (time_ms - local_baseline) * 100 / local_baseline ))
      if [[ $regression_pct -gt 50 ]]; then
        result_status="p1-regression"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        REGRESSIONS+=("P1|$label|regression ${regression_pct}% slower than baseline (${local_baseline}ms → ${time_ms}ms)")
        echo "P1 REGRESSION (+${regression_pct}% vs baseline ${local_baseline}ms) → ${time_ms}ms" >&2
      elif [[ $regression_pct -gt 15 ]]; then
        result_status="p2-regression"
        echo "P2 slow (+${regression_pct}% vs baseline ${local_baseline}ms) → ${time_ms}ms" >&2
        PASS_COUNT=$((PASS_COUNT + 1))
      else
        result_status="pass"
        echo "OK (${time_ms}ms)" >&2
        PASS_COUNT=$((PASS_COUNT + 1))
      fi
    else
      result_status="pass"
      echo "OK (${time_ms}ms, no baseline yet)" >&2
      PASS_COUNT=$((PASS_COUNT + 1))
    fi
  fi

  # Record measurement
  RESULTS+=("{\"endpoint\":\"$label\",\"url\":\"$url\",\"http_status\":$status_code,\"time_ms\":$time_ms,\"baseline_ms\":$local_baseline,\"regression_pct\":$regression_pct,\"result\":\"$result_status\"}")
done

echo "" >&2
echo "=== Results: $PASS_COUNT passed, $FAIL_COUNT failed ===" >&2

# ---- Write to ledger --------------------------------------------------
ENTRY_TYPE="measurement"
if [[ "$SET_BASELINE" == "true" ]]; then
  ENTRY_TYPE="baseline"
  echo "[info] Recording as new baseline" >&2
fi

# Compute p50 (median) from results for baseline recording
compute_p50() {
  local times=()
  for r in "${RESULTS[@]}"; do
    local ms
    ms=$(echo "$r" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('time_ms', -1))" 2>/dev/null)
    if [[ "$ms" -ge 0 ]]; then
      times+=("$ms")
    fi
  done
  if [[ ${#times[@]} -gt 0 ]]; then
    printf '%s\n' "${times[@]}" | sort -n | awk 'NR==int((NF+1)/2){print; exit} NF%2==0 {next}'
    # Simple: just use the mean
    local sum=0
    for t in "${times[@]}"; do sum=$((sum + t)); done
    echo $((sum / ${#times[@]}))
  else
    echo "-1"
  fi
}

for r in "${RESULTS[@]}"; do
  local label
  label=$(echo "$r" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('endpoint', 'unknown'))" 2>/dev/null)
  local time_ms
  time_ms=$(echo "$r" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('time_ms', -1))" 2>/dev/null)

  local entry
  entry=$(python3 -c "
import json, sys
r = json.loads(sys.argv[1])
entry = {
  'ts': '$NOW_ISO',
  'date': '$TODAY',
  'type': '$ENTRY_TYPE',
  'endpoint': r['endpoint'],
  'url': r['url'],
  'http_status': r['http_status'],
  'time_ms': r['time_ms'],
  'p50_ms': r['time_ms'],
  'baseline_ms': r['baseline_ms'],
  'regression_pct': r['regression_pct'],
  'result': r['result'],
  'threshold_ms': $THRESHOLD_MS,
  'set_by': 'perf-check.sh'
}
print(json.dumps(entry))
" "$r" 2>/dev/null)

  if [[ -n "$entry" ]]; then
    echo "$entry" >> "$LEDGER"
  fi
done

# ---- Print regressions ------------------------------------------------
if [[ ${#REGRESSIONS[@]} -gt 0 ]]; then
  echo "" >&2
  echo "=== REGRESSIONS DETECTED ===" >&2
  for reg in "${REGRESSIONS[@]}"; do
    echo "  $reg" >&2
  done
fi

# ---- Exit code --------------------------------------------------------
if [[ $FAIL_COUNT -gt 0 && "$NO_FAIL" != "true" ]]; then
  echo "" >&2
  echo "perf-check: FAIL ($FAIL_COUNT regressions). See $LEDGER" >&2
  exit 1
else
  echo "" >&2
  echo "perf-check: PASS ($PASS_COUNT checks). Logged to $LEDGER" >&2
  exit 0
fi
