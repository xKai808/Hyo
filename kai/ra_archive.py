#!/usr/bin/env python3
"""
ra_archive.py — post-run archiver for Ra daily briefs.

Reads today's rendered brief markdown, parses the YAML frontmatter for
structured metadata (entities, topics, lab_items), and appends timeline
entries to per-entity / per-topic / per-lab files under kai/research/.
Then rebuilds kai/research/index.md and kai/research/trends.md.

Everything it reads and writes is plain markdown. Stdlib only. Idempotent
for a given (date, entity) pair — re-runs replace rather than append.

Usage:
    python3 ra_archive.py                       # archive today's brief
    python3 ra_archive.py --date 2026-04-11     # archive a specific date
    python3 ra_archive.py --rebuild-index       # only rebuild index + trends

Frontmatter contract (what synthesize.py / hand-authored briefs must emit):

    ---
    date: YYYY-MM-DD
    kind: ra-daily
    edition: v2
    voice: kai.hyo
    entities:
      - slug: fed
        name: Federal Reserve
        aliases: [Fed, FOMC, Powell]
        category: macro
        take: "Held 3.50-3.75% second meeting; hawks openly floating hike"
        data: "Effective FFR 3.64%; dot plot unchanged at one cut 2026"
        hinge: "CPI in a few days, FOMC Apr 28-29"
        confidence: medium-high
      - slug: bitcoin
        ...
    topics:
      - slug: macro-rates
        name: "Macro & Rates"
        signal: "Fed out of rope, hawks stir"
        take: "Market no longer believes in two 2026 cuts"
    lab_items:
      - slug: ai-scientist-v2
        name: "AI Scientist-v2"
        what: "Agent that searches over research moves, not tokens"
        why: "Enables reasoning on problems where process matters more than answer"
        when: "Debugging, workflow optimization, pricing, go-to-market loops"
        paper_url: "https://arxiv.org/..."
    ---
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# paths
# --------------------------------------------------------------------------

ROOT = Path(
    os.environ.get(
        "HYO_ROOT",
        Path(__file__).resolve().parent.parent,
    )
).resolve()
NEWSLETTERS = Path(os.environ.get("HYO_NEWSLETTERS_DIR", ROOT / "newsletters"))
RESEARCH = ROOT / "kai" / "research"
ENTITIES = RESEARCH / "entities"
TOPICS = RESEARCH / "topics"
LAB = RESEARCH / "lab"
BRIEFS = RESEARCH / "briefs"
RAW = RESEARCH / "raw"
INDEX_FILE = RESEARCH / "index.md"
TRENDS_FILE = RESEARCH / "trends.md"

for d in (RESEARCH, ENTITIES, TOPICS, LAB, BRIEFS, RAW):
    d.mkdir(parents=True, exist_ok=True)


# --------------------------------------------------------------------------
# minimal YAML frontmatter parser (stdlib only)
# --------------------------------------------------------------------------

def _strip_quotes(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        return s[1:-1]
    return s


def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Parse a minimal YAML frontmatter block. Supports scalars, lists of
    scalars, and lists of dicts with scalar values. Good enough for Ra's needs.
    """
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    block = text[4:end]
    body = text[end + 5:]

    lines = block.splitlines()
    meta: dict = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$", line)
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).strip()
        if val == "":
            # could be a list or dict that follows, indented
            sub_lines = []
            i += 1
            while i < len(lines):
                nxt = lines[i]
                if nxt.startswith("  ") or nxt.startswith("\t") or nxt.strip() == "":
                    sub_lines.append(nxt)
                    i += 1
                else:
                    break
            meta[key] = _parse_list_block(sub_lines)
        else:
            # inline scalar or inline flow list like [a, b, c]
            if val.startswith("[") and val.endswith("]"):
                meta[key] = [_strip_quotes(x) for x in val[1:-1].split(",") if x.strip()]
            else:
                meta[key] = _strip_quotes(val)
            i += 1
    return meta, body


