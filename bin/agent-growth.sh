#!/usr/bin/env bash
# bin/agent-growth.sh — Growth execution phase for agent runners
#
# Every agent runner sources this and calls: run_growth_phase "$AGENT_NAME"
#
# What it does:
# 1. Reads the agent's GROWTH.md for the next improvement to work on
# 2. Reads improvement tickets (IMP-*) for that agent
# 3. Executes any concrete steps the agent can do autonomously
# 4. Updates GROWTH.md and the ticket with results
# 5. Reports to Kai what changed
#
# Agents have the RIGHT to build. They don't need Kai's permission.
# They report what they did. Kai can veto, but they execute first.
#
# Usage in a runner:
#   source "$HYO_ROOT/bin/agent-growth.sh"
#   run_growth_phase "nel"

set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
GROWTH_LOG_TAG="[growth]"

growth_log() { echo "$GROWTH_LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) [$1] $2"; }

check_aric_day() {
  local agent="$1"
  local day_of_week
  day_of_week=$(date +%u)  # 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun

  # Map day to agent ARIC schedule
  local aric_agent=""
  case "$day_of_week" in
    1) aric_agent="nel" ;;
    2) aric_agent="ra" ;;
    3) aric_agent="sam" ;;
    4) aric_agent="aether" ;;
    5) aric_agent="dex" ;;
    *) return 0 ;;
  esac

  # If today is this agent's ARIC day, trigger it
  if [[ "$agent" == "$aric_agent" ]]; then
    local aric_date
    aric_date=$(TZ="America/Denver" date +%Y-%m-%d)
    local aric_marker_dir="$HYO_ROOT/agents/$agent/research"
    mkdir -p "$aric_marker_dir"

    growth_log "$agent" "ARIC trigger: Today is $agent's ARIC day — full research cycle triggered (Phases 1-7)"
    touch "$aric_marker_dir/aric-trigger-$aric_date"
    growth_log "$agent" "Created marker: $aric_marker_dir/aric-trigger-$aric_date"
  fi
}

