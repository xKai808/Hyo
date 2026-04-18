#!/usr/bin/env bash
# kai/memory/consolidate.sh — Nightly memory consolidation (Felix-pattern)
#
# Reads daily notes from the last 7 days, extracts entries that are
# Hyo instructions / decisions / corrections / file uploads (not routine
# business monitor pings), and merges them into KNOWLEDGE.md.
#
# Schedule: runs nightly at 01:00 MT (after kai-daily at 23:30, before Ra at 03:00)
# Trigger: launchd / cron on Mini, or kai exec "bash kai/memory/consolidate.sh"
#
# Pattern modeled on Nat Eliason / Felix memory architecture:
#   Layer 1 = KNOWLEDGE.md      (durable facts — output of this script)
#   Layer 2 = kai/memory/daily/ (episodic notes — written during sessions)
#   Layer 3 = TACIT.md          (Hyo preferences + hard rules)

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DAILY_DIR="$ROOT/kai/memory/daily"
KNOWLEDGE="$ROOT/kai/memory/KNOWLEDGE.md"
TACIT="$ROOT/kai/memory/TACIT.md"
LOG="$ROOT/kai/memory/consolidation.log"

STAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
echo "[$STAMP] consolidate.sh: starting" | tee -a "$LOG"

# ── Gather daily notes from last 7 days ──────────────────────────────────────
CUTOFF=$(TZ=America/Denver date -v-7d +%Y-%m-%d 2>/dev/null \
  || TZ=America/Denver date -d "7 days ago" +%Y-%m-%d 2>/dev/null \
  || python3 -c "from datetime import date,timedelta; print((date.today()-timedelta(7)).isoformat())")

NOTES_BUNDLE=""
NOTE_COUNT=0
for f in "$DAILY_DIR"/*.md; do
  [[ -f "$f" ]] || continue
  DATE_OF_FILE=$(basename "$f" .md)
  [[ "$DATE_OF_FILE" < "$CUTOFF" ]] && continue
  # Only include entries that look like session notes (not business monitor pings)
  SESSION_LINES=$(grep -E "^\*\*\[HYO\]\|^\*\*\[KAI\]\|hyo_instruction\|hyo_upload\|hyo_feedback\|hyo_correction\|hyo_decision\|## Session\|## Hyo" "$f" 2>/dev/null || true)
  if [[ -n "$SESSION_LINES" ]]; then
    NOTES_BUNDLE+="
=== $DATE_OF_FILE ===
$(grep -v "Business Monitor\|Tickets:\|Newsletter:\|Feed:" "$f" | grep -v "^$" | head -80)"
    NOTE_COUNT=$((NOTE_COUNT + 1))
  fi
done

if [[ $NOTE_COUNT -eq 0 ]]; then
  echo "[$STAMP] No session notes found in last 7 days — KNOWLEDGE.md unchanged" | tee -a "$LOG"
  exit 0
fi

echo "[$STAMP] Found $NOTE_COUNT daily note files with session content" | tee -a "$LOG"

# ── Use Claude CLI to extract durable knowledge from session notes ────────────
# If no Claude binary, fall back to pattern-based extraction
CLAUDE_BIN=$(which claude 2>/dev/null || echo "")

if [[ -n "$CLAUDE_BIN" ]]; then
  EXTRACTED=$(echo "$NOTES_BUNDLE" | "$CLAUDE_BIN" -p "$(cat <<'PROMPT'
You are reading daily session notes from Kai (AI orchestrator for hyo.world) from the last 7 days.
Your job: extract ONLY facts, decisions, instructions, corrections, and feedback that Hyo has given Kai.
Do NOT extract routine business monitor status lines.
DO extract: Hyo uploaded X file, Hyo corrected Kai about Y, Hyo decided Z, Hyo instructed W.
Format each extracted item as a bullet: - [DATE] CATEGORY: description
Categories: ROLE_CORRECTION | TECHNICAL_CORRECTION | STRATEGIC_DIRECTION | FILE_UPLOADED | FEEDBACK | DECISION | INSTRUCTION
Output ONLY the bullets. No headers. No preamble.
PROMPT
)" 2>/dev/null || echo "")
else
  # Fallback: grep-based extraction for lines explicitly marked as Hyo content
  EXTRACTED=$(echo "$NOTES_BUNDLE" | grep -E "^\- \[HYO\]|hyo_instruction|hyo_upload|hyo_feedback|hyo_correction|hyo_decision" 2>/dev/null || echo "")
fi

if [[ -z "$EXTRACTED" ]]; then
  echo "[$STAMP] No extractable knowledge from session notes" | tee -a "$LOG"
  exit 0
fi

# ── Append extracted knowledge to KNOWLEDGE.md ───────────────────────────────
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
cat >> "$KNOWLEDGE" << APPENDBLOCK

---
## Consolidated from daily notes — $TODAY

$EXTRACTED
APPENDBLOCK

echo "[$STAMP] Appended $(echo "$EXTRACTED" | wc -l) extracted items to KNOWLEDGE.md" | tee -a "$LOG"

# ── Git commit ────────────────────────────────────────────────────────────────
cd "$ROOT"
git add kai/memory/KNOWLEDGE.md kai/memory/consolidation.log 2>/dev/null || true
if ! git diff --cached --quiet; then
  git commit -m "memory: nightly consolidation $TODAY — extracted session knowledge" \
    --author="Kai <kai@hyo.world>" 2>&1 | tail -1
  git push origin main 2>&1 | tail -1 || echo "[$STAMP] WARNING: push failed" | tee -a "$LOG"
fi

echo "[$STAMP] consolidate.sh: done" | tee -a "$LOG"
