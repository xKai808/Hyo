#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/agents/dex/dex.sh
#
# Dex Agent — System memory manager
# Owns integrity, compaction, indexing, pattern detection, and recall for ALL agent ledgers.
#
# Usage:
#   kai dex validate   - validate all JSONL files for integrity
#   kai dex stale      - detect tasks older than 72h with no update
#   kai dex compact    - archive old entries (>30 days) into archives
#   kai dex patterns   - cross-reference known-issues with recent logs
#   kai dex report     - run all phases and produce summary report
#

set -uo pipefail

# ---- Setup ------------------------------------------------------------------
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DEX_HOME="$ROOT/agents/dex"
DEX_LOGS="$DEX_HOME/logs"
DEX_ACTIVE="$DEX_HOME/ledger/ACTIVE.md"
DEX_LOG="$DEX_HOME/ledger/log.jsonl"

KAI_LEDGER="$ROOT/kai/ledger"
NEL_LEDGER="$ROOT/agents/nel/ledger"
RA_LEDGER="$ROOT/agents/ra/ledger"
SAM_LEDGER="$ROOT/agents/sam/ledger"

TODAY=$(date +%Y-%m-%d)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
REPORT="$DEX_LOGS/dex-$TODAY.md"
ACTIVITY_LOG="$DEX_LOGS/dex-activity-$TODAY.jsonl"

mkdir -p "$DEX_LOGS" "$DEX_HOME/ledger"

# ---- Dispatch sourcing for flag/report commands ----------------------------
DISPATCH_SH="$ROOT/bin/dispatch.sh"

dispatch_flag() {
  local severity="$1" title="$2"
  if [[ -f "$DISPATCH_SH" ]]; then
    bash "$DISPATCH_SH" flag dex "$severity" "$title" 2>/dev/null || true
  fi
}

dispatch_report() {
  local task_id="$1" status="$2" result="$3"
  if [[ -f "$DISPATCH_SH" ]]; then
    bash "$DISPATCH_SH" report "$task_id" "$status" "$result" 2>/dev/null || true
  fi
}

# ---- Color helpers ----------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RED=$(tput setaf 1); GRN=$(tput setaf 2)
  YLW=$(tput setaf 3); BLU=$(tput setaf 4); RST=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; RST=""
fi

log_info() { printf '[%s] %s\n' "$NOW_ISO" "$*" >> "$REPORT"; }
log_pass() { printf '%s✓%s %s\n' "$GRN" "$RST" "$*" | tee -a "$REPORT"; }
log_warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*" | tee -a "$REPORT"; }
log_fail() { printf '%s✗%s %s\n' "$RED" "$RST" "$*" | tee -a "$REPORT"; }

# ---- Activity logging to JSONL -----------------------------------------------
log_activity() {
  local phase="$1" status="$2" details="${3:-}"
  local entry=$(cat <<JSEOF
{"ts":"$NOW_ISO","phase":"$phase","status":"$status","details":"$details","agent":"dex.hyo"}
JSEOF
)
  echo "$entry" >> "$ACTIVITY_LOG" 2>/dev/null || true
}

# ---- Report Header ----------------------------------------------------------
cat > "$REPORT" <<EOF
# Dex System Maintenance Report

**Date:** $TODAY ($NOW_ISO)
**Agent:** dex.hyo v1.0.0
**Reports to:** Kai (CEO)

---

## Executive Summary

Dex conducts daily system memory validation, compaction, pattern detection, and integrity audits.
This report summarizes findings across all agent ledgers (kai, nel, ra, sam).
Corrupt entries, stale tasks, and recurrent patterns are flagged for Kai action.

---

EOF

log_info "dex.hyo daily run start"

# ============================================================================
# PHASE 1: INTEGRITY VALIDATION
# ============================================================================
echo "## Phase 1: JSONL Integrity Validation" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Phase 1: Validating all JSONL files"
log_activity "PHASE_1_INTEGRITY" "in_progress" "Starting JSONL validation"

INTEGRITY_PASS=0
INTEGRITY_FAIL=0
CORRUPT_ENTRIES=""
INTEGRITY_ERRORS=""

