#!/usr/bin/env python3
"""
aurora_public.py — per-subscriber Aurora generator.

Reads today's shared gather records (gather.py output), then for every
active subscriber in subscribers.jsonl, filters the gather down to
topics they care about, composes a personalized prompt (voice/depth/
length/freetext), calls the same LLM backends synthesize.py uses, and
writes one brief per subscriber to:

    newsletter/out/public/<date>/<sub_id>.md

Then the pipeline wrapper (aurora_public.sh) renders each markdown to
HTML and hands them to send_email.py.

This generator does NOT write to the research archive. The archive is
still authored exclusively by Ra (the Hyo-voice internal brief). Aurora
Public *reads* the archive for trend pulse and lab-library context but
never writes back.

Stdlib only. Reuses synthesize.py's backend functions directly.

Usage:
    python3 aurora_public.py                       # generate for today, all active subs
    python3 aurora_public.py --date 2026-04-12
    python3 aurora_public.py --sub sub_abc123      # only one subscriber (testing)
    python3 aurora_public.py --dry-run             # print plan, no LLM calls
    python3 aurora_public.py --preview             # use a hardcoded fake profile

Env vars:
    HYO_SUBSCRIBERS_FILE  override subscribers.jsonl path
    HYO_PUBLIC_OUT_DIR    override briefs output dir
    HYO_INTELLIGENCE_DIR  override gather jsonl location (same as synthesize.py)
    (Plus any of the backend-specific API keys synthesize.py respects.)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import time
from pathlib import Path

# We pull in synthesize.py's helpers directly so this file can stay small.
HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import synthesize  # type: ignore  # noqa: E402

# ---------------------------------------------------------------------------
# paths
# ---------------------------------------------------------------------------

HYO_ROOT = Path(
    os.environ.get("HYO_ROOT", HERE.parent)
).resolve()
SUBSCRIBERS = Path(
    os.environ.get("HYO_SUBSCRIBERS_FILE", HERE / "subscribers.jsonl")
)
PUBLIC_OUT = Path(
    os.environ.get("HYO_PUBLIC_OUT_DIR", HERE / "out" / "public")
)
INTELLIGENCE = Path(
    os.environ.get("HYO_INTELLIGENCE_DIR", Path.home() / "Documents" / "Projects" / "Kai" / "intelligence")
)
RESEARCH = HYO_ROOT / "kai" / "research"
CONTEXT_FILE = RESEARCH / ".context.md"

# ---------------------------------------------------------------------------
# topic → keyword map
# ---------------------------------------------------------------------------
#
# The gather stage pulls from a wide net; each subscriber's topics resolve to
# a set of regex keywords we match against record titles/summaries/tags. A
# record matches a subscriber if any of its topics' keywords hit.
#
# Keep this dictionary the single source of truth — it mirrors the topic
# taxonomy documented in docs/aurora-public.md.

TOPIC_KEYWORDS: dict[str, list[str]] = {
    "politics":       ["congress", "senate", "president", "election", "policy", "legislation", "vote", "supreme court", "DOJ", "white house"],
    "finance":        ["earnings", "IPO", "markets", "hedge fund", "bank", "wall street", "finance"],
    "macro":          ["Fed", "FOMC", "inflation", "CPI", "GDP", "interest rate", "jobs report", "unemployment", "ECB", "yield"],
    "stocks":         ["S&P", "NASDAQ", "stock", "shares", "ticker", "equity", "dividend"],
    "crypto":         ["bitcoin", "BTC", "ethereum", "ETH", "crypto", "stablecoin", "defi", "web3", "solana"],
    "startups":       ["startup", "seed round", "series A", "series B", "venture", "VC", "founder", "acquisition"],
    "tech":           ["software", "hardware", "chip", "platform", "developer", "open source", "github"],
    "ai":             ["AI", "LLM", "model", "neural", "agent", "Claude", "GPT", "OpenAI", "Anthropic", "Gemini", "Grok", "llama", "transformer", "fine-tune"],
    "social-media":   ["twitter", "x.com", "instagram", "tiktok", "threads", "bluesky", "meta", "social"],
    "fashion":        ["fashion", "runway", "haute couture", "streetwear", "designer", "Vogue", "Balenciaga", "Gucci", "Prada"],
    "gossip":         ["rumor", "dating", "split", "breakup", "scandal", "celebrity", "spotted"],
    "celebrity":      ["actor", "actress", "celebrity", "star", "red carpet", "oscars", "grammys", "cannes"],
    "film-and-tv":    ["film", "movie", "TV", "streaming", "Netflix", "HBO", "trailer", "box office", "series", "episode"],
    "music":          ["album", "song", "single", "billboard", "grammy", "tour", "concert", "festival"],
    "books":          ["book", "novel", "author", "memoir", "publishing", "bestseller", "Pulitzer"],
    "gaming":         ["game", "console", "steam", "indie dev", "E3", "xbox", "playstation", "nintendo", "esports", "speedrun"],
    "sports":         ["NFL", "NBA", "MLB", "NHL", "FIFA", "premier league", "champion", "playoff", "score"],
    "health":         ["health", "disease", "FDA", "trial", "vaccine", "nutrition", "medicine", "hospital", "doctor"],
    "fitness":        ["workout", "training", "marathon", "fitness", "strength", "gym"],
    "food":           ["restaurant", "chef", "recipe", "cuisine", "food", "Michelin", "dining"],
    "travel":         ["travel", "airline", "flight", "hotel", "destination", "tourism", "passport"],
    "science":        ["research", "study", "discovery", "physics", "biology", "chemistry", "quantum", "paper", "journal"],
    "climate":        ["climate", "emissions", "carbon", "renewable", "solar", "EV", "battery", "warming"],
    "space":          ["NASA", "SpaceX", "rocket", "satellite", "orbit", "moon", "mars", "telescope"],
    "design":         ["design", "UI", "UX", "product design", "Figma", "typography"],
    "architecture":   ["building", "architect", "skyscraper", "urban design", "pritzker"],
    "real-estate":    ["real estate", "housing", "mortgage", "rent", "property", "homebuyer"],
    "labor":          ["layoff", "hiring", "strike", "union", "wages", "jobs", "labor", "workforce"],
    "culture-wars":   ["ban", "protest", "controversy", "cancel", "identity", "debate"],
    "education":      ["school", "university", "tuition", "student", "teacher", "education", "curriculum"],
}

def _compile_keywords(topics: list[str]) -> list[re.Pattern]:
    pats: list[re.Pattern] = []
    seen = set()
    for t in topics:
        for kw in TOPIC_KEYWORDS.get(t, []):
            if kw.lower() in seen:
                continue
            seen.add(kw.lower())
            pats.append(re.compile(rf"\b{re.escape(kw)}\b", re.IGNORECASE))
    return pats

# ---------------------------------------------------------------------------
# subscriber loading
# ---------------------------------------------------------------------------

def load_subscribers() -> list[dict]:
    if not SUBSCRIBERS.exists():
        return []
    out: list[dict] = []
    with SUBSCRIBERS.open() as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def save_subscribers(subs: list[dict]) -> None:
    tmp = SUBSCRIBERS.with_suffix(".jsonl.tmp")
    with tmp.open("w") as f:
        for s in subs:
            f.write(json.dumps(s) + "\n")
    tmp.replace(SUBSCRIBERS)


# ---------------------------------------------------------------------------
# filter + rank gather records for a subscriber
# ---------------------------------------------------------------------------

def filter_records_for_sub(records: list[dict], sub: dict) -> list[dict]:
    topics = sub.get("interests", {}).get("topics", [])
    if not topics:
        return []
    pats = _compile_keywords(topics)
    if not pats:
        return []
    hits: list[tuple[int, dict]] = []
    for rec in records:
        blob = " ".join(str(rec.get(f, "")) for f in ("title", "summary", "tags", "source"))
        score = 0
        for p in pats:
            if p.search(blob):
                score += 1
        if score > 0:
            # combine keyword-match score with gather's native score
            native = float(rec.get("score", 0)) or 0.0
            composite = (score * 10) + native
            hits.append((composite, rec))
    hits.sort(key=lambda x: x[0], reverse=True)
    return [r for _, r in hits[:40]]  # top 40 for the LLM


# ---------------------------------------------------------------------------
# prompt composition
# ---------------------------------------------------------------------------

LENGTH_TARGETS = {
    "3min":  "400-550 words",
    "6min":  "900-1200 words",
    "12min": "1800-2300 words",
}

VOICE_DESCRIPTIONS = {
    "gentle":   "warm, careful, no political jabs, light-touch humor, never snarky",
    "balanced": "opinionated but not provocative — has a perspective, willing to disagree, but fair",
    "sharp":    "edgy, first-mover, willing to call things dumb, punchy sentences, light mischief",
}

DEPTH_DESCRIPTIONS = {
    "headlines":  "one or two sentence takes, no analogies, no deep explanation — reader wants to know WHAT happened more than WHY",
    "balanced":   "two or three stories with light context and one-line takes",
    "deep-dives": "one dominant story with real explanation and second-order implications, plus one or two sidelines",
}


def compose_prompt(sub: dict, date: str, context_md: str | None) -> str:
    interests = sub.get("interests", {})
    topics = interests.get("topics", [])
    voice  = interests.get("voice", "balanced")
    depth  = interests.get("depth", "balanced")
    length = interests.get("length", "6min")
    freetext = interests.get("freetext", "").strip()

    voice_desc  = VOICE_DESCRIPTIONS.get(voice, VOICE_DESCRIPTIONS["balanced"])
    depth_desc  = DEPTH_DESCRIPTIONS.get(depth, DEPTH_DESCRIPTIONS["balanced"])
    length_tgt  = LENGTH_TARGETS.get(length, LENGTH_TARGETS["6min"])

    about_block = f"\nAbout the subscriber (free text): {freetext}\n" if freetext else ""

    prior_context_block = ""
    if context_md:
        prior_context_block = (
            "\n\n## Prior context (PRN — use as needed, not on schedule)\n\n"
            "The following block is auto-generated from the Ra research archive. "
            "Reach into it when a hinge fired, a trend turned, or a lab note is "
            "directly relevant to this subscriber's topics. Skip it when today's "
            "stories are new ground or a callback would only add words.\n\n"
            + context_md.strip()
        )

    return f"""You are Aurora — a morning brief for one specific subscriber.