def _parse_list_block(lines: list[str]) -> list:
    """Parse an indented block beneath a key. Supports:
      - scalar
      - scalar
    and:
      - key1: value
        key2: value
        key3: [a, b, c]
    """
    items: list = []
    cur: dict | None = None
    for raw in lines:
        if not raw.strip():
            continue
        stripped = raw.lstrip()
        indent = len(raw) - len(stripped)
        if stripped.startswith("- "):
            rest = stripped[2:]
            if ":" in rest and not rest.strip().startswith("["):
                # first key of a new dict item
                if cur is not None:
                    items.append(cur)
                cur = {}
                key, _, val = rest.partition(":")
                val = val.strip()
                if val.startswith("[") and val.endswith("]"):
                    cur[key.strip()] = [_strip_quotes(x) for x in val[1:-1].split(",") if x.strip()]
                else:
                    cur[key.strip()] = _strip_quotes(val)
            else:
                # scalar list item
                if cur is not None:
                    items.append(cur)
                    cur = None
                items.append(_strip_quotes(rest))
        elif cur is not None and ":" in stripped:
            key, _, val = stripped.partition(":")
            val = val.strip()
            if val.startswith("[") and val.endswith("]"):
                cur[key.strip()] = [_strip_quotes(x) for x in val[1:-1].split(",") if x.strip()]
            else:
                cur[key.strip()] = _strip_quotes(val)
    if cur is not None:
        items.append(cur)
    return items


# --------------------------------------------------------------------------
# timeline file management
# --------------------------------------------------------------------------

TIMELINE_HEADER = "## Timeline\n\n"


