# Kai Telegram Bot — Deployment Checklist

## Pre-Deployment

- [ ] Script location: `/sessions/bold-kind-cerf/mnt/Kai analysis/kai_telegram.py` (553 lines)
- [ ] Syntax verified: `python3 -m py_compile kai_telegram.py`
- [ ] No external packages required (built-in Python 3 only)

## Prerequisites Setup

### 1. Create Telegram Bot
```
1. Open Telegram, search for @BotFather
2. Send /newbot
3. Follow prompts to create "Kai_11_bot"
4. Copy token (looks like: 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11)
5. Save as TELEGRAM_BOT_TOKEN in .env
```

### 2. Get Your Chat ID
```bash
# In a terminal, replace TOKEN with your bot token:
curl "https://api.telegram.org/botTOKEN/getUpdates"

# Open Telegram, send /start to your bot
# Run curl again, look for:
#   "id": XXXXXXXXXXXXXX
# This is your TELEGRAM_CHAT_ID
```

### 3. Add to .env
```bash
# Edit ~/Documents/Projects/Kai/.env
# Add these lines:
TELEGRAM_BOT_TOKEN=your_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# Verify ANTHROPIC_API_KEY is also present
# (already should be from previous setup)
```

## Deployment

### Option A: Manual Start (testing)
```bash
cd ~/Documents/Projects/Kai\ analysis
python3 kai_telegram.py

# Expected output:
# [HH:MM:SS] Starting Kai Telegram bot (chat_id=...)
# [HH:MM:SS] Sent message to ...: 97 chars
# [HH:MM:SS] Alert loop started (background)

# Then open Telegram and send /status
```

### Option B: Background (simple)
```bash
# Start in background:
nohup python3 ~/Documents/Projects/Kai\ analysis/kai_telegram.py > ~/kai_telegram.log 2>&1 &

# Verify running:
ps aux | grep kai_telegram

# View logs:
tail -f ~/kai_telegram.log

# Stop:
pkill -f kai_telegram.py
```

### Option C: Launchd (persistent auto-start)
```bash
# 1. Create plist file:
cat > ~/Library/LaunchAgents/com.kai.telegram.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.kai.telegram</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Users/kai/Documents/Projects/Kai analysis/kai_telegram.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/kai/kai_telegram.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/kai/kai_telegram_error.log</string>
</dict>
</plist>
PLIST

# 2. Load it:
launchctl load ~/Library/LaunchAgents/com.kai.telegram.plist

# 3. Verify:
launchctl list | grep kai.telegram

# 4. Check logs:
tail -f ~/kai_telegram.log

# To unload later:
launchctl unload ~/Library/LaunchAgents/com.kai.telegram.plist
```

## Post-Deployment Testing

### Test Commands in Telegram

Send each of these and verify response:

```
/status     → Current state + metrics + issues (compact format)
/balance    → Balance ledger with current balance
/analysis   → Latest analysis key findings
/bot        → Last 20 log lines from AetherBot
/issues     → Open issues list
/tasks      → Task list from operator_tasks.md
/stop       → Should respond "Stop flag written..."
/resume     → Should respond "Stop flag removed..."

hello       → Should get Claude response with context
what's the balance?  → Claude responds about current balance
```

### Monitoring

```bash
# Check bot is running:
ps aux | grep kai_telegram
# Should see: python3 /Users/kai/Documents/Projects/Kai analysis/kai_telegram.py

# View live logs:
tail -f ~/kai_telegram.log

# Expected activity every 60 seconds:
# [HH:MM:SS] [Alert loop checking heartbeat...]
# [HH:MM:SS] [Alert loop checking for new analysis...]
```

## Troubleshooting

### Bot doesn't start
```bash
# Check syntax:
python3 -m py_compile ~/Documents/Projects/Kai\ analysis/kai_telegram.py

# Check .env file:
cat ~/Documents/Projects/Kai/.env | grep TELEGRAM

# Check Python:
python3 --version  # Should be 3.7+
```

### No messages appear
```bash
# Check bot received token correctly:
python3 -c "import os; print(os.path.expanduser('~/Documents/Projects/Kai/.env')); exec(open(os.path.expanduser('~/Documents/Projects/Kai/.env')).read().replace('=', ' = \"') + '\"')" 2>/dev/null || echo "Check .env manually"

# Test API call:
curl "https://api.telegram.org/botTOKEN/getMe"  # Should return bot info
```

### Logs show API errors
```bash
# 401 error → Token invalid, get new one from @BotFather
# 404 error → Chat ID wrong, run the curl command above
# Connection error → Internet issue or Telegram API down
```

## Daily Maintenance

After deployment, monitor:

```bash
# Weekly check:
ps aux | grep kai_telegram  # Ensure still running

# If crashed (not in ps output):
nohup python3 ~/Documents/Projects/Kai\ analysis/kai_telegram.py > ~/kai_telegram.log 2>&1 &

# Check for errors in logs:
grep ERROR ~/kai_telegram.log | tail -20

# Verify heartbeat alerts are firing:
grep "HEARTBEAT" ~/kai_telegram.log
# Should see one every ~30 min
```

## Rollback

If anything goes wrong:

```bash
# Stop the bot:
pkill -f kai_telegram.py

# Or via launchctl:
launchctl unload ~/Library/LaunchAgents/com.kai.telegram.plist

# Check for errors:
tail -50 ~/kai_telegram_error.log

# Restart:
nohup python3 ~/Documents/Projects/Kai\ analysis/kai_telegram.py > ~/kai_telegram.log 2>&1 &
```

---

**Script Ready**: `/sessions/bold-kind-cerf/mnt/Kai analysis/kai_telegram.py`
**Documentation**: `KAI_TELEGRAM_SETUP.md`, `TELEGRAM_BOT_SUMMARY.txt`
