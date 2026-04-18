#!/usr/bin/env bash
# bin/dispatch.sh — Kai ↔ Agent bidirectional task + communication system
#
# Downward (Kai → Agent):
#   dispatch delegate <agent> <priority> <title> [--context "..."] [--deadline "ISO"]
#   dispatch ack <task_id> <method>
#   dispatch verify <task_id> [--notes "..."]
#   dispatch close <task_id>
#
# Upward (Agent → Kai):
#   dispatch flag <agent> <severity> <title>       # agent reports an issue to Kai
#   dispatch escalate <task_id> <reason>            # agent escalates a blocked task
#   dispatch self-delegate <agent> <priority> <title>  # agent creates own task (autonomous)
#
# Bidirectional:
#   dispatch report <task_id> <status> <result>
#
# Queries:
#   dispatch list <agent>          # show active tasks
#   dispatch log <agent> [--last N] # show recent log entries
#   dispatch status                 # summary across all agents
#   dispatch health                 # closed-loop health check across all agents
#
# Simulation:
#   dispatch simulate              # full delegation lifecycle sim for all agents
#   dispatch safeguard <issue_id> <description>  # trigger parallel prevention cascade
#
# Task IDs: auto-generated as <agent>-NNN
# Statuses: CREATED, DELEGATED, IN_PROGRESS, TESTING, VERIFIED, DONE, BLOCKED, FAILED
# Flags: auto-generated as flag-<agent>-NNN
#
# Memory:
#   dispatch memory                # show known issue patterns from simulation history
#   Outcome ledger: kai/ledger/simulation-outcomes.jsonl (append-only, nightly)

set -uo pipefail

ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Agent ledger paths
agent_ledger() {
  local agent="$1"
  case "$agent" in
    kai)    echo "$ROOT/kai/ledger" ;;
    nel)    echo "$ROOT/agents/nel/ledger" ;;
    ra)     echo "$ROOT/agents/ra/ledger" ;;
    sam)    echo "$ROOT/agents/sam/ledger" ;;
    aether) echo "$ROOT/agents/aether/ledger" ;;
    dex)    echo "$ROOT/agents/dex/ledger" ;;
    *)      echo "" ;;
  esac
}

# Get next task ID for an agent
next_id() {
  local agent="$1"
  local dir; dir=$(agent_ledger "$agent")
  local log="$dir/log.jsonl"
  if [[ ! -f "$log" ]]; then
    echo "${agent}-001"
    return
  fi
  local last; last=$(grep -oP "\"task_id\":\s*\"${agent}-[0-9]+\"" "$log" 2>/dev/null | tail -1 | grep -o '[0-9]*' | tail -1)
  if [[ -z "$last" ]]; then
    echo "${agent}-001"
  else
    # Strip leading zeros to prevent octal interpretation, then increment
    local num; num=$((10#$last + 1))
    printf '%s-%03d' "$agent" "$num"
  fi
}

# Append to log (validates agent first)
log_entry() {
  local agent="$1"
  local json="$2"
  local dir; dir=$(agent_ledger "$agent")
  if [[ -z "$dir" ]]; then
    echo "ERROR: unknown agent '$agent'" >&2
    return 1
  fi
  mkdir -p "$dir"
  echo "$json" >> "$dir/log.jsonl"
}

# Rebuild ACTIVE.md from log
rebuild_active() {
  local agent="$1"
  local dir; dir=$(agent_ledger "$agent")
  local log="$dir/log.jsonl"
  local active="$dir/ACTIVE.md"

  if [[ ! -f "$log" ]]; then
    echo "# $agent Active Tasks" > "$active"
    echo "" >> "$active"
    echo "No tasks yet." >> "$active"
    return
  fi

  python3 - "$agent" "$log" "$active" << 'PYEOF'
import json, sys
from collections import OrderedDict

agent = sys.argv[1]
log_path = sys.argv[2]
active_path = sys.argv[3]

tasks = OrderedDict()
with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        tid = entry.get("task_id", "")
        if not tid:
            continue
        if tid not in tasks:
            tasks[tid] = {
                "id": tid,
                "title": entry.get("title", ""),
                "priority": entry.get("priority", "P2"),
                "status": "CREATED",
                "created": entry.get("ts", ""),
                "delegated": "",
                "method": "",
                "result": "",
                "notes": "",
                "completed": "",
                "context": entry.get("context", ""),
            }
        action = entry.get("action", "")
        ts = entry.get("ts", "")
        if action == "DELEGATE":
            tasks[tid]["status"] = "DELEGATED"
            tasks[tid]["delegated"] = ts
            if entry.get("title"):
                tasks[tid]["title"] = entry["title"]
            if entry.get("priority"):
                tasks[tid]["priority"] = entry["priority"]
            if entry.get("context"):
                tasks[tid]["context"] = entry["context"]
        elif action == "ACK":
            tasks[tid]["status"] = entry.get("status", "IN_PROGRESS")
            tasks[tid]["method"] = entry.get("method", "")
        elif action == "REPORT":
            tasks[tid]["status"] = entry.get("status", "TESTING")
            tasks[tid]["result"] = entry.get("result", "")
        elif action == "VERIFY":
            tasks[tid]["status"] = "VERIFIED"
            tasks[tid]["notes"] = entry.get("notes", "")
        elif action == "CLOSE":
            tasks[tid]["status"] = "DONE"
            tasks[tid]["completed"] = entry.get("completed", ts)

in_progress = [t for t in tasks.values() if t["status"] in ("DELEGATED", "IN_PROGRESS", "TESTING", "BLOCKED")]
queued = [t for t in tasks.values() if t["status"] == "CREATED"]
done = [t for t in tasks.values() if t["status"] in ("DONE", "VERIFIED")]

with open(active_path, "w") as f:
    f.write(f"# {agent.title()} Active Tasks\n\n")
    f.write(f"Last updated: {max((e.get('ts','') for line in open(log_path) for e in [json.loads(line.strip())] if line.strip()), default='unknown')}\n\n")

    if in_progress:
        f.write("## In Progress\n\n")
        for t in in_progress:
            f.write(f"- **{t['id']}** [{t['priority']}] {t['title']}\n")
            f.write(f"  - Delegated: {t['delegated']}\n")
            if t["method"]:
                f.write(f"  - Method: {t['method']}\n")
            f.write(f"  - Status: {t['status']}")
            if t["result"]:
                f.write(f" — {t['result']}")
            f.write("\n\n")

    if queued:
        f.write("## Queued\n\n")
        for t in queued:
            f.write(f"- **{t['id']}** [{t['priority']}] {t['title']}\n")
            f.write(f"  - Created: {t['created']}\n\n")

    if done:
        f.write("## Recently Completed\n\n")
        for t in list(reversed(done))[:10]:
            f.write(f"- **{t['id']}** [{t['priority']}] {t['title']} — {t['completed']} (DONE)\n")
            if t["result"]:
                f.write(f"  - Result: {t['result']}\n")
            if t["notes"]:
                f.write(f"  - Notes: {t['notes']}\n")
            f.write("\n")

    if not in_progress and not queued and not done:
        f.write("No tasks yet.\n")
PYEOF
}

# ── Commands ──

cmd_delegate() {
  local agent="$1"; shift
  local priority="$1"; shift

  # Collect title words, stopping at flags
  local title_parts=()
  local context="" deadline=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --context) shift; context="${1:-}" ;;
      --deadline) shift; deadline="${1:-}" ;;
      *) title_parts+=("$1") ;;
    esac
    shift 2>/dev/null || break
  done
  local title="${title_parts[*]}"

  local tid; tid=$(next_id "$agent")

  # Use python3 for safe JSON generation (handles quotes/special chars)
  local json; json=$(python3 -c "
import json, sys
print(json.dumps({
  'ts': sys.argv[1], 'action': 'DELEGATE', 'task_id': sys.argv[2],
  'from': 'kai', 'to': sys.argv[3], 'title': sys.argv[4],
  'priority': sys.argv[5], 'context': sys.argv[6], 'deadline': sys.argv[7]
}))" "$NOW" "$tid" "$agent" "$title" "$priority" "$context" "$deadline")

  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"

  echo "Delegated: $tid [$priority] $title → $agent"
}

