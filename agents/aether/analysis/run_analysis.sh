#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# run_analysis.sh — Daily AetherBot analysis launcher
# Runs via launchd at 23:00 MT daily
# Sources API keys from hyo.env, runs kai_analysis.py
# ═══════════════════════════════════════════════════════════════════════════
set -o pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
ANALYSIS_DIR="$ROOT/agents/aether/analysis"
LOG_DIR="$ROOT/agents/aether/logs"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)

log() { echo "[analysis] $(TZ=America/Denver date +%H:%M:%S) $*"; }

# Source API keys
ENV_FILE="$HOME/security/hyo.env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
  log "Loaded environment from $ENV_FILE"
else
  ENV_FILE="$ROOT/agents/nel/security/.env"
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
    log "Loaded environment from $ENV_FILE"
  else
    log "WARNING: No env file found. API keys may be missing."
  fi
fi

# Check required keys
if [[ -z "$OPENAI_API_KEY" ]] && [[ -z "$ANTHROPIC_API_KEY" ]]; then
  log "ERROR: Neither OPENAI_API_KEY nor ANTHROPIC_API_KEY is set."
  log "Cannot run analysis without at least one LLM API key."
  log "Set keys in ~/security/hyo.env"
  exit 1
fi

# Check if analysis already exists for today
if [[ -f "$ANALYSIS_DIR/Analysis_$TODAY.txt" ]]; then
  log "Analysis for $TODAY already exists. Skipping."
  exit 0
fi

# Check if AetherBot log exists and has enough data
AETHER_LOG_DIR="$HOME/Documents/Projects/AetherBot/Logs"
LATEST_LOG=$(ls -t "$AETHER_LOG_DIR"/*.log 2>/dev/null | head -1)

if [[ -z "$LATEST_LOG" ]]; then
  log "No AetherBot log files found in $AETHER_LOG_DIR"
  exit 1
fi

LINE_COUNT=$(wc -l < "$LATEST_LOG" 2>/dev/null || echo "0")
log "Latest log: $LATEST_LOG ($LINE_COUNT lines)"

if [[ "$LINE_COUNT" -lt 100 ]]; then
  log "WARNING: Log has only $LINE_COUNT lines (need 100+ for meaningful analysis)"
fi

# Run the analysis
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

if [[ $EXIT_CODE -eq 0 ]]; then
  log "Analysis completed successfully"

  # Copy to Hyo feed location if analysis file was produced
  if [[ -f "$ANALYSIS_DIR/Analysis_$TODAY.txt" ]]; then
    log "Analysis file: $ANALYSIS_DIR/Analysis_$TODAY.txt"
  fi
else
  log "Analysis failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
