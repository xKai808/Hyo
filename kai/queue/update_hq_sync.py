#!/usr/bin/env python3
"""Update hq-state.json timestamps for this ops-sync run and dual-path sync.

Run via: HYO_ROOT=... bash kai/queue/exec.sh "python3 ~/Documents/Projects/Hyo/kai/queue/update_hq_sync.py"
"""
import json
import os
import shutil
from datetime import datetime, timezone

ROOT = os.path.expanduser('~/Documents/Projects/Hyo')
SAM_PATH = os.path.join(ROOT, 'agents/sam/website/data/hq-state.json')
WEB_PATH = os.path.join(ROOT, 'website/data/hq-state.json')

now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

note = (
    "Ops sync cycle @ 00:10 MT (2026-04-21, hq-ops-sync scheduled task — early run). "
    "Sentinel run #112: 5p/4f stable vs #111 — 0 new, 4 recurring, 0 resolved. "
    "Day 13 ESCALATED: P0 founder-token-integrity (mode 0600 vs 6xx — cosmetic), "
    "P1 scheduled-tasks-fired (aurora runs on Mini — benign), "
    "P1 secrets-dir-permissions (0755 on symlink — cosmetic). "
    "P2 task-queue-size 27 P0 tasks day 6 (counter persists). "
    "Cipher: clean, 0 findings, 7 permission autofixes, HQ push 200 OK. "
    "Nel: score 85/100 stable, 11 findings — 20 broken doc links (unchanged), "
    "25 untested scripts (unchanged), 3 inefficient patterns (unchanged), "
    "7 audit issues (5/7 checks passed — 5 sensitive files outside .secrets/), "
    "1 untriggered file (self-review), 0 verified leaks. "
    "Cross-project sentinel: hyo/aurora-ra/aether/kai-ceo all 4p/0f. "
    "ARIC research cycle ran (PLAYBOOK entry + brief published to ra/research/briefs/nel-2026-04-21.md). "
    "Self-delegated: nel-001 (P2) 20 broken-symlink fix, nel-001 (P3) cycle summary. "
    "Growth IMP-20260414-nel-002 CVE scanner still blocked (no package.json at root). "
    "Stderr noise: nel runner uses grep -P (BSD grep on macOS rejects) — P3 fix-it carried forward."
)

with open(SAM_PATH) as f:
    state = json.load(f)

state['updatedAt'] = now_utc

if state.get('events'):
    first = state['events'][0]
    if first.get('type') == 'ops-sync' and first.get('agent') == 'kai':
        first['ts'] = now_utc
        first['summary'] = (
            "Scheduled hq-ops-sync run (00:10 MT 4/21): sentinel 5p/4f stable (4 recurring, day 13), "
            "cipher clean (0 findings, 7 autofixes), nel score 85, 4 flags raised "
            "(P2 broken-links 20, P3 optimizations 3, P2 audit 7 issues, P2 untriggered-file)."
        )
        first.setdefault('details', {}).setdefault('nel', {})['flags'] = 4

mr = state.setdefault('morningReport', {})
mr['lastOpsSync'] = {
    'ts': now_utc,
    'note': note,
}
mr['summary'] = (
    "Ops sync cycle @ 00:10 MT on 2026-04-21 (hq-ops-sync scheduled task). "
    "Sentinel run #112: 5p/4f stable (4 recurring day 13). Cipher clean, 7 autofixes. "
    "Nel score 85/100, 11 findings (20 broken links, 25 untested, 3 inefficient, 7 audit, 1 untriggered, 0 leaks). "
    "Cross-project sentinel all 4p/0f. ARIC ran. Self-delegated: 20 broken-symlink fix P2 + cycle summary P3. "
    "Growth IMP-nel-002 still blocked. Nel runner stderr: grep -P unsupported on BSD."
)
mr['systemStatus'] = 'warnings'

with open(SAM_PATH, 'w') as f:
    json.dump(state, f, indent=2, ensure_ascii=False)

shutil.copyfile(SAM_PATH, WEB_PATH)

sam_size = os.path.getsize(SAM_PATH)
web_size = os.path.getsize(WEB_PATH)
print(f"Updated and synced.")
print(f"updatedAt: {state['updatedAt']}")
print(f"sam path:  {sam_size} bytes -> {SAM_PATH}")
print(f"web path:  {web_size} bytes -> {WEB_PATH}")
print(f"sizes match: {sam_size == web_size}")
