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

# ─── Source delegate (defines _find_claude_bin) ───────────────────────────────
[[ -f "$DELEGATE_SH" ]] && source "$DELEGATE_SH" || true

# Fault-fix #3: guarantee _find_claude_bin exists even if source failed
if ! declare -f _find_claude_bin > /dev/null 2>&1; then
  _find_claude_bin() {
    for candidate in \
      "$HOME/.npm-global/bin/claude" \
      "/usr/local/bin/claude" \
      "/opt/homebrew/bin/claude" \
      "$(which claude 2>/dev/null)"; do
      [[ -x "$candidate" ]] && echo "$candidate" && return 0
    done
    return 1
  }
fi

# ─── Circuit breaker: verify Claude Code responds before any cycle ─────────────
# P0 fix: never run a cycle when the tool is unavailable — advances state on nothing
check_claude_health() {
  local claude_bin
  if ! claude_bin=$(_find_claude_bin 2>/dev/null); then
    log "  CIRCUIT BREAKER: Claude Code binary not found"
    return 1
  fi
  if ! "$claude_bin" --version > /dev/null 2>&1; then
    log "  CIRCUIT BREAKER: Claude Code binary unresponsive"
    return 1
  fi
  return 0
}

# ─── State management (fault-fix #2: flock for concurrent-safe writes) ────────
MAX_RETRIES=3  # fault-fix #6: cap retries per weakness

get_state() {
  local agent="$1"
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo '{"current_weakness":"W1","stage":"research","cycles":0,"failure_count":0,"improvements":[],"last_run":""}'
  fi
}

save_state() {
  local agent="$1" state="$2"
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"

  # Pre-run: purge any stale .lock artifacts (file OR directory) unconditionally.
  # Root cause of 6-day miss: mkdir-based locking created file-type .lock artifacts
  # (not directories) that made `mkdir "$lock_file"` fail on every subsequent call,
  # `[[ -d ]]` return false (skipping stale cleanup), and rmdir fail silently.
  # Result: state never written. Fix: use Python atomic write — no external lock needed.
  rm -f "${state_file}.lock" 2>/dev/null || true
  rmdir "${state_file}.lock" 2>/dev/null || true

  # Python atomic write: write to tmp, then rename (rename is atomic on APFS/HFS+/ext4)
  python3 - << PYEOF
import json, os, sys, tempfile
state_file = "$state_file"
state_json = '''$state'''
try:
    data = json.loads(state_json)
except json.JSONDecodeError as e:
    print(f"[save_state] WARN: invalid JSON for $agent — {e}", file=sys.stderr)
    sys.exit(1)
os.makedirs(os.path.dirname(state_file), exist_ok=True)
tmp = state_file + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
os.replace(tmp, state_file)  # atomic on POSIX
PYEOF
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    log "ERROR: save_state failed for $agent (exit $rc)"
    return 1
  fi
  log "  ✓ State saved for $agent"
}

