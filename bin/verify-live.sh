#!/usr/bin/env bash
# verify-live.sh — S19-003: Verify live hyo.world reflects recent changes.
# Called after every push to confirm deployment is actually visible.
# Exits 0 = all checks pass. Exits 1 = failures found (logs details).
#
# Usage:
#   bash bin/verify-live.sh              # full check
#   bash bin/verify-live.sh --quick      # only ant-data + hq label
#   kai exec "bash ~/Documents/Projects/Hyo/bin/verify-live.sh"

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LOG_DIR="$ROOT/kai/ledger"
LOG_FILE="$LOG_DIR/verify-live.log"
SITE="https://www.hyo.world"
QUICK="${1:-}"

now() { TZ=America/Denver date '+%Y-%m-%dT%H:%M:%S-06:00'; }
log() { echo "[$(TZ=America/Denver date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

PASS=0
FAIL=0
FAILURES=()

check() {
  local name="$1" url="$2" marker="$3"
  local content
  # Note: no ?_v= query param for HTML pages — Vercel static routing breaks with query strings
  # --compressed handles brotli/gzip from CDN edge
  content=$(curl -sL --max-time 20 --compressed \
    -H "Cache-Control: no-cache" \
    -H "Pragma: no-cache" \
    "$url" 2>/dev/null || echo "CURL_FAIL")
  if [[ "$content" == "CURL_FAIL" ]]; then
    log "FAIL [$name]: could not fetch $url"
    FAILURES+=("$name: fetch failed ($url)")
    FAIL=$((FAIL+1))
    return
  fi
  if echo "$content" | grep -q "$marker"; then
    log "PASS [$name]: '$marker' found at $url"
    PASS=$((PASS+1))
  else
    log "FAIL [$name]: '$marker' NOT found at $url"
    FAILURES+=("$name: marker '$marker' missing at $url")
    FAIL=$((FAIL+1))
  fi
}

check_json() {
  local name="$1" url="$2" jq_expr="$3" expected="$4"
  local content
  content=$(curl -sL --max-time 20 -H "Cache-Control: no-cache" -H "Pragma: no-cache" \
    "${url}?_v=$(date +%s)" 2>/dev/null || echo "CURL_FAIL")
  if [[ "$content" == "CURL_FAIL" ]]; then
    log "FAIL [$name]: could not fetch $url"
    FAILURES+=("$name: fetch failed ($url)")
    FAIL=$((FAIL+1))
    return
  fi
  local actual
  actual=$(echo "$content" | python3 -c "import json,sys; d=json.load(sys.stdin); print($jq_expr)" 2>/dev/null || echo "PARSE_FAIL")
  if [[ "$actual" == "PARSE_FAIL" ]]; then
    log "FAIL [$name]: JSON parse failed at $url"
    FAILURES+=("$name: JSON parse error")
    FAIL=$((FAIL+1))
    return
  fi
  if [[ "$actual" == "$expected" ]]; then
    log "PASS [$name]: $jq_expr == $expected"
    PASS=$((PASS+1))
  else
    log "FAIL [$name]: $jq_expr → '$actual' (expected: '$expected')"
    FAILURES+=("$name: expected '$expected', got '$actual'")
    FAIL=$((FAIL+1))
  fi
}

check_json_contains() {
  local name="$1" url="$2" field="$3"
  local content
  content=$(curl -sL --max-time 20 -H "Cache-Control: no-cache" -H "Pragma: no-cache" \
    "${url}?_v=$(date +%s)" 2>/dev/null || echo "CURL_FAIL")
  if [[ "$content" == "CURL_FAIL" ]]; then
    FAILURES+=("$name: fetch failed")
    FAIL=$((FAIL+1))
    return
  fi
  if echo "$content" | python3 -c "import json,sys; d=json.load(sys.stdin); assert '$field' in d" 2>/dev/null; then
    log "PASS [$name]: field '$field' present"
    PASS=$((PASS+1))
  else
    log "FAIL [$name]: field '$field' missing"
    FAILURES+=("$name: '$field' not in JSON at $url")
    FAIL=$((FAIL+1))
  fi
}

log "=== verify-live.sh $(now) ==="

# ── 1. ant-data.json: new fields present ──────────────────────────────────────
check_json_contains "ant-data.byProcess" "$SITE/data/ant-data.json" "byProcess"
check_json_contains "ant-data.staleness" "$SITE/data/ant-data.json" "staleness"
check_json_contains "ant-data.alerts"    "$SITE/data/ant-data.json" "alerts"

# ── 2. ant-data.json freshness (updated within 25h) ──────────────────────────
ant_content=$(curl -sL --max-time 15 "$SITE/data/ant-data.json" 2>/dev/null || echo "")
if [[ -n "$ant_content" ]]; then
  age_ok=$(echo "$ant_content" | python3 -c "
import json,sys,datetime
d=json.load(sys.stdin)
updated = d.get('updatedAt','')
if not updated: print('no_ts'); exit()
try:
    dt = datetime.datetime.fromisoformat(updated)
    age = (datetime.datetime.now(dt.tzinfo) - dt).total_seconds() / 3600
    print('ok' if age < 25 else f'stale_{age:.0f}h')
except: print('parse_err')
" 2>/dev/null || echo "err")
  if [[ "$age_ok" == "ok" ]]; then
    log "PASS [ant-freshness]: data updated within 25h"
    PASS=$((PASS+1))
  else
    log "FAIL [ant-freshness]: $age_ok"
    FAILURES+=("ant-freshness: $age_ok")
    FAIL=$((FAIL+1))
  fi
fi

if [[ "$QUICK" == "--quick" ]]; then
  # ── 3. HQ: "View full brief" label present (S18-019) ──
  check "hq-view-full-brief" "$SITE/hq" "View full brief"
else
  # ── 3. HQ checks ──────────────────────────────────────────────────────────
  check "hq-view-full-brief"  "$SITE/hq"     "View full brief"
  check "hq-theme-toggle"     "$SITE/aurora" "theme-toggle"
  check "hq-byProcess-render" "$SITE/hq"     "byProcess"

  # ── 4. Aurora pages load ──────────────────────────────────────────────────
  check "aurora-200"      "$SITE/aurora"         "Aurora"
  check "aurora-page-200" "$SITE/aurora-page"    "Aurora"
  check "app-200"         "$SITE/app"            "hyo"

  # ── 5. Feed.json sanity ───────────────────────────────────────────────────
  check_json_contains "feed-reports" "$SITE/data/feed.json" "reports"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
log "--- verify-live result: $PASS passed, $FAIL failed ---"

if [[ $FAIL -gt 0 ]]; then
  log "FAILURES:"
  for f in "${FAILURES[@]}"; do
    log "  ✗ $f"
  done
  # Log to known-issues for pattern tracking
  python3 - <<PYEOF 2>/dev/null || true
import json, datetime
entry = {
  "ts": "$(now)",
  "source": "verify-live",
  "failures": $(python3 -c "import json; print(json.dumps([$(printf '"%s",' "${FAILURES[@]}" | sed 's/,$//')]  ))" 2>/dev/null || echo '[]'),
  "pass": $PASS,
  "fail": $FAIL
}
with open("$ROOT/kai/ledger/verify-live-history.jsonl", "a") as f:
    f.write(json.dumps(entry) + "\n")
PYEOF
  exit 1
fi

log "ALL CHECKS PASSED ($PASS/$((PASS+FAIL)))"
exit 0
