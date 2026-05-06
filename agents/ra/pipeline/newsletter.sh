#!/usr/bin/env bash
# newsletter.sh — one-shot wrapper for gather → synthesize → render
#
# Runs the full Hyo daily newsletter pipeline end to end. Every stage
# uses Python 3 standard library only — no venv, no pip. Safe for cron.
#
# Usage:
#   bash newsletter.sh                 # full run for today
#   bash newsletter.sh --date 2026-04-09  # backfill specific date
#   bash newsletter.sh --gather-only   # stop after gather.py
#   bash newsletter.sh --no-gather     # skip gather (re-synth + re-render)
#
# Exit codes:
#   0 = full success
#   1 = a required stage failed
#   2 = partial success (e.g. synthesis fell back to bundle mode)

set -u
cd "$(dirname "$0")"

# ---- env auto-load ----------------------------------------------------------
# Search the same places kai.sh does so credentials flow through even when
# this script is invoked from cron/launchd/scheduled tasks with a blank env.
_candidates=(
  "${HYO_ENV_FILE:-}"
  "$HOME/security/hyo.env"
  "$HOME/security/.env"
  "$HOME/.config/hyo/env"
  "$HOME/Documents/Projects/Hyo/.secrets/env"
)
for _f in "${_candidates[@]}"; do
  if [[ -n "$_f" && -f "$_f" && -r "$_f" ]]; then
    set -a; . "$_f"; set +a
    echo "[env] loaded $_f" >&2
    break
  fi
done
unset _candidates _f

DATE_ARG=""
GATHER_ONLY=0
NO_GATHER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)        DATE_ARG="--date $2"; shift 2 ;;
    --gather-only) GATHER_ONLY=1; shift ;;
    --no-gather)   NO_GATHER=1; shift ;;
    *)             echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

PY=${PYTHON:-python3}
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "[$STAMP] hyo-newsletter: starting pipeline"

# path to Kai's archive scripts, independent of cwd
HYO_ROOT_DEFAULT="$(cd "$(dirname "$0")/../../.." && pwd)"
export HYO_ROOT="${HYO_ROOT:-$HYO_ROOT_DEFAULT}"
RA_CONTEXT="$HYO_ROOT/agents/ra/ra_context.py"
RA_ARCHIVE="$HYO_ROOT/agents/ra/ra_archive.py"

if [[ $NO_GATHER -eq 0 ]]; then
  echo "[$STAMP] gather.py ..."
  if ! $PY gather.py $DATE_ARG; then
    echo "[$STAMP] gather.py FAILED (non-zero exit)" >&2
    exit 1
  fi
fi

if [[ $GATHER_ONLY -eq 1 ]]; then
  echo "[$STAMP] --gather-only set, stopping here"
  exit 0
fi

# pre-synthesize: build the prior-context block from the research archive
if [[ -f "$RA_CONTEXT" ]]; then
  echo "[$STAMP] ra_context.py ..."
  if ! $PY "$RA_CONTEXT" $DATE_ARG; then
    echo "[$STAMP] ra_context.py failed (non-fatal, continuing)" >&2
  fi
else
  echo "[$STAMP] ra_context.py not found at $RA_CONTEXT — skipping" >&2
fi

echo "[$STAMP] synthesize.py ..."
$PY synthesize.py $DATE_ARG
SYNTH_RC=$?
if [[ $SYNTH_RC -eq 1 ]]; then
  echo "[$STAMP] synthesize.py hard-failed" >&2
  exit 1
fi

# rc=2 means the api call failed and a bundle was written — still try render
echo "[$STAMP] render.py ..."
if ! $PY render.py $DATE_ARG; then
  echo "[$STAMP] render.py failed — the .md may be missing if synth fell back to bundle" >&2
  # not fatal if bundle mode
  [[ $SYNTH_RC -eq 2 ]] && exit 2
  exit 1
fi

# post-render: file today's research into the persistent archive
if [[ -f "$RA_ARCHIVE" && $SYNTH_RC -ne 2 ]]; then
  echo "[$STAMP] ra_archive.py ..."
  if ! $PY "$RA_ARCHIVE" $DATE_ARG; then
    echo "[$STAMP] ra_archive.py failed (non-fatal, brief is still rendered)" >&2
  fi
elif [[ ! -f "$RA_ARCHIVE" ]]; then
  echo "[$STAMP] ra_archive.py not found at $RA_ARCHIVE — skipping" >&2
fi

# ---- auto-publish to HQ feed -----------------------------------------------
TODAY_DATE=$(TZ=America/Denver date +%Y-%m-%d)
MD_FILE="$HYO_ROOT/agents/ra/output/${TODAY_DATE}.md"
FEED_GIT="$HYO_ROOT/agents/sam/website/data/feed.json"
FEED_LIVE="$HYO_ROOT/website/data/feed.json"

