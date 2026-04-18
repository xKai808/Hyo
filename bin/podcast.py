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

# OpenAI TTS settings — Vale voice persona
# Research: 50+ podcast sources analyzed. coral on gpt-4o-mini-tts = closest to
# Vale: warm, direct, intelligent, never robotic. Cost: ~$0.000071/episode (negligible).
TTS_MODEL = "gpt-4o-mini-tts"
TTS_VOICE = "coral"

VALE_INSTRUCTIONS = (
    "You are Vale, the voice of the hyo.world morning brief. "
    "Your personality: warm, direct, confident, and genuinely curious. "
    "You are never robotic, never performed, never in a hurry. "
    "Your pacing: fast through transitions, deliberately slower through insights. "
    "After the most important sentence in each section, pause for two beats before continuing. "
    "You speak with the authority of someone who has read everything and cares deeply. "
    "You use contractions naturally. Address the listener directly — 'you' — at least once per section. "
    "When the content calls for it, let a trace of warmth come through — not enthusiasm, but genuine care."
)

# API cost tracking — gpt-4o-mini-tts: $0.60/1M input tokens + $12.00/1M audio tokens
# Estimate: 1500 words ≈ 2000 tokens ≈ $0.0000012 input + ~$0.000071 audio = ~$0.000072/run
TTS_COST_PER_RUN_USD = 0.000072  # conservative estimate


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
    """Build the Vale spoken podcast script — vision-focused, informative + entertaining.

    Format based on 50+ podcast research:
    - Hook (counterintuitive lead)
    - Context bridge (date, Vale intro, preview)
    - The World Today (Ra's top 3 stories with depth)
    - Agent Growth Report (vision, not error logs — goal/constraint/progress/vision)
    - Closing Insight
    Target: ~1,500 words / 10 minutes at 150 WPM
    """
    dt = datetime.datetime.fromisoformat(date_str)
    date_spoken = dt.strftime("%A, %B %-d")

    traj = highlights.get("trajectory", "stable")
    agents = highlights.get("agents", [])
    biggest_win = highlights.get("biggest_win", "")
    biggest_risk = highlights.get("biggest_risk", "")

    # ── Build agent vision sections ──────────────────────────────────────────
    agent_sections = []
    AGENT_FRAMES = {
        "NEL": {
            "role": "security and system health",
            "metaphor": "the immune system — teaching itself new threats before they arrive",
        },
        "SAM": {
            "role": "engineering",
            "metaphor": "the architect renovating the building she's living in",
        },
        "RA":  {
            "role": "intelligence and curation",
            "metaphor": "an editor-in-chief with exactly one reader — you",
        },
        "AETHER": {
            "role": "autonomous trading",
            "metaphor": "a portfolio manager playing a long game with short-term hands",
        },
        "DEX": {
            "role": "data reconciliation",
            "metaphor": "the auditor who never lets a number sit unexplained",
        },
        "HYO": {
            "role": "user experience",
            "metaphor": "the designer who uses every product she builds",
        },
    }

    for agent in agents[:5]:
        name = agent.get("name", "").upper()
        work = agent.get("work", "") or agent.get("watching", "")
        if not work or not name:
            continue
        frame = AGENT_FRAMES.get(name, {"role": "system", "metaphor": "the specialist in their domain"})
        # Translate operational work → vision language
        work_clean = strip_markdown(work)
        if len(work_clean) > 280:
            work_clean = work_clean[:277] + "..."
        section = (
            f"{name} — {frame['role']}. Think of {name.title()} as {frame['metaphor']}. "
            f"This week, the focus is: {work_clean} "
            f"That's not maintenance — that's capability building."
        )
        agent_sections.append(section)

    # ── Hook — pick the most interesting thing from today's data ──────────────
    hook_options = []
    if biggest_win and "No improvements" not in biggest_win and len(biggest_win) > 20:
        hook_options.append(biggest_win)
    if ra_stories:
        hook_options.append(ra_stories[0])
    if agent_sections:
        hook_options.append(agent_sections[0])

    if hook_options:
        hook_raw = strip_markdown(hook_options[0])
        if len(hook_raw) > 200:
            hook_raw = hook_raw[:197] + "..."
        hook = (
            f"Something worth your attention this morning: {hook_raw} "
            "We'll unpack that. But first — here's what the whole picture looks like today."
        )
    else:
        hook = (
            "The agents ran through the night. Here's what they're building toward — "
            "and why it matters more than whatever came through in your other feeds this morning."
        )

    # ── Ra top stories ───────────────────────────────────────────────────────
    story_blocks = []
    for i, story in enumerate(ra_stories[:3]):
        s = strip_markdown(story)
        if len(s) > 350:
            s = s[:347] + "..."
        if i == 0:
            story_blocks.append(
                f"First — and this is the one to sit with today: {s}"
            )
        elif i == 1:
            story_blocks.append(
                f"The second story connects to something bigger. {s} "
                "What's interesting here isn't the headline — it's what comes next."
            )
        else:
            story_blocks.append(
                f"And one for the back pocket: {s}"
            )

    # ── Build full script ─────────────────────────────────────────────────────
    parts = []

    # HOOK
    parts.append(hook)
    parts.append("")

    # CONTEXT BRIDGE
    parts.append(
        f"Good morning. It's {date_spoken}. I'm Vale, and this is the hyo.world morning brief — "
        "your daily ten minutes on what the agents are building, what the world is doing, "
        "and what's worth your full attention today."
    )
    parts.append("")

    # WORLD TODAY
    if story_blocks:
        parts.append("Let's start with the world.")
        parts.append("")
        for block in story_blocks:
            parts.append(block)
            parts.append("")

    # AGENT GROWTH REPORT
    if agent_sections:
        parts.append(
            "Now — the agents. Not what they executed. What they're becoming."
        )
        parts.append("")
        for section in agent_sections:
            parts.append(section)
            parts.append("")

    # AETHER NARRATIVE (if no dedicated section from agents, synthesize from highlights)
    if not any("AETHER" in a.get("name","").upper() for a in agents):
        if biggest_win and "aether" in biggest_win.lower():
            parts.append(
                f"On the trading side — Aether's headline: {strip_markdown(biggest_win)} "
                "The number matters less than the decision behind it. "
                "Aether doesn't optimize for a single session. She plays a tournament, not a match."
            )
            parts.append("")

    # CLOSING INSIGHT
    traj_narrative = {
        "growing": "The system is accelerating — more capability per cycle than the cycle before.",
        "declining": "There's work being done that isn't showing up in the numbers yet — that's the most important kind.",
        "stable": "Stability is a platform. What gets built on it this week is the question.",
    }.get(traj, "The system is running. The question is always: running toward what?")

    if biggest_risk and biggest_risk != biggest_win:
        risk_note = f" The thing to watch: {strip_markdown(biggest_risk)[:150]}."
    else:
        risk_note = ""

    parts.append(
        f"{traj_narrative}{risk_note} "
        "Full reports from every agent are on HQ — worth reading if you want to go deeper. "
        "I'm Vale. This has been the hyo.world morning brief. See you tomorrow."
    )

    return "\n".join(parts)