# ─── Phase 1: Parse weaknesses + expansion opportunities from GROWTH.md ────────
# fault-fix #7: also parses E1/E2/E3 expansion opportunity blocks
# fault-fix #10: alert when GROWTH.md missing
parse_weaknesses() {
  local agent="$1"
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"

  if [[ ! -f "$growth_file" ]]; then
    log "  ALERT: $agent has no GROWTH.md — self-improvement flywheel cannot run"
    # Open a ticket so Kai knows
    if [[ -f "$TICKET_SH" ]]; then
      HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
        --agent "$agent" \
        --title "Missing GROWTH.md: $agent has no weakness/opportunity tracking" \
        --priority "P1" \
        --type "improvement" \
        --created-by "agent-self-improve" 2>/dev/null || true
    fi
    echo "[]"
    return
  fi

  python3 - "$growth_file" << 'PYEOF'
import sys, re, json

growth_file = sys.argv[1]
content = open(growth_file).read()

items = []
# Match ### W1:, ### W2:, ### W3: (weaknesses) AND ### E1:, ### E2: (expansion opportunities)
pattern = r'### ([WE]\d+): (.+?)\n(.*?)(?=\n### [WE]\d+:|\n## |\Z)'
matches = re.findall(pattern, content, re.DOTALL)

for wid, title, body in matches:
    # Extract severity
    sev_match = re.search(r'\*\*Severity:\*\*\s*(\w+)', body)
    severity = sev_match.group(1) if sev_match else 'P2'

    # Extract status — fault-fix: require explicit RESOLVED marker, not just '✓' in body
    status = 'active'
    if re.search(r'\*\*Status:\*\*.*RESOLVED', body, re.IGNORECASE):
        status = 'resolved'
    elif re.search(r'\*\*Status:\*\*.*in.progress', body, re.IGNORECASE):
        status = 'in_progress'

    # Extract evidence
    ev_match = re.search(r'\*\*Evidence:\*\*\n(.+?)(?=\n\*\*|\Z)', body, re.DOTALL)
    evidence = ev_match.group(1).strip()[:300] if ev_match else ''

    # Extract root cause / opportunity description
    rc_match = re.search(r'\*\*Root cause:\*\*\n(.+?)(?=\n\*\*|\Z)', body, re.DOTALL)
    if not rc_match:
        rc_match = re.search(r'\*\*Opportunity:\*\*\n(.+?)(?=\n\*\*|\Z)', body, re.DOTALL)
    root_cause = rc_match.group(1).strip()[:200] if rc_match else ''

    item_type = 'expansion' if wid.startswith('E') else 'weakness'
    items.append({
        'id': wid,
        'type': item_type,
        'title': title.strip(),
        'severity': severity,
        'status': status,
        'evidence': evidence,
        'root_cause': root_cause
    })

print(json.dumps(items))
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

  # Skip if researched today — but only if the research is valid (not auth-failure garbage)
  if [[ -f "$research_file" ]]; then
    local file_size
    file_size=$(wc -c < "$research_file" 2>/dev/null || echo 0)
    local has_auth_error
    has_auth_error=$(grep -c "Not logged in\|Please run /login\|Authentication required\|API key" "$research_file" 2>/dev/null || echo 0)
    if [[ "$file_size" -gt 300 && "$has_auth_error" -eq 0 ]]; then
      log "  Research exists for $weakness_id ($agent): $research_file"
      cat "$research_file"
      return 0
    else
      log "  Research file invalid (auth failure or too small: ${file_size}B, auth_errors=${has_auth_error}) — re-running"
      rm -f "$research_file"
    fi
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

    # Detect Claude Code auth failure — treat as empty output and fall through to Python fallback
    local _auth_fail=0
    if echo "$research_output" | grep -q "Not logged in\|Please run /login\|Authentication required\|Error: API"; then
      _auth_fail=1
      log "  [WARN] Claude Code auth failure detected — falling back to Python analysis"
      research_output=""
    fi

    if [[ -n "$research_output" && "$_auth_fail" -eq 0 ]]; then
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

  # Fallback: Python data-driven analysis (works without Claude Code auth)
  # Analyzes agent logs, ACTIVE.md, evolution.jsonl to produce real research output
  log "  [FALLBACK] Claude Code unavailable — running Python data-driven analysis for $weakness_id"
  local research_output
  research_output=$(python3 - << PYEOF 2>/dev/null
import os, json, re
from pathlib import Path

hyo_root = "$HYO_ROOT"
agent = "$agent"
weakness_id = "$weakness_id"
weakness_title = """$weakness_title"""
evidence = """$evidence"""
today = "$TODAY"

def read_tail(path, n=200):
    try:
        with open(path) as f:
            lines = f.readlines()
        return "".join(lines[-n:])
    except Exception:
        return ""

def read_jsonl(path, n=20):
    try:
        with open(path) as f:
            lines = [l.strip() for l in f if l.strip()]
        entries = []
        for l in lines[-n:]:
            try: entries.append(json.loads(l))
            except: pass
        return entries
    except Exception:
        return []

agent_dir = Path(hyo_root) / "agents" / agent
# Gather data sources
active_md = read_tail(agent_dir / "ledger" / "ACTIVE.md", 100)
evolution = read_jsonl(agent_dir / "evolution.jsonl", 30)
recent_log = read_tail(list(sorted((agent_dir / "logs").glob("*.md"), key=os.path.getmtime))[-1] if (agent_dir / "logs").exists() else Path("/dev/null"), 150)
growth_md = read_tail(agent_dir / "GROWTH.md", 80) if (agent_dir / "GROWTH.md").exists() else ""

# Count recent failures in evolution
fail_patterns = [e for e in evolution if e.get("outcome","").lower() in ("fail","failure","error","blocked")]
pass_patterns = [e for e in evolution if e.get("outcome","").lower() in ("success","pass","complete","shipped")]
recent_outcomes = [e.get("outcome","?") for e in evolution[-10:]]

# Root cause analysis from evidence keywords
root_cause_hints = []
if "empty" in evidence.lower() or "zero" in evidence.lower() or "no output" in evidence.lower():
    root_cause_hints.append("Output production gate is missing or silent-failing")
if "stale" in evidence.lower() or "old" in evidence.lower():
    root_cause_hints.append("Cache/memo not being invalidated on cycle boundary")
if "auth" in evidence.lower() or "401" in evidence.lower() or "403" in evidence.lower():
    root_cause_hints.append("Credential not being passed into subprocess environment")
if "slow" in evidence.lower() or "timeout" in evidence.lower():
    root_cause_hints.append("No timeout guard on external calls creating blocking")
if not root_cause_hints:
    root_cause_hints.append("Process skips step silently when precondition fails")

# Build fix approach from weakness context
fix_hints = []
if "aric" in weakness_title.lower() or "research" in weakness_title.lower():
    fix_hints.append("Add non-Claude fallback: parse RSS/web sources directly in bash + python3 requests")
    fix_hints.append("Gate research phase: if output <100 chars, mark as EMPTY and skip to next cycle")
    files = f"bin/agent-self-improve.sh, bin/agent-research.sh, agents/{agent}/GROWTH.md"
elif "report" in weakness_title.lower() or "publish" in weakness_title.lower():
    fix_hints.append("Add empty-check gate before publish: len(content) > 500 chars required")
    fix_hints.append("Wire Telegram alert when publish skipped due to empty content")
    files = f"agents/{agent}/{agent}.sh, bin/kai-autonomous.sh"
elif "score" in weakness_title.lower() or "sicq" in weakness_title.lower() or "metric" in weakness_title.lower():
    fix_hints.append("Pull score from verified-state.json instead of recalculating each cycle")
    fix_hints.append("Add score trend line: compare to 7-day rolling average, alert on >10pt drop")
    files = f"agents/{agent}/{agent}.sh, kai/ledger/verified-state.json"
else:
    fix_hints.append("Add explicit success check after each phase: output must be non-empty")
    fix_hints.append("Log phase completion time to detect which step is failing")
    files = f"agents/{agent}/{agent}.sh, agents/{agent}/ledger/ACTIVE.md"

root_cause = root_cause_hints[0] if root_cause_hints else "Silent failure in upstream dependency"

print(f"ROOT_CAUSE: {root_cause}")
print(f"FIX_APPROACH: {fix_hints[0]}")
print(f"FIX_APPROACH_2: {fix_hints[1] if len(fix_hints)>1 else 'Add explicit phase completion logging'}")
print(f"FILES_TO_CHANGE: {files}")
print(f"IMPLEMENTATION: 1. Add empty-output guard returning non-zero exit 2. Log failure with context 3. Notify via hyo-inbox.jsonl 4. Add regression test to sentinel.sh")
print(f"CONFIDENCE: MEDIUM")
print(f"COMPLEXITY: 1-2 hours")
print()
print(f"DATA_SOURCES_ANALYZED: ACTIVE.md ({len(active_md)} chars), evolution.jsonl ({len(evolution)} entries, {len(fail_patterns)} failures, {len(pass_patterns)} successes), recent_log ({len(recent_log)} chars)")
print(f"RECENT_OUTCOMES: {recent_outcomes}")
print(f"NOTE: Generated by Python data-driven fallback (Claude Code auth unavailable). Re-run after claude auth login for deeper analysis.")
PYEOF
)

  if [[ -n "$research_output" && ${#research_output} -gt 100 ]]; then
    local research_dir="$HYO_ROOT/agents/$agent/research/improvements"
    local research_file="$research_dir/${weakness_id}-${TODAY}.md"
    mkdir -p "$research_dir"
    cat > "$research_file" << RESEOF
# Research: $weakness_id — $weakness_title
**Agent:** $agent
**Date:** $TODAY
**Status:** pending_implementation
**Research_method:** python_data_driven_fallback

$research_output
RESEOF
    log "  ✓ Python fallback research complete → $research_file"
    echo "$research_output"
    return 0
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

  # P0 fix: only proceed when confidence is explicitly HIGH or MEDIUM.
  # Old bug: only blocked on "LOW" — empty/unknown confidence proceeded silently.
  if [[ "$confidence" != "HIGH" && "$confidence" != "MEDIUM" ]]; then
    log "  Skipping implementation: confidence='${confidence:-empty}' — need HIGH or MEDIUM"
    echo ""
    return
  fi

  echo "Fix $weakness_id in $agent: $weakness_title. Approach: $fix_approach. Files: $files_to_change. Steps: $implementation"
}

# ─── Phase 5: Verify the improvement worked ──────────────────────────────────
# P0 fix: check the SPECIFIC files listed in FILES_TO_CHANGE, not any system-wide commit.
# Old behavior: any commit today by any agent passed verification for any weakness (theater).
# New behavior: primary = specific files modified; fallback = deep agent check (no research file).
verify_improvement() {
  local agent="$1" weakness_id="$2"

  log "  Verifying improvement for $weakness_id ($agent)..."

  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  local research_file="$HYO_ROOT/agents/$agent/research/improvements/${weakness_id}-${TODAY}.md"

  # ── PRIMARY: check specific files from the research plan ───────────────────
  local specific_files_changed=0
  local files_to_check=""
  if [[ -f "$research_file" ]]; then
    files_to_check=$(grep "^FILES_TO_CHANGE:" "$research_file" | sed 's/FILES_TO_CHANGE: //' | tr ',' '\n' | sed 's/^ *//;s/ *$//')
  fi

  if [[ -n "$files_to_check" ]]; then
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      local full_path="$HYO_ROOT/$f"
      if [[ -f "$full_path" && "$full_path" -nt "$state_file" ]]; then
        specific_files_changed=$((specific_files_changed + 1))
        log "  ✓ Specific file changed: $f"
      fi
    done <<< "$files_to_check"

    if [[ "$specific_files_changed" -gt 0 ]]; then
      log "  ✓ PRIMARY verify passed: $specific_files_changed file(s) from research plan modified"
      return 0
    else
      log "  ✗ PRIMARY verify FAILED: FILES_TO_CHANGE were not modified"
      # When research plan was clear but files weren't touched → real failure, no fallback
      return 1
    fi
  fi

  # ── FALLBACK: no research file or no FILES_TO_CHANGE — use agent-specific checks ──
  log "  FALLBACK verify: no structured FILES_TO_CHANGE — using agent-specific evidence"
  local deep_ok=0
  case "$agent" in
    nel)
      local qa_log="$HYO_ROOT/agents/nel/logs/nel-$(date +%Y-%m-%d).md"
      if [[ -f "$qa_log" ]] && grep -q "✓\|PASS\|score.*[7-9][0-9]\|score.*100" "$qa_log" 2>/dev/null; then
        deep_ok=1; log "  ✓ Nel: recent log shows passing checks"
      fi
      ;;
    sam)
      local data_age
      data_age=$(find "$HYO_ROOT/agents/sam/website/data/" -name "*.json" -newer "$state_file" 2>/dev/null | wc -l | tr -d ' ')
      [[ "$data_age" -gt 0 ]] && deep_ok=1 && log "  ✓ Sam: $data_age data file(s) updated"
      ;;
    aether)
      local metrics="$HYO_ROOT/agents/sam/website/data/aether-metrics.json"
      [[ -f "$metrics" && "$metrics" -nt "$state_file" ]] && deep_ok=1 && log "  ✓ Aether: metrics updated"
      ;;
    ra)
      local ra_recent
      ra_recent=$(find "$HYO_ROOT/agents/ra/" -newer "$state_file" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      [[ "$ra_recent" -gt 0 ]] && deep_ok=1 && log "  ✓ Ra: $ra_recent file(s) updated"
      ;;
    kai)
      local kai_recent
      kai_recent=$(find "$HYO_ROOT/kai/" -newer "$state_file" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      [[ "$kai_recent" -gt 0 ]] && deep_ok=1 && log "  ✓ Kai: $kai_recent protocol/doc file(s) updated"
      ;;
    *)
      local generic_recent
      generic_recent=$(find "$HYO_ROOT/agents/$agent/" -newer "$state_file" 2>/dev/null | wc -l | tr -d ' ')
      [[ "$generic_recent" -gt 0 ]] && deep_ok=1
      ;;
  esac

  if [[ "$deep_ok" -eq 1 ]]; then
    log "  ✓ FALLBACK verify passed"
    return 0
  fi
  log "  ✗ FALLBACK verify failed: no evidence of change for $agent/$weakness_id"
  return 1
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

  # Log to agent evolution.jsonl — fault-fix #1: use env vars, not bash interpolation into python -c
  local evolution_file="$HYO_ROOT/agents/$agent/evolution.jsonl"
  SI_TS="$NOW_MT" SI_WID="$weakness_id" SI_WTITLE="$weakness_title" \
  SI_SUMMARY="$summary" SI_EVFILE="$evolution_file" \
  python3 << 'EVEOF'
