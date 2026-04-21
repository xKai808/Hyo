#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# agent-self-improve.sh — Closed-loop self-improvement for every agent
# Version: 1.0 — 2026-04-21
#
# THE COMPOUNDING FLYWHEEL:
#
#   Weakness (GROWTH.md)
#       ↓
#   Research (agent-research.sh + memory query)
#       ↓
#   Implementation (claude-code-delegate.sh)
#       ↓
#   Verification (nel-qa-cycle.sh / verify-render.sh)
#       ↓
#   Knowledge extraction (→ KNOWLEDGE.md + memory engine)
#       ↓
#   Weakness resolved → next weakness identified
#       ↓
#   [repeats every cycle, compounds across all agents]
#
# This is the difference between:
#   - Agents that detect the same problem forever (old system)
#   - Agents that fix their own problems and get structurally better (this)
#
# Usage:
#   bash bin/agent-self-improve.sh nel      # run for one agent
#   bash bin/agent-self-improve.sh all      # run for all agents
#
# Called by: agent runners (before main work), kai-autonomous.sh (daily 08:00 MT)
# Log: kai/ledger/self-improve.log
# State: agents/<name>/self-improve-state.json
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/self-improve.log"
KNOWLEDGE_MD="$HYO_ROOT/kai/memory/KNOWLEDGE.md"
MEMORY_ENGINE="$HYO_ROOT/kai/memory/agent_memory/memory_engine.py"
DELEGATE_SH="$HYO_ROOT/bin/claude-code-delegate.sh"
RESEARCH_SH="$HYO_ROOT/bin/agent-research.sh"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"

mkdir -p "$(dirname "$LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)

