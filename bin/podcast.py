#!/usr/bin/env python3
"""
podcast.py — Hyo Daily Podcast Generator
BUILD-001: Morning briefing audio for commute listening

Generates a spoken MP3 from:
  1. Morning report highlights (morning-report.json)
  2. Ra top stories (latest agents/ra/output/DATE.md)
  3. Aurora brief if available (newsletters/DATE.md)

Output: website/daily/podcast-DATE.mp3 (dual-path synced)
Feed:   feed.json entry added (type: podcast)
Runs:   06:00 MT daily via launchd com.hyo.podcast

Usage:
  python3 bin/podcast.py [--date YYYY-MM-DD] [--dry-run] [--voice VOICE]
"""

import os
import sys
import json
import re
import argparse
import datetime
import subprocess
import tempfile
import shutil
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
HYO_ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
SECRETS_DIR = os.path.join(HYO_ROOT, "agents/nel/security")
WEBSITE_PRIMARY = os.path.join(HYO_ROOT, "agents/sam/website")
WEBSITE_MIRROR  = os.path.join(HYO_ROOT, "website")
RA_OUTPUT_DIR   = os.path.join(HYO_ROOT, "agents/ra/output")
NEWSLETTERS_DIR = os.path.join(HYO_ROOT, "newsletters")
MORNING_REPORT  = os.path.join(WEBSITE_PRIMARY, "data/morning-report.json")
FEED_PRIMARY    = os.path.join(WEBSITE_PRIMARY, "data/feed.json")
FEED_MIRROR     = os.path.join(WEBSITE_MIRROR, "data/feed.json")
LOG_FILE        = os.path.join(HYO_ROOT, "agents/sam/logs/podcast.log")

# OpenAI TTS settings
TTS_MODEL = "tts-1-hd"
TTS_VOICE = "onyx"   # deep, calm, professional