def slugify(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    return s.strip("-") or "untitled"


def _upsert_timeline_entry(path: Path, date: str, block: str, header_text: str):
    """Insert or replace the entry for `date` inside a Timeline section.

    If the file doesn't exist, create it with `header_text` as intro content.
    If an entry for `date` already exists, replace it in-place.
    Otherwise prepend the new entry at the top of the Timeline section.
    """
    if not path.exists():
        path.write_text(header_text + TIMELINE_HEADER + block + "\n")
        return

    content = path.read_text()
    if TIMELINE_HEADER not in content:
        content = content.rstrip() + "\n\n" + TIMELINE_HEADER
    pre, post = content.split(TIMELINE_HEADER, 1)

    # remove any existing entry for this date
    date_marker = f"### {date}"
    lines = post.splitlines(keepends=True)
    out_lines: list[str] = []
    skip = False
    for line in lines:
        if line.startswith("### "):
            skip = line.startswith(date_marker)
        if not skip:
            out_lines.append(line)
    post_clean = "".join(out_lines)

    new_content = pre + TIMELINE_HEADER + block + "\n" + post_clean.lstrip("\n")
    path.write_text(new_content.rstrip() + "\n")


def archive_entity(date: str, ent: dict):
    slug = ent.get("slug") or slugify(ent.get("name", "entity"))
    name = ent.get("name", slug)
    aliases = ent.get("aliases", [])
    category = ent.get("category", "")
    take = ent.get("take", "")
    data = ent.get("data", "")
    hinge = ent.get("hinge", "")
    confidence = ent.get("confidence", "")

    path = ENTITIES / f"{slug}.md"

    alias_str = ", ".join(aliases) if isinstance(aliases, list) else str(aliases)
    header_text = (
        f"# Entity: {name}\n\n"
        f"**Slug:** `{slug}`  \n"
        f"**Aliases:** {alias_str or '—'}  \n"
        f"**Category:** {category or '—'}  \n\n"
    )

    entry = (
        f"### {date}\n"
        f"**Brief:** [{date}](../../../newsletters/{date}.md)\n\n"
        f"**Take:** {take}\n\n"
        f"**Data:** {data}\n\n"
        f"**Hinge:** {hinge}\n\n"
        f"**Confidence:** {confidence}\n"
    )
    _upsert_timeline_entry(path, date, entry, header_text)


def archive_topic(date: str, top: dict):
    slug = top.get("slug") or slugify(top.get("name", "topic"))
    name = top.get("name", slug)
    signal = top.get("signal", "")
    take = top.get("take", "")

    path = TOPICS / f"{slug}.md"

    header_text = f"# Topic: {name}\n\n**Slug:** `{slug}`\n\n"
    entry = (
        f"### {date}\n"
        f"**Brief:** [{date}](../../../newsletters/{date}.md)\n\n"
        f"**Signal:** {signal}\n\n"
        f"**Take:** {take}\n"
    )
    _upsert_timeline_entry(path, date, entry, header_text)


def archive_lab(date: str, item: dict):
    slug = item.get("slug") or slugify(item.get("name", "lab"))
    name = item.get("name", slug)
    what = item.get("what", "")
    why = item.get("why", "")
    when = item.get("when", "")
    paper_url = item.get("paper_url", "")
    limitations = item.get("limitations", "")
    related = item.get("related", "")

    path = LAB / f"{slug}.md"

    # lab entries are stable templates — if the file doesn't exist, create it;
    # if it does, append a "### Updated YYYY-MM-DD" block at the bottom with
    # whatever fields are new.
    if not path.exists():
        ref_line = f"- [Brief {date}](../../../newsletters/{date}.md)"
        if paper_url:
            ref_line += f"\n- [Source]({paper_url})"
        content = (
            f"# Lab: {name}\n\n"
            f"## First seen\n{date} · Ra brief\n\n"
            f"## What it is\n{what}\n\n"
            f"## Why it's interesting\n{why}\n\n"
            f"## When we'd reach for it\n{when}\n\n"
            f"## Limitations\n{limitations or '*(to be filled as we learn more)*'}\n\n"
            f"## References\n{ref_line}\n\n"
            f"## Related\n{related}\n"
        )
        path.write_text(content)
        return

    # append an update block
    existing = path.read_text()
    update = (
        f"\n\n## Update {date}\n"
        f"**Brief:** [{date}](../../../newsletters/{date}.md)\n"
    )
    for k, v in (("What", what), ("Why", why), ("When", when), ("Limitations", limitations)):
        if v:
            update += f"- **{k}:** {v}\n"
    if paper_url:
        update += f"- **Source:** {paper_url}\n"
    # dedupe: if the same date update block already exists, skip
    if f"## Update {date}" not in existing:
        path.write_text(existing.rstrip() + update)


# --------------------------------------------------------------------------
# index + trends rebuild
# --------------------------------------------------------------------------

def _collect_entries(folder: Path) -> list[dict]:
    entries = []
    for p in sorted(folder.glob("*.md")):
        text = p.read_text()
        dates = re.findall(r"^### (\d{4}-\d{2}-\d{2})", text, re.MULTILINE)
        name_match = re.match(r"^# (?:Entity|Topic|Lab): (.+)$", text.splitlines()[0] if text else "")
        name = name_match.group(1) if name_match else p.stem
        entries.append({
            "slug": p.stem,
            "name": name,
            "path": p,
            "dates": sorted(set(dates), reverse=True),
            "last_seen": sorted(dates, reverse=True)[0] if dates else "",
            "count": len(set(dates)),
        })
    return entries


def _fmt_table(rows: list[list[str]], headers: list[str]) -> str:
    if not rows:
        return f"| {' | '.join(headers)} |\n| {' | '.join(['---'] * len(headers))} |\n| *(empty)* |{' |' * (len(headers) - 1)}\n"
    out = "| " + " | ".join(headers) + " |\n"
    out += "| " + " | ".join("---" for _ in headers) + " |\n"
    for r in rows:
        out += "| " + " | ".join(r) + " |\n"
    return out


def rebuild_index():
    ents = _collect_entries(ENTITIES)
    tops = _collect_entries(TOPICS)
    labs_raw = []
    for p in sorted(LAB.glob("*.md")):
        text = p.read_text()
        first_seen_m = re.search(r"## First seen\n([\d\-]+)", text)
        name_m = re.match(r"^# Lab: (.+)$", text.splitlines()[0] if text else "")
        updates = re.findall(r"^## Update (\d{4}-\d{2}-\d{2})", text, re.MULTILINE)
        last = updates[-1] if updates else (first_seen_m.group(1) if first_seen_m else "")
        labs_raw.append({
            "slug": p.stem,
            "name": name_m.group(1) if name_m else p.stem,
            "first_seen": first_seen_m.group(1) if first_seen_m else "",
            "last_updated": last,
        })

    ents.sort(key=lambda x: x["last_seen"], reverse=True)
    tops.sort(key=lambda x: x["last_seen"], reverse=True)
    labs_raw.sort(key=lambda x: x["last_updated"] or x["first_seen"], reverse=True)

    ent_rows = [[f"[{e['name']}](entities/{e['slug']}.md)", e["last_seen"], str(e["count"])] for e in ents]
    top_rows = [[f"[{t['name']}](topics/{t['slug']}.md)", t["last_seen"], str(t["count"])] for t in tops]
    lab_rows = [[f"[{l['name']}](lab/{l['slug']}.md)", l["first_seen"], l["last_updated"]] for l in labs_raw]

    now = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    out = (
        f"# Ra Research Archive — Index\n\n"
        f"*Auto-generated {now}. Do not edit by hand — rerun `kai ra index` or `ra_archive.py --rebuild-index` to refresh.*\n\n"
        f"## Entities ({len(ents)})\n\n"
        + _fmt_table(ent_rows, ["Name", "Last seen", "Briefs"])
        + f"\n## Topics ({len(tops)})\n\n"
        + _fmt_table(top_rows, ["Name", "Last seen", "Briefs"])
        + f"\n## Lab ({len(labs_raw)})\n\n"
        + _fmt_table(lab_rows, ["Name", "First seen", "Last updated"])
        + f"\n---\n\n"
        f"See `kai/research/README.md` for archive layout and `kai ra` CLI commands.\n"
    )
    INDEX_FILE.write_text(out)


def rebuild_trends(today: str):
    today_dt = dt.datetime.strptime(today, "%Y-%m-%d").date()
    windows = {"7d": 7, "30d": 30, "90d": 90}

    def count_in_window(dates: list[str], days: int) -> int:
        c = 0
        for d in dates:
            try:
                delta = (today_dt - dt.datetime.strptime(d, "%Y-%m-%d").date()).days
                if 0 <= delta < days:
                    c += 1
            except ValueError:
                continue
        return c

    def classify(entry: dict) -> str:
        d7 = count_in_window(entry["dates"], 7)
        d30 = count_in_window(entry["dates"], 30)
        if not entry["dates"]:
            return "—"
        # first appearance within last 7 days
        first = min(entry["dates"])
        try:
            first_delta = (today_dt - dt.datetime.strptime(first, "%Y-%m-%d").date()).days
        except ValueError:
            first_delta = 999
        if first_delta <= 7:
            return "new"
        # rising if last-7 pace is > last-30 pace
        if d7 > 0 and (d7 / 7) > (d30 / 30) * 1.25:
            return "rising"
        if d7 == 0 and d30 > 0:
            return "falling"
        return "steady"

    def build_section(label: str, folder: Path) -> str:
        rows = []
        for e in _collect_entries(folder):
            d7 = count_in_window(e["dates"], 7)
            d30 = count_in_window(e["dates"], 30)
            d90 = count_in_window(e["dates"], 90)
            rows.append([
                f"[{e['name']}]({folder.name}/{e['slug']}.md)",
                classify(e),
                str(d7), str(d30), str(d90),
                e["last_seen"],
            ])
        rows.sort(key=lambda r: (r[1] != "rising", r[1] != "new", -int(r[2] or 0), -int(r[3] or 0)))
        if not rows:
            return f"### {label}\n\n*(empty)*\n\n"
        return f"### {label}\n\n" + _fmt_table(
            rows, ["Name", "Trend", "7d", "30d", "90d", "Last seen"]
        ) + "\n"

    now = dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    out = (
        f"# Ra Research Archive — Trends\n\n"
        f"*Auto-generated {now} · reference date {today}. Counts are "
        f"briefs-mentioning-entity over the given window.*\n\n"
        f"**Legend:**\n"
        f"- **rising** — 7-day pace exceeds 30-day pace by ≥25%\n"
        f"- **falling** — mentioned in last 30 days but not in last 7\n"
        f"- **new** — first appeared within the last 7 days\n"
        f"- **steady** — consistent presence across windows\n\n"
        f"## Entities\n\n"
        + build_section("Entities", ENTITIES)
        + "## Topics\n\n"
        + build_section("Topics", TOPICS)
    )
    TRENDS_FILE.write_text(out)


# --------------------------------------------------------------------------
# brief copy + raw copy
# --------------------------------------------------------------------------

def copy_brief_pointer(date: str):
    src = NEWSLETTERS / f"{date}.md"
    if not src.exists():
        return
    dst = BRIEFS / f"{date}.md"
    # write a tiny stub that points at the real file (we don't symlink because
    # symlinks are hostile across FUSE mounts)
    stub = (
        f"# Ra brief · {date}\n\n"
        f"Canonical file: [../../../newsletters/{date}.md](../../../newsletters/{date}.md)\n\n"
        f"*(This is a pointer maintained by `ra_archive.py`. Read the canonical file.)*\n"
    )
    dst.write_text(stub)


def copy_raw_jsonl(date: str):
    # raw jsonl lives wherever gather.py's output_dir is; best-effort copy
    candidates = [
        Path(os.environ.get("HYO_INTELLIGENCE_DIR", "")) / f"{date}.jsonl",
        Path.home() / "Documents" / "Projects" / "Kai" / "intelligence" / f"{date}.jsonl",
    ]
    for src in candidates:
        if src and src.exists():
            try:
                dst = RAW / f"{date}.jsonl"
                dst.write_text(src.read_text())
            except Exception:
                pass
            return


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def archive_brief(date: str) -> int:
    brief_path = NEWSLETTERS / f"{date}.md"
    if not brief_path.exists():
        print(f"[ra_archive] no brief at {brief_path}", file=sys.stderr)
        return 1
    text = brief_path.read_text()
    meta, _body = parse_frontmatter(text)

    entities = meta.get("entities") or []
    topics = meta.get("topics") or []
    lab_items = meta.get("lab_items") or []

    if not isinstance(entities, list):
        entities = []
    if not isinstance(topics, list):
        topics = []
    if not isinstance(lab_items, list):
        lab_items = []

    for e in entities:
        if isinstance(e, dict):
            archive_entity(date, e)
    for t in topics:
        if isinstance(t, dict):
            archive_topic(date, t)
    for l in lab_items:
        if isinstance(l, dict):
            archive_lab(date, l)

    copy_brief_pointer(date)
    copy_raw_jsonl(date)
    rebuild_index()
    rebuild_trends(date)

    print(
        f"[ra_archive] {date}: archived "
        f"{len([e for e in entities if isinstance(e, dict)])} entities, "
        f"{len([t for t in topics if isinstance(t, dict)])} topics, "
        f"{len([l for l in lab_items if isinstance(l, dict)])} lab items"
    )
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--rebuild-index", action="store_true", help="only rebuild index + trends")
    args = ap.parse_args()

    date = args.date or dt.date.today().isoformat()

    if args.rebuild_index:
        rebuild_index()
        rebuild_trends(date)
        print(f"[ra_archive] rebuilt index + trends as of {date}")
        return 0

    return archive_brief(date)


if __name__ == "__main__":
    sys.exit(main())
