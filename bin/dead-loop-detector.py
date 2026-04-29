#!/usr/bin/env python3
"""
bin/dead-loop-detector.py — Agent Dead-Loop Circuit Breaker

ARCHITECTURE: Based on GVU Variance Inequality (arXiv:2512.02731), Reflexion
(NeurIPS 2023), and TokenFence.dev circuit breaker pattern.

WHAT IT DOES:
  Detects when an agent runner is stuck in a repetitive cycle — same assessment,
  same weakness, same improvement plan — without evidence of forward progress.
  Three-tier response: warn → inject probe → escalate with state dump.

HOW IT WORKS:
  - Hash fingerprint: md5(agent + weakness_id + action_type + file_hash)
  - Ring buffer: 6 most recent cycle fingerprints per agent
  - If 3/6 fingerprints are identical → WARN (inject probe question)
  - If 5/6 fingerprints are identical → HARD STOP (escalate to Hyo inbox)
  - If state_hash_unchanged for 3 cycles → ESCALATE_HUMAN

USAGE:
  python3 bin/dead-loop-detector.py check <agent>       # check current cycle
  python3 bin/dead-loop-detector.py record <agent> <fingerprint_json>  # log step
  python3 bin/dead-loop-detector.py reset <agent>       # clear after real progress
  python3 bin/dead-loop-detector.py status              # all agents status

CALLED BY:
  - Every agent runner (nel.sh, ra.sh, sam.sh, etc.) before ARIC Phase 2
  - kai-autonomous.sh healthcheck
  - PROTOCOL_ARIC.md Phase 7.5

VERSION: 1.0 — 2026-04-27
SOURCES:
  - arXiv:2512.02731 (GVU Operator, Variance Inequality)
  - arXiv:2303.11366 (Reflexion)
  - arXiv:2512.20845 (MAR, dead-loop in single-agent reflection)
  - github.com/paperclipai/paperclip #390 (circuit breaker)
  - tokenfence.dev
"""

import json
import sys
import os
import hashlib
import time
from pathlib import Path
from datetime import datetime, timezone

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
STATE_FILE = os.path.join(ROOT, "kai/ledger/dead-loop-state.json")
SESSION_ERRORS = os.path.join(ROOT, "kai/ledger/session-errors.jsonl")
HYO_INBOX = os.path.join(ROOT, "kai/ledger/hyo-inbox.jsonl")

RING_SIZE = 6      # fingerprints to track per agent
WARN_COUNT = 3     # identical fingerprints → warn
STOP_COUNT = 5     # identical fingerprints → hard stop
NULL_PROGRESS = 3  # cycles with no state change → escalate human


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(state):
    Path(STATE_FILE).parent.mkdir(parents=True, exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def fingerprint(agent, weakness_id, action_type, content_hash=""):
    """Create a deterministic fingerprint for this agent's current cycle state."""
    raw = f"{agent}|{weakness_id}|{action_type}|{content_hash}"
    return hashlib.md5(raw.encode()).hexdigest()[:12]


def state_hash(agent, weakness_id, improvement_status, files_changed):
    """Hash the actual state — not just what the agent thinks it did."""
    raw = f"{agent}|{weakness_id}|{improvement_status}|{sorted(files_changed or [])}"
    return hashlib.md5(str(raw).encode()).hexdigest()[:12]


def log_session_error(agent, description, severity="P1"):
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "category": "dead_loop",
        "agent": agent,
        "description": description,
        "severity": severity,
        "prevention": "dead-loop-detector.py circuit breaker — auto-detected"
    }
    with open(SESSION_ERRORS, "a") as f:
        f.write(json.dumps(entry) + "\n")


def alert_hyo_inbox(agent, message, severity="P1"):
    entry = {
        "id": f"dead-loop-{agent}-{int(time.time())}",
        "ts": datetime.now(timezone.utc).isoformat(),
        "from": "dead-loop-detector",
        "severity": severity,
        "subject": f"CIRCUIT BREAKER: {agent} dead loop detected",
        "body": message,
        "status": "unread"
    }
    Path(HYO_INBOX).parent.mkdir(parents=True, exist_ok=True)
    with open(HYO_INBOX, "a") as f:
        f.write(json.dumps(entry) + "\n")


