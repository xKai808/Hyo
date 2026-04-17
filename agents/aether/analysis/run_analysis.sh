#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# run_analysis.sh — Daily AetherBot analysis launcher
# Runs via launchd at 23:00 MT daily
# Sources API keys from hyo.env, runs kai_analysis.py, copies output to the
# agents/aether/analysis/ directory, and publishes an aether-analysis entry
# to the HQ feed (website/data/feed.json).
# ═══════════════════════════════════════════════════════════════════════════
set -o pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
ANALYSIS_DIR="$ROOT/agents/aether/analysis"
LOG_DIR="$ROOT/agents/aether/logs"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)

# Where kai_analysis.py actually writes its output
KAI_ANALYSIS_OUTPUT_DIR="$HOME/Documents/Projects/AetherBot/Kai analysis"
KAI_ANALYSIS_FILE="$KAI_ANALYSIS_OUTPUT_DIR/Analysis_$TODAY.txt"
# Where we want the analysis to live inside the Hyo repo
REPO_ANALYSIS_FILE="$ANALYSIS_DIR/Analysis_$TODAY.txt"

log() { echo "[analysis] $(TZ=America/Denver date +%H:%M:%S) $*"; }

# Source API keys — use set -a so KEY=value lines auto-export to env
# (the hyo.env file uses bare KEY=value format without explicit `export`)
ENV_FILE="$HOME/security/hyo.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
  log "Loaded environment from $ENV_FILE"
else
  ENV_FILE="$ROOT/agents/nel/security/.env"
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
    log "Loaded environment from $ENV_FILE"
  else
    log "WARNING: No env file found. API keys may be missing."
  fi
fi

# Belt-and-suspenders: explicitly export known keys
export OPENAI_API_KEY ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID

# Check required keys
if [[ -z "$OPENAI_API_KEY" ]] && [[ -z "$ANTHROPIC_API_KEY" ]]; then
  log "ERROR: Neither OPENAI_API_KEY nor ANTHROPIC_API_KEY is set."
  log "Cannot run analysis without at least one LLM API key."
  log "Set keys in ~/security/hyo.env"
  exit 1
fi

# GATE: skip if repo already has today's analysis AND it was published to feed
if [[ -f "$REPO_ANALYSIS_FILE" ]]; then
  # Verify it also made it to HQ. If not, fall through to publish step.
  if python3 -c "
import json, sys
try:
    with open('$ROOT/agents/sam/website/data/feed.json') as f:
        d = json.load(f)
    for r in d.get('reports', []):
        if r.get('id') == 'aether-analysis-$TODAY':
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
"; then
    log "Analysis for $TODAY already exists and is on HQ. Skipping."
    exit 0
  else
    log "Analysis file exists for $TODAY but not on HQ. Will publish."
    SKIP_GEN=1
  fi
fi

# Check if AetherBot log exists and has enough data
# AetherBot logs use AetherBot_YYYY-MM-DD.txt naming (not *.log)
AETHER_LOG_DIR="$HOME/Documents/Projects/AetherBot/Logs"
LATEST_LOG=$(ls -t "$AETHER_LOG_DIR"/AetherBot_*.txt 2>/dev/null | head -1)

if [[ -z "$LATEST_LOG" ]]; then
  log "No AetherBot log files found in $AETHER_LOG_DIR (looking for AetherBot_*.txt)"
  exit 1
fi

LINE_COUNT=$(wc -l < "$LATEST_LOG" 2>/dev/null || echo "0")
log "Latest log: $LATEST_LOG ($LINE_COUNT lines)"

if [[ "$LINE_COUNT" -lt 100 ]]; then
  log "WARNING: Log has only $LINE_COUNT lines (need 100+ for meaningful analysis)"
fi

# Run the analysis unless we're just republishing an existing file
if [[ "${SKIP_GEN:-0}" != "1" ]]; then
  log "Starting daily analysis for $TODAY"
  cd "$ANALYSIS_DIR"

  if [[ -n "$OPENAI_API_KEY" ]] && [[ -n "$ANTHROPIC_API_KEY" ]]; then
    # Full analysis with both APIs
    python3 "$ANALYSIS_DIR/kai_analysis.py" 2>&1
    EXIT_CODE=$?
  elif [[ -n "$ANTHROPIC_API_KEY" ]]; then
    # Anthropic-only mode
    log "Running with Anthropic API only (no OpenAI cross-check)"
    ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" python3 "$ANALYSIS_DIR/kai_analysis.py" 2>&1
    EXIT_CODE=$?
  else
    # OpenAI-only mode (GPT fact-check)
    log "Running GPT fact-check only (no Anthropic)"
    python3 "$ANALYSIS_DIR/gpt_factcheck.py" --log "$LATEST_LOG" 2>&1
    EXIT_CODE=$?
  fi

  if [[ $EXIT_CODE -ne 0 ]]; then
    log "Analysis failed with exit code $EXIT_CODE"
    exit $EXIT_CODE
  fi
  log "Analysis completed successfully"
fi

# Copy kai_analysis.py output into the Hyo repo if it exists
if [[ -f "$KAI_ANALYSIS_FILE" ]] && [[ ! -f "$REPO_ANALYSIS_FILE" ]]; then
  cp "$KAI_ANALYSIS_FILE" "$REPO_ANALYSIS_FILE"
  log "Copied $KAI_ANALYSIS_FILE → $REPO_ANALYSIS_FILE"
fi

if [[ ! -f "$REPO_ANALYSIS_FILE" ]]; then
  log "ERROR: Expected analysis file not found at $REPO_ANALYSIS_FILE"
  exit 1
fi

# ── Publish to HQ feed as aether-analysis entry ────────────────────────────
log "Publishing aether-analysis-$TODAY to HQ feed..."
PUBLISH_SH="$ROOT/bin/aether-publish-analysis.sh"
if [[ -x "$PUBLISH_SH" ]]; then
  bash "$PUBLISH_SH" "$TODAY" "$REPO_ANALYSIS_FILE"
  PUB_RC=$?
  if [[ $PUB_RC -ne 0 ]]; then
    log "ERROR: publish step failed with rc=$PUB_RC — analysis file exists but HQ may be stale"
    exit $PUB_RC
  fi
  log "Published to HQ feed"
else
  log "ERROR: publisher missing at $PUBLISH_SH"
  exit 1
fi

log "Pipeline complete for $TODAY"
exit 0
