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

echo "[$STAMP] hyo-newsletter: done"
exit $SYNTH_RC