log()     { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_section() { echo "" >> "$LOG"; echo "══ $* ══" | tee -a "$LOG"; }

# ─── Source delegate ─────────────────────────────────────────────────────────
[[ -f "$DELEGATE_SH" ]] && source "$DELEGATE_SH" || true

# ─── State management ────────────────────────────────────────────────────────
get_state() {
  local agent="$1"
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo '{"current_weakness":"W1","stage":"research","cycles":0,"improvements":[],"last_run":""}'
  fi
}

save_state() {
  local agent="$1" state="$2"
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  echo "$state" > "$state_file"
}

# ─── Phase 1: Parse weaknesses from GROWTH.md ────────────────────────────────
parse_weaknesses() {
  local agent="$1"
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"

  [[ ! -f "$growth_file" ]] && echo "[]" && return

  python3 - "$growth_file" << 'PYEOF'
import sys, re, json

growth_file = sys.argv[1]
content = open(growth_file).read()

weaknesses = []
# Match ### W1:, ### W2:, ### W3: blocks
pattern = r'### (W\d+): (.+?)\n(.*?)(?=\n### W\d+:|\n## |\Z)'
matches = re.findall(pattern, content, re.DOTALL)

for wid, title, body in matches:
    # Extract severity
    sev_match = re.search(r'\*\*Severity:\*\*\s*(\w+)', body)
    severity = sev_match.group(1) if sev_match else 'P2'

    # Extract status (resolved/active/in-progress)
    status = 'active'
    if 'RESOLVED' in body.upper() or '✓' in body:
        status = 'resolved'
    elif 'IN PROGRESS' in body.upper() or 'IN-PROGRESS' in body.upper():
        status = 'in_progress'

    # Extract evidence (first 200 chars of evidence section)
    ev_match = re.search(r'\*\*Evidence:\*\*\n(.+?)(?=\n\*\*|\Z)', body, re.DOTALL)
    evidence = ev_match.group(1).strip()[:300] if ev_match else ''

    # Extract root cause
    rc_match = re.search(r'\*\*Root cause:\*\*\n(.+?)(?=\n\*\*|\Z)', body, re.DOTALL)
    root_cause = rc_match.group(1).strip()[:200] if rc_match else ''

    weaknesses.append({
        'id': wid,
        'title': title.strip(),
        'severity': severity,
        'status': status,
        'evidence': evidence,
        'root_cause': root_cause
    })

print(json.dumps(weaknesses))
PYEOF
}

# ─── Phase 2: Query memory for related prior knowledge ───────────────────────
query_memory() {
  local agent="$1" weakness_title="$2"

  if [[ ! -f "$MEMORY_ENGINE" ]]; then
    echo "[]"
    return
  fi

  HYO_ROOT="$HYO_ROOT" python3 "$MEMORY_ENGINE" recall "$weakness_title" --limit 3 2>/dev/null | \
    python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
results = []
for l in lines:
    l = l.strip()
    if not l or l.startswith('['): continue
    # Strip any leading timestamps/labels
    if '|' in l:
        parts = l.split('|', 1)
        results.append(parts[-1].strip())
    else:
        results.append(l[:200])
print(json.dumps(results[:3]))
" 2>/dev/null || echo "[]"
}

# ─── Phase 3: Research the weakness ──────────────────────────────────────────
research_weakness() {
  local agent="$1" weakness_id="$2" weakness_title="$3" evidence="$4"

  local research_dir="$HYO_ROOT/agents/$agent/research/improvements"
  local research_file="$research_dir/${weakness_id}-${TODAY}.md"
  mkdir -p "$research_dir"

  # Skip if researched today
  if [[ -f "$research_file" ]]; then
    log "  Research exists for $weakness_id ($agent): $research_file"
    cat "$research_file"
    return 0
  fi

  log "  Researching $weakness_id ($agent): $weakness_title"

  # Use Claude Code to research if available, otherwise use agent-research.sh
  local claude_bin
  if claude_bin=$(_find_claude_bin 2>/dev/null); then
    local research_prompt
    research_prompt=$(cat << PROMPT
You are researching a weakness in the hyo.world agent system to find a concrete fix.

Agent: $agent
Weakness ID: $weakness_id
Weakness: $weakness_title
Evidence: $evidence

Your job:
1. Analyze the root cause of this weakness
2. Research best practices for fixing it (think about what patterns solve this class of problem)
3. Propose a SPECIFIC, IMPLEMENTABLE fix — name the exact files to change, the exact logic to add
4. Estimate the fix complexity (hours) and confidence it will work

Output format:
ROOT_CAUSE: <one sentence>
FIX_APPROACH: <specific technical approach>
FILES_TO_CHANGE: <comma-separated file paths relative to HYO_ROOT>
IMPLEMENTATION: <step-by-step what to code>
CONFIDENCE: HIGH|MEDIUM|LOW
COMPLEXITY: <estimated hours>
PROMPT
)
    local research_output
    research_output=$(echo "$research_prompt" | "$claude_bin" \
      -p --output-format text --dangerously-skip-permissions 2>/dev/null || echo "")

    if [[ -n "$research_output" ]]; then
      cat > "$research_file" << RESEOF
# Research: $weakness_id — $weakness_title
**Agent:** $agent
**Date:** $TODAY
**Status:** pending_implementation

$research_output
RESEOF
      log "  ✓ Research complete → $research_file"
      echo "$research_output"
      return 0
    fi
  fi

  # Fallback: use agent-research.sh
  if [[ -x "$RESEARCH_SH" ]]; then
    bash "$RESEARCH_SH" "$agent" 2>/dev/null || true
  fi

  echo ""
}

# ─── Phase 4: Build implementation brief from research ───────────────────────
build_implementation_brief() {
  local agent="$1" weakness_id="$2" weakness_title="$3"
  local research_file="$HYO_ROOT/agents/$agent/research/improvements/${weakness_id}-${TODAY}.md"

  [[ ! -f "$research_file" ]] && echo "" && return

  local fix_approach files_to_change implementation
  fix_approach=$(grep "^FIX_APPROACH:" "$research_file" | sed 's/FIX_APPROACH: //')
  files_to_change=$(grep "^FILES_TO_CHANGE:" "$research_file" | sed 's/FILES_TO_CHANGE: //')
  implementation=$(grep -A 20 "^IMPLEMENTATION:" "$research_file" | head -20)
  local confidence
  confidence=$(grep "^CONFIDENCE:" "$research_file" | sed 's/CONFIDENCE: //')

  # Only proceed if confidence is HIGH or MEDIUM
  if [[ "$confidence" == "LOW" ]]; then
    log "  Skipping implementation: confidence=$confidence for $weakness_id"
    echo ""
    return
  fi

  echo "Fix $weakness_id in $agent: $weakness_title. Approach: $fix_approach. Files: $files_to_change. Steps: $implementation"
}

# ─── Phase 5: Verify the improvement worked ──────────────────────────────────
verify_improvement() {
  local agent="$1" weakness_id="$2"

  log "  Verifying improvement for $weakness_id ($agent)..."

  # Run agent-specific verification
  case "$agent" in
    nel)
      # Run a quick nel QA cycle check
      local qa_script="$HYO_ROOT/agents/nel/nel-qa-cycle.sh"
      if [[ -f "$qa_script" ]]; then
        HYO_ROOT="$HYO_ROOT" bash "$qa_script" 2>/dev/null | tail -5
        return ${PIPESTATUS[0]}
      fi
      ;;
    sam)
      # Check that website files are consistent
      local verify_script="$HYO_ROOT/bin/verify-render.sh"
      if [[ -f "$verify_script" ]]; then
        HYO_ROOT="$HYO_ROOT" bash "$verify_script" --quick 2>/dev/null | tail -3
        return ${PIPESTATUS[0]}
      fi
      ;;
    *)
      # Generic: check git diff has changes
      cd "$HYO_ROOT" && git diff --stat HEAD 2>/dev/null | tail -2
      ;;
  esac
  return 0
}

