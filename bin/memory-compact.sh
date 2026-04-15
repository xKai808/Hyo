#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# memory-compact.sh — 02:30 AM memory compaction
# Runs via launchd at 02:30 MTN. Handles:
#   1. Archive daily notes older than 30 days into monthly rollups
#   2. Compress daily notes older than 7 days (keep summary)
#   3. Deduplicate pattern library
#   4. Rotate system logs (keep last 2000 lines)
#   5. Archive closed tickets older than 30 days
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
MEMORY_DIR="$ROOT/kai/memory"
DAILY_DIR="$MEMORY_DIR/daily"
ARCHIVE_DIR="$DAILY_DIR/archive"
PATTERN_LIB="$MEMORY_DIR/patterns/pattern_library.md"
TICKET_LEDGER="$ROOT/kai/tickets/tickets.jsonl"
TICKET_ARCHIVE="$ROOT/kai/tickets/archive"

mkdir -p "$ARCHIVE_DIR" "$TICKET_ARCHIVE"

log() { echo "[compact] $(TZ=America/Denver date +%H:%M:%S) $*"; }
log "Starting memory compaction"

# ─── 1. Archive daily notes older than 30 days ───
ARCHIVED=0
find "$DAILY_DIR" -maxdepth 1 -name "*.md" -mtime +30 2>/dev/null | while read -r f; do
  MONTH=$(basename "$f" | cut -c1-7)  # YYYY-MM
  echo "" >> "$ARCHIVE_DIR/$MONTH.md"
  echo "---" >> "$ARCHIVE_DIR/$MONTH.md"
  echo "# $(basename "$f" .md)" >> "$ARCHIVE_DIR/$MONTH.md"
  cat "$f" >> "$ARCHIVE_DIR/$MONTH.md"
  rm "$f"
  ARCHIVED=$((ARCHIVED + 1))
done
log "Archived $ARCHIVED daily notes to monthly rollups"

# ─── 2. Compress daily notes older than 7 days (keep first 50 lines) ───
COMPRESSED=0
find "$DAILY_DIR" -maxdepth 1 -name "*.md" -mtime +7 2>/dev/null | while read -r f; do
  TOTAL_LINES=$(wc -l < "$f" | tr -d ' ')
  if [[ "$TOTAL_LINES" -gt 50 ]]; then
    head -50 "$f" > "$f.tmp"
    echo "" >> "$f.tmp"
    echo "[Compressed: original had $TOTAL_LINES lines, kept summary]" >> "$f.tmp"
    mv "$f.tmp" "$f"
    COMPRESSED=$((COMPRESSED + 1))
  fi
done
log "Compressed $COMPRESSED daily notes (7+ days old)"

# ─── 3. Deduplicate pattern library ───
if [[ -f "$PATTERN_LIB" ]]; then
  BEFORE=$(wc -l < "$PATTERN_LIB" | tr -d ' ')
  # Don't sort — patterns have structure. Just remove exact duplicate lines
  awk '!seen[$0]++' "$PATTERN_LIB" > "$PATTERN_LIB.tmp"
  mv "$PATTERN_LIB.tmp" "$PATTERN_LIB"
  AFTER=$(wc -l < "$PATTERN_LIB" | tr -d ' ')
  log "Pattern library: $BEFORE → $AFTER lines (deduped)"
fi

# ─── 4. Rotate system logs (keep last 2000 lines) ───
for logfile in "$ROOT/kai/queue/worker.log" \
               "$ROOT/agents/nel/logs/"*.log \
               "$ROOT/agents/ra/logs/"*.log \
               "$ROOT/agents/sam/logs/"*.log \
               "$ROOT/agents/aether/logs/"*.log; do
  [[ ! -f "$logfile" ]] && continue
  LINES=$(wc -l < "$logfile" | tr -d ' ')
  if [[ "$LINES" -gt 2000 ]]; then
    tail -2000 "$logfile" > "$logfile.tmp"
    mv "$logfile.tmp" "$logfile"
    log "Rotated $(basename "$logfile"): $LINES → 2000 lines"
  fi
done

# ─── 5. Archive closed tickets older than 30 days ───
if [[ -s "$TICKET_LEDGER" ]]; then
  python3 - "$TICKET_LEDGER" "$TICKET_ARCHIVE" << 'PYEOF'
import json, sys, os
from datetime import datetime, timedelta

ledger = sys.argv[1]
archive_dir = sys.argv[2]
cutoff = (datetime.now() - timedelta(days=30)).isoformat()

keep = []
archived = 0
with open(ledger) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        if entry.get('status') == 'CLOSED' and entry.get('closed_at', entry.get('created_at', '')) < cutoff:
            # Archive
            month = entry.get('closed_at', entry['created_at'])[:7]
            archive_file = os.path.join(archive_dir, f"{month}.jsonl")
            with open(archive_file, 'a') as af:
                af.write(json.dumps(entry, ensure_ascii=False) + '\n')
            archived += 1
        else:
            keep.append(line)

with open(ledger, 'w') as f:
    f.write('\n'.join(keep) + '\n' if keep else '')

print(f"Archived {archived} closed tickets (>30 days)")
PYEOF
fi

log "Memory compaction complete"