# If synthesize fell to bundle mode (rc=2) but a .md from a prior successful
# run already exists for today, use it — render.py will have refreshed the HTML.
# This prevents missing feed entries on nights when all LLM backends fail.
if [[ $SYNTH_RC -eq 2 && -f "$MD_FILE" ]]; then
  echo "[$STAMP] synthesize bundle mode but prior .md exists — proceeding with feed publish"
  SYNTH_RC=0  # treat as success for the publish gate
fi

if [[ -f "$MD_FILE" && $SYNTH_RC -ne 2 ]]; then
  echo "[$STAMP] publishing to HQ feed..."

  # ---- copy HTML to website/daily/ so /daily/newsletter-DATE resolves on Vercel ----
  # NOTE: bare YYYY-MM-DD filenames cause Vercel 404; use newsletter-DATE prefix instead
  HTML_SRC="$HYO_ROOT/agents/ra/output/${TODAY_DATE}.html"
  DAILY_DIR="$HYO_ROOT/agents/sam/website/daily"
  HTML_FILENAME="newsletter-${TODAY_DATE}.html"
  HTML_DST="$DAILY_DIR/${HTML_FILENAME}"
  if [[ -f "$HTML_SRC" ]]; then
    mkdir -p "$DAILY_DIR"
    cp "$HTML_SRC" "$HTML_DST"
    # also copy to website/ symlink path for dual-path consistency
    cp "$HTML_SRC" "$HYO_ROOT/website/daily/${HTML_FILENAME}" 2>/dev/null || true
    echo "[$STAMP] copied HTML → $HTML_DST"
  else
    echo "[$STAMP] WARNING: HTML source not found at $HTML_SRC — skipping copy" >&2
  fi

  # ---- VERIFICATION GATE: confirm HTML exists at deploy path before publishing ----
  if [[ ! -f "$HTML_DST" ]]; then
    echo "[$STAMP] ERROR: HTML not present at $HTML_DST — refusing to publish feed entry with broken readLink" >&2
    echo "[$STAMP] Fix: ensure render.py produces ${TODAY_DATE}.html in agents/ra/output/, then re-run newsletter.sh --no-gather" >&2
    exit 1
  fi

  python3 - "$MD_FILE" "$TODAY_DATE" "$FEED_GIT" "$FEED_LIVE" <<'PYPUB'
import json, re, sys, os, subprocess
md_path, date, feed_git, feed_live = sys.argv[1:5]
with open(md_path) as f:
    text = f.read()

# Parse structured entity data from YAML frontmatter
# Each entity has: name, take, hinge, confidence, category
entities_raw = re.findall(r'name:\s+"([^"]+)"', text)
takes_raw    = re.findall(r'take:\s+"([^"]+)"', text)
hinges_raw   = re.findall(r'hinge:\s+"([^"]+)"', text)
cats_raw     = re.findall(r'category:\s+(\S+)', text)
confs_raw    = re.findall(r'confidence:\s+(\S+)', text)

# Build structured story objects for top 5 entities
stories = []
for i, name in enumerate(entities_raw[:5]):
    stories.append({
        "title": name,
        "take":  takes_raw[i] if i < len(takes_raw) else "",
        "watch": hinges_raw[i] if i < len(hinges_raw) else "",
        "category": cats_raw[i] if i < len(cats_raw) else "",
    })

story_count = len(entities_raw)

# ── CONTENT PROTECTION GATE (v2 — 2026-04-27) ──────────────────────────────
# Problem: newsletter.sh runs multiple times per day (cron + retries).
# If a later run gathers 0 entities, it would overwrite a good earlier entry
# with empty content — Hyo sees "Today's tech and market intelligence." as
# the summary and 0 stories forever. This gate prevents that.
#
# Gate questions (all must be YES to publish):
#   Q1: Does this run have at least 1 story? → if NO, check Q2
#   Q2: Does today's feed entry already have stories? → if YES, SKIP this run
#       (protect the good entry; don't overwrite with empty)
#   Q3: Has today's entry never been published? → if YES + 0 stories, write
#       minimal entry without readLink (so no 404) and alert Telegram
if story_count == 0:
    # Check if today already has a good entry
    for path in [feed_git, feed_live]:
        if not os.path.exists(path):
            continue
        try:
            with open(path) as f:
                d = json.load(f)
            existing = next(
                (r for r in d.get("reports", [])
                 if r.get("id") == f"newsletter-ra-{date}"),
                None
            )
            if existing:
                existing_stories = existing.get("sections", {}).get("stories", [])
                if len(existing_stories) > 0:
                    print(f"[feed] CONTENT GATE: 0 entities this run but {len(existing_stories)} stories already published — keeping existing entry, skipping overwrite")
                    sys.exit(0)
        except Exception:
            pass
    # No good entry exists — publish minimal entry WITHOUT readLink (no 404)
    # and flag as gather-failed so Hyo sees an honest status
    print(f"[feed] CONTENT GATE: 0 entities, no prior entry — publishing empty-gather notice")
    # Alert Telegram
    # AETHERBOT_TELEGRAM_TOKEN = @xAetherbot (alerts only). TELEGRAM_BOT_TOKEN = @Kai_11_bot (conversations).
    token = os.environ.get("AETHERBOT_TELEGRAM_TOKEN") or os.environ.get("TELEGRAM_BOT_TOKEN", "")
    chat  = os.environ.get("TELEGRAM_CHAT_ID", "")
    if token and chat:
        import urllib.request, urllib.parse
        msg = f"⚠️ Aurora {date}: gather returned 0 entities — brief not published. Check sources.json and gather.py logs."
        urllib.request.urlopen(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data=urllib.parse.urlencode({"chat_id": chat, "text": msg}).encode(),
            timeout=5
        )