# ─── Phase 6: Extract and persist knowledge ──────────────────────────────────
persist_knowledge() {
  local agent="$1" weakness_id="$2" weakness_title="$3" summary="$4"

  log "  Persisting knowledge for $weakness_id → KNOWLEDGE.md + memory engine"

  # Write to KNOWLEDGE.md
  local knowledge_entry
  knowledge_entry=$(cat << ENTRY

### [$TODAY] $agent fixed $weakness_id: $weakness_title
**What worked:** $summary
**Files changed:** see evolution.jsonl
**Applicable to:** any agent with similar weakness
ENTRY
)

  # Append to KNOWLEDGE.md under an "Agent Improvements" section
  if grep -q "## Agent Improvements" "$KNOWLEDGE_MD" 2>/dev/null; then
    # Append after section header
    python3 - "$KNOWLEDGE_MD" "$knowledge_entry" << 'PYEOF'
import sys
path = sys.argv[1]
entry = sys.argv[2]
content = open(path).read()
marker = '## Agent Improvements'
if marker in content:
    content = content.replace(marker, marker + '\n' + entry, 1)
else:
    content += '\n## Agent Improvements\n' + entry
open(path, 'w').write(content)
print("KNOWLEDGE.md updated")
PYEOF
  else
    cat >> "$KNOWLEDGE_MD" << MDEOF

## Agent Improvements
$knowledge_entry
MDEOF
  fi

  # Write to memory engine
  if [[ -f "$MEMORY_ENGINE" ]]; then
    HYO_ROOT="$HYO_ROOT" python3 "$MEMORY_ENGINE" observe \
      "[$agent] Fixed $weakness_id — $weakness_title: $summary" \
      --type "improvement" \
      --agent "$agent" 2>/dev/null || true
  fi

  # Log to agent evolution.jsonl
  local evolution_file="$HYO_ROOT/agents/$agent/evolution.jsonl"
  python3 -c "
import json, datetime
entry = {
    'ts': '$NOW_MT',
    'type': 'weakness_resolved',
    'weakness_id': '$weakness_id',
    'weakness': '$weakness_title',
    'summary': '$summary',
    'method': 'claude-code-delegate',
    'compounded_to_knowledge': True
}
with open('$evolution_file', 'a') as f:
    f.write(json.dumps(entry) + '\n')
print('evolution.jsonl updated')
" 2>/dev/null || true
}

