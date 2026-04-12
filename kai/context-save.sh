#!/usr/bin/env bash
#
# kai/context-save.sh
#
# Kai's session context snapshot. Captures current state, open tasks, and agent
# status into a timestamped markdown file. Fast (<5 seconds) and non-destructive.
#
# This is NOT a project consolidation. It's a Kai-private recovery mechanism
# to ensure continuity across context windows and device switches without
# redundancy or double-logging.
#
# Usage:
#   kai context-save
#   kai context-save --date 2026-04-12-1430
#
# Outputs:
#   kai/context/YYYY-MM-DD-HHMM.md  (timestamped snapshot)
#   kai/context/LATEST.md           (symlink/copy to newest)

set -euo pipefail

# ---- repo root detection ------------------------------------------------
if [[ -n "${HYO_ROOT:-}" ]] && [[ -d "$HYO_ROOT" ]]; then
  ROOT="$HYO_ROOT"
else
  ROOT="$HOME/Documents/Projects/Hyo"
fi

CONTEXT_DIR="$ROOT/kai/context"
BRIEF="$ROOT/KAI_BRIEF.md"
TASKS="$ROOT/KAI_TASKS.md"
LOGS="$ROOT/kai/logs"
CONSOLIDATION="$ROOT/kai/consolidation"

# ---- setup ------
mkdir -p "$CONTEXT_DIR"

# Timestamp: use arg if provided, else now
if [[ -n "${2:-}" ]]; then
  TSTAMP="$2"
else
  TSTAMP=$(date -u +%Y-%m-%d-%H%M)
fi

OUTFILE="$CONTEXT_DIR/$TSTAMP.md"

# ---- color helpers ------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); BLU=$(tput setaf 4); GRN=$(tput setaf 2); RST=$(tput sgr0)
else
  BOLD=""; DIM=""; BLU=""; GRN=""; RST=""
fi

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s==>%s %s%s%s\n' "$BLU" "$RST" "$BOLD" "$*" "$RST"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }

# ---- extract current state from KAI_BRIEF ------
extract_brief_state() {
  if [[ ! -f "$BRIEF" ]]; then
    say "(KAI_BRIEF not found)"
    return 0
  fi
  # Extract "Current state" block (multiple sections)
  # Strategy: read from "## Current state" lines through the next "##" line
  awk '
    /^## Current state/ { in_state=1; next }
    in_state && /^##/ && !/^## Current state/ { exit }
    in_state { print }
  ' "$BRIEF" | head -c 1024 | sed 's/^/  /'
}

# ---- count tasks by priority ------
count_tasks() {
  if [[ ! -f "$TASKS" ]]; then
    say "(KAI_TASKS not found)"
    return 0
  fi
  local section="" p0=0 p1=0 p2=0 p3=0 done_count=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ P[0-9] ]]; then
      section="$(echo "$line" | grep -oE 'P[0-9]')"
    elif [[ "$line" =~ ^##\ Done ]]; then
      section="Done"
    elif [[ "$line" =~ ^\-\ \[\ \] ]]; then
      case "$section" in
        P0) ((p0++)) ;;
        P1) ((p1++)) ;;
        P2) ((p2++)) ;;
        P3) ((p3++)) ;;
      esac
    elif [[ "$line" =~ ^\-\ \[x\] ]]; then
      ((done_count++))
    fi
  done < "$TASKS"
  say "  P0: $p0 | P1: $p1 | P2: $p2 | P3: $p3 | Done: $done_count"
}

