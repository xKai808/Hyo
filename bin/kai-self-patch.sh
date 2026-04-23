#!/usr/bin/env bash
# bin/kai-self-patch.sh — Apply Kai orchestrator improvements without deadlock
#
# PROBLEM: kai-autonomous.sh cannot modify itself while running (deadlock).
# SOLUTION: Kai's self-improve cycle writes patch instructions to a pending file.
#           This script reads those instructions and applies them on next idle cycle.
#           Called by: launchd (com.hyo.kai-self-patch.plist) at 04:00 MT daily,
#                      BEFORE kai-autonomous.sh starts for the day.
#
# Patch format (kai/ledger/pending-patches.jsonl):
#   {"id": "P001", "target": "bin/kai-autonomous.sh", "type": "append|replace",
#    "search": "old text", "replace": "new text", "reason": "...", "created": "..."}

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
PATCHES="$ROOT/kai/ledger/pending-patches.jsonl"
APPLIED="$ROOT/kai/ledger/applied-patches.jsonl"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

[[ ! -f "$PATCHES" ]] && echo "[kai-self-patch] No pending patches." && exit 0

applied=0
failed=0

python3 - "$ROOT" "$PATCHES" "$APPLIED" "$NOW_MT" << 'PYEOF'
import json, os, sys, shutil

root, patches_path, applied_path, ts = sys.argv[1:5]

with open(patches_path) as f:
    patches = [json.loads(l) for l in f if l.strip()]

remaining = []
for patch in patches:
    pid = patch.get('id', '?')
    target = os.path.join(root, patch.get('target', ''))
    ptype = patch.get('type', 'replace')
    reason = patch.get('reason', '')

    if not os.path.exists(target):
        print(f"[kai-self-patch] SKIP {pid}: target not found {target}")
        remaining.append(patch)
        continue

    try:
        with open(target) as f:
            content = f.read()

        if ptype == 'replace':
            search = patch.get('search', '')
            replace = patch.get('replace', '')
            if search not in content:
                print(f"[kai-self-patch] SKIP {pid}: search string not found in {target}")
                remaining.append(patch)
                continue
            new_content = content.replace(search, replace, 1)
        elif ptype == 'append':
            new_content = content + '\n' + patch.get('replace', '')
        else:
            print(f"[kai-self-patch] SKIP {pid}: unknown type {ptype}")
            remaining.append(patch)
            continue

        # Write atomically
        tmp = target + '.patch-tmp'
        with open(tmp, 'w') as f:
            f.write(new_content)
        os.replace(tmp, target)

        # Record as applied
        record = {**patch, 'applied_at': ts, 'status': 'applied'}
        with open(applied_path, 'a') as f:
            f.write(json.dumps(record) + '\n')

        print(f"[kai-self-patch] APPLIED {pid}: {reason[:80]}")

    except Exception as e:
        print(f"[kai-self-patch] FAILED {pid}: {e}")
        remaining.append(patch)

# Rewrite patches file with only unapplied patches
with open(patches_path, 'w') as f:
    for p in remaining:
        f.write(json.dumps(p) + '\n')

print(f"[kai-self-patch] Done. Applied: {len(patches)-len(remaining)}, remaining: {len(remaining)}")
PYEOF
