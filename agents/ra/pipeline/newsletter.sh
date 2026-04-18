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

if [[ -f "$MD_FILE" && $SYNTH_RC -ne 2 ]]; then
  echo "[$STAMP] publishing to HQ feed..."
  python3 - "$MD_FILE" "$TODAY_DATE" "$FEED_GIT" "$FEED_LIVE" <<'PYPUB'
import json, re, sys, os, subprocess
md_path, date, feed_git, feed_live = sys.argv[1:5]
with open(md_path) as f:
    text = f.read()
entities = re.findall(r'name:\s+"([^"]+)"', text)
takes    = re.findall(r'take:\s+"([^"]+)"', text)
summary  = " | ".join(f"{e}: {t}" for e, t in zip(entities[:3], takes[:3])) or "Today's tech and market intelligence."
topics   = list(dict.fromkeys(re.findall(r'name:\s+"([^"]+)"', text)))[:6]
now = subprocess.check_output(["bash","-c","TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z"],text=True).strip()
entry = {"id": f"newsletter-ra-{date}", "type": "newsletter",
         "title": f"Aurora Daily Brief — {date}", "author": "Ra",
         "authorIcon": "📰", "authorColor": "#b49af0",
         "timestamp": now, "date": date,
         "sections": {"summary": summary[:500], "topics": topics,
                      "readLink": f"/newsletters/{date}.html"}}
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
print(f"[feed] published {entry['id']}")
PYPUB
  [[ $? -ne 0 ]] && echo "[$STAMP] WARNING: feed publish failed" >&2
else
  echo "[$STAMP] skipping feed publish (no md or bundle mode)" >&2
fi

echo "[$STAMP] hyo-newsletter: done"
exit $SYNTH_RC
