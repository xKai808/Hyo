#!/usr/bin/env bash
# agent-goals-sync.sh — S18-007/008: Daily agent goal renewal
# Reads each agent's ACTIVE.md + GROWTH.md and publishes a fresh
# "agent-goals" entry per agent to feed.json (both paths).
#
# Usage:
#   bash bin/agent-goals-sync.sh              # sync all agents
#   bash bin/agent-goals-sync.sh nel          # sync one agent
#   bash bin/agent-goals-sync.sh --verify     # verify without writing
#
# Called from: each agent runner (after main phases), and daily at 22:55 MT
# via kai report chain.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
TODAY="${SYNC_DATE:-$(TZ=America/Denver date '+%Y-%m-%d')}"
NOW_TS=$(TZ=America/Denver date '+%Y-%m-%dT%H:%M:%S-06:00')
VERIFY="${1:-}"
SINGLE_AGENT="${1:-}"

FEED_A="$ROOT/agents/sam/website/data/feed.json"
FEED_B="$ROOT/website/data/feed.json"

log() { echo "[$(TZ=America/Denver date '+%H:%M:%S')] agent-goals-sync: $*"; }

# ── Agent config ───────────────────────────────────────────────────────────────
# Format: "name|displayName|icon|color"
AGENTS=(
  "nel|Nel|🔍|#66c986"
  "ra|Ra|📰|#e8b877"
  "sam|Sam|⚙️|#8ac9e8"
  "aether|Aether|📈|#e8c96a"
  "dex|Dex|🧮|#c4a8f0"
  "hyo|hyo|✦|#a78bfa"
)

