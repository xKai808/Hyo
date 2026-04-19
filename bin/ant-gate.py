#!/usr/bin/env python3
"""
ant-gate.py — Ant Quality Gate (hard block)
============================================
Called by ant-update.sh after Python data generation.
Runs 5 gates against ant-data.json. Exits 0 on pass, exits 1 on fail.

When gate fails: sends Telegram alert AND exits 1 so ant-update.sh
aborts the commit and does not push broken data to HQ.

Usage:
    python3 bin/ant-gate.py [--ant-file PATH]

Called by ant-update.sh:
    python3 bin/ant-gate.py
    if [ $? -ne 0 ]; then
        exit 1   # abort commit
    fi
"""

import json
import os
import sys
import urllib.request
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ── Paths ─────────────────────────────────────────────────────────────────────
HYO_ROOT      = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
SECRETS_DIR   = os.path.join(HYO_ROOT, "agents/nel/security")
ANT_FILE      = os.environ.get("ANT_OUT_FILE",
                    os.path.join(HYO_ROOT, "agents/sam/website/data/ant-data.json"))
ANT_FILE2     = os.environ.get("ANT_OUT_FILE2",
                    os.path.join(HYO_ROOT, "website/data/ant-data.json"))

# ── Telegram ──────────────────────────────────────────────────────────────────

def _load_telegram_creds() -> tuple[str, str]:
    token   = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    if token and chat_id:
        return token, chat_id
    for env_path in [
        os.path.join(SECRETS_DIR, "env"),
        os.path.expanduser("~/Documents/Projects/Kai/.env"),
    ]:
        if not os.path.exists(env_path):
            continue
        try:
            with open(env_path) as f:
                for line in f:
                    line = line.strip()
                    if "=" not in line or line.startswith("#"):
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip(); v = v.strip()
                    if k == "TELEGRAM_BOT_TOKEN" and not token:
                        token = v
                    elif k == "TELEGRAM_CHAT_ID" and not chat_id:
                        chat_id = v
        except Exception:
            pass
        if token and chat_id:
            break
    return token, chat_id


def send_telegram_alert(msg: str):
    """Non-blocking Telegram alert. Failure is printed, not raised."""
    try:
        token, chat_id = _load_telegram_creds()
        if not token or not chat_id:
            print("[ant-gate] WARN: Telegram creds not found — alert not sent")
            return
        payload = json.dumps({"chat_id": chat_id, "text": f"[ANT GATE FAIL] {msg}"}).encode()
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            if result.get("ok"):
                print(f"[ant-gate] Telegram alert sent")
            else:
                print(f"[ant-gate] Telegram alert error: {result}")
    except Exception as e:
        print(f"[ant-gate] WARN: Telegram send failed: {e}")


# ── Gate logic ────────────────────────────────────────────────────────────────

def run_gates(ant_file: str, ant_file2: str) -> list[str]:
    """
    Run 5 gates. Returns list of failure strings.
    Empty list = PASS.

    Gates:
    1. Credits not null — remaining/total must be present for both providers
    2. History not empty — 14-day history array must have entries
    3. Freshness — updatedAt must be within the last 60 minutes
    4. Dual-path sync — both ant-data.json files must exist and have same content length
    5. History populated — each history entry must have at least one non-zero provider value
    """
    failures = []

    # ── Load primary file ──────────────────────────────────────────────────────
    try:
        with open(ant_file) as f:
            data = json.load(f)
    except FileNotFoundError:
        return [f"GATE-1: cannot read {ant_file} — file does not exist"]
    except json.JSONDecodeError as e:
        return [f"GATE-1: {ant_file} is not valid JSON: {e}"]

    credits = data.get("credits", {})

    # ── Gate 1: Credits not null ───────────────────────────────────────────────
    for provider in ("anthropic", "openai"):
        pdata = credits.get(provider, {})
        remaining = pdata.get("remaining")
        total     = pdata.get("total")
        if remaining is None:
            failures.append(
                f"GATE-1: credits.{provider}.remaining is null — "
                f"real scrape missing and budget fallback failed. Run 'kai ant-scrape'."
            )
        if total is None:
            failures.append(
                f"GATE-1: credits.{provider}.total is null"
            )

    # ── Gate 2: History not empty ──────────────────────────────────────────────
    history = data.get("history", [])
    if not history:
        failures.append(
            "GATE-2: history[] is empty — daily chart will be blank. "
            "Check api-usage.jsonl has at least one valid record."
        )

    # ── Gate 3: Freshness ─────────────────────────────────────────────────────
    updated_at = data.get("updatedAt", "")
    if updated_at:
        try:
            dt = datetime.fromisoformat(updated_at).astimezone(timezone.utc)
            age_h = (datetime.now(timezone.utc) - dt).total_seconds() / 3600
            if age_h > 1.0:
                failures.append(
                    f"GATE-3: updatedAt is {age_h:.1f}h old — "
                    f"ant-update.sh may have crashed before writing the file"
                )
        except Exception as e:
            failures.append(f"GATE-3: cannot parse updatedAt '{updated_at}': {e}")
    else:
        failures.append("GATE-3: updatedAt field missing from ant-data.json")

    # ── Gate 4: Dual-path sync ────────────────────────────────────────────────
    if not os.path.exists(ant_file2):
        failures.append(
            f"GATE-4: mirror file missing: {ant_file2} — "
            f"dual-path write failed. HQ Vercel mirror will serve stale data."
        )
    else:
        size1 = os.path.getsize(ant_file)
        size2 = os.path.getsize(ant_file2)
        if abs(size1 - size2) > 10:  # tolerate tiny whitespace diff
            failures.append(
                f"GATE-4: dual-path size mismatch: primary={size1}B mirror={size2}B — "
                f"files may have diverged"
            )

    # ── Gate 5: History populated ─────────────────────────────────────────────
    if history:
        non_zero_days = sum(
            1 for h in history
            if h.get("anthropic", 0) > 0 or h.get("openai", 0) > 0
        )
        if non_zero_days == 0:
            failures.append(
                "GATE-5: history[] has entries but all values are zero — "
                "api-usage.jsonl records may have wrong date format or zero costs"
            )

    return failures


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Ant quality gate — hard block")
    parser.add_argument("--ant-file", default=ANT_FILE, help="Path to ant-data.json")
    parser.add_argument("--ant-file2", default=ANT_FILE2, help="Path to mirror ant-data.json")
    args = parser.parse_args()

    print(f"[ant-gate] Running 5 gates on {args.ant_file}")

    failures = run_gates(args.ant_file, args.ant_file2)

    if not failures:
        print("[ant-gate] GATE PASS — all 5 gates cleared")
        sys.exit(0)

    # ── Failures ───────────────────────────────────────────────────────────────
    print(f"[ant-gate] GATE FAIL — {len(failures)} failure(s):")
    for f in failures:
        print(f"  ✗ {f}")

    alert_body = "\n".join(failures)
    send_telegram_alert(f"{len(failures)} gate failure(s):\n{alert_body}")

    sys.exit(1)


if __name__ == "__main__":
    main()
