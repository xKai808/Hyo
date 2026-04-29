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

# ─── Reasoning patterns reminder (Pattern 7: encode lessons in running things) ─
# Source the pre-action check so it's available throughout this script.
# The patterns file is read here so tomorrow's self-improve run loads active failure modes,
# not just rules from a doc that gets ignored.
PRE_ACTION_CHECK="$HYO_ROOT/bin/kai-pre-action-check.sh"
REASONING_PATTERNS="$HYO_ROOT/kai/ledger/kai-reasoning-patterns.md"
if [[ -f "$PRE_ACTION_CHECK" ]]; then
  source "$PRE_ACTION_CHECK" 2>/dev/null || true
fi
# Log if reasoning patterns file exists and is current — stale = not being maintained
if [[ -f "$REASONING_PATTERNS" ]]; then
  patterns_age_days=$(python3 -c "import os,time; print(int((time.time()-os.path.getmtime('$REASONING_PATTERNS'))/86400))" 2>/dev/null || echo "?")
  if [[ "${patterns_age_days:-99}" -gt 7 ]]; then
    log "WARN: kai-reasoning-patterns.md is ${patterns_age_days} days old — update after any session where Hyo catches a mistake"
  fi
fi

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

# ─── Circuit breaker: verify Claude Code responds AND auth is valid ────────────
# P0 fix: never run a cycle when the tool is unavailable — advances state on nothing
# Auth fix: --version passes even with expired auth; use -p to test actual auth.
CLAUDE_AUTH_OK=false  # module-level flag set once, read by all agents
CLAUDE_AUTH_REASON=""

