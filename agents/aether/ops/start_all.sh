#!/bin/bash
# AetherBot + Kai Telegram — complete startup script
# Kills conflicts, sets env, starts both services
# Usage: bash ~/Documents/Projects/AetherBot/start_all.sh

set -e

echo "=== Kai Infrastructure Startup ==="

# 1. Kill ALL conflicting processes
echo "[1/5] Killing conflicting processes..."
pkill -f "python.*bot\.py" 2>/dev/null || true
pkill -f "python.*kai_bot" 2>/dev/null || true
pkill -f "python.*kai_telegram" 2>/dev/null || true
pkill -f "python.*telegram" 2>/dev/null || true
sleep 2
echo "  Done."

# 2. Ensure .env has Telegram credentials
ENV_FILE="$HOME/Documents/Projects/Kai/.env"
if ! grep -q "TELEGRAM_BOT_TOKEN=" "$ENV_FILE" 2>/dev/null; then
    echo "TELEGRAM_BOT_TOKEN=8764945876:AAEpWflnfYqmCtN-2oFvSC3QU_DTP8_9OQY" >> "$ENV_FILE"
    echo "  Added TELEGRAM_BOT_TOKEN to .env"
fi
if ! grep -q "TELEGRAM_CHAT_ID=" "$ENV_FILE" 2>/dev/null; then
    echo "TELEGRAM_CHAT_ID=5098923226" >> "$ENV_FILE"
    echo "  Added TELEGRAM_CHAT_ID to .env"
fi
echo "[2/5] Env vars confirmed."

# 3. Deploy latest v254
BOT_SRC="$HOME/Documents/Projects/AetherBot/Code versions/AetherBot_MASTER_v254.py"
BOT_DST="$HOME/bot.py"
if [ -f "$BOT_SRC" ]; then
    cp "$BOT_SRC" "$BOT_DST"
    echo "[3/5] v254 deployed to ~/bot.py"
else
    echo "[3/5] WARNING: v254 source not found, using existing ~/bot.py"
fi

# 4. Start AetherBot via logger
cd "$HOME/Documents/Projects/AetherBot"
nohup /opt/homebrew/bin/python3 aetherbot_logger.py >> /dev/null 2>&1 &
ABOT_PID=$!
echo "[4/5] AetherBot started (PID $ABOT_PID)"

# 5. Start Kai Telegram bridge
sleep 1
nohup /opt/homebrew/bin/python3 "$HOME/Documents/Projects/AetherBot/Kai analysis/kai_telegram.py" >> "$HOME/kai_telegram.log" 2>&1 &
KAI_PID=$!
echo "[5/5] Kai Telegram bridge started (PID $KAI_PID)"

echo ""
echo "=== All systems running ==="
echo "  AetherBot v254:  PID $ABOT_PID"
echo "  Kai Telegram:    PID $KAI_PID"
echo "  Test: send /status to @Kai_11_bot"
echo "  Logs: tail -f ~/kai_telegram.log"
echo "  Stop all: pkill -f 'python.*bot\.py'; pkill -f kai_telegram"
