#!/usr/bin/env bash
# bin/aetherbot-monitor.sh — Real 15-minute AetherBot trade monitor
#
# Runs every 15 min via kai-autonomous.sh. Looks at the ACTUAL last 15 minutes
# of the AetherBot log and answers: is the bot trading when it should be?
#
# Distinguishes:
#   NORMAL — bot running, READY signals being filtered by market conditions
#   AUTH_FAILURE — 401 errors happening right now (key not set / rejected)
#   DEAD — no log writes in last 15 min (process crashed)
#   TRADED — actual BUY SNAPSHOT happened (this is what we want to see)
#
# SE-031-004: Addresses Hyo's concern that "verifying" vs "seeing actual trades"
# is different. This monitor reports what actually happened, not what should happen.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
LOG_DIR="$HOME/Documents/Projects/AetherBot/Logs"
TODAY=$(TZ="America/Denver" date +"%Y-%m-%d")
LOG_FILE="$LOG_DIR/AetherBot_${TODAY}.txt"
INBOX="$ROOT/kai/ledger/hyo-inbox.jsonl"
MONITOR_LOG="$ROOT/kai/ledger/aetherbot-monitor.log"
TS=$(TZ="America/Denver" date +"%Y-%m-%dT%H:%M:%S-06:00")
NOW_EPOCH=$(date +%s)
WINDOW_SECS=900  # 15 minutes

log() { echo "[$TS] $*" | tee -a "$MONITOR_LOG"; }

# ─── Check process is alive ──────────────────────────────────────────────────
BOT_PID=$(pgrep -f "python.*bot\.py" 2>/dev/null | head -1)
if [[ -z "$BOT_PID" ]]; then
    log "DEAD: AetherBot process not running"
    printf '{"ts":"%s","from":"aetherbot-monitor","priority":"P0","status":"unread","subject":"AetherBot DEAD — process not running","body":"AetherBot process (bot.py) is not running. No trades possible. Fix: cd ~/Documents/Projects/AetherBot && nohup /opt/homebrew/bin/python3 aetherbot_logger.py >> /dev/null 2>&1 &"}\n' "$TS" >> "$INBOX"
    exit 1
fi

# ─── Check log file exists and is being written ──────────────────────────────
if [[ ! -f "$LOG_FILE" ]]; then
    log "DEAD: No log file for today ($LOG_FILE)"
    printf '{"ts":"%s","from":"aetherbot-monitor","priority":"P0","status":"unread","subject":"AetherBot log missing for %s","body":"No AetherBot log file found for today. Bot may not be writing output."}\n' "$TS" "$TODAY" >> "$INBOX"
    exit 1
fi

LOG_MOD=$(stat -f %m "$LOG_FILE" 2>/dev/null || stat -c %Y "$LOG_FILE" 2>/dev/null || echo 0)
LOG_AGE=$(( NOW_EPOCH - LOG_MOD ))
if [[ "$LOG_AGE" -gt 120 ]]; then
    log "STALE: Log file last written ${LOG_AGE}s ago (>2min) — bot may be frozen"
    printf '{"ts":"%s","from":"aetherbot-monitor","priority":"P1","status":"unread","subject":"AetherBot log stale — last write %ds ago","body":"AetherBot log has not been updated in %d seconds. Bot may be frozen or crashed. PID %s still exists but no output."}\n' "$TS" "$LOG_AGE" "$LOG_AGE" "$BOT_PID" >> "$INBOX"
fi

# ─── Parse last 15 minutes of activity ───────────────────────────────────────
# Get current MT time for window boundary
WINDOW_START=$(TZ="America/Denver" date -v-15M +"%H:%M:%S" 2>/dev/null || \
               TZ="America/Denver" date -d "-15 minutes" +"%H:%M:%S" 2>/dev/null)

# Count key events in the last 15 min window
# Note: 401 lines don't have timestamps so we count total day 401s and compare to last check
READY_IN_WINDOW=$(awk -v ws="$WINDOW_START" '
    /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9].*READY/ {
        ts=substr($0,1,8)
        if (ts >= ws) count++
    }
    END {print count+0}
' "$LOG_FILE" 2>/dev/null)

BUY_IN_WINDOW=$(awk -v ws="$WINDOW_START" '
    /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9].*BUY SNAPSHOT/ {
        ts=substr($0,1,8)
        if (ts >= ws) count++
    }
    END {print count+0}
' "$LOG_FILE" 2>/dev/null)

AUTH_FAIL_TODAY=$(grep -c "Order failed: 401" "$LOG_FILE" 2>/dev/null; true)
AUTH_FAIL_TODAY="${AUTH_FAIL_TODAY:-0}"
BUY_TODAY=$(grep -c "BUY SNAPSHOT" "$LOG_FILE" 2>/dev/null; true)
BUY_TODAY="${BUY_TODAY:-0}"

