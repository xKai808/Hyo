#!/usr/bin/env bash
# bin/verify-render.sh — Post-deploy render verification
#
# Fetches live HQ data and verifies every section renders correctly.
# Run after every push to catch the rendered-output-gap that persisted
# for 3+ days undetected (simulation showed 9 failures, nobody acted).
#
# Usage:
#   bash bin/verify-render.sh              # full verification
#   bash bin/verify-render.sh --quick      # data files only
#   bash bin/verify-render.sh --fix        # attempt auto-fix on failure
#
# Exit codes:
#   0 = all checks passed
#   1 = render failures detected
#   2 = infrastructure failure (can't reach site)

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
SITE="https://www.hyo.world"
RESULTS_FILE="$ROOT/kai/ledger/render-verification.jsonl"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S%z")

passed=0
failed=0
warnings=0
failures=()

log() { echo "[$TS] $*"; }
pass() { ((passed++)); log "PASS: $1"; }
fail() { ((failed++)); failures+=("$1"); log "FAIL: $1"; }
warn() { ((warnings++)); log "WARN: $1"; }

# ─── 1. Can we reach the site? ─────────────────────────────────────────────
log "=== RENDER VERIFICATION ==="

http_code=$(curl -s -o /dev/null -w "%{http_code}" "$SITE" 2>/dev/null || echo "000")
if [[ "$http_code" == "000" ]]; then
  log "FATAL: Cannot reach $SITE (network error)"
  exit 2
elif [[ "$http_code" != "200" && "$http_code" != "307" && "$http_code" != "301" ]]; then
  warn "Site returned HTTP $http_code (may be auth-gated)"
fi

# ─── 2. Verify static data files exist and are valid JSON ──────────────────
check_json_file() {
  local path="$1"
  local name="$2"
  local url="$SITE$path"

  local response
  response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null)
  local code
  code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$code" != "200" ]]; then
    fail "$name: HTTP $code at $url"
    return 1
  fi

  # Validate JSON
  if ! echo "$body" | python3 -m json.tool > /dev/null 2>&1; then
    fail "$name: invalid JSON at $url"
    return 1
  fi

  echo "$body"
  return 0
}

