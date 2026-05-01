#!/usr/bin/env python3
"""
aric-external-filter.py — Filter ARIC intelligence items to external sources only.

Problem: agents populate research_conducted[] with internal sources:
  - file:// URLs (GROWTH.md, session-errors.jsonl, aether.sh)
  - "internal" / "from GROWTH.md" / "from ACTIVE.md" descriptions
  - Wikipedia as sole source (too generic)
  - Empty or missing source fields

These are not external intelligence. They are internal bookkeeping dressed as research.
The morning report must contain what we learned from the world — not what we said to ourselves.

Input  (stdin): JSON array of raw ARIC intelligence items
Output (stdout): JSON array with internal-source items removed

Items removed: logged to stderr with reason.
Items kept: external URL present, not a file:// path, not flagged as internal.

If ALL items are removed: outputs [] — caller uses "No external research completed overnight."
That honest statement is better than synthesized internal navel-gazing.

Usage:
    cat aric-latest.json | python3 bin/aric-external-filter.py
    echo '[...]' | python3 bin/aric-external-filter.py
"""
from __future__ import annotations

import json
import re
import sys
from urllib.parse import urlparse

# Patterns that indicate an internal source — not external intelligence
INTERNAL_SOURCE_PATTERNS = [
    r"^file://",
    r"GROWTH\.md",
    r"session-errors\.jsonl",
    r"ACTIVE\.md",
    r"PLAYBOOK\.md",
    r"KNOWLEDGE\.md",
    r"KAI_BRIEF\.md",
    r"KAI_TASKS\.md",
    r"AGENT_ALGORITHMS\.md",
    r"\(internal\)",
    r"from GROWTH",
    r"from ACTIVE",
    r"from PLAYBOOK",
    r"Kai's mistake ledger",
    r"^internal$",
    r"agent_memory",
    r"kai/ledger",
    r"kai/protocols",
    r"agents/\w+/GROWTH",
    r"agents/\w+/ACTIVE",
]

# Patterns that are acceptable external sources
EXTERNAL_URL_PATTERN = re.compile(
    r"^https?://",
    re.IGNORECASE
)

# These domains are too generic to count as specific intelligence
GENERIC_DOMAINS = {
    "en.wikipedia.org",
    "wikipedia.org",
}


def _source_is_internal(source: str) -> tuple[bool, str]:
    """Return (is_internal, reason) for a given source string."""
    if not source or source.strip() == "":
        return True, "empty source"

    for pattern in INTERNAL_SOURCE_PATTERNS:
        if re.search(pattern, source, re.IGNORECASE):
            return True, f"matches internal pattern: {pattern}"

    return False, ""


def _source_is_external(source: str) -> bool:
    """Return True if the source is a proper external URL."""
    if not EXTERNAL_URL_PATTERN.match(source.strip()):
        return False
    try:
        parsed = urlparse(source.strip())
        domain = parsed.netloc.lower()
        if domain in GENERIC_DOMAINS:
            return False  # generic enough to flag, but don't block if it's the only source
        return bool(domain)
    except Exception:
        return False


def _item_has_external_source(item: dict) -> tuple[bool, str]:
    """Return (passes, reason) for an item."""
    source = item.get("source", "") or item.get("url", "") or ""

    # Check for internal patterns first
    internal, reason = _source_is_internal(source)
    if internal:
        return False, reason

    # Require at least an http/https URL (even generic ones pass if not internal)
    if EXTERNAL_URL_PATTERN.match(source.strip()):
        return True, "external URL"

    # Named sources like "Mailchimp Reports" without a URL — borderline
    # Accept if the finding contains an external URL inline
    finding = item.get("finding", "") or ""
    if re.search(r"https?://\S+", finding):
        return True, "external URL in finding"

    return False, f"no external URL found in source: {repr(source[:80])}"


def filter_items(items: list[dict]) -> list[dict]:
    kept = []
    for item in items:
        passes, reason = _item_has_external_source(item)
        if passes:
            kept.append(item)
        else:
            agent = item.get("agent", "?")
            topic = item.get("topic", "") or item.get("finding", "")[:60]
            print(
                f"FILTERED [{agent}] {repr(topic[:60])!s} — {reason}",
                file=sys.stderr,
            )
    return kept


def main():
    raw = sys.stdin.read().strip()
    if not raw:
        print("[]")
        return

    try:
        items = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"Input JSON parse error: {e}", file=sys.stderr)
        sys.exit(1)

    if not isinstance(items, list):
        print("Expected JSON array", file=sys.stderr)
        sys.exit(1)

    filtered = filter_items(items)
    removed = len(items) - len(filtered)
    if removed > 0:
        print(
            f"aric-external-filter: removed {removed}/{len(items)} internal-source items",
            file=sys.stderr,
        )

    print(json.dumps(filtered, ensure_ascii=False))


if __name__ == "__main__":
    main()
