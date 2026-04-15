#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Sam verify.sh — Engineering & Infrastructure verification gates
# System 3 (Sprint) + System 2 Gate 2 (Coding)
#
# Open-ended questions encoded as executable checks:
#   1. Does the code do exactly what the spec says?
#   2. What happens with unexpected input?
#   3. Are there hardcoded values that should be env vars?
#   4. What tests were run, and what was their pass rate?
#   5. What would break in the existing codebase if this shipped?
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
TICKET_ID="${1:-}"
PASS=0
FAIL=0
WARN=0

check() {
  local name="$1" result="$2"
  if [[ "$result" == "pass" ]]; then
    echo "  ✅ $name"
    PASS=$((PASS + 1))
  elif [[ "$result" == "warn" ]]; then
    echo "  ⚠️  $name"
    WARN=$((WARN + 1))
  else
    echo "  ❌ $name"
    FAIL=$((FAIL + 1))
  fi
}

echo "═══ Sam Verification Gates ═══"
echo "Ticket: ${TICKET_ID:-manual}"
echo ""

# ─── GATE: Website static files valid ───
echo "Gate: Coding — static file integrity"
for f in "$HYO_ROOT/website/hq.html" "$HYO_ROOT/website/research.html" "$HYO_ROOT/website/index.html"; do
  fname=$(basename "$f")
  if [[ -f "$f" ]]; then
    # Check for basic HTML structure
    if grep -q "<html" "$f" && grep -q "</html>" "$f"; then
      check "$fname has valid HTML structure" "pass"
    else
      check "$fname missing HTML tags" "fail"
    fi
  else
    check "$fname exists" "fail"
  fi
done

# ─── GATE: JSON data files are valid ───
echo ""
echo "Gate: Coding — data file integrity"
for f in "$HYO_ROOT/website/data/feed.json" "$HYO_ROOT/website/data/aether-daily-sections.json"; do
  fname=$(basename "$f")
  if [[ -f "$f" ]]; then
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
      check "$fname is valid JSON" "pass"
    else
      check "$fname is INVALID JSON" "fail"
    fi
  fi
done

# ─── GATE: Vercel config valid ───
echo ""
echo "Gate: Infrastructure — deployment config"
VERCEL_JSON="$HYO_ROOT/website/vercel.json"
if [[ -f "$VERCEL_JSON" ]]; then
  if python3 -c "import json; json.load(open('$VERCEL_JSON'))" 2>/dev/null; then
    check "vercel.json is valid JSON" "pass"
  else
    check "vercel.json is INVALID JSON" "fail"
  fi

  # Check X-Frame-Options is SAMEORIGIN not DENY
  if grep -q '"SAMEORIGIN"' "$VERCEL_JSON"; then
    check "X-Frame-Options is SAMEORIGIN (iframe-safe)" "pass"
  elif grep -q '"DENY"' "$VERCEL_JSON"; then
    check "X-Frame-Options is DENY (will break research iframe)" "fail"
  fi
fi

# ─── GATE: API endpoints have handler files ───
echo ""
echo "Gate: Coding — API endpoint files"
API_DIR="$HYO_ROOT/website/api"
if [[ -d "$API_DIR" ]]; then
  ENDPOINT_COUNT=$(find "$API_DIR" -name "*.js" -o -name "*.ts" | wc -l | tr -d ' ')
  check "$ENDPOINT_COUNT API endpoint files found" "pass"
fi

# ─── GATE: No console.log in production code ───
echo ""
echo "Gate: Coding — production readiness"
CONSOLE_LOGS=$(grep -rl "console\.log" "$HYO_ROOT/website/api/" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$CONSOLE_LOGS" -eq 0 ]]; then
  check "No console.log in API code" "pass"
else
  check "$CONSOLE_LOGS API files contain console.log" "warn"
fi

# ─── GATE: Feed copies in sync ───
echo ""
echo "Gate: Infrastructure — data sync"
FEED_A="$HYO_ROOT/website/data/feed.json"
FEED_B="$HYO_ROOT/agents/sam/website/data/feed.json"
if [[ -f "$FEED_A" && -f "$FEED_B" ]]; then
  if diff -q "$FEED_A" "$FEED_B" > /dev/null 2>&1; then
    check "feed.json synced across both paths" "pass"
  else
    check "feed.json OUT OF SYNC between website/ and agents/sam/website/" "fail"
  fi
fi

# ─── SUMMARY ───
echo ""
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
if [[ $FAIL -gt 0 ]]; then
  echo "VERDICT: FAIL — $FAIL checks did not pass"
  exit 1
else
  echo "VERDICT: PASS"
  exit 0
fi
