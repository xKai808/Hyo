#!/usr/bin/env python3
"""
bin/pre-publish-dedup.py — Pre-publish duplicate detection gate.

Checks whether a proposed feed entry would be a duplicate of an existing entry.
Called by kai push before writing to the feed or HQ API.

Exit codes:
  0 — no duplicate found (safe to publish)
  1 — exact or near-duplicate detected (BLOCK publish)
  2 — usage error or feed unreadable (warn only, allow publish)

Usage:
  python3 bin/pre-publish-dedup.py --agent AGENT --type TYPE --date DATE --title TITLE

Rules:
  - EXACT duplicate: same agent + same type + same date → always block
  - NEAR duplicate:  same agent + same type + title similarity ≥ 80% within 7 days → block
  - TITLE similarity uses token-set ratio (ignores word order, handles minor rewrites)
  - Returns clear human-readable reason when blocking

Change history:
  v1.0 (2026-04-28): Initial — #81 Pre-publish dedup algorithm.
"""

import argparse, json, os, re, sys
from pathlib import Path
from datetime import datetime, timedelta

ROOT = Path(__file__).resolve().parent.parent
FEED_PATHS = [
    ROOT / "agents" / "sam" / "website" / "data" / "feed.json",
    ROOT / "website" / "data" / "feed.json",
]
NEAR_DEDUP_DAYS = 7          # look-back window for near-dup check
SIMILARITY_THRESHOLD = 0.80  # 80% token overlap = near-dup


# ── Simple token-set similarity (no external deps) ───────────────────────────
def tokenize(s: str) -> set:
    """Lowercase alphanumeric tokens, strip stop-words."""
    STOP = {"the", "a", "an", "of", "for", "in", "on", "at", "to", "and",
            "or", "is", "was", "are", "with", "from", "by", "as", "this",
            "daily", "report", "update", "summary", "analysis"}
    tokens = set(re.findall(r'\b[a-z0-9]{2,}\b', s.lower()))
    return tokens - STOP


def similarity(a: str, b: str) -> float:
    ta, tb = tokenize(a), tokenize(b)
    if not ta or not tb:
        return 0.0
    intersection = len(ta & tb)
    union = len(ta | tb)
    return intersection / union if union else 0.0


# ── Load feed (prefer first path that exists and is readable) ────────────────
def load_reports() -> list:
    for path in FEED_PATHS:
        if not path.exists():
            continue
        try:
            with open(path) as f:
                data = json.load(f)
            return data.get("reports", [])
        except Exception as e:
            print(f"[dedup] WARN: could not read {path}: {e}", file=sys.stderr)
    return []


# ── Main gate ─────────────────────────────────────────────────────────────────
def check_duplicate(agent: str, entry_type: str, date: str, title: str) -> tuple[bool, str]:
    """
    Returns (is_duplicate, reason).
    is_duplicate=True → caller should block publish.
    """
    reports = load_reports()
    if not reports:
        return False, "feed empty or unreadable — allowing publish"

    try:
        entry_date = datetime.strptime(date, "%Y-%m-%d")
    except ValueError:
        return False, f"invalid date format '{date}' — allowing publish"

    cutoff = entry_date - timedelta(days=NEAR_DEDUP_DAYS)

    for r in reports:
        # agent field not consistently set — fall back to author (lowercased) or id prefix
        r_agent_raw = (
            r.get("agent")
            or r.get("author", "")
            or r.get("id", "").split("-")[2] if r.get("id", "").count("-") >= 2 else ""
        )
        r_agent = str(r_agent_raw).lower()
        r_type  = r.get("type", "")
        r_date_str = r.get("date", r.get("ts", r.get("timestamp", "")))[:10]
        r_title = r.get("title", r.get("description", ""))

        # Normalize agent for comparison (Kai → kai, Nel → nel, etc.)
        agent_normalized = agent.lower()

        # Only compare same agent + same type
        if r_agent != agent_normalized or r_type != entry_type:
            continue

        try:
            r_date = datetime.strptime(r_date_str, "%Y-%m-%d")
        except ValueError:
            continue

        # Rule 1: exact duplicate (same agent, type, date)
        if r_date_str == date:
            return True, (
                f"EXACT DUPLICATE: {agent}/{entry_type} already published for {date}. "
                f"Existing title: '{r_title}'. "
                f"Block publish to prevent double-entry on HQ."
            )

        # Rule 2: near-duplicate (same agent, type, similar title within 7 days)
        if r_date >= cutoff:
            sim = similarity(title, r_title)
            if sim >= SIMILARITY_THRESHOLD:
                return True, (
                    f"NEAR-DUPLICATE: '{title}' is {sim:.0%} similar to '{r_title}' "
                    f"({r_agent}/{r_type} on {r_date_str}, {(entry_date - r_date).days}d ago). "
                    f"Similarity threshold: {SIMILARITY_THRESHOLD:.0%}. "
                    f"If this is intentional (e.g. correction), use --force to bypass."
                )

    return False, "no duplicate found"


def main():
    parser = argparse.ArgumentParser(description="Pre-publish duplicate detection gate")
    parser.add_argument("--agent",  required=True, help="Agent name (e.g. aether, nel)")
    parser.add_argument("--type",   required=True, help="Feed entry type (e.g. aether-analysis)")
    parser.add_argument("--date",   required=True, help="Entry date (YYYY-MM-DD)")
    parser.add_argument("--title",  required=True, help="Entry title")
    parser.add_argument("--force",  action="store_true", help="Bypass dedup check (use for corrections)")
    parser.add_argument("--quiet",  action="store_true", help="Suppress output (for scripted use)")
    args = parser.parse_args()

    if args.force:
        if not args.quiet:
            print(f"[dedup] --force: bypassing dedup check for {args.agent}/{args.type}/{args.date}")
        sys.exit(0)

    is_dup, reason = check_duplicate(args.agent, args.type, args.date, args.title)

    if is_dup:
        print(f"\n{'!' * 70}")
        print(f"DEDUP GATE BLOCKED: {reason}")
        print(f"{'!' * 70}\n")
        sys.exit(1)
    else:
        if not args.quiet:
            print(f"[dedup] PASS — {reason}")
        sys.exit(0)


if __name__ == "__main__":
    main()
