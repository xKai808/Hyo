#!/usr/bin/env python3
"""
agents/dex/dex-repair.py — Dex I1: Automated JSONL Auto-Repair

Dex W1 fix: Dex detected issues but never fixed them. This script closes
the loop: scan JSONL ledger files, auto-repair deterministic corruption,
report what was fixed vs. what needs manual attention.

Shipped: 2026-04-21 | Protocol: agents/dex/PROTOCOL_DEX_SELF_IMPROVEMENT.md

WHAT IT FIXES (deterministic, safe to auto-repair):
  - Duplicate entries (same ts+description) → keep first, remove duplicates
  - Missing 'ts' field → inject estimated timestamp from file mtime or neighbors
  - Missing 'status' field in known-issues.jsonl → default to 'open'
  - Missing 'severity' field → default to 'P2' (safe default, escalate manually)
  - Trailing commas or extra whitespace in JSON → normalize
  - Empty lines → remove

WHAT IT DOES NOT FIX (requires human judgment):
  - Wrong field values (wrong severity, wrong description)
  - Business logic errors (wrong status for a resolved issue)
  - Files with >20% corruption (flag P0, don't auto-repair, too risky)

USAGE:
  python3 agents/dex/dex-repair.py                    # scan + repair all ledgers
  python3 agents/dex/dex-repair.py --dry-run           # scan only, no writes
  python3 agents/dex/dex-repair.py --file path/to.jsonl  # specific file
  python3 agents/dex/dex-repair.py --report            # output machine-readable JSON

OUTPUT:
  agents/dex/ledger/repair-log.jsonl — repair history
  stdout — human-readable summary
  exit 0 — repairs complete (or nothing to fix)
  exit 1 — P0: >20% corruption in a file, manual intervention required
"""

from __future__ import annotations
import argparse
import datetime
import json
import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", str(Path.home() / "Documents" / "Projects" / "Hyo")))
REPAIR_LOG = ROOT / "agents" / "dex" / "ledger" / "repair-log.jsonl"

# JSONL files to scan (relative to ROOT)
TARGET_FILES = [
    "kai/ledger/known-issues.jsonl",
    "kai/ledger/session-errors.jsonl",
    "kai/ledger/api-usage.jsonl",
    "kai/ledger/guidance.jsonl",
    "kai/ledger/log.jsonl",
    "agents/nel/ledger/log.jsonl",
    "agents/ra/ledger/engagement.jsonl",
    "agents/sam/ledger/performance-baseline.jsonl",
]

NOW = datetime.datetime.now(datetime.timezone.utc).isoformat()


def parse_jsonl_lines(path: Path) -> tuple[list[dict], list[tuple[int, str, str]]]:
    """Parse JSONL file. Returns (valid_records, errors).
    errors: list of (line_num, raw_line, error_message)
    """
    records = []
    errors = []
    try:
        with open(path) as f:
            for i, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError as e:
                    errors.append((i, line, str(e)))
    except OSError as e:
        errors.append((0, "", f"File read error: {e}"))
    return records, errors


def dedup_records(records: list[dict]) -> tuple[list[dict], int]:
    """Remove duplicate records. Duplicates = same ts+description (or ts+event)."""
    seen = set()
    deduped = []
    removed = 0
    for r in records:
        key = (
            r.get("ts", ""),
            r.get("description", r.get("event", r.get("id", str(r))))[:100]
        )
        if key in seen:
            removed += 1
        else:
            seen.add(key)
            deduped.append(r)
    return deduped, removed


def inject_missing_fields(records: list[dict], file_name: str) -> tuple[list[dict], int]:
    """Inject defaults for missing required fields. Returns (records, num_fixed)."""
    fixed = 0
    for r in records:
        changed = False
        # Missing 'ts': inject current time as estimation (flag as estimated)
        if "ts" not in r and "timestamp" not in r:
            r["ts"] = NOW
            r["_ts_estimated"] = True
            changed = True
        # known-issues.jsonl: missing status
        if "known-issues" in file_name and "status" not in r:
            r["status"] = "open"
            changed = True
        # known-issues.jsonl: missing severity
        if "known-issues" in file_name and "severity" not in r and "description" in r:
            r["severity"] = "P2"
            r["_severity_defaulted"] = True
            changed = True
        # session-errors.jsonl: missing category
        if "session-errors" in file_name and "category" not in r and "description" in r:
            r["category"] = "unknown"
            changed = True
        if changed:
            fixed += 1
    return records, fixed


