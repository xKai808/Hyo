#!/usr/bin/env bash
# aurora-overnight.sh — Run 100+ Aurora simulations overnight
# Covers: all 27 combos + 7-hour hourly runs for 10 sim users
# Outputs two HTML reports to website/daily/

set -euo pipefail
HYO_ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
PIPELINE="$HYO_ROOT/agents/ra/pipeline"
WEBSITE="$HYO_ROOT/agents/sam/website"
WEBSITE2="$HYO_ROOT/website"
DATE=$(TZ=America/Denver date +%Y-%m-%d)
LOG="$HYO_ROOT/kai/logs/aurora-sim-$DATE.log"

echo "[aurora-overnight] Starting at $(TZ=America/Denver date)" | tee -a "$LOG"

cd "$PIPELINE"

# Phase 1: Run all 27 voice/depth/length combos
echo "[aurora-overnight] Phase 1: 27 combos" | tee -a "$LOG"
python3 aurora-sim.py --combos all --no-log 2>&1 | tee -a "$LOG" || true

# Phase 2: 10 users × 7 hourly runs = 70 runs
echo "[aurora-overnight] Phase 2: 10 users × 7 hours" | tee -a "$LOG"
python3 aurora-sim.py --users sim-users.json --hours 7 2>&1 | tee -a "$LOG" || true

# Phase 3: Generate report 1 — full simulation analysis
echo "[aurora-overnight] Phase 3: Generating reports" | tee -a "$LOG"
python3 sim-report-template.py \
  --input sim-results.jsonl \
  --output "$WEBSITE/daily/aurora-sim-report-$DATE.html" \
  --title "Aurora Simulation Analysis — $DATE" 2>&1 | tee -a "$LOG" || true

# Phase 4: Generate report 2 — voice compliance summary  
python3 sim-report-template.py \
  --input sim-results.jsonl \
  --output "$WEBSITE/daily/aurora-voice-compliance-$DATE.html" \
  --title "Aurora Voice Compliance — $DATE" \
  --mode voice 2>&1 | tee -a "$LOG" || true

# Sync to both website paths
for f in "aurora-sim-report-$DATE.html" "aurora-voice-compliance-$DATE.html"; do
  if [[ -f "$WEBSITE/daily/$f" ]]; then
    cp "$WEBSITE/daily/$f" "$WEBSITE2/daily/$f"
    echo "[aurora-overnight] Synced $f" | tee -a "$LOG"
  fi
done

# Commit and push
cd "$HYO_ROOT"
git add agents/sam/website/daily/ website/daily/ agents/ra/pipeline/sim-results.jsonl 2>/dev/null || true
git commit -m "feat(aurora): overnight sim results — $DATE — 100+ runs, voice compliance reports" 2>/dev/null || true
git push origin main 2>&1 | tail -3 | tee -a "$LOG" || true

echo "[aurora-overnight] Done at $(TZ=America/Denver date)" | tee -a "$LOG"
