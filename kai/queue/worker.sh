#!/usr/bin/env bash
# kai/queue/worker.sh — File-based command queue worker
#
# Watches kai/queue/pending/ for command files. Picks them up, executes,
# writes results to kai/queue/completed/ (or failed/).
#
# Command file format (JSON):
#   {"id":"cmd-001","ts":"...","command":"git push origin main","timeout":30,"agent":"kai"}
#
# Result file format (JSON):
#   {"id":"cmd-001","ts":"...","command":"...","exit_code":0,"stdout":"...","stderr":"...","duration_s":2.1}
#
# Usage:
#   bash kai/queue/worker.sh          # run once (process all pending)
#   bash kai/queue/worker.sh --watch  # continuous mode (fswatch)
#   bash kai/queue/worker.sh --daemon # background mode (launchd)

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
QUEUE="$ROOT/kai/queue"
PENDING="$QUEUE/pending"
RUNNING="$QUEUE/running"
COMPLETED="$QUEUE/completed"
FAILED="$QUEUE/failed"
LOG="$QUEUE/worker.log"

mkdir -p "$PENDING" "$RUNNING" "$COMPLETED" "$FAILED"

NOW_ISO() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log() { printf '[%s] %s\n' "$(NOW_ISO)" "$*" >> "$LOG"; }

# ---- Security: only allow commands from known safe patterns ----
# Block anything that could damage the system
is_safe_command() {
  local cmd="$1"

  # Block dangerous patterns
  if echo "$cmd" | grep -qiE 'rm -rf /|mkfs|dd if=|:(){ :|chmod -R 777|curl.*\|.*sh|wget.*\|.*sh'; then
    return 1
  fi

  # Block secret exfiltration
  if echo "$cmd" | grep -qiE 'cat.*secret|cat.*token|cat.*\.key|cat.*\.env|echo.*secret'; then
    return 1
  fi

  return 0
}

# ---- Process a single command file ----
process_command() {
  local cmd_file="$1"
  local basename=$(basename "$cmd_file")

  # Parse JSON
  local cmd_id=$(python3 -c "import json,sys; print(json.load(open('$cmd_file'))['id'])" 2>/dev/null)
  local command=$(python3 -c "import json,sys; print(json.load(open('$cmd_file'))['command'])" 2>/dev/null)
  local timeout=$(python3 -c "import json,sys; print(json.load(open('$cmd_file')).get('timeout',60))" 2>/dev/null)

  if [[ -z "$cmd_id" ]] || [[ -z "$command" ]]; then
    log "SKIP: invalid command file $basename"
    mv "$cmd_file" "$FAILED/$basename"
    return 1
  fi

  log "EXEC: [$cmd_id] $command (timeout: ${timeout}s)"

  # Security check
  if ! is_safe_command "$command"; then
    log "BLOCKED: [$cmd_id] command failed security check"
    python3 -c "
import json
result = {
  'id': '$cmd_id',
  'ts': '$(NOW_ISO)',
  'command': $(python3 -c "import json; print(json.dumps('$command'))"),
  'exit_code': -1,
  'stdout': '',
  'stderr': 'BLOCKED: command failed security check',
  'duration_s': 0
}
with open('$FAILED/$basename', 'w') as f:
  json.dump(result, f, indent=2)
" 2>/dev/null
    rm -f "$cmd_file"
    return 1
  fi

  # Move to running
  mv "$cmd_file" "$RUNNING/$basename"

  # Execute with timeout
  local start_time=$(date +%s)
  local stdout_file=$(mktemp)
  local stderr_file=$(mktemp)

  # Run in project root
  cd "$ROOT"
  timeout "${timeout}s" bash -c "$command" > "$stdout_file" 2> "$stderr_file"
  local exit_code=$?
  cd - > /dev/null

  local end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Read output (truncate to 10KB to keep files manageable)
  local stdout_content=$(head -c 10240 "$stdout_file" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
  local stderr_content=$(head -c 10240 "$stderr_file" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

  rm -f "$stdout_file" "$stderr_file"

  # Write result
  local dest_dir="$COMPLETED"
  [[ $exit_code -ne 0 ]] && dest_dir="$FAILED"

  # Build result JSON safely using python with file-based I/O
  local result_file="$dest_dir/$basename"
  python3 -c "
import json, sys

# Read the original command from the running file
try:
    with open('$RUNNING/$basename') as f:
        orig = json.load(f)
        command = orig.get('command', 'unknown')
except:
    command = 'unknown'

# Read stdout/stderr from temp-captured content
stdout = $stdout_content
stderr = $stderr_content

result = {
    'id': '$cmd_id',
    'ts': '$(NOW_ISO)',
    'command': command,
    'exit_code': $exit_code,
    'stdout': stdout,
    'stderr': stderr,
    'duration_s': $duration
}
with open('$result_file', 'w') as f:
    json.dump(result, f, indent=2)
" 2>/dev/null

  # Clean up running
  rm -f "$RUNNING/$basename"

  if [[ $exit_code -eq 0 ]]; then
    log "DONE: [$cmd_id] exit=0 (${duration}s)"
  else
    log "FAIL: [$cmd_id] exit=$exit_code (${duration}s)"
  fi
}

# ---- Main: process all pending commands ----
process_all() {
  local count=0
  for cmd_file in "$PENDING"/*.json; do
    [[ -f "$cmd_file" ]] || continue
    process_command "$cmd_file"
    count=$((count + 1))
  done

  if [[ $count -eq 0 ]]; then
    log "IDLE: no pending commands"
  else
    log "BATCH: processed $count commands"
  fi
}

# ---- Watch mode (continuous) ----
watch_mode() {
  log "WATCH: starting continuous mode"

  if ! command -v fswatch >/dev/null 2>&1; then
    log "FALLBACK: fswatch not found, using poll mode (5s interval)"
    while true; do
      process_all
      sleep 5
    done
  else
    # Process anything already pending
    process_all

    # Watch for new files
    fswatch -0 "$PENDING" | while read -d '' event; do
      # Small delay to let file finish writing
      sleep 0.5
      process_all
    done
  fi
}

# ---- Entry point ----
case "${1:-}" in
  --watch|--daemon)
    watch_mode
    ;;
  *)
    process_all
    ;;
esac
