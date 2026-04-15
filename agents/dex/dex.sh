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

# ---- Growth Phase (self-improvement before main work) -----------------------
GROWTH_SH="$ROOT/bin/agent-growth.sh"
if [[ -f "$GROWTH_SH" ]]; then
  source "$GROWTH_SH"
  run_growth_phase "dex" || true
fi

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
  # Don't flag yet — Phase 1.5 will attempt auto-repair
else
  log_activity "PHASE_1_INTEGRITY" "passed" "All JSONL files validated successfully"
  log_pass "Phase 1 complete: All JSONL files valid"
fi

# ============================================================================
# PHASE 1.5: AUTO-REPAIR FOR FIXABLE CORRUPTION
# ============================================================================
echo "## Phase 1.5: Auto-Repair for Fixable Corruption" >> "$REPORT"
echo "" >> "$REPORT"

log_info "Phase 1.5: Attempting auto-repair on detected corruption"
log_activity "PHASE_1_5_REPAIR" "in_progress" "Running auto-repair on corrupt JSONL files"

REPAIR_SCRIPT="$DEX_HOME/repair.sh"
REPAIR_COUNT=0
REPAIR_RESULTS=""
STILL_CORRUPT=0

# Function to repair a JSONL file
repair_jsonl() {
  local filepath="$1"
  local agent_name="$2"

  if [[ ! -f "$filepath" ]] || [[ ! -s "$filepath" ]]; then
    return 0
  fi

  if [[ ! -x "$REPAIR_SCRIPT" ]]; then
    log_warn "repair.sh not found or not executable at $REPAIR_SCRIPT"
    return 1
  fi

  # Run repair and capture JSON output
  local repair_output
  repair_output=$(bash "$REPAIR_SCRIPT" "$filepath" 2>/dev/null || echo '{"status":"error"}')

  # Parse repair output
  local status=$(echo "$repair_output" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('status', 'unknown'))" 2>/dev/null || echo "unknown")
  local repaired=$(echo "$repair_output" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('repaired', 0))" 2>/dev/null || echo "0")
  local unfixable=$(echo "$repair_output" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('unfixable', 0))" 2>/dev/null || echo "0")
  local removed=$(echo "$repair_output" | python3 -c "import json, sys; d=json.load(sys.stdin); print(d.get('removed', 0))" 2>/dev/null || echo "0")

  if [[ "$status" != "error" ]]; then
    ((REPAIR_COUNT++))
    if [[ $repaired -gt 0 ]] || [[ $removed -gt 0 ]]; then
      log_pass "Repaired: $agent_name:$filepath (fixed $repaired, deduped/removed $removed)"
      REPAIR_RESULTS="${REPAIR_RESULTS}  - $agent_name: repaired=$repaired, deduped=$removed, unfixable=$unfixable\n"
    fi
    if [[ $unfixable -gt 0 ]]; then
      ((STILL_CORRUPT++))
      REPAIR_RESULTS="${REPAIR_RESULTS}    ⚠ $unfixable entries still unfixable — requires manual review\n"
    fi
  else
    log_warn "repair.sh failed for $agent_name:$filepath"
    REPAIR_RESULTS="${REPAIR_RESULTS}  - $agent_name: repair failed (see logs)\n"
  fi
}

# Attempt repair on all ledger files if corruption was detected
if [[ $INTEGRITY_FAIL -gt 0 ]]; then
  repair_jsonl "$KAI_LEDGER/log.jsonl" "kai" || true
  repair_jsonl "$NEL_LEDGER/log.jsonl" "nel" || true
  repair_jsonl "$RA_LEDGER/log.jsonl" "ra" || true
  repair_jsonl "$SAM_LEDGER/log.jsonl" "sam" || true
  repair_jsonl "$KAI_LEDGER/known-issues.jsonl" "kai:known-issues" || true
  repair_jsonl "$KAI_LEDGER/simulation-outcomes.jsonl" "kai:simulation-outcomes" || true
  repair_jsonl "$DEX_LOG" "dex" || true

  # Report Phase 1.5 results
  {
    echo "### Results"
    echo ""
    echo "- Files processed: $REPAIR_COUNT"
    echo "- Entries still unfixable: $STILL_CORRUPT"
    echo ""

    if [[ -n "$REPAIR_RESULTS" ]]; then
      echo "### Repair Details"
      echo ""
      echo -e "$REPAIR_RESULTS"
      echo ""
    fi
  } >> "$REPORT"

  if [[ $STILL_CORRUPT -gt 0 ]]; then
    log_activity "PHASE_1_5_REPAIR" "partial" "Fixed some, $STILL_CORRUPT entries remain unfixable"
    dispatch_flag "P1" "Dex Phase 1.5: Repaired corruption but $STILL_CORRUPT entries still unfixable (manual review needed)"
  else
    log_activity "PHASE_1_5_REPAIR" "success" "All fixable corruption repaired"
    log_pass "Phase 1.5 complete: All fixable corruption repaired"
  fi
