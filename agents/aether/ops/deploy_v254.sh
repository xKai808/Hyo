#!/bin/bash
# AetherBot v254 Deployment Script
# Run from Mac Mini terminal: cd ~/Documents/Projects/AetherBot && bash deploy_v254.sh

set -e

V254="Code versions/AetherBot_MASTER_v254.py"
BOT="$HOME/bot.py"
BACKUP="$HOME/bot_v253_backup.py"

echo "=== AetherBot v254 Deploy ==="

# 1. Verify v254 exists
if [ ! -f "$V254" ]; then
    echo "ERROR: $V254 not found"
    exit 1
fi

# 2. Backup current bot.py
if [ -f "$BOT" ]; then
    cp "$BOT" "$BACKUP"
    echo "[1/3] Backed up current bot.py -> bot_v253_backup.py"
else
    echo "[1/3] No existing bot.py to backup"
fi

# 3. Copy v254 into place
cp "$V254" "$BOT"
echo "[2/3] Deployed v254 -> ~/bot.py"

# 4. Kill running bot (logger will need manual restart)
BOT_PID=$(pgrep -f "python.*bot\.py" 2>/dev/null || true)
if [ -n "$BOT_PID" ]; then
    kill $BOT_PID
    echo "[3/3] Killed old bot process (PID $BOT_PID)"
    echo ""
    echo "Restart with: cd ~/Documents/Projects/AetherBot && python3 aetherbot_logger.py"
else
    echo "[3/3] No running bot process found"
    echo ""
    echo "Start with: cd ~/Documents/Projects/AetherBot && python3 aetherbot_logger.py"
fi

echo ""
echo "v254 deployed. Changes:"
echo "  P0:   TIME_BDI_LOW pre-emptive exit + staged BDI=0 exit"
echo "  P1.1: Harvest entry gate (blocks sell below cost basis)"
echo "  P1.2: OB parser diagnostics (raw API response logging)"
echo ""
echo "Rollback: cp ~/bot_v253_backup.py ~/bot.py"