# ---- scan recent logs ------
scan_agent_logs() {
  local agent="$1" pattern="$2"
  if [[ ! -d "$LOGS" ]]; then
    say "  (no logs dir)"
    return 0
  fi
  local latest
  latest=$(find "$LOGS" -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  if [[ -n "$latest" ]]; then
    local age
    age=$(( ($(date +%s) - $(stat -L -c %Y "$latest" 2>/dev/null || stat -L -f %m "$latest" 2>/dev/null || date +%s)) / 60 ))
    local filename
    filename=$(basename "$latest")
    say "  $agent: $filename (${age}m ago)"
  else
    say "  $agent: no logs yet"
  fi
}

# ---- scan per-project task summaries ------
project_task_summary() {
  if [[ ! -d "$CONSOLIDATION" ]]; then
    say "  (no consolidation dir)"
    return 0
  fi
  for proj_dir in "$CONSOLIDATION"/*; do
    [[ ! -d "$proj_dir" ]] && continue
    local proj
    proj=$(basename "$proj_dir")
    local tasks_file="$proj_dir/tasks.md"
    if [[ ! -f "$tasks_file" ]]; then
      say "  $proj: (no tasks.md)"
      continue
    fi
    local open closed
    open=$(grep -c '^\- \[ \]' "$tasks_file" 2>/dev/null || echo 0)
    closed=$(grep -c '^\- \[x\]' "$tasks_file" 2>/dev/null || echo 0)
    say "  $proj: $open open, $closed done"
  done
}

# ---- main ------
hdr "Building Kai context snapshot"

say "Timestamp: $TSTAMP"
say "Output: $OUTFILE"
echo

# ---- build snapshot ------
{
  cat <<'HEADER'
# Kai Context Snapshot

**This is NOT a project consolidation.** This is Kai's private session-recovery mechanism.
Use this file to pick up where you left off in a previous session without redundancy or re-reading.

HEADER

  say "**Snapshot time:** $TSTAMP"
  say "**Generated:** $(date -u +%Y-%m-%dT%H:%M:%SZ) (UTC)"
  say

  hdr "KAI_BRIEF Current State"
  extract_brief_state
  echo

  hdr "KAI_TASKS Summary"
  say "Task counts by priority:"
  count_tasks
  echo

  hdr "Agent Logs (most recent)"
  say "Recent activity from defense agents:"
  scan_agent_logs "Sentinel" "sentinel-*.log"
  scan_agent_logs "Cipher" "cipher-*.log"
  scan_agent_logs "Ra/Aurora" "aurora-*.log"
  scan_agent_logs "Consolidation" "consolidation-*.log"
  echo

  hdr "Per-Project Task Status"
  say "Open vs done tasks per project (from consolidation/*/tasks.md):"
  project_task_summary
  echo

  hdr "How to Recover"
  cat <<'RECOVERY'

If you're reading this in a new session:

1. You're reading LATEST.md, which was auto-updated to point to this snapshot.
2. Next, read these files in order:
   - KAI_BRIEF.md (full persistent memory)
   - KAI_TASKS.md (complete task queue)
   - NFT/HyoRegistry_Notes.md (architecture reference)
3. Check the "Agent Logs" section above for what's been happening.
4. See "Per-Project Task Status" to understand where each project stands.
5. Answer: What shipped? What's next? What should I focus on in the next 15 minutes?

This snapshot is <5 seconds to generate and is meant to be lightweight. The full state
lives in KAI_BRIEF.md (session continuity), KAI_TASKS.md (priority queue), and
kai/consolidation/ (per-project history compounding). This file is just the fast bridge.

RECOVERY

} > "$OUTFILE"

ok "snapshot written to $OUTFILE"

# ---- update LATEST symlink/copy ------
latest_link="$CONTEXT_DIR/LATEST.md"
if [[ -f "$latest_link" ]] || [[ -L "$latest_link" ]]; then
  rm -f "$latest_link"
fi
# On systems where symlinks may not work, use a copy instead
if ln -s "$(basename "$OUTFILE")" "$latest_link" 2>/dev/null; then
  ok "updated symlink: LATEST.md -> $(basename "$OUTFILE")"
else
  # Fallback to copy if symlink fails
  cp "$OUTFILE" "$latest_link"
  ok "updated copy: LATEST.md (symlink failed, using copy)"
fi

echo
say "Use: ${BOLD}kai recover${RST} to view the latest snapshot"
say "Or:  ${BOLD}cat $latest_link${RST}"
