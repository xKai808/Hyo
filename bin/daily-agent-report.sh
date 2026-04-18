#!/usr/bin/env bash
# bin/daily-agent-report.sh — Generate and publish an agent's daily report to HQ feed
#
# Called at the end of each agent runner cycle (weekdays only).
# Reads the agent's ACTIVE.md, GROWTH.md, evolution.jsonl, and today's log
# to build a factual daily report — no theater, no sim-ack.
#
# Usage:
#   bash bin/daily-agent-report.sh <agent_name>
#   agent_name: nel | ra | sam | aether | kai | dex
#
# Exit 0 = published. Exit 1 = skipped (weekend) or failed.

set -uo pipefail

AGENT="${1:?Usage: daily-agent-report.sh <agent_name>}"
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
DOW=$(TZ=America/Denver date +%u)  # 1=Mon ... 7=Sun

# Skip weekends — no daily reports Saturday or Sunday
if [[ "$DOW" == "6" || "$DOW" == "7" ]]; then
  echo "[daily-report:$AGENT] Weekend — skipping daily report"
  exit 0
fi

FEED_GIT="$ROOT/agents/sam/website/data/feed.json"
FEED_LIVE="$ROOT/website/data/feed.json"
ENTRY_ID="${AGENT}-daily-${TODAY}"

# Skip if already published today
if python3 -c "
import json, sys
with open('$FEED_GIT') as f:
    d = json.load(f)
sys.exit(0 if any(r.get('id') == '$ENTRY_ID' for r in d.get('reports',[])) else 1)
" 2>/dev/null; then
  echo "[daily-report:$AGENT] Already published for $TODAY — skipping"
  exit 0
fi

# Agent metadata
declare -A AGENT_ICON=( [nel]="🔒" [ra]="📰" [sam]="⚙️" [aether]="📈" [kai]="👔" [dex]="🧬" )
declare -A AGENT_COLOR=( [nel]="#7ec4e0" [ra]="#b49af0" [sam]="#6dd49c" [aether]="#e8c96a" [kai]="#d4a853" [dex]="#e07060" )
declare -A AGENT_TITLE=( [nel]="Nel" [ra]="Ra" [sam]="Sam" [aether]="Aether" [kai]="Kai" [dex]="Dex" )

ICON="${AGENT_ICON[$AGENT]:-📄}"
COLOR="${AGENT_COLOR[$AGENT]:-var(--accent)}"
DISPLAY="${AGENT_TITLE[$AGENT]:-$AGENT}"

# Collect data from agent files
AGENT_DIR="$ROOT/agents/$AGENT"
ACTIVE_MD="$AGENT_DIR/ledger/ACTIVE.md"
GROWTH_MD="$AGENT_DIR/GROWTH.md"
EVOL_JSONL="$AGENT_DIR/evolution.jsonl"
LOG_FILE="$AGENT_DIR/logs/${AGENT}-${TODAY}.log"

# Kai uses different paths
if [[ "$AGENT" == "kai" ]]; then
  ACTIVE_MD="$ROOT/kai/ledger/kai-active.md"
  GROWTH_MD="$ROOT/kai/ledger/kai-active.md"
  EVOL_JSONL="$ROOT/kai/ledger/log.jsonl"
  LOG_FILE="$ROOT/kai/memory/daily/${TODAY}.md"
fi

python3 - "$AGENT" "$DISPLAY" "$ICON" "$COLOR" \
         "$TODAY" "$ENTRY_ID" \
         "${ACTIVE_MD:-/dev/null}" "${GROWTH_MD:-/dev/null}" \
         "${EVOL_JSONL:-/dev/null}" "${LOG_FILE:-/dev/null}" \
         "$FEED_GIT" "$FEED_LIVE" << 'PYEOF'
import json, os, re, sys, subprocess

agent, display, icon, color, today, entry_id, \
active_path, growth_path, evol_path, log_path, \
feed_git, feed_live = sys.argv[1:13]

def read_file(path, max_chars=4000):
    try:
        with open(path) as f:
            return f.read(max_chars)
    except:
        return ""

def get_mt():
    return subprocess.check_output(
        ["bash","-c","TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z"],
        text=True).strip()

active = read_file(active_path)
growth = read_file(growth_path)
evol   = read_file(evol_path, 8000)
log    = read_file(log_path)