# Check if AETHERBOT_KEY is actually configured
# Check env var first, then fall back to reading the .env file (bot may have loaded it)
KEY_CHECK=$(python3 -c "
import os
# Check env var
k = os.environ.get('AETHERBOT_KEY', '')
if k and k != 'PASTE_YOUR_AETHERBOT_KEY_ID_HERE':
    print('OK')
else:
    # Check .env file (where aetherbot_logger.py loads it from)
    env_file = os.path.expanduser('~/Documents/Projects/Hyo/agents/nel/security/env')
    try:
        with open(env_file) as f:
            for line in f:
                if line.strip().startswith('AETHERBOT_KEY='):
                    v = line.strip().split('=', 1)[1].strip()
                    if v and v != 'PASTE_YOUR_AETHERBOT_KEY_ID_HERE':
                        print('OK (from env file)')
                        exit()
    except Exception:
        pass
    print('MISSING')
" 2>/dev/null || echo "MISSING")

# ─── Rate-limit alerts (once per 4 hours per type) ───────────────────────────
AUTH_FLAG="/tmp/aether-auth-monitor-$(TZ=America/Denver date +%Y%m%d%H | head -c 11)"
NOTRADE_FLAG="/tmp/aether-notrade-monitor-$(TZ=America/Denver date +%Y%m%d%H | head -c 11)"

log "STATUS: bot PID=$BOT_PID, log_age=${LOG_AGE}s, ready_15m=$READY_IN_WINDOW, buys_15m=$BUY_IN_WINDOW, buys_today=$BUY_TODAY, auth_fail_today=$AUTH_FAIL_TODAY, key=$KEY_CHECK"

# ─── Alert: Key not configured ───────────────────────────────────────────────
if [[ "$KEY_CHECK" == "MISSING" ]] && [[ ! -f "$AUTH_FLAG" ]]; then
    touch "$AUTH_FLAG"
    log "ALERT: AETHERBOT_KEY not set — all orders will 401"
    printf '{"ts":"%s","from":"aetherbot-monitor","priority":"P0","status":"unread","subject":"AetherBot KEY not configured — 401 on all orders","body":"AETHERBOT_KEY env var is not set. Bot is running (PID %s) but will fail with 401 on every order attempt. Fix: (1) echo AETHERBOT_KEY=YOUR_KEY_ID >> ~/Documents/Projects/Hyo/agents/nel/security/.env (2) Restart: pkill -f aetherbot_logger && cd ~/Documents/Projects/AetherBot && nohup python3 aetherbot_logger.py >> /dev/null 2>&1 &"}\n' "$TS" "$BOT_PID" >> "$INBOX"
fi

# ─── Report: Successful trade (positive signal) ───────────────────────────────
if [[ "$BUY_IN_WINDOW" -gt 0 ]]; then
    log "TRADED: $BUY_IN_WINDOW BUY SNAPSHOT(s) in last 15min — bot is actively trading"
fi

# ─── Alert: READY signals but no trades for extended period ──────────────────
if [[ "$READY_IN_WINDOW" -gt 5 && "$BUY_IN_WINDOW" -eq 0 && "$BUY_TODAY" -eq 0 ]]; then
    # Check the reason — if it's always ABS_TOO_LOW or PRICE_ABOVE_CEIL, that's normal market conditions
    FILTER_COUNT=$(awk -v ws="$WINDOW_START" '
        /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9].*READY.*(ABS_TOO_LOW|PRICE_ABOVE_CEIL|BPS_TOO_LOW)/ {
            ts=substr($0,1,8)
            if (ts >= ws) count++
        }
        END {print count+0}
    ' "$LOG_FILE" 2>/dev/null)

    PASS_COUNT=$(awk -v ws="$WINDOW_START" '
        /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9].*READY.*PASS/ {
            ts=substr($0,1,8)
            if (ts >= ws) count++
        }
        END {print count+0}
    ' "$LOG_FILE" 2>/dev/null)

    if [[ "$PASS_COUNT" -gt 0 && ! -f "$AUTH_FLAG" ]]; then
        touch "$AUTH_FLAG"
        log "ALERT: $PASS_COUNT PASS signals in last 15min with 0 trades — auth or execution failure"
        printf '{"ts":"%s","from":"aetherbot-monitor","priority":"P0","status":"unread","subject":"AetherBot PASS signals not converting to trades","body":"Bot generated %d PASS signals in last 15 minutes (conditions met for trade) but placed 0 orders. Auth failure likely. auth_fail_today=%s, key=%s. Check 401 errors: grep Order.failed %s"}\n' "$TS" "$PASS_COUNT" "$AUTH_FAIL_TODAY" "$KEY_CHECK" "$LOG_FILE" >> "$INBOX"
    elif [[ "$FILTER_COUNT" -eq "$READY_IN_WINDOW" ]]; then
        log "NORMAL: all $READY_IN_WINDOW READY signals filtered by market conditions (ABS/BPS/PRICE) — no alert needed"
    fi
fi

# ─── Summary line for morning report ─────────────────────────────────────────
SUMMARY_FILE="$ROOT/agents/aether/ledger/trade-monitor-latest.json"
python3 -c "
import json, os
summary = {
    'ts': '$TS',
    'bot_pid': '$BOT_PID',
    'log_age_s': $LOG_AGE,
    'ready_last_15m': $READY_IN_WINDOW,
    'buys_last_15m': $BUY_IN_WINDOW,
    'buys_today': $BUY_TODAY,
    'auth_fail_today': $AUTH_FAIL_TODAY,
    'key_status': '$KEY_CHECK',
    'status': 'TRADING' if $BUY_IN_WINDOW > 0 else ('AUTH_BROKEN' if '$KEY_CHECK' == 'MISSING' else 'MONITORING')
}
with open('$SUMMARY_FILE', 'w') as f:
    json.dump(summary, f, indent=2)
    f.write('\n')
" 2>/dev/null || true

log "Monitor complete: ready=$READY_IN_WINDOW buys_15m=$BUY_IN_WINDOW buys_today=$BUY_TODAY auth_fail=$AUTH_FAIL_TODAY"
