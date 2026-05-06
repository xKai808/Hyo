#!/usr/bin/env bash
# bin/weekly-maintenance.sh — Autonomous weekly context + memory upkeep
#
# Runs every Saturday at 02:00 MT via kai-autonomous.sh
# Zero manual intervention required — fully autonomous
#
# What it does:
# 1. Compact tickets.jsonl (trim bloated notes arrays, archive resolved)
# 2. Archive old KAI_BRIEF sections (keep last 2 sessions)
# 3. Archive completed KAI_TASKS (keep only active)
# 4. Rotate JSONL logs (cap at 100 entries)
# 5. Report savings to morning report

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
LOG="$ROOT/kai/ledger/weekly-maintenance.log"

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }

log "=== Weekly Maintenance — $TODAY ==="

# ── 1. Compact tickets.jsonl ──────────────────────────────────────────────────
TICKETS="$ROOT/kai/tickets/tickets.jsonl"
if [[ -f "$TICKETS" ]]; then
    python3 - "$TICKETS" "$TODAY" << 'PYEOF'
import json, os, sys

tickets_path, today = sys.argv[1:3]
valid = []
with open(tickets_path) as f:
    for l in f:
        l = l.strip()
        if l:
            try: valid.append(json.loads(l))
            except: pass

before_size = os.path.getsize(tickets_path)

archive_path = tickets_path.replace('.jsonl', f'-archive-{today}.jsonl')

# Separate: archive resolved/closed, keep active
archived = []
active = []
for t in valid:
    status = t.get('status', '')
    if status in ('RESOLVED', 'CLOSED', 'ARCHIVED', 'SHIPPED'):
        # Keep minimal info for archive
        archived.append({k: v for k, v in t.items() 
                         if k in ('id', 'title', 'owner', 'priority', 'status', 'created_at', 'updated_at')})
    else:
        # Compact notes: keep last 20 items only (not 11,318!)
        if isinstance(t.get('notes'), list) and len(t['notes']) > 20:
            t = dict(t)  # copy
            t['notes'] = t['notes'][-20:]  # keep last 20
        active.append(t)

# Write compact tickets
with open(tickets_path, 'w') as f:
    for t in active:
        f.write(json.dumps(t) + '\n')

# Write archive
if archived:
    with open(archive_path, 'a') as f:
        for t in archived:
            f.write(json.dumps(t) + '\n')

after_size = os.path.getsize(tickets_path)
print(f"tickets.jsonl: {before_size/1024/1024:.1f}MB → {after_size/1024/1024:.1f}MB "
      f"({len(active)} active, {len(archived)} archived)")
PYEOF
    log "Tickets compacted"
fi

# ── 2. Archive old KAI_BRIEF sections ────────────────────────────────────────
BRIEF="$ROOT/KAI_BRIEF.md"
if [[ -f "$BRIEF" ]]; then
    python3 - "$BRIEF" "$ROOT" "$TODAY" << 'PYEOF'
import re, os, sys
brief_path, root, today = sys.argv[1:4]
with open(brief_path) as f:
    content = f.read()

sections = re.split(r'\n(?=## )', content)
header = sections[0]
sections = sections[1:]

# Keep: current state, last 2 shipped sessions, open P0s
keep_kw = ['current', 'open p0', 'shipped this session (2026-04', 'shipped today (2026-04']
keep, archive = [], []
for s in sections:
    first = s.split('\n')[0].lower()
    if any(kw in first for kw in keep_kw):
        keep.append(s)
    else:
        archive.append(s)

old_size = len(content)
new_content = header + '\n' + '\n'.join('## ' + s for s in keep)
new_size = len(new_content)

if new_size < old_size * 0.95:  # Only write if meaningful reduction
    arch_path = os.path.join(root, f'KAI_BRIEF-archive-{today}.md')
    with open(arch_path, 'w') as f:
        f.write(f'# KAI_BRIEF Archive — {today}\n\n')
        for s in archive:
            f.write('## ' + s + '\n')
    with open(brief_path, 'w') as f:
        f.write(new_content)
    print(f"KAI_BRIEF.md: {old_size/1024:.0f}KB → {new_size/1024:.0f}KB (archived {len(archive)} sections)")
else:
    print(f"KAI_BRIEF.md: no significant reduction needed ({old_size/1024:.0f}KB)")
PYEOF
    log "KAI_BRIEF archived"
fi

# ── 3. Archive completed KAI_TASKS ──────────────────────────────────────────
TASKS="$ROOT/KAI_TASKS.md"
if [[ -f "$TASKS" ]]; then
    python3 - "$TASKS" "$ROOT" "$TODAY" << 'PYEOF'
import re, os, sys
tasks_path, root, today = sys.argv[1:4]
with open(tasks_path) as f:
    content = f.read()

lines = content.split('\n')
active, done = [], []
in_done = False

for line in lines:
    if re.match(r'^#+\s*(Done|Completed|Archived)', line, re.I):
        in_done = True
    elif re.match(r'^#+\s', line) and not re.match(r'^#+\s*(Done|Completed|Archived)', line, re.I):
        in_done = False
    (done if in_done else active).append(line)