else
  {
    echo "### Results"
    echo ""
    echo "- Skipped: No corruption detected in Phase 1"
    echo ""
  } >> "$REPORT"
  log_activity "PHASE_1_5_REPAIR" "skipped" "No corruption found to repair"
  log_pass "Phase 1.5 skipped: No corruption to repair"
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
# PHASE 6A: DAILY INTELLIGENCE SCAN (runs every day)
# Lightweight: scan for operational gaps, dispatch research requests to Ra,
# ingest any new briefs that arrived, check for stale research across agents.
# ============================================================================
echo "## Phase 6A: Daily Intelligence Scan" >> "$REPORT"
echo "" >> "$REPORT"
log_info "Phase 6A: Daily intelligence scan"
log_activity "PHASE_6A_DAILY_INTEL" "in_progress" "Starting daily intelligence scan"

RESEARCH_DIR="$ROOT/agents/ra/research/briefs"
RESEARCH_REQUEST_FILE="$DEX_HOME/ledger/research-requests.jsonl"
RESEARCH_FINDINGS=0
RESEARCH_REQUESTS=0
KAI_TASKS="$ROOT/KAI_TASKS.md"

mkdir -p "$RESEARCH_DIR"

# ---- 6A.1: Scan today's operations for research-worthy gaps ----
RESEARCH_NEEDS=""
# Check today's activity log for failures or issues that need investigation
if [[ -f "$ACTIVITY_LOG" ]]; then
  while IFS= read -r line; do
    local_status=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
    local_phase=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('phase',''))" 2>/dev/null || echo "")
    local_details=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('details',''))" 2>/dev/null || echo "")

    if [[ "$local_status" == "failed" ]] || [[ "$local_status" == "found" ]]; then
      RESEARCH_NEEDS="${RESEARCH_NEEDS}${local_phase}: ${local_details}\n"
    fi
  done < "$ACTIVITY_LOG"
fi 2>/dev/null

# Also scan yesterday's log for anything that wasn't caught
YESTERDAY=$(date -u -d "1 day ago" +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d 2>/dev/null)
YESTERDAY_LOG="$DEX_LOGS/dex-activity-${YESTERDAY}.jsonl"
if [[ -f "$YESTERDAY_LOG" ]]; then
  while IFS= read -r line; do
    local_status=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
    local_phase=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('phase',''))" 2>/dev/null || echo "")
    local_details=$(echo "$line" | python3 -c "import sys,json; print(json.load(sys.stdin).get('details',''))" 2>/dev/null || echo "")

    if [[ "$local_status" == "failed" ]] || [[ "$local_status" == "found" ]]; then
      RESEARCH_NEEDS="${RESEARCH_NEEDS}${local_phase}: ${local_details}\n"
    fi
  done < "$YESTERDAY_LOG"
fi 2>/dev/null

# ---- 6A.2: Daily research request to Ra ----
# Rotate through domains daily so every topic gets covered within a week
DAILY_TOPICS=(
  "agentic AI: multi-agent orchestration patterns, new frameworks, MCP protocol updates"
  "ledger systems: append-only log best practices, JSONL alternatives, event sourcing"
  "AI agents: autonomous agent architectures, memory systems, tool-use patterns"
  "data integrity: validation algorithms, checksums for streaming data, corruption recovery"
  "agent communication: inter-agent protocols, delegation patterns, consensus mechanisms"
  "AI research: latest papers on agent coordination, planning, self-improvement"
  "infrastructure: automation patterns, scheduled agent execution, monitoring dashboards"
)

