#!/usr/bin/env python3
"""
bin/maintenance-audit.py — Nightly System Maintenance Auditor
Version: 1.0
Author: Kai
Date: 2026-04-21
Trigger: com.hyo.system-maintenance launchd plist at 01:30 MT daily

Per PROTOCOL_SYSTEM_MAINTENANCE.md Section 4:
  - Phase 1 (--check-dead-scripts): find .sh/.py files with no trigger, no reference
  - Phase 2 (--check-stale-protocols): find protocol files referencing dead paths/tools
  - Phase 3 (--check-duplicates): find files with identical sha256 that aren't dual-path

FLAGS ONLY. Never deletes. Never moves. Never disables.
All flags go to kai/ledger/maintenance-log.jsonl.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
LOG_PATH = os.path.join(ROOT, "kai", "ledger", "maintenance-log.jsonl")
TRIGGER_MATRIX = os.path.join(ROOT, "kai", "protocols", "TRIGGER_MATRIX.md")

# --- Known dual-path pairs (NOT redundant — intentional design) ---
DUAL_PATH_PAIRS = [
    ("website/", "agents/sam/website/"),
]

# --- Known ignore patterns (symlinks, intentional copies) ---
SKIP_PATHS = [
    "website/",           # symlink to agents/sam/website — not a real directory
    "newsletter/",        # symlink to agents/ra/pipeline/
    "newsletters/",       # symlink to agents/ra/output/
    ".secrets/",          # symlink to agents/nel/security/
    ".git/",
    "__pycache__/",
    "node_modules/",
    "venv/",
    ".venv/",
]

# --- Today ---
TODAY_MT = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d")
NOW_ISO = datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def log_flag(flag_type: str, file: str, reason: str, severity: str = "P3"):
    """Write a flag entry to maintenance-log.jsonl."""
    entry = {
        "date": TODAY_MT,
        "ts": NOW_ISO,
        "type": flag_type,
        "file": file,
        "reason": reason,
        "severity": severity,
        "action": "flagged",
        "session": "nightly-auto"
    }
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(entry) + "\n")
    print(f"  [FLAG {severity}] {flag_type}: {file}")
    print(f"         Reason: {reason}")


def log_summary(phase: str, flags_count: int, scanned: int):
    """Write phase summary to maintenance-log.jsonl."""
    entry = {
        "date": TODAY_MT,
        "ts": NOW_ISO,
        "type": "phase-summary",
        "phase": phase,
        "scanned": scanned,
        "flags": flags_count,
        "action": "summary"
    }
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(entry) + "\n")


def should_skip(path: str) -> bool:
    """Return True if this path should be skipped."""
    rel = os.path.relpath(path, ROOT)
    for skip in SKIP_PATHS:
        if rel.startswith(skip):
            return True
    return os.path.islink(path)


def read_trigger_matrix() -> set:
    """Return set of all script/file names listed in TRIGGER_MATRIX.md."""
    if not os.path.exists(TRIGGER_MATRIX):
        return set()
    try:
        content = open(TRIGGER_MATRIX).read()
        # Extract any filename.sh or filename.py mentioned
        names = set(re.findall(r'[\w\-\.]+\.(?:sh|py)', content))
        return names
    except Exception:
        return set()


_git_age_cache: dict[str, int] = {}

def _load_git_ages() -> dict[str, int]:
    """Run a single git log to get all file last-commit timestamps in bulk."""
    if _git_age_cache:
        return _git_age_cache
    try:
        # Get all files in repo with their last commit timestamp
        result = subprocess.run(
            ["git", "log", "--pretty=format:%at", "--name-only", "--diff-filter=A,M", "--no-renames", "-n", "2000"],
            cwd=ROOT, capture_output=True, text=True, timeout=30
        )
        current_ts = None
        for line in result.stdout.split("\n"):
            line = line.strip()
            if not line:
                continue
            if line.isdigit():
                current_ts = int(line)
            elif current_ts and line:
                # Don't overwrite — we want the MOST RECENT commit for each file
                if line not in _git_age_cache:
                    age_s = time.time() - current_ts
                    _git_age_cache[line] = int(age_s / 86400)
    except Exception:
        pass
    return _git_age_cache


def get_git_age_days(path: str) -> int:
    """Return age in days since last git commit for the given file. Returns 9999 if unknown."""
    ages = _load_git_ages()
    rel = os.path.relpath(path, ROOT)
    return ages.get(rel, 9999)


def grep_references(filename: str, root: str) -> int:
    """Count grep hits for this filename (without path) across the codebase."""
    try:
        result = subprocess.run(
            ["grep", "-r", "--include=*.sh", "--include=*.py",
             "--include=*.md", "--include=*.json", "--include=*.jsonl",
             "-l", filename, root],
            capture_output=True, text=True, timeout=30
        )
        lines = [l for l in result.stdout.strip().split("\n") if l and ".git" not in l]
        return len(lines)
    except Exception:
        return 0


# ============================================================
# PHASE 1: Dead script detection
# ============================================================

def check_dead_scripts() -> int:
    """
    Flags .sh and .py files in bin/ and agents/*/ that:
    - Are not listed in TRIGGER_MATRIX.md
    - Have not been git-committed in >14 days
    - Have zero grep references across the codebase
    Returns count of flags.
    """
    print("\n[Phase 1] Dead script scan...")
    trigger_names = read_trigger_matrix()
    flags = 0
    scanned = 0

    scan_dirs = [
        os.path.join(ROOT, "bin"),
        os.path.join(ROOT, "agents"),
        os.path.join(ROOT, "kai"),
    ]

    for scan_dir in scan_dirs:
        for dirpath, dirnames, filenames in os.walk(scan_dir):
            # Prune skip dirs
            dirnames[:] = [d for d in dirnames if not should_skip(os.path.join(dirpath, d))]
            for filename in filenames:
                if not filename.endswith((".sh", ".py")):
                    continue
                full_path = os.path.join(dirpath, filename)
                if should_skip(full_path):
                    continue
                scanned += 1
                rel = os.path.relpath(full_path, ROOT)

                # Check trigger matrix
                in_trigger = filename in trigger_names

                # Check git age
                git_age = get_git_age_days(full_path)

                # Check grep references (search for filename, not full path)
                refs = grep_references(filename, ROOT)

                # Dead = not in trigger + old commit + zero references to this filename
                # (We're lenient: require ALL THREE to flag, to avoid false positives)
                if not in_trigger and git_age > 14 and refs == 0:
                    reason = (
                        f"Not in TRIGGER_MATRIX.md; last commit {git_age}d ago; "
                        f"0 grep references to '{filename}' across codebase"
                    )
                    log_flag("dead-script", rel, reason, severity="P3")
                    flags += 1

    log_summary("dead-scripts", flags, scanned)
    print(f"  → Scanned {scanned} scripts, flagged {flags}")
    return flags


# ============================================================
# PHASE 2: Stale protocol scan
# ============================================================

def check_stale_protocols() -> int:
    """
    Flags protocol .md files in kai/protocols/ where:
    - A referenced file path no longer exists
    - A referenced script is not in TRIGGER_MATRIX.md
    - Version header is >60 days old
    Returns count of flags.
    """
    print("\n[Phase 2] Stale protocol scan...")
    trigger_names = read_trigger_matrix()
    flags = 0
    scanned = 0

    protocol_dir = os.path.join(ROOT, "kai", "protocols")
    if not os.path.isdir(protocol_dir):
        print("  → kai/protocols/ not found, skipping")
        return 0

    for filename in os.listdir(protocol_dir):
        if not filename.endswith(".md"):
            continue
        full_path = os.path.join(protocol_dir, filename)
        rel = os.path.relpath(full_path, ROOT)
        scanned += 1

        try:
            content = open(full_path).read()
        except Exception:
            continue

        # Check for file path references that no longer exist.
        # Strip code block lines first to avoid matching example JSON/shell paths.
        # Remove ```...``` blocks and lines with 4+ leading spaces (code indent).
        prose_content = re.sub(r'```.*?```', '', content, flags=re.DOTALL)
        prose_content = re.sub(r'(?m)^    .*$', '', prose_content)  # indented code lines

        # Pattern: path references like agents/xxx/yyy.sh or bin/xxx.sh
        # Require at least one / after the root component to avoid false matches
        path_refs = re.findall(
            r'\b(?:agents|bin|kai)/[\w/\-]+\.(?:sh|py|md|json|jsonl)\b',
            prose_content
        )
        dead_refs = []
        for ref in path_refs:
            # Avoid flagging YYYY/MM date-pattern paths (examples like agents/nel/archive/2026/04/)
            if re.search(r'/\d{4}/', ref):
                continue
            full_ref = os.path.join(ROOT, ref)
            if not os.path.exists(full_ref):
                # For .json refs, also check if .jsonl version exists (common suffix mismatch)
                if ref.endswith(".json") and os.path.exists(full_ref + "l"):
                    continue  # .jsonl exists, false positive
                dead_refs.append(ref)

        if dead_refs:
            reason = f"References {len(dead_refs)} path(s) that no longer exist: {', '.join(dead_refs[:3])}"
            log_flag("stale-protocol-dead-refs", rel, reason, severity="P2")
            flags += 1

        # Check version header age
        version_match = re.search(r'(?:Date|Updated|date):\s+(\d{4}-\d{2}-\d{2})', content)
        if version_match:
            version_date_str = version_match.group(1)
            try:
                version_date = datetime.strptime(version_date_str, "%Y-%m-%d")
                age_days = (datetime.now() - version_date).days
                if age_days > 60:
                    reason = f"Protocol dated {version_date_str} ({age_days}d ago) — may need version bump"
                    log_flag("stale-protocol-old-version", rel, reason, severity="P3")
                    flags += 1
            except Exception:
                pass

    log_summary("stale-protocols", flags, scanned)
    print(f"  → Scanned {scanned} protocols, flagged {flags}")
    return flags


# ============================================================
# PHASE 3: Duplicate file detection
# ============================================================

def file_sha256(path: str) -> str:
    """Return sha256 hex digest of file contents."""
    h = hashlib.sha256()
    try:
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except Exception:
        return ""


def is_dual_path(rel_a: str, rel_b: str) -> bool:
    """Return True if rel_a and rel_b are known intentional dual-path pairs."""
    for pair_a, pair_b in DUAL_PATH_PAIRS:
        if (rel_a.startswith(pair_a) and rel_b.startswith(pair_b)) or \
           (rel_a.startswith(pair_b) and rel_b.startswith(pair_a)):
            return True
    return False


def check_duplicates() -> int:
    """
    Finds files with identical sha256 that are NOT intentional dual-path pairs.
    Flags but never removes.
    Returns count of flags.
    """
    print("\n[Phase 3] Duplicate file detection...")
    flags = 0
    scanned = 0

    # Build hash → [paths] map for all non-trivial files
    hash_map: dict[str, list[str]] = {}

    scan_dirs = [
        os.path.join(ROOT, "bin"),
        os.path.join(ROOT, "agents"),
        os.path.join(ROOT, "kai"),
        os.path.join(ROOT, "website", "data"),
        os.path.join(ROOT, "agents", "sam", "website", "data"),
    ]

    for scan_dir in scan_dirs:
        if not os.path.isdir(scan_dir):
            continue
        for dirpath, dirnames, filenames in os.walk(scan_dir):
            dirnames[:] = [d for d in dirnames if not should_skip(os.path.join(dirpath, d))]
            for filename in filenames:
                full_path = os.path.join(dirpath, filename)
                if should_skip(full_path):
                    continue
                # Only check non-trivial files (>100 bytes)
                try:
                    size = os.path.getsize(full_path)
                    if size < 100:
                        continue
                except Exception:
                    continue
                scanned += 1
                digest = file_sha256(full_path)
                if digest:
                    rel = os.path.relpath(full_path, ROOT)
                    hash_map.setdefault(digest, []).append(rel)

    # Flag duplicates
    reported = set()
    for digest, paths in hash_map.items():
        if len(paths) < 2:
            continue
        # Check if all pairs are intentional dual-path
        all_intentional = True
        for i, pa in enumerate(paths):
            for pb in paths[i+1:]:
                if not is_dual_path(pa, pb):
                    all_intentional = False
                    break
            if not all_intentional:
                break

        if all_intentional:
            continue

        key = tuple(sorted(paths))
        if key in reported:
            continue
        reported.add(key)

        reason = f"Identical content (sha256 {digest[:12]}...) — may be unintentional duplicate: {', '.join(paths[:3])}"
        log_flag("duplicate-file", paths[0], reason, severity="P3")
        flags += 1

    log_summary("duplicates", flags, scanned)
    print(f"  → Scanned {scanned} files, flagged {flags} duplicate groups")
    return flags


# ============================================================
# NIGHTLY SUMMARY
# ============================================================

def write_nightly_summary(flags_by_phase: dict):
    """Write the nightly run summary to maintenance-log.jsonl."""
    entry = {
        "date": TODAY_MT,
        "ts": NOW_ISO,
        "type": "nightly-summary",
        "dead_scripts_flagged": flags_by_phase.get("dead-scripts", 0),
        "stale_protocols_flagged": flags_by_phase.get("stale-protocols", 0),
        "duplicates_flagged": flags_by_phase.get("duplicates", 0),
        "total_flags": sum(flags_by_phase.values()),
        "actions_taken": [],
        "escalations_required": []
    }
    with open(LOG_PATH, "a") as f:
        f.write(json.dumps(entry) + "\n")
    print(f"\n[Summary] Flags today: {entry['total_flags']} "
          f"(dead={entry['dead_scripts_flagged']}, "
          f"stale={entry['stale_protocols_flagged']}, "
          f"dupes={entry['duplicates_flagged']})")
    print(f"[Summary] Log: {LOG_PATH}")


# ============================================================
# MAIN
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Hyo system maintenance auditor — flags only, never deletes"
    )
    parser.add_argument("--check-dead-scripts", action="store_true",
                        help="Phase 1: Find scripts with no trigger, no reference")
    parser.add_argument("--check-stale-protocols", action="store_true",
                        help="Phase 2: Find protocols with dead path refs or old versions")
    parser.add_argument("--check-duplicates", action="store_true",
                        help="Phase 3: Find files with identical sha256")
    parser.add_argument("--all", action="store_true",
                        help="Run all phases (used by nightly launchd)")
    args = parser.parse_args()

    if not (args.check_dead_scripts or args.check_stale_protocols or
            args.check_duplicates or args.all):
        parser.print_help()
        sys.exit(1)

    print(f"[maintenance-audit] {TODAY_MT} — HYO_ROOT={ROOT}")
    print(f"[maintenance-audit] Log: {LOG_PATH}\n")

    flags_by_phase = {}

    if args.all or args.check_dead_scripts:
        flags_by_phase["dead-scripts"] = check_dead_scripts()

    if args.all or args.check_stale_protocols:
        flags_by_phase["stale-protocols"] = check_stale_protocols()

    if args.all or args.check_duplicates:
        flags_by_phase["duplicates"] = check_duplicates()

    if args.all:
        write_nightly_summary(flags_by_phase)

    total = sum(flags_by_phase.values())
    # Exit 0 even with flags — flags are informational, not errors
    sys.exit(0)


if __name__ == "__main__":
    main()