old_size = len(content)
new_content = '\n'.join(active)
new_size = len(new_content)

if len(done) > 10 and new_size < old_size * 0.95:
    arch_path = os.path.join(root, f'KAI_TASKS-done-archive-{today}.md')
    with open(arch_path, 'w') as f:
        f.write(f'# KAI_TASKS Done Archive — {today}\n\n')
        f.write('\n'.join(done))
    with open(tasks_path, 'w') as f:
        f.write(new_content)
    print(f"KAI_TASKS.md: {old_size/1024:.0f}KB → {new_size/1024:.0f}KB (archived done sections)")
else:
    print(f"KAI_TASKS.md: {old_size/1024:.0f}KB, no archiving needed")
PYEOF
    log "KAI_TASKS archived"
fi

# ── 4. Rotate JSONL logs ─────────────────────────────────────────────────────
HYO_ROOT="$ROOT" python3 "$ROOT/bin/context-optimizer.py" --rotate-logs >> "$LOG" 2>&1
log "JSONL logs rotated"

# ── 4.5. Trim bloated ledger files ───────────────────────────────────────────
# guidance.jsonl and hyo-inbox.jsonl grow unbounded. Archive entries >30d old.
python3 - "$ROOT" << 'PYEOF'
import json, os, sys
from datetime import datetime, timezone, timedelta

root = sys.argv[1]
today = datetime.now(timezone.utc)
cutoff = today - timedelta(days=30)

ledger_files = {
    'guidance.jsonl': os.path.join(root, 'kai/ledger/guidance.jsonl'),
    'hyo-inbox.jsonl': os.path.join(root, 'kai/ledger/hyo-inbox.jsonl'),
}

for name, path in ledger_files.items():
    if not os.path.exists(path):
        continue

    with open(path) as f:
        lines = [l.strip() for l in f if l.strip()]

    keep, archive = [], []
    for line in lines:
        try:
            entry = json.loads(line)
            # Try common timestamp fields
            ts_str = entry.get('timestamp') or entry.get('created_at') or entry.get('date') or ''
            if ts_str:
                ts = datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
                if ts < cutoff:
                    archive.append(line)
                    continue
        except Exception:
            pass
        keep.append(line)

    if archive:
        year_month = today.strftime('%Y/%m')
        arch_dir = os.path.join(root, f'kai/ledger/archive/{year_month}')
        os.makedirs(arch_dir, exist_ok=True)
        arch_path = os.path.join(arch_dir, f'{name.replace(".jsonl", "")}-pre-{today.strftime("%Y-%m-%d")}.jsonl')
        with open(arch_path, 'a') as f:
            f.write('\n'.join(archive) + '\n')
        with open(path, 'w') as f:
            f.write('\n'.join(keep) + '\n')
        old_kb = sum(len(l)+1 for l in lines) / 1024
        new_kb = sum(len(l)+1 for l in keep) / 1024
        print(f"  {name}: {old_kb:.0f}KB → {new_kb:.0f}KB (archived {len(archive)} entries >30d)")
    else:
        print(f"  {name}: no entries older than 30d to archive ({len(lines)} entries kept)")
PYEOF
log "Ledger files trimmed (guidance.jsonl, hyo-inbox.jsonl — entries >30d archived)"

# ── 4.6. Archive old research/raw + logs (>30 days) ──────────────────────────
if [[ -f "$ROOT/bin/archive-old-files.sh" ]]; then
  HYO_ROOT="$ROOT" bash "$ROOT/bin/archive-old-files.sh" --days 30 >> "$LOG" 2>&1
  log "Old files archived (research/raw, logs, output >30d compressed to tar.gz)"
fi

# ── 4.7. Dex organization audit (dual-path gaps, silos, stale cross-refs) ────
if [[ -f "$ROOT/agents/dex/dex.sh" ]]; then
  HYO_ROOT="$ROOT" bash "$ROOT/agents/dex/dex.sh" --org-audit >> "$LOG" 2>&1
  log "Dex organization audit complete — see agents/dex/logs/organization-$(date +%Y-%m-%d).md"
fi

# ── 5. Report final state ─────────────────────────────────────────────────────
python3 - "$ROOT" << 'PYEOF'
import os
root = sys.argv[1] if __import__('sys').argv[1:] else '.'
import sys
root = sys.argv[1]
files = {
    'KAI_BRIEF.md': 'KAI_BRIEF.md',
    'KAI_TASKS.md': 'KAI_TASKS.md',
    'tickets.jsonl': 'kai/tickets/tickets.jsonl',
    'hyo-inbox.jsonl': 'kai/ledger/hyo-inbox.jsonl',
    'known-issues.jsonl': 'kai/ledger/known-issues.jsonl',
}
total = 0
for name, rel in files.items():
    path = os.path.join(root, rel)
    if os.path.exists(path):
        size = os.path.getsize(path)
        total += size
        print(f"  {name}: {size/1024:.1f}KB")
print(f"  TOTAL: {total/1024:.1f}KB (~{total//4:,} tokens, ~${total//4/1_000_000*3:.4f}/session)")
PYEOF
log "=== Maintenance complete ==="
