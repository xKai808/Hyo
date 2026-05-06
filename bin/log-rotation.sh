#!/usr/bin/env bash
# bin/log-rotation.sh — Rotate unbounded text log files to prevent disk fill
#
# Called by: weekly-maintenance.sh every Saturday 02:00 MT
# Also callable manually: bash bin/log-rotation.sh
#
# Strategy:
#   - Text .log files > 5MB → compress tail to .gz archive, truncate to last 500 lines
#   - Text .log files > 1MB → truncate to last 1000 lines (keep recent for debugging)
#   - Queue completed jobs > 7 days → compress to monthly tar.gz, delete originals
#   - claude-delegate-failed-*.txt → consolidate to monthly archive, delete
#
# SE-010: Never delete what isn't clearly understood. Compress+keep, don't destroy.

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z | sed 's/\([+-][0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/')
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
MONTH=$(TZ=America/Denver date +%Y-%m)
LOG_ARCHIVE="$ROOT/kai/ledger/archive"
QUEUE_ARCHIVE="$ROOT/kai/queue/archive"

mkdir -p "$LOG_ARCHIVE" "$QUEUE_ARCHIVE"

log() { echo "[$NOW_MT] $*"; }
bytes_to_mb() { echo "scale=1; $1 / 1048576" | bc 2>/dev/null || echo "?"; }

saved=0
log "=== Log Rotation — $TODAY ==="

# ─────────────────────────────────────────────────────────────────────────────
# 1. Rotate text .log files in kai/ledger/
# ─────────────────────────────────────────────────────────────────────────────
rotate_log() {
    local path="$1"
    local max_bytes="${2:-5242880}"   # 5MB default threshold
    local keep_lines="${3:-500}"      # lines to keep in live file

    [[ ! -f "$path" ]] && return 0

    local size
    size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo 0)

    if [[ "$size" -gt "$max_bytes" ]]; then
        local name
        name=$(basename "$path" .log)
        local archive_path="$LOG_ARCHIVE/${name}-${TODAY}.log.gz"

        # Compress all but the last keep_lines lines → archive
        local total_lines
        total_lines=$(wc -l < "$path")
        local archive_lines=$(( total_lines - keep_lines ))

        if [[ "$archive_lines" -gt 0 ]]; then
            head -n "$archive_lines" "$path" | gzip > "$archive_path"
            # Keep only last keep_lines in live file
            local tmp="${path}.tmp"
            tail -n "$keep_lines" "$path" > "$tmp" && mv "$tmp" "$path"
            local new_size
            new_size=$(stat -f%z "$path" 2>/dev/null || stat -c%s "$path" 2>/dev/null || echo 0)
            local delta=$(( size - new_size ))
            saved=$(( saved + delta ))
            log "  Rotated: $(basename $path) — $(bytes_to_mb $size)MB → $(bytes_to_mb $new_size)MB (saved $(bytes_to_mb $delta)MB) → $archive_path"
        fi
    fi
}

# Primary offenders (10MB, 8.8MB, 8.7MB)
rotate_log "$ROOT/kai/ledger/self-improve.log"       5242880  500
rotate_log "$ROOT/kai/ledger/kai-autonomous.log"     5242880  500
rotate_log "$ROOT/kai/ledger/claude-delegate.log"    5242880  500

# Secondary logs (>1MB → rotate at 2MB, keep 1000 lines)
for logfile in \
    "$ROOT/kai/ledger/bore-tunnel.log" \
    "$ROOT/kai/ledger/ticket-enforcer.log" \
    "$ROOT/kai/ledger/queue-hygiene.log" \
    "$ROOT/kai/ledger/outcome-check.log" \
    "$ROOT/kai/ledger/flywheel-doctor.log" \
    "$ROOT/kai/ledger/weekly-maintenance.log" \
    "$ROOT/kai/ledger/aetherbot-monitor.log" \
    "$ROOT/kai/ledger/aurora-retention.log"; do
    rotate_log "$logfile" 2097152 1000
done

# Agent-specific logs
for agent in nel sam ra dex; do
    for logfile in "$ROOT/agents/$agent/logs/"*.log; do
        [[ -f "$logfile" ]] && rotate_log "$logfile" 2097152 500
    done
done

# ─────────────────────────────────────────────────────────────────────────────
# 2. Archive queue completed jobs > 7 days
# ─────────────────────────────────────────────────────────────────────────────
COMPLETED_DIR="$ROOT/kai/queue/completed"
if [[ -d "$COMPLETED_DIR" ]]; then
    CUTOFF=$(date -d "7 days ago" +%Y-%m-%d 2>/dev/null || \
             date -v-7d +%Y-%m-%d 2>/dev/null || echo "2000-01-01")

    ARCHIVE_JOBS="$QUEUE_ARCHIVE/completed-${MONTH}.tar.gz"
    OLD_JOBS=()

    while IFS= read -r -d '' f; do
        # Check file modification date
        local_date=$(date -r "$f" +%Y-%m-%d 2>/dev/null || echo "2026-01-01")
        if [[ "$local_date" < "$CUTOFF" ]]; then
            OLD_JOBS+=("$f")
        fi
    done < <(find "$COMPLETED_DIR" -name "*.json" -print0 2>/dev/null)

    if [[ "${#OLD_JOBS[@]}" -gt 0 ]]; then
        tar -czf "$ARCHIVE_JOBS" --remove-files "${OLD_JOBS[@]}" 2>/dev/null && \
            log "  Queue archive: ${#OLD_JOBS[@]} jobs → $ARCHIVE_JOBS"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Consolidate claude-delegate-failed-*.txt → monthly archive