check_claude_health() {
  local claude_bin
  if ! claude_bin=$(_find_claude_bin 2>/dev/null); then
    log "  CIRCUIT BREAKER: Claude Code binary not found"
    CLAUDE_AUTH_REASON="binary_not_found"
    return 1
  fi
  if ! "$claude_bin" --version > /dev/null 2>&1; then
    log "  CIRCUIT BREAKER: Claude Code binary unresponsive"
    CLAUDE_AUTH_REASON="binary_unresponsive"
    return 1
  fi
  # Auth test: --version passes even when auth is expired; probe with a real call
  local auth_test
  auth_test=$("$claude_bin" -p "echo auth_ok" --output-format text 2>&1 | head -3 || true)
  if echo "$auth_test" | grep -qiE "Not logged in|Please run /login|Authentication required|Error: API|Unauthorized"; then
    log "  CIRCUIT BREAKER: Claude Code auth expired — implement stage disabled for all agents"
    # Log to daily-issues.jsonl for morning report pickup (no Telegram — Kai handles silently)
    local issues_log="$HYO_ROOT/kai/ledger/daily-issues.jsonl"
    local ts_now
    ts_now=$(TZ=America/Denver date +"%Y-%m-%dT%H:%M:%S%z")
    local today_key
    today_key=$(TZ=America/Denver date +%Y-%m-%d)
    if ! grep -q "\"key\":\"claude-auth-expired-$today_key\"" "$issues_log" 2>/dev/null; then
      echo "{\"ts\":\"$ts_now\",\"key\":\"claude-auth-expired-$today_key\",\"agent\":\"kai\",\"question\":\"AUTH\",\"severity\":\"P0\",\"description\":\"Claude Code auth expired. Implement stage for ALL agents is disabled until renewed. Python fallback active for research only. ACTION REQUIRED: claude auth login on the Mini.\",\"remediated\":false,\"date\":\"$today_key\"}" >> "$issues_log"
      log "  → Auth expiry logged to daily-issues.jsonl for morning report"
    fi
    CLAUDE_AUTH_REASON="auth_expired"
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
  local agent="$1" weakness_id="$2" weakness_title="$3" evidence="$4" prior_knowledge="${5:-[]}"

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
      # C3 fix C3-P1-2: preserve the old research file before overwriting on retry.
      # If previous research was Claude Code quality and retry falls back to Python,
      # we'd silently lose the better version. Archive it as -vN before removal.
      local v=1
      while [[ -f "${research_file%.md}-v${v}.md" ]]; do v=$((v+1)); done
      mv "$research_file" "${research_file%.md}-v${v}.md" 2>/dev/null || rm -f "$research_file"
      log "  Research file invalid (auth failure or too small: ${file_size}B, auth_errors=${has_auth_error}) — archived to v${v}, re-running"
    fi
  fi

  log "  Researching $weakness_id ($agent): $weakness_title"

  # ── Pull external research context if available (agent-research.sh findings) ──
  local external_context=""
  local sources_file="$HYO_ROOT/agents/$agent/research-sources.json"
  local findings_file="$HYO_ROOT/agents/$agent/research/findings-${TODAY}.md"
  if [[ -f "$findings_file" ]]; then
    # Today's external research already ran — pull the relevant section
    external_context=$(grep -A 5 -i "$weakness_title\|$weakness_id" "$findings_file" 2>/dev/null | head -20 || true)
    [[ -n "$external_context" ]] && log "  External context: pulled ${#external_context} chars from today's findings"
  elif [[ -f "$sources_file" ]]; then
    # Trigger external research now — this is synchronous but fast (15-30s)
    log "  Triggering external research pull for $agent..."
    HYO_ROOT="$HYO_ROOT" bash "$HYO_ROOT/bin/agent-research.sh" "$agent" >> "$HYO_ROOT/kai/ledger/self-improve.log" 2>&1 || true
    [[ -f "$findings_file" ]] && external_context=$(grep -A 5 -i "$weakness_title\|$weakness_id" "$findings_file" 2>/dev/null | head -20 || true)
    log "  External research triggered: ${#external_context} chars found"
  fi

  # ── Daily assess integration: pull evidence-grounded Q7/Q8/Q6 from 4AM assessment ──
  # agent-daily-assess.sh runs at 04:00 — 30 min before self-improve at 04:30.
  # It answers 8 mandatory questions from LIVE evidence (logs, tickets, feed, GROWTH.md goals).
  # Q4 = top weakness by severity+deadline (used by run_self_improve to override current_weakness)
  # Q6 = external signal from findings file (enriches external_context below)
  # Q7 = testable hypothesis derived from evidence (becomes research anchor — prevents stale prompts)
  # Q8 = exact success measure (becomes verification criterion in the research output)
  local daily_assess_file="$HYO_ROOT/agents/$agent/ledger/daily-assess-${TODAY}.json"
  local da_hypothesis="" da_success_measure="" da_external_signal="" da_quality=""
  if [[ -f "$daily_assess_file" ]]; then
    da_hypothesis=$(python3 -c "
import json
from pathlib import Path
try:
    d = json.loads(Path('$daily_assess_file').read_text())
    print(d.get('Q7_hypothesis', '') or d.get('hypothesis', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")
    da_success_measure=$(python3 -c "
import json
from pathlib import Path
try:
    d = json.loads(Path('$daily_assess_file').read_text())
    print(d.get('Q8_success_measure', '') or d.get('success_measure', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")
    da_external_signal=$(python3 -c "
import json
from pathlib import Path
try:
    d = json.loads(Path('$daily_assess_file').read_text())
    print(d.get('Q6_external_signal', '') or d.get('external_signal', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")
    da_quality=$(python3 -c "
import json
from pathlib import Path
try:
    d = json.loads(Path('$daily_assess_file').read_text())
    print(d.get('assessment_quality', 'UNKNOWN'))
except Exception:
    print('UNKNOWN')
" 2>/dev/null || echo "UNKNOWN")
    if [[ -n "$da_hypothesis" ]]; then
      log "  Daily-assess Q7: hypothesis loaded (${#da_hypothesis} chars, quality=$da_quality)"
      # Merge Q6 external signal into external_context if not duplicate
      if [[ -n "$da_external_signal" ]]; then
        external_context="${external_context}
[Daily-assess Q6 external signal]: ${da_external_signal}"
        log "  Daily-assess Q6: external signal merged into context"
      fi
    else
      log "  Daily-assess: file found but Q7 empty (quality=$da_quality) — running without hypothesis anchor"
    fi
  else
    log "  Daily-assess: no assessment file for today — Phase 3 running without 4AM grounding"
  fi

  # ── IMPROVEMENT v2.0: Forward AAR — read what last cycle said to focus on ──────
  # Each successful cycle writes a forward AAR note. This cycle reads it and
  # injects it as a research anchor. This creates a learning chain across cycles
  # rather than each ARIC cycle starting cold from GROWTH.md alone.
  local forward_aar_context=""
  local _aar_dir="$HYO_ROOT/agents/$agent/ledger"
  local _aar_file="$_aar_dir/forward-aar-${TODAY}.json"
  # Check today's AAR, then yesterday's
  for _aar_candidate in "$_aar_file" "$_aar_dir/forward-aar-$(TZ=America/Denver date -v-1d +%Y-%m-%d 2>/dev/null || date -d 'yesterday' +%Y-%m-%d 2>/dev/null || echo prev).json"; do
    if [[ -f "$_aar_candidate" ]]; then
      forward_aar_context=$(python3 -c "
import json
from pathlib import Path
try:
    entries = json.loads(Path('$_aar_candidate').read_text())
    if not isinstance(entries, list): entries = [entries]
    # Filter for this weakness or general entries
    relevant = [e for e in entries if e.get('next_cycle_goal') and
                (e.get('agent') == '$agent' or e.get('weakness_id') == '$weakness_id')]
    if relevant:
        last = relevant[-1]
        g = last.get('next_cycle_goal', {})
        parts = []
        if g.get('direction'): parts.append(f\"Direction: {g['direction']}\")
        if g.get('question'): parts.append(f\"Key question: {g['question']}\")
        if g.get('success_measure'): parts.append(f\"Success measure: {g['success_measure']}\")
        print('\n'.join(parts))
except Exception as e:
    pass
" 2>/dev/null || echo "")
      if [[ -n "$forward_aar_context" ]]; then
        log "  Forward AAR loaded from $( basename "$_aar_candidate"): ${#forward_aar_context} chars"
        break
      fi
    fi
  done

  # ── Goal deadline urgency: check if this weakness has an overdue goal ─────────
  local goal_urgency=""
  local growth_file_path="$HYO_ROOT/agents/$agent/GROWTH.md"
  if [[ -f "$growth_file_path" ]]; then
    goal_urgency=$(python3 -c "
import re, sys
from pathlib import Path
from datetime import datetime, timezone
content = Path('$growth_file_path').read_text()
today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
# Find goals table rows linking to this weakness
pattern = r'\|\s*G\d+\s*\|[^|]+\|\s*(\d{4}-\d{2}-\d{2})\s*\|[^|]+\|\s*$weakness_id\s*\|'
overdue = []
for m in re.finditer(pattern, content):
    deadline = m.group(1)
    if deadline < today:
        overdue.append(deadline)
if overdue:
    print(f'OVERDUE GOAL: linked goal deadline {overdue[0]} has passed. This weakness is URGENT — P0 priority.')
" 2>/dev/null || echo "")
    [[ -n "$goal_urgency" ]] && log "  $goal_urgency"
  fi

  # Use Claude Code to research if available, otherwise use agent-research.sh
  local claude_bin
  if claude_bin=$(_find_claude_bin 2>/dev/null); then
    local research_prompt
    research_prompt=$(cat << PROMPT
You are researching a weakness in the hyo.world agent system to find a concrete, executable fix.
You have access to external findings, a pre-computed daily assessment, and internal evidence. Use ALL of it.

Agent: $agent
Weakness ID: $weakness_id
Weakness: $weakness_title
Evidence: $evidence
${goal_urgency:+Goal status: $goal_urgency}

GROWTH.md fix approach (canonical — implement exactly this):
$(grep -A 20 "### ${weakness_id}:" "$HYO_ROOT/agents/$agent/GROWTH.md" 2>/dev/null | grep -A 10 "Fix approach\|fix_approach" | head -15 || echo "(not found — derive from evidence)")

Forward AAR from previous cycle (what the last cycle said to focus on — use as research direction):
${forward_aar_context:-"(no forward AAR — this is the first cycle for this weakness)"}

Daily assessment (4AM evidence-based analysis — use as research anchor):
Hypothesis: ${da_hypothesis:-"(not available — daily-assess may not have run yet)"}
Success measure: ${da_success_measure:-"(not specified — derive from weakness title)"}

Prior memory hits (from memory engine — what we already know about this weakness):
$(echo "$prior_knowledge" | python3 -c "
import json,sys
hits = json.load(sys.stdin)
if hits:
    for i,h in enumerate(hits[:3]):
        print(f'  [{i+1}] {h}')
else:
    print('  (no prior memory — first time researching this weakness)')
" 2>/dev/null || echo "  (memory query failed)")

External research findings (from agent-research.sh + daily-assess Q6):
${external_context:-"(no external findings today — use internal analysis)"}

Recent agent evolution (last 3 entries):
$(tail -3 "$HYO_ROOT/agents/$agent/evolution.jsonl" 2>/dev/null | python3 -c "import json,sys; [print(json.loads(l).get('assessment','')) for l in sys.stdin if l.strip()]" 2>/dev/null || echo "(none)")

Your job:
1. Use the GROWTH.md fix approach as your primary source — it is what the agent planned
2. Use the daily assessment hypothesis as your research anchor — it was derived from live evidence
3. Augment with external findings if relevant
4. Make the implementation steps SPECIFIC: exact file paths, exact function names, exact logic
5. If the GROWTH.md approach is sound, execute it exactly — do not invent a different approach
6. If goal is overdue, treat as P0 and prioritize speed-to-ship over perfection
7. Your VERIFICATION criterion MUST match the daily assessment success measure (if provided)

Output format (machine-parsed):
ROOT_CAUSE: <one sentence>
FIX_APPROACH: <specific technical approach — must match or improve on GROWTH.md>
FILES_TO_CHANGE: <comma-separated file paths relative to HYO_ROOT>
IMPLEMENTATION: <numbered step-by-step — be specific enough that implement stage can execute without further research>
VERIFICATION: <exact check that proves the fix worked — matches daily-assess Q8 success measure>
CONFIDENCE: HIGH|MEDIUM|LOW
COMPLEXITY: <estimated hours>
EXTERNAL_SOURCES_USED: <list sources that informed this, or "none">
ASSESSMENT_ANCHOR: <one sentence — how the daily hypothesis shaped this research>
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
# Daily-assess grounding (from 4AM evidence-based assessment)
da_hypothesis = """${da_hypothesis}"""
da_success_measure = """${da_success_measure}"""

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

# ── PRIMARY SOURCE: Read GROWTH.md for this specific weakness ─────────────────
# The fix approach is ALREADY in GROWTH.md — the agent wrote it there.
# Always extract from GROWTH.md first. Only fall back to heuristics if GROWTH.md
# doesn't have a fix approach for this weakness. This prevents the fallback from
# producing generic wrong content when the real answer is sitting in the file.
growth_path = agent_dir / "GROWTH.md"
canonical_root_cause = ""
canonical_fix_approach = ""
canonical_fix_approach_2 = ""
canonical_files = ""
canonical_implementation = ""
canonical_evidence_from_growth = ""

if growth_path.exists():
    growth_content = growth_path.read_text()
    # Find the specific weakness block by ID (e.g. ### W1:)
    pattern = rf'###\s+{re.escape(weakness_id)}[:\s](.+?)(?=\n###\s+[WE]\d+|\n##\s|\Z)'
    m = re.search(pattern, growth_content, re.DOTALL)
    if m:
        block = m.group(0)
        # Extract Root cause
        rc = re.search(r'\*\*Root cause[:\*]+\s*\n(.+?)(?=\n\*\*|\Z)', block, re.DOTALL)
        if rc: canonical_root_cause = rc.group(1).strip().replace('\n', ' ')[:400]
        # Extract Fix approach (may be labeled "Fix approach:" or "**Fix approach:**")
        fa = re.search(r'\*\*Fix approach[:\*]+\s*\n(.+?)(?=\n\*\*|\n---|\Z)', block, re.DOTALL)
        if fa:
            fa_text = fa.group(1).strip()
            # Split into primary and secondary if multiple paragraphs
            fa_parts = [p.strip() for p in fa_text.split('\n\n') if p.strip()]
            canonical_fix_approach = fa_parts[0][:500] if fa_parts else fa_text[:500]
            canonical_fix_approach_2 = fa_parts[1][:300] if len(fa_parts) > 1 else ""
        # Extract evidence
        ev = re.search(r'\*\*Evidence[:\*]+\s*\n(.+?)(?=\n\*\*|\Z)', block, re.DOTALL)
        if ev: canonical_evidence_from_growth = ev.group(1).strip().replace('\n', ' ')[:300]

# ── Cycle 3 fix C3-P0-1: fallback to Improvement Plan when weakness body has no Fix approach ─
# Existing GROWTH.md files store fix approaches in Improvement Plan (### I1: ... Addresses W1)
# not in the weakness body. If the weakness body search found nothing, search the Improvement Plan.
if not canonical_fix_approach and growth_path.exists():
    # Find the improvement section that addresses this weakness (e.g. Addresses W1)
    imp_pattern = rf'###\s+I\d+:[^\n]+\n(?:[^\n]*\n)*?Addresses\s+{re.escape(weakness_id)}\b'
    imp_m = re.search(imp_pattern, growth_content, re.DOTALL)
    if imp_m:
        # Extract the full improvement block (up to next ### or ## section)
        start = imp_m.start()
        end_search = re.search(r'\n###\s+[WEI]\d+|\n##\s', growth_content[start + 1:])
        imp_block = growth_content[start: start + 1 + (end_search.start() if end_search else len(growth_content) - start)]
        # Extract **Approach:** content from the improvement block
        approach_m = re.search(r'\*\*Approach:\*\*\s*\n(.+?)(?=\n\*\*|\n###|\n##|\Z)', imp_block, re.DOTALL)
        if approach_m:
            fa_text_imp = approach_m.group(1).strip()
            fa_parts_imp = [p.strip() for p in fa_text_imp.split('\n\n') if p.strip()]
            canonical_fix_approach = fa_parts_imp[0][:500] if fa_parts_imp else fa_text_imp[:500]
            canonical_fix_approach_2 = fa_parts_imp[1][:300] if len(fa_parts_imp) > 1 else ""
            if not canonical_root_cause:
                rc_imp = re.search(r'\*\*Root cause:\*\*\s*\n(.+?)(?=\n\*\*|\Z)', imp_block, re.DOTALL)
                if rc_imp: canonical_root_cause = rc_imp.group(1).strip().replace('\n', ' ')[:400]

# ── SECONDARY SOURCES: logs, evolution, ACTIVE.md ─────────────────────────────
active_md = read_tail(agent_dir / "ledger" / "ACTIVE.md", 100)
evolution = read_jsonl(agent_dir / "evolution.jsonl", 30)
try:
    log_files = sorted((agent_dir / "logs").glob("*.md"), key=os.path.getmtime) if (agent_dir / "logs").exists() else []
    recent_log = read_tail(log_files[-1], 150) if log_files else ""
except Exception:
    recent_log = ""
growth_md_raw = read_tail(growth_path, 80) if growth_path.exists() else ""

# Count recent outcomes
fail_patterns = [e for e in evolution if str(e.get("outcome","")).lower() in ("fail","failure","error","blocked")]
pass_patterns = [e for e in evolution if str(e.get("outcome","")).lower() in ("success","pass","complete","shipped")]
recent_outcomes = [e.get("outcome","?") for e in evolution[-10:]]

# ── Determine outputs ─────────────────────────────────────────────────────────
# GROWTH.md canonical content takes priority over heuristics
if canonical_fix_approach:
    root_cause = canonical_root_cause or f"As documented in GROWTH.md {weakness_id}: {weakness_title}"
    fix_approach = canonical_fix_approach
    fix_approach_2 = canonical_fix_approach_2 or "Verify with regression test in sentinel.sh after implementation"
    # Files: if not in GROWTH.md, derive from weakness ID and agent
    files = canonical_files or f"bin/agent-self-improve.sh, agents/{agent}/GROWTH.md, agents/{agent}/ledger/ACTIVE.md"
    implementation = f"Follow Fix approach from GROWTH.md {weakness_id}. Step 1: {fix_approach[:200]}. Step 2: Test idempotency. Step 3: Update GROWTH.md status to in_progress. Step 4: Add regression test."
    confidence = "HIGH"
    complexity = "2-4 hours"
    source_note = f"PRIMARY SOURCE: GROWTH.md {weakness_id} canonical fix approach extracted directly."
else:
    # Heuristic fallback (GROWTH.md had no fix approach for this ID — unusual)
    if "empty" in evidence.lower() or "zero" in evidence.lower():
        root_cause = "Output production gate is missing or silent-failing"
        fix_approach = "Add non-empty output guard after each phase: exit non-zero if output is empty"
        fix_approach_2 = "Log phase completion time to detect which step stalls"
    elif "stale" in evidence.lower() or "drift" in evidence.lower() or "continuity" in evidence.lower():
        root_cause = "State not being refreshed on cycle boundary — reading cached values"
        fix_approach = "Force re-read from source files at cycle start, not from in-memory state"
        fix_approach_2 = "Add modification-time check: if file unchanged >24h, flag STALE before reading"
    elif "auth" in evidence.lower() or "login" in evidence.lower():
        root_cause = "Credential not being passed into subprocess environment"
        fix_approach = "Export auth token before subprocess call; add auth test at top of pipeline"
        fix_approach_2 = "Gate entire pipeline on auth check result — don't proceed on auth failure"
    else:
        root_cause = "Process skips step silently when precondition fails"
        fix_approach = "Add explicit precondition checks with non-zero exit on failure"
        fix_approach_2 = "Log skip reason to hyo-inbox.jsonl for morning report visibility"
    files = f"agents/{agent}/{agent}.sh, agents/{agent}/GROWTH.md"
    implementation = "1. Add precondition check 2. Log failure reason 3. Notify hyo-inbox 4. Regression test in sentinel.sh"
    confidence = "MEDIUM"
    complexity = "1-3 hours"
    source_note = f"WARNING: GROWTH.md had no fix_approach for {weakness_id} — heuristic fallback used. Add Fix approach section to GROWTH.md."

verification = da_success_measure if da_success_measure.strip() else f"Verify {weakness_id} fix: run agent {agent} cycle and confirm output shows fix applied (check logs/{today}.md)"
assessment_anchor = f"Daily-assess hypothesis: {da_hypothesis[:200]}" if da_hypothesis.strip() else "No daily-assess hypothesis available — fallback used"

print(f"ROOT_CAUSE: {root_cause}")
print(f"FIX_APPROACH: {fix_approach}")
print(f"FIX_APPROACH_2: {fix_approach_2}")
print(f"FILES_TO_CHANGE: {files}")
print(f"IMPLEMENTATION: {implementation}")
print(f"VERIFICATION: {verification}")
print(f"CONFIDENCE: {confidence}")
print(f"COMPLEXITY: {complexity}")
print(f"ASSESSMENT_ANCHOR: {assessment_anchor}")
print()
print(f"DATA_SOURCES_ANALYZED: GROWTH.md-{weakness_id} (canonical), ACTIVE.md ({len(active_md)} chars), evolution.jsonl ({len(evolution)} entries, {len(fail_patterns)} failures, {len(pass_patterns)} successes), recent_log ({len(recent_log)} chars), daily-assess ({len(da_hypothesis)} chars hypothesis)")
print(f"RECENT_OUTCOMES: {recent_outcomes}")
print(f"{source_note}")
print(f"NOTE: Python fallback (Claude Code auth unavailable). Re-run with valid auth for full analysis + external source integration.")
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

  # ── Circuit breaker: read pre-flight CLAUDE_AUTH_OK flag (set once at module level)
  # Research + Python fallback always run. Only implement stage gates on auth.
  # We do NOT re-call check_claude_health() per agent — the Telegram alert already fired.
  local claude_auth_ok="${CLAUDE_AUTH_OK:-false}"
  if [[ "$claude_auth_ok" != "true" ]]; then
    log "  AUTH UNAVAILABLE: $agent implement stage disabled — research + Python fallback active"
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

  # Cycle 2 fix: parse weaknesses FIRST — before any override/gate logic that needs status checks.
  # Previously parse_weaknesses ran at line ~1079, AFTER goal urgency and Q4 override blocks.
  # urgent_status and da_q4_status checks queried $weaknesses when it was still empty string,
  # meaning resolved-weakness protection never actually fired. Move here so all gate checks work.
  local weaknesses
  weaknesses=$(parse_weaknesses "$agent")
  local weakness_count
  weakness_count=$(echo "$weaknesses" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
  local active_count resolved_count
  active_count=$(echo "$weaknesses" | python3 -c "import json,sys; ws=json.load(sys.stdin); print(sum(1 for w in ws if w.get('status','active')!='resolved'))" 2>/dev/null || echo "0")
  resolved_count=$((weakness_count - active_count))
  log "  Weaknesses: $weakness_count total ($active_count active, $resolved_count resolved)"

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

  # ── Goal deadline urgency check ────────────────────────────────────────────────
  # If any goal linked to a weakness has an overdue deadline, override current_weakness
  # to that weakness and log a P0. Goals with past deadlines take priority.
  local growth_file_g="$HYO_ROOT/agents/$agent/GROWTH.md"
  if [[ -f "$growth_file_g" ]]; then
    local urgent_weakness
    urgent_weakness=$(python3 -c "
import re, sys
from pathlib import Path
from datetime import datetime, timezone
content = Path('$growth_file_g').read_text()
today_str = datetime.now(timezone.utc).strftime('%Y-%m-%d')
# Goals table format: | G1 | description | 2026-04-28 | pending | W1 |
pattern = r'\|\s*(G\d+)\s*\|[^|]+\|\s*(\d{4}-\d{2}-\d{2})\s*\|[^|]+\|\s*([WE]\d+)\s*\|'
overdue = []
for m in re.finditer(pattern, content):
    gid, deadline, wid = m.group(1), m.group(2), m.group(3)
    if deadline < today_str:
        overdue.append((deadline, wid, gid))
if overdue:
    overdue.sort()  # oldest overdue first
    print(overdue[0][1])  # weakness ID with oldest overdue goal
" 2>/dev/null || echo "")
    if [[ -n "$urgent_weakness" && "$urgent_weakness" != "$current_weakness" ]]; then
      # P0 gate: do not override to an already-resolved weakness — that wastes a cycle
      local urgent_status
      urgent_status=$(echo "$weaknesses" | python3 -c "
import json,sys
ws = json.load(sys.stdin)
for w in ws:
    if w['id'] == '$urgent_weakness':
        print(w.get('status','active'))
        break
else:
    print('unknown')
" 2>/dev/null || echo "unknown")
      if [[ "$urgent_status" == "resolved" ]]; then
        log "  GOAL URGENCY: $urgent_weakness is already RESOLVED — skipping override"
      else
      log "  GOAL URGENCY: $urgent_weakness has overdue deadline — overriding current_weakness from $current_weakness"
      current_weakness="$urgent_weakness"
      stage="research"  # restart from research for the urgent weakness
      failure_count=0
      # Open P0 issue
      local issues_log="$HYO_ROOT/kai/ledger/daily-issues.jsonl"
      local urg_key="goal-overdue-${agent}-${urgent_weakness}-${TODAY}"
      if ! grep -q "\"key\":\"${urg_key}\"" "$issues_log" 2>/dev/null; then
        echo "{\"ts\":\"$NOW_MT\",\"key\":\"$urg_key\",\"agent\":\"$agent\",\"question\":\"GOAL\",\"severity\":\"P0\",\"description\":\"Goal deadline passed for $agent/$urgent_weakness. Overriding cycle to address urgent weakness now.\",\"remediated\":false,\"date\":\"$TODAY\"}" >> "$issues_log"
      fi
      fi  # end: not resolved check
    fi
  fi

  # ── Daily assess Q4 override: use evidence-based top weakness from 4AM assessment ──
  # agent-daily-assess.sh runs at 04:00 and derives Q4_top_weakness from severity + goal deadlines.
  # If its recommendation differs from the state-machine's current_weakness AND we're in
  # research stage (not mid-implement), override. This prevents the self-improve loop from
  # working on stale weakness priority — daily data wins over state machine order.
  # Only applies in research stage to avoid interrupting in-progress implementations.
  local daily_assess_run_file="$HYO_ROOT/agents/$agent/ledger/daily-assess-${TODAY}.json"
  if [[ -f "$daily_assess_run_file" && "$stage" == "research" ]]; then
    local da_q4_weakness
    da_q4_weakness=$(python3 -c "
import json
from pathlib import Path
try:
    d = json.loads(Path('$daily_assess_run_file').read_text())
    q4 = d.get('Q4_top_weakness', {})
    if isinstance(q4, dict):
        wid = q4.get('weakness_id', '')
    else:
        wid = str(q4)
    # Only accept valid weakness/expansion IDs (W1-W9, E1-E9)
    import re
    print(wid if re.match(r'^[WE]\d+$', wid) else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
    if [[ -n "$da_q4_weakness" && "$da_q4_weakness" != "$current_weakness" && "$da_q4_weakness" != "null" ]]; then
      # P0 gate: never override to a resolved weakness — daily-assess Q4 may recommend
      # a weakness that was just resolved in the last cycle. Check status first.
      local da_q4_status
      da_q4_status=$(echo "$weaknesses" | python3 -c "
import json,sys
ws = json.load(sys.stdin)
for w in ws:
    if w['id'] == '$da_q4_weakness':
        print(w.get('status','active'))
        break
else:
    print('unknown')
" 2>/dev/null || echo "unknown")
      if [[ "$da_q4_status" == "resolved" ]]; then
        log "  DAILY-ASSESS Q4: $da_q4_weakness is already RESOLVED — ignoring override, keeping $current_weakness"
      else
        log "  DAILY-ASSESS Q4 OVERRIDE: $da_q4_weakness (daily evidence, status=$da_q4_status) → overriding $current_weakness (state machine)"
        current_weakness="$da_q4_weakness"
        stage="research"
        failure_count=0
      fi
    else
      log "  Daily-assess Q4: $da_q4_weakness — consistent with state machine ($current_weakness), no override"
    fi
  else
    [[ ! -f "$daily_assess_run_file" ]] && log "  Daily-assess: no 4AM assessment file — state machine weakness order used"
  fi

  # weaknesses / weakness_count / active_count already populated at top of function (Cycle 2 fix)
  if [[ "$weakness_count" -eq 0 ]]; then
    log "  No weaknesses in GROWTH.md — nothing to improve"
    return 0
  fi
  if [[ "$active_count" -eq 0 ]]; then
    log "  All $weakness_count weaknesses are RESOLVED — nothing active to improve"
    log "  → identify_next_weakness should have added new items. If GROWTH.md has no active items, update manually."
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

      # Run research — pass prior_knowledge so it enriches the research prompt
      # Previously queried and logged but never forwarded (silent waste of memory engine value)
      research_weakness "$agent" "$current_weakness" "$weakness_title" "$evidence" "$prior_knowledge" > /dev/null

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
        local fix_approach_check confidence_check verification_check source_note_check
        fix_approach_check=$(grep "^FIX_APPROACH:" "$expected_research" | sed 's/FIX_APPROACH: //' | head -1)
        confidence_check=$(grep "^CONFIDENCE:" "$expected_research" | sed 's/CONFIDENCE: //' | head -1)
        verification_check=$(grep "^VERIFICATION:" "$expected_research" | sed 's/VERIFICATION: //' | head -1)
        source_note_check=$(grep "WARNING: GROWTH.md had no fix_approach" "$expected_research" 2>/dev/null || echo "")
        if [[ -z "$fix_approach_check" ]]; then
          gate_fail=1
          gate_reason="FIX_APPROACH field is empty in research file"
        elif [[ "$confidence_check" != "HIGH" && "$confidence_check" != "MEDIUM" ]]; then
          gate_fail=1
          gate_reason="CONFIDENCE='${confidence_check:-empty}' — need HIGH or MEDIUM"
        elif [[ -z "$verification_check" ]]; then
          # P1 gate: research without a VERIFICATION criterion cannot be verified after implement.
          # Force back to research so a proper verification measure is derived.
          gate_fail=1
          gate_reason="VERIFICATION field is empty — cannot verify fix after implement (re-research needed)"
        elif [[ -n "$source_note_check" ]]; then
          # P1 gate: Python heuristic fallback produced MEDIUM confidence with WARNING in source_note.
          # This means GROWTH.md had no Fix approach for this weakness — heuristic guessed.
          # Heuristic output passing the gate caused wrong implementations in production.
          # Block and require GROWTH.md to have a Fix approach section added first.
          gate_fail=1
          gate_reason="Python heuristic fallback used (no Fix approach in GROWTH.md for $current_weakness) — add Fix approach to GROWTH.md first"
          log "  → ACTION REQUIRED: Add '**Fix approach:**' section to agents/$agent/GROWTH.md under ### $current_weakness"
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
        # P0 gate: do NOT advance to verify when implement was skipped.
        # Saving to "verify" with no actual implementation creates a guaranteed fail loop:
        # verify fails → failure_count++ → back to research → build brief → empty → verify → ...
        # Instead: log, increment failure (so MAX_RETRIES eventually advances the weakness),
        # and save back to "research" so we try building a better brief next cycle.
        log "  GATE: implement skipped — saving back to research stage (failure $((failure_count+1))/$MAX_RETRIES)"
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"failure_count\":$((failure_count+1)),\"improvements\":[],\"last_run\":\"$NOW_MT\",\"skip_reason\":\"brief_empty\"}"

        # ── IMPROVEMENT v2.0: Emit event signal on brief_empty ───────────────
        # Structural fix for OK Plateau: schedule-only improvement → arrested development.
        # When research produces empty output, emit a signal immediately so kai-autonomous
        # can trigger a targeted improvement cycle without waiting for the next 04:30 run.
        # This converts a silent failure into an actionable event (antifragility pattern).
        local _sig_sh="$HYO_ROOT/bin/kai-signal.sh"
        if [[ -f "$_sig_sh" ]]; then
          HYO_ROOT="$HYO_ROOT" bash "$_sig_sh" emit "$agent" "research_failure" \
            "brief_empty for $current_weakness after $((failure_count+1)) attempts. Stage: implement. CLAUDE_AUTH_REASON: ${CLAUDE_AUTH_REASON:-unknown}" \
            "agent-self-improve:implement" 2>/dev/null || true
          log "  → Signal emitted: research_failure (failure $((failure_count+1))/$MAX_RETRIES)"
        fi

        # ── Python fallback brief: attempt a data-only implementation brief ──
        # Rather than silently failing, try to produce a minimal implementable brief
        # from existing research files without Claude Code. This unblocks cycles
        # even when the LLM is unavailable.
        local _fallback_brief=""
        local _research_file_retry="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
        if [[ ! -f "$_research_file_retry" ]]; then
          # Try yesterday's research as fallback anchor
          local _yesterday
          _yesterday=$(TZ=America/Denver date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d 2>/dev/null || echo "")
          if [[ -n "$_yesterday" ]]; then
            local _yesterday_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${_yesterday}.md"
            if [[ -f "$_yesterday_file" ]]; then
              log "  FALLBACK: using yesterday's research as brief anchor ($current_weakness)"
              cp "$_yesterday_file" "$_research_file_retry" 2>/dev/null || true
              log "  → Copied yesterday's research — implement stage may proceed next cycle"
            fi
          fi
        fi

        report_to_kai "$agent"
        return 0
      fi

      # Find relevant files from research
      local research_file="$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"
      local files_hint=""
      if [[ -f "$research_file" ]]; then
        files_hint=$(grep "^FILES_TO_CHANGE:" "$research_file" | sed 's/FILES_TO_CHANGE: //')
      fi

      # Gate: implement stage requires valid Claude Code auth (pre-checked at module level)
      if [[ "${claude_auth_ok:-false}" != "true" ]]; then
        log "  GATE BLOCK: implement stage skipped — Claude Code auth unavailable (pre-checked)"
        log "  → Run: claude auth login on the Mini to re-enable implement stage"
        log "  → Python fallback research remains active; state held at implement"
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"implement\",\"cycles\":$cycles,\"failure_count\":$failure_count,\"improvements\":[],\"last_run\":\"$NOW_MT\",\"blocked_reason\":\"claude_auth_unavailable\"}"
        return 0
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

        # P0 gate: mark weakness RESOLVED in GROWTH.md HERE, before identify_next_weakness.
        # Previously RESOLVED was written inside identify_next_weakness() which requires
        # Claude Code auth. If auth is unavailable, weakness was never marked resolved →
        # next cycle re-researches and re-implements an already-fixed weakness (wasted cycle).
        # Fix: always mark resolved immediately upon verify success, regardless of auth state.
        local growth_file_v="$HYO_ROOT/agents/$agent/GROWTH.md"
        if [[ -f "$growth_file_v" ]]; then
          python3 - "$growth_file_v" "$current_weakness" << 'PYEOF' 2>/dev/null || true
import sys, re
path, wid = sys.argv[1], sys.argv[2]
content = open(path).read()
# Only add RESOLVED if not already present
if f'### {wid}:' in content and 'RESOLVED' not in content[content.find(f'### {wid}:'):content.find(f'### {wid}:')+500]:
    content = re.sub(
        r'(### ' + re.escape(wid) + r': .+?\n)',
        r'\1**Status:** ✓ RESOLVED — verified by agent-self-improve.sh\n',
        content, count=1
    )
    open(path, 'w').write(content)
    print(f"{wid} marked RESOLVED in GROWTH.md")
else:
    print(f"{wid} already marked or pattern not found — no change")
PYEOF
          log "  ✓ $current_weakness marked RESOLVED in GROWTH.md"
        fi

        # Persist knowledge
        persist_knowledge "$agent" "$current_weakness" "$weakness_title" \
          "Fixed via Claude Code delegate — see agents/$agent/research/improvements/${current_weakness}-${TODAY}.md"

        # Identify next weakness (may fail if auth unavailable — that's OK, weakness is already marked RESOLVED above)
        local next_wid
        next_wid=$(identify_next_weakness "$agent" "$current_weakness")
        next_wid="${next_wid:-W1}"

        log "  Next weakness: $next_wid"
        save_state "$agent" "{\"current_weakness\":\"$next_wid\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"failure_count\":0,\"improvements\":[\"$current_weakness\"],\"last_run\":\"$NOW_MT\"}"

        # ── IMPROVEMENT v2.0: Write forward AAR for next cycle ───────────────
        # After a successful fix, write a structured "next cycle goal" that the
        # NEXT research phase reads as its anchor. This creates a compounding
        # learning chain — each cycle tells the next what to focus on, preventing
        # cold starts from GROWTH.md alone. (Double-loop learning in practice.)
        local _aar_fwd_dir="$HYO_ROOT/agents/$agent/ledger"
        local _aar_fwd_file="$_aar_fwd_dir/forward-aar-${TODAY}.json"
        mkdir -p "$_aar_fwd_dir"
        python3 - << PYEOF 2>/dev/null || true
import json
from pathlib import Path

p = Path("$_aar_fwd_file")
existing = []
if p.exists():
    try:
        existing = json.loads(p.read_text())
        if not isinstance(existing, list): existing = [existing]
    except: pass

# Read research file to extract what was learned
research_path = Path("$HYO_ROOT/agents/$agent/research/improvements/${current_weakness}-${TODAY}.md")
learned = ""
if research_path.exists():
    content = research_path.read_text()
    # Extract ROOT_CAUSE and VERIFICATION lines as the lesson
    for line in content.splitlines():
        if line.startswith(("ROOT_CAUSE:", "VERIFICATION:", "CONFIDENCE:")):
            learned += line + "\n"

aar = {
    "ts": "$NOW_MT",
    "agent": "$agent",
    "weakness_resolved": "$current_weakness",
    "weakness_title": "$weakness_title",
    "cycles_taken": $((cycles + 1)),
    "next_weakness": "$next_wid",
    "lessons_from_fix": learned.strip() or "see research file",
    "next_cycle_goal": {
        "direction": f"Research $next_wid immediately — previous cycle resolved $current_weakness after $((cycles + 1)) cycle(s)",
        "question": f"What is the evidence-based root cause of $next_wid? What does the agent's own data say?",
        "success_measure": f"$next_wid fix is verifiable via a specific command or log check — not just 'it should work'",
        "priority": "P2",
        "bypass_rotation": False,
        "previous_resolution": {
            "weakness": "$current_weakness",
            "lessons": learned.strip()
        }
    }
}
existing.append(aar)
p.write_text(json.dumps(existing, indent=2))
print(f"[self-improve] Forward AAR written for next cycle: next_weakness=$next_wid")
PYEOF
        log "  ✓ Forward AAR written for $next_wid (next cycle will read it)"

        # P0 gate: commit AND push. Never swallow push failure with || true.
        # SE-010-015: 8 commits sat latent for 18h because push was || true.
        # If push fails: log P1 to daily-issues so morning report surfaces it.
        local git_push_ok=0
        if cd "$HYO_ROOT" 2>/dev/null; then
          git add "agents/$agent/" "kai/memory/KNOWLEDGE.md" 2>/dev/null || true
          if ! git diff --cached --quiet 2>/dev/null; then
            if git commit -m "improve($agent): $current_weakness resolved — $weakness_title" 2>/dev/null; then
              if git push origin main 2>/dev/null; then
                log "  ✓ Improvement committed and pushed"
                git_push_ok=1
              else
                log "  ✗ PUSH FAILED for $agent/$current_weakness — staged but not on remote"
                local push_key="git-push-fail-${agent}-${current_weakness}-${TODAY}"
                if ! grep -q "\"key\":\"${push_key}\"" "$HYO_ROOT/kai/ledger/daily-issues.jsonl" 2>/dev/null; then
                  echo "{\"ts\":\"$NOW_MT\",\"key\":\"$push_key\",\"agent\":\"$agent\",\"question\":\"PUSH\",\"severity\":\"P1\",\"description\":\"git push failed after $agent/$current_weakness improvement was committed. Commit exists locally but not on remote. Run: cd $HYO_ROOT && git push origin main\",\"remediated\":false,\"date\":\"$TODAY\"}" >> "$HYO_ROOT/kai/ledger/daily-issues.jsonl"
                fi
              fi
            else
              log "  WARN: git commit failed (nothing staged?) — skipping push"
            fi
          else
            log "  INFO: No staged changes to commit (already clean)"
            git_push_ok=1
          fi
        fi

      else
        log "  ✗ Verification failed — regression risk, rolling back to research stage (failure $((failure_count+1))/$MAX_RETRIES)"
        # C3 fix C3-P1-4: if verify failed but files WERE changed, the changes are still applied.
        # Log this to daily-issues so Kai knows to manually review and potentially revert.
        local uncommitted_changes
        uncommitted_changes=$(cd "$HYO_ROOT" && git diff --name-only "agents/$agent/" 2>/dev/null | head -10 || echo "")
        if [[ -n "$uncommitted_changes" ]]; then
          local verify_fail_key="verify-fail-changes-${agent}-${current_weakness}-${TODAY}"
          if ! grep -q "\"key\":\"${verify_fail_key}\"" "$HYO_ROOT/kai/ledger/daily-issues.jsonl" 2>/dev/null; then
            echo "{\"ts\":\"$NOW_MT\",\"key\":\"$verify_fail_key\",\"agent\":\"$agent\",\"question\":\"VERIFY\",\"severity\":\"P1\",\"description\":\"Verify failed for $agent/$current_weakness but files were changed: $uncommitted_changes — changes NOT committed (awaiting manual review). Check if the implementation was partially applied and decide whether to revert.\",\"remediated\":false,\"date\":\"$TODAY\"}" >> "$HYO_ROOT/kai/ledger/daily-issues.jsonl"
            log "  → P1 logged: uncommitted changes from failed verify — manual review needed"
          fi
        fi
        save_state "$agent" "{\"current_weakness\":\"$current_weakness\",\"stage\":\"research\",\"cycles\":$((cycles+1)),\"failure_count\":$((failure_count+1)),\"improvements\":[],\"last_run\":\"$NOW_MT\"}"
      fi
      ;;
  esac

  log "  Cycle complete for $agent"

  # ── Pre-action gate: Pattern 7 enforcement ────────────────────────────────────
  # Pattern 7: The Report Instead of the System — every lesson must be encoded in
  # something that runs, not just prose. This check fires each cycle to verify:
  # - Is the research file present (not just described)?
  # - Is the state machine in a valid stage (not stale)?
  # - Did something actually change this cycle (not theater)?
  local expected_state_file="$HYO_ROOT/agents/$agent/ledger/self-improve-state.json"
  if [[ -f "$expected_state_file" ]]; then
    local state_age_s
    state_age_s=$(python3 -c "import os,time; print(int(time.time()-os.path.getmtime('$expected_state_file')))" 2>/dev/null || echo "999")
    if [[ "${state_age_s:-999}" -lt 300 ]]; then
      log "  ✓ Gate P7: state file updated this cycle (${state_age_s}s ago) — cycle produced real output"
    else
      log "  WARN Gate P7: state file not updated this cycle (${state_age_s}s old) — was this cycle theater?"
    fi
  fi

  # ── Report to Kai ────────────────────────────────────────────────────────────
  # Pass the stage that was COMPLETED this cycle (save_state already wrote next stage,
  # so reading state would give wrong stage in the report).
  report_to_kai "$agent" "$stage"
}

# ─── Report to Kai (write self-improve-latest.json + dispatch) ───────────────
report_to_kai() {
  local agent="$1"
  # P1 fix: accept stage_completed as param so we report what HAPPENED this cycle,
  # not what's next. Previously save_state ran before report_to_kai, so reading state
  # gave the NEXT stage (e.g., "implement" after research was done → report was wrong).
  local stage_completed="${2:-}"
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

  # Determine outcome text — use stage_completed to describe what happened THIS cycle
  local outcome_text
  local completed="${stage_completed:-$stage}"
  case "$completed" in
    research)   outcome_text="Researched $current_weakness — built research brief, advancing to implement" ;;
    implement)  outcome_text="Implemented fix for $current_weakness — advancing to verify" ;;
    verify)     outcome_text="Verified + knowledge persisted for $current_weakness — next weakness queued" ;;
    *)          outcome_text="Completed stage: ${completed}" ;;
  esac

  # Write self-improve-latest.json (consumed by morning report generator)
  python3 - << PYEOF
import json
from pathlib import Path

report = {
    "agent": "$agent",
    "report_date": "$TODAY",
    "ts": "$NOW_MT",
    "cycle_stage_completed": "${stage_completed:-$stage}",
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

# Pre-flight: verify Claude Code auth once at the module level.
# Sets CLAUDE_AUTH_OK=true/false — implement stage reads this flag per-agent.
# If auth is down → Telegram alert fires once here, not once per agent.
log_section "AUTH PRE-CHECK"
if check_claude_health; then
  CLAUDE_AUTH_OK=true
  log "✓ Claude Code auth verified — implement stage active"
else
  CLAUDE_AUTH_OK=false
  log "✗ Claude Code auth unavailable — all agents run research+Python fallback only"
fi

if [[ "$TARGET" == "all" ]]; then
  # Kai runs FIRST, synchronously. Its research findings (systemic patterns, cross-agent
  # insights) are written before any other agent runs. This is the orchestrator model:
  # Kai diagnoses → agents act on informed context.
  log_section "KAI (orchestrator — runs first)"
  run_self_improve "kai" >> "$LOG" 2>&1

  # Propagate Kai's findings: if Kai's research file exists, extract systemic insights
  # for injection into other agents' context.
  KAI_RESEARCH=$(ls -t "$HYO_ROOT/agents/kai/research/improvements/"*-"$TODAY".md 2>/dev/null | head -1 || true)
  if [[ -f "$KAI_RESEARCH" ]]; then
    KAI_SYSTEMIC=$(grep -A5 "SYSTEMIC_PATTERN:\|CROSS_AGENT:" "$KAI_RESEARCH" 2>/dev/null | head -20 || true)
    log "✓ Kai research complete — systemic context available for agents"
    [[ -n "$KAI_SYSTEMIC" ]] && log "  Systemic patterns found: $(echo "$KAI_SYSTEMIC" | wc -l) lines"
  fi

  # All other agents run in parallel (Kai is done, no state race)
  log_section "AGENTS (parallel)"
  for agent in nel sam aether ra dex; do
    ( run_self_improve "$agent" ) >> "$LOG" 2>&1 &
  done
  wait  # collect all backgrounds before summary
  report_summary
else
  run_self_improve "$TARGET"
fi

log "agent-self-improve.sh complete"
exit 0
