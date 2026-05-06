#!/usr/bin/env bash
# bin/archive-to-research.sh — Archive a week's agent reports to research-archive.json
#
# Called by weekly-report.sh after all weekly reports are published.
# Takes agent-daily and agent-weekly entries from feed.json for the given week
# and appends them to research-archive.json, organized by agent and month.
#
# Usage:
#   bash bin/archive-to-research.sh <week>   e.g. 2026-W16

set -uo pipefail
WEEK="${1:?Usage: archive-to-research.sh <YYYY-WNN>}"
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"

FEED_GIT="$ROOT/agents/sam/website/data/feed.json"
ARCHIVE_GIT="$ROOT/agents/sam/website/data/research-archive.json"
ARCHIVE_LIVE="$ROOT/website/data/research-archive.json"

python3 - "$WEEK" "$FEED_GIT" "$ARCHIVE_GIT" "$ARCHIVE_LIVE" << 'PYEOF'
import json, os, sys, subprocess

week, feed_path, archive_git, archive_live = sys.argv[1:5]

def get_mt():
    import re
    raw = subprocess.check_output(
        ["bash","-c","TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z"],text=True).strip()
    return re.sub(r'([+-]\d{2})(\d{2})$', r'\1:\2', raw)

# Load feed
with open(feed_path) as f:
    feed = json.load(f)

# Collect this week's agent-daily and agent-weekly entries
archive_types = {"agent-daily", "agent-weekly", "agent-reflection"}
week_reports = [r for r in feed.get("reports", [])
                if r.get("type") in archive_types and r.get("week") == week
                or (r.get("type") in archive_types and r.get("date", "")[:7] >= week[:7])]

# Also include all agent-reflection reports older than 7 days (keep feed clean)
from datetime import datetime, timedelta
cutoff = (datetime.now() - timedelta(days=7)).strftime("%Y-%m-%d")
to_archive = [r for r in feed.get("reports", [])
              if r.get("type") in archive_types
              and r.get("date", "9999") <= cutoff]

# Load or init archive
def load_archive(path):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return {"agents": {}, "lastUpdated": ""}

def save_archive(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

now = get_mt()
archived_count = 0

for archive_path in [archive_git, archive_live]:
    arc = load_archive(archive_path)
    agents_data = arc.setdefault("agents", {})

    for r in to_archive:
        agent = r.get("author", "Unknown")
        date = r.get("date", r.get("timestamp", "")[:10])
        month = date[:7] if date else "unknown"

        # Organize: agents → agent_name → months → month → [reports]
        agent_data = agents_data.setdefault(agent, {"months": {}})
        months = agent_data.setdefault("months", {})
        month_data = months.setdefault(month, [])

        # Idempotent — don't re-add if already archived
        if not any(existing.get("id") == r.get("id") for existing in month_data):
            month_data.append(r)
            archived_count += 1

        # Sort each month descending
        months[month].sort(key=lambda x: x.get("date", ""), reverse=True)

    arc["lastUpdated"] = now
    arc["lastArchiveWeek"] = week
    save_archive(archive_path, arc)

# Remove archived entries from feed (keep last 14 days in live feed)
if to_archive:
    archive_ids = {r["id"] for r in to_archive}
    feed["reports"] = [r for r in feed["reports"] if r.get("id") not in archive_ids]
    feed["lastUpdated"] = now
    with open(feed_path, "w") as f:
        json.dump(feed, f, ensure_ascii=False, indent=2)
    print(f"[archive] removed {len(archive_ids)} entries from feed (moved to research archive)")

print(f"[archive] week={week} archived={archived_count} entries to research-archive.json")
PYEOF