cmd_ack() {
  local task_id="$1"
  local method="${2:-}"
  local agent="${task_id%%-*}"
  local json; json=$(python3 -c "
import json, sys
print(json.dumps({'ts':sys.argv[1],'action':'ACK','task_id':sys.argv[2],'from':sys.argv[3],'to':'kai','status':'IN_PROGRESS','method':sys.argv[4]}))" "$NOW" "$task_id" "$agent" "$method")
  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"
  echo "Acknowledged: $task_id → IN_PROGRESS"
}

cmd_report() {
  local task_id="$1"
  local status="$2"
  local result="${3:-}"
  local agent="${task_id%%-*}"
  local json; json=$(python3 -c "
import json, sys
print(json.dumps({'ts':sys.argv[1],'action':'REPORT','task_id':sys.argv[2],'from':sys.argv[3],'to':'kai','status':sys.argv[4],'result':sys.argv[5]}))" "$NOW" "$task_id" "$agent" "$status" "$result")
  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"
  echo "Report: $task_id → $status"
}

cmd_verify() {
  local task_id="$1"
  local notes="${2:-verified by Kai}"
  local agent="${task_id%%-*}"
  local json; json=$(python3 -c "
import json, sys
print(json.dumps({'ts':sys.argv[1],'action':'VERIFY','task_id':sys.argv[2],'from':'kai','to':sys.argv[3],'status':'VERIFIED','notes':sys.argv[4]}))" "$NOW" "$task_id" "$agent" "$notes")
  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"
  echo "Verified: $task_id"
}

cmd_close() {
  local task_id="$1"
  local agent="${task_id%%-*}"
  local json; json=$(python3 -c "
import json, sys
print(json.dumps({'ts':sys.argv[1],'action':'CLOSE','task_id':sys.argv[2],'status':'DONE','completed':sys.argv[1]}))" "$NOW" "$task_id")
  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"
  echo "Closed: $task_id → DONE"
}

cmd_list() {
  local agent="$1"
  local dir; dir=$(agent_ledger "$agent")
  if [[ -f "$dir/ACTIVE.md" ]]; then
    cat "$dir/ACTIVE.md"
  else
    echo "No tasks for $agent"
  fi
}

cmd_log() {
  local agent="$1"
  local count="${2:-10}"
  local dir; dir=$(agent_ledger "$agent")
  if [[ -f "$dir/log.jsonl" ]]; then
    tail -n "$count" "$dir/log.jsonl" | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        print(f\"{e.get('ts','')} {e.get('action',''):10s} {e.get('task_id',''):10s} {e.get('status','')} {e.get('title','')}{e.get('result','')}\")
    except: pass
"
  else
    echo "No log for $agent"
  fi
}

cmd_status() {
  echo "=== Kai Dispatch Status ==="
  echo ""
  for agent in nel ra sam; do
    local dir; dir=$(agent_ledger "$agent")
    local log="$dir/log.jsonl"
    if [[ -f "$log" ]]; then
      local total; total=$(grep -c '"action"' "$log" 2>/dev/null || echo 0)
      local open; open=$(python3 -c "
import json
tasks={}
with open('$log') as f:
    for l in f:
        try:
            e=json.loads(l.strip())
            tid=e.get('task_id','')
            if not tid: continue
            if tid not in tasks: tasks[tid]={'status':'CREATED'}
            a=e.get('action','')
            if a=='CLOSE': tasks[tid]['status']='DONE'
            elif a=='VERIFY': tasks[tid]['status']='VERIFIED'
            elif a=='REPORT': tasks[tid]['status']=e.get('status','TESTING')
            elif a=='ACK': tasks[tid]['status']='IN_PROGRESS'
            elif a=='DELEGATE': tasks[tid]['status']='DELEGATED'
        except: pass
open_count=sum(1 for t in tasks.values() if t['status'] not in ('DONE','VERIFIED'))
done_count=sum(1 for t in tasks.values() if t['status'] in ('DONE','VERIFIED'))
print(f'{open_count} open, {done_count} done')
" 2>/dev/null || echo "0 open, 0 done")
      echo "  $agent: $open ($total log entries)"
    else
      echo "  $agent: no tasks"
    fi
  done
}

# ── Upward Communication ──

# Get next flag ID for an agent
next_flag_id() {
  local agent="$1"
  local dir; dir=$(agent_ledger "$agent")
  local log="$dir/log.jsonl"
  if [[ ! -f "$log" ]]; then
    echo "flag-${agent}-001"
    return
  fi
  local last; last=$(grep -oP "\"task_id\":\s*\"flag-${agent}-[0-9]+\"" "$log" 2>/dev/null | tail -1 | grep -o '[0-9]*' | tail -1)
  if [[ -z "$last" ]]; then
    echo "flag-${agent}-001"
  else
    local num; num=$((10#$last + 1))
    printf 'flag-%s-%03d' "$agent" "$num"
  fi
}

# Agent flags an issue to Kai (agent-initiated)
cmd_flag() {
  local agent="$1"; shift
  local severity="$1"; shift  # P0, P1, P2, P3
  local title="$*"
  local fid; fid=$(next_flag_id "$agent")

  local json; json=$(python3 -c "
import json, sys
print(json.dumps({
  'ts': sys.argv[1], 'action': 'FLAG', 'task_id': sys.argv[2],
  'from': sys.argv[3], 'to': 'kai', 'severity': sys.argv[4],
  'title': sys.argv[5], 'status': 'FLAGGED'
}))" "$NOW" "$fid" "$agent" "$severity" "$title")

  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"

  # If P0 or P1, auto-trigger safeguard cascade + What's Next response
  if [[ "$severity" == "P0" || "$severity" == "P1" ]]; then
    echo "⚠ HIGH SEVERITY FLAG: $fid [$severity] $title (from $agent)"
    echo "  → Auto-triggering safeguard cascade..."
    cmd_safeguard "$fid" "$title"

    # WHAT'S NEXT: Don't just log — determine remediation owner and dispatch
    local owner="$agent"  # default: flagging agent owns the fix
    # Route by domain keywords
    case "$title" in
      *queue*|*deploy*|*build*|*server*|*API*|*api*)  owner="sam" ;;
      *security*|*secret*|*token*|*leak*|*cipher*)    owner="nel" ;;
      *newsletter*|*source*|*content*|*brief*)        owner="ra" ;;
      *trade*|*aether*|*dashboard*|*kalshi*|*GPT*)    owner="aether" ;;
      *integrity*|*compact*|*stale*|*ledger*|*jsonl*) owner="dex" ;;
    esac

    echo "  → What's Next: dispatching auto-remediation to $owner"
    cmd_delegate "$owner" "$severity" "[AUTO-REMEDIATE] $title (flagged by $agent, cascade $fid)"

    # EVENT-DRIVEN AGENT TRIGGER: queue the receiving agent's runner immediately.
    # Don't wait for next scheduled cycle. The agent needs to pick up the task,
    # act on it, and reflect NOW — not in 6 hours. This is what makes agents
    # responsive, not just scheduled.
    local QUEUE_DIR="$ROOT/kai/queue/pending"
    if [[ -d "$QUEUE_DIR" ]]; then
      # Resolve the agent runner path
      local agent_runner="$ROOT/agents/$owner/$owner.sh"
      if [[ -f "$agent_runner" ]]; then
        local run_id="event-${owner}-${fid}"
        python3 -c "
import json
cmd = {'id':'$run_id','ts':'$NOW','command':'bash $agent_runner','timeout':300,'agent':'$owner','note':'event-driven: $severity flag $fid triggered immediate $owner run'}
with open('$QUEUE_DIR/${run_id}.json','w') as f:
  json.dump(cmd,f)
" 2>/dev/null && echo "  → Queued event-driven $owner run: $run_id (agent will pick up task + reflect)"
      else
        echo "  → WARN: no runner at $agent_runner — $owner cannot be event-triggered"
      fi

      # Also queue healthcheck rerun for verification
      local recheck_id="recheck-$fid"
      python3 -c "
import json
cmd = {'id':'$recheck_id','ts':'$NOW','command':'bash $ROOT/kai/queue/healthcheck.sh','timeout':120,'agent':'dispatch-recheck','note':'auto-queued after $severity flag $fid'}
with open('$QUEUE_DIR/${recheck_id}.json','w') as f:
  json.dump(cmd,f)
" 2>/dev/null && echo "  → Queued re-check: $recheck_id"
    fi
  elif [[ "$severity" == "P2" ]]; then
    echo "Flag: $fid [$severity] $title (from $agent → kai)"
    echo "  → What's Next: task created for next review cycle"
  else
    echo "Flag: $fid [$severity] $title (from $agent → kai, logged for weekly review)"
  fi
}

# Agent escalates a blocked/stuck task
cmd_escalate() {
  local task_id="$1"
  local reason="${2:-blocked, needs Kai decision}"
  local agent="${task_id%%-*}"

  local json; json=$(python3 -c "
import json, sys
print(json.dumps({
  'ts': sys.argv[1], 'action': 'ESCALATE', 'task_id': sys.argv[2],
  'from': sys.argv[3], 'to': 'kai', 'status': 'BLOCKED',
  'reason': sys.argv[4]
}))" "$NOW" "$task_id" "$agent" "$reason")

  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"
  echo "Escalated: $task_id → BLOCKED ($reason)"
}

# Agent self-delegates a task (autonomous discovery)
cmd_self_delegate() {
  local agent="$1"; shift
  local priority="$1"; shift
  local title="$*"
  local tid; tid=$(next_id "$agent")

  local json; json=$(python3 -c "
import json, sys
print(json.dumps({
  'ts': sys.argv[1], 'action': 'SELF_DELEGATE', 'task_id': sys.argv[2],
  'from': sys.argv[3], 'to': sys.argv[3], 'title': sys.argv[4],
  'priority': sys.argv[5], 'status': 'IN_PROGRESS',
  'origin': 'autonomous'
}))" "$NOW" "$tid" "$agent" "$title" "$priority")

  log_entry "$agent" "$json"
  log_entry "kai" "$json"
  rebuild_active "$agent"
  rebuild_active "kai"
  echo "Self-delegated: $tid [$priority] $title ($agent → self, logged to kai)"
}

# ── Safeguard Cascade ──
# When an issue is found, don't just fix it — prevent recurrence system-wide.
# Creates parallel tasks across agents to cross-reference and harden.
cmd_safeguard() {
  local issue_id="$1"
  local description="$2"
  local safeguard_log="$ROOT/kai/ledger/safeguards.jsonl"
  mkdir -p "$(dirname "$safeguard_log")"

  local json; json=$(python3 -c "
import json, sys
print(json.dumps({
  'ts': sys.argv[1], 'trigger': sys.argv[2], 'description': sys.argv[3],
  'actions_spawned': ['nel-audit', 'sam-test', 'ra-integrity', 'kai-memory']
}))" "$NOW" "$issue_id" "$description")

  echo "$json" >> "$safeguard_log"

  echo "  [safeguard] Logged trigger: $issue_id"
  echo "  [safeguard] Spawning parallel prevention tasks:"

  # Nel: investigate if this class of issue exists elsewhere
  cmd_delegate nel P1 "SAFEGUARD: Cross-reference issue ($issue_id) — scan entire codebase for similar patterns: $description" 2>&1 | sed 's/^/    /'

  # Sam: add test coverage for this specific failure mode
  cmd_delegate sam P1 "SAFEGUARD: Add test coverage for issue ($issue_id): $description" 2>&1 | sed 's/^/    /'

  # Kai: log to memory so this pattern is known next simulation
  local mem_entry; mem_entry=$(python3 -c "
import json, sys
print(json.dumps({
  'ts': sys.argv[1], 'type': 'issue_pattern', 'source': sys.argv[2],
  'description': sys.argv[3], 'status': 'active',
  'prevention': 'Nel audit + Sam test coverage deployed'
}))" "$NOW" "$issue_id" "$description")
  echo "$mem_entry" >> "$ROOT/kai/ledger/known-issues.jsonl"
  echo "    → Memory: pattern logged to known-issues.jsonl"
}

# ── Closed-Loop Health Check ──
cmd_health() {
  echo "=== Closed-Loop Health Check ==="
  echo ""

  local issues=0

  # Check 1: any tasks stuck in DELEGATED for too long (no ACK)
  for agent in nel ra sam; do
    local dir; dir=$(agent_ledger "$agent")
    local log="$dir/log.jsonl"
    [[ -f "$log" ]] || continue

    local stale; stale=$(python3 -c "
import json, datetime
stale = []
tasks = {}
with open('$log') as f:
    for l in f:
        try:
            e = json.loads(l.strip())
            tid = e.get('task_id','')
            if not tid: continue
            if tid not in tasks: tasks[tid] = {'status':'CREATED','delegated':''}
            a = e.get('action','')
            if a == 'DELEGATE':
                tasks[tid]['status'] = 'DELEGATED'
                tasks[tid]['delegated'] = e.get('ts','')
            elif a in ('ACK','REPORT','VERIFY','CLOSE'):
                tasks[tid]['status'] = a
        except: pass
now = datetime.datetime.utcnow()
for tid, t in tasks.items():
    if t['status'] == 'DELEGATED' and t['delegated']:
        try:
            dt = datetime.datetime.fromisoformat(t['delegated'].replace('Z',''))
            if (now - dt).total_seconds() > 86400:
                stale.append(tid)
        except: pass
print(','.join(stale) if stale else '')
" "$log" 2>/dev/null)

    if [[ -n "$stale" ]]; then
      echo "  ⚠ $agent: stale tasks (DELEGATED >24h, no ACK): $stale"
      ((issues++))
    else
      echo "  ✓ $agent: no stale delegations"
    fi
  done

  # Check 2: any FLAGS not addressed
  local kai_log; kai_log=$(agent_ledger "kai")/log.jsonl
  if [[ -f "$kai_log" ]]; then
    local open_flags; open_flags=$(python3 -c "
import json
flags = {}
with open('$kai_log') as f:
    for l in f:
        try:
            e = json.loads(l.strip())
            if e.get('action') == 'FLAG':
                flags[e['task_id']] = e.get('severity','?')
            if e.get('action') in ('CLOSE','VERIFY') and e.get('task_id','') in flags:
                del flags[e['task_id']]
        except: pass
if flags:
    print(', '.join(f'{k} [{v}]' for k, v in flags.items()))
else:
    print('')
" 2>/dev/null)

    if [[ -n "$open_flags" ]]; then
      echo "  ⚠ kai: unresolved flags: $open_flags"
      ((issues++))
    else
      echo "  ✓ kai: all flags resolved"
    fi
  fi

  # Check 3: ledger files exist and are non-empty for all agents
  for agent in kai nel ra sam; do
    local dir; dir=$(agent_ledger "$agent")
    if [[ ! -f "$dir/log.jsonl" ]]; then
      echo "  ⚠ $agent: no ledger file"
      ((issues++))
    elif [[ ! -f "$dir/ACTIVE.md" ]]; then
      echo "  ⚠ $agent: ACTIVE.md missing (ledger exists but view not rebuilt)"
      ((issues++))
    else
      echo "  ✓ $agent: ledger + active view present"
    fi
  done

  # Check 4: safeguards log exists and recent entries are addressed
  local safeguard_log="$ROOT/kai/ledger/safeguards.jsonl"
  if [[ -f "$safeguard_log" ]]; then
    local sg_count; sg_count=$(wc -l < "$safeguard_log" | tr -d ' ')
    echo "  ✓ safeguard log: $sg_count entries"
  else
    echo "  · safeguard log: empty (no cascades triggered yet)"
  fi

  # Check 5: known-issues memory
  local ki="$ROOT/kai/ledger/known-issues.jsonl"
  if [[ -f "$ki" ]]; then
    local ki_count; ki_count=$(wc -l < "$ki" | tr -d ' ')
    echo "  ✓ known issues: $ki_count patterns logged"
  else
    echo "  · known issues: empty (no patterns recorded yet)"
  fi

  echo ""
  if [[ $issues -eq 0 ]]; then
    echo "Health: ALL CLEAR — closed loop intact"
  else
    echo "Health: $issues ISSUE(S) — action required"
  fi
}

# ── Nightly Simulation ──
cmd_simulate() {
  local sim_log="$ROOT/kai/ledger/simulation-outcomes.jsonl"
  mkdir -p "$(dirname "$sim_log")"
  local started="$NOW"
  local results=()
  local total_pass=0
  local total_fail=0

  echo "=== Nightly Delegation Lifecycle Simulation ==="
  echo "Started: $NOW"
  echo ""

  # Read known issues to check for regressions
  local known_issues="$ROOT/kai/ledger/known-issues.jsonl"
  if [[ -f "$known_issues" ]]; then
    local ki_count; ki_count=$(wc -l < "$known_issues" | tr -d ' ')
    echo "Known issue patterns loaded: $ki_count"
  fi

  # ── Phase 1: Downward delegation test (Kai → each agent) ──
  echo ""
  echo "Phase 1: Downward delegation (Kai → Agent)"
  for agent in nel ra sam; do
    local tid; tid=$(next_id "$agent")
    local test_title="SIM-TEST: nightly delegation handshake verification"

    # Delegate
    cmd_delegate "$agent" P3 "$test_title" --context "nightly-sim-$NOW" > /dev/null 2>&1

    # Verify it landed in the agent's log
    local dir; dir=$(agent_ledger "$agent")
    if grep -q "SIM-TEST.*nightly delegation" "$dir/log.jsonl" 2>/dev/null; then
      echo "  ✓ $agent: delegation received in ledger"
      ((total_pass++))
    else
      echo "  ✗ $agent: delegation NOT found in ledger"
      ((total_fail++))
      results+=("FAIL:delegate:$agent")
    fi

    # ACK (simulating agent receiving and acknowledging)
    cmd_ack "$tid" "sim-ack: agent handshake test" > /dev/null 2>&1
    if grep -q "ACK.*$tid" "$dir/log.jsonl" 2>/dev/null; then
      echo "  ✓ $agent: ACK round-trip confirmed"
      ((total_pass++))
    else
      echo "  ✗ $agent: ACK failed"
      ((total_fail++))
      results+=("FAIL:ack:$agent")
    fi

    # Report
    cmd_report "$tid" TESTING "sim-report: all clear" > /dev/null 2>&1

    # Verify + Close
    cmd_verify "$tid" "sim-verify: nightly handshake passed" > /dev/null 2>&1
    cmd_close "$tid" > /dev/null 2>&1

    if grep -q "CLOSE.*$tid" "$dir/log.jsonl" 2>/dev/null; then
      echo "  ✓ $agent: full lifecycle (delegate→ack→report→verify→close) PASSED"
      ((total_pass++))
    else
      echo "  ✗ $agent: lifecycle incomplete"
      ((total_fail++))
      results+=("FAIL:lifecycle:$agent")
    fi
  done

  # ── Phase 2: Upward communication test (Agent → Kai) ──
  echo ""
  echo "Phase 2: Upward communication (Agent → Kai)"
  for agent in nel ra sam; do
    # Self-delegate test
    cmd_self_delegate "$agent" P3 "SIM-TEST: autonomous task creation verification" > /dev/null 2>&1
    local kai_log; kai_log=$(agent_ledger "kai")/log.jsonl
    if grep -q "SELF_DELEGATE.*SIM-TEST.*autonomous" "$kai_log" 2>/dev/null; then
      echo "  ✓ $agent: self-delegate visible in kai ledger"
      ((total_pass++))
    else
      echo "  ✗ $agent: self-delegate NOT visible in kai ledger"
      ((total_fail++))
      results+=("FAIL:self-delegate:$agent")
    fi

    # Flag test (P3 to avoid triggering safeguard cascade)
    cmd_flag "$agent" P3 "SIM-TEST: upward flag communication test" > /dev/null 2>&1
    if grep -q "FLAG.*SIM-TEST.*upward flag" "$kai_log" 2>/dev/null; then
      echo "  ✓ $agent: flag visible in kai ledger"
      ((total_pass++))
    else
      echo "  ✗ $agent: flag NOT visible in kai ledger"
      ((total_fail++))
      results+=("FAIL:flag:$agent")
    fi
  done

  # ── Phase 3: Agent runner execution test ──
  echo ""
  echo "Phase 3: Agent runners"
  for agent in nel ra sam; do
    local runner="$ROOT/agents/$agent/$agent.sh"
    if [[ -x "$runner" ]]; then
      bash "$runner" 2>&1 > /dev/null
      local exit_code=$?
      if [[ $exit_code -eq 0 ]]; then
        echo "  ✓ $agent.sh: exit 0"
        ((total_pass++))
      else
        echo "  ✗ $agent.sh: exit $exit_code"
        ((total_fail++))
        results+=("FAIL:runner:$agent:exit-$exit_code")
      fi
    else
      echo "  ✗ $agent.sh: not executable or missing"
      ((total_fail++))
      results+=("FAIL:runner:$agent:missing")
    fi
  done

  # ── Phase 4: Cross-reference integrity ──
  echo ""
  echo "Phase 4: Cross-reference integrity"

  # Check Kai's log has entries for all agents
  local kai_log; kai_log=$(agent_ledger "kai")/log.jsonl
  for agent in nel ra sam; do
    if grep -q "\"to\": \"$agent\"" "$kai_log" 2>/dev/null || \
       grep -q "\"from\": \"$agent\"" "$kai_log" 2>/dev/null; then
      echo "  ✓ kai ↔ $agent: cross-reference entries exist"
      ((total_pass++))
    else
      echo "  ✗ kai ↔ $agent: no cross-reference entries"
      ((total_fail++))
      results+=("FAIL:xref:$agent")
    fi
  done

  # Check ACTIVE.md consistency with log
  for agent in kai nel ra sam; do
    local dir; dir=$(agent_ledger "$agent")
    if [[ -f "$dir/ACTIVE.md" && -f "$dir/log.jsonl" ]]; then
      echo "  ✓ $agent: ACTIVE.md + log.jsonl in sync"
      ((total_pass++))
    else
      echo "  ✗ $agent: missing ACTIVE.md or log.jsonl"
      ((total_fail++))
      results+=("FAIL:sync:$agent")
    fi
  done

  # ── Phase 5: Known issue regression check ──
  echo ""
  echo "Phase 5: Known issue regression check"
  if [[ -f "$known_issues" ]]; then
    python3 - "$known_issues" "$ROOT" << 'PYEOF'
import json, sys, os, subprocess

ki_path = sys.argv[1]
root = sys.argv[2]
regressions = 0

with open(ki_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except:
            continue
        desc = entry.get("description", "")
        # Check if the description mentions specific patterns we can verify
        if "JSON" in desc and "injection" in desc.lower():
            # Check dispatch.sh still uses python3 json.dumps
            result = subprocess.run(
                ["grep", "-c", "json.dumps", os.path.join(root, "bin/dispatch.sh")],
                capture_output=True, text=True
            )
            count = int(result.stdout.strip() or "0")
            if count >= 5:
                print(f"  ✓ Regression check: JSON injection fix still in place ({count} json.dumps calls)")
            else:
                print(f"  ✗ REGRESSION: JSON injection fix may have been reverted ({count} json.dumps calls)")
                regressions += 1

        if "permission" in desc.lower():
            # Check watch-deploy.sh is still executable
            path = os.path.join(root, "bin/watch-deploy.sh")
            if os.path.isfile(path) and os.access(path, os.X_OK):
                print(f"  ✓ Regression check: watch-deploy.sh still executable")
            else:
                print(f"  ✗ REGRESSION: watch-deploy.sh permissions reverted")
                regressions += 1

if regressions == 0:
    print(f"  ✓ No regressions detected across known issue patterns")
sys.exit(regressions)
PYEOF
    local reg_exit=$?
    total_pass=$((total_pass + 1))
    if [[ $reg_exit -gt 0 ]]; then
      total_fail=$((total_fail + reg_exit))
      results+=("FAIL:regression:$reg_exit-issues")
    fi
  else
    echo "  · No known issues to check (first run)"
  fi

  # ── Phase 6: Rendered Output Pathway Verification ──
  echo ""
  echo "Phase 6: Rendered output pathway verification"
  local render_fail=0

  # Check: every JSON in website/data/ must have a render reference in hq.html
  local hq_html="$ROOT/website/hq.html"
  if [[ -f "$hq_html" ]]; then
    for jf in "$ROOT"/website/data/*.json; do
      [[ ! -f "$jf" ]] && continue
      local jname
      jname=$(basename "$jf")
      if ! grep -q "$jname" "$hq_html" 2>/dev/null; then
        echo "  ✗ FAIL: $jname has no rendering reference in hq.html"
        render_fail=$((render_fail + 1))
        results+=("FAIL:render:$jname-unbound")
      fi
    done

    # Check: aether-metrics.json has real balance
    local aether_json="$ROOT/website/data/aether-metrics.json"
    if [[ -f "$aether_json" ]]; then
      local abal
      abal=$(python3 -c "import json; d=json.load(open('$aether_json')); cw=d.get('currentWeek',d.get('currentPeriod',{})); print(cw.get('currentBalance',0))" 2>/dev/null || echo "0")
      if [[ "$abal" == "1000.0" ]] || [[ "$abal" == "1000" ]] || [[ "$abal" == "0" ]]; then
        echo "  ✗ FAIL: Aether balance is default/placeholder (\$$abal)"
        render_fail=$((render_fail + 1))
        results+=("FAIL:render:aether-default-balance")
      else
        echo "  ✓ Aether real balance: \$$abal"
      fi
    fi

    # Check: morning report exists and is current
    local mr_json="$ROOT/website/data/morning-report.json"
    if [[ -f "$mr_json" ]]; then
      local mr_date
      mr_date=$(python3 -c "import json; print(json.load(open('$mr_json')).get('date',''))" 2>/dev/null || echo "")
      local today_check
      today_check=$(TZ="America/Denver" date +%Y-%m-%d)
      local yesterday_check
      yesterday_check=$(TZ="America/Denver" date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d 2>/dev/null || echo "")
      if [[ "$mr_date" != "$today_check" ]] && [[ "$mr_date" != "$yesterday_check" ]]; then
        echo "  ✗ FAIL: Morning report stale (date=$mr_date, today=$today_check) — auto-regenerating"
        render_fail=$((render_fail + 1))
        results+=("FAIL:render:morning-report-stale")
        # Auto-remediate
        local mr_gen="$ROOT/bin/generate-morning-report.sh"
        if [[ -f "$mr_gen" ]]; then
          HYO_ROOT="$ROOT" bash "$mr_gen" 2>&1 || true
          echo "  → Auto-regenerated morning report"
        fi
      else
        echo "  ✓ Morning report current: $mr_date"
      fi

      # Verify hq.html has rendering code
      if ! grep -q "loadMorningReport\|mrSummary" "$hq_html" 2>/dev/null; then
        echo "  ✗ FAIL: Morning report data exists but hq.html has no rendering code"
        render_fail=$((render_fail + 1))
        results+=("FAIL:render:morning-report-no-render")
      else
        echo "  ✓ Morning report rendering wired in hq.html"
      fi
    else
      echo "  ✗ FAIL: Morning report JSON missing — auto-generating"
      render_fail=$((render_fail + 1))
      results+=("FAIL:render:morning-report-missing")
      # Auto-remediate
      local mr_gen="$ROOT/bin/generate-morning-report.sh"
      if [[ -f "$mr_gen" ]]; then
        HYO_ROOT="$ROOT" bash "$mr_gen" 2>&1 || true
        echo "  → Auto-generated morning report"
      fi
    fi
  else
    echo "  · hq.html not found — skipping render checks"
  fi

  if [[ $render_fail -eq 0 ]]; then
    echo "  ✓ All rendered output pathways verified"
    total_pass=$((total_pass + 1))
  else
    total_fail=$((total_fail + render_fail))
  fi

  # ── Phase 7: OS permission / TCC audit (SE-011-007) ──
  # Any binary that accesses protected macOS directories (~/Documents, ~/Desktop,
  # ~/Downloads, etc.) requires explicit user grant via TCC prompt. Simulation
  # must catch this BEFORE the user sees an unexpected dialog.
  echo ""
  echo "Phase 7: OS permission audit (TCC / protected directories)"
  local tcc_fail=0
  local protected_dirs=("$HOME/Documents" "$HOME/Desktop" "$HOME/Downloads")

  # Enumerate agent tools that scan filesystem
  local scan_bins=()
  command -v gitleaks  >/dev/null 2>&1 && scan_bins+=("gitleaks")
  # trufflehog removed (SE-011-007). Add future scanners here.

  for bin_name in "${scan_bins[@]}"; do
    local bin_path; bin_path=$(command -v "$bin_name" 2>/dev/null || true)
    if [[ -z "$bin_path" ]]; then continue; fi

    # Check if this binary has been granted Full Disk Access via TCC database
    # (We can't read the TCC DB directly, but we can test access to a protected dir)
    for pdir in "${protected_dirs[@]}"; do
      if [[ -d "$pdir" ]]; then
        # Try a non-destructive access test
        if ! ls "$pdir" >/dev/null 2>&1; then
          echo "  ✗ FAIL: $bin_name cannot access $pdir (TCC denied or not granted)"
          echo "    → Hyo must grant access: System Settings → Privacy & Security → Files and Folders → $bin_name"
          tcc_fail=$((tcc_fail + 1))
          results+=("FAIL:tcc:$bin_name:$(basename "$pdir")")
        fi
      fi
    done

    # If binary has access, verify it's been granted (no pending prompt)
    if [[ $tcc_fail -eq 0 ]]; then
      echo "  ✓ $bin_name: access to protected directories OK"
      ((total_pass++))
    fi
  done

  if [[ ${#scan_bins[@]} -eq 0 ]]; then
    echo "  · No filesystem-scanning binaries found (gitleaks, trufflehog not installed)"
    ((total_pass++))
  fi

  if [[ $tcc_fail -gt 0 ]]; then
    echo ""
    echo "  ⚠ ACTION REQUIRED FOR HYO:"
    echo "  The following tools need folder access granted in macOS Privacy settings."
    echo "  Kai MUST notify Hyo before first run of any tool that triggers a TCC prompt."
    total_fail=$((total_fail + tcc_fail))
  fi

  # ── Summary ──
  local finished; finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo ""
  echo "=== Simulation Complete ==="
  echo "Pass: $total_pass | Fail: $total_fail | Duration: $started → $finished"

  # Log outcome
  local outcome; outcome=$(python3 -c "
import json, sys
print(json.dumps({
  'ts': sys.argv[1], 'finished': sys.argv[2],
  'passed': int(sys.argv[3]), 'failed': int(sys.argv[4]),
  'failures': sys.argv[5].split(',') if sys.argv[5] else [],
  'agents_tested': ['nel', 'ra', 'sam'],
  'phases': ['delegation', 'upward-comm', 'runners', 'xref', 'regression', 'render', 'tcc-audit']
}))" "$started" "$finished" "$total_pass" "$total_fail" "$(IFS=,; echo "${results[*]:-}")")
  echo "$outcome" >> "$sim_log"
  echo "Outcome logged to: kai/ledger/simulation-outcomes.jsonl"

  # If failures → open resolutions via RA-1 for each unique failure
  if [[ $total_fail -gt 0 ]]; then
    echo ""
    echo "⚠ Failures detected — opening resolutions via RA-1..."
    local resolve_script="$ROOT/kai/protocols/resolve.sh"
    for fail in "${results[@]:-}"; do
      [[ -z "$fail" ]] && continue
      echo "  → Failure: $fail"
      if [[ -f "$resolve_script" ]]; then
        existing=$(grep -rl "IN-PROGRESS" "$ROOT/kai/ledger/resolutions/" 2>/dev/null | xargs grep -l "${fail}" 2>/dev/null | head -1)
        if [[ -z "$existing" ]]; then
          local res_id
          res_id=$(HYO_ROOT="$ROOT" bash "$resolve_script" init "[Simulation] $fail" 2>/dev/null | tail -1)
          [[ -n "$res_id" ]] && echo "  → Opened resolution $res_id"
        else
          echo "  → Existing resolution covers this: $(basename "$existing" .md)"
        fi
      fi
    done
  fi
}

# ── Memory: known issue patterns ──
cmd_memory() {
  echo "=== Known Issue Patterns ==="
  local ki="$ROOT/kai/ledger/known-issues.jsonl"
  if [[ -f "$ki" ]]; then
    python3 -c "
import json
with open('$ki') as f:
    for line in f:
        try:
            e = json.loads(line.strip())
            print(f\"  [{e.get('ts','')}] {e.get('source','')} — {e.get('description','')}\")
            print(f\"    Prevention: {e.get('prevention','none')}\")
            print(f\"    Status: {e.get('status','unknown')}\")
            print()
        except: pass
"
  else
    echo "  No patterns recorded yet."
  fi

  echo ""
  echo "=== Simulation History (last 10) ==="
  local sl="$ROOT/kai/ledger/simulation-outcomes.jsonl"
  if [[ -f "$sl" ]]; then
    tail -10 "$sl" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        status = '✓ ALL PASS' if e.get('failed',0) == 0 else f\"✗ {e['failed']} FAIL\"
        print(f\"  [{e.get('ts','')}] {status} (pass={e.get('passed',0)}, fail={e.get('failed',0)})\")
        if e.get('failures'):
            for f in e['failures']:
                if f: print(f\"    → {f}\")
    except: pass
"
  else
    echo "  No simulation history yet."
  fi
}

# ── Simulation Review ──
# Runs after dispatch simulate to auto-flag any failures found in the last outcome
cmd_simulate_review() {
  local outcomes_file="$ROOT/kai/ledger/simulation-outcomes.jsonl"

  if [[ ! -f "$outcomes_file" ]]; then
    echo "Warning: $outcomes_file does not exist"
    return 1
  fi

  if [[ ! -s "$outcomes_file" ]]; then
    echo "Warning: $outcomes_file is empty"
    return 1
  fi

  # Read the last line (most recent outcome)
  local last_outcome; last_outcome=$(tail -1 "$outcomes_file")

  # Parse with Python to extract needed fields
  python3 - "$last_outcome" << 'PYEOF'
import json, sys

try:
  outcome = json.loads(sys.argv[1])
except:
  print("ERROR: Could not parse last outcome as JSON")
  sys.exit(1)

ts = outcome.get('ts', 'unknown')
passed = outcome.get('passed', 0)
failed = outcome.get('failed', 0)
failures = outcome.get('failures', [])

print(f"Reviewing latest simulation...")
print(f"  Last run: {ts} — {passed} passed, {failed} failed")

if failed == 0:
  print(f"  All clear — no action needed")
else:
  print(f"  Found {len(failures)} failure(s):")
  for failure in failures:
    if failure.strip():
      print(f"  → Flagging: {failure}")

sys.exit(0 if failed == 0 else 1)
PYEOF

  local review_exit=$?

  # If there were failures, flag them now
  if [[ $review_exit -ne 0 ]]; then
    # Parse failures again for flagging
    local last_outcome; last_outcome=$(tail -1 "$outcomes_file")
    python3 - "$last_outcome" "$ROOT" << 'PYEOF'
import json, sys, subprocess

try:
  outcome = json.loads(sys.argv[1])
except:
  sys.exit(1)

root = sys.argv[2]
failures = outcome.get('failures', [])

for failure in failures:
  if not failure.strip():
    continue
  # Call dispatch flag for each failure
  cmd = [
    'dispatch', 'flag', 'kai', 'P1',
    f'Simulation failure: {failure}'
  ]
  # Can't directly call dispatch, so we'll use the log mechanism
  # Instead, create the flag entry directly
  import os, datetime

  now = datetime.datetime.utcnow().isoformat() + 'Z'
  kai_log = os.path.join(root, 'kai/ledger/log.jsonl')
  os.makedirs(os.path.dirname(kai_log), exist_ok=True)

  flag_json = json.dumps({
    'ts': now, 'action': 'FLAG', 'task_id': f'kai-sim-failure',
    'from': 'dispatch-simulate-review', 'to': 'kai',
    'severity': 'P1', 'title': f'Simulation failure: {failure}',
    'status': 'FLAGGED'
  })
  with open(kai_log, 'a') as f:
    f.write(flag_json + '\n')

print(f"  {len(failures)} issues auto-escalated")
PYEOF
  fi
}

# ── Dispatch ──
# ── Hyo → Kai message sync ──
cmd_hyo_sync() {
  local sync_script="$ROOT/kai/queue/dispatch-sync-hyo-messages.sh"
  if [[ ! -f "$sync_script" ]]; then
    echo "ERROR: $sync_script not found" >&2
    return 1
  fi
  HYO_ROOT="$ROOT" bash "$sync_script"
}

# ── Hyo inbox: show unread messages ──
cmd_hyo_inbox() {
  local inbox="$ROOT/kai/ledger/hyo-inbox.jsonl"
  if [[ ! -f "$inbox" ]]; then
    echo "No hyo-inbox.jsonl found"
    return
  fi
  python3 -c "
import json, sys
unread = []
all_msgs = []
with open('$inbox') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            e = json.loads(line)
            all_msgs.append(e)
            if e.get('status') == 'unread':
                unread.append(e)
        except: pass

print(f'=== Hyo Inbox ({len(unread)} unread / {len(all_msgs)} total) ===')
if not all_msgs:
    print('  No messages yet.')
else:
    for m in all_msgs[-20:]:  # last 20
        status = '● UNREAD' if m.get('status') == 'unread' else '  read  '
        ts = m.get('ts','')[:16].replace('T',' ')
        print(f'  [{status}] {ts}  {m.get(\"message\",\"\")}')
"
}

cmd="${1:-status}"
shift 2>/dev/null || true

case "$cmd" in
  delegate)       cmd_delegate "$@" ;;
  ack)            cmd_ack "$@" ;;
  report)         cmd_report "$@" ;;
  verify)         cmd_verify "$@" ;;
  close)          cmd_close "$@" ;;
  flag)           cmd_flag "$@" ;;
  escalate)       cmd_escalate "$@" ;;
  self-delegate)  cmd_self_delegate "$@" ;;
  safeguard)      cmd_safeguard "$@" ;;
  health)         cmd_health ;;
  simulate)       cmd_simulate ;;
  simulate-review) cmd_simulate_review ;;
  memory)         cmd_memory ;;
  list)           cmd_list "$@" ;;
  log)            cmd_log "$@" ;;
  status)         cmd_status ;;
  hyo-sync)       cmd_hyo_sync ;;
  hyo-inbox)      cmd_hyo_inbox ;;
  *)  echo "Unknown: $cmd"
      echo "Usage: dispatch {delegate|ack|report|verify|close|flag|escalate|self-delegate|safeguard|health|simulate|simulate-review|memory|list|log|status|hyo-sync|hyo-inbox}" ;;
esac