now = subprocess.check_output(["bash","-c","TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z"],text=True).strip()

# BLUF summary: count + top story lead
top_story = entities_raw[0] if entities_raw else ""
if stories:
    bluf = f"{story_count} stories this morning, led by {top_story}."
else:
    bluf = "Aurora gather returned 0 stories today — sources may be unavailable."

topics = list(dict.fromkeys(entities_raw))[:6]

# readLink only included when there are actual stories (prevents 404 on empty page)
sections = {
    "summary": bluf,
    "stories": stories,
    "topics": topics,
}
if story_count > 0:
    # readLink uses /daily/newsletter-DATE — bare YYYY-MM-DD causes Vercel 404 (SE-019)
    sections["readLink"] = f"/daily/newsletter-{date}"

entry = {
    "id": f"newsletter-ra-{date}",
    "type": "newsletter",
    "title": f"Aurora Daily Brief — {date}",
    "author": "Ra",
    "authorIcon": "📰",
    "authorColor": "#b49af0",
    "timestamp": now,
    "date": date,
    "sections": sections,
}

for path in [feed_git, feed_live]:
    if not os.path.exists(path):
        continue
    with open(path) as f:
        d = json.load(f)
    reports = d.setdefault("reports", [])
    reports[:] = [r for r in reports if r.get("id") != entry["id"]]
    reports.insert(0, entry)
    d["lastUpdated"] = now
    with open(path, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
print(f"[feed] published {entry['id']} ({story_count} stories, readLink={'yes' if story_count > 0 else 'OMITTED — 0 stories'})")
PYPUB
  PYPUB_RC=$?
  [[ $PYPUB_RC -ne 0 && $PYPUB_RC -ne 0 ]] && echo "[$STAMP] WARNING: feed publish failed (rc=$PYPUB_RC)" >&2

  # ---- COMMIT & PUSH so Vercel deploys the HTML (fixes /daily/DATE 404) ----
  cd "$HYO_ROOT"
  git add "agents/sam/website/daily/${HTML_FILENAME}" \
          "agents/sam/website/data/feed.json" \
          "website/data/feed.json" 2>/dev/null || true
  if git diff --cached --quiet; then
    echo "[$STAMP] nothing new to commit (already up to date)"
  else
    git commit -m "newsletter: publish ${TODAY_DATE} brief + HTML to daily/" \
        --author="Ra <ra@hyo.world>" 2>&1 | tail -1
    git push origin main 2>&1 | tail -1 \
      && echo "[$STAMP] pushed to Vercel" \
      || echo "[$STAMP] WARNING: git push failed — HTML not yet on Vercel" >&2
  fi

  # ---- LIVE URL VERIFICATION GATE (v1 — 2026-04-27) ─────────────────────────
  # Verify the page is actually accessible on Vercel, not just pushed to git.
  # "git push succeeded" ≠ "Hyo can see the page" — Vercel deploy takes 15-30s.
  # This gate waits and confirms HTTP 200 with content >= 500 bytes.
  # If it fails: Telegram alert sent by publish-verify.sh, pipeline exit = 1.
  VERIFY_SCRIPT="$HYO_ROOT/bin/publish-verify.sh"
  if [[ -f "$VERIFY_SCRIPT" ]]; then
    LIVE_URL="https://hyo.world/daily/newsletter-${TODAY_DATE}"
    echo "[$STAMP] verifying live URL: $LIVE_URL"
    bash "$VERIFY_SCRIPT" "$LIVE_URL" 500 90 \
      || echo "[$STAMP] WARNING: live URL verification failed — Hyo may see 404" >&2
  fi
else
  echo "[$STAMP] skipping feed publish (no md or bundle mode)" >&2
fi

echo "[$STAMP] hyo-newsletter: done"
exit $SYNTH_RC