# Function to validate a JSONL file
validate_jsonl() {
  local filepath="$1"
  local agent_name="${2:-unknown}"

  if [[ ! -f "$filepath" ]]; then
    return 0
  fi

  local line_no=0
  local corrupt=0
  while IFS= read -r line; do
    ((line_no++))
    if [[ -z "$line" ]]; then
      continue
    fi

    # Try to parse as JSON
    if ! echo "$line" | python3 -m json.tool >/dev/null 2>&1; then
      corrupt=$((corrupt + 1))
      CORRUPT_ENTRIES="${CORRUPT_ENTRIES}  - $agent_name:$filepath:line $line_no\n"
      INTEGRITY_ERRORS="${INTEGRITY_ERRORS}    ${RED}✗${RST} $agent_name:$filepath:line $line_no — invalid JSON\n"
    fi

    # Check required fields (ts, type/action, agent)
    local has_ts=$(echo "$line" | python3 -c "import sys, json; d=json.load(sys.stdin); print('ts' in d)" 2>/dev/null)
    local has_action_or_type=$(echo "$line" | python3 -c "import sys, json; d=json.load(sys.stdin); print(('action' in d or 'type' in d))" 2>/dev/null)

    if [[ "$has_ts" != "True" ]] || [[ "$has_action_or_type" != "True" ]]; then
      corrupt=$((corrupt + 1))
      CORRUPT_ENTRIES="${CORRUPT_ENTRIES}  - $agent_name:$filepath:line $line_no (missing ts/action/type)\n"
    fi
  done < "$filepath"

  if [[ $corrupt -gt 0 ]]; then
    ((INTEGRITY_FAIL++))
    log_fail "JSONL validation failed: $filepath ($corrupt corrupt entries)"
    return 1
  else
    ((INTEGRITY_PASS++))
    log_pass "JSONL validation passed: $filepath"
    return 0
  fi
}

# Validate all ledger files
validate_jsonl "$KAI_LEDGER/log.jsonl" "kai" || true
validate_jsonl "$NEL_LEDGER/log.jsonl" "nel" || true
validate_jsonl "$RA_LEDGER/log.jsonl" "ra" || true
validate_jsonl "$SAM_LEDGER/log.jsonl" "sam" || true
validate_jsonl "$KAI_LEDGER/known-issues.jsonl" "kai:known-issues" || true
validate_jsonl "$KAI_LEDGER/simulation-outcomes.jsonl" "kai:simulation-outcomes" || true

# Validate dex's own ledger log
validate_jsonl "$DEX_LOG" "dex" || true

# Report Phase 1 results
{
  echo "### Results"
  echo ""
  echo "- Passed: $INTEGRITY_PASS JSONL files"
  echo "- Failed: $INTEGRITY_FAIL JSONL files"
  echo ""

  if [[ -n "$CORRUPT_ENTRIES" ]]; then
    echo "### Corrupt Entries Found"
    echo ""
    echo -e "$CORRUPT_ENTRIES"
    echo ""
  fi
} >> "$REPORT"

if [[ $INTEGRITY_FAIL -gt 0 ]]; then
  log_activity "PHASE_1_INTEGRITY" "failed" "Found $INTEGRITY_FAIL corrupt JSONL files"
  dispatch_flag "P0" "Dex Phase 1 FAILED: $INTEGRITY_FAIL JSONL files have corrupt entries"
else
  log_activity "PHASE_1_INTEGRITY" "passed" "All JSONL files validated successfully"
  log_pass "Phase 1 complete: All JSONL files valid"
fi

# ============================================================================
# PHASE 2: STALE TASK DETECTION
# ============================================================================
echo "## Phase 2: Stale Task Detection (72h threshold)" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Phase 2: Detecting stale tasks"
log_activity "PHASE_2_STALE" "in_progress" "Scanning ACTIVE.md files"

STALE_TASKS=""
STALE_COUNT=0