run_growth_phase() {
  local agent="$1"
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"
  local ticket_ledger="$HYO_ROOT/kai/tickets/tickets.jsonl"
  local timestamp
  timestamp=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)

  growth_log "$agent" "Starting growth phase"

  # Check if today is this agent's ARIC day and trigger if so
  check_aric_day "$agent"

  if [[ ! -f "$growth_file" ]]; then
    growth_log "$agent" "No GROWTH.md found — skipping growth phase"
    return 0
  fi

  # Find the agent's next improvement ticket that's OPEN
  local next_ticket=""
  local next_title=""
  local next_weakness=""
  if [[ -f "$ticket_ledger" ]]; then
    next_ticket=$(python3 -c "
import json
with open('$ticket_ledger') as f:
    for line in f:
        line = line.strip()
        if not line: continue
        try:
            t = json.loads(line)
            if t.get('owner') == '$agent' and t.get('ticket_type') == 'improvement' and t.get('status') == 'OPEN':
                print(t['id'])
                break
        except: pass
" 2>/dev/null)
    if [[ -n "$next_ticket" ]]; then
      next_title=$(python3 -c "
import json
with open('$ticket_ledger') as f:
    for line in f:
        try:
            t = json.loads(line)
            if t.get('id') == '$next_ticket':
                print(t.get('title', '')[:80])
                break
        except: pass
" 2>/dev/null)
      next_weakness=$(python3 -c "
import json
with open('$ticket_ledger') as f:
    for line in f:
        try:
            t = json.loads(line)
            if t.get('id') == '$next_ticket':
                print(t.get('weakness', ''))
                break
        except: pass
" 2>/dev/null)
    fi
  fi

  if [[ -z "$next_ticket" ]]; then
    growth_log "$agent" "No open improvement tickets — growth phase idle"
    return 0
  fi

  growth_log "$agent" "Next improvement: $next_ticket — $next_title (addresses $next_weakness)"

  # ── Agent-specific growth execution ──
  # Each agent has concrete steps it can execute autonomously.
  # These are NOT LLM reasoning — they're concrete scripts/checks.

  local executed=false
  local result=""

  case "$agent" in
    nel)
      # Nel I1: Adaptive sentinel — can we detect repeated failures and generate deeper checks?
      if [[ "$next_weakness" == "W1" ]]; then
        # Count how many sentinel checks have failed 5+ consecutive times
        local sentinel_state="$HYO_ROOT/agents/nel/memory/sentinel.state.json"
        if [[ -f "$sentinel_state" ]]; then
          result=$(python3 -c "
import json
with open('$sentinel_state') as f:
    s = json.load(f)
chronic = []
for check, data in s.get('checks', {}).items():
    consec = data.get('consecutive_failures', 0)
    if consec >= 5:
        chronic.append(f'{check}: {consec} consecutive failures')
if chronic:
    print(f'Found {len(chronic)} chronic failures: ' + '; '.join(chronic))
else:
    print('No chronic failures detected (all <5 consecutive)')
" 2>/dev/null) || result="Could not read sentinel state"
          executed=true
        fi
      fi

      # Nel I2: Dependency audit — can we scan package.json right now?
      if [[ "$next_weakness" == "W2" ]]; then
        local pkg_json="$HYO_ROOT/package.json"
        if [[ -f "$pkg_json" ]]; then
          result=$(python3 -c "
import json
with open('$pkg_json') as f:
    pkg = json.load(f)
deps = {}
deps.update(pkg.get('dependencies', {}))
deps.update(pkg.get('devDependencies', {}))
print(f'Found {len(deps)} dependencies in package.json:')
for name, ver in sorted(deps.items()):
    print(f'  {name}: {ver}')
print(f'Next step: cross-reference these against GitHub Advisory Database')
" 2>/dev/null) || result="Could not parse package.json"
          executed=true
        else
          result="No package.json found at project root — check website/ or agents/sam/website/"
          executed=true
        fi
      fi
      ;;

    ra)
      # Ra I1: Source health monitoring — can we validate sources right now?
      if [[ "$next_weakness" == "W1" ]]; then
        local sources_json="$HYO_ROOT/agents/ra/pipeline/sources.json"
        if [[ -f "$sources_json" ]]; then
          result=$(python3 -c "
import json
with open('$sources_json') as f:
    sources = json.load(f)
if isinstance(sources, list):
    print(f'Found {len(sources)} sources in pipeline config.')
    print('Next step: add health score field to each source, test reachability before gather.')
elif isinstance(sources, dict):
    total = sum(len(v) if isinstance(v, list) else 1 for v in sources.values())
    print(f'Found {total} sources across {len(sources)} categories.')
    print('Next step: add per-source health scoring to gather.py Phase 0.')
" 2>/dev/null) || result="Could not parse sources.json"
          executed=true
        fi
      fi
      ;;

    sam)
      # Sam I2: Vercel KV — check if KV is configured
      if [[ "$next_weakness" == "W2" ]]; then
        local vercel_json="$HYO_ROOT/website/vercel.json"
        if [[ -f "$vercel_json" ]]; then
          result=$(python3 -c "
import json
with open('$vercel_json') as f:
    v = json.load(f)
has_kv = 'stores' in str(v) or 'kv' in str(v).lower()
if has_kv:
    print('Vercel KV appears configured in vercel.json')
else:
    print('No KV configuration found in vercel.json. Need to: 1) provision KV via Vercel dashboard, 2) add KV_REST_API_URL + KV_REST_API_TOKEN to env, 3) install @vercel/kv package')
" 2>/dev/null) || result="Could not parse vercel.json"
          executed=true
        fi
      fi

      # Sam I3: Error handling audit — count endpoints without try/catch
      if [[ "$next_weakness" == "W3" ]]; then
        local api_dir="$HYO_ROOT/website/api"
        if [[ -d "$api_dir" ]]; then
          result=$(python3 -c "
import os, glob
api_dir = '$api_dir'
files = glob.glob(os.path.join(api_dir, '**', '*.js'), recursive=True)
no_trycatch = []
for f in files:
    content = open(f).read()
    if 'try' not in content and 'catch' not in content:
        no_trycatch.append(os.path.basename(f))
if no_trycatch:
    print(f'{len(no_trycatch)} API files lack try/catch: {', '.join(no_trycatch[:5])}')
else:
    print(f'All {len(files)} API files have try/catch blocks')
" 2>/dev/null) || result="Could not scan API directory"
          executed=true
        fi
      fi
      ;;

    aether)
      # Aether I1: Phantom position tracking — count phantom warnings in recent logs
      if [[ "$next_weakness" == "W1" ]]; then
        local log_dir="$HYO_ROOT/agents/aether/logs"
        result=$(python3 -c "
import glob, os
log_dir = '$log_dir'
logs = sorted(glob.glob(os.path.join(log_dir, 'aether-*.log')))[-3:]  # last 3 days
total_phantom = 0
for log in logs:
    with open(log) as f:
        phantoms = sum(1 for line in f if 'POS WARNING' in line)
        total_phantom += phantoms
        day = os.path.basename(log)
        if phantoms > 0:
            print(f'  {day}: {phantoms} phantom warnings')
print(f'Total phantom warnings (last 3 days): {total_phantom}')
if total_phantom > 10:
    print('URGENT: Phantom rate is high. Need to build the separator ASAP.')
" 2>/dev/null) || result="Could not scan aether logs"
        executed=true
      fi
      ;;

    dex)
      # Dex I1: Auto-repair JSONL — count corrupt entries across ledgers
      if [[ "$next_weakness" == "W1" ]]; then
        result=$(python3 -c "
import glob, json, os
root = '$HYO_ROOT'
ledgers = glob.glob(os.path.join(root, '**', '*.jsonl'), recursive=True)
corrupt = 0
fixable = 0
for ledger in ledgers:
    try:
        with open(ledger) as f:
            for i, line in enumerate(f):
                line = line.strip()
                if not line: continue
                try:
                    json.loads(line)
                except:
                    corrupt += 1
                    # Check if it's a common fixable pattern
                    if line.endswith('}{'):
                        fixable += 1
                    elif line.count('{') != line.count('}'):
                        fixable += 1
    except: pass
print(f'Scanned {len(ledgers)} JSONL files.')
print(f'Found {corrupt} corrupt entries ({fixable} likely auto-fixable).')
if corrupt > 0:
    print(f'Auto-repair rate estimate: {fixable}/{corrupt} = {100*fixable//max(corrupt,1)}%')
" 2>/dev/null) || result="Could not scan JSONL files"
        executed=true
      fi

      # Dex I2: Root cause clustering
      if [[ "$next_weakness" == "W2" ]]; then
        local ki_file="$HYO_ROOT/kai/ledger/known-issues.jsonl"
        if [[ -f "$ki_file" ]]; then
          result=$(python3 -c "
import json
from collections import Counter
clusters = Counter()
with open('$ki_file') as f:
    for line in f:
        try:
            e = json.loads(line.strip())
            # Cluster by source/category
            src = e.get('source', e.get('agent', 'unknown'))
            cat = e.get('category', e.get('type', 'uncategorized'))
            clusters[f'{src}/{cat}'] += 1
        except: pass
print(f'Root cause clusters from known-issues.jsonl:')
for cluster, count in clusters.most_common(10):
    print(f'  {cluster}: {count} issues')
" 2>/dev/null) || result="Could not cluster known issues"
          executed=true
        fi
      fi
      ;;
  esac

  # ── Report results ──
  if [[ "$executed" == true && -n "$result" ]]; then
    growth_log "$agent" "Growth execution result:"
    echo "$result" | while read -r line; do
      growth_log "$agent" "  $line"
    done

    # Update GROWTH.md growth log
    local today_date
    today_date=$(TZ="America/Denver" date +%Y-%m-%d)
    local short_result
    short_result=$(echo "$result" | head -1 | cut -c1-80)

    # Append to growth log table in GROWTH.md
    if grep -q "## Growth Log" "$growth_file"; then
      echo "| $today_date | $next_ticket ($next_weakness): $short_result | Automated assessment |" >> "$growth_file"
      growth_log "$agent" "Updated GROWTH.md growth log"
    fi
  else
    growth_log "$agent" "No executable steps for current ticket — needs Kai session for LLM reasoning"
  fi

  growth_log "$agent" "Growth phase complete"
}