def log(msg: str):
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        Path(LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def load_openai_key() -> str:
    key_file = os.path.join(SECRETS_DIR, "openai.key")
    if os.path.exists(key_file):
        with open(key_file) as f:
            key = f.read().strip().encode("ascii", "ignore").decode("ascii").strip()
            if key:
                return key
    return os.environ.get("OPENAI_API_KEY", "")


def mt_now() -> datetime.datetime:
    tz = datetime.timezone(datetime.timedelta(hours=-6))  # MDT (-6)
    try:
        import zoneinfo
        tz = zoneinfo.ZoneInfo("America/Denver")
    except Exception:
        pass
    return datetime.datetime.now(tz)


def load_morning_report() -> dict:
    """Load morning-report.json and extract key highlights."""
    if not os.path.exists(MORNING_REPORT):
        return {}
    with open(MORNING_REPORT) as f:
        return json.load(f)


def load_ra_newsletter(date_str: str) -> str:
    """Load Ra's latest newsletter markdown for the given date."""
    # Try exact date first, then yesterday
    for d in [date_str, (datetime.datetime.fromisoformat(date_str) - datetime.timedelta(days=1)).strftime("%Y-%m-%d")]:
        path = os.path.join(RA_OUTPUT_DIR, f"{d}.md")
        if os.path.exists(path):
            with open(path) as f:
                return f.read()
    return ""


def load_aurora_brief(date_str: str) -> str:
    """Load Aurora daily brief for the given date."""
    for d in [date_str, (datetime.datetime.fromisoformat(date_str) - datetime.timedelta(days=1)).strftime("%Y-%m-%d")]:
        path = os.path.join(NEWSLETTERS_DIR, f"{d}.md")
        if os.path.exists(path):
            with open(path) as f:
                return f.read()
    return ""


def strip_frontmatter(md_text: str) -> str:
    """Aggressively strip all YAML/frontmatter from markdown."""
    # Strip outer ---...--- frontmatter
    md_text = re.sub(r"^\s*---\s*\n.*?\n---\s*\n", "", md_text, flags=re.DOTALL)
    # Strip fenced ```yaml ... ``` blocks at the start
    md_text = re.sub(r"^\s*```yaml\s*\n.*?\n```\s*\n", "", md_text, flags=re.DOTALL)
    # Strip remaining ```...``` code fences at start (any lang)
    md_text = re.sub(r"^\s*```\w*\s*\n.*?\n```\s*\n", "", md_text, flags=re.DOTALL)
    # Strip lone backtick lines
    md_text = re.sub(r"^\s*`{1,3}\s*$", "", md_text, flags=re.MULTILINE)
    return md_text.strip()


def extract_ra_stories(md_text: str) -> list[str]:
    """Extract The Story + Also Moving headlines from Ra newsletter."""
    stories = []
    if not md_text:
        return stories

    # Strip all frontmatter (handles nested/double frontmatter in Ra output)
    md_text = strip_frontmatter(md_text)
    # Run twice — Ra sometimes has nested frontmatter
    md_text = strip_frontmatter(md_text)

    # Extract h2 sections — skip the title (h1) and navigation sections
    skip_headings = {"ra", "hyo", "aurora", "daily brief", "also moving", "the lab", "worth sitting with"}
    sections = re.split(r"\n## ", md_text)

    for section in sections:
        lines = section.strip().split("\n")
        if not lines:
            continue
        heading = re.sub(r"^#+\s*", "", lines[0]).strip()
        # Skip boilerplate section titles
        if heading.lower() in skip_headings:
            continue
        if "·" in heading:
            # Keep after ·
            heading = heading.split("·", 1)[-1].strip()
        body_lines = []
        for l in lines[1:]:
            l = l.strip()
            if not l or l.startswith("*This isn") or l.startswith("*"):
                continue
            body_lines.append(l)
            if len(body_lines) >= 3:
                break
        body = " ".join(body_lines)
        body = strip_markdown(body)
        if body and heading and len(body) > 20:
            # Truncate to ~250 chars for natural speech
            if len(body) > 250:
                body = body[:247] + "..."
            stories.append(f"{heading} — {body}")

    return stories[:3]  # Top 3 stories


def extract_morning_highlights(report: dict) -> dict:
    """Extract key data points from morning report."""
    summary = report.get("executive_summary", {})
    agents_data = report.get("agents", {})

    highlights = {
        "system_online": summary.get("system_online", True),
        "trajectory": summary.get("growth_trajectory", "stable"),
        "trajectory_confidence": summary.get("trajectory_confidence", ""),
        "biggest_risk": summary.get("biggest_risk", ""),
        "biggest_win": summary.get("biggest_win", ""),
        "api_spend": summary.get("api_spend_today", ""),
        "agents": []
    }

    for agent_name, agent_data in agents_data.items():
        if not isinstance(agent_data, dict):
            continue
        novel = agent_data.get("novel_work", "")
        weakness = agent_data.get("weakness_identified", "")
        if novel and novel != "No novel work identified — check if improvement cycle is running.":
            highlights["agents"].append({"name": agent_name.upper(), "work": novel[:200]})
        elif weakness:
            highlights["agents"].append({"name": agent_name.upper(), "watching": weakness[:150]})

    return highlights


def strip_markdown(text: str) -> str:
    """Remove markdown formatting for clean TTS."""
    # Remove headers
    text = re.sub(r"^#{1,6}\s+", "", text, flags=re.MULTILINE)
    # Remove bold/italic
    text = re.sub(r"\*{1,3}([^*]+)\*{1,3}", r"\1", text)
    # Remove links
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    # Remove code
    text = re.sub(r"`[^`]+`", "", text)
    # Remove horizontal rules
    text = re.sub(r"^[-*_]{3,}\s*$", "", text, flags=re.MULTILINE)
    # Remove extra whitespace
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def build_podcast_script(date_str: str, highlights: dict, ra_stories: list[str], aurora_brief: str, ra_md: str = "") -> str:
    """Build the spoken podcast script."""
    # Parse date for natural reading
    dt = datetime.datetime.fromisoformat(date_str)
    date_spoken = dt.strftime("%A, %B %-d")  # e.g. "Saturday, April 18"

    traj = highlights.get("trajectory", "stable")
    traj_label = {
        "growing": "things are accelerating",
        "declining": "there's work to do",
        "stable": "things are holding steady",
    }.get(traj, traj)

    lines = []

    # ── Intro ──
    lines.append(
        f"Good morning. It's {date_spoken}. "
        "This is your Hyo daily brief."
    )
    lines.append("")

    # ── System status ──
    lines.append(
        f"System status: {'all agents online' if highlights['system_online'] else 'some agents offline'}. "
        f"Growth trajectory: {traj_label}."
    )
    if highlights.get("trajectory_confidence"):
        lines.append(f"Confidence: {highlights['trajectory_confidence']}.")
    lines.append("")

    # ── Agent highlights ──
    active_agents = [a for a in highlights.get("agents", []) if a.get("work")]
    watching_agents = [a for a in highlights.get("agents", []) if a.get("watching")]

    if active_agents:
        lines.append("What shipped overnight:")
        for a in active_agents[:3]:
            lines.append(f"  {a['name']}: {a['work']}")
        lines.append("")

    if watching_agents and not active_agents:
        lines.append("What the agents are tracking:")
        for a in watching_agents[:2]:
            lines.append(f"  {a['name']} is watching: {a['watching']}")
        lines.append("")

    # ── Biggest win / risk ──
    if highlights.get("biggest_win") and "No improvements" not in highlights["biggest_win"]:
        lines.append(f"Biggest win: {highlights['biggest_win']}.")
    if highlights.get("biggest_risk"):
        lines.append(f"Watch out for: {highlights['biggest_risk']}.")
    if highlights.get("api_spend"):
        lines.append(f"API spend today: {highlights['api_spend']}.")
    lines.append("")

    # ── Ra top stories ──
    if ra_stories:
        lines.append("From Ra, your intelligence feed:")
        for story in ra_stories[:3]:
            # Clean for speech
            story_clean = strip_markdown(story)
            if len(story_clean) > 300:
                story_clean = story_clean[:297] + "..."
            lines.append(f"  {story_clean}")
        lines.append("")

    # ── Aurora brief snippet (only if different file from Ra newsletter) ──
    if aurora_brief and aurora_brief != ra_md:
        brief_clean = strip_frontmatter(aurora_brief)
        brief_clean = strip_frontmatter(brief_clean)
        # Find first substantial paragraph (not a heading)
        paragraphs = [p.strip() for p in brief_clean.split("\n\n")
                      if p.strip() and not p.startswith("#") and len(p.strip()) > 60]
        if paragraphs:
            excerpt = strip_markdown(paragraphs[0])
            if len(excerpt) > 350:
                excerpt = excerpt[:347] + "..."
            lines.append("Aurora brief:")
            lines.append(f"  {excerpt}")
            lines.append("")

    # ── Outro ──
    lines.append(
        "That's your morning brief. "
        "Check hyo dot world slash h-q for the full report. "
        "Have a good one."
    )

    return "\n".join(lines)


def call_openai_tts(script: str, output_path: str, voice: str = TTS_VOICE, dry_run: bool = False) -> bool:
    """Call OpenAI TTS API and save MP3."""
    if dry_run:
        log(f"[DRY RUN] Would call TTS for {len(script)} chars → {output_path}")
        # Write a placeholder file so the pipeline can continue
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "wb") as f:
            f.write(b"ID3")  # Minimal placeholder
        return True

    api_key = load_openai_key()
    if not api_key:
        log("ERROR: No OpenAI API key found")
        return False

    try:
        import openai
        client = openai.OpenAI(api_key=api_key)

        log(f"Calling OpenAI TTS: model={TTS_MODEL}, voice={voice}, chars={len(script)}")

        Path(output_path).parent.mkdir(parents=True, exist_ok=True)

        with client.audio.speech.with_streaming_response.create(
            model=TTS_MODEL,
            voice=voice,
            input=script,
            response_format="mp3",
        ) as response:
            response.stream_to_file(output_path)

        size_kb = os.path.getsize(output_path) // 1024
        log(f"TTS complete: {output_path} ({size_kb}KB)")
        return True

    except ImportError:
        log("openai package not installed — attempting pip install")
        subprocess.run([sys.executable, "-m", "pip", "install", "openai", "--break-system-packages", "-q"], check=True)
        return call_openai_tts(script, output_path, voice, dry_run)
    except Exception as e:
        log(f"ERROR TTS: {e}")
        return False