def send_telegram(message):
    """Best-effort Telegram alert."""
    # AETHERBOT_TELEGRAM_TOKEN = @xAetherbot (alerts only). TELEGRAM_BOT_TOKEN = @Kai_11_bot (conversations).
    token = os.environ.get("AETHERBOT_TELEGRAM_TOKEN") or os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat = os.environ.get("TELEGRAM_CHAT_ID", "")
    if not (token and chat):
        # Try loading from env file
        # @xaetherbot channel — credentials in ~/Documents/Projects/Kai/.env (AETHER_OPERATIONS.md §14)
        for kai_env in [
            os.path.expanduser("~/Documents/Projects/Kai/.env"),
            os.path.expanduser("~/security/hyo.env"),
        ]:
            try:
                for line in open(kai_env):
                    if line.startswith("AETHERBOT_TELEGRAM_TOKEN=") and not token:
                        token = line.split("=",1)[1].strip().strip('"').strip("'")
                    elif line.startswith("TELEGRAM_BOT_TOKEN=") and not token:
                        token = line.split("=",1)[1].strip().strip('"').strip("'")
                    elif line.startswith("TELEGRAM_CHAT_ID=") and not chat:
                        chat = line.split("=",1)[1].strip().strip('"').strip("'")
            except Exception:
                pass
            if token and chat:
                break
        if not (token and chat):
            return
    try:
        import urllib.request, urllib.parse
        urllib.request.urlopen(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=urllib.parse.urlencode({"chat_id": chat, "text": message}).encode(),
            timeout=5
        )
    except Exception:
        pass


def cmd_record(agent, fp_data):
    """Record a cycle fingerprint for an agent. Called by runner on each ARIC cycle."""
    state = load_state()
    agent_state = state.setdefault(agent, {
        "ring": [],
        "null_progress_count": 0,
        "last_state_hash": None,
        "warn_issued_at": None,
        "stop_issued_at": None,
        "last_updated": None
    })

    # Build fingerprint from provided data
    fp = fingerprint(
        agent,
        fp_data.get("weakness_id", "?"),
        fp_data.get("action_type", "?"),
        fp_data.get("content_hash", "")
    )

    # Build state hash
    sh = state_hash(
        agent,
        fp_data.get("weakness_id", "?"),
        fp_data.get("improvement_status", "?"),
        fp_data.get("files_changed", [])
    )

    # Update ring buffer
    ring = agent_state["ring"]
    ring.append(fp)
    if len(ring) > RING_SIZE:
        ring.pop(0)
    agent_state["ring"] = ring

    # Null progress tracking
    if sh == agent_state.get("last_state_hash"):
        agent_state["null_progress_count"] = agent_state.get("null_progress_count", 0) + 1
    else:
        agent_state["null_progress_count"] = 0
        agent_state["last_state_hash"] = sh

    agent_state["last_updated"] = datetime.now(timezone.utc).isoformat()
    state[agent] = agent_state
    save_state(state)

    # Check and return tier
    return cmd_check(agent, state)


def cmd_check(agent, state=None):
    """Check current state and return: OK | WARN | HARD_STOP | ESCALATE_HUMAN"""
    if state is None:
        state = load_state()
    agent_state = state.get(agent, {})

    ring = agent_state.get("ring", [])
    null_progress = agent_state.get("null_progress_count", 0)

    if not ring:
        return "OK"

    # Count most frequent fingerprint
    max_fp_count = max(ring.count(fp) for fp in set(ring))

    # Three-step repeating pattern in 6-step ring
    if len(ring) == 6:
        if ring[:3] == ring[3:]:
            max_fp_count = max(max_fp_count, 3)

    if null_progress >= NULL_PROGRESS:
        return "ESCALATE_HUMAN"
    elif max_fp_count >= STOP_COUNT:
        return "HARD_STOP"
    elif max_fp_count >= WARN_COUNT:
        return "WARN"

    return "OK"


def cmd_reset(agent):
    """Clear dead-loop state after genuine progress (new commit, new weakness, etc.)"""
    state = load_state()
    if agent in state:
        state[agent] = {
            "ring": [],
            "null_progress_count": 0,
            "last_state_hash": None,
            "warn_issued_at": None,
            "stop_issued_at": None,
            "last_updated": datetime.now(timezone.utc).isoformat()
        }
        save_state(state)
    print(f"[dead-loop] {agent}: state cleared — progress acknowledged")


def cmd_status():
    """Print all agents' dead-loop status."""
    state = load_state()
    if not state:
        print("[dead-loop] No state recorded yet.")
        return

    print("[dead-loop] Agent status summary:")
    for agent, agent_state in sorted(state.items()):
        ring = agent_state.get("ring", [])
        null_count = agent_state.get("null_progress_count", 0)
        last_updated = agent_state.get("last_updated", "never")
        if ring:
            max_fp = max(ring.count(fp) for fp in set(ring))
        else:
            max_fp = 0

        tier = cmd_check(agent, state)
        tier_icon = {"OK": "✓", "WARN": "⚠️", "HARD_STOP": "🛑", "ESCALATE_HUMAN": "🚨"}.get(tier, "?")
        print(f"  {tier_icon} {agent}: ring={len(ring)}/{RING_SIZE} max_fp={max_fp} null_progress={null_count} tier={tier} last={last_updated}")