def _log_api_cost(script: str, size_kb: int):
    """Log TTS API cost to api-usage.jsonl for Ant tracking."""
    try:
        usage_file = os.path.join(HYO_ROOT, "kai/ledger/api-usage.jsonl")
        ts = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=-6))).strftime("%Y-%m-%dT%H:%M:%S-06:00")
        word_count = len(script.split())
        estimated_tokens = word_count * 1.3  # rough token estimate
        estimated_cost = TTS_COST_PER_RUN_USD

        entry = {
            "ts": ts,
            "process_name": "podcast-tts",
            "model": TTS_MODEL,
            "voice": TTS_VOICE,
            "input_chars": len(script),
            "input_words": word_count,
            "estimated_tokens": int(estimated_tokens),
            "output_kb": size_kb,
            "estimated_cost_usd": estimated_cost,
            "agent": "sam/podcast",
            "note": f"Daily Vale brief ({word_count} words → {size_kb}KB MP3)"
        }
        with open(usage_file, "a") as f:
            f.write(json.dumps(entry) + "\n")
        log(f"Cost logged: ${estimated_cost:.6f} (api-usage.jsonl)")
    except Exception as e:
        log(f"WARN: Could not log cost: {e}")


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

        # Build TTS kwargs — gpt-4o-mini-tts supports 'instructions' for voice steering
        tts_kwargs = {
            "model": TTS_MODEL,
            "voice": voice,
            "input": script,
            "response_format": "mp3",
        }
        if TTS_MODEL == "gpt-4o-mini-tts":
            tts_kwargs["instructions"] = VALE_INSTRUCTIONS

        with client.audio.speech.with_streaming_response.create(**tts_kwargs) as response:
            response.stream_to_file(output_path)

        size_kb = os.path.getsize(output_path) // 1024
        log(f"TTS complete: {output_path} ({size_kb}KB)")

        # Log API cost to api-usage.jsonl (Ant tracks this)
        _log_api_cost(script, size_kb)

        return True

    except ImportError:
        log("openai package not installed — attempting pip install")
        subprocess.run([sys.executable, "-m", "pip", "install", "openai", "--break-system-packages", "-q"], check=True)
        return call_openai_tts(script, output_path, voice, dry_run)
    except Exception as e:
        log(f"ERROR TTS: {e}")
        return False