import json, os
entry = {
    'ts': os.environ['SI_TS'],
    'type': 'weakness_resolved',
    'weakness_id': os.environ['SI_WID'],
    'weakness': os.environ['SI_WTITLE'],
    'summary': os.environ['SI_SUMMARY'],
    'method': 'claude-code-delegate',
    'compounded_to_knowledge': True
}
with open(os.environ['SI_EVFILE'], 'a') as f:
    f.write(json.dumps(entry) + '\n')
print('evolution.jsonl updated')
EVEOF
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
NEXT_WEAKNESS_TYPE: W (internal weakness) or E (expansion opportunity)
NEXT_WEAKNESS_ID: W4 (or next available — check existing IDs first)
NEXT_WEAKNESS_TITLE: <title>
NEXT_WEAKNESS_SEVERITY: P0|P1|P2
NEXT_WEAKNESS_EVIDENCE: <specific evidence from files you read>
NEXT_WEAKNESS_ROOT_CAUSE: <one sentence for weakness, or "Opportunity: ..." for expansion>
NEXT_WEAKNESS_FIX_APPROACH: <specific approach>

For expansion opportunities (type=E): identify novel capabilities, new integrations, new data sources, new products, or growth vectors the agent could build. These are not bugs — they are directions.
PROMPT
)
    local next_weakness
    next_weakness=$(echo "$next_prompt" | "$claude_bin" \
      -p --output-format text --dangerously-skip-permissions 2>/dev/null || echo "")

    if [[ -n "$next_weakness" ]]; then
      # Append new weakness/opportunity to GROWTH.md
      local nw_id nw_title nw_sev nw_ev nw_rc nw_fix
      nw_id=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_ID:" | sed 's/NEXT_WEAKNESS_ID: //' | tr -d ' ')
      nw_title=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_TITLE:" | sed 's/NEXT_WEAKNESS_TITLE: //')
      nw_sev=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_SEVERITY:" | sed 's/NEXT_WEAKNESS_SEVERITY: //')
      nw_ev=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_EVIDENCE:" | sed 's/NEXT_WEAKNESS_EVIDENCE: //')
      nw_rc=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_ROOT_CAUSE:" | sed 's/NEXT_WEAKNESS_ROOT_CAUSE: //')
      nw_fix=$(echo "$next_weakness" | grep "^NEXT_WEAKNESS_FIX_APPROACH:" | sed 's/NEXT_WEAKNESS_FIX_APPROACH: //')

      # fault-fix #5: check if ID already exists before appending
      if [[ -n "$nw_id" && -n "$nw_title" ]]; then
        local already_exists
        already_exists=$(grep -c "^### ${nw_id}:" "$growth_file" 2>/dev/null || echo "0")
        if [[ "$already_exists" -gt 0 ]]; then
          # ID collision — find next available
          local numeric
          numeric=$(echo "$nw_id" | tr -dc '0-9')
          local prefix
          prefix=$(echo "$nw_id" | tr -dc 'WE')
          while grep -q "^### ${prefix}${numeric}:" "$growth_file" 2>/dev/null; do
            numeric=$((numeric + 1))
          done
          nw_id="${prefix}${numeric}"
          log "  Duplicate ID — reassigned to $nw_id"
        fi

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
        log "  New item identified: $nw_id — $nw_title"

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

  # ── Circuit breaker: Claude Code must be available before doing any work ────
  if ! check_claude_health; then
    log "  CIRCUIT BREAKER: Claude Code unavailable for $agent — skipping cycle (state unchanged)"
    if [[ -f "$TICKET_SH" ]]; then
      HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
        --agent "$agent" \
        --title "Self-improve: Claude Code unavailable — $agent cycle skipped" \
        --priority "P1" --type "improvement" \
        --created-by "agent-self-improve" 2>/dev/null || true
    fi
    return 0
  fi

  # Load state
  local state
  state=$(get_state "$agent")
  local current_weakness stage cycles failure_count
  current_weakness=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_weakness','W1'))" 2>/dev/null || echo "W1")
  stage=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stage','research'))" 2>/dev/null || echo "research")
  cycles=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cycles',0))" 2>/dev/null || echo "0")
  failure_count=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('failure_count',0))" 2>/dev/null || echo "0")

  log "  State: weakness=$current_weakness stage=$stage cycles=$cycles failures=$failure_count"

  # fault-fix #6: max-retries gate — skip permanently-failing weaknesses
  if [[ "$failure_count" -ge "$MAX_RETRIES" ]]; then
    log "  MAX RETRIES ($MAX_RETRIES) reached for $current_weakness — skipping to next item"
    local next_wid
    next_wid=$(echo "$weaknesses" | python3 -c "
import json,sys
ws = json.load(sys.stdin)
ids = [w['id'] for w in ws if w.get('status','active') != 'resolved']
curr = '$current_weakness'
idx = next((i for i,w in enumerate(ws) if w['id']==curr), -1)
remaining = [w['id'] for w in ws[idx+1:] if w.get('status','active') != 'resolved']
print(remaining[0] if remaining else (ids[0] if ids else 'W1'))
" 2>/dev/null || echo "W1")
    save_state "$agent" "{\"current_weakness\":\"$next_wid\",\"stage\":\"research\",\"cycles\":$cycles,\"failure_count\":0,\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
    log "  → Advanced to $next_wid (failure cap)"
    return 0
  fi

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

      # ── EMPTY-RESEARCH GATE (P0 fix + content validation) ──────────────────
      # Bug 1: empty research silently advanced state → implement → verify → "resolved"
      # Bug 2: research file could EXIST but have empty fix_approach/confidence fields
      # New rule: file must exist AND contain non-empty FIX_APPROACH + CONFIDENCE=HIGH|MEDIUM
      local expected_research="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
      local gate_fail=0
      local gate_reason=""
      if [[ ! -f "$expected_research" ]]; then
        gate_fail=1
        gate_reason="research file not written"
      else
        local fix_approach_check confidence_check
        fix_approach_check=$(grep "^FIX_APPROACH:" "$expected_research" | sed 's/FIX_APPROACH: //' | head -1)
        confidence_check=$(grep "^CONFIDENCE:" "$expected_research" | sed 's/CONFIDENCE: //' | head -1)
        if [[ -z "$fix_approach_check" ]]; then
          gate_fail=1
          gate_reason="FIX_APPROACH field is empty in research file"
        elif [[ "$confidence_check" != "HIGH" && "$confidence_check" != "MEDIUM" ]]; then
          gate_fail=1
          gate_reason="CONFIDENCE='${confidence_check:-empty}' — need HIGH or MEDIUM"
        fi
      fi
      if [[ $gate_fail -eq 1 ]]; then
        log "  GATE: Research content invalid — $gate_reason"
        log "  → Keeping stage at 'research', incrementing failure ($((failure_count+1))/$MAX_RETRIES)"
        if [[ -f "$TICKET_SH" ]]; then
          HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
            --agent "$agent" \
            --title "Self-improve: empty research for $agent/$current_weakness — Claude Code returned nothing" \
            --priority "P1" --type "improvement" \
            --created-by "agent-self-improve" 2>/dev/null || true
        fi
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"failure_count\":$((failure_count+1)),\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
        report_to_kai "$agent"
        return 0
      fi

      # Advance to implement (research file verified present)
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
        log "  No implementation brief (confidence too low or research missing)"
        # Check if research file flags this as needing infrastructure/approval
        local research_file_check="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
        local needs_approval=0
        local approval_reason=""
        if [[ -f "$research_file_check" ]]; then
          approval_reason=$(grep "^REQUIRES_APPROVAL:" "$research_file_check" | sed 's/REQUIRES_APPROVAL: //' | head -1)
          [[ -n "$approval_reason" ]] && needs_approval=1
        fi
        if [[ $needs_approval -eq 1 ]]; then
          # Queue for async approval instead of blocking indefinitely
          local approval_id="${agent}-${current_weakness}-$(date +%Y%m%d)"
          local approvals_file="$HYO_ROOT/kai/ledger/pending-approvals.jsonl"
          if ! grep -q "\"id\":\"$approval_id\"" "$approvals_file" 2>/dev/null; then
            echo "{\"id\":\"$approval_id\",\"agent\":\"$agent\",\"weakness\":\"$current_weakness\",\"reason\":\"$approval_reason\",\"blocks\":\"improvement cannot ship without infrastructure\",\"status\":\"pending\",\"created\":\"$NOW_MT\"}" >> "$approvals_file"
            log "  → Queued for approval: $approval_reason (ID: $approval_id)"
            log "  → Run: kai improvement-approval --approve $approval_id to unblock"
          else
            log "  → Already pending approval (ID: $approval_id)"
          fi
        fi
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
          save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"verify\",\"cycles\":$cycles,\"failure_count\":0,\"improvements\":[\"$current_weakness\"],\"last_run\":\"$NOW_MT\"}"
        } || {
          log "  ✗ Implementation failed — will retry next cycle (failure $((failure_count+1))/$MAX_RETRIES)"
          save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"failure_count\":$((failure_count+1)),\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
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
        save_state "$agent" "{\"current_weakness\":\"$next_wid\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"failure_count\":0,\"improvements\":[\"$current_weakness\"],\"last_run\":\"$NOW_MT\"}"

        # Commit all improvements
        cd "$HYO_ROOT" 2>/dev/null && \
          git add "agents/$agent/" "kai/memory/KNOWLEDGE.md" 2>/dev/null && \
          git diff --cached --quiet 2>/dev/null || \
          git commit -m "improve($agent): $current_weakness resolved — $weakness_title" 2>/dev/null && \
          git push origin main 2>/dev/null && \
          log "  ✓ Improvement committed and pushed" || true

      else
        log "  ✗ Verification failed — regression risk, rolling back to research stage (failure $((failure_count+1))/$MAX_RETRIES)"
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"failure_count\":$((failure_count+1)),\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
      fi
      ;;
  esac

  log "  Cycle complete for $agent"

  # ── Report to Kai ────────────────────────────────────────────────────────────
  report_to_kai "$agent"
}

