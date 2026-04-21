#!/usr/bin/env python3
"""
agents/dex/dex-dedup.py — Dex W3 Phase 1: Known False-Positive Auto-Resolver

Dex W1 fix loop: even after repair + clustering, 162+ recurrent detections
flood the ledger — same security folder flag every 6h, same 401 API error
every cycle. These are KNOWN false positives (or resolved issues being re-flagged).

This script:
  1. Loads a known-false-positives registry (dex/known-fps.json)
  2. Scans ledger JSONL files for matching patterns
  3. Marks matching open issues as 'resolved_fp' with reason
  4. Writes a dedup report
  5. Prunes resolved_fp entries older than 30d from the active ledger

Shipped: 2026-04-21 | Protocol: agents/dex/GROWTH.md W3

USAGE:
  python3 agents/dex/dex-dedup.py                 # run dedup
  python3 agents/dex/dex-dedup.py --dry-run       # preview only
  python3 agents/dex/dex-dedup.py --add-fp <pattern> <reason>   # register new FP

EXIT:
  0 — clean (nothing to dedup)
  1 — deduped N entries (informational, not an error)
"""

from __future__ import annotations
import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", str(Path.home() / "Documents" / "Projects" / "Hyo")))
KNOWN_FPS_FILE = ROOT / "agents" / "dex" / "known-fps.json"
DEDUP_LOG = ROOT / "agents" / "dex" / "ledger" / "dedup-log.jsonl"

# Ledger files to scan for false positives
TARGET_FILES = [
    "kai/ledger/known-issues.jsonl",
    "agents/nel/ledger/log.jsonl",
]

NOW = datetime.datetime.now(datetime.timezone.utc)
NOW_ISO = NOW.isoformat()
TODAY = NOW.strftime("%Y-%m-%d")

# ── Default known false positives ────────────────────────────────────────────
# These patterns are known to fire repeatedly but represent resolved or
# intentional states. Each entry has:
#   pattern: regex matching description/event/message fields
#   reason:  why this is a false positive
#   max_age_days: only auto-resolve entries older than this (0 = always)
DEFAULT_FPS: list[dict] = [
    {
        "id": "FP-001",
        "pattern": r"security.*\.secrets|\.secrets.*security|nel/security",
        "reason": "agents/nel/security/ is the designated secrets directory. "
                  "Flagging it as a vulnerability is expected behavior from "
                  "directory scanners — the contents are gitignored and mode 700/600.",
        "max_age_days": 0,
        "severity_cap": "P3",  # Only auto-resolve if severity <= P3
    },
    {
        "id": "FP-002",
        "pattern": r"401.*api|api.*401|unauthorized.*hyo\.world|hyo\.world.*unauthorized",
        "reason": "401 from HQ API with no founder token is expected in unauthenticated "
                  "health checks. Token is configured in Vercel env — not a real failure.",
        "max_age_days": 0,
        "severity_cap": "P2",
    },
    {
        "id": "FP-003",
        "pattern": r"pip.audit.*not installed|pip-audit.*not.*install",
        "reason": "pip-audit is not installed in the sandbox. Python dependency "
                  "auditing falls back to listing packages — expected behavior in sandbox.",
        "max_age_days": 0,
        "severity_cap": "P3",
    },
    {
        "id": "FP-004",
        "pattern": r"bore\.pub.*refus|ssh.*bore.*fail|tunnel.*down",
        "reason": "bore.pub tunnel is intermittent (P0 in KAI_TASKS S18-013). "
                  "Flagging this every cycle is noise — it has its own P0 ticket.",
        "max_age_days": 0,
        "severity_cap": "P2",
    },
    {
        "id": "FP-005",
        "pattern": r"aurora.*no.*output|aurora.*not.*running|aurora.*log.*missing",
        "reason": "Aurora runner was consolidated into Ra. aurora.hyo.json manifest "
                  "is legacy. SENT-002 NOTED in KAI_TASKS.",
        "max_age_days": 0,
        "severity_cap": "P3",
    },
]


