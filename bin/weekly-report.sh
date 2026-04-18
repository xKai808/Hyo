#!/usr/bin/env bash
# bin/weekly-report.sh — Saturday weekly report for ALL agents
#
# Runs every Saturday. For each agent:
#   1. Generates weekly summary (weaknesses, improvements, tickets)
#   2. Triggers all pending tickets to complete within 1 hour
#   3. Publishes agent-weekly feed entry
#   4. Calls archive-to-research.sh to move week's reports to research archive
#
# Scheduled: Saturday 06:00 MT via com.hyo.weekly-report.plist
# Manual: HYO_ROOT=/... bash bin/weekly-report.sh [--force]

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
FORCE="${1:-}"
DOW=$(TZ=America/Denver date +%u)  # 6=Sat

if [[ "$DOW" != "6" && "$FORCE" != "--force" ]]; then
  echo "[weekly] Not Saturday (dow=$DOW). Use --force to override."
  exit 0
fi

FEED_GIT="$ROOT/agents/sam/website/data/feed.json"
FEED_LIVE="$ROOT/website/data/feed.json"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
WEEK=$(TZ=America/Denver date +%Y-W%V)
WEEK_START=$(TZ=America/Denver date -v-6d +%Y-%m-%d 2>/dev/null || TZ=America/Denver date -d '6 days ago' +%Y-%m-%d)

log() { echo "[weekly $(TZ=America/Denver date +%H:%M:%S)] $*"; }
log "=== Weekly report starting for $WEEK ==="

AGENTS=("nel" "ra" "sam" "aether" "kai")

# ── Step 1: Trigger all pending tickets to complete within 1hr ───────────────
log "Triggering pending tickets (1hr SLA)..."
TICKETS_PATH="$ROOT/kai/tickets/tickets.jsonl"
TRIGGERED=0
if [[ -f "$TICKETS_PATH" ]]; then
  python3 - "$TICKETS_PATH" "$TODAY" << 'PYTRIG'
import json, sys, os
from datetime import datetime, timedelta
import subprocess

tickets_path, today = sys.argv[1:3]
now_str = subprocess.check_output(
    ["bash","-c","TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z"],text=True).strip()

