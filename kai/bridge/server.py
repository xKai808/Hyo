#!/usr/bin/env python3
"""
kai/bridge/server.py — HTTP command bridge for Hyo Mini.

Replaces filesystem-based queue polling with direct HTTP execution.
Cowork (or any authorized client) POSTs commands; this server executes
them in ~/Documents/Projects/Hyo and returns JSON results.

Security:
  - Bearer token required (from agents/nel/security/founder.token)
  - Command safety checks (ported from worker.sh)
  - Binds 0.0.0.0:9876 for local-network access only

Usage:
  python3 kai/bridge/server.py                # foreground
  python3 kai/bridge/server.py --port 9876    # custom port
"""

import http.server
import json
import os
import re
import subprocess
import sys
import time
import threading
from pathlib import Path
from urllib.parse import urlparse

# ── Configuration ─────────────────────────────────────────────────────────────

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
PORT = int(os.environ.get("HYO_BRIDGE_PORT", "9876"))
MAX_TIMEOUT = 300  # 5 minutes, same cap as worker.sh
MAX_OUTPUT = 10240  # 10KB output cap, same as worker.sh
LOG_FILE = os.path.join(ROOT, "kai", "bridge", "bridge.log")

START_TIME = time.time()
COMMAND_COUNT = 0
COMMAND_LOCK = threading.Lock()


def load_token() -> str:
    """Load bearer token from founder.token."""
    token_path = os.path.join(ROOT, "agents", "nel", "security", "founder.token")
    try:
        return Path(token_path).read_text().strip()
    except FileNotFoundError:
        log(f"FATAL: token file not found at {token_path}")
        sys.exit(1)


AUTH_TOKEN = None  # loaded at startup


# ── Logging ───────────────────────────────────────────────────────────────────

def log(msg: str):
    """Append timestamped message to bridge.log."""
    ts = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime())
    line = f"[{ts}] {msg}\n"
    try:
        os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(line)
    except Exception:
        pass  # don't crash on log failure
    # Also print to stdout for launchd log capture
    print(line, end="", flush=True)


# ── Safety checks (ported from worker.sh is_safe_command) ─────────────────────

DANGEROUS_PATTERNS = [
    r'rm\s+-rf\s+/',
    r'mkfs',
    r'dd\s+if=',
    r':\(\)\{\s*:\|',
    r'chmod\s+-R\s+777',
    r'curl.*\|.*sh',
    r'wget.*\|.*sh',
]

SECRET_PATTERNS = [
    r'cat.*secret',
    r'cat.*token',
    r'cat.*\.key',
    r'cat.*\.env',
    r'echo.*secret',
]


def is_safe_command(cmd: str) -> bool:
    """Return True if command passes safety checks."""
    cmd_lower = cmd.lower()
    for pattern in DANGEROUS_PATTERNS + SECRET_PATTERNS:
        if re.search(pattern, cmd_lower):
            return False
    return True


# ── Command execution ─────────────────────────────────────────────────────────

def execute_command(command: str, timeout: int = 60) -> dict:
    """Execute a shell command in the project root and return results."""
    global COMMAND_COUNT

    timeout = min(timeout, MAX_TIMEOUT)
    start = time.time()

    # Clear proxy vars (same as worker.sh)
    env = os.environ.copy()
    for var in ["http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY",
                "ALL_PROXY", "all_proxy", "no_proxy", "NO_PROXY"]:
        env.pop(var, None)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_CONFIG_COUNT"] = "2"
    env["GIT_CONFIG_KEY_0"] = "http.proxy"
    env["GIT_CONFIG_VALUE_0"] = ""
    env["GIT_CONFIG_KEY_1"] = "https.proxy"
    env["GIT_CONFIG_VALUE_1"] = ""

    try:
        result = subprocess.run(
            ["bash", "-c", command],
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=ROOT,
            env=env,
        )
        stdout = result.stdout[:MAX_OUTPUT]
        stderr = result.stderr[:MAX_OUTPUT]
        exit_code = result.returncode
    except subprocess.TimeoutExpired:
        stdout = ""
        stderr = f"TIMEOUT: command exceeded {timeout}s limit"
        exit_code = 124  # standard timeout exit code
    except Exception as e:
        stdout = ""
        stderr = f"EXEC_ERROR: {str(e)}"
        exit_code = -1

    duration = round(time.time() - start, 2)

    with COMMAND_LOCK:
        COMMAND_COUNT += 1

    return {
        "stdout": stdout,
        "stderr": stderr,
        "exit_code": exit_code,
        "duration_s": duration,
        "command": command,
    }