# ── Python parser ──────────────────────────────────────────────────────────────
parse_agent() {
  local agent_name="$1"
  local active_path="$ROOT/agents/${agent_name}/ledger/ACTIVE.md"
  local growth_path="$ROOT/agents/${agent_name}/GROWTH.md"

  python3 - "$active_path" "$growth_path" "$TODAY" "$NOW_TS" "$agent_name" << 'PYEOF'
import sys, json, re, os, datetime

active_path = sys.argv[1]
growth_path = sys.argv[2]
today       = sys.argv[3]
now_ts      = sys.argv[4]
agent_name  = sys.argv[5]

# ── Parse ACTIVE.md ────────────────────────────────────────────────────────────
def parse_active(path):
    in_progress = []
    completed_count = 0
    if not os.path.exists(path):
        return {'inProgress': [], 'completedCount': 0, 'lastUpdated': None}
    with open(path) as f:
        content = f.read()

    # Last updated timestamp
    lu_match = re.search(r'Last updated:\s*(.+)', content)
    last_updated = lu_match.group(1).strip() if lu_match else None

    # In Progress section
    ip_match = re.search(r'## In Progress\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
    if ip_match:
        text = ip_match.group(1)
        for m in re.finditer(r'- \*\*(\S+)\*\*\s+\[([^\]]+)\](.*?)(?=\n- \*\*|\Z)', text, re.DOTALL):
            ticket_id = m.group(1)
            priority  = m.group(2)
            rest      = m.group(3).strip()
            # First line of rest after [priority]
            first_line = rest.split('\n')[0].strip()
            # Remove brackets at start
            first_line = re.sub(r'^\[.*?\]\s*', '', first_line).strip()
            # Remove SAFEGUARD/AUTO-REMEDIATE verbose prefixes
            first_line = re.sub(r'^(SAFEGUARD|AUTO-REMEDIATE|REMEDIATE):\s*', '', first_line).strip()
            # Trim long titles
            if len(first_line) > 100:
                first_line = first_line[:97] + '...'
            if first_line:
                in_progress.append({
                    'id': ticket_id,
                    'priority': priority,
                    'title': first_line
                })
    in_progress = in_progress[:6]  # cap at 6

    # Completed count
    done_match = re.search(r'## (?:Completed|Done|Resolved)\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
    if done_match:
        completed_count = len(re.findall(r'- \*\*', done_match.group(1)))

    return {
        'inProgress': in_progress,
        'completedCount': completed_count,
        'lastUpdated': last_updated
    }

# ── Parse GROWTH.md ────────────────────────────────────────────────────────────
def parse_growth(path):
    weaknesses = []
    goals      = []
    if not os.path.exists(path):
        return {'weaknesses': [], 'goals': []}
    with open(path) as f:
        content = f.read()

    # W1/W2/W3 weakness titles
    for m in re.finditer(r'### (W\d): (.+?)(?:\n|$)', content):
        weaknesses.append({
            'id': m.group(1),
            'title': m.group(2).strip()
        })

    # Goals section — numbered list
    goals_match = re.search(r'## Goals.*?\n(.*?)(?=\n## |\Z)', content, re.DOTALL)
    if goals_match:
        goals_text = goals_match.group(1)
        for m in re.finditer(r'\d+\.\s+(.+?)(?=\n\d+\.|\Z)', goals_text, re.DOTALL):
            goal = m.group(1).strip()
            first_line = goal.split('\n')[0].strip()
            # Remove markdown bold from deadline
            first_line = re.sub(r'\*\*([^*]+)\*\*', r'\1', first_line).strip()
            if first_line and len(first_line) > 5:
                # Extract deadline if present
                deadline_match = re.match(r'(By \d{4}-\d{2}-\d{2}|By \w+ \d+):\s*(.*)', first_line)
                if deadline_match:
                    goals.append({
                        'deadline': deadline_match.group(1),
                        'text': deadline_match.group(2)[:120]
                    })
                else:
                    goals.append({'deadline': None, 'text': first_line[:120]})

    return {'weaknesses': weaknesses, 'goals': goals}

# ── Build feed entry ───────────────────────────────────────────────────────────
active = parse_active(active_path)
growth = parse_growth(growth_path)

in_progress = active['inProgress']
goals       = growth['goals']
weaknesses  = growth['weaknesses']

# Summary sentence
n_ip = len(in_progress)
n_goals = len(goals)
n_w = len(weaknesses)
active_last = active.get('lastUpdated', '?')

summary_parts = []
if n_ip > 0:
    summary_parts.append(f"{n_ip} task{'s' if n_ip!=1 else ''} in progress")
else:
    summary_parts.append("no active tasks")
if n_goals > 0:
    summary_parts.append(f"{n_goals} self-set goal{'s' if n_goals!=1 else ''}")
if n_w > 0:
    summary_parts.append(f"{n_w} tracked weakness{'es' if n_w!=1 else ''}")
summary = ' · '.join(summary_parts) + '.'

entry = {
    "id":           f"agent-goals-{agent_name}-{today}",
    "type":         "agent-goals",
    "title":        f"{agent_name.capitalize()} Goals \u2014 {today}",
    "author":       agent_name,
    "timestamp":    now_ts,
    "date":         today,
    "sections": {
        "summary":     summary,
        "inProgress":  in_progress,
        "goals":       goals,
        "weaknesses":  weaknesses,
        "activeLastUpdated": active_last
    }
}

print(json.dumps(entry))
PYEOF
}

# ── Upsert into feed.json ──────────────────────────────────────────────────────
upsert_feed() {
  local entry="$1"
  local feed_path="$2"
  if [[ ! -f "$feed_path" ]]; then
    log "WARN: $feed_path not found, skipping"
    return 1
  fi
  python3 - "$feed_path" "$entry" << 'PYEOF'
import json, sys

feed_path = sys.argv[1]
entry     = json.loads(sys.argv[2])
entry_id  = entry['id']

with open(feed_path) as f:
    data = json.load(f)

reports = data.setdefault('reports', [])
# Remove same-date+agent entry (idempotent)
agent  = entry.get('author', '')
edate  = entry.get('date', '')
reports[:] = [
    r for r in reports
    if not (r.get('type') == 'agent-goals'
            and r.get('author') == agent
            and r.get('date') == edate)
]
reports.append(entry)
# Sort by timestamp desc (most recent first)
reports.sort(key=lambda r: r.get('timestamp', ''), reverse=True)

with open(feed_path, 'w') as f:
    json.dump(data, f, indent=2)
print(f"[upsert] OK: {entry_id} → {feed_path}")
PYEOF
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  local filter="${SINGLE_AGENT:-}"
  local verify=0
  local total=0
  local ok=0

  if [[ "$filter" == "--verify" ]]; then
    log "Running in verify mode (no writes)"
    verify=1
    filter=""
  fi

  for spec in "${AGENTS[@]}"; do
    IFS='|' read -r aname display_name icon color <<< "$spec"

    # Skip if filtering to one agent
    if [[ -n "$filter" ]] && [[ "$filter" != "--verify" ]] && [[ "$aname" != "$filter" ]]; then
      continue
    fi

    total=$((total+1))
    log "Syncing $aname..."

    # Parse agent files
    entry_json=$(parse_agent "$aname" 2>/dev/null)
    if [[ -z "$entry_json" ]]; then
      log "WARN: $aname parse failed, skipping"
      continue
    fi

    # Inject author metadata from spec
    entry_json=$(python3 -c "
import json, sys
entry = json.loads(sys.stdin.read())
entry['authorIcon']  = '$icon'
entry['authorColor'] = '$color'
entry['title']       = '$display_name Goals \u2014 $TODAY'
print(json.dumps(entry))
" <<< "$entry_json")

    if [[ "$verify" -eq 1 ]]; then
      echo "$entry_json" | python3 -c "import json,sys; e=json.load(sys.stdin); print(f\"  {e['id']}: {e['sections']['summary']}\")"
      ok=$((ok+1))
      continue
    fi

    # Write to both feed paths
    upsert_feed "$entry_json" "$FEED_A" && \
    upsert_feed "$entry_json" "$FEED_B" && \
    ok=$((ok+1)) || log "WARN: upsert failed for $aname"
  done

  log "Done: $ok/$total agents synced for $TODAY"
  [[ "$ok" -eq "$total" ]]
}

main "$@"