def load_known_fps() -> list[dict]:
    """Load known FP registry, merging defaults with any user additions."""
    fps = list(DEFAULT_FPS)
    if KNOWN_FPS_FILE.exists():
        try:
            with open(KNOWN_FPS_FILE) as f:
                user_fps = json.load(f)
            # User FPs override defaults by id
            default_ids = {fp["id"] for fp in fps}
            for ufp in user_fps:
                if ufp.get("id") not in default_ids:
                    fps.append(ufp)
        except (json.JSONDecodeError, OSError) as e:
            print(f"  ⚠ Could not load {KNOWN_FPS_FILE}: {e}", file=sys.stderr)
    return fps


def save_known_fps(fps: list[dict]) -> None:
    KNOWN_FPS_FILE.parent.mkdir(parents=True, exist_ok=True)
    # Save only non-default FPs (defaults are baked in)
    default_ids = {fp["id"] for fp in DEFAULT_FPS}
    user_fps = [fp for fp in fps if fp.get("id") not in default_ids]
    with open(KNOWN_FPS_FILE, "w") as f:
        json.dump(user_fps, f, indent=2)
    print(f"  Saved {len(user_fps)} user FP(s) to {KNOWN_FPS_FILE}")


def severity_rank(sev: str) -> int:
    """Lower = more severe."""
    return {"P0": 0, "P1": 1, "P2": 2, "P3": 3, "P4": 4}.get(str(sev).upper(), 99)


def matches_fp(record: dict, fp: dict) -> bool:
    """Check if a record matches a known false positive pattern."""
    pattern = fp.get("pattern", "")
    if not pattern:
        return False

    # Check text fields
    text = " ".join([
        str(record.get("description", "")),
        str(record.get("event", "")),
        str(record.get("message", "")),
        str(record.get("title", "")),
        str(record.get("error", "")),
    ]).lower()

    if not re.search(pattern, text, re.IGNORECASE):
        return False

    # Check age constraint
    max_age = fp.get("max_age_days", 0)
    if max_age > 0:
        ts_str = record.get("ts") or record.get("timestamp")
        if ts_str:
            try:
                ts = datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                age_days = (NOW - ts).days
                if age_days < max_age:
                    return False  # Too recent to auto-resolve
            except ValueError:
                pass

    # Check severity constraint
    severity_cap = fp.get("severity_cap", "P3")
    record_sev = record.get("severity", "P3")
    if severity_rank(record_sev) < severity_rank(severity_cap):
        return False  # Too severe to auto-resolve

    # Only auto-resolve open/active issues
    status = str(record.get("status", "open")).lower()
    if status in ("resolved", "resolved_fp", "closed", "done"):
        return False

    return True


def process_file(path: Path, known_fps: list[dict], dry_run: bool) -> dict:
    """Process a single JSONL file, marking false positive entries."""
    result = {
        "file": str(path.relative_to(ROOT)),
        "ts": NOW_ISO,
        "lines_read": 0,
        "matched_fps": 0,
        "lines_written": 0,
        "status": "ok",
        "matches": [],
    }

    if not path.exists():
        result["status"] = "skipped"
        return result

    records = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    records.append({"_raw": line, "_parse_error": True})
    except OSError as e:
        result["status"] = f"read_error: {e}"
        return result

    result["lines_read"] = len(records)
    modified = False

    for rec in records:
        if rec.get("_parse_error"):
            continue
        for fp in known_fps:
            if matches_fp(rec, fp):
                result["matched_fps"] += 1
                result["matches"].append({
                    "fp_id": fp["id"],
                    "description": str(rec.get("description", rec.get("event", "")))[:80],
                    "original_status": rec.get("status", "open"),
                    "severity": rec.get("severity", "unknown"),
                })
                if not dry_run:
                    rec["status"] = "resolved_fp"
                    rec["resolved_fp_id"] = fp["id"]
                    rec["resolved_fp_reason"] = fp["reason"][:120]
                    rec["resolved_fp_at"] = NOW_ISO
                modified = True
                break  # Only apply first matching FP

    result["lines_written"] = len(records)

    if modified and not dry_run:
        try:
            backup = path.with_suffix(".jsonl.fp-bak")
            import shutil
            shutil.copy2(path, backup)
            with open(path, "w") as f:
                for rec in records:
                    if not rec.get("_parse_error"):
                        f.write(json.dumps(rec) + "\n")
                    else:
                        f.write(rec["_raw"] + "\n")
            result["status"] = "deduped"
        except OSError as e:
            result["status"] = f"write_error: {e}"
    elif result["matched_fps"] == 0:
        result["status"] = "clean"

    return result


