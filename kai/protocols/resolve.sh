#!/usr/bin/env bash
# kai/protocols/resolve.sh — Resolution Algorithm executor
#
# Called by agents and healthcheck when an issue is detected.
# Enforces the full RA-1 loop: recall → identify → analyze → fix → verify → simulate → report.
#
# Usage:
#   bash kai/protocols/resolve.sh init "<issue description>"
#     → Creates a new resolution file, runs RECALL (Step 0), outputs RES-ID
#
#   bash kai/protocols/resolve.sh update <RES-ID> <step> "<content>"
#     → Appends to an in-progress resolution (steps: identify, rootcause, tasks, execute, verify, simulate, report)
#
#   bash kai/protocols/resolve.sh close <RES-ID>
#     → Finalizes: validates all steps complete, updates system memory, commits
#
#   bash kai/protocols/resolve.sh recall "<keyword>"
#     → Searches past resolutions for prior art
#
#   bash kai/protocols/resolve.sh status [RES-ID]
#     → Shows resolution progress (which steps done/pending)
#
#   bash kai/protocols/resolve.sh list
#     → Lists all resolutions with status

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
RES_DIR="$ROOT/kai/ledger/resolutions"
PROTOCOL_DIR="$ROOT/kai/protocols"
KNOWN_ISSUES="$ROOT/kai/ledger/known-issues.jsonl"
PROTO_EVOLUTION="$PROTOCOL_DIR/evolution.jsonl"

mkdir -p "$RES_DIR"

NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)

log() { echo "[resolve] $*"; }

# Get next resolution ID
next_id() {
  local last
  last=$(ls "$RES_DIR"/RES-*.md 2>/dev/null | sort -V | tail -1 | grep -oE '[0-9]+' | tail -1)
  if [[ -z "$last" ]]; then
    echo "001"
  else
    printf "%03d" $((10#$last + 1))
  fi
}

# ── INIT: Create new resolution, run recall ──
cmd_init() {
  local description="$1"
  local id
  id="RES-$(next_id)"
  local file="$RES_DIR/${id}.md"

  log "Initializing $id"

  # STEP 0: RECALL — search for prior art
  log "Step 0: Recall — searching prior art..."
  local recall_output
  recall_output=$(python3 "$PROTOCOL_DIR/recall.py" "$description" 2>/dev/null || echo "Recall system unavailable")

  cat > "$file" << RESEOF
# Resolution $id

**Date:** $NOW_MT
**Status:** IN-PROGRESS
**Reporter:** (pending)
**Agent:** (pending)

---

## Step 0: Recall (Prior Art)

$recall_output

---

## Step 1: Identify

**Issue:** $description
**Expected behavior:** (pending)
**Actual behavior:** (pending)
**Impact:** (pending)
**Class of failure:** (pending)

---

## Step 2: Root Cause Analysis

(pending)

---

## Step 3: Actionable Tasks

(pending)

---

## Step 4: Execution Log

(pending)

---

## Step 5: Verification Results

(pending)

---

## Step 6: Simulation Results

(pending)

---

## Step 7: Resolution Summary

**What worked:** (pending)
**What failed:** (pending)
**Process improvements:** (pending)
**Prevention:** (pending)

**Tags:** (pending)

---

## Step 8: System Memory Updates

(pending)

---

## Step 9: Closure

(pending)
RESEOF

  log "Created $file"
  log "Prior art search complete"
  echo "$id"
}

# ── UPDATE: Append to a specific step ──
cmd_update() {
  local id="$1"
  local step="$2"
  local content="$3"
  local file="$RES_DIR/${id}.md"

  if [[ ! -f "$file" ]]; then
    log "ERROR: $id not found at $file"
    return 1
  fi

  # Map step names to section headers
  local section=""
  case "$step" in
    identify)   section="## Step 1: Identify" ;;
    rootcause)  section="## Step 2: Root Cause Analysis" ;;
    tasks)      section="## Step 3: Actionable Tasks" ;;
    execute)    section="## Step 4: Execution Log" ;;
    verify)     section="## Step 5: Verification Results" ;;
    simulate)   section="## Step 6: Simulation Results" ;;
    report)     section="## Step 7: Resolution Summary" ;;
    memory)     section="## Step 8: System Memory Updates" ;;
    *)
      log "ERROR: Unknown step '$step'. Valid: identify, rootcause, tasks, execute, verify, simulate, report, memory"
      return 1
      ;;
  esac

  # Replace (pending) under the section with actual content
  python3 - "$file" "$section" "$content" << 'PYEOF'
import sys

filepath = sys.argv[1]
section = sys.argv[2]
content = sys.argv[3]

with open(filepath) as f:
    lines = f.readlines()

output = []
in_section = False
replaced = False

for i, line in enumerate(lines):
    if line.strip() == section:
        in_section = True
        output.append(line)
        continue

    if in_section and not replaced:
        # Skip blank lines after section header
        if line.strip() == "" and not replaced:
            output.append(line)
            continue
        if line.strip() == "(pending)":
            # Replace (pending) with actual content
            output.append(content + "\n\n")
            replaced = True
            in_section = False
            continue
        elif line.startswith("## ") or line.startswith("---"):
            # Section ended without finding (pending), insert before next section
            output.append(content + "\n\n")
            replaced = True
            in_section = False
            output.append(line)
            continue
        else:
            # Content already exists — append to it
            output.append(line)
            if i + 1 < len(lines) and (lines[i + 1].startswith("---") or lines[i + 1].startswith("## ")):
                output.append("\n" + content + "\n")
                replaced = True
                in_section = False
            continue

    output.append(line)

