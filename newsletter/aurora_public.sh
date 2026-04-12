#!/usr/bin/env bash
# aurora_public.sh — one-shot wrapper for the Aurora Public pipeline.
#
# Runs gather (wide net) → ra_context (for PRN continuity) → aurora_public
# (one brief per active subscriber) → send_email (dispatch briefs). Every
# stage is stdlib-only Python; this shell script is just the conductor.
#
# Usage:
#   bash aurora_public.sh                     # full run for today
#   bash aurora_public.sh --date 2026-04-12   # backfill a specific date
#   bash aurora_public.sh --no-gather         # reuse today's gather output
#   bash aurora_public.sh --preview           # generate for the fake preview
#                                             # profile only — never sends
#   bash aurora_public.sh --dry-send          # generate but dry-run the sender
#   bash aurora_public.sh --backend resend    # force email backend
#
# Env autoloaded from:
#   $HYO_ENV_FILE, ~/security/hyo.env, ~/security/.env,
#   ~/.config/hyo/env, $HYO_ROOT/.secrets/env
#
# Exit codes:
#   0 = success (every subscriber delivered)
#   1 = a required stage failed
#   2 = partial success (gen/send had some failures; check logs)

set -u
cd "$(dirname "$0")"

# ---- env auto-load ---------------------------------------------------------
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
NO_GATHER=0
PREVIEW=0
DRY_SEND=0
EMAIL_BACKEND=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --date)        DATE_ARG="--date $2"; shift 2 ;;
    --no-gather)   NO_GATHER=1; shift ;;
    --preview)     PREVIEW=1; shift ;;
    --dry-send)    DRY_SEND=1; shift ;;
    --backend)     EMAIL_BACKEND="$2"; shift 2 ;;
    *)             echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

PY=${PYTHON:-python3}
STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "[$STAMP] aurora-public: starting pipeline"

HYO_ROOT_DEFAULT="$(cd "$(dirname "$0")/.." && pwd)"
export HYO_ROOT="${HYO_ROOT:-$HYO_ROOT_DEFAULT}"
RA_CONTEXT="$HYO_ROOT/kai/ra_context.py"

# 1) gather — shared with Ra. Skip if caller already ran it today.
if [[ $NO_GATHER -eq 0 ]]; then
  echo "[$STAMP] gather.py ..."
  if ! $PY gather.py $DATE_ARG; then
    echo "[$STAMP] gather.py FAILED" >&2
    exit 1
  fi
else
  echo "[$STAMP] --no-gather: reusing existing gather output"
fi

# 2) ra_context — PRN continuity block. Non-fatal if missing.
if [[ -f "$RA_CONTEXT" ]]; then
  echo "[$STAMP] ra_context.py ..."
  if ! $PY "$RA_CONTEXT" $DATE_ARG; then
    echo "[$STAMP] ra_context.py failed (non-fatal)" >&2
  fi
else
  echo "[$STAMP] ra_context.py not at $RA_CONTEXT — skipping" >&2
fi

# 3) aurora_public — one brief per active subscriber.
AP_ARGS="$DATE_ARG"
[[ $PREVIEW -eq 1 ]] && AP_ARGS="$AP_ARGS --preview"
echo "[$STAMP] aurora_public.py $AP_ARGS ..."
$PY aurora_public.py $AP_ARGS
GEN_RC=$?
if [[ $GEN_RC -eq 1 ]]; then
  echo "[$STAMP] aurora_public.py hard-failed" >&2
  exit 1
fi

# 4) send_email — dispatch. Preview mode does not send.
if [[ $PREVIEW -eq 1 ]]; then
  echo "[$STAMP] preview mode: skipping send_email.py"
  exit $GEN_RC
fi

SEND_ARGS="$DATE_ARG"
[[ $DRY_SEND -eq 1 ]] && SEND_ARGS="$SEND_ARGS --dry-run"
[[ -n "$EMAIL_BACKEND" ]] && SEND_ARGS="$SEND_ARGS --backend $EMAIL_BACKEND"
echo "[$STAMP] send_email.py $SEND_ARGS ..."
$PY send_email.py $SEND_ARGS
SEND_RC=$?

echo "[$STAMP] aurora-public: done · gen_rc=$GEN_RC · send_rc=$SEND_RC"
# bubble up the worst non-zero code
if [[ $GEN_RC -ne 0 ]]; then exit $GEN_RC; fi
exit $SEND_RC