Every morning you read a shared stream of news about the world and produce a
brief customized to exactly one person. You're not a feed reader. You're a
writer with a point of view.

# This subscriber

Topics they care about: {", ".join(topics)}
Voice preference: {voice} — {voice_desc}
Depth preference: {depth} — {depth_desc}
Length target: {length} read ({length_tgt})
{about_block}

# How to write

- Open with a single hook line in italic — the day at a glance in one sentence.
- Pick the 2-4 stories from the context that actually matter for THIS subscriber. Ignore the rest.
- Translate every story: WHY it matters, not just what happened. Assume the reader is smart but not already in the weeds.
- Never regurgitate the topic list. Never say "Here's your daily roundup." Never start with "Good morning." The voice is Aurora's, not a press release.
- Use section markers, not headers. Keep it flowing like an essay, not a dashboard. Section markers should be short and feel like the rhythm of a human breaking up their own thoughts.
- If any of the subscriber's topics are completely absent from today's stream, that's fine — don't pad. A short, honest brief beats a long padded one.
- Cap analogies at 1 for the whole brief. Prefer precise language.
- Include inline explanations when a term might not be universally understood. "Dot plot (the Fed's collective guess at future rates)". Keep them light.
- End with one short "Worth sitting with" line — a question or reframe that makes the reader think about the day.
- Target length: {length_tgt}.