# ── HTTP Handler ──────────────────────────────────────────────────────────────

class BridgeHandler(http.server.BaseHTTPRequestHandler):
    """Handle POST /exec and POST /health."""

    def log_message(self, format, *args):
        """Override to use our logger instead of stderr."""
        log(f"HTTP: {format % args}")

    def _send_json(self, status: int, data: dict):
        """Send a JSON response."""
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_auth(self) -> bool:
        """Verify bearer token. Returns True if authorized."""
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self._send_json(401, {"error": "Missing or invalid Authorization header"})
            return False
        token = auth[7:].strip()
        if token != AUTH_TOKEN:
            log(f"AUTH_FAIL: invalid token from {self.client_address[0]}")
            self._send_json(403, {"error": "Invalid token"})
            return False
        return True

    def _read_body(self) -> dict | None:
        """Read and parse JSON body."""
        try:
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length)
            return json.loads(raw)
        except (json.JSONDecodeError, ValueError) as e:
            self._send_json(400, {"error": f"Invalid JSON: {str(e)}"})
            return None

    def do_POST(self):
        path = urlparse(self.path).path

        if path == "/health":
            self._handle_health()
        elif path == "/exec":
            self._handle_exec()
        else:
            self._send_json(404, {"error": f"Unknown endpoint: {path}"})

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self._handle_health()
        else:
            self._send_json(404, {"error": f"Unknown endpoint: {path}"})

    def _handle_health(self):
        """Return server health status (no auth required for health check)."""
        uptime = round(time.time() - START_TIME, 1)
        self._send_json(200, {
            "status": "ok",
            "uptime_s": uptime,
            "commands_processed": COMMAND_COUNT,
            "root": ROOT,
        })

    def _handle_exec(self):
        """Execute a command and return results."""
        if not self._check_auth():
            return

        body = self._read_body()
        if body is None:
            return

        command = body.get("command")
        if not command or not isinstance(command, str):
            self._send_json(400, {"error": "Missing 'command' field"})
            return

        timeout = min(int(body.get("timeout", 60)), MAX_TIMEOUT)

        # Safety check
        if not is_safe_command(command):
            log(f"BLOCKED: {command[:80]}")
            self._send_json(403, {
                "error": "Command blocked by safety check",
                "command": command,
                "exit_code": -1,
            })
            return

        log(f"EXEC: {command[:120]} (timeout={timeout}s)")
        result = execute_command(command, timeout)
        log(f"DONE: exit={result['exit_code']} ({result['duration_s']}s)")

        status = 200 if result["exit_code"] == 0 else 422
        self._send_json(status, result)


# ── Server startup ────────────────────────────────────────────────────────────

class ThreadedHTTPServer(http.server.HTTPServer):
    """Handle each request in a new thread so long commands don't block health checks."""
    allow_reuse_address = True

    def process_request(self, request, client_address):
        t = threading.Thread(target=self._handle_request_thread,
                             args=(request, client_address))
        t.daemon = True
        t.start()

    def _handle_request_thread(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        except Exception:
            self.handle_error(request, client_address)
        finally:
            self.shutdown_request(request)


def main():
    global AUTH_TOKEN, PORT

    # Parse --port flag
    if "--port" in sys.argv:
        idx = sys.argv.index("--port")
        if idx + 1 < len(sys.argv):
            PORT = int(sys.argv[idx + 1])

    AUTH_TOKEN = load_token()
    log(f"START: binding 0.0.0.0:{PORT}, root={ROOT}")

    server = ThreadedHTTPServer(("0.0.0.0", PORT), BridgeHandler)
    try:
        log("READY: accepting connections")
        server.serve_forever()
    except KeyboardInterrupt:
        log("SHUTDOWN: interrupted")
        server.shutdown()


if __name__ == "__main__":
    main()
