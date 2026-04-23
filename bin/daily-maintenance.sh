#!/usr/bin/env bash
# bin/daily-maintenance.sh — Daily autonomous upkeep for fast-growing files
#
# Runs every day at 01:30 MT via kai-autonomous.sh
# Prevents mess accumulation between weekly deep-cleans.
#
# WHY DAILY (not weekly):
#   hyo-inbox.jsonl: grows ~100+ messages/day → would be 700+ by Saturday
#   tickets.jsonl: race-condition duplicates accumulate intra-day
#   log.jsonl files: aether/kai logs grow ~300-400 lines/day → 2K+/week
#   Context cost is paid EVERY SESSION — daily cleanup keeps it low every day
#
# Split from weekly-maintenance.sh (which handles heavy archiving):
#   Daily:  inbox trim, ticket dedup+cap, log rotation (100 entries)
#   Weekly: ticket archiving, KAI_BRIEF/KAI_TASKS archiving, full stats

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
LOG="$ROOT/kai/ledger/daily-maintenance.log"

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }

log "=== Daily Maintenance — $TODAY ==="

# ── 1. Inbox trim: keep last 50 messages ─────────────────────────────────────
# inbox grows ~100 messages/day; without trim it reaches 700 by Saturday
INBOX="$ROOT/kai/ledger/hyo-inbox.jsonl"
if [[ -f "$INBOX" ]]; then
    python3 - "$INBOX" << 'PYEOF'
import json, sys, os
path = sys.argv[1]
with open(path) as f:
    lines = [l.strip() for l in f if l.strip()]
before = len(lines)
# Keep last 50 messages (most recent)
kept = lines[-50:] if len(lines) > 50 else lines
with open(path, 'w') as f:
    f.write('\n'.join(kept) + '\n')
print(f"  inbox: {before} → {len(kept)} messages")
PYEOF
fi

# ── 2. Ticket dedup + cap ─────────────────────────────────────────────────────
# Race condition: multiple agents write tickets.jsonl simultaneously → duplicates
# Fix: deduplicate (keep last/most-recent per ID) and enforce 20-note cap
TICKETS="$ROOT/kai/tickets/tickets.jsonl"
if [[ -f "$TICKETS" ]]; then
    python3 - "$TICKETS" << 'PYEOF'
import json, sys
path = sys.argv[1]
seen = {}
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            t = json.loads(line)
            tid = t.get('id', '')
            if not tid: continue
            # Cap notes to 20 (keep most recent)
            notes = t.get('notes', [])
            if len(notes) > 20:
                t['notes'] = notes[-20:]
            seen[tid] = t  # last occurrence wins (most recent update)
        except Exception:
            pass
with open(path, 'w') as f:
    for t in seen.values():
        f.write(json.dumps(t, ensure_ascii=False) + '\n')
print(f"  tickets: {len(seen)} unique (deduped, notes capped at 20)")
PYEOF
fi

# ── 3. Sync tickets.jsonl → tickets.db ───────────────────────────────────────
# After dedup, refresh the SQLite DB to match
if [[ -f "$ROOT/bin/tickets-db.py" ]]; then
    HYO_ROOT="$ROOT" python3 "$ROOT/bin/tickets-db.py" migrate >> "$LOG" 2>&1
    log "tickets.db synced"
fi

# ── 4. Rotate fast-growing JSONL logs (cap at 100 entries) ───────────────────
python3 - "$ROOT" << 'PYEOF'
import json, sys, os, glob
root = sys.argv[1]
log_files = [
    'agents/aether/ledger/log.jsonl',
    'agents/nel/ledger/log.jsonl',
    'agents/ra/ledger/log.jsonl',
    'agents/sam/ledger/log.jsonl',
    'agents/dex/ledger/log.jsonl',
    'kai/ledger/log.jsonl',
    'kai/ledger/known-issues.jsonl',
    'kai/ledger/session-errors.jsonl',
]
for rel in log_files:
    path = os.path.join(root, rel)
    if not os.path.exists(path): continue
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]
    if len(lines) > 100:
        with open(path, 'w') as f:
            f.write('\n'.join(lines[-100:]) + '\n')
        print(f"  rotated {rel}: {len(lines)} → 100 entries")
PYEOF

# ── 5. Report sizes ───────────────────────────────────────────────────────────
python3 - "$ROOT" << 'PYEOF'
import os, sys
root = sys.argv[1]
files = {
    'hyo-inbox.jsonl':     'kai/ledger/hyo-inbox.jsonl',
    'tickets.jsonl':       'kai/tickets/tickets.jsonl',
    'tickets.db':          'kai/tickets/tickets.db',
    'aether/log.jsonl':    'agents/aether/ledger/log.jsonl',
    'kai/log.jsonl':       'kai/ledger/log.jsonl',
    'known-issues.jsonl':  'kai/ledger/known-issues.jsonl',
}
total = 0
for name, rel in files.items():
    path = os.path.join(root, rel)
    if os.path.exists(path):
        size = os.path.getsize(path)
        total += size
        flag = ' ⚠ OVER 50KB' if size > 50_000 else ''
        print(f"  {name}: {size/1024:.1f}KB{flag}")
tokens = total // 4
print(f"  TOTAL: {total/1024:.1f}KB (~{tokens:,} tokens, ~${tokens/1_000_000*3:.4f}/session)")
PYEOF

# ── 5. Memory integrity check ─────────────────────────────────────────────────
# Scans KNOWLEDGE.md and session-handoff for untagged claims, stale facts,
# and inferences older than 48h. Prevents contaminated memory from recycling.
# See: kai/protocols/PROTOCOL_MEMORY_INTEGRITY.md
if [[ -f "$ROOT/bin/memory-integrity-check.sh" ]]; then
    HYO_ROOT="$ROOT" bash "$ROOT/bin/memory-integrity-check.sh" >> "$LOG" 2>&1
fi

log "=== Daily maintenance complete ==="
