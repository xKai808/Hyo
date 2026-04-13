#!/usr/bin/env python3
"""
kai/queue/submit.py — Submit a command to the queue and optionally wait for result.

Usage from Cowork/Claude Code:
  python3 kai/queue/submit.py "git push origin main"
  python3 kai/queue/submit.py --wait 30 "git status"
  python3 kai/queue/submit.py --timeout 120 "npm run build"

The script writes a JSON command file to kai/queue/pending/ and optionally
polls kai/queue/completed/ or kai/queue/failed/ for the result.
"""

import json
import os
import sys
import time
import argparse
from pathlib import Path

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
QUEUE = Path(ROOT) / "kai" / "queue"


def submit(command: str, timeout: int = 60) -> str:
    """Submit a command, return the command ID."""
    cmd_id = f"cmd-{int(time.time())}-{os.getpid()}"
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    cmd = {
        "id": cmd_id,
        "ts": ts,
        "command": command,
        "timeout": timeout,
        "agent": "kai-cowork",
    }

    pending_dir = QUEUE / "pending"
    pending_dir.mkdir(parents=True, exist_ok=True)

    cmd_file = pending_dir / f"{cmd_id}.json"
    cmd_file.write_text(json.dumps(cmd, indent=2))

    return cmd_id


def wait_for_result(cmd_id: str, wait_seconds: int = 30) -> dict | None:
    """Poll for result. Returns result dict or None if timeout."""
    completed = QUEUE / "completed"
    failed = QUEUE / "failed"

    deadline = time.time() + wait_seconds
    while time.time() < deadline:
        for d in [completed, failed]:
            result_file = d / f"{cmd_id}.json"
            if result_file.exists():
                return json.loads(result_file.read_text())
        time.sleep(1)

    return None


def main():
    parser = argparse.ArgumentParser(description="Submit command to Kai queue")
    parser.add_argument("command", help="Command to execute on Mini")
    parser.add_argument("--wait", type=int, default=0,
                        help="Wait N seconds for result (0 = fire and forget)")
    parser.add_argument("--timeout", type=int, default=60,
                        help="Execution timeout in seconds")
    args = parser.parse_args()

    cmd_id = submit(args.command, args.timeout)
    print(f"Submitted: {cmd_id}")

    if args.wait > 0:
        print(f"Waiting up to {args.wait}s for result...")
        result = wait_for_result(cmd_id, args.wait)
        if result:
            print(f"Exit code: {result['exit_code']}")
            if result.get("stdout", "").strip():
                print(f"stdout:\n{result['stdout']}")
            if result.get("stderr", "").strip():
                print(f"stderr:\n{result['stderr']}")
            return result["exit_code"]
        else:
            print(f"Timeout — check kai queue results later")
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
