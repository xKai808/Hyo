#!/usr/bin/env bash
# kai/memory/agent_memory/nightly_consolidation.sh
# =========================================================
# Nightly memory consolidation — runs at 01:15 MT (after
# consolidate.sh at 01:00, before Ra at 03:00)
#
# This script runs the full JordanMcCann-pattern promotion
# pipeline on the SQLite memory database:
#   1. Promote yesterday's working memory → episodic
#   2. Promote aged episodic → semantic
#   3. Apply confidence decay to all semantic facts
#   4. Sync semantic layer back to KNOWLEDGE.md
#   5. Check for unresolved contradictions → open ticket
#   6. Commit and push

set -euo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
MEMORY_DIR="$ROOT/kai/memory/agent_memory"
ENGINE="$MEMORY_DIR/memory_engine.py"
KNOWLEDGE="$ROOT/kai/memory/KNOWLEDGE.md"
LOG="$MEMORY_DIR/consolidation.log"

STAMP=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
YESTERDAY=$(TZ=America/Denver date -v-1d +%Y-%m-%d 2>/dev/null \
  || TZ=America/Denver date -d "yesterday" +%Y-%m-%d 2>/dev/null \
  || python3 -c "from datetime import date,timedelta; print((date.today()-timedelta(1)).isoformat())")

echo "[$STAMP] nightly_consolidation.sh: starting" | tee -a "$LOG"

# ── 1. Run promotion pipeline via memory engine ───────────────────────────────
python3 "$ENGINE" promote --date "$YESTERDAY" 2>&1 | tee -a "$LOG"
EXIT_CODE=${PIPESTATUS[0]}
if [[ $EXIT_CODE -ne 0 ]]; then
  echo "[$STAMP] WARNING: promotion pipeline returned $EXIT_CODE" | tee -a "$LOG"
fi

# ── 2. Sync semantic layer to KNOWLEDGE.md ────────────────────────────────────
# Extract all active semantic facts and append any new ones to KNOWLEDGE.md
# (this supplements the existing consolidate.sh which reads flat daily notes)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)

NEW_FACTS=$(python3 - <<'PYEOF' 2>/dev/null
import sqlite3, json, os, pathlib

ROOT = pathlib.Path(os.environ.get("HYO_ROOT", pathlib.Path.home() / "Documents/Projects/Hyo"))
DB = ROOT / "kai/memory/agent_memory/memory.db"
if not DB.exists():
    print("")
    exit(0)

conn = sqlite3.connect(str(DB))
conn.row_factory = sqlite3.Row

# Get semantic facts added or updated in the last 24 hours
rows = conn.execute("""
    SELECT category, fact_key, fact_value, confidence
    FROM semantic_memory
    WHERE superseded_by IS NULL
      AND (last_reinforced > datetime('now', '-24 hours')
           OR created_at > datetime('now', '-24 hours'))
    ORDER BY category, confidence DESC
""").fetchall()

if not rows:
    print("")
    exit(0)

out = []
for r in rows:
    out.append(f"- [{r['category']}] {r['fact_key']}: {r['fact_value']} (conf={r['confidence']:.2f})")
print("\n".join(out))
PYEOF
)

if [[ -n "$NEW_FACTS" ]]; then
  cat >> "$KNOWLEDGE" << APPENDBLOCK

---
## Memory Engine Sync — $TODAY (nightly consolidation)

$NEW_FACTS
APPENDBLOCK
  echo "[$STAMP] Synced $(echo "$NEW_FACTS" | wc -l) semantic facts to KNOWLEDGE.md" | tee -a "$LOG"
else
  echo "[$STAMP] No new semantic facts to sync" | tee -a "$LOG"
fi

# ── 3. Check for unresolved contradictions → open P1 ticket ──────────────────
CONTRADICTION_COUNT=$(python3 - <<'PYEOF' 2>/dev/null
import sqlite3, pathlib, os
ROOT = pathlib.Path(os.environ.get("HYO_ROOT", pathlib.Path.home() / "Documents/Projects/Hyo"))
DB = ROOT / "kai/memory/agent_memory/memory.db"
if not DB.exists():
    print(0); exit(0)
conn = sqlite3.connect(str(DB))
count = conn.execute("SELECT COUNT(*) FROM contradiction_log WHERE resolution = 'FLAGGED'").fetchone()[0]
print(count)
PYEOF
)

if [[ "$CONTRADICTION_COUNT" -gt 0 ]]; then
  echo "[$STAMP] WARNING: $CONTRADICTION_COUNT unresolved contradictions in semantic memory" | tee -a "$LOG"
  # Open P1 ticket via ticket.sh
  if [[ -x "$ROOT/bin/ticket.sh" ]]; then
    bash "$ROOT/bin/ticket.sh" \
      --priority P1 \
      --title "Memory engine: $CONTRADICTION_COUNT unresolved contradictions in semantic layer" \
      --body "Run: python3 kai/memory/agent_memory/memory_engine.py recall contradiction" \
      2>/dev/null || true
  fi
fi

# ── 4. Verify database health ─────────────────────────────────────────────────
python3 - <<'PYEOF' 2>&1 | tee -a "$LOG"
import sqlite3, pathlib, os, sys
ROOT = pathlib.Path(os.environ.get("HYO_ROOT", pathlib.Path.home() / "Documents/Projects/Hyo"))
DB = ROOT / "kai/memory/agent_memory/memory.db"
if not DB.exists():
    print("[health] DB does not exist yet — will be created on first observe()")
    sys.exit(0)
conn = sqlite3.connect(str(DB))
conn.row_factory = sqlite3.Row
raw = conn.execute("SELECT COUNT(*) as n FROM raw_events").fetchone()["n"]
working = conn.execute("SELECT COUNT(*) as n FROM working_memory WHERE promoted = 0").fetchone()["n"]
episodic = conn.execute("SELECT COUNT(*) as n FROM episodic_memory").fetchone()["n"]
semantic = conn.execute("SELECT COUNT(*) as n FROM semantic_memory WHERE superseded_by IS NULL").fetchone()["n"]
print(f"[health] raw={raw} | working={working} | episodic={episodic} | semantic={semantic}")
PYEOF

# ── 5. Commit and push ────────────────────────────────────────────────────────
cd "$ROOT"
git add \
  kai/memory/KNOWLEDGE.md \
  kai/memory/agent_memory/memory.db \
  kai/memory/agent_memory/consolidation.log \
  kai/memory/daily/ \
  2>/dev/null || true

if ! git diff --cached --quiet; then
  git commit -m "memory: nightly consolidation $TODAY — engine sync + semantic promotion" \
    --author="Kai <kai@hyo.world>" 2>&1 | tail -1
  git push origin main 2>&1 | tail -1 \
    || echo "[$STAMP] WARNING: git push failed" | tee -a "$LOG"
fi

echo "[$STAMP] nightly_consolidation.sh: done" | tee -a "$LOG"
