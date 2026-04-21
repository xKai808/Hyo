#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# queue-hygiene.sh — Keeps the command queue clean and healthy
#
# Problems it fixes:
#   - completed/ directory backing up with 1100+ items (confirmed in audit)
#   - failed/ items not being reviewed and logged
#   - pending/ items that are stale (queued >24h ago, never picked up)
#
# Runs daily at 09:30 MT via kai-autonomous.sh dispatch
# Also runs on-demand: bash bin/queue-hygiene.sh
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
QUEUE="$HYO_ROOT/kai/queue"
LOG="$HYO_ROOT/kai/ledger/queue-hygiene.log"
ARCHIVE="$HYO_ROOT/kai/queue/archive"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"

mkdir -p "$ARCHIVE" "$(dirname "$LOG")"

NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
NOW_EPOCH=$(date +%s)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_section() { echo "" >> "$LOG"; echo "═══ $* ═══" | tee -a "$LOG"; }

log_section "QUEUE HYGIENE — $TODAY"

# ─── 1. Archive completed items older than 7 days ─────────────────────────────
log_section "1. Archive completed items"
ARCHIVE_MONTH="$ARCHIVE/$(TZ=America/Denver date +%Y-%m)"
mkdir -p "$ARCHIVE_MONTH"

ARCHIVED=0
KEPT=0
for f in "$QUEUE/completed/"*.json 2>/dev/null; do
  [[ ! -f "$f" ]] && continue
  # Get file modification time
  fmtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
  age_days=$(( (NOW_EPOCH - fmtime) / 86400 ))
  if [[ $age_days -ge 7 ]]; then
    mv "$f" "$ARCHIVE_MONTH/" 2>/dev/null && ARCHIVED=$((ARCHIVED + 1))
  else
    KEPT=$((KEPT + 1))
  fi
done
log "Archived: $ARCHIVED completed items (>7 days old) → $ARCHIVE_MONTH"
log "Kept: $KEPT recent completed items"

# ─── 2. Review failed items ───────────────────────────────────────────────────
log_section "2. Review failed items"
FAILED_COUNT=0
NEW_FAILURES=0

for f in "$QUEUE/failed/"*.json 2>/dev/null; do
  [[ ! -f "$f" ]] && continue
  FAILED_COUNT=$((FAILED_COUNT + 1))

  # Extract command for logging
  cmd_preview=$(python3 -c "
import json
try:
    with open('$f') as fp:
        d = json.load(fp)
    cmd = d.get('command', d.get('cmd', ''))[:80]
    ts = d.get('ts', d.get('submitted', 'unknown'))
    print(f'{ts}: {cmd}...')
except:
    print('unparseable')
" 2>/dev/null || echo "unparseable")

  log "FAILED: $(basename $f) — $cmd_preview"

  # Check if this failure has already been ticketed
  fname=$(basename "$f" .json)
  already_ticketed=$(python3 -c "
import json
try:
    with open('$HYO_ROOT/kai/tickets/tickets.jsonl') as tf:
        for line in tf:
            e = json.loads(line.strip())
            if '$fname' in e.get('title','') and e.get('status') not in ('CLOSED','ARCHIVED','RESOLVED'):
                print('yes')
                break
except:
    pass
" 2>/dev/null || echo "")

  if [[ "$already_ticketed" != "yes" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "sam" \
      --title "Queue job failed: $fname — $cmd_preview" \
      --priority "P2" \
      --created-by "queue-hygiene" 2>/dev/null || true
    NEW_FAILURES=$((NEW_FAILURES + 1))
  fi
done

log "Failed jobs total: $FAILED_COUNT | New tickets opened: $NEW_FAILURES"

# ─── 3. Detect stale pending items (>24h, never picked up) ───────────────────
log_section "3. Stale pending items"
STALE_PENDING=0

for f in "$QUEUE/pending/"*.json 2>/dev/null; do
  [[ ! -f "$f" ]] && continue
  fmtime=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
  age_h=$(( (NOW_EPOCH - fmtime) / 3600 ))
  if [[ $age_h -ge 24 ]]; then
    log "STALE PENDING: $(basename $f) — ${age_h}h old"
    STALE_PENDING=$((STALE_PENDING + 1))
  fi
done

if [[ $STALE_PENDING -gt 0 ]]; then
  log "⚠️ $STALE_PENDING stale pending items — queue worker may be down"
  HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
    --agent "sam" \
    --title "Queue worker stale: $STALE_PENDING pending items stuck >24h" \
    --priority "P1" \
    --created-by "queue-hygiene" 2>/dev/null || true
fi

# ─── 4. Summary ───────────────────────────────────────────────────────────────
log_section "SUMMARY"
CURRENT_COMPLETED=$(ls "$QUEUE/completed/" 2>/dev/null | wc -l | tr -d ' ')
CURRENT_FAILED=$(ls "$QUEUE/failed/" 2>/dev/null | wc -l | tr -d ' ')
CURRENT_PENDING=$(ls "$QUEUE/pending/" 2>/dev/null | wc -l | tr -d ' ')

log "Queue state: pending=$CURRENT_PENDING | completed=$CURRENT_COMPLETED | failed=$CURRENT_FAILED"
log "Hygiene run complete: $NOW_MT"
exit 0
