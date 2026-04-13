#!/bin/bash
# Kai Watchdog — keeps the Telegram bridge alive, enables self-restart deploys.
# When the bridge exits (code 0 = intentional restart), watchdog relaunches
# with the LATEST code from disk. This is how Cowork deploys without terminal access.
#
# ONE-TIME SETUP (paste once, never again):
#   chmod +x ~/Documents/Projects/AetherBot/kai_watchdog.sh
#   nohup ~/Documents/Projects/AetherBot/kai_watchdog.sh >> ~/kai_watchdog.log 2>&1 & disown
#
# After this, all deploys happen automatically via flag files.

BRIDGE_SCRIPT="$HOME/Documents/Projects/AetherBot/Kai analysis/kai_telegram.py"
PYTHON="/opt/homebrew/bin/python3"
LOG="$HOME/kai_telegram.log"

echo "[$(date '+%H:%M:%S')] Kai Watchdog started. PID=$$"

# Kill any existing standalone bridge instances
pkill -f "kai_telegram.py" 2>/dev/null
sleep 1

while true; do
    echo "[$(date '+%H:%M:%S')] Starting Kai Telegram bridge..."
    "$PYTHON" "$BRIDGE_SCRIPT" >> "$LOG" 2>&1
    EXIT_CODE=$?
    echo "[$(date '+%H:%M:%S')] Bridge exited (code=$EXIT_CODE). Restarting in 3s..."
    sleep 3
done
