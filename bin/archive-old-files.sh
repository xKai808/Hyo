#!/usr/bin/env bash
# bin/archive-old-files.sh — Compress and archive files older than N days
#
# Runs weekly (wired into weekly-maintenance.sh Saturday 02:00 MT)
# Also callable manually: bash bin/archive-old-files.sh [--days N] [--dry-run]
#
# What gets archived:
#   agents/*/research/raw/   — raw research files older than 30 days → tar.gz
#   agents/*/logs/           — log files older than 30 days → tar.gz
#   agents/ra/output/        — newsletter output older than 30 days → tar.gz
#
# Archive location: agents/<name>/archive/YYYY/MM/<name>-raw-YYYY-MM.tar.gz
# Dry-run: shows what would be archived without touching files

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DAYS=30
DRY_RUN=false
LOG_FILE="/tmp/archive-old-files-$(date +%Y%m%d).log"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --days)    DAYS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) break ;;
    esac
done

log() { echo "[archive] $*" | tee -a "$LOG_FILE"; }
log "=== Archive run: $(date '+%Y-%m-%d %H:%M MT') | days=${DAYS} | dry-run=${DRY_RUN} ==="

TOTAL_ARCHIVED=0
TOTAL_FREED=0

archive_dir() {
    local agent="$1"
    local dir_path="$2"
    local label="$3"   # e.g. "raw", "logs", "output"

    [[ -d "$dir_path" ]] || return 0

    # Find files older than $DAYS days
    local old_files
    old_files=$(find "$dir_path" -maxdepth 1 -type f -mtime "+$DAYS" 2>/dev/null | sort)

    [[ -z "$old_files" ]] && {
        log "  $agent/$label: no files older than ${DAYS}d"
        return 0
    }

    local count
    count=$(echo "$old_files" | wc -l | tr -d ' ')
    local total_size
    total_size=$(echo "$old_files" | xargs du -sc 2>/dev/null | tail -1 | awk '{print $1}')

    log "  $agent/$label: found $count files (${total_size}KB) older than ${DAYS}d"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "$old_files" | head -5 | while read -r f; do log "    [dry] would archive: $(basename "$f")"; done
        [[ "$count" -gt 5 ]] && log "    [dry] ... and $((count - 5)) more"
        return 0
    fi

    # Create archive dir
    local year month
    year=$(date +%Y)
    month=$(date +%m)
    local arch_dir="$ROOT/agents/$agent/archive/$year/$month"
    mkdir -p "$arch_dir"

    # Compress into dated tarball
    local tar_name="${agent}-${label}-pre-$(date +%Y-%m-%d).tar.gz"
    local tar_path="$arch_dir/$tar_name"

    # Build list of files to tar (basenames only, run from dir_path)
    local file_list
    file_list=$(echo "$old_files" | xargs -I{} basename {})

    (
        cd "$dir_path"
        echo "$file_list" | xargs tar -czf "$tar_path" 2>/dev/null
    )

    # Remove originals only if tar succeeded
    if [[ -f "$tar_path" && -s "$tar_path" ]]; then
        echo "$old_files" | xargs rm -f
        local tar_size
        tar_size=$(du -k "$tar_path" | awk '{print $1}')
        log "  $agent/$label: archived → $tar_name (${tar_size}KB compressed from ${total_size}KB raw)"
        TOTAL_ARCHIVED=$((TOTAL_ARCHIVED + count))
        TOTAL_FREED=$((TOTAL_FREED + total_size - tar_size))
    else
        log "  WARN: tar creation failed for $agent/$label — originals preserved"
    fi
}

# ── Archive research/raw for all agents ──────────────────────────────────────
AGENTS=(nel dex sam aether ra kai)
for agent in "${AGENTS[@]}"; do
    archive_dir "$agent" "$ROOT/agents/$agent/research/raw" "raw"
done

# ── Archive logs for all agents ──────────────────────────────────────────────
for agent in "${AGENTS[@]}"; do
    archive_dir "$agent" "$ROOT/agents/$agent/logs" "logs"
done

# ── Archive Ra newsletter output ─────────────────────────────────────────────
archive_dir "ra" "$ROOT/agents/ra/output" "output"

# ── Archive Aether logs (high-volume) ────────────────────────────────────────
archive_dir "aether" "$ROOT/agents/aether/logs" "aether-logs"

# ── Summary ──────────────────────────────────────────────────────────────────
log "=== Archive complete: $TOTAL_ARCHIVED files archived, ~${TOTAL_FREED}KB freed ==="
[[ "$DRY_RUN" == "true" ]] && log "=== DRY RUN — no files were modified ==="
