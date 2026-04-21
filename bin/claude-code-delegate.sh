#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# claude-code-delegate.sh — Delegate coding tasks to Claude Code CLI
# Version: 1.0 — 2026-04-21
#
# This is the bridge between agent runners and Claude Code's full coding
# capability. Any agent can call this to have Claude Code autonomously:
#   - Read and understand files
#   - Implement fixes / features
#   - Write tests
#   - Commit changes
#
# Unlike the queue worker (which runs bash), Claude Code can reason about
# code, plan multi-step implementations, and self-verify.
#
# Usage:
#   source bin/claude-code-delegate.sh
#   claude_delegate --agent "sam" --task "Fix the broken regex in sentinel.sh line 204" \
#                   --files "agents/nel/sentinel.sh" \
#                   --ticket "nel-001" --priority "P1"
#
# Or as standalone:
#   bash bin/claude-code-delegate.sh --agent sam --task "..." --files "file1 file2"
#
# Output:
#   - Logs to kai/ledger/claude-delegate.log
#   - On success: commits changes, reports to dispatch
#   - On failure: opens P1 ticket, logs to known-issues
#
# Gate: Only runs if claude binary is found. Never blocks if unavailable.
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/claude-delegate.log"
DISPATCH_SH="$HYO_ROOT/bin/dispatch.sh"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"

mkdir -p "$(dirname "$LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }

# ─── Find claude binary ───────────────────────────────────────────────────
_find_claude_bin() {
  # Check explicit override first
  if [[ -n "${HYO_CLAUDE_BIN:-}" && -x "$HYO_CLAUDE_BIN" ]]; then
    echo "$HYO_CLAUDE_BIN"; return 0
  fi
  # Common install locations
  for candidate in \
    "$HOME/.npm-global/bin/claude" \
    "$HOME/.nvm/versions/node/$(node --version 2>/dev/null)/bin/claude" \
    "/usr/local/bin/claude" \
    "/opt/homebrew/bin/claude" \
    "$(which claude 2>/dev/null)"; do
    [[ -x "$candidate" ]] && echo "$candidate" && return 0
  done
  return 1
}

# ─── Main delegate function ───────────────────────────────────────────────
claude_delegate() {
  local agent="" task="" files="" ticket="" priority="P2" timeout=300
  local commit_after=true auto_dispatch=true dry_run=false

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent)     agent="$2";     shift 2 ;;
      --task)      task="$2";      shift 2 ;;
      --files)     files="$2";     shift 2 ;;
      --ticket)    ticket="$2";    shift 2 ;;
      --priority)  priority="$2";  shift 2 ;;
      --timeout)   timeout="$2";   shift 2 ;;
      --no-commit) commit_after=false; shift ;;
      --dry-run)   dry_run=true;   shift ;;
      *) shift ;;
    esac
  done

  [[ -z "$task" ]] && log "ERROR: --task required" && return 1
  [[ -z "$agent" ]] && agent="sam"

  # Find claude binary
  local claude_bin
  if ! claude_bin=$(_find_claude_bin); then
    log "SKIP: claude binary not found — install via: npm i -g @anthropic-ai/claude-code"
    return 0  # Non-fatal: system degrades gracefully without Claude Code
  fi

  log "DELEGATE [$priority] agent=$agent ticket=${ticket:-none}"
  log "  Task: $task"
  log "  Files: ${files:-none specified}"
  log "  Claude bin: $claude_bin"

  if [[ "$dry_run" == "true" ]]; then
    log "  DRY-RUN: would invoke claude with above task"
    return 0
  fi

  # ─── Build the prompt ────────────────────────────────────────────────────
  # Read file contents if specified
  local file_context=""
  if [[ -n "$files" ]]; then
    for f in $files; do
      local fpath="$HYO_ROOT/$f"
      if [[ -f "$fpath" ]]; then
        file_context+="
