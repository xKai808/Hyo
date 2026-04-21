#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# protocol-staleness-check.sh — Prevents protocols from going stale
# Version: 1.0 — 2026-04-21
#
# Problem: Protocols accumulate, are never reviewed, become stale rules
# that agents follow even when the system has evolved past them.
#
# Solution: Every protocol must have a "# Last reviewed:" header.
# This script checks every .md file in kai/protocols/ and agents/*/
# PLAYBOOK.md, PRIORITIES.md, GROWTH.md, PROTOCOL_*.md files.
# If a file is >30 days since last review → opens a P2 ticket.
# If >60 days → P1 ticket. If >90 days → P0 ticket.
# If a file has NO "Last reviewed" header → writes one dated today and flags.
#
# Runs daily at 09:00 MT via kai-autonomous.sh.
# Also runs weekly at 06:00 MT Saturday in the weekly-report.sh block.
#
# Log: kai/ledger/protocol-staleness.log
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/protocol-staleness.log"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"

mkdir -p "$(dirname "$LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
TODAY_EPOCH=$(TZ=America/Denver date +%s)

log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_section() { echo "" >> "$LOG"; echo "═══ $* ═══" | tee -a "$LOG"; }

log_section "PROTOCOL STALENESS CHECK — $TODAY"

STALE_30=0
STALE_60=0
STALE_90=0
NO_HEADER=0
FRESH=0

check_protocol_file() {
  local filepath="$1"
  local filename
  filename=$(basename "$filepath")

  # Extract "Last reviewed:" date from file header
  local last_reviewed=""
  last_reviewed=$(grep -i "^#\? Last reviewed:" "$filepath" 2>/dev/null | head -1 | sed 's/.*Last reviewed://i' | tr -d '[:space:]' | head -c 10)

  if [[ -z "$last_reviewed" ]]; then
    # No header — stamp it with today and flag
    echo "" >> "$filepath"
    echo "<!-- Last reviewed: $TODAY by protocol-staleness-check.sh -->" >> "$filepath"
    log "NO_HEADER: $filename — stamped with today"
    NO_HEADER=$((NO_HEADER + 1))
    return
  fi

  # Compute age in days
  local reviewed_epoch
  reviewed_epoch=$(TZ=America/Denver date -j -f "%Y-%m-%d" "$last_reviewed" +%s 2>/dev/null || \
                   TZ=America/Denver date -d "$last_reviewed" +%s 2>/dev/null || echo 0)

  if [[ "$reviewed_epoch" -eq 0 ]]; then
    log "PARSE_FAIL: $filename — could not parse date '$last_reviewed'"
    return
  fi

  local age_days=$(( (TODAY_EPOCH - reviewed_epoch) / 86400 ))

  if [[ $age_days -ge 90 ]]; then
    log "STALE_90: $filename — ${age_days} days since review"
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "nel" \
      --title "Protocol critically stale (${age_days}d): $filename" \
      --priority "P0" \
      --created-by "protocol-staleness-check" 2>/dev/null || true
    STALE_90=$((STALE_90 + 1))
  elif [[ $age_days -ge 60 ]]; then
    log "STALE_60: $filename — ${age_days} days since review"
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "nel" \
      --title "Protocol stale (${age_days}d): $filename" \
      --priority "P1" \
      --created-by "protocol-staleness-check" 2>/dev/null || true
    STALE_60=$((STALE_60 + 1))
  elif [[ $age_days -ge 30 ]]; then
    log "STALE_30: $filename — ${age_days} days since review"
    HYO_ROOT="$HYO_ROOT" bash "$TICKET_SH" create \
      --agent "nel" \
      --title "Protocol due for review (${age_days}d): $filename" \
      --priority "P2" \
      --created-by "protocol-staleness-check" 2>/dev/null || true
    STALE_30=$((STALE_30 + 1))
  else
    log "FRESH: $filename — ${age_days} days"
    FRESH=$((FRESH + 1))
  fi
}

# ─── Scan all protocol files ───────────────────────────────────────────────────
log_section "kai/protocols/"
for f in "$HYO_ROOT/kai/protocols/"*.md; do
  [[ -f "$f" ]] && check_protocol_file "$f"
done

log_section "Agent PLAYBOOK/PROTOCOL/GROWTH/PRIORITIES"
for agent in nel ra sam aether dex hyo ant; do
  agent_dir="$HYO_ROOT/agents/$agent"
  [[ ! -d "$agent_dir" ]] && continue
  for pattern in PLAYBOOK.md GROWTH.md PRIORITIES.md PROTOCOL_*.md; do
    for f in "$agent_dir/$pattern" "$agent_dir/"*"/$pattern"; do
      [[ -f "$f" ]] && check_protocol_file "$f"
    done
  done
done

log_section "Root-level protocols"
for f in "$HYO_ROOT/CLAUDE.md" "$HYO_ROOT/kai/AGENT_ALGORITHMS.md"; do
  [[ -f "$f" ]] && check_protocol_file "$f"
done

# ─── Summary ──────────────────────────────────────────────────────────────────
log_section "SUMMARY"
log "Fresh (<30d): $FRESH | Stale 30-59d: $STALE_30 | Stale 60-89d: $STALE_60 | Critical (90d+): $STALE_90 | No header: $NO_HEADER"
log "Total flags: $((STALE_30 + STALE_60 + STALE_90 + NO_HEADER))"
log "Run complete: $NOW_MT"

exit 0