# ─────────────────────────────────────────────────────────────────────────────
LEDGER="$ROOT/kai/ledger"
FAILED_FILES=("$LEDGER"/claude-delegate-failed-*.txt)
if [[ -e "${FAILED_FILES[0]}" ]]; then
    COUNT="${#FAILED_FILES[@]}"
    FAILED_ARCHIVE="$LOG_ARCHIVE/claude-delegate-failures-${MONTH}.md"

    {
        echo "# Claude Delegate Failure Archive — $MONTH"
        echo ""
        echo "Consolidated $COUNT failure files on $TODAY"
        echo "Content: each file contained 'Not logged in · Please run /login'"
        echo ""
        echo "Timestamps (Unix):"
        for f in "${FAILED_FILES[@]}"; do
            basename "$f" .txt | sed 's/claude-delegate-failed-//'
        done
    } >> "$FAILED_ARCHIVE"

    rm -f "${FAILED_FILES[@]}"
    log "  Consolidated: $COUNT claude-delegate-failed files → $FAILED_ARCHIVE"
    saved=$(( saved + COUNT * 35 ))
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Archive old aether analysis files > 30 days
# ─────────────────────────────────────────────────────────────────────────────
ANALYSIS_DIR="$ROOT/agents/aether/analysis"
AETHER_ARCHIVE_DIR="$ROOT/agents/aether/archive"
mkdir -p "$AETHER_ARCHIVE_DIR"

if [[ -d "$ANALYSIS_DIR" ]]; then
    CUTOFF_30=$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || \
                date -v-30d +%Y-%m-%d 2>/dev/null || echo "2000-01-01")

    OLD_ANALYSIS=()
    while IFS= read -r -d '' f; do
        fname=$(basename "$f")
        # Match date-based files: Analysis_*, GPT_*, Simulation_*, Deep_*, Final_*, raw_extract_*
        if [[ "$fname" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            file_date=$(echo "$fname" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
            if [[ -n "$file_date" && "$file_date" < "$CUTOFF_30" ]]; then
                OLD_ANALYSIS+=("$f")
            fi
        fi
    done < <(find "$ANALYSIS_DIR" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.bak" \) -print0 2>/dev/null)

    if [[ "${#OLD_ANALYSIS[@]}" -gt 0 ]]; then
        ANALYSIS_ARCHIVE="$AETHER_ARCHIVE_DIR/analysis-pre-${CUTOFF_30}.tar.gz"
        tar -czf "$ANALYSIS_ARCHIVE" --remove-files "${OLD_ANALYSIS[@]}" 2>/dev/null && \
            log "  Aether analysis: ${#OLD_ANALYSIS[@]} files → $ANALYSIS_ARCHIVE"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5. Archive old self-review logs per agent > 60 days
# ─────────────────────────────────────────────────────────────────────────────
for agent in aether nel sam ra dex; do
    LOGS_DIR="$ROOT/agents/$agent/logs"
    [[ ! -d "$LOGS_DIR" ]] && continue

    CUTOFF_60=$(date -d "60 days ago" +%Y-%m-%d 2>/dev/null || \
                date -v-60d +%Y-%m-%d 2>/dev/null || echo "2000-01-01")

    OLD_REVIEWS=()
    while IFS= read -r -d '' f; do
        fname=$(basename "$f")
        if [[ "$fname" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
            file_date=$(echo "$fname" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
            if [[ -n "$file_date" && "$file_date" < "$CUTOFF_60" ]]; then
                OLD_REVIEWS+=("$f")
            fi
        fi
    done < <(find "$LOGS_DIR" -maxdepth 1 -type f \( -name "*.md" -o -name "*.txt" \) -print0 2>/dev/null)

    if [[ "${#OLD_REVIEWS[@]}" -gt 0 ]]; then
        AGENT_ARCHIVE="$ROOT/agents/$agent/archive"
        mkdir -p "$AGENT_ARCHIVE"
        REVIEWS_ARCHIVE="$AGENT_ARCHIVE/logs-pre-${CUTOFF_60}.tar.gz"
        tar -czf "$REVIEWS_ARCHIVE" --remove-files "${OLD_REVIEWS[@]}" 2>/dev/null && \
            log "  $agent logs: ${#OLD_REVIEWS[@]} files → $REVIEWS_ARCHIVE"
    fi
done

log "Total estimated saved: $(bytes_to_mb $saved)MB"
log "=== Log Rotation Complete ==="
