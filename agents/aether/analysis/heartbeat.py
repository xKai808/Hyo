#!/usr/bin/env python3
"""
Kai Heartbeat — Lightweight system health check
Runs on Mac Mini via cron every 15 minutes.
Writes status to ~/Documents/Projects/Kai/memory/heartbeat.md
Checks: AetherBot process, recent log activity, disk space, balance tracking.
NO external API calls. Zero cost.
"""

import os
import subprocess
import glob
from datetime import datetime, timedelta
from pathlib import Path

HEARTBEAT_FILE = os.path.expanduser("~/Documents/Projects/Kai/memory/heartbeat.md")
LOG_DIR = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
HEARTBEAT_LOG = os.path.expanduser("~/Documents/Projects/AetherBot/Kai analysis/heartbeat_log.txt")


def check_aetherbot_process():
    """Check if bot.py is running."""
    try:
        result = subprocess.run(
            ["pgrep", "-f", "bot.py"],
            capture_output=True, text=True, timeout=5
        )
        if result.stdout.strip():
            return "RUNNING", f"PID: {result.stdout.strip().split()[0]}"
        return "STOPPED", "No bot.py process found"
    except Exception as e:
        return "UNKNOWN", str(e)


def check_dashboard_server():
    """Check if the dashboard server is running on port 8420."""
    try:
        import urllib.request
        req = urllib.request.Request("http://localhost:8420/", method="HEAD")
        with urllib.request.urlopen(req, timeout=3) as resp:
            return "RUNNING", f"HTTP {resp.status}"
    except:
        return "DOWN", "Dashboard server not responding on port 8420"


def check_latest_log():
    """Check if AetherBot has written to logs recently."""
    today = datetime.now().strftime("%Y-%m-%d")
    log_file = os.path.join(LOG_DIR, f"AetherBot_{today}.txt")

    if not os.path.exists(log_file):
        # Check if it's a weekend — bot is OFF
        day_of_week = datetime.now().weekday()
        if day_of_week >= 5:  # Saturday=5, Sunday=6
            return "OFF (weekend)", "Bot is off on weekends"
        return "NO LOG", f"No log file for {today}"

    stat = os.stat(log_file)
    mod_time = datetime.fromtimestamp(stat.st_mtime)
    age_minutes = (datetime.now() - mod_time).total_seconds() / 60
    size_kb = stat.st_size / 1024

    if age_minutes < 20:
        return "ACTIVE", f"Last write {int(age_minutes)}m ago, {size_kb:.0f}KB"
    elif age_minutes < 60:
        return "QUIET", f"Last write {int(age_minutes)}m ago"
    else:
        return "STALE", f"No writes in {int(age_minutes)}m — check if bot is stuck"


def check_disk_space():
    """Check available disk space."""
    try:
        result = subprocess.run(
            ["df", "-h", "/"],
            capture_output=True, text=True, timeout=5
        )
        lines = result.stdout.strip().split("\n")
        if len(lines) >= 2:
            parts = lines[1].split()
            avail = parts[3] if len(parts) > 3 else "unknown"
            pct_used = parts[4] if len(parts) > 4 else "unknown"
            return avail, pct_used
    except:
        pass
    return "unknown", "unknown"


def get_last_known_balance():
    """Read last balance from session brief if available."""
    brief_file = os.path.expanduser("~/Documents/Projects/Kai/memory/session_brief.md")
    try:
        with open(brief_file, "r") as f:
            for line in f:
                if "AetherBot balance" in line:
                    parts = line.split("|")
                    if len(parts) >= 3:
                        return parts[2].strip()
    except:
        pass
    return "unknown"


def write_heartbeat():
    now = datetime.now()
    timestamp = now.strftime("%Y-%m-%d %H:%M MTN")

    bot_status, bot_detail = check_aetherbot_process()
    log_status, log_detail = check_latest_log()
    disk_avail, disk_pct = check_disk_space()
    balance = get_last_known_balance()

    dash_status, dash_detail = check_dashboard_server()

    content = f"""# Kai Heartbeat
Last active: {timestamp}

## System Status
| Check | Status | Detail |
|-------|--------|--------|
| AetherBot process | {bot_status} | {bot_detail} |
| Log activity | {log_status} | {log_detail} |
| Dashboard server | {dash_status} | {dash_detail} |
| Disk space | {disk_avail} free | {disk_pct} used |
| Last known balance | {balance} | from session brief |

## Alerts
"""

    alerts = []
    day_of_week = datetime.now().weekday()
    is_weekend = day_of_week >= 5

    if bot_status == "STOPPED" and not is_weekend:
        alerts.append("- **CRITICAL:** AetherBot process not found. Check Terminal.")
    elif bot_status == "STOPPED" and is_weekend:
        pass  # Expected — bot is off weekends
    if log_status == "STALE" and not is_weekend:
        alerts.append(f"- **WARNING:** Log stale — {log_detail}")
    if dash_status == "DOWN":
        alerts.append("- **WARNING:** Dashboard server down. Run: launchctl load ~/Library/LaunchAgents/com.kai.dashboard.plist")
    if disk_pct != "unknown" and int(disk_pct.replace("%", "")) > 90:
        alerts.append(f"- **WARNING:** Disk usage at {disk_pct}")

    if alerts:
        content += "\n".join(alerts) + "\n"
    else:
        content += "None\n"

    content += f"\n---\n*Updated every 15 minutes by heartbeat.py*\n"

    # Write heartbeat file
    os.makedirs(os.path.dirname(HEARTBEAT_FILE), exist_ok=True)
    with open(HEARTBEAT_FILE, "w") as f:
        f.write(content)

    # Append to rolling log (keeps last 24h of heartbeats for debugging)
    log_line = f"{timestamp} | bot={bot_status} | log={log_status} | disk={disk_pct}\n"
    with open(HEARTBEAT_LOG, "a") as f:
        f.write(log_line)

    # Trim heartbeat log to last 96 entries (~24h at 15min intervals)
    try:
        with open(HEARTBEAT_LOG, "r") as f:
            lines = f.readlines()
        if len(lines) > 96:
            with open(HEARTBEAT_LOG, "w") as f:
                f.writelines(lines[-96:])
    except:
        pass

    return bot_status, log_status


if __name__ == "__main__":
    bot_status, log_status = write_heartbeat()
    print(f"Heartbeat written: bot={bot_status}, log={log_status}")
