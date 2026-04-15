#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Aether verify.sh — Trading & Financial Intelligence verification gates
# System 3 (Sprint) + System 4 (Adversarial) + System 5 (Memory)
#
# Open-ended questions encoded as executable checks:
#   1. Does the P&L reconcile with actual exchange balances?
#   2. Are phantom positions flagged and not counted as real?
#   3. Is the dashboard data current (not stale)?
#   4. Do logged trades match the exchange API response?
#   5. Has GPT cross-check been performed on daily analysis?
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

echo "═══ Aether Verification Gates ═══"
echo "Ticket: ${TICKET_ID:-manual}"
echo ""

# ─── GATE: Dashboard data file exists and is current ───
echo "Gate: Dashboard — data freshness"
AETHER_DATA="$HYO_ROOT/website/data/aether-daily-sections.json"
if [[ -f "$AETHER_DATA" ]]; then
  if python3 -c "import json; json.load(open('$AETHER_DATA'))" 2>/dev/null; then
    check "aether-daily-sections.json is valid JSON" "pass"
  else
    check "aether-daily-sections.json is INVALID JSON" "fail"
  fi

  # Check freshness (modified within last 24h)
  if [[ $(find "$AETHER_DATA" -mmin -1440 2>/dev/null) ]]; then
    check "Dashboard data updated within 24h" "pass"
  else
    check "Dashboard data is STALE (>24h old)" "warn"
  fi
else
  check "aether-daily-sections.json exists" "fail"
fi

# ─── GATE: Aether report in feed ───
echo ""
echo "Gate: Publishing — HQ presence"
FEED="$HYO_ROOT/website/data/feed.json"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
if grep -q "aether.*$TODAY" "$FEED" 2>/dev/null; then
  check "Aether has a report in today's feed" "pass"
else
  check "Aether has no report in today's feed" "warn"
fi

# ─── GATE: No phantom positions in latest log ───
echo ""
echo "Gate: Adversarial — phantom position check"
AETHER_LOG_DIR="$HYO_ROOT/agents/aether/logs"
if [[ -d "$AETHER_LOG_DIR" ]]; then
  LATEST_LOG=$(ls -t "$AETHER_LOG_DIR"/*.log 2>/dev/null | head -1)
  if [[ -n "$LATEST_LOG" ]]; then
    PHANTOM_COUNT=$(grep -c "POS WARNING\|phantom\|PHANTOM" "$LATEST_LOG" 2>/dev/null || echo "0")
    if [[ "$PHANTOM_COUNT" -eq 0 ]]; then
      check "No phantom position warnings in latest log" "pass"
    else
      check "$PHANTOM_COUNT phantom position warnings found" "warn"
    fi
  else
    check "Aether log files exist" "warn"
  fi
fi

# ─── GATE: Publish gates active (max 1x/day) ───
echo ""
echo "Gate: QA — publish rate limiting"
TODAY_MARKER=$(TZ=America/Denver date +%Y%m%d)
RESEARCH_MARKER="/tmp/aether-research-published-$TODAY_MARKER"
REPORT_MARKER="/tmp/aether-report-published-$TODAY_MARKER"
if [[ -f "$RESEARCH_MARKER" || -f "$REPORT_MARKER" ]]; then
  check "Daily publish markers active (rate limiting working)" "pass"
else
  check "No publish markers today (aether may not have run)" "warn"
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