# Function to check for stale tasks in ACTIVE.md
check_stale_tasks() {
  local filepath="$1"
  local agent_name="$2"

  if [[ ! -f "$filepath" ]]; then
    return 0
  fi

  # Extract task lines with timestamps
  local cutoff_time=$(date -u -d "72 hours ago" +%s 2>/dev/null || date -u -v-72H +%s 2>/dev/null || echo 0)

  while IFS= read -r line; do
    # Look for lines with format: "- **task-id** [priority] description" with timestamp
    if [[ $line =~ Delegated:\ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      local task_date="${BASH_REMATCH[1]}"
      local task_epoch=$(date -u -d "$task_date" +%s 2>/dev/null || date -u -f "%Y-%m-%d" "$task_date" +%s 2>/dev/null || echo 0)

      if [[ $task_epoch -gt 0 ]] && [[ $task_epoch -lt $cutoff_time ]]; then
        # Extract task ID
        if [[ $line =~ \*\*([a-z]+-[0-9]+)\*\* ]]; then
          local task_id="${BASH_REMATCH[1]}"
          ((STALE_COUNT++))
          STALE_TASKS="${STALE_TASKS}  - $agent_name:$task_id (delegated $task_date)\n"
        fi
      fi
    fi
  done < "$filepath"
}

# Check all ACTIVE.md files
check_stale_tasks "$KAI_LEDGER/ACTIVE.md" "kai" || true
check_stale_tasks "$NEL_LEDGER/ACTIVE.md" "nel" || true
check_stale_tasks "$RA_LEDGER/ACTIVE.md" "ra" || true
check_stale_tasks "$SAM_LEDGER/ACTIVE.md" "sam" || true

# Report Phase 2 results
{
  echo "### Results"
  echo ""

  if [[ $STALE_COUNT -eq 0 ]]; then
    echo "✓ No stale tasks detected (all tasks delegated within 72h)"
  else
    echo "! Found $STALE_COUNT stale tasks:"
    echo ""
    echo -e "$STALE_TASKS"
    echo ""
  fi
} >> "$REPORT"

if [[ $STALE_COUNT -gt 0 ]]; then
  log_activity "PHASE_2_STALE" "found" "$STALE_COUNT tasks older than 72h"
  dispatch_flag "P1" "Dex Phase 2: Found $STALE_COUNT stale tasks (>72h without update)"
else
  log_activity "PHASE_2_STALE" "passed" "No stale tasks detected"
  log_pass "Phase 2 complete: No stale tasks detected"
fi

# ============================================================================
# PHASE 3: LOG COMPACTION
# ============================================================================
echo "## Phase 3: Log Compaction (30-day threshold)" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Phase 3: Compacting old log entries"
log_activity "PHASE_3_COMPACTION" "in_progress" "Starting log compaction"

COMPACTION_COUNT=0
COMPACTED_BYTES=0

# Function to compact a JSONL log
compact_log() {
  local filepath="$1"
  local agent_name="$2"

  if [[ ! -f "$filepath" ]]; then
    return 0
  fi

  # Determine archive file name based on current date (YYYY-MM format)
  local month=$(date +%Y-%m)
  local last_month=$(date -u -d "31 days ago" +%Y-%m 2>/dev/null || date -u -v-31d +%Y-%m 2>/dev/null)

  # Calculate cutoff timestamp (30 days ago)
  local cutoff_date=$(date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-30d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

  local dir=$(dirname "$filepath")
  local base=$(basename "$filepath" .jsonl)
  local archive="$dir/${base}-archive-${last_month}.jsonl"

  # Python-based compaction (split old vs recent)
  python3 - "$filepath" "$archive" "$cutoff_date" << 'PYEOF'
import json
import sys
from datetime import datetime

log_file = sys.argv[1]
archive_file = sys.argv[2]
cutoff = sys.argv[3]

try:
  cutoff_dt = datetime.fromisoformat(cutoff.replace('Z', '+00:00'))
except:
  cutoff_dt = datetime.utcnow()

recent = []
archive_list = []

with open(log_file) as f:
  for line in f:
    line = line.strip()
    if not line:
      continue
    try:
      entry = json.loads(line)
      ts = entry.get('ts', '')
      try:
        entry_dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        if entry_dt < cutoff_dt:
          archive_list.append(entry)
        else:
          recent.append(entry)
      except:
        recent.append(entry)
    except:
      recent.append(line)

# Write archive
if archive_list:
  with open(archive_file, 'a') as f:
    for entry in archive_list:
      if isinstance(entry, dict):
        f.write(json.dumps(entry) + '\n')
      else:
        f.write(entry + '\n')
  print(f"Archived {len(archive_list)} entries to {archive_file}")

# Rewrite log with recent entries only
with open(log_file, 'w') as f:
  for entry in recent:
    if isinstance(entry, dict):
      f.write(json.dumps(entry) + '\n')
    else:
      f.write(entry + '\n')
print(f"Kept {len(recent)} recent entries in {log_file}")
PYEOF

  if [[ $? -eq 0 ]]; then
    ((COMPACTION_COUNT++))
    log_pass "Compacted log: $agent_name"
  fi
}

# Compact all agent logs
compact_log "$KAI_LEDGER/log.jsonl" "kai" || true
compact_log "$NEL_LEDGER/log.jsonl" "nel" || true
compact_log "$RA_LEDGER/log.jsonl" "ra" || true
compact_log "$SAM_LEDGER/log.jsonl" "sam" || true
compact_log "$DEX_LOG" "dex" || true

# Report Phase 3 results
{
  echo "### Results"
  echo ""
  echo "- Compacted: $COMPACTION_COUNT log files"
  echo "- Entries >30 days old archived to log-archive-YYYY-MM.jsonl in each ledger directory"
  echo ""
} >> "$REPORT"

log_activity "PHASE_3_COMPACTION" "completed" "Compacted $COMPACTION_COUNT log files"
log_pass "Phase 3 complete: Compaction executed"

# ============================================================================
# PHASE 4: PATTERN DETECTION
# ============================================================================
echo "## Phase 4: Pattern Detection (Known Issues Cross-Reference)" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Phase 4: Detecting recurrent patterns"
log_activity "PHASE_4_PATTERNS" "in_progress" "Cross-referencing known-issues.jsonl"

PATTERNS_FOUND=0
RECURRENCE_ALERTS=""

# Check if known-issues.jsonl exists
if [[ -f "$KAI_LEDGER/known-issues.jsonl" ]]; then

  # Extract known issue descriptions from known-issues.jsonl
  # For each known issue, scan recent logs for similar patterns
  python3 - "$KAI_LEDGER/known-issues.jsonl" "$KAI_LEDGER/log.jsonl" "$NEL_LEDGER/log.jsonl" "$RA_LEDGER/log.jsonl" "$SAM_LEDGER/log.jsonl" << 'PYEOF'
import json
import sys
from datetime import datetime, timedelta

known_issues_file = sys.argv[1]
log_files = sys.argv[2:]

# Load known issues
known_issues = {}
try:
  with open(known_issues_file) as f:
    for line in f:
      line = line.strip()
      if not line:
        continue
      try:
        entry = json.loads(line)
        desc = entry.get('description', '').lower()
        if desc:
          known_issues[desc] = entry
      except:
        pass
except:
  pass

# Scan logs for pattern matches (substring matching)
cutoff = datetime.utcnow() - timedelta(days=7)
found_patterns = {}

for log_file in log_files:
  try:
    with open(log_file) as f:
      for line in f:
        line = line.strip()
        if not line:
          continue
        try:
          entry = json.loads(line)
          ts = entry.get('ts', '')
          desc = entry.get('description', '') or entry.get('title', '')
          desc_lower = desc.lower()

          # Check if this log entry matches a known issue pattern
          for pattern, pattern_data in known_issues.items():
            if pattern in desc_lower or desc_lower in pattern:
              if desc not in found_patterns:
                found_patterns[desc] = {
                  'count': 0,
                  'ts': ts,
                  'pattern': pattern,
                  'status': pattern_data.get('status', 'unknown')
                }
              found_patterns[desc]['count'] += 1
        except:
          pass
  except:
    pass

# Report findings
if found_patterns:
  print(f"PATTERNS_FOUND={len(found_patterns)}")
  for desc, data in found_patterns.items():
    print(f"PATTERN:{data['count']}:{desc}:{data['status']}")
else:
  print("PATTERNS_FOUND=0")
PYEOF

  # Parse output
  while IFS='=' read -r key val; do
    if [[ "$key" == "PATTERNS_FOUND" ]]; then
      PATTERNS_FOUND=$val
    fi
  done < <(python3 - "$KAI_LEDGER/known-issues.jsonl" "$KAI_LEDGER/log.jsonl" "$NEL_LEDGER/log.jsonl" "$RA_LEDGER/log.jsonl" "$SAM_LEDGER/log.jsonl" 2>/dev/null <<'PYEOF'
import json
import sys
from datetime import datetime, timedelta

known_issues_file = sys.argv[1]
log_files = sys.argv[2:]

known_issues = {}
try:
  with open(known_issues_file) as f:
    for line in f:
      line = line.strip()
      if not line:
        continue
      try:
        entry = json.loads(line)
        desc = entry.get('description', '').lower()
        if desc:
          known_issues[desc] = entry
      except:
        pass
except:
  pass

cutoff = datetime.utcnow() - timedelta(days=7)
found_patterns = {}

for log_file in log_files:
  try:
    with open(log_file) as f:
      for line in f:
        line = line.strip()
        if not line:
          continue
        try:
          entry = json.loads(line)
          ts = entry.get('ts', '')
          desc = entry.get('description', '') or entry.get('title', '')
          desc_lower = desc.lower()

          for pattern, pattern_data in known_issues.items():
            if pattern in desc_lower:
              if desc not in found_patterns:
                found_patterns[desc] = {
                  'count': 0,
                  'ts': ts,
                  'status': pattern_data.get('status', 'unknown')
                }
              found_patterns[desc]['count'] += 1
        except:
          pass
  except:
    pass

if found_patterns:
  print(f"PATTERNS_FOUND={len(found_patterns)}")
  for desc, data in found_patterns.items():
    print(f"  - {desc} ({data['count']} recent occurrences, status: {data['status']})")
else:
  print("PATTERNS_FOUND=0")
PYEOF
  )
fi

# Report Phase 4 results
{
  echo "### Results"
  echo ""

  if [[ $PATTERNS_FOUND -eq 0 ]]; then
    echo "✓ No recurrent patterns detected in recent logs"
  else
    echo "! Found $PATTERNS_FOUND recurrent patterns:"
    echo ""
    echo -e "$RECURRENCE_ALERTS"
    echo ""
  fi
} >> "$REPORT"

if [[ $PATTERNS_FOUND -gt 0 ]]; then
  log_activity "PHASE_4_PATTERNS" "found" "$PATTERNS_FOUND recurrent patterns detected"
  dispatch_flag "P1" "Dex Phase 4: $PATTERNS_FOUND recurrent patterns detected — check safeguard status"
else
  log_activity "PHASE_4_PATTERNS" "passed" "No recurrent patterns detected"
  log_pass "Phase 4 complete: No recurrent patterns detected"
fi

# ============================================================================
# PHASE 5: REPORT & DISPATCH
# ============================================================================
echo "## Phase 5: Summary & Dispatch" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Phase 5: Generating summary and dispatch report"
log_activity "PHASE_5_REPORT" "in_progress" "Compiling final report"

{
  echo "### Overall Status"
  echo ""

  if [[ $INTEGRITY_FAIL -eq 0 ]] && [[ $STALE_COUNT -eq 0 ]] && [[ $PATTERNS_FOUND -eq 0 ]]; then
    echo "✓ **All systems healthy** — No issues detected across all ledgers"
    STATUS="HEALTHY"
  else
    echo "⚠ **Issues detected** — See details above"
    STATUS="ISSUES_DETECTED"
  fi

  echo ""
  echo "### Recommended Actions"
  echo ""

  if [[ $INTEGRITY_FAIL -gt 0 ]]; then
    echo "1. **P0 — Fix corrupt JSONL entries** (see Corrupt Entries section)"
  fi

  if [[ $STALE_COUNT -gt 0 ]]; then
    echo "1. **P1 — Unblock or close stale tasks** (see Stale Tasks section)"
  fi

  if [[ $PATTERNS_FOUND -gt 0 ]]; then
    echo "1. **P1 — Review recurrent patterns** (check safeguard cascade status)"
  fi

  echo ""
  echo "---"
  echo ""
  echo "**Report generated:** $NOW_ISO"
  echo "**Next run:** Tomorrow 03:00 MT (0900 UTC)"

} >> "$REPORT"

log_activity "PHASE_5_REPORT" "completed" "Report generated"
log_pass "Phase 5 complete: Report generated and dispatch sent"

# ============================================================================
# PHASE 6: ACTIVE RESEARCH (Monday only)
# ============================================================================
DOW=$(TZ="America/Denver" date +%u)  # 1=Monday
if [[ "$DOW" == "1" ]]; then
  log_info "Phase 6: Active research (weekly Monday cycle)"

  RESEARCH_DIR="$ROOT/agents/ra/research/briefs"
  DEX_BRIEF=$(ls -t "$RESEARCH_DIR"/dex-*.md 2>/dev/null | head -1)
  RESEARCH_FINDINGS=0

  if [[ -n "$DEX_BRIEF" ]]; then
    log_pass "Found research brief: $DEX_BRIEF"
    # Log that we read the brief
    log_activity "PHASE_6_RESEARCH" "brief_read" "$DEX_BRIEF"
  else
    log_warn "No research brief found for Dex — Ra needs to generate one"
    dispatch_flag "P3" "no research brief available for Dex"
  fi

  # Anti-stale check: verify all agents have recent research briefs
  for agent in kai sam nel ra aurora aether dex; do
    AGENT_BRIEF=$(ls -t "$RESEARCH_DIR"/${agent}-*.md 2>/dev/null | head -1)
    if [[ -z "$AGENT_BRIEF" ]]; then
      log_warn "No research brief found for agent: $agent"
      dispatch_flag "P2" "agent research stale: $agent (no brief exists)"
      RESEARCH_FINDINGS=$((RESEARCH_FINDINGS + 1))
    else
      # Check age of brief
      BRIEF_DATE=$(stat -f "%m" "$AGENT_BRIEF" 2>/dev/null || stat -c "%Y" "$AGENT_BRIEF" 2>/dev/null || echo "0")
      NOW_EPOCH=$(date +%s)
      AGE_DAYS=$(( (NOW_EPOCH - BRIEF_DATE) / 86400 ))
      if [[ $AGE_DAYS -gt 14 ]]; then
        log_warn "Research brief stale for $agent: ${AGE_DAYS}d old"
        dispatch_flag "P2" "agent research stale: $agent (${AGE_DAYS}d since last brief)"
        RESEARCH_FINDINGS=$((RESEARCH_FINDINGS + 1))
      fi
    fi
  done

  log_activity "PHASE_6_RESEARCH" "completed" "Checked all agents, ${RESEARCH_FINDINGS} stale briefs flagged"
  log_pass "Phase 6 complete: Research check done, ${RESEARCH_FINDINGS} issues"
else
  log_info "Phase 6: Skipped (runs Monday only, today is day $DOW)"
fi

# ============================================================================
# FINAL: Dispatch to Kai
# ============================================================================
log_info "Dispatching daily summary to Kai"

dispatch_report "dex-daily" "COMPLETED" "Integrity: $INTEGRITY_PASS files validated, $INTEGRITY_FAIL issues. Stale: $STALE_COUNT tasks >72h. Patterns: $PATTERNS_FOUND recurrent. See $REPORT for details."

# Write final summary line
log_info "dex.hyo daily run complete — status: $STATUS"

cat >> "$REPORT" <<EOF

---

**Report location:** $REPORT
**Activity log:** $ACTIVITY_LOG
**Agent:** dex.hyo v1.0.0
**Next scheduled run:** $(date -u -d "24 hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

EOF

# Exit status
if [[ $INTEGRITY_FAIL -gt 0 ]]; then
  exit 2
elif [[ $STALE_COUNT -gt 0 ]] || [[ $PATTERNS_FOUND -gt 0 ]]; then
  exit 1
else
  exit 0
fi