# Output format

Return a single markdown document with YAML frontmatter:

```
---
date: {date}
kind: aurora-public
subscriber_id: {sub.get("id", "unknown")}
voice: {voice}
depth: {depth}
length: {length}
topics: [{", ".join(topics)}]
subject_line: "<short subject line, 6-10 words, written as if Aurora is sending a friendly note>"
---
<the brief body starts here — no h1, just the hook line, then the body>
```

The `subject_line` becomes the email subject. Make it specific to today, not generic. Examples of good subject lines: "The Fed blinked and your grocery bill didn't", "Three AI stories that actually matter", "Fashion week just told you where the economy is going".

The body is markdown. Use italics for the hook. Use short paragraphs. Do NOT include any section titled "Topics" or "Your interests" — the subscriber already knows what they picked.
{prior_context_block}
"""


# ---------------------------------------------------------------------------
# build context bundle for the LLM
# ---------------------------------------------------------------------------

def build_sub_context(records: list[dict], sub: dict, date: str) -> str:
    parts: list[str] = []
    topics = sub.get("interests", {}).get("topics", [])
    parts.append(f"# Gather records for {date}")
    parts.append(f"Subscriber: {sub.get('id')} · topics={topics}")
    parts.append(f"Matched records: {len(records)}\n")
    if not records:
        parts.append("*(No records matched the subscriber's topics today. Produce a short honest brief acknowledging a quiet day on their beat, then one interesting thing from the broader stream that's still worth their attention.)*\n")
        return "\n".join(parts)
    for r in records:
        parts.append(synthesize.format_record(r))
    out = "\n".join(parts)
    if len(out) > synthesize.MAX_CONTEXT_CHARS:
        out = out[:synthesize.MAX_CONTEXT_CHARS] + "\n\n[...truncated...]\n"
    return out


def load_all_records(date: str) -> list[dict]:
    path = INTELLIGENCE / f"{date}.jsonl"
    if not path.exists():
        # fall back to research/raw dir (where ra_archive stashes a copy)
        alt = RESEARCH / "raw" / f"{date}.jsonl"
        if alt.exists():
            path = alt
        else:
            return []
    recs = synthesize.load_jsonl(path)
    recs = synthesize.dedupe_records(recs)
    return recs


# ---------------------------------------------------------------------------
# generation loop
# ---------------------------------------------------------------------------

def generate_for_sub(sub: dict, records: list[dict], date: str,
                     context_md: str | None, backend: str, model: str,
                     timeout: int, dry_run: bool) -> dict | None:
    matched = filter_records_for_sub(records, sub)
    prompt  = compose_prompt(sub, date, context_md)
    context = build_sub_context(matched, sub, date)

    out_dir = PUBLIC_OUT / date
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{sub['id']}.md"

    if dry_run:
        print(f"[aurora_public] DRY {sub['id']} · {len(matched)} matched · would call {backend}:{model} → {out_file}")
        return {"id": sub["id"], "path": str(out_file), "matched": len(matched), "skipped": True}

    print(f"[aurora_public] {sub['id']} · {len(matched)} matched · calling {backend}:{model}")
    t0 = time.time()
    try:
        fn = synthesize.BACKENDS[backend][0]
        text = fn(prompt, context, model=model, timeout=timeout)
    except Exception as e:
        print(f"[aurora_public] {sub['id']} FAILED: {e}", file=sys.stderr)
        return {"id": sub["id"], "path": None, "matched": len(matched), "error": str(e)}
    took = time.time() - t0

    out_file.write_text(text.strip() + "\n")
    print(f"[aurora_public] {sub['id']} · ok · {len(text)} chars · {took:.1f}s → {out_file}")
    return {"id": sub["id"], "path": str(out_file), "matched": len(matched), "bytes": len(text)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="YYYY-MM-DD (default: today)")
    ap.add_argument("--sub", help="restrict to a single subscriber id")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--preview", action="store_true",
                    help="use a hardcoded fake subscriber for testing")
    ap.add_argument("--backend", default=None, help="force synthesis backend")
    ap.add_argument("--timeout", type=int, default=240)
    args = ap.parse_args()

    date = args.date or dt.date.today().isoformat()

    if args.preview:
        subs = [{
            "id": "sub_preview",
            "email": "preview@hyo.world",
            "status": "active",
            "interests": {
                "topics": ["ai", "startups", "crypto", "gaming"],
                "voice": "sharp",
                "depth": "balanced",
                "length": "6min",
                "freetext": "indie game dev in Denver, very online, hates crypto hype but pays attention to infra",
            },
        }]
    else:
        subs = [s for s in load_subscribers() if s.get("status") == "active"]
        if args.sub:
            subs = [s for s in subs if s.get("id") == args.sub]

    if not subs:
        print("[aurora_public] no active subscribers — nothing to do")
        return 0

    records = load_all_records(date)
    print(f"[aurora_public] {date}: {len(records)} gather records · {len(subs)} subscribers")

    context_md: str | None = None
    if CONTEXT_FILE.exists():
        context_md = CONTEXT_FILE.read_text()

    backend, model = synthesize.pick_backend(args.backend)
    if backend == "bundle":
        print("[aurora_public] no LLM backend available — use --dry-run or set ANTHROPIC_API_KEY/GROK_API_KEY/install claude-code", file=sys.stderr)
        return 2

    PUBLIC_OUT.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []
    for sub in subs:
        r = generate_for_sub(
            sub=sub,
            records=records,
            date=date,
            context_md=context_md,
            backend=backend,
            model=model,
            timeout=args.timeout,
            dry_run=args.dry_run,
        )
        if r:
            results.append(r)

    # write a small run manifest the email sender can read
    manifest = {
        "date": date,
        "backend": backend,
        "model": model,
        "total": len(results),
        "ok": len([r for r in results if r.get("path") and not r.get("error")]),
        "errors": len([r for r in results if r.get("error")]),
        "results": results,
    }
    mf = PUBLIC_OUT / date / "manifest.json"
    mf.parent.mkdir(parents=True, exist_ok=True)
    mf.write_text(json.dumps(manifest, indent=2))
    print(f"[aurora_public] manifest → {mf}")
    return 0 if manifest["errors"] == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
