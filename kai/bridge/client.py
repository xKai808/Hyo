#!/usr/bin/env python3
"""
kai/bridge/client.py — Client for the Hyo HTTP bridge.

Sends commands to the Mini's bridge server via HTTP. Falls back to
filesystem queue if the bridge is unreachable.

Usage:
  from kai.bridge.client import exec_on_mini
  result = exec_on_mini("git status")
  print(result["stdout"])

CLI:
  python3 kai/bridge/client.py "git push origin main"
  python3 kai/bridge/client.py --timeout 120 "npm run build"
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))


def _load_config() -> dict:
    """Load bridge config from config.json."""
    config_path = os.path.join(ROOT, "kai", "bridge", "config.json")
    try:
        with open(config_path) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"mini_host": "192.168.1.100", "port": 9876}


def _load_token() -> str:
    """Load auth token."""
    config = _load_config()
    token_path = config.get("token_path", "agents/nel/security/founder.token")
    # Handle both absolute and relative paths
    if not os.path.isabs(token_path):
        token_path = os.path.join(ROOT, token_path)
    return Path(token_path).read_text().strip()


def exec_on_mini(command: str, timeout: int = 60) -> dict:
    """
    Execute a command on the Mini via the HTTP bridge.

    Returns dict with keys: stdout, stderr, exit_code, duration_s, command
    Falls back to filesystem queue if bridge is unreachable.
    """
    config = _load_config()
    host = config.get("mini_host", "192.168.1.100")
    port = config.get("port", 9876)
    url = f"http://{host}:{port}/exec"

    try:
        token = _load_token()
    except FileNotFoundError:
        return {
            "stdout": "",
            "stderr": "ERROR: auth token not found",
            "exit_code": -1,
            "duration_s": 0,
            "command": command,
            "source": "error",
        }

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
        # Connection timeout: 5s. Read timeout: timeout + 10s buffer
        with urllib.request.urlopen(req, timeout=timeout + 10) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            body["source"] = "bridge"
            return body
    except (urllib.error.URLError, ConnectionRefusedError, OSError, TimeoutError) as e:
        # Bridge unreachable — fall back to filesystem queue
        return _fallback_queue(command, timeout, str(e))


def _fallback_queue(command: str, timeout: int, reason: str) -> dict:
    """Fall back to filesystem-based queue submission."""
    try:
        # Import submit from queue module
        queue_submit = os.path.join(ROOT, "kai", "queue", "submit.py")
        if not os.path.exists(queue_submit):
            return {
                "stdout": "",
                "stderr": f"Bridge unreachable ({reason}) and queue submit.py not found",
                "exit_code": -1,
                "duration_s": 0,
                "command": command,
                "source": "error",
            }

        # Use the queue's submit and wait mechanism
        sys.path.insert(0, os.path.join(ROOT, "kai", "queue"))
        import importlib.util
        spec = importlib.util.spec_from_file_location("submit", queue_submit)
        submit_mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(submit_mod)

        cmd_id = submit_mod.submit(command, timeout)
        result = submit_mod.wait_for_result(cmd_id, wait_seconds=min(timeout + 10, 120))

        if result:
            result["source"] = "queue_fallback"
            return result
        else:
            return {
                "stdout": "",
                "stderr": f"Bridge unreachable ({reason}). Queue fallback timed out.",
                "exit_code": -1,
                "duration_s": 0,
                "command": command,
                "source": "queue_fallback_timeout",
            }
    except Exception as e:
        return {
            "stdout": "",
            "stderr": f"Bridge unreachable ({reason}). Queue fallback failed: {str(e)}",
            "exit_code": -1,
            "duration_s": 0,
            "command": command,
            "source": "error",
        }


def health_check() -> dict | None:
    """Check if bridge is reachable. Returns health dict or None."""
    config = _load_config()
    host = config.get("mini_host", "192.168.1.100")
    port = config.get("port", 9876)
    url = f"http://{host}:{port}/health"

    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception:
        return None


def main():
    """CLI interface."""
    import argparse
    parser = argparse.ArgumentParser(description="Execute command on Mini via bridge")
    parser.add_argument("command", nargs="?", help="Command to execute")
    parser.add_argument("--timeout", type=int, default=60, help="Timeout in seconds")
    parser.add_argument("--health", action="store_true", help="Check bridge health")
    args = parser.parse_args()

    if args.health:
        result = health_check()
        if result:
            print(json.dumps(result, indent=2))
            return 0
        else:
            print("Bridge unreachable")
            return 1

    if not args.command:
        parser.print_help()
        return 1

    result = exec_on_mini(args.command, args.timeout)
    print(f"Source: {result.get('source', 'unknown')}")
    print(f"Exit code: {result['exit_code']}")
    if result.get("stdout", "").strip():
        print(f"stdout:\n{result['stdout']}")
    if result.get("stderr", "").strip():
        print(f"stderr:\n{result['stderr']}")
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
