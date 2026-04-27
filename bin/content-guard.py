#!/usr/bin/env python3
"""
bin/content-guard.py — Content Regression Guard

ARCHITECTURE: Based on content-regression circuit breaker pattern.
Prevents agent runners from committing output that is catastrophically
smaller than the previous artifact — a signal that a gather/synthesize
step silently failed and is about to overwrite good content with empty output.

WHAT IT DOES:
  Compares the proposed new content file (or byte count) against the
  prior version. If the ratio of new_bytes / prior_bytes falls below
  the threshold (default 0.10), it blocks the commit and alerts Hyo.

  Three thresholds:
    BLOCK   (ratio < 0.10): Hard block — new file is < 10% of prior
    WARN    (ratio < 0.30): Soft warn  — new file is < 30% of prior
    OK      (ratio >= 0.30): Content looks healthy

USAGE:
  python3 bin/content-guard.py check <filepath> [--prior <prior_filepath>]
    → compare current file vs prior (or prior version via git HEAD)

  python3 bin/content-guard.py check-bytes <new_bytes> <prior_bytes>
    → raw byte count comparison (for scripts that have the data in memory)

  python3 bin/content-guard.py record <filepath>
    → save current content baseline (call AFTER a verified successful publish)

EXIT CODES:
  0 = OK (safe to commit)
  1 = ERROR (file not found, etc.)
  2 = WARN (commit with caution — surfaced in logs but not blocked)
  3 = BLOCK (hard block — do not commit, alert dispatched)

CALLED BY:
  - newsletter.sh before git commit of feed.json
  - podcast.py before committing script + audio
  - generate-morning-report.sh before publishing morning report
  - Any agent runner that overwrites a data file

VERSION: 1.0 — 2026-04-27
SOURCES:
  - Content regression pattern (SE-030 post-mortem)
  - arXiv:2512.02731 (GVU — variance inequality, signal vs. noise in self-verification)
  - Reflexion (NeurIPS 2023) — evaluator must be independent from generator
  - TokenFence.dev circuit breaker pattern
"""

import json
import sys
import os
import subprocess
import time
from pathlib import Path
from datetime import datetime, timezone

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
BASELINE_FILE = os.path.join(ROOT, "kai/ledger/content-guard-baselines.json")
SESSION_ERRORS = os.path.join(ROOT, "kai/ledger/session-errors.jsonl")
HYO_INBOX = os.path.join(ROOT, "kai/ledger/hyo-inbox.jsonl")

BLOCK_RATIO = 0.10   # < 10% of prior → hard block
WARN_RATIO  = 0.30   # < 30% of prior → warn
MIN_PRIOR_BYTES = 100  # below this, no comparison (first write)


def load_baselines():
    try:
        with open(BASELINE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_baselines(baselines):
    Path(BASELINE_FILE).parent.mkdir(parents=True, exist_ok=True)
    with open(BASELINE_FILE, "w") as f:
        json.dump(baselines, f, indent=2)


def get_git_prior_bytes(filepath):
    """Get byte count of filepath from git HEAD (last committed version)."""
    try:
        abs_path = os.path.abspath(filepath)
        git_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=os.path.dirname(abs_path),
            stderr=subprocess.DEVNULL
        ).decode().strip()
        rel_path = os.path.relpath(abs_path, git_root)
        content = subprocess.check_output(
            ["git", "show", f"HEAD:{rel_path}"],
            cwd=git_root,
            stderr=subprocess.DEVNULL
        )
        return len(content)
    except Exception:
        return None