### File: $f
\`\`\`
$(cat "$fpath" 2>/dev/null | head -300)
\`\`\`
"
      fi
    done
  fi

  local prompt
  prompt=$(cat << PROMPT
You are Sam, the engineering agent for hyo.world. You are running autonomously on the Mini (macOS).

## Task
$task

## Context
- HYO_ROOT: $HOME/Documents/Projects/Hyo
- Agent: $agent
- Ticket: ${ticket:-none}
- Priority: $priority
- Timestamp: $NOW_MT

## Rules
1. Read the relevant files before making changes
2. Implement the fix completely — no partial work
3. Verify your changes work (run tests if they exist, check syntax)
4. Be conservative — only change what the task requires
5. After implementation, output a brief summary: what you changed, why, and verification result

## File Context
${file_context:-No specific files provided — read relevant files yourself based on the task.}

## Required output format
After completing the task, output exactly:
RESULT: SUCCESS or RESULT: FAILURE
CHANGED: <comma-separated list of files you modified>
SUMMARY: <one sentence of what you did>
PROMPT
)

  # ─── Run Claude Code ─────────────────────────────────────────────────────
  local output_file="$HYO_ROOT/kai/ledger/claude-delegate-output-$(date +%s).txt"
  local exit_code=0

  log "  Invoking Claude Code (timeout: ${timeout}s)..."

  # Use stdin to avoid argv length limits (same pattern as synthesize.py)
  echo "$prompt" | "$claude_bin" \
    -p \
    --output-format text \
    --dangerously-skip-permissions \
    > "$output_file" 2>&1 || exit_code=$?

  local output
  output=$(cat "$output_file" 2>/dev/null || echo "")

  # ─── Parse result ─────────────────────────────────────────────────────────
  local result_line changed_files summary_line
  result_line=$(echo "$output" | grep "^RESULT:" | tail -1 | sed 's/RESULT: //')
  changed_files=$(echo "$output" | grep "^CHANGED:" | tail -1 | sed 's/CHANGED: //')
  summary_line=$(echo "$output" | grep "^SUMMARY:" | tail -1 | sed 's/SUMMARY: //')

  if [[ $exit_code -eq 0 && "$result_line" == "SUCCESS" ]]; then
    log "  ✓ Claude Code completed successfully"
    log "  Changed: ${changed_files:-unknown}"
    log "  Summary: ${summary_line:-no summary}"

    # Auto-commit if changes were made
    if [[ "$commit_after" == "true" && -n "$changed_files" ]]; then
      cd "$HYO_ROOT" 2>/dev/null || true
      local commit_msg="fix($agent): ${summary_line:-Claude Code auto-fix} [ticket:${ticket:-auto}]"
      if git add -A 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
        log "  No git changes to commit"
      else
        git commit -m "$commit_msg" 2>/dev/null && \
          git push origin main 2>/dev/null && \
          log "  ✓ Committed and pushed: $commit_msg" || \
          log "  WARN: commit/push failed"
      fi
    fi

    # Close ticket if provided
    if [[ -n "$ticket" && -f "$TICKET_SH" ]]; then
      HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" update "$ticket" \
        --status "RESOLVED" \
        --note "Claude Code auto-resolved: $summary_line" 2>/dev/null || true
    fi

    # Report success to dispatch
    if [[ "$auto_dispatch" == "true" && -f "$DISPATCH_SH" ]]; then
      bash "$DISPATCH_SH" report "$agent" "completed" \
        "Claude Code resolved: $task — $summary_line" 2>/dev/null || true
    fi

    rm -f "$output_file"
    return 0

  else
    log "  ✗ Claude Code failed (exit=$exit_code result=${result_line:-none})"
    log "  Output tail: $(echo "$output" | tail -5)"

    # Open a ticket for human review
    if [[ -f "$TICKET_SH" ]]; then
      HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
        --agent "$agent" \
        --title "Claude Code delegate failed: $task" \
        --priority "$priority" \
        --type "bug" \
        --created-by "claude-code-delegate" 2>/dev/null || true
    fi

    # Save output for debugging
    mv "$output_file" "$HYO_ROOT/kai/ledger/claude-delegate-failed-$(date +%s).txt" 2>/dev/null || true
    return 1
  fi
}

# ─── Standalone entrypoint ────────────────────────────────────────────────
# When sourced, only the function is loaded.
# When run directly, execute with args.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  claude_delegate "$@"
fi