def prune_old_resolved_fp(path: Path, days: int = 30, dry_run: bool = False) -> int:
    """Remove resolved_fp entries older than `days` days to keep ledgers lean."""
    if not path.exists():
        return 0
    cutoff = NOW - datetime.timedelta(days=days)
    records = []
    pruned = 0
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                    if rec.get("status") == "resolved_fp":
                        ts_str = rec.get("resolved_fp_at", rec.get("ts", ""))
                        if ts_str:
                            try:
                                ts = datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                                if ts < cutoff:
                                    pruned += 1
                                    continue
                            except ValueError:
                                pass
                    records.append(line)
                except json.JSONDecodeError:
                    records.append(line)
    except OSError:
        return 0

    if pruned > 0 and not dry_run:
        with open(path, "w") as f:
            for line in records:
                f.write(line + "\n")
    return pruned


def cmd_add_fp(pattern: str, reason: str, fps: list[dict]) -> None:
    """Register a new user-defined false positive."""
    existing_ids = [fp.get("id", "") for fp in fps]
    user_ids = [fp for fp in existing_ids if fp.startswith("UFP-")]
    next_num = len(user_ids) + 1
    new_fp = {
        "id": f"UFP-{next_num:03d}",
        "pattern": pattern,
        "reason": reason,
        "max_age_days": 0,
        "severity_cap": "P3",
        "added": TODAY,
    }
    fps.append(new_fp)
    save_known_fps(fps)
    print(f"  Registered {new_fp['id']}: {pattern[:60]}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Dex false-positive auto-resolver")
    ap.add_argument("--dry-run", action="store_true", help="Preview only, no writes")
    ap.add_argument("--add-fp", nargs=2, metavar=("PATTERN", "REASON"),
                    help="Register a new known false positive")
    ap.add_argument("--prune-days", type=int, default=30,
                    help="Prune resolved_fp entries older than N days (default 30)")
    ap.add_argument("--report", action="store_true", help="Output JSON summary")
    args = ap.parse_args()

    DEDUP_LOG.parent.mkdir(parents=True, exist_ok=True)

    fps = load_known_fps()

    print(f"=== Dex False-Positive Dedup — {TODAY} ===")
    print(f"  {len(fps)} known FP patterns loaded")
    if args.dry_run:
        print("  (DRY RUN — no files will be modified)")
    print()

    if args.add_fp:
        cmd_add_fp(args.add_fp[0], args.add_fp[1], fps)
        return 0

    files = [ROOT / f for f in TARGET_FILES]
    reports = []
    total_matched = 0
    total_pruned = 0

    for path in files:
        report = process_file(path, fps, dry_run=args.dry_run)
        reports.append(report)
        rel = report["file"]
        status = report["status"]
        matched = report["matched_fps"]

        if status == "clean":
            print(f"  ✓ {rel} — clean ({report['lines_read']} lines, 0 FPs)")
        elif status == "deduped":
            print(f"  ✔ {rel} — marked {matched} false positive(s):")
            for m in report["matches"][:5]:
                print(f"      [{m['fp_id']}] {m['description'][:60]}")
            if len(report["matches"]) > 5:
                print(f"      ... and {len(report['matches'])-5} more")
            total_matched += matched
        elif status == "skipped":
            print(f"  - {rel} — not found")
        else:
            print(f"  ~ {rel} — {status} ({matched} matched)")
            total_matched += matched

        # Prune old resolved_fp entries
        pruned = prune_old_resolved_fp(path, days=args.prune_days, dry_run=args.dry_run)
        if pruned > 0:
            total_pruned += pruned
            print(f"    → pruned {pruned} old resolved_fp entries (>{args.prune_days}d)")

        # Log to dedup ledger
        try:
            with open(DEDUP_LOG, "a") as f:
                f.write(json.dumps(report) + "\n")
        except OSError:
            pass

    print()
    print(f"=== Summary: {total_matched} FPs resolved, {total_pruned} old entries pruned ===")

    if args.report:
        summary = {
            "ts": NOW_ISO,
            "dry_run": args.dry_run,
            "fp_patterns_loaded": len(fps),
            "files_scanned": len(files),
            "total_fps_resolved": total_matched,
            "total_entries_pruned": total_pruned,
            "reports": reports,
        }
        print()
        print(json.dumps(summary, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
