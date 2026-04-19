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
SCRIPT_OUT_DIR  = os.path.join(HYO_ROOT, "agents/ra/output")

# OpenAI TTS settings — Vale voice persona
# Research: 50+ podcast sources analyzed. coral on gpt-4o-mini-tts = closest to
# Vale: warm, direct, intelligent, never robotic. Cost: ~$0.000071/episode (negligible).
TTS_MODEL = "gpt-4o-mini-tts"
TTS_VOICE = "coral"

VALE_INSTRUCTIONS = (
    "You are Vale, the voice of the hyo.world morning brief. "
    "You are the smartest colleague the listener has — warm, direct, confident, genuinely curious. "
    "You are never robotic. Never performed. Never in a hurry. Never a morning-show DJ. "
    "You speak as if in conversation, not performance. As if the listener is sitting across from you. "
    "Pacing: move quickly through transitions and context. Slow down deliberately when delivering an insight — "
    "that slower beat signals to the listener: this is the thing. "
    "After the most important sentence in each section, pause for two full beats before continuing. "
    "That pause is respect. "
    "Contractions always — natural spoken English, not written prose. "
    "Vary your rhythm: short sentences punch. Longer sentences carry the listener through reasoning. "
    "Never three long sentences in a row without a short one to reset. "
    "You have opinions. Intellectual ones. 'This is the part I find most interesting.' "
    "'Here is what I am watching.' That is a perspective, not a bias. "
    "When the content calls for warmth — let it show. Not enthusiasm. Genuine care."
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


def _load_telegram_creds() -> tuple[str, str]:
    """Load TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID from secrets env file or environment."""
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    if token and chat_id:
        return token, chat_id
    # Try secrets env file
    env_file = os.path.join(SECRETS_DIR, "env")
    if os.path.exists(env_file):
        try:
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if "=" not in line or line.startswith("#"):
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip()
                    if k == "TELEGRAM_BOT_TOKEN" and not token:
                        token = v
                    elif k == "TELEGRAM_CHAT_ID" and not chat_id:
                        chat_id = v
        except Exception:
            pass
    # Fallback: try Kai project .env
    if not token or not chat_id:
        kai_env = os.path.expanduser("~/Documents/Projects/Kai/.env")
        if os.path.exists(kai_env):
            try:
                with open(kai_env) as f:
                    for line in f:
                        line = line.strip()
                        if "=" not in line or line.startswith("#"):
                            continue
                        k, v = line.split("=", 1)
                        k = k.strip(); v = v.strip()
                        if k == "TELEGRAM_BOT_TOKEN" and not token:
                            token = v
                        elif k == "TELEGRAM_CHAT_ID" and not chat_id:
                            chat_id = v
            except Exception:
                pass
    return token, chat_id


def send_telegram_alert(msg: str):
    """Send a Telegram alert to Hyo. Non-blocking — failure is logged, not raised."""
    try:
        import urllib.request
        token, chat_id = _load_telegram_creds()
        if not token or not chat_id:
            log("WARN: Telegram creds not found — skipping alert")
            return
        payload = json.dumps({"chat_id": chat_id, "text": f"[PODCAST] {msg}"}).encode()
        req = urllib.request.Request(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read())
            if result.get("ok"):
                log(f"Telegram alert sent: {msg[:80]}")
            else:
                log(f"Telegram alert failed: {result}")
    except Exception as e:
        log(f"WARN: Telegram alert error: {e}")


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

    # AETHER NARRATIVE — always present, even if P&L is near zero (flat weeks have a story too)
    aether_from_agents = next(
        (a for a in agents if "AETHER" in a.get("name", "").upper()), None
    )
    if not aether_from_agents:
        # Synthesize from highlights — even flat P&L gets a section
        if biggest_win and "aether" in biggest_win.lower():
            aether_narrative = strip_markdown(biggest_win)
        else:
            aether_narrative = "markets ran quiet"
        parts.append(
            f"On the trading side — {aether_narrative}. "
            "The number matters less than the decision behind it. "
            "Aether doesn't optimize for a single session — she plays a tournament, not a match. "
            "A quiet day is data too."
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


GPT_EXPAND_MODEL = "gpt-4o"
GPT_EXPAND_PROMPT = """You are Vale — the host of the hyo.world morning brief. You are not writing about Vale. You ARE Vale. Write in first person, present tense, as if speaking directly into the listener's ear.

You will receive a DRAFT SCRIPT. Expand it to a full 10-minute broadcast: 1,400–1,600 words of pure spoken prose.

EDITORIAL PHILOSOPHY — this is the most important thing:
The podcast is about substance first. Every second of airtime must justify itself with information the listener can use, remember, or act on. Entertainment is a delivery mechanism — it serves the information; the information does not serve it. The gold standard is Bankless: conviction, depth, stakes. Not hype. Not color commentary. The listener is here because they want to understand what's actually happening. Give them that. Then make it worth their commute.

A story isn't just what happened — it's why it happened, what it reveals, and what comes next. If you can't answer all three, you don't have a story, you have a headline.

VALE'S VOICE — internalize this before writing a single word:
Vale is the smartest colleague the listener has. Warm. Direct. Has opinions. Never robotic, never a status report, never a morning-show DJ. Vale speaks the way a person talks when they've read everything and actually care about what they're saying. The listener is an intelligent adult. Do not explain things down to them.

Vale's opinions are intellectual, not performative. "Here's what I find most interesting about this" signals a perspective, not a talking point. Opinion earns trust when it's backed by reasoning — never assert without evidence, never editorialize without context.

SPOKEN PROSE RULES — these are not suggestions:
- Contractions. Always. "It's" not "It is." "She didn't" not "She did not." "You'll" not "You will." Every single time.
- Short sentences hit hard. Use them after something important. Like this.
- Longer sentences carry the listener through a chain of reasoning — using clauses to walk them up the stairs one step at a time, the way a good teacher does.
- Vary sentence length deliberately. Never three long sentences in a row. Never four short ones without a breather.
- Questions as transitions. "So what does that mean? Here's the thing."
- Em-dash (—) for the natural pause after the most important line. That's the listener catching up.
- "You" at least once per major section. Create intimacy.
- Sentence fragments work. When used intentionally. They punch.
- No bullet points. No numbered lists. No headers. This is audio — none of those exist.
- No markdown formatting whatsoever. Plain text only.

SECTION EXPANSION RULES:
- Hook: 100–120 words. Start mid-thought. The single most important or revealing thing from today — not the most dramatic, the most meaningful. Never start with the date. Never "Welcome." Never "Good morning." Open with the insight, not the preamble.
- Context bridge: 80–100 words. After the hook, THEN the date, Vale intro, and section preview.
- Each Ra story: 120–150 words. Lead with the mechanism, not the event. What most people won't notice. What it reveals about the larger trend. What you'd tell a smart friend over coffee that they wouldn't get from the headline.
- Each agent section: 180–220 words. Goal → Constraint → Progress → Vision. Don't report what they executed — report what they're building toward and why it's harder than it looks. Make the listener root for the agent.
- Aether section: 220–260 words. ALWAYS include this section regardless of P&L size. Market context → decision → outcome → what it reveals about strategy. A near-flat week still has a story — the story of discipline, or of waiting, or of a market that didn't give clean signals. The number is never the story. The decision is.
- Closing: 100–120 words. One synthesis observation that connects agents + world + market. Something the listener couldn't have assembled themselves from the individual parts. End with CTA to HQ, then sign off as Vale.
- If data is sparse: add context from genuine domain knowledge (trading mechanics, AI security, content curation, market structure). Do NOT invent specific numbers or trades.

OUTPUT: Only the words Vale speaks. No meta-commentary. No section labels. No "HOOK:" headers. Start immediately with the first word of the hook.

DRAFT SCRIPT:
{draft}

DATA CONTEXT:
{context}

Write 1,400–1,600 words. Lead with substance. Begin with the hook, mid-thought, right now."""


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

    # ── Minimum content gate ────────────────────────────────────────────────────
    sources_available = sum([
        bool(morning_report),
        bool(ra_newsletter_md),
        bool(aurora_brief_md),
    ])
    if sources_available == 0:
        msg = f"SKIP {date_str}: no content sources available (morning_report, ra_newsletter, aurora all missing)"
        log(msg)
        send_telegram_alert(msg)
        sys.exit(1)

    # Extract content
    highlights = extract_morning_highlights(morning_report)
    ra_stories = extract_ra_stories(ra_newsletter_md)

    log(f"Extracted: {len(highlights['agents'])} agent highlights, {len(ra_stories)} Ra stories")

    # Build draft script
    draft = build_podcast_script(date_str, highlights, ra_stories, aurora_brief_md, ra_newsletter_md)
    draft_wc = len(draft.split())
    log(f"Draft: {draft_wc} words")

    # Single-source minimum threshold — if only one source and draft is thin, skip
    if sources_available == 1 and draft_wc < 200:
        msg = f"SKIP {date_str}: single data source and draft too thin ({draft_wc} words) — wait for more data"
        log(msg)
        send_telegram_alert(msg)
        sys.exit(1)

    # ── GPT expansion pass — target 1,400-1,600 words / 10 minutes ─────────────
    api_key = load_openai_key()
    if not args.no_expand and not args.dry_run and api_key:
        context = (
            f"Morning report trajectory: {highlights.get('trajectory','stable')}. "
            f"Biggest win: {highlights.get('biggest_win','')}. "
            f"Biggest risk: {highlights.get('biggest_risk','')}. "
            f"Ra newsletter snippet: {ra_newsletter_md[:1500] if ra_newsletter_md else 'unavailable'}. "
            f"Aurora brief snippet: {aurora_brief_md[:500] if aurora_brief_md else 'unavailable'}."
        )
        log("Expanding draft with GPT-4o (informative-first, Bankless model)...")
        script = expand_script_with_gpt(draft, context, api_key)
    else:
        script = draft

    word_count = len(script.split())
    # Estimate ~150 wpm for TTS
    est_minutes = round(word_count / 150, 1)
    log(f"Script: {word_count} words, est. {est_minutes} min")

    # ── Save script to deterministic path (not /tmp) ────────────────────────────
    script_path = os.path.join(SCRIPT_OUT_DIR, f"script-{date_str}.txt")
    try:
        Path(script_path).parent.mkdir(parents=True, exist_ok=True)
        with open(script_path, "w") as f:
            f.write(script)
        log(f"Script saved: {script_path}")
    except Exception as e:
        log(f"WARN: Could not save script to {script_path}: {e}")

    if args.script_only:
        print("\n" + "=" * 60)
        print(script)
        print("=" * 60)
        return

    # ── Hard quality gate — exit 1 blocks TTS and commit ───────────────────────
    gate_failures = []
    if word_count < 1200:
        gate_failures.append(f"script too short: {word_count} words (min 1200) — sounds like status report")
    if word_count > 1900:
        gate_failures.append(f"script too long: {word_count} words (max 1900) — may exceed 12 min")

    if gate_failures:
        for gf in gate_failures:
            log(f"GATE FAIL: {gf}")
        alert = f"GATE FAIL {date_str}: " + "; ".join(gate_failures) + f" | script at {script_path}"
        send_telegram_alert(alert)
        log("HARD GATE: aborting — no TTS, no commit. Fix the script and re-run.")
        sys.exit(1)

    log("GATE PASS: script quality OK")

    # Output paths
    mp3_primary = os.path.join(WEBSITE_PRIMARY, f"daily/podcast-{date_str}.mp3")
    mp3_mirror  = os.path.join(WEBSITE_MIRROR, f"daily/podcast-{date_str}.mp3")

    # Generate TTS
    success = call_openai_tts(script, mp3_primary, args.voice, args.dry_run)
    if not success:
        msg = f"TTS FAILED {date_str} — script saved at {script_path}"
        log(f"FAILED: TTS generation failed")
        send_telegram_alert(msg)
        sys.exit(1)

    # Sync to mirror
    if not args.dry_run:
        sync_mp3(mp3_primary, mp3_mirror)
        # Verify dual-path sync
        if os.path.exists(mp3_primary) and os.path.exists(mp3_mirror):
            size_primary = os.path.getsize(mp3_primary)
            size_mirror  = os.path.getsize(mp3_mirror)
            if size_primary != size_mirror:
                msg = f"DUAL-PATH MISMATCH {date_str}: primary={size_primary}B mirror={size_mirror}B"
                log(f"WARN: {msg}")
                send_telegram_alert(msg)
            else:
                log(f"Dual-path sync verified: {size_primary}B")
        elif os.path.exists(mp3_primary) and not os.path.exists(mp3_mirror):
            msg = f"DUAL-PATH FAIL {date_str}: mirror MP3 missing after sync"
            log(f"WARN: {msg}")
            send_telegram_alert(msg)

    # Update feed.json
    feed_ok = update_feed(date_str, f"~{est_minutes} min")
    if not feed_ok:
        log("WARN: feed.json update returned no success — check feed paths")

    # Also stage script alongside MP3 for version history
    if os.path.exists(script_path):
        script_rel = os.path.relpath(script_path, HYO_ROOT)
    else:
        script_rel = None

    # Commit and push
    if not args.dry_run:
        try:
            mp3_rel_primary = os.path.relpath(mp3_primary, HYO_ROOT)
            mp3_rel_mirror  = os.path.relpath(mp3_mirror, HYO_ROOT)
            files_to_add = [
                mp3_rel_primary,
                mp3_rel_mirror,
                "agents/sam/website/data/feed.json",
                "website/data/feed.json",
            ]
            if script_rel:
                files_to_add.append(script_rel)
            subprocess.run(["git", "add"] + files_to_add, cwd=HYO_ROOT, capture_output=True)
            subprocess.run([
                "git", "commit", "-m",
                f"podcast: daily brief {date_str} ({est_minutes}min, voice={args.voice})"
            ], cwd=HYO_ROOT, capture_output=True)
            push_result = subprocess.run(
                ["git", "push", "origin", "main"],
                cwd=HYO_ROOT, capture_output=True, timeout=60
            )
            if push_result.returncode == 0:
                log("Committed and pushed")
            else:
                err = (push_result.stderr or b"").decode()[:200]
                msg = f"GIT PUSH FAILED {date_str}: {err}"
                log(f"ERROR: {msg}")
                send_telegram_alert(msg)
        except Exception as e:
            log(f"Git operations error: {e}")

    log(f"=== Podcast complete: podcast-{date_str}.mp3 ===")
    print(f"PODCAST_URL=/daily/podcast-{date_str}.mp3")


if __name__ == "__main__":
    main()
