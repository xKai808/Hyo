#!/usr/bin/env bash
# bin/flush-knowledge-queue.sh — Flush staged knowledge entries into KNOWLEDGE.md
#
# MARINA WYSS ARCHITECTURE FIX (2026-05-05):
# Knowledge must be read-only during agent execution. Agents that resolve a
# weakness during their run write to kai/memory/knowledge-queue.jsonl instead
# of directly to KNOWLEDGE.md. This script runs at 01:00 MT (before any agent
# starts their next cycle) to safely flush all pending entries into KNOWLEDGE.md.
#
# Why this works:
#   - 01:00 MT is between daily reporting (22:00–23:30 MT) and next morning cycle
#   - No agents are writing to KNOWLEDGE.md when this runs
#   - knowledge-queue.jsonl uses atomic line appends (safe for concurrent agents)
#   - This script holds an exclusive lock on KNOWLEDGE.md during the flush
#
# Called by: agents/nel/consolidation/consolidate.sh (at 01:00 MT nightly)
# Lock: kai/memory/knowledge-queue.lock (prevents concurrent flush)
#
# Usage:
#   bash bin/flush-knowledge-queue.sh
#   bash bin/flush-knowledge-queue.sh --dry-run   # show what would be written

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
QUEUE="$HYO_ROOT/kai/memory/knowledge-queue.jsonl"
KNOWLEDGE_MD="$HYO_ROOT/kai/memory/KNOWLEDGE.md"
LOCK="$HYO_ROOT/kai/memory/knowledge-queue.lock"
FLUSH_LOG="$HYO_ROOT/kai/ledger/knowledge-flush.log"
DRY_RUN=false

mkdir -p "$(dirname "$QUEUE")" "$(dirname "$FLUSH_LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

log() { echo "[$NOW_MT] $*" | tee -a "$FLUSH_LOG"; }
log_why() { echo "[$NOW_MT][WHY] $*" | tee -a "$FLUSH_LOG"; }

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Check queue exists and is non-empty ──────────────────────────────────────
if [[ ! -f "$QUEUE" ]]; then
  log "knowledge-queue.jsonl not found — nothing to flush"
  exit 0
fi

PENDING_COUNT=$(grep -c '"status":"pending_flush"' "$QUEUE" 2>/dev/null || echo 0)
if [[ "$PENDING_COUNT" -eq 0 ]]; then
  log "No pending entries in knowledge-queue.jsonl — flush skipped"
  log_why "WHY: all queue entries already marked flushed, or queue is empty"
  exit 0
fi

log "Found $PENDING_COUNT pending knowledge entries to flush"

# ── Exclusive lock (prevent concurrent flush runs) ────────────────────────────
exec 9>"$LOCK"
if ! flock -n 9; then
  log "ERROR: another flush is already running (lock held at $LOCK)"
  log_why "WHY: bail out — two concurrent flushes would cause the same race condition we're fixing"
  exit 1
fi
log_why "WHY: lock acquired — safe to write to KNOWLEDGE.md exclusively"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would flush $PENDING_COUNT entries:"
fi

# ── Flush entries into KNOWLEDGE.md ─────────────────────────────────────────
FLUSHED=0
ERRORS=0

python3 - "$QUEUE" "$KNOWLEDGE_MD" "$DRY_RUN" "$NOW_MT" << 'PYEOF'
import json, sys, os
from datetime import datetime

queue_path = sys.argv[1]
knowledge_path = sys.argv[2]
dry_run = sys.argv[3].lower() == "true"
flush_ts = sys.argv[4]

# Read all entries
entries = []
with open(queue_path) as f:
    for i, line in enumerate(f, 1):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            entries.append((i, entry))
        except json.JSONDecodeError as e:
            print(f"SKIP line {i}: invalid JSON — {e}")

pending = [(i, e) for i, e in entries if e.get('status') == 'pending_flush']
already_flushed = [(i, e) for i, e in entries if e.get('status') != 'pending_flush']

print(f"Queue: {len(entries)} total, {len(pending)} pending, {len(already_flushed)} already flushed")

if not pending:
    print("Nothing to flush.")
    sys.exit(0)

# Read current KNOWLEDGE.md
if os.path.exists(knowledge_path):
    content = open(knowledge_path).read()
else:
    content = "# KNOWLEDGE.md — Permanent Knowledge Layer\n"

# Build the block to append under ## Agent Improvements
new_entries_md = ""
for _, entry in pending:
    date = entry.get('date', entry.get('ts', '')[:10])
    agent = entry.get('agent', 'unknown')
    wid = entry.get('weakness_id', '?')
    wtitle = entry.get('weakness_title', '?')
    summary = entry.get('summary', '')
    new_entries_md += f"\n### [{date}] {agent} fixed {wid}: {wtitle}\n"
    new_entries_md += f"**What worked:** {summary}\n"
    new_entries_md += f"**Files changed:** see agents/{agent}/evolution.jsonl\n"
    new_entries_md += f"**Applicable to:** any agent with similar weakness\n"
    new_entries_md += f"**Flushed at:** {flush_ts}\n"

if dry_run:
    print(f"[DRY RUN] Would append to KNOWLEDGE.md:")
    print(new_entries_md)
else:
    # Insert under ## Agent Improvements section (or create it)
    marker = '## Agent Improvements'
    if marker in content:
        # Insert right after the section header line
        idx = content.index(marker) + len(marker)
        content = content[:idx] + new_entries_md + content[idx:]
    else:
        content += f"\n## Agent Improvements\n{new_entries_md}"
    open(knowledge_path, 'w').write(content)
    print(f"Wrote {len(pending)} entries to KNOWLEDGE.md")

    # Mark entries as flushed in the queue (rewrite queue file atomically)
    updated_entries = []
    for i, entry in entries:
        if entry.get('status') == 'pending_flush':
            entry['status'] = 'flushed'
            entry['flushed_at'] = flush_ts
        updated_entries.append(entry)

    tmp_path = queue_path + '.tmp'
    with open(tmp_path, 'w') as f:
        for entry in updated_entries:
            f.write(json.dumps(entry) + '\n')
    os.replace(tmp_path, queue_path)  # atomic rename
    print(f"Queue updated: {len(pending)} entries marked flushed")

print(f"FLUSH_COUNT:{len(pending)}")
PYEOF

FLUSH_EXIT=$?
if [[ $FLUSH_EXIT -eq 0 ]]; then
  log "Flush complete — $PENDING_COUNT entries written to KNOWLEDGE.md"
  log_why "WHY: flush succeeded at 01:00 MT boundary — no agents writing concurrently"
else
  log "ERROR: flush failed (exit $FLUSH_EXIT) — KNOWLEDGE.md unchanged"
  log_why "WHY: abort on flush error — partial writes would corrupt KNOWLEDGE.md"
fi

# Release lock
flock -u 9
exit $FLUSH_EXIT
