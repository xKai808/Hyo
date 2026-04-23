#!/usr/bin/env bash
# bin/improvement-approval.sh — Async approval gate for infrastructure-blocked improvements
#
# PROBLEM: agent-self-improve.sh blocks permanently when improvement needs infrastructure
#          (Vercel KV provisioning, new API keys, spending approval).
# SOLUTION: Instead of blocking, write to pending-approvals.jsonl.
#           Morning report surfaces approvals. Hyo types one response.
#           This script runs the improvement when approved.
#
# Usage:
#   improvement-approval.sh --list           # show pending approvals
#   improvement-approval.sh --approve ID     # approve and unblock improvement
#   improvement-approval.sh --reject ID      # reject (skip this improvement)

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
APPROVALS="$ROOT/kai/ledger/pending-approvals.jsonl"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

ACTION="${1:---list}"
TARGET_ID="${2:-}"

case "$ACTION" in
  --list)
    if [[ ! -f "$APPROVALS" ]] || [[ ! -s "$APPROVALS" ]]; then
      echo "No pending approvals."
      exit 0
    fi
    python3 -c "
import json
with open('$APPROVALS') as f:
    items = [json.loads(l) for l in f if l.strip()]
pending = [i for i in items if i.get('status') == 'pending']
if not pending:
    print('No pending approvals.')
else:
    print(f'{len(pending)} improvement(s) awaiting approval:')
    for i in pending:
        print(f'  [{i[\"id\"]}] {i[\"agent\"]}/{i[\"weakness\"]} — {i[\"reason\"]}')
        print(f'        Blocks: {i.get(\"blocks\",\"improvement cannot ship\")}')
"
    ;;

  --approve)
    python3 - "$APPROVALS" "$TARGET_ID" "$NOW_MT" << 'PYEOF'
import json, sys
path, tid, ts = sys.argv[1:4]
items = []
approved = None
with open(path) as f:
    for l in f:
        if l.strip():
            item = json.loads(l)
            if item['id'] == tid and item.get('status') == 'pending':
                item['status'] = 'approved'
                item['approved_at'] = ts
                approved = item
            items.append(item)
with open(path, 'w') as f:
    for item in items:
        f.write(json.dumps(item) + '\n')
if approved:
    print(f"Approved: {approved['agent']}/{approved['weakness']} — {approved['reason']}")
    print(f"The next self-improve cycle will unblock and execute this improvement.")
else:
    print(f"ID {tid} not found or already processed.")
PYEOF
    ;;

  --reject)
    python3 - "$APPROVALS" "$TARGET_ID" "$NOW_MT" << 'PYEOF'
import json, sys
path, tid, ts = sys.argv[1:4]
items = []
with open(path) as f:
    for l in f:
        if l.strip():
            item = json.loads(l)
            if item['id'] == tid and item.get('status') == 'pending':
                item['status'] = 'rejected'
                item['rejected_at'] = ts
            items.append(item)
with open(path, 'w') as f:
    for item in items:
        f.write(json.dumps(item) + '\n')
print(f"Rejected {tid}. Improvement will be skipped.")
PYEOF
    ;;
esac