def update_feed(date_str: str, duration_estimate: str = "~3 min") -> bool:
    """Add podcast entry to feed.json (both paths)."""
    ts = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-6)))
    ts_str = ts.strftime("%Y-%m-%dT%H:%M:%S-06:00")

    entry = {
        "id": f"podcast-{date_str}",
        "type": "podcast",
        "title": f"Hyo Daily Podcast — {date_str}",
        "author": "Kai",
        "authorIcon": "🎙️",
        "authorColor": "#d4a853",
        "timestamp": ts_str,
        "date": date_str,
        "sections": {
            "summary": f"Your morning brief for {date_str}. Morning report highlights + Ra top stories + Aurora brief.",
            "audioUrl": f"/daily/podcast-{date_str}.mp3",
            "duration": duration_estimate
        }
    }

    updated = 0
    for feed_path in [FEED_PRIMARY, FEED_MIRROR]:
        if not os.path.exists(feed_path):
            continue
        try:
            with open(feed_path) as f:
                feed = json.load(f)

            reports = feed.get("reports", [])

            # Dedup: remove existing entry for same date
            reports = [r for r in reports if r.get("id") != entry["id"]]

            # Prepend new entry
            reports.insert(0, entry)
            feed["reports"] = reports
            feed["lastUpdated"] = ts_str

            with open(feed_path, "w") as f:
                json.dump(feed, f, indent=2, ensure_ascii=False)
                f.write("\n")

            log(f"Feed updated: {feed_path}")
            updated += 1
        except Exception as e:
            log(f"ERROR updating feed {feed_path}: {e}")

    return updated > 0