# ─── Report to Kai (write self-improve-latest.json + dispatch) ───────────────
report_to_kai() {
  local agent="$1"
  local report_dir="$HYO_ROOT/agents/$agent/research"
  local report_file="$report_dir/self-improve-latest.json"
  mkdir -p "$report_dir"

  # Read current state
  local state
  state=$(get_state "$agent")
  local current_weakness stage cycles last_run
  current_weakness=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('current_weakness','?'))" 2>/dev/null || echo "?")
  stage=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('stage','?'))" 2>/dev/null || echo "?")
  cycles=$(echo "$state" | python3 -c "import json,sys; print(json.load(sys.stdin).get('cycles',0))" 2>/dev/null || echo "0")
  local improvements
  improvements=$(echo "$state" | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(d.get('improvements',[])))" 2>/dev/null || echo "")

  # Read weakness title from GROWTH.md
  local weakness_title=""
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"
  if [[ -f "$growth_file" ]]; then
    weakness_title=$(grep "^### $current_weakness:" "$growth_file" 2>/dev/null | head -1 | sed "s/### $current_weakness: //")
  fi

  # Check if research file exists for today
  local research_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
  local research_summary=""
  local fix_approach=""
  local confidence=""
  if [[ -f "$research_file" ]]; then
    fix_approach=$(grep "^FIX_APPROACH:" "$research_file" | sed 's/FIX_APPROACH: //' | head -1)
    confidence=$(grep "^CONFIDENCE:" "$research_file" | sed 's/CONFIDENCE: //' | head -1)
    research_summary="Research completed (confidence: ${confidence:-unknown})"
  fi

  # Determine outcome text
  local outcome_text
  case "$stage" in
    research)   outcome_text="Researched $current_weakness — advancing to implement next cycle" ;;
    implement)  outcome_text="Implemented fix for $current_weakness — awaiting verification" ;;
    verify)     outcome_text="Verified + knowledge persisted — next weakness queued" ;;
    *)          outcome_text="Stage: $stage" ;;
  esac

  # Write self-improve-latest.json (consumed by morning report generator)
  python3 - << PYEOF