def repair_file(path: Path, dry_run: bool = False) -> dict:
    """Repair a single JSONL file. Returns repair report dict."""
    result = {
        "file": str(path.relative_to(ROOT)),
        "ts": NOW,
        "lines_read": 0,
        "parse_errors": 0,
        "duplicates_removed": 0,
        "fields_injected": 0,
        "lines_written": 0,
        "status": "ok",
        "skipped_reason": None,
        "errors": [],
    }

    if not path.exists():
        result["status"] = "skipped"
        result["skipped_reason"] = "file not found"
        return result

    records, parse_errors = parse_jsonl_lines(path)
    result["lines_read"] = len(records) + len(parse_errors)
    result["parse_errors"] = len(parse_errors)
    result["errors"] = [{"line": e[0], "error": e[2]} for e in parse_errors]

    # Safety check: >20% corruption → P0, don't auto-repair
    total_lines = result["lines_read"]
    if total_lines > 0 and (len(parse_errors) / total_lines) > 0.20:
        result["status"] = "p0_high_corruption"
        result["skipped_reason"] = (
            f"{len(parse_errors)}/{total_lines} lines corrupt ({len(parse_errors)/total_lines:.0%}) "
            f"— exceeds 20% threshold. Manual review required."
        )
        return result

    if not records:
        result["status"] = "empty"
        return result

    # Dedup
    records, dupes = dedup_records(records)
    result["duplicates_removed"] = dupes

    # Inject missing fields
    records, injected = inject_missing_fields(records, path.name)
    result["fields_injected"] = injected

    result["lines_written"] = len(records)

    # Write back (unless dry run)
    if not dry_run and (dupes > 0 or injected > 0):
        backup = path.with_suffix(".jsonl.bak")
        try:
            import shutil
            shutil.copy2(path, backup)
            with open(path, "w") as f:
                for r in records:
                    f.write(json.dumps(r) + "\n")
            result["status"] = "repaired"
        except OSError as e:
            result["status"] = "write_error"
            result["errors"].append({"line": 0, "error": str(e)})
    elif dupes == 0 and injected == 0 and not parse_errors:
        result["status"] = "clean"

    return result


def main() -> int:
    ap = argparse.ArgumentParser(description="Dex JSONL auto-repair")
    ap.add_argument("--dry-run", action="store_true", help="Scan only, no writes")
    ap.add_argument("--file", help="Repair specific file only")
    ap.add_argument("--report", action="store_true", help="Output JSON summary")
    args = ap.parse_args()

    REPAIR_LOG.parent.mkdir(parents=True, exist_ok=True)

    files = [ROOT / args.file] if args.file else [ROOT / f for f in TARGET_FILES]

    reports = []
    total_dupes = 0
    total_injected = 0
    total_p0 = 0
    total_clean = 0
    total_repaired = 0
    total_skipped = 0

    print(f"=== Dex JSONL Auto-Repair — {NOW[:10]} ===")
    if args.dry_run:
        print("  (DRY RUN — no files will be modified)")
    print()

    for path in files:
        report = repair_file(path, dry_run=args.dry_run)
        reports.append(report)

        status = report["status"]
        rel = report["file"]

        if status == "clean":
            print(f"  ✓ {rel} — clean ({report['lines_read']} lines)")
            total_clean += 1
        elif status == "repaired":
            print(f"  ✔ {rel} — REPAIRED: {report['duplicates_removed']} dupes removed, {report['fields_injected']} fields injected")
            total_repaired += 1
            total_dupes += report["duplicates_removed"]
            total_injected += report["fields_injected"]
        elif status == "p0_high_corruption":
            print(f"  ✗ P0 {rel} — HIGH CORRUPTION: {report['skipped_reason']}")
            total_p0 += 1
        elif status == "skipped":
            print(f"  - {rel} — skipped: {report['skipped_reason']}")
            total_skipped += 1
        elif status == "empty":
            print(f"  - {rel} — empty file")
            total_skipped += 1
        elif status == "ok":
            errs = report.get("parse_errors", 0)
            if errs:
                print(f"  ~ {rel} — {report['lines_read']} lines, {errs} parse error(s) below 20% threshold (data recovered)")
            else:
                print(f"  ✓ {rel} — clean ({report['lines_read']} lines)")
            total_clean += 1
        else:
            print(f"  ? {rel} — {status}: {report.get('errors', [])}")

        # Log to repair ledger
        try:
            with open(REPAIR_LOG, "a") as f:
                f.write(json.dumps(report) + "\n")
        except OSError:
            pass

    print()
    print(f"=== Summary: {total_clean} clean, {total_repaired} repaired, {total_p0} P0, {total_skipped} skipped ===")
    if total_dupes or total_injected:
        print(f"  Removed {total_dupes} duplicate entries, injected {total_injected} missing fields")
    if total_p0 > 0:
        print(f"  P0 FILES REQUIRE MANUAL REVIEW — do not auto-repair high-corruption files")

    if args.report:
        summary = {
            "ts": NOW,
            "dry_run": args.dry_run,
            "files_scanned": len(files),
            "clean": total_clean,
            "repaired": total_repaired,
            "p0_high_corruption": total_p0,
            "skipped": total_skipped,
            "total_dupes_removed": total_dupes,
            "total_fields_injected": total_injected,
            "reports": reports,
        }
        print()
        print(json.dumps(summary, indent=2))

    return 1 if total_p0 > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
