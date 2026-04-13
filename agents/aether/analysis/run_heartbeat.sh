#!/bin/bash
# Kai Heartbeat — runs every 15 minutes via cron
# Cron entry: */15 * * * * /Users/kai/Documents/Projects/AetherBot/Kai\ analysis/run_heartbeat.sh
# Zero external API calls. Zero cost. Pure local checks.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON="/opt/homebrew/bin/python3"

$PYTHON "$SCRIPT_DIR/heartbeat.py" >> "$SCRIPT_DIR/heartbeat_log.txt" 2>&1
