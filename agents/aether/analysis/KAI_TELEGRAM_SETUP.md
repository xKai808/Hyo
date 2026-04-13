# Kai Telegram Bot Setup & Deployment

## File Location
`/sessions/bold-kind-cerf/mnt/Kai analysis/kai_telegram.py` (production-ready)

## Prerequisites

1. **Telegram Bot Token** — from @BotFather on Telegram. Add to `.env`:
   ```
   TELEGRAM_BOT_TOKEN=YOUR_TOKEN_HERE
   ```

2. **Telegram Chat ID** — your personal DM chat ID with the bot. Get via:
   ```bash
   curl "https://api.telegram.org/botTOKEN/getUpdates"
   ```
   Look for `"id": XXXXXX` in the response. Add to `.env`:
   ```
   TELEGRAM_CHAT_ID=XXXXXX
   ```

3. **API Keys in .env** — ensure present:
   - `ANTHROPIC_API_KEY` (for Claude conversations)
   - `TELEGRAM_BOT_TOKEN` (described above)
   - `TELEGRAM_CHAT_ID` (described above)

## Quick Start

### Manual (terminal)
```bash
cd ~/Documents/Projects/Kai\ analysis
python3 kai_telegram.py
```

You'll see:
```
[HH:MM:SS] Starting Kai Telegram bot (chat_id=...)
[HH:MM:SS] Alert loop started (background)
[HH:MM:SS] Message: /status
...
```

### Persistent (background, Mac Mini)
```bash
nohup python3 ~/Documents/Projects/Kai\ analysis/kai_telegram.py > ~/kai_telegram.log 2>&1 &
```

Or use `launchd` for auto-start:
```bash
# Create ~/Library/LaunchAgents/com.kai.telegram.plist
# See launchd config below
```

## Commands

| Command | Effect |
|---------|--------|
| `/status` | Current state + active metrics + open issues |
| `/balance` | Balance ledger and current balance |
| `/analysis` | Latest Final/Deep/Standard analysis file (key findings) |
| `/bot` | AetherBot log tail (last 20 lines) |
| `/issues` | Open issues list from session_brief.md |
| `/tasks` | Current task list from operator_tasks.md |
| `/stop` | Write .stop_flag to halt AetherBot |
| `/resume` | Remove .stop_flag to restart AetherBot |
| Any text | Conversational interface (sends to Claude with context) |

## Auto-Alerts

**Every 30 minutes:**
- Check AetherBot log modification time
- If no activity in 20 min: send "AetherBot may be down" alert

**Real-time:**
- Monitor for new `*Analysis*.txt` files in `~/Documents/Projects/AetherBot/Kai analysis`
- Send summary of new analysis automatically

## File Paths (all read from .env locations)

```
.env location:                  ~/Documents/Projects/Kai/.env
Session brief:                  ~/Documents/Projects/Kai/memory/session_brief.md
Operator tasks:                 ~/Documents/Projects/Kai/memory/operator_tasks.md
AetherBot logs:                 ~/Documents/Projects/AetherBot/Logs/*.log
AetherBot analysis:             ~/Documents/Projects/AetherBot/Kai analysis/*.txt
Stop flag:                       ~/Documents/Projects/AetherBot/.stop_flag
```

## Launchd Configuration (optional, for auto-start)

Create `~/Library/LaunchAgents/com.kai.telegram.plist`:
```xml
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
```

Then load it:
```bash
launchctl load ~/Library/LaunchAgents/com.kai.telegram.plist
```

## Logging

All activity goes to stdout. When running in background:
```bash
tail -f ~/kai_telegram.log
```

## Error Handling

- Bot never crashes — all exceptions caught and logged
- Network errors: log and retry on next update
- Missing files: gracefully return error message
- API errors: log with status code and continue

## Dependencies

- Python 3 (built-in only, no external packages needed)
- `requests` library not required — uses `urllib` for API calls
- No telegram-bot library — direct API calls via HTTP

## Testing

Quick test without running full bot:
```bash
python3 -c "from kai_telegram import load_env_keys; print(load_env_keys())"
```

Should print your env keys (safely load only, no API calls).