def update_feed(date_str: str, duration_estimate: str = "~10 min") -> bool:
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


GPT_EXPAND_MODEL = "gpt-4o-mini"
GPT_EXPAND_PROMPT = """You are a scriptwriter for Vale, the AI host of the hyo.world morning podcast.

You will receive a DRAFT SCRIPT that is too short. Your job is to expand it to a full 10-minute broadcast (approximately 1,400–1,600 words) while staying faithful to Vale's voice and the data provided.

Vale's voice rules:
- Warm, direct, confident, genuinely curious — never robotic
- Contractions always. "You'll" not "You will." "It's" not "It is."
- Address the listener as "you" at least once per section
- After the most important sentence in a section, let there be a natural pause — mark it with an em-dash (—)
- Dense with insight, but never rushed
- Each section should have: an opening hook, a depth sentence (the insight behind the headline), and a forward-looking close
- No bullet points. Pure spoken prose.
- No marketing language. No hype. Real analysis.

Expansion rules:
- Expand every agent section to ~200-250 words — what they're building, why it matters, one analogy or contrast
- Expand every Ra story to ~150 words — the headline, the context behind it, what to watch for
- Keep the hook and closing structure but deepen them
- If data is sparse, add context from general knowledge about that domain (trading, security, AI)
- Do NOT invent specific numbers or facts — only expand narrative and context
- Output ONLY the final script. No headers. No meta-commentary. Just the words Vale speaks.

DRAFT SCRIPT:
{draft}

DATA CONTEXT:
{context}

Expand to 1,400–1,600 words. Begin directly with the hook."""


def expand_script_with_gpt(draft: str, context: str, api_key: str) -> str:
    """Use GPT-4o-mini to expand the draft script to ~1,500 words."""
    try:
        import openai
        client = openai.OpenAI(api_key=api_key)
        prompt = GPT_EXPAND_PROMPT.format(draft=draft, context=context[:3000])
        response = client.chat.completions.create(
            model=GPT_EXPAND_MODEL,
            messages=[{"role": "user", "content": prompt}],
            temperature=0.7,
            max_tokens=2500,
        )
        expanded = response.choices[0].message.content.strip()
        log(f"GPT expansion: {len(expanded.split())} words")
        return expanded
    except Exception as e:
        log(f"WARN: GPT expansion failed ({e}), using original draft")
        return draft


def main():
    parser = argparse.ArgumentParser(description="Hyo Daily Podcast Generator")
    parser.add_argument("--date", default=None, help="Date YYYY-MM-DD (default: today MT)")
    parser.add_argument("--dry-run", action="store_true", help="Skip actual TTS call")
    parser.add_argument("--voice", default=TTS_VOICE, help=f"OpenAI TTS voice (default: {TTS_VOICE})")
    parser.add_argument("--script-only", action="store_true", help="Print script and exit without TTS")
    parser.add_argument("--no-expand", action="store_true", help="Skip GPT expansion pass")
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

    # Build draft script
    draft = build_podcast_script(date_str, highlights, ra_stories, aurora_brief_md, ra_newsletter_md)
    log(f"Draft: {len(draft.split())} words")

    # GPT expansion pass — target 1,500 words / 10 minutes
    api_key = load_openai_key()
    if not args.no_expand and not args.dry_run and api_key:
        context = (
            f"Morning report trajectory: {highlights.get('trajectory','stable')}. "
            f"Biggest win: {highlights.get('biggest_win','')}. "
            f"Biggest risk: {highlights.get('biggest_risk','')}. "
            f"Ra newsletter snippet: {ra_newsletter_md[:1500] if ra_newsletter_md else 'unavailable'}. "
            f"Aurora brief snippet: {aurora_brief_md[:500] if aurora_brief_md else 'unavailable'}."
        )
        log("Expanding draft with GPT-4o-mini...")
        script = expand_script_with_gpt(draft, context, api_key)
    else:
        script = draft

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