DAY_INDEX=$(( $(date +%j) % ${#DAILY_TOPICS[@]} ))
DAILY_TOPIC="${DAILY_TOPICS[$DAY_INDEX]}"

# If operational gaps found, prepend them as context to the research request
if [[ -n "$RESEARCH_NEEDS" ]]; then
  DAILY_TOPIC="[OPS-GAP] $(echo -e "$RESEARCH_NEEDS" | head -1 | tr -d '\n') + standing: $DAILY_TOPIC"
fi

# Log and dispatch
REQ_ENTRY=$(cat <<JSEOF
{"ts":"$NOW_ISO","type":"research-request","date":"$TODAY","topic":"$DAILY_TOPIC","operational_gaps":"$(echo -e "$RESEARCH_NEEDS" | tr '\n' ';' | sed 's/;$//')","status":"submitted","cadence":"daily"}
JSEOF
)
echo "$REQ_ENTRY" >> "$RESEARCH_REQUEST_FILE" 2>/dev/null || true

if [[ -f "$DISPATCH_SH" ]]; then
  bash "$DISPATCH_SH" delegate ra P3 "[DAILY-INTEL] Dex $TODAY: $DAILY_TOPIC" 2>/dev/null || true
  RESEARCH_REQUESTS=$((RESEARCH_REQUESTS + 1))
  log_pass "6A.2: Daily research request dispatched to Ra"
fi

echo "### Daily Research Request" >> "$REPORT"
echo "" >> "$REPORT"
echo "- Topic: $DAILY_TOPIC" >> "$REPORT"
echo "- Dispatched to: Ra (P3)" >> "$REPORT"
if [[ -n "$RESEARCH_NEEDS" ]]; then
  echo "- Operational gaps attached as context" >> "$REPORT"
fi
echo "" >> "$REPORT"

# ---- 6A.3: Ingest any new briefs that arrived since last run ----
NEW_BRIEFS=0
LAST_RUN_EPOCH=0
# Check when Dex last ran by looking at the previous day's report
PREV_REPORT="$DEX_LOGS/dex-${YESTERDAY}.md"
if [[ -f "$PREV_REPORT" ]]; then
  LAST_RUN_EPOCH=$(stat -f "%m" "$PREV_REPORT" 2>/dev/null || stat -c "%Y" "$PREV_REPORT" 2>/dev/null || echo "0")
fi

for brief in "$RESEARCH_DIR"/dex-*.md; do
  [[ -f "$brief" ]] || continue
  BRIEF_EPOCH=$(stat -f "%m" "$brief" 2>/dev/null || stat -c "%Y" "$brief" 2>/dev/null || echo "0")
  if [[ $BRIEF_EPOCH -gt $LAST_RUN_EPOCH ]] && [[ $LAST_RUN_EPOCH -gt 0 ]]; then
    NEW_BRIEFS=$((NEW_BRIEFS + 1))
    log_pass "6A.3: New brief arrived: $brief"

    # Log for Kai review
    EVAL_ENTRY=$(cat <<JSEOF
{"ts":"$NOW_ISO","type":"research-eval","brief":"$brief","date":"$TODAY","status":"pending_review","notes":"New brief arrived — queued for Kai review"}
JSEOF
    )
    echo "$EVAL_ENTRY" >> "$DEX_LOG" 2>/dev/null || true
  fi
done

echo "### Brief Ingestion" >> "$REPORT"
echo "" >> "$REPORT"
echo "- New briefs since last run: $NEW_BRIEFS" >> "$REPORT"
echo "" >> "$REPORT"

# ---- 6A.4: Anti-stale check (runs daily, not just Monday) ----
echo "### Anti-Stale Check (all agents)" >> "$REPORT"
echo "" >> "$REPORT"

for agent in kai sam nel ra aurora aether dex; do
  AGENT_BRIEF=$(ls -t "$RESEARCH_DIR"/${agent}-*.md 2>/dev/null | head -1)
  if [[ -z "$AGENT_BRIEF" ]]; then
    log_warn "No research brief found for agent: $agent"
    dispatch_flag "P2" "agent research stale: $agent (no brief exists)"
    RESEARCH_FINDINGS=$((RESEARCH_FINDINGS + 1))
    echo "- $agent: **NO BRIEF** — flagged P2" >> "$REPORT"
  else
    BRIEF_DATE=$(stat -f "%m" "$AGENT_BRIEF" 2>/dev/null || stat -c "%Y" "$AGENT_BRIEF" 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - BRIEF_DATE) / 86400 ))
    if [[ $AGE_DAYS -gt 14 ]]; then
      log_warn "Research brief stale for $agent: ${AGE_DAYS}d old"
      dispatch_flag "P2" "agent research stale: $agent (${AGE_DAYS}d since last brief)"
      RESEARCH_FINDINGS=$((RESEARCH_FINDINGS + 1))
      echo "- $agent: **STALE** (${AGE_DAYS}d old) — flagged P2" >> "$REPORT"
    else
      log_pass "Research brief current for $agent: ${AGE_DAYS}d old"
      echo "- $agent: current (${AGE_DAYS}d old)" >> "$REPORT"
    fi
  fi
done

echo "" >> "$REPORT"

log_activity "PHASE_6A_DAILY_INTEL" "completed" "Requests: $RESEARCH_REQUESTS, new briefs: $NEW_BRIEFS, stale: $RESEARCH_FINDINGS"
log_pass "Phase 6A complete: Daily intel done — $RESEARCH_REQUESTS requests, $NEW_BRIEFS new briefs, $RESEARCH_FINDINGS stale"

# ============================================================================
# PHASE 6B: DEEP RESEARCH SYNTHESIS (Monday only)
# Full cycle: evaluate accumulated briefs, score findings, create concrete
# [RESEARCH] implementation tasks, submit deep-dive requests to Ra.
# ============================================================================
DOW=$(TZ="America/Denver" date +%u)  # 1=Monday
if [[ "$DOW" == "1" ]]; then
  echo "## Phase 6B: Weekly Deep Research Synthesis (Monday)" >> "$REPORT"
  echo "" >> "$REPORT"
  log_info "Phase 6B: Weekly deep research synthesis"
  log_activity "PHASE_6B_DEEP_RESEARCH" "in_progress" "Starting weekly synthesis"

  WEEK_NUM=$(date +%Y-W%V)
  DEX_RESEARCH_LOG="$DEX_LOGS/research-${WEEK_NUM}.md"

  # ---- 6B.1: Evaluate ALL briefs from the past week ----
  WEEKLY_BRIEFS=0
  APPLICABLE_FINDINGS=0

  cat > "$DEX_RESEARCH_LOG" <<REOF
# Dex Research Synthesis — $WEEK_NUM

**Generated:** $NOW_ISO
**Agent:** dex.hyo v1.1.0

## Briefs Evaluated This Week

REOF

  for brief in "$RESEARCH_DIR"/dex-*.md; do
    [[ -f "$brief" ]] || continue
    BRIEF_EPOCH=$(stat -f "%m" "$brief" 2>/dev/null || stat -c "%Y" "$brief" 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    BRIEF_AGE=$(( (NOW_EPOCH - BRIEF_EPOCH) / 86400 ))

    if [[ $BRIEF_AGE -le 7 ]]; then
      WEEKLY_BRIEFS=$((WEEKLY_BRIEFS + 1))
      echo "- $(basename "$brief") (${BRIEF_AGE}d old)" >> "$DEX_RESEARCH_LOG"
    fi
  done

  echo "" >> "$DEX_RESEARCH_LOG"
  echo "## Implementation Candidates" >> "$DEX_RESEARCH_LOG"
  echo "" >> "$DEX_RESEARCH_LOG"
  echo "Findings scored APPLICABLE will appear here after Kai interactive review." >> "$DEX_RESEARCH_LOG"
  echo "" >> "$DEX_RESEARCH_LOG"

  echo "### Weekly Brief Evaluation" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "- Briefs from this week: $WEEKLY_BRIEFS" >> "$REPORT"
  echo "- Research synthesis: $DEX_RESEARCH_LOG" >> "$REPORT"
  echo "" >> "$REPORT"

  # ---- 6B.2: Submit deep-dive research request (more specific than daily) ----
  # Scan last 7 days of research requests to find patterns
  STANDING_DEEP_TOPICS=(
    "JSONL validation: schema evolution patterns for append-only agent logs — compare current python3 json.tool approach against jsonschema, pydantic, or Zod-based validation"
    "Compaction: integrity-preserving archival with rollback for JSONL ledgers — evaluate write-ahead logging, CRC32 checksums, and atomic rename patterns"
    "Pattern detection: anomaly detection in multi-agent log streams — compare rule-based vs statistical approaches for our scale (100-1000 entries/day)"
    "Audit trails: SOC2/ISO27001 patterns applicable to agent memory systems — what's the minimum viable audit trail for a multi-agent system"
    "Agentic memory: how production multi-agent systems handle recall and context — survey LangGraph, CrewAI, AutoGen memory architectures"
  )

  WEEK_INDEX=$(( $(date +%V) % ${#STANDING_DEEP_TOPICS[@]} ))
  DEEP_TOPIC="${STANDING_DEEP_TOPICS[$WEEK_INDEX]}"

  if [[ -f "$DISPATCH_SH" ]]; then
    bash "$DISPATCH_SH" delegate ra P2 "[RESEARCH-REQ] Dex $WEEK_NUM deep-dive: $DEEP_TOPIC" 2>/dev/null || true
    log_pass "6B.2: Weekly deep-dive request dispatched to Ra"
  fi

  echo "### Deep-Dive Research Request" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "- Topic: $DEEP_TOPIC" >> "$REPORT"
  echo "- Priority: P2 (higher than daily P3)" >> "$REPORT"
  echo "" >> "$REPORT"

  # ---- 6B.3: Check implementation task pipeline ----
  DEX_RESEARCH_TASKS=0
  if [[ -f "$KAI_TASKS" ]]; then
    DEX_RESEARCH_TASKS=$(grep -c "\[RESEARCH\].*[Dd]ex" "$KAI_TASKS" 2>/dev/null || echo "0")
  fi

  echo "### Implementation Pipeline" >> "$REPORT"
  echo "" >> "$REPORT"
  echo "- Active [RESEARCH] tasks for Dex: $DEX_RESEARCH_TASKS" >> "$REPORT"
  echo "- Pending Kai review: check KAI_TASKS.md [RESEARCH] section" >> "$REPORT"
  echo "" >> "$REPORT"

  # Self-idle check: has Dex produced any research output in 21 days?
  LAST_RESEARCH_OUTPUT=$(ls -t "$DEX_LOGS"/research-*.md 2>/dev/null | head -1)
  if [[ -n "$LAST_RESEARCH_OUTPUT" ]]; then
    RESEARCH_EPOCH=$(stat -f "%m" "$LAST_RESEARCH_OUTPUT" 2>/dev/null || stat -c "%Y" "$LAST_RESEARCH_OUTPUT" 2>/dev/null || echo "0")
    RESEARCH_AGE=$(( ($(date +%s) - RESEARCH_EPOCH) / 86400 ))
    if [[ $RESEARCH_AGE -gt 21 ]]; then
      dispatch_flag "P2" "Dex research idle: no synthesis output in ${RESEARCH_AGE}d"
      log_warn "Self-check: Dex research idle for ${RESEARCH_AGE}d"
    fi
  fi

  log_activity "PHASE_6B_DEEP_RESEARCH" "completed" "Weekly briefs: $WEEKLY_BRIEFS, deep-dive dispatched, pipeline: $DEX_RESEARCH_TASKS tasks"
  log_pass "Phase 6B complete: Weekly synthesis done"
else
  log_info "Phase 6B: Skipped (deep synthesis runs Monday only, today is day $DOW)"
fi

# ============================================================================
# SELF-REVIEW: Dex Pathway Audit
# ============================================================================
log_info "Self-review: Dex pathway audit..."
SR_ISSUES=0

# INPUT: Are JSONL ledger files accessible?
for jfile in "$ROOT/kai/ledger/log.jsonl" "$ROOT/agents/nel/ledger/log.jsonl" "$ROOT/agents/sam/ledger/log.jsonl" "$ROOT/agents/ra/ledger/log.jsonl"; do
  if [[ ! -f "$jfile" ]]; then
    log_warn "Self-review: missing ledger file: $jfile"
    SR_ISSUES=$((SR_ISSUES + 1))
  fi
done

# PROCESSING: Did integrity checks complete?
if [[ -z "${INTEGRITY_PASS:-}" ]]; then
  log_warn "Self-review: integrity check variable not set"
  SR_ISSUES=$((SR_ISSUES + 1))
fi

# OUTPUT: Is report file valid?
if [[ -f "$REPORT" ]]; then
  rsize=$(wc -c < "$REPORT" 2>/dev/null || echo 0)
  if [[ $rsize -lt 100 ]]; then
    log_warn "Self-review: report file suspiciously small (${rsize}B)"
    SR_ISSUES=$((SR_ISSUES + 1))
  fi
else
  log_warn "Self-review: report file not generated"
  SR_ISSUES=$((SR_ISSUES + 1))
fi

# REPORTING: ACTIVE.md current?
DEX_ACTIVE="$ROOT/agents/dex/ledger/ACTIVE.md"
if [[ -f "$DEX_ACTIVE" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    dex_mtime=$(stat -f %m "$DEX_ACTIVE" 2>/dev/null || echo 0)
  else
    dex_mtime=$(stat -c %Y "$DEX_ACTIVE" 2>/dev/null || echo 0)
  fi
  dex_age_h=$(( ($(date +%s) - dex_mtime) / 3600 ))
  if [[ $dex_age_h -gt 48 ]]; then
    log_warn "Self-review: ACTIVE.md stale (${dex_age_h}h)"
    SR_ISSUES=$((SR_ISSUES + 1))
  fi
fi

if [[ $SR_ISSUES -eq 0 ]]; then
  log_pass "Self-review: Dex pathway healthy"
else
  log_warn "Self-review: $SR_ISSUES issues in Dex pathway"
fi

# ============================================================================
# SELF-REVIEW REASONING GATES
# ============================================================================
AGENT_GATES="$ROOT/kai/protocols/agent-gates.sh"
if [[ -f "$AGENT_GATES" ]]; then
  source "$AGENT_GATES"
  run_self_review "dex" || true

  # ── Dex-specific domain reasoning (Dex owns these questions) ──
  # TODO: Dex — evolve this section via PLAYBOOK.md
  #   e.g., "Is my ledger consistent or has drift crept in?"
  #   e.g., "Are compaction patterns still valid for current data volume?"
  #   e.g., "What integrity check am I NOT running that I should be?"
fi

# ============================================================================
# DOMAIN RESEARCH (External Research — agent-research.sh)
# Dex researches data integrity patterns, event sourcing, agent memory architectures.
# ============================================================================
RESEARCH_SCRIPT="$ROOT/bin/agent-research.sh"
if [[ -x "$RESEARCH_SCRIPT" ]]; then
  log_info "Running domain research: data integrity, event sourcing, memory patterns..."
  if bash "$RESEARCH_SCRIPT" dex --publish 2>&1 | tail -5; then
    log_pass "Domain research complete — findings saved and published"
  else
    log_warn "Domain research encountered issues — check agents/dex/research/"
  fi
fi

# ============================================================================
# SELF-EVOLUTION: Dex Learning & Improvement Tracking
# ============================================================================
log_info "Self-evolution: capturing metrics and learning signals..."

EVOLUTION_FILE="$ROOT/agents/dex/evolution.jsonl"
PLAYBOOK="$ROOT/agents/dex/PLAYBOOK.md"

# Collect Dex-specific metrics
INTEGRITY_PASS=${INTEGRITY_PASS:-0}
INTEGRITY_FAIL=${INTEGRITY_FAIL:-0}
STALE_COUNT=${STALE_COUNT:-0}
PATTERNS_FOUND=${PATTERNS_FOUND:-0}

# Get last evolution entry for comparison
LAST_EVOLUTION=""
if [[ -f "$EVOLUTION_FILE" && -s "$EVOLUTION_FILE" ]]; then
  LAST_EVOLUTION=$(tail -1 "$EVOLUTION_FILE")
fi

# Extract last integrity metrics for regression detection
LAST_INTEGRITY_FAIL=0
if [[ -n "$LAST_EVOLUTION" ]]; then
  LAST_INTEGRITY_FAIL=$(echo "$LAST_EVOLUTION" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('metrics', {}).get('integrity_fail', 0))" 2>/dev/null || echo "0")
fi

# Determine assessment
ASSESSMENT="daily memory maintenance completed"
IMPROVEMENTS_PROPOSED=0
if [[ $INTEGRITY_FAIL -gt $LAST_INTEGRITY_FAIL ]]; then
  ASSESSMENT="integrity issues increased: $LAST_INTEGRITY_FAIL → $INTEGRITY_FAIL corrupt JSONL entries"
  IMPROVEMENTS_PROPOSED=$((IMPROVEMENTS_PROPOSED + 1))
elif [[ $INTEGRITY_FAIL -lt $LAST_INTEGRITY_FAIL && $LAST_INTEGRITY_FAIL -gt 0 ]]; then
  ASSESSMENT="integrity improved: $LAST_INTEGRITY_FAIL → $INTEGRITY_FAIL corrupt entries fixed"
  IMPROVEMENTS_PROPOSED=$((IMPROVEMENTS_PROPOSED + 1))
fi

if [[ $PATTERNS_FOUND -gt 0 ]]; then
  if [[ -z "$ASSESSMENT" ]] || [[ "$ASSESSMENT" == "daily memory maintenance completed" ]]; then
    ASSESSMENT="pattern detection: $PATTERNS_FOUND recurrent issues found"
  fi
  IMPROVEMENTS_PROPOSED=$((IMPROVEMENTS_PROPOSED + 1))
fi

# Check if PLAYBOOK is stale (>7 days)
PLAYBOOK_UPDATED=false
STALENESS_FLAG=false
if [[ -f "$PLAYBOOK" ]]; then
  PLAYBOOK_MTIME=$(stat -f %m "$PLAYBOOK" 2>/dev/null || stat -c %Y "$PLAYBOOK" 2>/dev/null || echo "0")
  PLAYBOOK_AGE=$(( ($(date +%s) - PLAYBOOK_MTIME) / 86400 ))
  if [[ $PLAYBOOK_AGE -lt 7 ]]; then
    PLAYBOOK_UPDATED=true
  elif [[ $PLAYBOOK_AGE -gt 7 ]]; then
    STALENESS_FLAG=true
  fi
fi

# STEP 10: AGENT REFLECTION (constitutional — AGENT_ALGORITHMS.md v2.0)
REFLECT_BOTTLENECK="none"
REFLECT_SYMPTOM_OR_SYSTEM="system"
REFLECT_ARTIFACT_ALIVE="yes"
REFLECT_DOMAIN_GROWTH="stagnant"
REFLECT_LEARNING=""

# (a) Bottleneck: integrity failures = Dex detecting but not auto-repairing
if [[ $INTEGRITY_FAIL -gt 0 ]]; then
  REFLECT_BOTTLENECK="detected ${INTEGRITY_FAIL} corrupt JSONL entries — check if auto-repair ran or just flagged"
fi

# (b) Symptom or system: recurring patterns getting re-flagged
if [[ $PATTERNS_FOUND -gt 10 ]]; then
  REFLECT_SYMPTOM_OR_SYSTEM="symptom — ${PATTERNS_FOUND} recurrent patterns suggests prior fixes didn't address root causes"
fi

# (c) Artifact alive: self-review log
SR_LOG="$ROOT/agents/dex/logs/self-review-$(date +%Y-%m-%d).md"
if [[ ! -f "$SR_LOG" ]]; then
  REFLECT_ARTIFACT_ALIVE="no — self-review log not generated this cycle"
fi

# (d) Domain growth
if [[ "$PLAYBOOK_UPDATED" == "true" ]]; then
  REFLECT_DOMAIN_GROWTH="active — PLAYBOOK updated within 7 days"
else
  REFLECT_DOMAIN_GROWTH="stagnant — PLAYBOOK not updated in ${PLAYBOOK_AGE:-unknown}d, no new integrity patterns"
fi

# (e) Learning
REFLECT_LEARNING="integrity=${INTEGRITY_PASS}p/${INTEGRITY_FAIL}f, stale=${STALE_COUNT}, patterns=${PATTERNS_FOUND}"

# Build evolution entry (MUST include reflection per AGENT_ALGORITHMS.md step 11)
EVOLUTION_ENTRY=$(python3 << PYEOF
import json
from datetime import datetime
import sys

entry = {
  "ts": "$NOW_ISO",
  "version": "2.0",
  "metrics": {
    "integrity_pass": $INTEGRITY_PASS,
    "integrity_fail": $INTEGRITY_FAIL,
    "stale_count": $STALE_COUNT,
    "patterns_found": $PATTERNS_FOUND
  },
  "assessment": "$ASSESSMENT",
  "improvements_proposed": $IMPROVEMENTS_PROPOSED,
  "playbook_updated": $([ "$PLAYBOOK_UPDATED" = "true" ] && echo "True" || echo "False"),
  "staleness_flag": $([ "$STALENESS_FLAG" = "true" ] && echo "True" || echo "False"),
  "reflection": {
    "bottleneck": "$REFLECT_BOTTLENECK",
    "symptom_or_system": "$REFLECT_SYMPTOM_OR_SYSTEM",
    "artifact_alive": "$REFLECT_ARTIFACT_ALIVE",
    "domain_growth": "$REFLECT_DOMAIN_GROWTH",
    "learning": "$REFLECT_LEARNING"
  }
}

print(json.dumps(entry))
PYEOF
)

# Append to evolution ledger
echo "$EVOLUTION_ENTRY" >> "$EVOLUTION_FILE"
log_pass "Self-evolution logged: $ASSESSMENT"

if [[ "$STALENESS_FLAG" == "True" ]]; then
  log_warn "PLAYBOOK.md is stale — consider refreshing with latest operational procedures"
fi

# ── Dex self-authored reflection → HQ feed ──
PUBLISH_SCRIPT="$ROOT/bin/publish-to-feed.sh"
DEX_REFLECTION="/tmp/dex-reflection-sections-$(date +%Y%m%d).json"

python3 - "$DEX_REFLECTION" "${INTEGRITY_PASS:-0}" "${INTEGRITY_FAIL:-0}" \
          "${STALE_COUNT:-0}" "${PATTERN_COUNT:-0}" "$ASSESSMENT" "$ROOT" << 'PYEOF'
import json, sys, os
sf = sys.argv[1]
i_pass = int(sys.argv[2]) if sys.argv[2].isdigit() else 0
i_fail = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
stale = int(sys.argv[4]) if sys.argv[4].isdigit() else 0
patterns = int(sys.argv[5]) if sys.argv[5].isdigit() else 0
assess = sys.argv[6]
root = sys.argv[7]
from datetime import datetime
today = datetime.now().strftime("%Y-%m-%d")

research_summary = "No research conducted this cycle."
ff = os.path.join(root, "agents", "dex", "research", f"findings-{today}.md")
if os.path.exists(ff):
    with open(ff) as f:
        c = f.read()
    if "## Key Takeaways" in c:
        t = c.split("## Key Takeaways")[1].split("##")[0].strip()
        research_summary = t if t else "Research completed — no high-signal findings."

followups = []
src = os.path.join(root, "agents", "dex", "research-sources.json")
if os.path.exists(src):
    with open(src) as f:
        cfg = json.load(f)
    followups = [fu["item"] for fu in cfg.get("followUps", []) if fu.get("status") == "open"]
if not followups:
    followups = ["Evaluate auto-repair for corrupt JSONL entries",
                 "Research cross-agent dependency graph patterns",
                 "Investigate predictive staleness detection"]

# ── Build human-readable prose ──
total_files = i_pass + i_fail
intro_parts = []
if total_files == 0:
    intro_parts.append("Quiet cycle — no ledger files were scanned, which probably means the runner exited early or there's a path issue.")
elif i_fail == 0:
    intro_parts.append(f"Clean sweep. Validated all {i_pass} ledger files and everything parsed correctly. The organization's data is in good shape.")
else:
    intro_parts.append(f"Scanned {total_files} files. {i_pass} are clean, but {i_fail} {'has' if i_fail == 1 else 'have'} integrity problems — corrupt entries, malformed JSON lines, or structural issues that need repair.")

if stale > 0:
    intro_parts.append(f"Also found {stale} stale task{'s' if stale > 1 else ''} that {'have' if stale > 1 else 'has'} been sitting open for more than 72 hours. Stale tasks usually mean something got stuck or forgotten.")
if patterns > 0:
    if patterns > 10:
        intro_parts.append(f"I'm tracking {patterns} recurrent patterns in the issue logs. That's too many unresolved — the same bugs keep reappearing, which means we're treating symptoms instead of root causes.")
    else:
        intro_parts.append(f"Tracking {patterns} recurrent pattern{'s' if patterns > 1 else ''} across the system. Keeping an eye on whether these resolve or get worse.")

research_text = research_summary
if research_text == "No research conducted this cycle.":
    research_text = "No external research this cycle. When I do research, I'm looking at data engineering patterns — append-only logs, event sourcing, JSONL best practices — anything that helps me do a better job as the system's memory guardian."

changes_text = ""
if i_fail > 0:
    changes_text = f"Completed the integrity sweep and flagged {i_fail} file{'s' if i_fail > 1 else ''} for repair. {'Also identified' if stale > 0 else 'No'} stale tasks{f' — {stale} items need attention' if stale > 0 else ' this cycle'}."
else:
    changes_text = f"Ran the full integrity sweep across {i_pass} files — everything is clean. {'Found ' + str(stale) + ' stale tasks that need follow-up.' if stale > 0 else 'No stale tasks or integrity issues.'}"

kai_msg = ""
if i_fail > 0:
    kai_msg = f"We have {i_fail} corrupted ledger file{'s' if i_fail > 1 else ''} that need repair. If left alone, this could cause downstream issues when other agents try to read their history. I'll attempt auto-repair next cycle."
elif patterns > 10:
    kai_msg = f"{patterns} recurrent patterns is a lot. We're accumulating unresolved issues faster than we're fixing them. Might need a dedicated cleanup sprint."
elif stale > 0:
    kai_msg = f"{stale} stale task{'s' if stale > 1 else ''} in the system. Not urgent, but worth a quick review to see if {'they' if stale > 1 else 'it'} can be closed or reassigned."
else:
    kai_msg = "Data layer is healthy. All ledgers parse correctly, no corruption, no stale tasks. I'm doing my job."

sections = {
    "introspection": " ".join(intro_parts),
    "research": research_text,
    "changes": changes_text,
    "followUps": followups[:5],
    "forKai": kai_msg
}
with open(sf, "w") as f:
    json.dump(sections, f, indent=2)
PYEOF

if [[ -f "$DEX_REFLECTION" && -x "$PUBLISH_SCRIPT" ]]; then
  bash "$PUBLISH_SCRIPT" "agent-reflection" "dex" "Dex — Data Integrity Report" "$DEX_REFLECTION" 2>/dev/null || true
  log_pass "Self-authored report published to HQ feed"
fi

# ============================================================================
# STEP 13: MEMORY UPDATE (constitutional — AGENT_ALGORITHMS.md)
# ============================================================================
DEX_ACTIVE="$ROOT/agents/dex/ledger/ACTIVE.md"
mkdir -p "$(dirname "$DEX_ACTIVE")"
cat > "$DEX_ACTIVE" << ACTIVEEOF
# Dex — Active Tasks (auto-updated every cycle)
**Last updated:** $(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

## This Cycle
- Integrity: ${INTEGRITY_PASS} files validated, ${INTEGRITY_FAIL} issues
- Stale tasks: ${STALE_COUNT} (>72h)
- Recurrent patterns: ${PATTERNS_FOUND}
- Assessment: ${ASSESSMENT}
- Status: ${STATUS}

## Open Issues
$(if [[ ${INTEGRITY_FAIL:-0} -gt 0 ]]; then echo "- ${INTEGRITY_FAIL} integrity failures need repair"; fi)
$(if [[ ${STALE_COUNT:-0} -gt 0 ]]; then echo "- ${STALE_COUNT} stale tasks need attention"; fi)
$(if [[ "$STALENESS_FLAG" == "True" ]]; then echo "- PLAYBOOK.md is stale"; fi)

## Reflection Summary
- Bottleneck: ${REFLECT_BOTTLENECK}
- Domain growth: ${REFLECT_DOMAIN_GROWTH}
ACTIVEEOF
log_pass "Memory update: ACTIVE.md written"

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