# ─── 3. Aether metrics verification ───────────────────────────────────────
log "--- Aether Metrics ---"
aether_json=$(check_json_file "/data/aether-metrics.json" "aether-metrics.json")
if [[ $? -eq 0 ]]; then
  pass "aether-metrics.json: reachable and valid JSON"

  # Verify required fields exist and are non-zero
  check_field() {
    local field="$1"
    local description="$2"
    local value
    value=$(echo "$aether_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cw = d.get('currentWeek', {})
v = cw.get('$field')
print(v if v is not None else 'MISSING')
" 2>/dev/null)

    if [[ "$value" == "MISSING" || "$value" == "None" ]]; then
      fail "aether currentWeek.$field: MISSING"
    elif [[ "$value" == "0" || "$value" == "0.0" ]]; then
      warn "aether currentWeek.$field: is zero (may be stale)"
    else
      pass "aether currentWeek.$field = $value"
    fi
  }

  check_field "trades" "Trade count (BUY SNAPSHOT)"
  check_field "wins" "Win count (TICKER CLOSE)"
  check_field "losses" "Loss count (TICKER CLOSE)"
  check_field "winRate" "Win rate"
  check_field "currentBalance" "Current balance"
  check_field "pnl" "P&L (balance math)"

  # Verify strategies exist
  strat_count=$(echo "$aether_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(len(d.get('currentWeek', {}).get('strategies', [])))
" 2>/dev/null)

  if [[ "$strat_count" == "0" ]]; then
    fail "aether strategies: empty (should have active strategies)"
  else
    pass "aether strategies: $strat_count strategies present"
  fi

  # Verify no legacy fields
  legacy=$(echo "$aether_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
cw = d.get('currentWeek', {})
found = []
if 'settledTrades' in cw: found.append('settledTrades')
if 'totalTradeEvents' in cw: found.append('totalTradeEvents')
if 'settledPnl' in cw: found.append('settledPnl')
print(','.join(found) if found else 'CLEAN')
" 2>/dev/null)

  if [[ "$legacy" != "CLEAN" ]]; then
    warn "aether legacy fields still present: $legacy"
  else
    pass "aether: no legacy fields (settledTrades/totalTradeEvents/settledPnl)"
  fi
fi

# ─── 4. Feed.json verification ────────────────────────────────────────────
log "--- Feed Data ---"
feed_json=$(check_json_file "/data/feed.json" "feed.json")
if [[ $? -eq 0 ]]; then
  pass "feed.json: reachable and valid JSON"

  report_count=$(echo "$feed_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
reports = d.get('reports', [])
print(len(reports))
" 2>/dev/null)

  if [[ "$report_count" == "0" ]]; then
    warn "feed.json: 0 reports (may be stale)"
  else
    pass "feed.json: $report_count reports"
  fi

  # Check for today's reports
  today=$(TZ="America/Denver" date +%Y-%m-%d)
  today_count=$(echo "$feed_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
today = '$today'
reports = d.get('reports', [])
count = sum(1 for r in reports if r.get('date','').startswith(today) or r.get('timestamp','').startswith(today))
print(count)
" 2>/dev/null)

  if [[ "$today_count" == "0" ]]; then
    warn "feed.json: no reports for today ($today)"
  else
    pass "feed.json: $today_count reports for today"
  fi
fi

# ─── 5. API health check ──────────────────────────────────────────────────
log "--- API Health ---"
api_response=$(curl -s "$SITE/api/health" 2>/dev/null)
api_ok=$(echo "$api_response" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print('true' if d.get('ok') else 'false')
except: print('error')
" 2>/dev/null)

if [[ "$api_ok" == "true" ]]; then
  pass "API health: ok"
else
  fail "API health: not ok (response: $api_response)"
fi

# ─── 6. HQ HTML exists ────────────────────────────────────────────────────
log "--- HTML Pages ---"
for page in "/hq.html" "/marketplace.html" "/aurora.html"; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$SITE$page" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    pass "$page: HTTP 200"
  elif [[ "$code" == "401" || "$code" == "403" ]]; then
    pass "$page: HTTP $code (auth-gated, expected)"
  else
    fail "$page: HTTP $code"
  fi
done

# ─── 7. Local file consistency ─────────────────────────────────────────────
log "--- Local File Consistency ---"
website_metrics="$ROOT/website/data/aether-metrics.json"
sam_metrics="$ROOT/agents/sam/website/data/aether-metrics.json"

if [[ -f "$website_metrics" && -f "$sam_metrics" ]]; then
  if diff -q "$website_metrics" "$sam_metrics" > /dev/null 2>&1; then
    pass "dual-path: website/ and agents/sam/website/ aether-metrics.json match"
  else
    fail "dual-path: website/ and agents/sam/website/ aether-metrics.json DIVERGED"
  fi
else
  warn "dual-path: one or both aether-metrics.json files missing"
fi

# Same for feed.json
website_feed="$ROOT/website/data/feed.json"
sam_feed="$ROOT/agents/sam/website/data/feed.json"
if [[ -f "$website_feed" && -f "$sam_feed" ]]; then
  if diff -q "$website_feed" "$sam_feed" > /dev/null 2>&1; then
    pass "dual-path: feed.json files match"
  else
    fail "dual-path: feed.json files DIVERGED"
  fi
fi

# ─── Summary ──────────────────────────────────────────────────────────────
log ""
log "=== VERIFICATION COMPLETE ==="
log "  PASSED:   $passed"
log "  FAILED:   $failed"
log "  WARNINGS: $warnings"

if [[ $failed -gt 0 ]]; then
  log ""
  log "FAILURES:"
  for f in "${failures[@]}"; do
    log "  - $f"
  done
fi

# Log result to ledger
mkdir -p "$(dirname "$RESULTS_FILE")"
echo "{\"ts\":\"$TS\",\"passed\":$passed,\"failed\":$failed,\"warnings\":$warnings,\"failures\":[$(printf '"%s",' "${failures[@]}" | sed 's/,$//')]}" >> "$RESULTS_FILE"

if [[ $failed -gt 0 ]]; then
  log ""
  log "ACTION REQUIRED: $failed render verification failures detected."
  exit 1
fi

exit 0
