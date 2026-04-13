#!/usr/bin/env python3
"""
AetherBot Log Rotation Wrapper
Runs AetherBot continuously and creates a new dated log file each day.
Logs saved to ~/Documents/Projects/AetherBot/Logs/AetherBot_YYYY-MM-DD.txt
Never needs to be restarted.
"""

import subprocess
import sys
import os
import datetime

BOT_PATH = os.path.expanduser("~/bot.py")
LOG_DIR = os.path.expanduser("~/Documents/Projects/AetherBot/Logs")
PYTHON = "/opt/homebrew/bin/python3"

def get_log_path():
    date = datetime.datetime.now().strftime("%Y-%m-%d")
    return os.path.join(LOG_DIR, f"AetherBot_{date}.txt")

def run():
    os.makedirs(LOG_DIR, exist_ok=True)

    process = subprocess.Popen(
        [PYTHON, "-u", BOT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=1,
        universal_newlines=True
    )

    current_date = datetime.datetime.now().strftime("%Y-%m-%d")
    log_file = open(get_log_path(), "a", buffering=1)
    print(f"AetherBot logger started. Logging to: {get_log_path()}")

    try:
        for line in process.stdout:
            # Check if day has changed — if so roll over to new log file
            new_date = datetime.datetime.now().strftime("%Y-%m-%d")
            if new_date != current_date:
                log_file.close()
                current_date = new_date
                log_file = open(get_log_path(), "a", buffering=1)
                print(f"New log file: {get_log_path()}")

            # Write to log file and print to terminal
            log_file.write(line)
            sys.stdout.write(line)

    except KeyboardInterrupt:
        print("\nStopping AetherBot...")
    finally:
        process.terminate()
        log_file.close()

if __name__ == "__main__":
    run()
