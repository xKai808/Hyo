#!/usr/bin/env bash
# bin/publish-to-feed.sh — Publish a report entry to the HQ feed
#
# Used by agent runners and Kai to post reports to the feed.
# Each call appends one report entry to website/data/feed.json.
#
# Usage:
#   bash bin/publish-to-feed.sh <type> <author> <title> <json-sections-file>
#
# Types: morning-report, ceo-report, agent-reflection, research-drop
# Sections file: a JSON file with the report sections (varies by type)
#
# Example:
#   bash bin/publish-to-feed.sh agent-reflection nel "Nel — Overnight Reflection" /tmp/nel-sections.json
#
# The sections JSON format depends on report type:
#   agent-reflection: {"introspection":"...","research":"...","changes":"...","followUps":["..."],"forKai":"..."}
#   ceo-report:       {"direction":"...","priorities":["..."],"agentGrowth":"...","risks":"..."}
#   research-drop:    {"topic":"...","finding":"...","implications":"...","nextSteps":["..."]}

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
FEED="$ROOT/website/data/feed.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)
MONTH_KEY=$(echo "$TODAY" | cut -c1-7)

TYPE="${1:?Usage: publish-to-feed.sh <type> <author> <title> <sections-json-file>}"
AUTHOR="${2:?Missing author}"
TITLE="${3:?Missing title}"
SECTIONS_FILE="${4:?Missing sections JSON file}"

if [[ ! -f "$SECTIONS_FILE" ]]; then
  echo "ERROR: sections file not found: $SECTIONS_FILE" >&2
  exit 1
fi

# Agent metadata lookup
declare -A ICONS=( [kai]="👔" [nel]="🔧" [sam]="⚙️" [ra]="📰" [aether]="📈" [dex]="🗃️" )
declare -A COLORS=( [kai]="#d4a853" [nel]="#6dd49c" [sam]="#7ec4e0" [ra]="#b49af0" [aether]="#e8c96a" [dex]="#e07060" )

AUTHOR_LC=$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')
ICON="${ICONS[$AUTHOR_LC]:-📋}"
COLOR="${COLORS[$AUTHOR_LC]:-#888888}"
AUTHOR_NAME=$(echo "$AUTHOR" | sed 's/^./\U&/')

# Generate unique ID
REPORT_ID="${TYPE}-${AUTHOR_LC}-${TODAY}-$(date +%H%M%S)"

python3 - "$FEED" "$REPORT_ID" "$TYPE" "$AUTHOR_NAME" "$ICON" "$COLOR" \
          "$NOW_MT" "$TODAY" "$MONTH_KEY" "$TITLE" "$SECTIONS_FILE" <<'PYEOF'
import json, sys, os

feed_path    = sys.argv[1]
report_id    = sys.argv[2]
report_type  = sys.argv[3]
author       = sys.argv[4]
icon         = sys.argv[5]
color        = sys.argv[6]
timestamp    = sys.argv[7]
date         = sys.argv[8]
month_key    = sys.argv[9]
title        = sys.argv[10]
sections_file= sys.argv[11]

# Read sections
with open(sections_file) as f:
    sections = json.load(f)

# Build entry
entry = {
    "id": report_id,
    "type": report_type,
    "title": title,
    "author": author,
    "authorIcon": icon,
    "authorColor": color,
    "timestamp": timestamp,
    "date": date,
    "sections": sections
}

# Read existing feed
feed = {"lastUpdated": timestamp, "today": date, "agents": {}, "reports": [], "history": {}}
if os.path.exists(feed_path):
    try:
        with open(feed_path) as f:
            feed = json.load(f)
    except:
        pass

# Update
feed["lastUpdated"] = timestamp
feed["today"] = date
feed["reports"].append(entry)
feed["reports"].sort(key=lambda r: r.get("timestamp", ""), reverse=True)

# History
if month_key not in feed.get("history", {}):
    months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    m_idx = int(month_key.split("-")[1]) - 1
    label = f"{months[m_idx]} {month_key.split('-')[0]}"
    feed["history"][month_key] = {"label": label, "reports": []}

if report_id not in feed["history"][month_key]["reports"]:
    feed["history"][month_key]["reports"].append(report_id)

with open(feed_path, "w") as f:
    json.dump(feed, f, indent=2)

print(f"Published to feed: [{report_type}] {title} by {author}")
PYEOF

echo "Feed entry published: $REPORT_ID"
