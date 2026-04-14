#!/usr/bin/env bash
# bin/process-forkai.sh — Kai inbox accountability loop
#
# Reads all agent feed reports from agents/sam/website/data/feed.json
# Extracts the "forKai" field from each report's sections
# Checks if the item is already logged in kai/ledger/forkai-inbox.jsonl
# If not, appends a new JSONL entry
# Lists all unreviewed items at the end
#
# Usage: bash bin/process-forkai.sh
#        Run as part of healthcheck or manually

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
FEED="$ROOT/agents/sam/website/data/feed.json"
INBOX="$ROOT/kai/ledger/forkai-inbox.jsonl"
LOG_TAG="[process-forkai]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

# Ensure inbox file exists
if [[ ! -f "$INBOX" ]]; then
  log "Creating new forKai inbox at $INBOX"
  mkdir -p "$(dirname "$INBOX")"
  touch "$INBOX"
fi

# If feed doesn't exist, exit gracefully
if [[ ! -f "$FEED" ]]; then
  log "WARNING: Feed file not found at $FEED — skipping"
  exit 0
fi

log "Processing forKai items from feed..."

python3 << PYEOF
import json
import sys
from datetime import datetime

feed_path = "$FEED"
inbox_path = "$INBOX"

# Load feed
try:
    with open(feed_path) as f:
        feed = json.load(f)
except Exception as e:
    print(f"[ERROR] Failed to read feed: {e}")
    sys.exit(1)

# Load existing inbox
existing = set()
try:
    if sys.modules.get('pathlib'):
        from pathlib import Path
        if Path(inbox_path).exists():
            with open(inbox_path) as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            item = json.loads(line)
                            # Use timestamp + agent + message as unique key
                            key = (item.get('ts'), item.get('agent'), item.get('message')[:100])
                            existing.add(key)
                        except:
                            pass
    else:
        import os
        if os.path.exists(inbox_path):
            with open(inbox_path) as f:
                for line in f:
                    line = line.strip()
                    if line:
                        try:
                            item = json.loads(line)
                            key = (item.get('ts'), item.get('agent'), item.get('message')[:100])
                            existing.add(key)
                        except:
                            pass
except Exception as e:
    print(f"[WARNING] Could not load existing inbox: {e}")

# Extract forKai items from reports
new_items = []
reports = feed.get('reports', [])

for report in reports:
    # Check for forKai field in sections
    sections = report.get('sections', {})

    # forKai could be a string, list, or dict
    for_kai = sections.get('forKai')
    if for_kai:
        agent = report.get('author', 'unknown').lower()
        ts = report.get('timestamp', datetime.now().isoformat())

        # Handle different forKai formats
        if isinstance(for_kai, list):
            for msg in for_kai:
                new_items.append({
                    'ts': ts,
                    'agent': agent,
                    'message': str(msg),
                    'status': 'unreviewed',
                    'kai_response': ''
                })
        elif isinstance(for_kai, str):
            new_items.append({
                'ts': ts,
                'agent': agent,
                'message': for_kai,
                'status': 'unreviewed',
                'kai_response': ''
            })
        elif isinstance(for_kai, dict):
            # If it has a 'message' field, use that; otherwise stringify the whole thing
            msg = for_kai.get('message', json.dumps(for_kai))
            new_items.append({
                'ts': ts,
                'agent': agent,
                'message': msg,
                'status': 'unreviewed',
                'kai_response': ''
            })

# Append new items that aren't already in inbox
new_count = 0
with open(inbox_path, 'a') as f:
    for item in new_items:
        key = (item['ts'], item['agent'], item['message'][:100])
        if key not in existing:
            f.write(json.dumps(item) + '\n')
            new_count += 1
            existing.add(key)

print(f"[+] {new_count} new forKai items added to inbox")

# List all unreviewed items
print("\n=== UNREVIEWED KAI INBOX ITEMS ===")
try:
    with open(inbox_path) as f:
        unreviewed = []
        for line in f:
            line = line.strip()
            if line:
                try:
                    item = json.loads(line)
                    if item.get('status') == 'unreviewed':
                        unreviewed.append(item)
                except:
                    pass

    if unreviewed:
        print(f"\nFound {len(unreviewed)} unreviewed items:")
        for i, item in enumerate(unreviewed, 1):
            print(f"\n{i}. [{item.get('agent', '?').upper()}] {item.get('ts', '?')}")
            print(f"   {item.get('message', '?')}")
    else:
        print("No unreviewed items in inbox.")
except Exception as e:
    print(f"[ERROR] Failed to list inbox items: {e}")

PYEOF