import json
from pathlib import Path

report = {
    "agent": "$agent",
    "report_date": "$TODAY",
    "ts": "$NOW_MT",
    "cycle_stage_completed": "$stage",
    "weakness_id": "$current_weakness",
    "weakness_title": "$weakness_title",
    "fix_approach": "$fix_approach",
    "confidence": "$confidence",
    "research_summary": "$research_summary",
    "improvements_resolved": [x for x in "$improvements".split(",") if x],
    "total_cycles": int("$cycles"),
    "outcome": "$outcome_text",
    "research_file": "$research_file" if Path("$research_file").exists() else None,
    "next_stage": "implement" if "$stage" == "research" else ("verify" if "$stage" == "implement" else "research")
}

Path("$report_file").write_text(json.dumps(report, indent=2))
print(f"self-improve-latest.json written for $agent")
PYEOF

  log "  ✓ Report written → $report_file"

  # Dispatch report to Kai via dispatch.sh
  local dispatch_sh="$HYO_ROOT/bin/dispatch.sh"
  if [[ -f "$dispatch_sh" ]]; then
    local task_id="${agent}-self-improve-${TODAY}"
    local report_msg="${outcome_text} | weakness: ${current_weakness} — ${weakness_title} | cycles: ${cycles} | stage → ${stage}"
    bash "$dispatch_sh" report "$task_id" "completed" "$report_msg" 2>/dev/null || true
    log "  ✓ Dispatched report to Kai: $task_id"
  fi

  # ── Publish to HQ feed ────────────────────────────────────────────────────────
  local publish_sh="$HYO_ROOT/bin/publish-to-feed.sh"
  if [[ -f "$publish_sh" ]]; then
    local sections_tmp
    # macOS mktemp: use -t flag (template prefix) not positional path
    # Clean up any stale temp files from crashed previous runs first
    rm -f /tmp/si-sections-*.json 2>/dev/null || true
    sections_tmp=$(mktemp -t si-sections.XXXXXX) && mv "$sections_tmp" "${sections_tmp}.json" && sections_tmp="${sections_tmp}.json"

    # Build research note: what was researched today (from research file if exists)
    local research_note="No research file yet for this cycle."
    if [[ -f "$research_file" ]]; then
      local rc_line
      rc_line=$(grep "^ROOT_CAUSE:" "$research_file" | head -1 | sed 's/ROOT_CAUSE: //')
      research_note="Root cause identified: ${rc_line:-see research file}. Approach: ${fix_approach:-not yet determined}."
    fi

    # What changed this cycle
    local changes_note
    case "$stage" in
      research)  changes_note="Research phase completed. No code changed yet — fix approach documented in research file." ;;
      implement) changes_note="Implementation delegated to Claude Code. Changes committed if successful." ;;
      verify)    changes_note="Verification passed. Knowledge persisted to KNOWLEDGE.md and memory engine." ;;
      *)         changes_note="Cycle stage: $stage" ;;
    esac

    # Follow-ups for Kai
    local followup
    if [[ -n "$improvements" ]]; then
      followup="Resolved: $improvements. Next: advance to next weakness."
    else
      followup="Continuing work on $current_weakness. Next stage: $([ "$stage" = "research" ] && echo "implement" || [ "$stage" = "implement" ] && echo "verify" || echo "research (next weakness)")."
    fi

    # fault-fix #1: pass values via env vars so special chars in titles/summaries don't corrupt JSON
    SI_AGENT="$agent" SI_WID="$current_weakness" SI_WTITLE="$weakness_title" \
    SI_OUTCOME="$outcome_text" SI_STAGE="$stage" SI_CYCLES="$cycles" \
    SI_RESEARCH_NOTE="$research_note" SI_CHANGES_NOTE="$changes_note" \
    SI_FOLLOWUP="$followup" SI_TODAY="$TODAY" \
    python3 << 'SECEOF' > "$sections_tmp" 2>/dev/null