def log_session_error(filepath, description, severity="P1"):
    entry = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "category": "content_regression",
        "file": str(filepath),
        "description": description,
        "severity": severity,
        "prevention": "content-guard.py circuit breaker — auto-detected"
    }
    try:
        with open(SESSION_ERRORS, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def alert_hyo_inbox(filepath, message, severity="P1"):
    entry = {
        "id": f"content-guard-{int(time.time())}",
        "ts": datetime.now(timezone.utc).isoformat(),
        "from": "content-guard",
        "severity": severity,
        "subject": f"CONTENT REGRESSION BLOCKED: {os.path.basename(filepath)}",
        "body": message,
        "status": "unread"
    }
    try:
        Path(HYO_INBOX).parent.mkdir(parents=True, exist_ok=True)
        with open(HYO_INBOX, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception:
        pass


def send_telegram(message):
    """Best-effort Telegram alert."""
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat = os.environ.get("TELEGRAM_CHAT_ID", "")
    if not (token and chat):
        env_path = os.path.join(ROOT, "agents/nel/security/.telegram_token")
        try:
            token = Path(env_path).read_text().strip()
            chat_path = os.path.join(ROOT, "agents/nel/security/.telegram_chat_id")
            chat = Path(chat_path).read_text().strip()
        except Exception:
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


def evaluate_ratio(new_bytes, prior_bytes, filepath, source_label):
    """Core evaluation logic. Returns exit code and prints verdict."""
    if prior_bytes < MIN_PRIOR_BYTES:
        print(f"[content-guard] OK: {filepath} — first write or prior too small ({prior_bytes}B), skipping comparison")
        return 0

    ratio = new_bytes / prior_bytes
    ratio_pct = round(ratio * 100, 1)

    if ratio < BLOCK_RATIO:
        msg = (
            f"[content-guard] BLOCK: {filepath}\n"
            f"  New: {new_bytes}B  Prior ({source_label}): {prior_bytes}B  Ratio: {ratio_pct}%\n"
            f"  Threshold: {int(BLOCK_RATIO*100)}% — this is a content regression.\n"
            f"  The gather/synthesize step likely silently failed.\n"
            f"  DO NOT COMMIT. Investigate before overwriting prior content."
        )
        print(msg)
        alert_body = (
            f"⛔ CONTENT REGRESSION BLOCKED\n"
            f"File: {filepath}\n"
            f"New size: {new_bytes}B | Prior size: {prior_bytes}B | Ratio: {ratio_pct}%\n"
            f"Gate threshold: {int(BLOCK_RATIO*100)}%\n"
            f"Cause: gather/synthesize likely failed silently.\n"
            f"Action: check agent runner logs, re-run gather step."
        )
        alert_hyo_inbox(filepath, alert_body, "P1")
        send_telegram(alert_body)
        log_session_error(filepath, f"BLOCK: {ratio_pct}% of prior ({prior_bytes}B) — new={new_bytes}B", "P1")
        return 3  # BLOCK

    elif ratio < WARN_RATIO:
        msg = (
            f"[content-guard] WARN: {filepath}\n"
            f"  New: {new_bytes}B  Prior ({source_label}): {prior_bytes}B  Ratio: {ratio_pct}%\n"
            f"  Below {int(WARN_RATIO*100)}% threshold — content shrank significantly.\n"
            f"  Committing, but flagging for review."
        )
        print(msg)
        log_session_error(filepath, f"WARN: {ratio_pct}% of prior ({prior_bytes}B) — new={new_bytes}B", "P2")
        return 2  # WARN

    else:
        print(
            f"[content-guard] OK: {filepath}\n"
            f"  New: {new_bytes}B  Prior ({source_label}): {prior_bytes}B  Ratio: {ratio_pct}% ✓"
        )
        return 0  # OK


def cmd_check(filepath, prior_filepath=None):
    """Check a file against its prior version."""
    if not os.path.exists(filepath):
        print(f"[content-guard] ERROR: file not found: {filepath}", file=sys.stderr)
        return 1

    new_bytes = os.path.getsize(filepath)

    # Determine prior bytes
    prior_bytes = None
    source_label = "unknown"

    # 1. Explicit prior file
    if prior_filepath and os.path.exists(prior_filepath):
        prior_bytes = os.path.getsize(prior_filepath)
        source_label = f"prior:{os.path.basename(prior_filepath)}"

    # 2. Saved baseline
    if prior_bytes is None:
        baselines = load_baselines()
        key = os.path.abspath(filepath)
        if key in baselines:
            prior_bytes = baselines[key].get("bytes", 0)
            source_label = f"baseline:{baselines[key].get('recorded_at', '?')[:10]}"

    # 3. Git HEAD
    if prior_bytes is None:
        git_bytes = get_git_prior_bytes(filepath)
        if git_bytes is not None:
            prior_bytes = git_bytes
            source_label = "git:HEAD"

    if prior_bytes is None:
        print(f"[content-guard] OK: {filepath} — no prior found, skipping (first write)")
        return 0

    return evaluate_ratio(new_bytes, prior_bytes, filepath, source_label)


def cmd_check_bytes(new_bytes, prior_bytes, label="<stream>"):
    """Check raw byte counts (for callers that have content in memory)."""
    try:
        new_bytes = int(new_bytes)
        prior_bytes = int(prior_bytes)
    except ValueError:
        print(f"[content-guard] ERROR: invalid byte counts: {new_bytes}, {prior_bytes}", file=sys.stderr)
        return 1
    return evaluate_ratio(new_bytes, prior_bytes, label, "provided")


def cmd_record(filepath):
    """Save current file as the new baseline (call after verified successful publish)."""
    if not os.path.exists(filepath):
        print(f"[content-guard] ERROR: cannot record baseline — file not found: {filepath}", file=sys.stderr)
        return 1
    baselines = load_baselines()
    key = os.path.abspath(filepath)
    size = os.path.getsize(filepath)
    baselines[key] = {
        "path": filepath,
        "bytes": size,
        "recorded_at": datetime.now(timezone.utc).isoformat()
    }
    save_baselines(baselines)
    print(f"[content-guard] RECORDED: {filepath} → {size}B baseline saved")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: content-guard.py [check|check-bytes|record] [args...]")
        print("  check <filepath> [--prior <prior_filepath>]")
        print("  check-bytes <new_bytes> <prior_bytes> [label]")
        print("  record <filepath>")
        sys.exit(1)

    command = sys.argv[1]

    if command == "check":
        filepath = sys.argv[2] if len(sys.argv) > 2 else None
        if not filepath:
            print("Usage: content-guard.py check <filepath>", file=sys.stderr)
            sys.exit(1)
        prior = None
        if "--prior" in sys.argv:
            idx = sys.argv.index("--prior")
            prior = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None
        sys.exit(cmd_check(filepath, prior))

    elif command == "check-bytes":
        new_b = sys.argv[2] if len(sys.argv) > 2 else "0"
        prior_b = sys.argv[3] if len(sys.argv) > 3 else "0"
        label = sys.argv[4] if len(sys.argv) > 4 else "<stream>"
        sys.exit(cmd_check_bytes(new_b, prior_b, label))

    elif command == "record":
        filepath = sys.argv[2] if len(sys.argv) > 2 else None
        if not filepath:
            print("Usage: content-guard.py record <filepath>", file=sys.stderr)
            sys.exit(1)
        sys.exit(cmd_record(filepath))

    else:
        print(f"Unknown command: {command}", file=sys.stderr)
        sys.exit(1)