def sync_mp3(primary_path: str, mirror_path: str):
    """Sync MP3 to mirror path."""
    try:
        Path(mirror_path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(primary_path, mirror_path)
        log(f"Synced MP3: {mirror_path}")
    except Exception as e:
        log(f"ERROR syncing MP3: {e}")


def push_to_hq(date_str: str, log_output: str):
    """Push podcast entry to HQ feed via kai push."""
    try:
        kai_push = os.path.join(HYO_ROOT, "bin/publish-to-feed.sh")
        if os.path.exists(kai_push):
            subprocess.run([
                "bash", kai_push, "podcast", f"podcast-{date_str}",
                f"Hyo Daily Podcast — {date_str}", log_output
            ], cwd=HYO_ROOT, capture_output=True, timeout=30)
            log("HQ push attempted via publish-to-feed.sh")
    except Exception as e:
        log(f"HQ push skipped: {e}")


def main():
    parser = argparse.ArgumentParser(description="Hyo Daily Podcast Generator")
    parser.add_argument("--date", default=None, help="Date YYYY-MM-DD (default: today MT)")
    parser.add_argument("--dry-run", action="store_true", help="Skip actual TTS call")
    parser.add_argument("--voice", default=TTS_VOICE, help=f"OpenAI TTS voice (default: {TTS_VOICE})")
    parser.add_argument("--script-only", action="store_true", help="Print script and exit without TTS")
    args = parser.parse_args()

    # Determine date
    if args.date:
        date_str = args.date
    else:
        now = mt_now()
        date_str = now.strftime("%Y-%m-%d")

    log(f"=== Podcast Generator: {date_str} ===")

    # Load data sources
    morning_report = load_morning_report()
    ra_newsletter_md = load_ra_newsletter(date_str)
    aurora_brief_md = load_aurora_brief(date_str)

    log(f"Sources: morning_report={'yes' if morning_report else 'no'}, "
        f"ra_newsletter={'yes' if ra_newsletter_md else 'no'}, "
        f"aurora={'yes' if aurora_brief_md else 'no'}")

    # Extract content
    highlights = extract_morning_highlights(morning_report)
    ra_stories = extract_ra_stories(ra_newsletter_md)

    log(f"Extracted: {len(highlights['agents'])} agent highlights, {len(ra_stories)} Ra stories")

    # Build script
    script = build_podcast_script(date_str, highlights, ra_stories, aurora_brief_md, ra_newsletter_md)
    word_count = len(script.split())
    # Estimate ~150 wpm for TTS
    est_minutes = round(word_count / 150, 1)

    log(f"Script: {word_count} words, est. {est_minutes} min")

    if args.script_only:
        print("\n" + "=" * 60)
        print(script)
        print("=" * 60)
        return

    # Output paths
    mp3_primary = os.path.join(WEBSITE_PRIMARY, f"daily/podcast-{date_str}.mp3")
    mp3_mirror  = os.path.join(WEBSITE_MIRROR, f"daily/podcast-{date_str}.mp3")

    # Generate TTS
    success = call_openai_tts(script, mp3_primary, args.voice, args.dry_run)
    if not success:
        log("FAILED: TTS generation failed")
        sys.exit(1)

    # Sync to mirror
    if not args.dry_run:
        sync_mp3(mp3_primary, mp3_mirror)

    # Update feed.json
    update_feed(date_str, f"~{est_minutes} min")

    # Commit and push
    if not args.dry_run:
        try:
            mp3_rel_primary = os.path.relpath(mp3_primary, HYO_ROOT)
            mp3_rel_mirror  = os.path.relpath(mp3_mirror, HYO_ROOT)
            subprocess.run([
                "git", "add",
                mp3_rel_primary,
                mp3_rel_mirror,
                "agents/sam/website/data/feed.json",
                "website/data/feed.json"
            ], cwd=HYO_ROOT, capture_output=True)
            subprocess.run([
                "git", "commit", "-m",
                f"podcast: daily brief {date_str} ({est_minutes}min, voice={args.voice})"
            ], cwd=HYO_ROOT, capture_output=True)
            subprocess.run(["git", "push", "origin", "main"],
                           cwd=HYO_ROOT, capture_output=True, timeout=60)
            log("Committed and pushed")
        except Exception as e:
            log(f"Git operations: {e}")

    log(f"=== Podcast complete: podcast-{date_str}.mp3 ===")
    print(f"PODCAST_URL=/daily/podcast-{date_str}.mp3")


if __name__ == "__main__":
    main()