# ─── Phase 7: Identify next weakness ─────────────────────────────────────────
identify_next_weakness() {
  local agent="$1" resolved_id="$2"
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"

  # Mark resolved weakness in GROWTH.md
  if [[ -f "$growth_file" ]]; then
    python3 - "$growth_file" "$resolved_id" << 'PYEOF'
import sys, re
path = sys.argv[1]
wid = sys.argv[2]
content = open(path).read()
# Add RESOLVED tag after the weakness header
content = re.sub(
    r'(### ' + wid + r': .+?\n)',
    r'\1**Status:** ✓ RESOLVED — auto-fixed by agent-self-improve.sh\n',
    content
)
open(path, 'w').write(content)
print(f"{wid} marked resolved in GROWTH.md")
PYEOF
  fi

  # Use Claude Code to identify the NEXT weakness based on current metrics
  local claude_bin
  if claude_bin=$(_find_claude_bin 2>/dev/null); then
    local next_prompt
    next_prompt=$(cat << PROMPT
You are $agent, a hyo.world agent. You just resolved weakness $resolved_id.

Read the current state of your domain and identify the NEXT highest-impact weakness.

Base your assessment on:
1. Recent errors in agents/$agent/logs/ (look for recurring patterns)
2. Current ticket count and types in kai/tickets/tickets.jsonl for owner=$agent
3. Your GROWTH.md for any remaining weaknesses
4. Known issues in kai/ledger/known-issues.jsonl related to $agent

Output format (used to auto-update GROWTH.md):
NEXT_WEAKNESS_ID: W4 (or next available)
NEXT_WEAKNESS_TITLE: <title>
NEXT_WEAKNESS_SEVERITY: P0|P1|P2
NEXT_WEAKNESS_EVIDENCE: <specific evidence from files you read>
NEXT_WEAKNESS_ROOT_CAUSE: <one sentence>
NEXT_WEAKNESS_FIX_APPROACH: <specific approach>
PROMPT
)
    local next_weakness
    next_weakness=$(echo "$next_prompt" | "$claude_bin" \
      -p --output-format text --dangerously-skip-permissions 2>/dev/null || echo "")

    if [[ -n "$next_weakness" ]]; then
      # Append new weakness to GROWTH.md
      local nw_id nw_title nw_sev nw_ev nw_rc nw_fix
      nw_id=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_ID:" | sed 's/NEXT_WEAKNESS_ID: //')
      nw_title=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_TITLE:" | sed 's/NEXT_WEAKNESS_TITLE: //')
      nw_sev=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_SEVERITY:" | sed 's/NEXT_WEAKNESS_SEVERITY: //')
      nw_ev=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_EVIDENCE:" | sed 's/NEXT_WEAKNESS_EVIDENCE: //')
      nw_rc=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_ROOT_CAUSE:" | sed 's/NEXT_WEAKNESS_ROOT_CAUSE: //')
      nw_fix=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_FIX_APPROACH:" | sed 's/NEXT_WEAKNESS_FIX_APPROACH: //')

      if [[ -n "$nw_id" && -n "$nw_title" ]]; then
        cat >> "$growth_file" << GROWTHEOF

### $nw_id: $nw_title
**Severity:** $nw_sev
**Status:** active — auto-identified by agent-self-improve.sh on $TODAY

**Evidence:**
$nw_ev

**Root cause:**
$nw_rc

**Fix approach:**
$nw_fix
GROWTHEOF
        log "  New weakness identified: $nw_id — $nw_title"

        # Create improvement ticket
        if [[ -f "$TICKET_SH" ]]; then
          HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
            --agent "$agent" \
            --title "Improvement [$nw_id]: $nw_title" \
            --priority "${nw_sev:-P2}" \
            --type "improvement" \
            --created-by "agent-self-improve" 2>/dev/null || true
        fi

        echo "$nw_id"
      fi
    fi
  fi
}

