#!/usr/bin/env python3
"""
kai/queue/submit.py — Submit a command to the queue and optionally wait for result.

BRIDGE-FIRST MODE (v2): Tries HTTP bridge before filesystem queue.
The bridge eliminates mount-sync latency (30-120s) by sending commands
directly over HTTP to the Mini's bridge server.

Usage from Cowork/Claude Code:
  python3 kai/queue/submit.py "git push origin main"
  python3 kai/queue/submit.py --wait 30 "git status"
  python3 kai/queue/submit.py --timeout 120 "npm run build"
  python3 kai/queue/submit.py --queue-only "git status"   # skip bridge

The script tries the HTTP bridge first. If unreachable, falls back to
writing a JSON command file to kai/queue/pending/ and polling for results.
"""

import json
import os
import sys
import time
import argparse
import urllib.request
import urllib.error
from pathlib import Path

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
QUEUE = Path(ROOT) / "kai" / "queue"


# ── Bridge-first execution ────────────────────────────────────────────────────

def _try_bridge(command: str, timeout: int = 60) -> dict | None:
    """Try HTTP bridge. Returns result dict or None if unreachable."""
    config_path = Path(ROOT) / "kai" / "bridge" / "config.json"
    try:
        config = json.loads(config_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return None

    host = config.get("mini_host", "")
    port = config.get("port", 9876)
    if not host or host == "MINI_IP_HERE":
        return None  # not configured yet

    # Load token
    token_path = config.get("token_path", "agents/nel/security/founder.token")
    if not os.path.isabs(token_path):
        token_path = os.path.join(ROOT, token_path)
    try:
        token = Path(token_path).read_text().strip()
    except FileNotFoundError:
        return None

    url = f"http://{host}:{port}/exec"
    payload = json.dumps({"command": command, "timeout": timeout}).encode("utf-8")

    req = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=timeout + 10) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            result["source"] = "bridge"
            return result
    except (urllib.error.URLError, ConnectionRefusedError, OSError, TimeoutError):
        return None


# ── Filesystem queue (original method) ────────────────────────────────────────

def submit(command: str, timeout: int = 60) -> str:
    """Submit a command to filesystem queue, return the command ID."""
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


# ── Main (bridge-first) ──────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Submit command to Kai queue")
    parser.add_argument("command", help="Command to execute on Mini")
    parser.add_argument("--wait", type=int, default=0,
                        help="Wait N seconds for result (0 = fire and forget)")
    parser.add_argument("--timeout", type=int, default=60,
                        help="Execution timeout in seconds")
    parser.add_argument("--queue-only", action="store_true",
                        help="Skip bridge, use filesystem queue only")
    args = parser.parse_args()

    # ── Try bridge first (unless --queue-only) ──
    if not args.queue_only:
        result = _try_bridge(args.command, args.timeout)
        if result is not None:
            print(f"[bridge] Exit code: {result['exit_code']}")
            if result.get("stdout", "").strip():
                print(f"stdout:\n{result['stdout']}")
            if result.get("stderr", "").strip():
                print(f"stderr:\n{result['stderr']}")
            return result["exit_code"]
        else:
            print("[bridge] Unreachable, falling back to filesystem queue...")

    # ── Filesystem queue fallback ──
    cmd_id = submit(args.command, args.timeout)
    print(f"Submitted: {cmd_id}")

    if args.wait > 0 or not args.queue_only:
        wait_time = args.wait if args.wait > 0 else 30
        print(f"Waiting up to {wait_time}s for result...")
        result = wait_for_result(cmd_id, wait_time)
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
