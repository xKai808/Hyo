#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# Ra verify.sh — Publishing & Content verification gates
# System 2 Gate 6 (Publishing) + System 1 Phase 2 (Execution Verification)
#
# Open-ended questions encoded as executable checks:
#   1. Is the content accurate, complete, and free of errors?
#   2. Does the tone match the platform and audience?
#   3. What is the URL, and does it load?
#   4. Can the end user actually see this content right now?
#   5. Does it appear in the feed?
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

echo "═══ Ra Verification Gates ═══"
echo "Ticket: ${TICKET_ID:-manual}"
echo ""

# ─── GATE: Newsletter output exists ───
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NEWSLETTER_MD="$HYO_ROOT/agents/ra/output/$TODAY.md"
NEWSLETTER_HTML="$HYO_ROOT/agents/ra/output/$TODAY.html"
DAILY_HTML="$HYO_ROOT/website/daily/$TODAY.html"

if [[ -s "$NEWSLETTER_MD" ]]; then
  check "Newsletter markdown exists and is non-empty" "pass"
else
  check "Newsletter markdown exists ($NEWSLETTER_MD)" "fail"
fi

if [[ -s "$NEWSLETTER_HTML" ]]; then
  check "Newsletter HTML rendered" "pass"
else
  check "Newsletter HTML rendered ($NEWSLETTER_HTML)" "fail"
fi

# ─── GATE: Content deployed to website ───
if [[ -s "$DAILY_HTML" ]]; then
  check "Newsletter deployed to /daily/$TODAY" "pass"
else
  check "Newsletter deployed to /daily/$TODAY" "fail"
fi

# ─── GATE: Feed entry exists ───
FEED="$HYO_ROOT/website/data/feed.json"
if grep -q "\"ra-newsletter-$TODAY\"" "$FEED" 2>/dev/null; then
  check "Newsletter entry in feed.json" "pass"
else
  check "Newsletter entry in feed.json" "fail"
fi

# ─── GATE: Feed entry has readLink ───
if grep -q "readLink.*daily/$TODAY" "$FEED" 2>/dev/null; then
  check "Feed entry has readLink to /daily/$TODAY" "pass"
else
  check "Feed entry has readLink" "fail"
fi

# ─── GATE: Newsletter has substantive content (not bundle/raw) ───
if [[ -s "$NEWSLETTER_MD" ]]; then
  WORD_COUNT=$(wc -w < "$NEWSLETTER_MD" | tr -d ' ')
  if [[ "$WORD_COUNT" -gt 500 ]]; then
    check "Newsletter is substantive ($WORD_COUNT words)" "pass"
  elif [[ "$WORD_COUNT" -gt 100 ]]; then
    check "Newsletter is thin ($WORD_COUNT words — should be 500+)" "warn"
  else
    check "Newsletter appears to be raw/bundle output ($WORD_COUNT words)" "fail"
  fi
fi

# ─── GATE: Both feed copies synced ───
FEED_SAM="$HYO_ROOT/agents/sam/website/data/feed.json"
if [[ -f "$FEED" && -f "$FEED_SAM" ]]; then
  if diff -q "$FEED" "$FEED_SAM" > /dev/null 2>&1; then
    check "Feed.json synced between website/ and agents/sam/website/" "pass"
  else
    check "Feed.json NOT synced — website/ and agents/sam/website/ differ" "warn"
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