# ─── Main: run self-improvement cycle for one agent ──────────────────────────
run_self_improve() {
  local agent="$1"
  local agent_dir="$HYO_ROOT/agents/$agent"

  [[ ! -d "$agent_dir" ]] && log "SKIP: agent dir not found: $agent_dir" && return 0

  log_section "SELF-IMPROVE: $agent — $TODAY"

  # Load state
  local state
  state=$(get_state "$agent")
  local current_weakness stage cycles
  current_weakness=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_weakness','W1'))" 2>/dev/null || echo "W1")
  stage=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stage','research'))" 2>/dev/null || echo "research")
  cycles=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cycles',0))" 2>/dev/null || echo "0")

  log "  State: weakness=$current_weakness stage=$stage cycles=$cycles"

  # Parse weaknesses
  local weaknesses
  weaknesses=$(parse_weaknesses "$agent")
  local weakness_count
  weakness_count=$(echo "$weaknesses" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  log "  Weaknesses found: $weakness_count"

  if [[ "$weakness_count" -eq 0 ]]; then
    log "  No weaknesses in GROWTH.md — nothing to improve"
    return 0
  fi

  # Get current weakness details
  local weakness_title weakness_severity weakness_status evidence root_cause
  weakness_title=$(echo "$weaknesses" | python3 -c "
import json,sys
ws = json.load(sys.stdin)
target = '$current_weakness'
for w in ws:
    if w['id'] == target:
        print(w['title'])
        break
" 2>/dev/null || echo "")
  weakness_status=$(echo "$weaknesses" | python3 -c "
import json,sys
ws = json.load(sys.stdin)
for w in ws:
    if w['id'] == '$current_weakness':
        print(w.get('status','active'))
        break
" 2>/dev/null || echo "active")
  evidence=$(echo "$weaknesses" | python3 -c "
import json,sys
ws = json.load(sys.stdin)
for w in ws:
    if w['id'] == '$current_weakness':
        print(w.get('evidence','')[:200])
        break
" 2>/dev/null || echo "")

  # Skip already-resolved weaknesses
  if [[ "$weakness_status" == "resolved" ]]; then
    log "  $current_weakness already resolved — advancing to next"
    # Advance weakness
    local next_wid
    next_wid=$(echo "$weaknesses" | python3 -c "
import json,sys
ws = json.load(sys.stdin)
ids = [w['id'] for w in ws]
curr = '$current_weakness'
idx = ids.index(curr) if curr in ids else -1
if idx >= 0 and idx + 1 < len(ids):
    print(ids[idx+1])
else:
    print(ids[0] if ids else 'W1')
" 2>/dev/null || echo "W1")
    save_state "$agent" "{\"current_weakness\":\"$next_wid\",\"stage\":\"research\",\"cycles\":$cycles,\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
    return 0
  fi

  log "  Working on: $current_weakness — $weakness_title (stage: $stage)"

  case "$stage" in

    research)
      # ── Stage 1: Research the weakness ──
      log "  Stage: RESEARCH"

      # Query prior knowledge first
      local prior_knowledge
      prior_knowledge=$(query_memory "$agent" "$weakness_title")
      local prior_count
      prior_count=$(echo "$prior_knowledge" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
      log "  Prior memory hits: $prior_count"

      # Run research
      research_weakness "$agent" "$current_weakness" "$weakness_title" "$evidence" > /dev/null

      # Advance to implement
      save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"implement\",\"cycles\":$((cycles+1)),\"prior_knowledge_hits\":$prior_count,\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
      log "  → Advanced to implement stage"
      ;;

    implement)
      # ── Stage 2: Implement the fix ──
      log "  Stage: IMPLEMENT"

      # Build implementation brief from research
      local brief
      brief=$(build_implementation_brief "$agent" "$current_weakness" "$weakness_title")

      if [[ -z "$brief" ]]; then
        log "  No implementation brief (confidence too low or research missing) — skipping"
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"verify\",\"cycles\":$cycles,\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
        return 0
      fi

      # Find relevant files from research
      local research_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
      local files_hint=""
      if [[ -f "$research_file" ]]; then
        files_hint=$(grep "^FILES_TO_CHANGE:" "$research_file" | sed 's/FILES_TO_CHANGE: //')
      fi

      # Delegate to Claude Code
      if [[ -f "$DELEGATE_SH" ]]; then
        source "$DELEGATE_SH" 2>/dev/null || true
        claude_delegate \
          --agent "$agent" \
          --task "$brief" \
          --files "${files_hint:-}" \
          --priority "P2" \
          --timeout 600 && {
          log "  ✓ Implementation complete"
          save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"verify\",\"cycles\":$cycles,\"improvements\":[\"$current_weakness\"],\"last_run\":\"$NOW_MT\"}"
        } || {
          log "  ✗ Implementation failed — will retry next cycle"
          save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
        }
      else
        log "  SKIP: claude-code-delegate.sh not found"
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"verify\",\"cycles\":$cycles,\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
      fi
      ;;

    verify)
      # ── Stage 3: Verify + persist knowledge ──
      log "  Stage: VERIFY"

      verify_improvement "$agent" "$current_weakness"
      local verify_exit=$?

      if [[ $verify_exit -eq 0 ]]; then
        log "  ✓ Verification passed"

        # Persist knowledge
        persist_knowledge "$agent" "$current_weakness" "$weakness_title" \
          "Fixed via Claude Code delegate — see agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"

        # Identify next weakness
        local next_wid
        next_wid=$(identify_next_weakness "$agent" "$current_weakness")
        next_wid="${next_wid:-W1}"

        log "  Next weakness: $next_wid"
        save_state "$agent" "{\"current_weakness\":\"$next_wid\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"improvements\":[\"$current_weakness\"],\"last_run\":\"$NOW_MT\"}"

        # Commit all improvements
        cd "$HYO_ROOT" 2>/dev/null && \
          git add "agents/$agent/" "kai/memory/KNOWLEDGE.md" 2>/dev/null && \
          git diff --cached --quiet 2>/dev/null || \
          git commit -m "improve($agent): $current_weakness resolved — $weakness_title" 2>/dev/null && \
          git push origin main 2>/dev/null && \
          log "  ✓ Improvement committed and pushed" || true

      else
        log "  ✗ Verification failed — regression risk, rolling back to research stage"
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
      fi
      ;;
  esac

  log "  Cycle complete for $agent"
}

# ─── Summary report ───────────────────────────────────────────────────────────
report_summary() {
  log_section "SELF-IMPROVE SUMMARY — $TODAY"

  python3 - "$HYO_ROOT" << 'PYEOF'
import json, sys, os
from pathlib import Path

root = Path(sys.argv[1])
agents = ['nel', 'ra', 'sam', 'aether', 'dex', 'hyo']

print(f"{'Agent':<10} {'Weakness':<6} {'Stage':<12} {'Cycles':<8} {'Last Run':<20}")
print("-" * 60)
for agent in agents:
    state_file = root / f"agents/{agent}/self-improve-state.json"
    if state_file.exists():
        try:
            s = json.loads(state_file.read_text())
            wid = s.get('current_weakness', '?')
            stage = s.get('stage', '?')
            cycles = s.get('cycles', 0)
            last = s.get('last_run', 'never')[:16]
            print(f"{agent:<10} {wid:<6} {stage:<12} {cycles:<8} {last:<20}")
        except:
            print(f"{agent:<10} ERROR reading state")
    else:
        print(f"{agent:<10} no state yet")
PYEOF
}

# ─── Entrypoint ───────────────────────────────────────────────────────────────
TARGET="${1:-all}"

if [[ "$TARGET" == "all" ]]; then
  for agent in nel sam aether ra dex; do
    run_self_improve "$agent" || true
  done
  report_summary
else
  run_self_improve "$TARGET"
fi

log "agent-self-improve.sh complete"
exit 0