def run_with_response(agent, fp_json_str):
    """Record + check, then output the appropriate response for runner to consume."""
    try:
        fp_data = json.loads(fp_json_str)
    except json.JSONDecodeError as e:
        print(f"[dead-loop] ERROR: invalid fingerprint JSON: {e}", file=sys.stderr)
        sys.exit(1)

    tier = cmd_record(agent, fp_data)

    if tier == "OK":
        print(f"[dead-loop] {agent}: OK — no loop detected")
        sys.exit(0)

    elif tier == "WARN":
        msg = (
            f"[dead-loop] WARN: {agent} is showing repeated cycle pattern "
            f"(same weakness/action {WARN_COUNT}+ cycles). "
            f"Probe: What information is missing that would change the assessment? "
            f"What external signal would confirm or refute the current plan?"
        )
        print(msg)
        log_session_error(agent, f"WARN: {WARN_COUNT}+ identical fingerprints in ring buffer", "P2")
        sys.exit(2)  # Runner should inject probe question into agent context

    elif tier == "HARD_STOP":
        msg = (
            f"[dead-loop] HARD STOP: {agent} has {STOP_COUNT}+ identical fingerprints — "
            f"cognitive entrenchment detected. Stripping tool calls. "
            f"Agent must produce a text summary of what it knows and what it is missing "
            f"before any further tool use is permitted."
        )
        print(msg)
        alert = (
            f"🛑 DEAD LOOP — {agent}\n"
            f"Same cycle fingerprint appeared {STOP_COUNT}+ times.\n"
            f"Agent is reflecting itself deeper into the same wrong pattern.\n"
            f"Action required: manual review of agents/{agent}/research/ — check for diversity in recent findings.\n"
            f"Auto-action: tool use stripped, probe injected."
        )
        alert_hyo_inbox(agent, alert, "P1")
        send_telegram(alert)
        log_session_error(agent, f"HARD STOP: {STOP_COUNT}+ identical fingerprints — cognitive entrenchment", "P1")
        sys.exit(3)  # Runner should strip tool_calls, force text summary

    elif tier == "ESCALATE_HUMAN":
        msg = (
            f"[dead-loop] ESCALATE: {agent} has had {NULL_PROGRESS}+ cycles with zero state change. "
            f"Real state is not advancing despite reported activity. "
            f"Escalating to Hyo inbox + Telegram."
        )
        print(msg)
        alert = (
            f"🚨 AGENT STALLED — {agent}\n"
            f"{NULL_PROGRESS}+ consecutive cycles with no actual state change.\n"
            f"This is the null-progress signal (not just repeated fingerprints).\n"
            f"Possible causes: broken tool, auth expired, empty data source, reasoning loop.\n"
            f"Check: agents/{agent}/research/aric-latest.json for last actual change."
        )
        alert_hyo_inbox(agent, alert, "P0")
        send_telegram(alert)
        log_session_error(agent, f"ESCALATE: {NULL_PROGRESS}+ null-progress cycles", "P0")
        sys.exit(4)  # Runner should halt and escalate


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: dead-loop-detector.py [check|record|reset|status] [agent] [json]")
        sys.exit(1)

    command = sys.argv[1]

    if command == "status":
        cmd_status()

    elif command == "check":
        agent = sys.argv[2] if len(sys.argv) > 2 else "unknown"
        tier = cmd_check(agent)
        tier_icon = {"OK": "✓", "WARN": "⚠️", "HARD_STOP": "🛑", "ESCALATE_HUMAN": "🚨"}.get(tier, "?")
        print(f"[dead-loop] {tier_icon} {agent}: {tier}")
        exit_codes = {"OK": 0, "WARN": 2, "HARD_STOP": 3, "ESCALATE_HUMAN": 4}
        sys.exit(exit_codes.get(tier, 0))

    elif command == "record":
        agent = sys.argv[2] if len(sys.argv) > 2 else "unknown"
        fp_json = sys.argv[3] if len(sys.argv) > 3 else "{}"
        run_with_response(agent, fp_json)

    elif command == "reset":
        agent = sys.argv[2] if len(sys.argv) > 2 else "unknown"
        cmd_reset(agent)

    else:
        print(f"Unknown command: {command}")
        sys.exit(1)
