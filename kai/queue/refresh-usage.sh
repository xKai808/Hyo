#!/bin/bash
# refresh-usage.sh — Update OpenAI + Claude CSV files from live billing APIs
# Called by: kai queue (automated every 4-6 hours), or manually via: bash refresh-usage.sh
# Logs to: /tmp/hyo-usage-refresh.log
# Falls back gracefully to existing CSVs if API keys aren't available

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DATA_DIR="$HYO_ROOT/website/data"
LOG_FILE="/tmp/hyo-usage-refresh.log"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Logging function
log() {
  echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

log "=== Usage refresh started ==="

# ─── OpenAI ───
# Requires: OPENAI_API_KEY, OPENAI_ORG_ID environment variables
refresh_openai() {
  log "Checking OpenAI API key..."

  if [ -z "${OPENAI_API_KEY:-}" ]; then
    log "OPENAI_API_KEY not set. Skipping OpenAI refresh."
    return 0
  fi

  if [ -z "${OPENAI_ORG_ID:-}" ]; then
    log "OPENAI_ORG_ID not set. Skipping OpenAI refresh."
    return 0
  fi

  log "Fetching OpenAI usage data..."

  # Calculate timestamps for last 30 days
  END_TIME=$(date +%s)
  START_TIME=$((END_TIME - 30 * 86400))

  # Call OpenAI usage API
  # Docs: https://platform.openai.com/docs/api-reference/organization/usage
  RESPONSE=$(curl -s \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "OpenAI-Organization: $OPENAI_ORG_ID" \
    "https://api.openai.com/v1/organization/billing/usage?start_time=$START_TIME&end_time=$END_TIME" 2>/dev/null || echo '{}')

  # Check for errors
  if echo "$RESPONSE" | grep -q '"error"'; then
    ERROR=$(echo "$RESPONSE" | grep -o '"message":"[^"]*' | head -1 | cut -d'"' -f4)
    log "OpenAI API error: $ERROR"
    return 1
  fi

  # Parse and save
  # Note: OpenAI's /usage endpoint returns daily data in a different format than the CSV export.
  # If you have the CSV export URL, use that instead:
  # curl -H "Authorization: Bearer $OPENAI_API_KEY" \
  #   "https://api.openai.com/v1/organization/billing/files/completions_usage?startDate=2026-03-13&endDate=2026-04-12" \
  #   -o completions_usage_2026-03-13_2026-04-12.csv

  log "OpenAI: API call succeeded, but raw JSON parsing not yet implemented."
  log "   (Set up OPENAI_CSV_EXPORT_URL or implement JSON→CSV parsing)"

  return 0
}

# ─── Anthropic Claude ───
# Requires: ANTHROPIC_API_KEY, ANTHROPIC_ORG_ID (org ID is optional but recommended)
refresh_claude() {
  log "Checking Anthropic API key..."

  if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    log "ANTHROPIC_API_KEY not set. Skipping Claude refresh."
    return 0
  fi

  log "Fetching Anthropic Claude usage data..."

  # Anthropic usage API endpoint:
  # https://api.anthropic.com/v1/organizations/{organization_id}/usage
  # Documentation: https://docs.anthropic.com/en/docs/build-a-claude-site/usage-tracking

  ORG_ID="${ANTHROPIC_ORG_ID:-}"
  if [ -z "$ORG_ID" ]; then
    log "ANTHROPIC_ORG_ID not set. Querying usage without org filter..."
    ENDPOINT="https://api.anthropic.com/v1/usage"
  else
    ENDPOINT="https://api.anthropic.com/v1/organizations/$ORG_ID/usage"
  fi

  RESPONSE=$(curl -s \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    "$ENDPOINT" 2>/dev/null || echo '{}')

  # Check for errors
  if echo "$RESPONSE" | grep -q '"error"'; then
    ERROR=$(echo "$RESPONSE" | grep -o '"message":"[^"]*' | head -1 | cut -d'"' -f4)
    log "Anthropic API error: $ERROR"
    return 1
  fi

  log "Anthropic: API call succeeded, but JSON→CSV parsing not yet implemented."
  log "   (The API returns structured JSON; you'll need a parser to convert to CSV format)"

  return 0
}

# ─── Main flow ───

log "Data directory: $DATA_DIR"
log "Existing CSVs:"
ls -lh "$DATA_DIR"/*.csv 2>/dev/null || log "  (no CSVs found)"

# Try OpenAI refresh
if ! refresh_openai; then
  log "OpenAI refresh failed or skipped. Falling back to existing CSVs."
fi

# Try Claude refresh
if ! refresh_claude; then
  log "Claude refresh failed or skipped. Falling back to existing CSVs."
fi

log "=== Usage refresh complete ==="
log "Next refresh scheduled: 4-6 hours from now"
log "To view current usage, visit: https://www.hyo.world/hq (API usage section)"

# Return success even if API calls failed (fallback is always available)
exit 0