# If we never found the section, append at end
if not replaced:
    output.append(f"\n{section}\n\n{content}\n")

with open(filepath, "w") as f:
    f.writelines(output)

print(f"Updated {section} in {filepath}")
PYEOF

  log "Updated $id → $step"
}

# ── CLOSE: Finalize resolution ──
cmd_close() {
  local id="$1"
  local file="$RES_DIR/${id}.md"

  if [[ ! -f "$file" ]]; then
    log "ERROR: $id not found"
    return 1
  fi

  # Check for incomplete steps
  local pending_count
  pending_count=$(grep -c "(pending)" "$file" 2>/dev/null | tr -d '[:space:]' || echo "0")
  pending_count=${pending_count:-0}

  if [[ "$pending_count" -gt 2 ]]; then
    log "WARNING: $id still has $pending_count pending sections. Complete them before closing."
    grep -n "(pending)" "$file"
    return 1
  fi

  # Update status to RESOLVED
  sed -i "s/\*\*Status:\*\* IN-PROGRESS/**Status:** RESOLVED/" "$file" 2>/dev/null || \
  python3 -c "
import sys
with open('$file') as f:
    c = f.read()
c = c.replace('**Status:** IN-PROGRESS', '**Status:** RESOLVED')
with open('$file','w') as f:
    f.write(c)
"

  # Append closure timestamp
  echo "" >> "$file"
  echo "**Closed:** $NOW_MT" >> "$file"

  log "$id marked RESOLVED"

  # Update system memory
  log "Updating known-issues.jsonl..."
  # Extract class and prevention from the report
  local class_of_failure
  class_of_failure=$(grep "Class of failure:" "$file" | head -1 | sed 's/.*Class of failure: *//' | sed 's/\*//g' || echo "unknown")
  local prevention
  prevention=$(grep "Prevention:" "$file" | head -1 | sed 's/.*Prevention: *//' || echo "see resolution report")

  if [[ -n "$class_of_failure" ]] && [[ "$class_of_failure" != "(pending)" ]]; then
    echo "{\"ts\":\"$NOW_MT\",\"type\":\"resolution\",\"source\":\"$id\",\"description\":\"RESOLVED: $class_of_failure\",\"status\":\"resolved\",\"prevention\":\"$prevention\"}" >> "$KNOWN_ISSUES"
  fi

  log "$id closed. Report: $file"
}

# ── RECALL: Search prior art ──
cmd_recall() {
  local keyword="$1"
  python3 "$PROTOCOL_DIR/recall.py" "$keyword"
}

# ── STATUS: Show resolution progress ──
cmd_status() {
  local id="${1:-}"

  if [[ -n "$id" ]]; then
    local file="$RES_DIR/${id}.md"
    if [[ ! -f "$file" ]]; then
      log "ERROR: $id not found"
      return 1
    fi
    echo "=== $id ==="
    grep "Status:" "$file" | head -1
    echo ""
    echo "Step completion:"
    for step in "Step 0" "Step 1" "Step 2" "Step 3" "Step 4" "Step 5" "Step 6" "Step 7" "Step 8" "Step 9"; do
      local section_line
      section_line=$(grep -A 3 "## $step" "$file" 2>/dev/null | tail -1)
      if echo "$section_line" | grep -q "(pending)"; then
        echo "  $step: ○ PENDING"
      else
        echo "  $step: ● DONE"
      fi
    done
  else
    # List all resolutions
    echo "=== All Resolutions ==="
    for f in "$RES_DIR"/RES-*.md; do
      [[ ! -f "$f" ]] && continue
      local rid
      rid=$(basename "$f" .md)
      local status
      status=$(grep "Status:" "$f" | head -1 | sed 's/.*Status:\*\* //')
      local issue
      issue=$(grep "Issue:" "$f" | head -1 | sed 's/.*Issue:\*\* //' | head -c 60)
      echo "  $rid [$status] $issue"
    done
  fi
}

# ── LIST: List all resolutions ──
cmd_list() {
  cmd_status ""
}

# ── MAIN ──
case "${1:-help}" in
  init)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: resolve.sh init \"<issue description>\""
      exit 1
    fi
    cmd_init "$2"
    ;;
  update)
    if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]] || [[ -z "${4:-}" ]]; then
      echo "Usage: resolve.sh update <RES-ID> <step> \"<content>\""
      echo "Steps: identify, rootcause, tasks, execute, verify, simulate, report, memory"
      exit 1
    fi
    cmd_update "$2" "$3" "$4"
    ;;
  close)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: resolve.sh close <RES-ID>"
      exit 1
    fi
    cmd_close "$2"
    ;;
  recall)
    if [[ -z "${2:-}" ]]; then
      echo "Usage: resolve.sh recall \"<keyword>\""
      exit 1
    fi
    cmd_recall "$2"
    ;;
  status)
    cmd_status "${2:-}"
    ;;
  list)
    cmd_list
    ;;
  help|*)
    echo "kai/protocols/resolve.sh — Resolution Algorithm (RA-1) executor"
    echo ""
    echo "Commands:"
    echo "  init   \"<description>\"              Create new resolution + recall prior art"
    echo "  update <ID> <step> \"<content>\"      Update a resolution step"
    echo "  recall \"<keyword>\"                  Search past resolutions"
    echo "  status [ID]                          Show progress"
    echo "  close  <ID>                          Finalize and update system memory"
    echo "  list                                 List all resolutions"
    echo ""
    echo "Steps: identify, rootcause, tasks, execute, verify, simulate, report, memory"
    ;;
esac
