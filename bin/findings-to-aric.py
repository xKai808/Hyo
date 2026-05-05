#!/usr/bin/env python3
"""
findings-to-aric.py — Bridge agent-research.sh findings into aric-latest.json.

THE GAP THIS CLOSES:
  agent-research.sh runs daily and writes findings-YYYY-MM-DD.md for each agent.
  These contain real external research (Kalshi API, arXiv, Reddit, Hacker News, etc).
  BUT: generate-morning-report.sh reads aric-latest.json → research_conducted[],
  which is written by the ARIC/Claude Code cycle that requires auth and is weeks stale.

  This script reads today's findings file, extracts meaningful content from each
  source, and writes it into aric-latest.json research_conducted[] so the morning
  report sees fresh external intelligence every day.

Usage:
  python3 bin/findings-to-aric.py                     # all agents
  python3 bin/findings-to-aric.py --agent aether       # one agent
  python3 bin/findings-to-aric.py --date 2026-04-30    # specific date

Called by: kai-autonomous.sh at 04:45 MT (after agent-research.sh at 04:30)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

MT = ZoneInfo("America/Denver")
ROOT = Path(os.environ.get("HYO_ROOT", Path.home() / "Documents/Projects/Hyo"))
AGENTS = ["aether", "nel", "ra", "sam", "kai", "dex"]

# Minimum content size to consider a source finding worth including
MIN_CONTENT_CHARS = 80


def today_mt() -> str:
    return datetime.now(MT).strftime("%Y-%m-%d")


def load_sources(agent: str) -> dict[str, dict]:
    """Load research-sources.json for agent. Returns {source_name: {url, focus}}."""
    sources_file = ROOT / "agents" / agent / "research-sources.json"
    if not sources_file.exists():
        return {}
    try:
        config = json.loads(sources_file.read_text())
        return {
            s["name"]: {"url": s.get("url", ""), "focus": s.get("focus", "")}
            for s in config.get("sources", [])
            if s.get("name")
        }
    except Exception:
        return {}


def parse_findings(findings_path: Path, sources: dict[str, dict], agent: str) -> list[dict]:
    """
    Parse findings-DATE.md into research_conducted[] items.

    Findings files have sections like:
      ### Source Name
      **Focus:** ...
      **Data size:** N chars
      **Content preview:** ...
      **Versions referenced:** ...
    """
    try:
        text = findings_path.read_text()
    except Exception:
        return []

    items = []

    # Split on ### headers (each source is a section)
    sections = re.split(r"\n### ", text)

    for section in sections[1:]:  # skip header preamble
        lines = section.strip().split("\n")
        if not lines:
            continue

        source_name = lines[0].strip()
        section_text = "\n".join(lines[1:])

        # Look up URL from research-sources.json
        source_info = sources.get(source_name, {})
        source_url = source_info.get("url", "")
        focus = source_info.get("focus", "")

        # Extract content preview
        preview_match = re.search(
            r"\*\*Content preview:\*\*\s*(.*?)(?=\n\n|\n\*\*|\Z)",
            section_text,
            re.DOTALL,
        )
        content_preview = ""
        if preview_match:
            content_preview = preview_match.group(1).strip()
            # Strip HTML noise from raw fetched content
            content_preview = re.sub(r"<[^>]+>", " ", content_preview)
            content_preview = re.sub(r"\s+", " ", content_preview).strip()

        # Extract versions referenced (good signal for technical findings)
        versions_match = re.search(r"\*\*Versions referenced:\*\*\s*(.+)", section_text)
        versions = versions_match.group(1).strip() if versions_match else ""

        # Extract data size
        size_match = re.search(r"\*\*Data size:\*\*\s*(\d+)\s*chars", section_text)
        data_size = int(size_match.group(1)) if size_match else 0

        # Skip sources with no meaningful content
        if data_size < MIN_CONTENT_CHARS and not versions:
            continue

        # Build the finding text
        if versions:
            finding = f"{source_name}: {focus}. Current versions: {versions}."
            if content_preview and len(content_preview) > 50:
                finding += f" Context: {content_preview[:300]}"
        elif content_preview and len(content_preview) > 50:
            # Trim JSON noise — many sources return raw API JSON
            clean_preview = content_preview
            if clean_preview.startswith("{") or clean_preview.startswith("["):
                # Try to extract something readable from JSON-ish content
                readable = re.findall(r'"(?:title|name|text|summary|abstract|selftext)"\s*:\s*"([^"]{20,200})"', clean_preview)
                if readable:
                    clean_preview = " | ".join(readable[:3])
                else:
                    clean_preview = ""

            if clean_preview:
                finding = f"{source_name}: {clean_preview[:400]}"
            else:
                continue  # skip — content is just raw JSON we can't extract
        else:
            continue  # skip — no useful content

        # Skip if source URL is missing or internal
        if not source_url or source_url.startswith("file://"):
            continue

        item = {
            "topic": source_name,
            "why": focus or f"Domain research for {agent}",
            "finding": finding,
            "source": source_url,
            "result": "Queued for next cycle — findings captured in intelligence brief",
            "agent": agent,
        }
        items.append(item)

    return items


def merge_into_aric(agent: str, new_items: list[dict], date: str) -> bool:
    """
    Merge new research_conducted items into aric-latest.json.
    Preserves improvement_built, weakness_worked, and other existing fields.
    Updates: research_conducted[], cycle_date, aric_phase.
    """
    aric_path = ROOT / "agents" / agent / "research" / "aric-latest.json"

    # Load existing or create skeleton
    existing = {}
    if aric_path.exists():
        try:
            existing = json.loads(aric_path.read_text())
        except Exception:
            existing = {}

    # Merge: keep existing fields, update research section.
    # IMPORTANT: do NOT overwrite research_conducted[] wholesale — this destroys
    # any items written by the ARIC Claude Code cycle (which uses a different source).
    # Instead, merge by de-duping on topic+source: existing Claude Code items are kept,
    # findings-to-aric items are added or updated.
    existing_items = existing.get("research_conducted", [])
    existing_keys = {(i.get("topic", ""), i.get("source", "")) for i in existing_items}
    # Keep Claude Code items not covered by today's findings run
    merged = [i for i in existing_items if (i.get("topic", ""), i.get("source", "")) not in {(n.get("topic",""), n.get("source","")) for n in new_items}]
    merged.extend(new_items)

    existing["agent"] = agent
    existing["cycle_date"] = date
    existing["aric_phase"] = existing.get("aric_phase", "Daily Research Cycle")
    existing["research_conducted"] = merged
    existing["research_source"] = "findings-to-aric.py (agent-research.sh findings bridge)"
    existing["_updated"] = datetime.now(MT).isoformat()

    # Preserve improvement fields if they exist
    # (written by agent-growth.sh — don't overwrite)
    # They're already in existing if present

    try:
        aric_path.parent.mkdir(parents=True, exist_ok=True)
        aric_path.write_text(json.dumps(existing, indent=2, ensure_ascii=False))
        return True
    except Exception as e:
        print(f"ERROR writing aric-latest.json for {agent}: {e}", file=sys.stderr)
        return False


def process_agent(agent: str, date: str) -> tuple[int, int]:
    """Returns (items_written, items_skipped)."""
    findings_path = ROOT / "agents" / agent / "research" / f"findings-{date}.md"

    if not findings_path.exists():
        # Try yesterday
        from datetime import timedelta
        yesterday = (datetime.strptime(date, "%Y-%m-%d") - timedelta(days=1)).strftime("%Y-%m-%d")
        findings_path = ROOT / "agents" / agent / "research" / f"findings-{yesterday}.md"
        if not findings_path.exists():
            print(f"  {agent}: no findings file for {date} or {yesterday} — skipping")
            return 0, 0

    sources = load_sources(agent)
    items = parse_findings(findings_path, sources, agent)

    if not items:
        print(f"  {agent}: no extractable items from {findings_path.name}")
        return 0, 0

    ok = merge_into_aric(agent, items, date)
    if ok:
        print(f"  {agent}: wrote {len(items)} items to aric-latest.json from {findings_path.name}")
        return len(items), 0
    return 0, len(items)


def main():
    parser = argparse.ArgumentParser(description="Bridge findings-DATE.md into aric-latest.json")
    parser.add_argument("--agent", default=None, help="Process one agent only")
    parser.add_argument("--date", default=None, help="Date to process (YYYY-MM-DD, default: today MT)")
    args = parser.parse_args()

    date = args.date or today_mt()
    agents = [args.agent] if args.agent else AGENTS

    print(f"findings-to-aric: processing {len(agents)} agents for {date}")
    total_written = 0
    for agent in agents:
        written, skipped = process_agent(agent, date)
        total_written += written

    print(f"findings-to-aric: done — {total_written} total items written to aric-latest.json files")


if __name__ == "__main__":
    main()
