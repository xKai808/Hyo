#!/usr/bin/env python3
"""Update hq-state.json for 2026-04-22 08:10 MT ops-sync cycle (scheduled task).

Run via: HYO_ROOT=... bash kai/queue/exec.sh "python3 ~/Documents/Projects/Hyo/kai/queue/update_hq_ops_0810.py"
"""
import json
import os
import shutil
from datetime import datetime, timezone

ROOT = os.path.expanduser('~/Documents/Projects/Hyo')
SAM_PATH = os.path.join(ROOT, 'agents/sam/website/data/hq-state.json')
WEB_PATH = os.path.join(ROOT, 'website/data/hq-state.json')

now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

# Results from this ops-sync run (08:09-08:10 MT on 2026-04-22)
SENTINEL_RUN_ID = 130
SENTINEL = {
    "lastRunId": SENTINEL_RUN_ID,
    "lastRunAt": now_utc,
    "passed": 7,
    "failed": 2,
    "new": 0,
    "recurring": 2,
    "resolved": 2,
    "regression": False,
}
CIPHER = {
    "lastRunAt": now_utc,
    "findings": 0,
    "autofixes": 7,
    "leaks": 0,
    "founderToken": "600",
    "secretsDir": "700",
}

EVENT_MSG = (
    "Ops sync cycle @ 08:10 MT (2026-04-22, hq-ops-sync 3rd of day). "
    f"Sentinel #{SENTINEL_RUN_ID}: 7p/2f — 0 new, 2 recurring, 2 resolved "
    "(api-health-green:82547bfc, scheduled-tasks-fired:cdc05baa cleared this run). "
    "Remaining recurring: P1 scheduled-tasks-fired day 21 (no aurora logs — structural), "
    "P2 task-queue-size 29 P0 tasks day 13. "
    "Cipher clean (0 findings, 7 permission autofixes, HQ push 200 OK). "
    "Nel: score 65→85 (+20), 1 finding in block, 13 findings in self-review. "
    "Flags raised: P2 broken-links 20, P3 code-optimizations 8, P2 audit 7 issues. "
    "Self-delegated: nel-001 P2 (20 broken symlinks fix), nel-001 P3 (cycle summary). "
    "ARIC cycle already ran today — skipped. Dual-path hq-state.json sync enforced."
)

NOTE = (
    "Ops sync cycle @ 08:10 MT (2026-04-22, hq-ops-sync scheduled task, 3rd of day). "
    f"Sentinel run #{SENTINEL_RUN_ID}: 7p/2f — 0 new, 2 recurring, 2 resolved. "
    "Cipher clean: 0 findings, 7 permission autofixes, 0 leaks, HQ push 200. "
    "Nel score 65→85 (+20). Self-review: 13 findings. "
    "Flags: P2 broken-links (20 unchanged), P3 optimizations (8), P2 audit (7 issues). "
    "Self-delegated P2 20-broken-symlink fix + P3 cycle summary. "
    "Growth IMP-nel idle (no open IMP tickets). Stderr noise: nel runner grep -P "
    "unsupported on BSD (carried forward P3)."
)

with open(SAM_PATH) as f:
    state = json.load(f)

state['updatedAt'] = now_utc
state['sentinel'] = SENTINEL
state['cipher'] = CIPHER

# Prepend a fresh event (newest first)
new_event = {
    "ts": now_utc,
    "agent": "kai",
    "msg": EVENT_MSG,
    "severity": "warning",
}
events = state.setdefault('events', [])
events.insert(0, new_event)

# Keep events list bounded (keep last 200 to prevent unbounded growth)
if len(events) > 200:
    state['events'] = events[:200]

# Update morningReport
mr = state.setdefault('morningReport', {})
mr['lastOpsSync'] = {
    'ts': now_utc,
    'note': NOTE,
}
mr['summary'] = (
    "Ops sync 08:10 MT on 2026-04-22 (3rd cycle of day). "
    f"Sentinel #{SENTINEL_RUN_ID} 7p/2f (2 recurring, 2 resolved — first meaningful clear-out of stale checks). "
    "Cipher clean, 7 autofixes. Nel score 65→85 (+20). "
    "13 findings in self-review. 3 flags: P2 broken-links 20, P3 optimizations 8, P2 audit 7. "
    "Self-delegated P2 broken-symlink fix + P3 cycle summary."
)
mr['systemStatus'] = 'warnings'

# Write to primary (sam) path with atomic replace
tmp = SAM_PATH + '.tmp'
with open(tmp, 'w') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)
os.replace(tmp, SAM_PATH)

# Dual-path sync (SE-010-011 prevention): copy to website/ path
shutil.copyfile(SAM_PATH, WEB_PATH)

sam_size = os.path.getsize(SAM_PATH)
web_size = os.path.getsize(WEB_PATH)
print("Updated and dual-synced.")
print(f"updatedAt:   {state['updatedAt']}")
print(f"sentinel:    {json.dumps(SENTINEL)}")
print(f"cipher:      {json.dumps(CIPHER)}")
print(f"nel.lastRun: {state.get('nel',{}).get('lastRun')}")
print(f"sam path:    {sam_size} bytes -> {SAM_PATH}")
print(f"web path:    {web_size} bytes -> {WEB_PATH}")
print(f"sizes match: {sam_size == web_size}")