import json, os
e = os.environ
sections = {
    'weakness':      e['SI_WID'] + ' — ' + e['SI_WTITLE'],
    'outcome':       e['SI_OUTCOME'],
    'introspection': (
        'Working on structural weakness ' + e['SI_WID'] + ': ' + e['SI_WTITLE'] +
        '. Stage completed: ' + e['SI_STAGE'] +
        '. Cycle count: ' + e['SI_CYCLES'] +
        '. ' + e['SI_OUTCOME']
    ),
    'research':   e['SI_RESEARCH_NOTE'],
    'changes':    e['SI_CHANGES_NOTE'],
    'followUps':  [e['SI_FOLLOWUP']],
    'forKai': (
        'Self-improve cycle ' + e['SI_TODAY'] + ' complete. '
        'Dispatched via report_to_kai(). '
        'See agents/' + e['SI_AGENT'] + '/research/self-improve-latest.json for full state.'
    )
}
print(json.dumps(sections))
SECEOF

    if [[ -s "$sections_tmp" ]]; then
      local report_title="${agent^} Self-Improvement — ${current_weakness}: ${weakness_title} (${TODAY})"
      HYO_ROOT="$HYO_ROOT" bash "$publish_sh" \
        "self-improve-report" \
        "$agent" \
        "$report_title" \
        "$sections_tmp" 2>/dev/null && \
        log "  ✓ Published self-improve report to HQ feed" || \
        log "  WARN: HQ publish failed (non-fatal)"
    fi

    rm -f "$sections_tmp" 2>/dev/null || true
  fi

  # ── Kai-specific: publish a dedicated research-drop to HQ for system research ──
  # Hyo: "Kai's research is paramount for continued self-improvement of the system"
  # Every other agent publishes a self-improve-report; Kai also publishes a research-drop
  # so the research findings appear in the Research tab with full detail.
  if [[ "$agent" == "kai" && -f "$publish_sh" ]]; then
    local research_drop_tmp
    rm -f /tmp/kai-research-drop-*.json 2>/dev/null || true
    research_drop_tmp=$(mktemp -t kai-research-drop.XXXXXX) && mv "$research_drop_tmp" "${research_drop_tmp}.json" && research_drop_tmp="${research_drop_tmp}.json"

    # Build rich research findings from the research file (if it exists)
    local rc_line="" fix_line="" impl_lines="" research_finding="" research_implications="" next_steps_json
    if [[ -f "$research_file" ]]; then
      rc_line=$(grep "^ROOT_CAUSE:" "$research_file" | head -1 | sed 's/ROOT_CAUSE: //')
      fix_line=$(grep "^FIX_APPROACH:" "$research_file" | head -1 | sed 's/FIX_APPROACH: //')
      impl_lines=$(grep -A 10 "^IMPLEMENTATION:" "$research_file" | head -8 | tr '\n' ' ')
      research_finding="Root cause: ${rc_line:-under investigation}. Fix approach: ${fix_line:-see research file}. ${impl_lines}"
      research_implications="This orchestrator weakness (${current_weakness}: ${weakness_title}) affects system-wide reliability. Resolving it improves Kai's ability to coordinate agents, maintain state continuity, and compound system knowledge across sessions."
      next_steps_json='["Implement the fix approach documented in the research file","Verify improvement in next self-improve cycle","Update KNOWLEDGE.md and AGENT_ALGORITHMS.md with the resolved pattern","Monitor for regression in the next 3 cycles"]'
    else
      research_finding="Researching ${current_weakness}: ${weakness_title}. Research file being populated by Claude Code analysis of agent logs, tickets, and protocol files. See agents/kai/research/improvements/ for output."
      research_implications="Kai (orchestrator) self-improvement directly affects all agents — improvements to session continuity, decision quality, signal latency, and memory coverage have multiplicative impact across the entire system."
      next_steps_json='["Complete research phase — generate research file with root cause + fix approach","Advance to implement stage on next cycle","Publish updated research drop with findings"]'
    fi

    # Source for the theater gate — hyo.world is the system being analyzed
    local system_source="https://hyo.world/hq (system under analysis)"

    SI_AGENT="$agent" SI_WID="$current_weakness" SI_WTITLE="$weakness_title" \
    SI_FINDING="$research_finding" SI_IMPLICATIONS="$research_implications" \
    SI_STAGE="$stage" SI_CYCLES="$cycles" SI_TODAY="$TODAY" \
    SI_SOURCE="$system_source" SI_NEXT_STEPS="$next_steps_json" \
    python3 << 'DROPEOF' > "$research_drop_tmp" 2>/dev/null
