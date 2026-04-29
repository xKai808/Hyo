#!/usr/bin/env bash
# bin/publish-verify.sh — Live URL verification gate
#
# PURPOSE: After every git push, verify the deployed page actually returns 200
# with non-empty content. Called by every publish pipeline.
# Not a rule. A gate that must pass or the pipeline marks the publish FAILED.
#
# VERSION: 1.0 — 2026-04-27
# RATIONALE: Repeatedly marking tasks "done" because git push exited 0 without
# verifying the live URL. This script closes that gap.
#
# Usage:
#   bash bin/publish-verify.sh <URL> [min_bytes] [max_wait_seconds]
#
# Arguments:
#   URL              Full URL to fetch (e.g. https://hyo.world/daily/newsletter-2026-04-27)
#   min_bytes        Minimum response body size to consider valid (default: 500)
#   max_wait_seconds How long to wait for Vercel to deploy before giving up (default: 90)
#
# Exit codes:
#   0 = URL returned 200 with content >= min_bytes
#   1 = URL returned non-200, empty response, or timed out
#
# Output:
#   Writes result to stdout. Callers should capture and log.
#
# Called by:
#   agents/ra/pipeline/newsletter.sh (after Aurora newsletter publish)
#   bin/generate-morning-report.sh   (after morning report publish)
#   bin/podcast.py                   (after podcast publish)

set -uo pipefail

URL="${1:-}"
MIN_BYTES="${2:-500}"
MAX_WAIT="${3:-90}"

if [[ -z "$URL" ]]; then
  echo "[publish-verify] ERROR: URL required" >&2
  exit 1
fi

STAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
INTERVAL=10
ELAPSED=0
RESULT="TIMEOUT"
HTTP_CODE=""
BODY_BYTES=0

echo "[$STAMP] publish-verify: checking $URL (min ${MIN_BYTES}B, max wait ${MAX_WAIT}s)"

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  # Fetch with curl: follow redirects, get HTTP code + body size
  HTTP_CODE=$(curl -s -o /tmp/pv_body.tmp -w "%{http_code}" \
    --connect-timeout 5 --max-time 15 \
    -L "$URL" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "200" ]]; then
    BODY_BYTES=$(wc -c < /tmp/pv_body.tmp 2>/dev/null || echo 0)
    if [[ $BODY_BYTES -ge $MIN_BYTES ]]; then
      RESULT="PASS"
      break
    else
      RESULT="EMPTY"  # 200 but body too small — likely placeholder or blank page
    fi
  elif [[ "$HTTP_CODE" == "404" ]]; then
    RESULT="404"
  elif [[ "$HTTP_CODE" == "000" ]]; then
    RESULT="NETWORK_ERROR"
  else
    RESULT="HTTP_${HTTP_CODE}"
  fi

  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
  echo "[$STAMP] publish-verify: $RESULT (${ELAPSED}s elapsed) — retrying..."
done

rm -f /tmp/pv_body.tmp

# ── Report result ──────────────────────────────────────────────────────────────
NOW=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
if [[ "$RESULT" == "PASS" ]]; then
  echo "[$NOW] publish-verify: PASS — $URL returned HTTP 200, ${BODY_BYTES}B"
  exit 0
else
  echo "[$NOW] publish-verify: FAIL — $URL result=$RESULT http=$HTTP_CODE bytes=${BODY_BYTES}" >&2

  # ── Telegram alert on failure ────────────────────────────────────────────────
  # PROTOCOL: @xaetherbot is the ONLY Telegram channel. (AETHER_OPERATIONS.md §14)
  # Credentials live in ~/Documents/Projects/Kai/.env (not nel/security/ — those files don't exist).
  ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
  KAI_ENV="$HOME/Documents/Projects/Kai/.env"
  # AETHERBOT_TELEGRAM_TOKEN = @xAetherbot (alerts only). TELEGRAM_BOT_TOKEN = @Kai_11_bot (conversations).
  TOKEN=$(grep '^AETHERBOT_TELEGRAM_TOKEN=' "$KAI_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"'"'" || true)
  TOKEN=${TOKEN:-$(grep '^AETHERBOT_TELEGRAM_TOKEN=' "$HOME/security/hyo.env" 2>/dev/null | cut -d= -f2 | tr -d '"'"'" || true)}
  TOKEN=${TOKEN:-$(grep '^TELEGRAM_BOT_TOKEN=' "$KAI_ENV" 2>/dev/null | cut -d= -f2 | tr -d '"'"'" || echo "${TELEGRAM_BOT_TOKEN:-}")}
  CHAT=$(grep '^TELEGRAM_CHAT_ID=' "$KAI_ENV" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '"'"'" | tr -d '[:space:]' || echo "${TELEGRAM_CHAT_ID:-}")
  if [[ -n "$TOKEN" && -n "$CHAT" ]]; then
    MSG="🚨 PUBLISH VERIFY FAIL | $URL | result=$RESULT | http=$HTTP_CODE | ${ELAPSED}s waited"
    curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
      -d "chat_id=${CHAT}" -d "text=${MSG}" >/dev/null 2>&1 || true
  fi

  exit 1
fi
