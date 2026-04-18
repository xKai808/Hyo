#!/usr/bin/env python3
"""
kai-bridge.py — Persistent HTTP command bridge for Mac Mini.
Allows Kai (Claude sessions from any machine) to execute commands on the Mini
with zero filesystem queue latency and no sandbox limitations.

Endpoint: POST http://localhost:9876/exec
Auth:     Bearer token from agents/nel/security/founder.token
Body:     {"cmd": "bash command here", "timeout": 30}
Returns:  {"ok": true, "stdout": "...", "stderr": "...", "exit_code": 0, "elapsed_ms": 123}

Security:
  - Token required on every request
  - Commands run as current user (kai)
  - No sudo (add to sudoers separately if needed)
  - Rate limit: max 1 concurrent execution
  - Log every command to kai/ledger/bridge-log.jsonl

Usage:
  python3 bin/kai-bridge.py                  # foreground
  nohup python3 bin/kai-bridge.py &          # background (use launchd instead)

launchd plist: com.hyo.kai-bridge.plist
"""

import http.server
import json
import os
import subprocess
import threading
import time
import datetime
import pathlib
import sys

# ── Config ─────────────────────────────────────────────────────────────────────
PORT = 9876
HYO_ROOT = os.path.expanduser("~/Documents/Projects/Hyo")
TOKEN_FILE = os.path.join(HYO_ROOT, "agents/nel/security/founder.token")
LOG_FILE = os.path.join(HYO_ROOT, "kai/ledger/bridge-log.jsonl")
MAX_TIMEOUT = 300  # seconds
DEFAULT_TIMEOUT = 30
LOCK = threading.Lock()

# ── Token ──────────────────────────────────────────────────────────────────────
def load_token():
    try:
        with open(TOKEN_FILE) as f:
            return f.read().strip()
    except Exception as e:
        print(f"[bridge] ERROR: cannot read token from {TOKEN_FILE}: {e}", flush=True)
        sys.exit(1)

TOKEN = load_token()

# ── Logging ────────────────────────────────────────────────────────────────────
def log_entry(cmd, stdout, stderr, exit_code, elapsed_ms, requester_ip):
    entry = {
        "ts": datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-6))).isoformat(),
        "cmd": cmd[:500],  # truncate for log
        "exit_code": exit_code,
        "elapsed_ms": elapsed_ms,
        "stdout_bytes": len(stdout),
        "stderr_bytes": len(stderr),
        "requester_ip": requester_ip,
    }
    try:
        pathlib.Path(LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as e:
        print(f"[bridge] log error: {e}", flush=True)

# ── Handler ────────────────────────────────────────────────────────────────────
class BridgeHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        # Suppress default HTTP logging (we do our own)
        pass

    def send_json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, {"ok": True, "service": "kai-bridge", "port": PORT})
        else:
            self.send_json(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        # Auth
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer ") or auth[7:] != TOKEN:
            self.send_json(401, {"ok": False, "error": "unauthorized"})
            return

        if self.path != "/exec":
            self.send_json(404, {"ok": False, "error": "unknown endpoint"})
            return

        # Parse body
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
        except Exception:
            self.send_json(400, {"ok": False, "error": "invalid JSON body"})
            return

        cmd = body.get("cmd", "").strip()
        if not cmd:
            self.send_json(400, {"ok": False, "error": "cmd is required"})
            return

        timeout = min(int(body.get("timeout", DEFAULT_TIMEOUT)), MAX_TIMEOUT)
        cwd = body.get("cwd", HYO_ROOT)

        # Acquire lock (no concurrent executions)
        if not LOCK.acquire(blocking=False):
            self.send_json(429, {"ok": False, "error": "another command is running — retry in a moment"})
            return

        requester_ip = self.client_address[0]
        print(f"[bridge] EXEC from {requester_ip}: {cmd[:120]}", flush=True)
        start = time.time()

        try:
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=timeout,
                cwd=cwd,
                env={**os.environ, "HYO_ROOT": HYO_ROOT},
            )
            stdout = result.stdout
            stderr = result.stderr
            exit_code = result.returncode
        except subprocess.TimeoutExpired:
            stdout = ""
            stderr = f"[bridge] command timed out after {timeout}s"
            exit_code = 124
        except Exception as e:
            stdout = ""
            stderr = str(e)
            exit_code = 1
        finally:
            LOCK.release()

        elapsed_ms = int((time.time() - start) * 1000)
        log_entry(cmd, stdout, stderr, exit_code, elapsed_ms, requester_ip)

        self.send_json(200, {
            "ok": exit_code == 0,
            "exit_code": exit_code,
            "stdout": stdout,
            "stderr": stderr,
            "elapsed_ms": elapsed_ms,
            "cmd": cmd,
        })


# ── Main ───────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print(f"[bridge] kai-bridge starting on port {PORT}", flush=True)
    print(f"[bridge] HYO_ROOT = {HYO_ROOT}", flush=True)
    print(f"[bridge] Token loaded from {TOKEN_FILE}", flush=True)
    print(f"[bridge] Logging to {LOG_FILE}", flush=True)

    server = http.server.HTTPServer(("0.0.0.0", PORT), BridgeHandler)
    print(f"[bridge] Listening on 0.0.0.0:{PORT} — ready", flush=True)

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[bridge] Shutting down.", flush=True)
        server.shutdown()
