#!/bin/bash
# Kai API Usage Check — runs daily at 17:30 MTN via cron
# Cron entry: 30 17 * * 1-5 /Users/kai/Documents/Projects/AetherBot/Kai\ analysis/run_api_check.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="/opt/homebrew/bin/python3"
LOG="$SCRIPT_DIR/api_check_log.txt"

echo "$(date '+%Y-%m-%d %H:%M') — Starting API usage check" >> "$LOG"
$PYTHON "$SCRIPT_DIR/api_usage_check.py" >> "$LOG" 2>&1
echo "$(date '+%Y-%m-%d %H:%M') — Done" >> "$LOG"