lines = []
triggered = 0
with open(tickets_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            t = json.loads(line)
            if t.get('status') in ('OPEN', 'ACTIVE', 'BLOCKED'):
                t['weekly_deadline'] = now_str
                t['weekly_triggered'] = today
                t['sla_override'] = '1hr'
                t['status'] = 'ACTIVE'
                triggered += 1
            lines.append(json.dumps(t))
        except:
            lines.append(line)

with open(tickets_path, 'w') as f:
    f.write('\n'.join(lines) + '\n')

print(f"[tickets] triggered {triggered} pending → ACTIVE with 1hr SLA")
PYTRIG
fi

# ── Step 2: Generate per-agent weekly reports ────────────────────────────────
generate_weekly() {
  local agent="$1"
  python3 - "$agent" "$WEEK" "$WEEK_START" "$TODAY" \
            "$ROOT" "$FEED_GIT" "$FEED_LIVE" << 'PYWEEK'
import json, os, re, sys, subprocess
from datetime import datetime, timedelta

agent, week, week_start, today, root, feed_git, feed_live = sys.argv[1:8]

ICONS  = {"nel":"🔒","ra":"📰","sam":"⚙️","aether":"📈","kai":"👔","dex":"🧬"}
COLORS = {"nel":"#7ec4e0","ra":"#b49af0","sam":"#6dd49c","aether":"#e8c96a","kai":"#d4a853","dex":"#e07060"}
NAMES  = {"nel":"Nel","ra":"Ra","sam":"Sam","aether":"Aether","kai":"Kai","dex":"Dex"}

icon  = ICONS.get(agent, "📄")
color = COLORS.get(agent, "#aaa")
name  = NAMES.get(agent, agent.capitalize())

def read_file(path, max_chars=6000):
    try:
        with open(path) as f:
            return f.read(max_chars)
    except:
        return ""

def get_mt():
    return subprocess.check_output(
        ["bash","-c","TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z"],text=True).strip()

# Paths
if agent == "kai":
    growth_path  = os.path.join(root, "kai/ledger/kai-active.md")
    evol_path    = os.path.join(root, "kai/ledger/log.jsonl")
    active_path  = os.path.join(root, "kai/ledger/kai-active.md")
else:
    growth_path  = os.path.join(root, f"agents/{agent}/GROWTH.md")
    evol_path    = os.path.join(root, f"agents/{agent}/evolution.jsonl")
    active_path  = os.path.join(root, f"agents/{agent}/ledger/ACTIVE.md")

growth  = read_file(growth_path)
evol    = read_file(evol_path, 12000)
active  = read_file(active_path)

# ── Weaknesses ──────────────────────────────────────────────────────────────
weaknesses = []
for m in re.finditer(r'\*\*(W\d+)[:\-]([^\*]+)\*\*([^\n]*)', growth):
    weaknesses.append(f"{m.group(1)}: {m.group(2).strip()} — {m.group(3).strip()}"[:200])
if not weaknesses:
    # Fallback: find any W1/W2/W3 lines
    for line in growth.split('\n'):
        m = re.match(r'.*W(\d)[:\-\s](.+)', line)
        if m:
            weaknesses.append(f"W{m.group(1)}: {m.group(2).strip()}"[:200])
weaknesses = weaknesses[:3]

# ── Improvements shipped this week ──────────────────────────────────────────
shipped = []
# Parse evolution.jsonl for this week's entries
for line in evol.split('\n'):
    line = line.strip()
    if not line or '{' not in line:
        continue
    try:
        e = json.loads(line)
        entry_date = e.get('ts', e.get('date', ''))[:10]
        if week_start <= entry_date <= today:
            typ = e.get('type', e.get('ticket_type', ''))
            if typ in ('improvement', 'shipped', 'fix') or e.get('improvement_description'):
                desc = e.get('improvement_description') or e.get('summary') or e.get('description', '')
                if desc and len(desc) > 10:
                    shipped.append(desc[:200])
    except:
        pass
shipped = shipped[:5]

# ── Tickets this week ────────────────────────────────────────────────────────
tickets_path = os.path.join(root, "kai/tickets/tickets.jsonl")
week_tickets = {"total": 0, "resolved": 0, "pending": 0, "triggered": 0}
pending_list = []
if os.path.exists(tickets_path):
    with open(tickets_path) as tf:
        for line in tf:
            line = line.strip()
            if not line: continue
            try:
                t = json.loads(line)
                created = t.get('created', t.get('ts', ''))[:10]
                if week_start <= created <= today or t.get('weekly_triggered') == today:
                    week_tickets["total"] += 1
                    s = t.get('status','')
                    if s in ('CLOSED','ARCHIVED','RESOLVED','SHIPPED'):
                        week_tickets["resolved"] += 1
                    else:
                        week_tickets["pending"] += 1
                        if t.get('weekly_triggered') == today:
                            week_tickets["triggered"] += 1
                        pending_list.append(f"{t.get('id','?')}: {t.get('title','')[:60]}")
            except: pass

# ── Verdict ──────────────────────────────────────────────────────────────────
if len(shipped) >= 2 and week_tickets["resolved"] > week_tickets["pending"]:
    verdict = "expanding"
elif shipped or week_tickets["resolved"] > 0:
    verdict = "stable"
else:
    verdict = "needs attention"

# Also count all-time pending
all_pending = 0
if os.path.exists(tickets_path):
    with open(tickets_path) as tf:
        for line in tf:
            line = line.strip()
            if not line: continue
            try:
                t = json.loads(line)
                if t.get('status') in ('OPEN','ACTIVE','BLOCKED'):
                    all_pending += 1
            except: pass

now = get_mt()
entry_id = f"{agent}-weekly-{week}"

entry = {
    "id": entry_id,
    "type": "agent-weekly",
    "title": f"{name} — Week {week} Summary",
    "author": name,
    "authorIcon": icon,
    "authorColor": color,
    "timestamp": now,
    "date": today,
    "week": week,
    "weekStart": week_start,
    "sections": {
        "weaknesses": weaknesses or ["No weaknesses documented — update GROWTH.md"],
        "improvements_shipped": shipped or ["No improvements shipped this week."],
        "tickets": {
            "week_total":    week_tickets["total"],
            "week_resolved": week_tickets["resolved"],
            "week_pending":  week_tickets["pending"],
            "triggered_for_completion": week_tickets["triggered"],
            "all_pending": all_pending,
            "pending_list": pending_list[:5]
        },
        "verdict": verdict
    }
}

def upsert(path):
    if not os.path.exists(path):
        return False
    with open(path) as f:
        d = json.load(f)
    reports = d.setdefault("reports", [])
    reports[:] = [r for r in reports if r.get("id") != entry_id]
    reports.insert(0, entry)
    d["lastUpdated"] = now
    with open(path, "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
    return True

ok1 = upsert(feed_git)
ok2 = upsert(feed_live)
print(f"[weekly:{agent}] published {entry_id} verdict={verdict} shipped={len(shipped)} pending_triggered={week_tickets['triggered']}")
if not (ok1 or ok2): sys.exit(1)
PYWEEK
}

for agent in "${AGENTS[@]}"; do
  log "Generating weekly report: $agent"
  generate_weekly "$agent" || log "WARNING: $agent weekly report failed"
done

# ── Step 3: Archive week's reports to research ───────────────────────────────
log "Archiving week's reports to research section..."
bash "$ROOT/bin/archive-to-research.sh" "$WEEK" || log "WARNING: archive step failed"

# ── Step 4: Commit and push ──────────────────────────────────────────────────
log "Committing weekly reports..."
cd "$ROOT"
git add agents/sam/website/data/feed.json website/data/feed.json \
        agents/sam/website/data/research-archive.json website/data/research-archive.json \
        kai/tickets/tickets.jsonl 2>/dev/null || true
git commit -m "weekly: $WEEK reports + research archive + pending tickets triggered

Agents: nel ra sam aether kai
All pending tickets set to ACTIVE with 1hr SLA.
Week's daily/weekly reports archived to research section." 2>/dev/null || true
git push origin main 2>&1 | tail -3 || log "WARNING: push failed"

log "=== Weekly report complete for $WEEK ==="