# ── Extract completed items ──────────────────────────────────────────────────
completed = re.findall(r'##\s+Recently Completed.*?(?=##|\Z)', active, re.DOTALL)
completed_text = completed[0] if completed else ""
shipped_items = re.findall(r'\*\*[^\*]+\*\*.*?SHIPPED[^\n]*', completed_text)
if not shipped_items:
    shipped_items = re.findall(r'- \*\*[^\*]+\*\*[^\n]+DONE[^\n]*', completed_text)

# ── Extract in-progress ──────────────────────────────────────────────────────
in_progress = re.findall(r'##\s+In Progress(.*?)(?=##|\Z)', active, re.DOTALL)
wip_text = in_progress[0].strip() if in_progress else ""
wip_items = [l.strip() for l in wip_text.split('\n') if l.strip().startswith('- **')][:5]

# ── Count tickets ────────────────────────────────────────────────────────────
try:
    import subprocess as sp
    root = os.path.dirname(os.path.dirname(feed_git.replace('/agents/sam/website/data/feed.json','')))
    # Use the parent of agents/sam/website
    hyo_root = feed_git.replace('/agents/sam/website/data/feed.json','')
    tickets_path = os.path.join(hyo_root, 'kai/tickets/tickets.jsonl')
    today_tickets = {"opened": 0, "closed": 0, "pending": 0}
    if os.path.exists(tickets_path):
        with open(tickets_path) as tf:
            for line in tf:
                line = line.strip()
                if not line: continue
                try:
                    t = json.loads(line)
                    if t.get('agent', agent) != agent and agent != 'kai':
                        pass
                    s = t.get('status','')
                    if s in ('OPEN','ACTIVE','BLOCKED'): today_tickets["pending"] += 1
                    elif s in ('CLOSED','ARCHIVED','RESOLVED','SHIPPED'): today_tickets["closed"] += 1
                except: pass
except Exception as e:
    today_tickets = {"opened": 0, "closed": 0, "pending": 0}

# ── Extract today's growth/evolution entry ───────────────────────────────────
today_evol = ""
for line in reversed(evol.split('\n')):
    if today in line and '{' in line:
        try:
            e = json.loads(line)
            today_evol = e.get('summary', e.get('description', ''))[:300]
        except:
            pass
        if today_evol:
            break

# ── Extract weaknesses from GROWTH.md ───────────────────────────────────────
weaknesses = re.findall(r'\*\*W\d+[:\-][^\*]+\*\*[^\n]*', growth)[:3]
if not weaknesses:
    weaknesses = re.findall(r'W\d+[:\-][^\n]+', growth)[:3]

# ── Build sections ───────────────────────────────────────────────────────────
executed = f"Cycle ran for {today}. "
if wip_items:
    executed += f"Active work: {len(wip_items)} items in progress."
else:
    executed += "No active items — queue empty or idle."

shipped_str = ""
if shipped_items:
    shipped_str = "\n".join(shipped_items[:3])
else:
    # Check if today's log has shipped markers
    log_shipped = re.findall(r'SHIPPED[^\n]*|✓[^\n]+fixed[^\n]*|fix[^\n]+ship[^\n]*', log, re.IGNORECASE)
    shipped_str = log_shipped[0][:200] if log_shipped else "No new shipments today."

ticket_summary = f"Pending: {today_tickets['pending']} | Closed: {today_tickets['closed']}"

weakness_str = ""
if weaknesses:
    weakness_str = " | ".join(w.strip('* ').strip() for w in weaknesses[:2])
else:
    weakness_str = "See GROWTH.md for tracked weaknesses."

now = get_mt()

entry = {
    "id": entry_id,
    "type": "agent-daily",
    "title": f"{display} — Daily Report {today}",
    "author": display,
    "authorIcon": icon,
    "authorColor": color,
    "timestamp": now,
    "date": today,
    "sections": {
        "executed": executed,
        "shipped": shipped_str or "No new shipments today.",
        "active": "\n".join(wip_items) if wip_items else "Queue clear.",
        "tickets": ticket_summary,
        "weaknesses": weakness_str,
        "evolution": today_evol or "No evolution entry for today."
    }
}

def upsert_feed(path, entry):
    if not os.path.exists(path):
        return False
    with open(path) as f:
        d = json.load(f)
    reports = d.setdefault("reports", [])
    reports[:] = [r for r in reports if r.get("id") != entry["id"]]
    reports.insert(0, entry)
    d["lastUpdated"] = now
    with open(path, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    return True

ok1 = upsert_feed(feed_git, entry)
ok2 = upsert_feed(feed_live, entry)
print(f"[daily-report:{agent}] published {entry_id} git={ok1} live={ok2}")
if not (ok1 or ok2):
    sys.exit(1)
PYEOF
