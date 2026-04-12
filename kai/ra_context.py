#!/usr/bin/env python3
"""
ra_context.py — pre-synthesize context loader for Ra daily briefs.

Reads today's raw gather output (today's jsonl of scraped records) and the
existing research archive, then writes `kai/research/.context.md` — a
compact "prior takes" block that synthesize.py prepends to the model's
context. The goal is that Ra can say things like:

    "Last time we covered the Fed on 2026-04-11, we said X. Today's
     update is Y. The trend is rising — 4 mentions in 7d vs 9 in 30d."

How it works:

1. Build an index of every entity/topic in the archive and its aliases
   (by reading the headers of every .md file under entities/ and topics/).
2. Skim today's gather records (titles + summaries) for alias hits, case
   insensitive. Tally matches per entity/topic.
3. For every hit, load the last 1–3 timeline entries from that file and
   include the most recent Take / Data / Hinge so synthesize can weave
   continuity naturally.
4. Include a short "Trend pulse" section with the current rising /
   falling / new classification lifted from trends.md if present.
5. Include a "Lab library" one-liner so Ra can reach into durable notes
   when the day's news touches something already filed.

Stdlib only. Usage:

    python3 ra_context.py                       # today
    python3 ra_context.py --date 2026-04-11     # backfill
    python3 ra_context.py --limit-per-entity 3  # more context per hit

Emits `kai/research/.context.md`. synthesize.py reads that file if it
exists and prepends it to the prompt. Safe to call when the archive is
empty — the file will still be written and will just say "archive empty."
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(
    os.environ.get(
        "HYO_ROOT",
        Path(__file__).resolve().parent.parent,
    )
).resolve()
RESEARCH = ROOT / "kai" / "research"
ENTITIES = RESEARCH / "entities"
TOPICS = RESEARCH / "topics"
LAB = RESEARCH / "lab"
TRENDS_FILE = RESEARCH / "trends.md"
CONTEXT_FILE = RESEARCH / ".context.md"

# where gather.py drops its jsonl per-day dumps; checked in order
GATHER_CANDIDATES = [
    lambda d: Path(os.environ.get("HYO_INTELLIGENCE_DIR", "")) / f"{d}.jsonl",
    lambda d: Path.home() / "Documents" / "Projects" / "Kai" / "intelligence" / f"{d}.jsonl",
    lambda d: RESEARCH / "raw" / f"{d}.jsonl",
]

# --------------------------------------------------------------------------
# archive readers
# --------------------------------------------------------------------------


def _read_header_fields(text: str) -> dict:
    """Pull slug / aliases / category out of an entity file header."""
    out = {}
    for pattern, key in (
        (r"\*\*Slug:\*\*\s*`([^`]+)`", "slug"),
        (r"\*\*Aliases:\*\*\s*(.+)", "aliases"),
        (r"\*\*Category:\*\*\s*(.+)", "category"),
    ):
        m = re.search(pattern, text)
        if m:
            out[key] = m.group(1).strip()
    return out


def load_entity_index() -> list[dict]:
    """Every entity file → { slug, name, aliases[], dates[], file, last_take_block }"""
    items = []
    for p in sorted(ENTITIES.glob("*.md")):
        text = p.read_text()
        first = text.splitlines()[0] if text else ""
        name_m = re.match(r"^# Entity: (.+)$", first)
        name = name_m.group(1) if name_m else p.stem

        header = _read_header_fields(text)
        aliases_raw = header.get("aliases", "")
        aliases = []
        if aliases_raw and aliases_raw != "—":
            aliases = [a.strip() for a in aliases_raw.split(",") if a.strip()]
        # always include the canonical name and slug as match keys
        match_keys = {name.lower()} | {a.lower() for a in aliases} | {p.stem.replace("-", " ")}

        dates = re.findall(r"^### (\d{4}-\d{2}-\d{2})", text, re.MULTILINE)
        items.append({
            "slug": p.stem,
            "name": name,
            "aliases": aliases,
            "match_keys": [k for k in match_keys if k],
            "dates": sorted(set(dates), reverse=True),
            "file": p,
            "text": text,
            "kind": "entity",
        })
    return items


def load_topic_index() -> list[dict]:
    items = []
    for p in sorted(TOPICS.glob("*.md")):
        text = p.read_text()
        first = text.splitlines()[0] if text else ""
        name_m = re.match(r"^# Topic: (.+)$", first)
        name = name_m.group(1) if name_m else p.stem

        # topic slug words are reasonable match keys on their own
        slug_words = p.stem.replace("-", " ")
        match_keys = {name.lower(), slug_words.lower()}

        dates = re.findall(r"^### (\d{4}-\d{2}-\d{2})", text, re.MULTILINE)
        items.append({
            "slug": p.stem,
            "name": name,
            "aliases": [],
            "match_keys": [k for k in match_keys if k],
            "dates": sorted(set(dates), reverse=True),
            "file": p,
            "text": text,
            "kind": "topic",
        })
    return items


def load_lab_index() -> list[dict]:
    items = []
    for p in sorted(LAB.glob("*.md")):
        text = p.read_text()
        first = text.splitlines()[0] if text else ""
        name_m = re.match(r"^# Lab: (.+)$", first)
        name = name_m.group(1) if name_m else p.stem
        # grab the "What it is" line for a one-liner
        what_m = re.search(r"## What it is\n(.+?)(?:\n\n|\Z)", text, re.DOTALL)
        what = (what_m.group(1).strip().splitlines()[0] if what_m else "")
        items.append({
            "slug": p.stem,
            "name": name,
            "what": what,
        })
    return items


# --------------------------------------------------------------------------
# matching
# --------------------------------------------------------------------------

# keys shorter than this are ignored to avoid matching "ai" against "pain"
MIN_KEY_LEN = 3


def _alias_regex(key: str) -> re.Pattern:
    # word-bounded, case-insensitive
    return re.compile(rf"\b{re.escape(key)}\b", re.IGNORECASE)


def score_records(records: list[dict], items: list[dict]) -> list[dict]:
    """For each item, count alias hits across records. Return items sorted
    by score desc, keeping only hits."""
    scored = []
    for item in items:
        hits = 0
        snippets: list[str] = []
        for key in item["match_keys"]:
            if len(key) < MIN_KEY_LEN:
                continue
            rx = _alias_regex(key)
            for rec in records:
                blob = " ".join(str(rec.get(f, "")) for f in ("title", "summary", "url", "tags"))
                if rx.search(blob):
                    hits += 1
                    if len(snippets) < 2:
                        t = rec.get("title") or rec.get("summary") or ""
                        if t and t not in snippets:
                            snippets.append(t[:140])
        if hits > 0:
            entry = dict(item)
            entry["hits"] = hits
            entry["snippets"] = snippets
            scored.append(entry)
    scored.sort(key=lambda x: x["hits"], reverse=True)
    return scored


def last_timeline_block(text: str, limit: int = 1) -> str:
    """Return the most recent N Timeline entries from a file, joined as md."""
    if "## Timeline" not in text:
        return ""
    _, post = text.split("## Timeline", 1)
    # split on ### headers
    chunks = re.split(r"(?=^### \d{4}-\d{2}-\d{2})", post, flags=re.MULTILINE)
    chunks = [c.strip() for c in chunks if c.strip().startswith("### ")]
    return "\n\n".join(chunks[:limit])


# --------------------------------------------------------------------------
# gather records
# --------------------------------------------------------------------------


def load_gather_records(date: str) -> list[dict]:
    for make in GATHER_CANDIDATES:
        try:
            p = make(date)
        except Exception:
            continue
        if p and p.exists():
            out: list[dict] = []
            with p.open() as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        out.append(json.loads(line))
                    except Exception:
                        continue
            return out
    return []


# --------------------------------------------------------------------------
# trend summary (read-only from trends.md)
# --------------------------------------------------------------------------


def read_trend_pulse() -> dict:
    if not TRENDS_FILE.exists():
        return {"rising": [], "new": [], "falling": []}
    text = TRENDS_FILE.read_text()
    rising, new, falling = [], [], []
    for line in text.splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 2:
            continue
        name = cells[0]
        trend = cells[1].lower() if len(cells) > 1 else ""
        if "](" not in name:
            continue
        # cells[0] looks like "[Fed](entities/fed.md)"
        nm = re.match(r"\[([^\]]+)\]", name)
        if not nm:
            continue
        label = nm.group(1)
        if trend == "rising":
            rising.append(label)
        elif trend == "new":
            new.append(label)
        elif trend == "falling":
            falling.append(label)
    return {
        "rising": sorted(set(rising))[:8],
        "new": sorted(set(new))[:8],
        "falling": sorted(set(falling))[:8],
    }


# --------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------


def render_context(
    date: str,
    ent_hits: list[dict],
    top_hits: list[dict],
    labs: list[dict],
    trends: dict,
    gather_count: int,
    limit_per_entity: int,
) -> str:
    now = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    lines: list[str] = []
    lines.append(f"# Ra context — {date}")
    lines.append("")
    lines.append(
        f"*Auto-generated {now} by `kai/ra_context.py`. "
        f"Gather records scanned: {gather_count}.*"
    )
    lines.append("")
    lines.append(
        "**PRN — use as needed, not on schedule.** This is a resource, not "
        "an obligation. Reach into the archive when a hinge fired, a trend "
        "turned, or a lab note is directly relevant. Skip it when today's "
        "stories are new ground or a callback would only add words. The "
        "brief is not a daily sequel — most of them should stand on their "
        "own. The archive updates either way."
    )
    lines.append("")

    # Prior takes
    lines.append("## Prior takes on today's signal")
    lines.append("")
    if not ent_hits and not top_hits:
        lines.append(
            "*No archive matches for today's gather records.* Either the archive is "
            "empty, the gather failed, or today's stories are genuinely new ground — "
            "treat every entity/topic you write about as a first-appearance and "
            "let ra_archive.py file it for tomorrow's continuity."
        )
        lines.append("")
    else:
        if ent_hits:
            lines.append("### Entities we already track")
            lines.append("")
            for hit in ent_hits[:10]:
                block = last_timeline_block(hit["text"], limit=limit_per_entity)
                lines.append(f"**{hit['name']}** ({hit['hits']} mentions in today's gather)")
                if hit["snippets"]:
                    snip = hit["snippets"][0]
                    lines.append(f"> Today's signal: {snip}")
                if block:
                    lines.append("")
                    lines.append(block)
                lines.append("")
        if top_hits:
            lines.append("### Topics we already track")
            lines.append("")
            for hit in top_hits[:6]:
                block = last_timeline_block(hit["text"], limit=1)
                lines.append(f"**{hit['name']}** ({hit['hits']} mentions in today's gather)")
                if block:
                    lines.append("")
                    lines.append(block)
                lines.append("")

    # Trend pulse
    lines.append("## Trend pulse")
    lines.append("")
    rising = ", ".join(trends.get("rising", [])) or "—"
    new = ", ".join(trends.get("new", [])) or "—"
    falling = ", ".join(trends.get("falling", [])) or "—"
    lines.append(f"- **Rising:** {rising}")
    lines.append(f"- **New this week:** {new}")
    lines.append(f"- **Falling:** {falling}")
    lines.append("")
    lines.append(
        "*Use these when a story connects to a trend — a rising entity getting "
        "another catalyst is more interesting than an isolated headline.*"
    )
    lines.append("")

    # Lab library
    lines.append("## Lab library (durable capability notes on file)")
    lines.append("")
    if not labs:
        lines.append("*(empty — file the first one today)*")
    else:
        for l in labs[:20]:
            line = f"- **{l['name']}** — {l['what']}" if l["what"] else f"- **{l['name']}**"
            lines.append(line)
    lines.append("")
    lines.append(
        "*When today's news touches one of these, reach for it: cite the lab "
        "note in The Lab section rather than re-explaining from scratch.*"
    )
    lines.append("")

    return "\n".join(lines).rstrip() + "\n"


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def build_context(date: str, limit_per_entity: int = 1) -> int:
    records = load_gather_records(date)
    ents = load_entity_index()
    tops = load_topic_index()
    labs = load_lab_index()

    ent_hits = score_records(records, ents) if records else []
    top_hits = score_records(records, tops) if records else []
    trends = read_trend_pulse()

    CONTEXT_FILE.parent.mkdir(parents=True, exist_ok=True)
    text = render_context(
        date=date,
        ent_hits=ent_hits,
        top_hits=top_hits,
        labs=labs,
        trends=trends,
        gather_count=len(records),
        limit_per_entity=limit_per_entity,
    )
    CONTEXT_FILE.write_text(text)
    print(
        f"[ra_context] {date}: {len(records)} records, "
        f"{len(ent_hits)} entity hits, {len(top_hits)} topic hits, "
        f"{len(labs)} lab notes on file → {CONTEXT_FILE}"
    )
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--limit-per-entity", type=int, default=1,
                    help="how many prior timeline entries to include per hit")
    args = ap.parse_args()
    date = args.date or dt.date.today().isoformat()
    return build_context(date, limit_per_entity=args.limit_per_entity)


if __name__ == "__main__":
    sys.exit(main())