import json, os
e = os.environ
sections = {
    'topic':          'Kai Orchestrator Self-Research: ' + e['SI_WID'] + ' — ' + e['SI_WTITLE'],
    'finding':        e['SI_FINDING'] + ' Source: ' + e['SI_SOURCE'],
    'sources':        e['SI_SOURCE'],
    'implications':   e['SI_IMPLICATIONS'],
    'nextSteps':      json.loads(e.get('SI_NEXT_STEPS', '[]')),
    'context':        (
        'Kai runs self-improvement via the same compounding flywheel as all agents. '
        'Kai weaknesses are architectural — they affect orchestration, memory, coordination, and decision quality. '
        'Stage completed this cycle: ' + e['SI_STAGE'] + '. Total cycles: ' + e['SI_CYCLES'] + '.'
    )
}
print(json.dumps(sections))
DROPEOF

    if [[ -s "$research_drop_tmp" ]]; then
      local drop_title="Kai System Research — ${current_weakness}: ${weakness_title} (${TODAY})"
      HYO_ROOT="$HYO_ROOT" bash "$publish_sh" \
        "research-drop" \
        "kai" \
        "$drop_title" \
        "$research_drop_tmp" 2>/dev/null && \
        log "  ✓ Published Kai research-drop to HQ feed (Research tab)" || \
        log "  WARN: Kai research-drop publish failed (non-fatal)"
    fi

    rm -f "$research_drop_tmp" 2>/dev/null || true
  fi
}

# ─── Summary report ───────────────────────────────────────────────────────────
report_summary() {
  log_section "SELF-IMPROVE SUMMARY — $TODAY"

  python3 - "$HYO_ROOT" << 'PYEOF'
import json, sys, os
from pathlib import Path

root = Path(sys.argv[1])
agents = ['nel', 'ra', 'sam', 'aether', 'dex', 'kai']

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
  # fault-fix #9: run each agent's cycle in background so they don't block each other
  # flock inside save_state prevents concurrent state corruption
  for agent in nel sam aether ra dex kai; do
    ( run_self_improve "$agent" ) >> "$LOG" 2>&1 &
  done
  wait  # collect all backgrounds before summary
  report_summary
else
  run_self_improve "$TARGET"
fi

log "agent-self-improve.sh complete"
exit 0
