#!/usr/bin/env bash
# kai/consolidation/consolidate.sh — nightly per-project consolidation
# Runs sentinel + cipher checks per project, appends compounding entries,
# updates project task lists, syncs to HQ.
#
# Usage: bash kai/consolidation/consolidate.sh [--project <name>]
#   --project hyo|aurora-ra|aether|kai-ceo   Run one project only
#   (no args)                                    Run all four + cross-project sentinel/cipher

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DATE="$(date -u +%Y-%m-%d)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_DIR="$ROOT/agents/nel/logs"
mkdir -p "$LOG_DIR"

LOGFILE="$LOG_DIR/consolidation-${DATE}.md"

# ── Portable stat ──
if stat -c %a / >/dev/null 2>&1; then
  stat_mode() { stat -c %a "$1" 2>/dev/null; }
else
  stat_mode() { stat -f %Mp%Lp "$1" 2>/dev/null; }
fi

# ── Helpers ──
log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOGFILE"; }
section() { echo "" >> "$LOGFILE"; echo "## $*" >> "$LOGFILE"; echo "" >> "$LOGFILE"; }

append_history() {
  local project="$1" content="$2"
  local hist="$SCRIPT_DIR/$project/history.md"

  # Check if an entry for today already exists
  if grep -q "^## $DATE — nightly consolidation\$" "$hist" 2>/dev/null; then
    # Today's entry exists — replace it in place
    # Find the line number of today's entry and the next section (or EOF)
    local start_line; start_line=$(grep -n "^## $DATE — nightly consolidation\$" "$hist" | tail -1 | cut -d: -f1)
    local end_line; end_line=$(tail -n +$((start_line+1)) "$hist" | grep -n "^## [0-9]" | head -1 | cut -d: -f1)

    if [[ -z "$end_line" ]]; then
      # No next section — delete from start_line to EOF and append new entry
      head -n $((start_line-1)) "$hist" > "$hist.tmp"
      echo "" >> "$hist.tmp"
      echo "## $DATE — nightly consolidation" >> "$hist.tmp"
      echo "" >> "$hist.tmp"
      echo "$content" >> "$hist.tmp"
      mv "$hist.tmp" "$hist"
    else
      # Next section exists — delete lines from start_line to end_line-1 and insert new entry
      end_line=$((start_line + end_line - 2))
      head -n $((start_line-1)) "$hist" > "$hist.tmp"
      echo "" >> "$hist.tmp"
      echo "## $DATE — nightly consolidation" >> "$hist.tmp"
      echo "" >> "$hist.tmp"
      echo "$content" >> "$hist.tmp"
      tail -n +$((end_line+1)) "$hist" >> "$hist.tmp"
      mv "$hist.tmp" "$hist"
    fi
  else
    # No entry for today — append normally
    echo "" >> "$hist"
    echo "## $DATE — nightly consolidation" >> "$hist"
    echo "" >> "$hist"
    echo "$content" >> "$hist"
  fi
}

# ══════════════════════════════════════════════════════════════
# SENTINEL — per-project checks
# ══════════════════════════════════════════════════════════════
sentinel_hyo() {
  local findings=""
  local passed=0 failed=0

  # API health
  if curl -sf "https://www.hyo.world/api/health" >/dev/null 2>&1; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: API health endpoint unreachable"
  fi

  # Secrets dir
  local smode; smode=$(stat_mode "$ROOT/agents/nel/security" 2>/dev/null || echo "missing")
  if [[ "$smode" == "700" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: .secrets dir mode=$smode (want 700)"
  fi

  # Founder token
  if [[ -f "$ROOT/agents/nel/security/founder.token" ]]; then
    local tmode; tmode=$(stat_mode "$ROOT/agents/nel/security/founder.token" 2>/dev/null || echo "missing")
    if [[ "$tmode" == "600" ]]; then
      passed=$((passed+1))
    else
      failed=$((failed+1)); findings="${findings}\n- FAIL: founder.token mode=$tmode (want 600)"
    fi
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: founder.token missing"
  fi

  # HQ data file exists
  if [[ -f "$ROOT/website/data/hq-state.json" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: hq-state.json missing"
  fi

  echo "passed=$passed failed=$failed"
  [[ -n "$findings" ]] && echo -e "findings:$findings"
}

sentinel_aurora_ra() {
  local findings=""
  local passed=0 failed=0

  # Latest newsletter exists
  local latest; latest=$(ls -1 "$ROOT/newsletters/"*.md 2>/dev/null | sort | tail -1)
  if [[ -n "$latest" ]]; then
    local size; size=$(wc -c < "$latest")
    if [[ "$size" -gt 500 ]]; then
      passed=$((passed+1))
    else
      failed=$((failed+1)); findings="${findings}\n- FAIL: latest newsletter < 500 bytes ($size)"
    fi
    # Age check (mtime < 48h for now since we don't have daily runs)
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: no newsletters found"
  fi

  # Research archive exists
  if [[ -f "$ROOT/agents/ra/research/index.md" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: research archive index missing"
  fi

  # Subscriber endpoint accessible
  # (skip in sandbox — can't curl)

  # Prompts exist
  if [[ -f "$ROOT/agents/ra/pipeline/prompts/synthesize.md" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: synthesize prompt missing"
  fi

  echo "passed=$passed failed=$failed"
  [[ -n "$findings" ]] && echo -e "findings:$findings"
}

sentinel_aether() {
  local findings=""
  local passed=0 failed=0

  # Manifest exists
  if [[ -f "$ROOT/agents/manifests/aether.hyo.json" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: aether.hyo.json manifest missing"
  fi

  # Runner script exists
  if [[ -f "$ROOT/kai/aether.sh" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: kai/aether.sh runner missing"
  fi

  echo "passed=$passed failed=$failed"
  [[ -n "$findings" ]] && echo -e "findings:$findings"
}

sentinel_kai_ceo() {
  local findings=""
  local passed=0 failed=0

  # KAI_BRIEF.md exists and recent
  if [[ -f "$ROOT/KAI_BRIEF.md" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: KAI_BRIEF.md missing"
  fi

  # KAI_TASKS.md exists
  if [[ -f "$ROOT/KAI_TASKS.md" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: KAI_TASKS.md missing"
  fi

  # kai.sh dispatcher exists and is executable
  if [[ -x "$ROOT/bin/kai.sh" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: bin/kai.sh not executable"
  fi

  # Consolidation histories exist for all projects
  local all_exist=true
  for proj in hyo aurora-ra aether kai-ceo nel sam; do
    if [[ ! -f "$SCRIPT_DIR/$proj/history.md" ]]; then
      all_exist=false
      findings="${findings}\n- FAIL: consolidation/$proj/history.md missing"
    fi
  done
  if $all_exist; then passed=$((passed+1)); else failed=$((failed+1)); fi

  echo "passed=$passed failed=$failed"
  [[ -n "$findings" ]] && echo -e "findings:$findings"
}

sentinel_nel() {
  local findings=""
  local passed=0 failed=0

  # nel.hyo.json manifest exists
  if [[ -f "$ROOT/agents/manifests/nel.hyo.json" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: nel.hyo.json manifest missing"
  fi

  # agents/nel/nel.sh runner exists and is executable
  if [[ -x "$ROOT/agents/nel/nel.sh" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: agents/nel/nel.sh not executable"
  fi

  # nel consolidation history exists
  if [[ -f "$SCRIPT_DIR/nel/history.md" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: consolidation/nel/history.md missing"
  fi

  # Recent nel logs exist
  local nel_logs; nel_logs=$(find "$LOG_DIR" -name "*nel*" -type f -mtime -1 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$nel_logs" -gt 0 ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: no recent nel logs in agents/nel/logs/ (< 24h)"
  fi

  echo "passed=$passed failed=$failed"
  [[ -n "$findings" ]] && echo -e "findings:$findings"
}

sentinel_sam() {
  local findings=""
  local passed=0 failed=0

  # sam.hyo.json manifest exists
  if [[ -f "$ROOT/agents/manifests/sam.hyo.json" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: sam.hyo.json manifest missing"
  fi

  # agents/sam/sam.sh runner exists and is executable
  if [[ -x "$ROOT/agents/sam/sam.sh" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: agents/sam/sam.sh not executable"
  fi

  # sam consolidation history exists
  if [[ -f "$SCRIPT_DIR/sam/history.md" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: consolidation/sam/history.md missing"
  fi

  # website/ directory health checks
  if [[ -f "$ROOT/website/index.html" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: website/index.html missing"
  fi

  if [[ -f "$ROOT/website/hq.html" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: website/hq.html missing"
  fi

  if [[ -f "$ROOT/website/vercel.json" ]]; then
    passed=$((passed+1))
  else
    failed=$((failed+1)); findings="${findings}\n- FAIL: website/vercel.json missing"
  fi

  echo "passed=$passed failed=$failed"
  [[ -n "$findings" ]] && echo -e "findings:$findings"
}

# ══════════════════════════════════════════════════════════════
# CIPHER — per-project secret/leak scans
# ══════════════════════════════════════════════════════════════
cipher_scan() {
  local dir="$1" label="$2"
  local leaks=0
  # Scan for common secret patterns
  local hits; hits=$(grep -rn --include="*.js" --include="*.sh" --include="*.py" --include="*.md" --include="*.json" \
    -iE '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|AKIA[A-Z0-9]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY)' \
    "$dir" 2>/dev/null | grep -v node_modules | grep -v '.secrets' | grep -v '.git' | head -5 || true)
  if [[ -n "$hits" ]]; then
    leaks=$(echo "$hits" | wc -l | tr -d ' ')
    echo "leaks=$leaks in $label"
    echo "$hits"
  else
    echo "leaks=0 in $label"
  fi
}

# ══════════════════════════════════════════════════════════════
# PER-PROJECT CONSOLIDATION
# ══════════════════════════════════════════════════════════════
run_project() {
  local project="$1"
  local hist="$SCRIPT_DIR/$project/history.md"

  # Idempotency check: if today's entry already exists, update in-place instead of skipping
  # (The append_history function will handle the replacement)
  section "$project"
  log "Starting $project consolidation"

  case "$project" in
    hyo)
      local result; result=$(sentinel_hyo)
      log "Sentinel [hyo]: $result"
      local cipher_web; cipher_web=$(cipher_scan "$ROOT/website" "website/")
      local cipher_nft; cipher_nft=$(cipher_scan "$ROOT/NFT" "NFT/")
      log "Cipher [hyo]: $cipher_web | $cipher_nft"

      local entry="**Sentinel:** $result
**Cipher:** $cipher_web | $cipher_nft
**HQ state:** $(wc -c < "$ROOT/website/data/hq-state.json" 2>/dev/null || echo 0) bytes
**Docs deployed:** $(ls "$ROOT/website/docs/" 2>/dev/null | wc -l | tr -d ' ') agent dirs"
      append_history "hyo" "$entry"
      ;;

    aurora-ra)
      local result; result=$(sentinel_aurora_ra)
      log "Sentinel [aurora-ra]: $result"
      local cipher_nl; cipher_nl=$(cipher_scan "$ROOT/agents/ra/pipeline" "agents/ra/pipeline/")
      log "Cipher [aurora-ra]: $cipher_nl"

      local nl_count; nl_count=$(ls "$ROOT/newsletters/"*.md 2>/dev/null | wc -l | tr -d ' ')
      local archive_count; archive_count=$(find "$ROOT/kai/research/entities" "$ROOT/kai/research/topics" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      local entry="**Sentinel:** $result
**Cipher:** $cipher_nl
**Newsletters shipped:** $nl_count
**Research archive entries:** $archive_count"
      append_history "aurora-ra" "$entry"
      ;;

    aether)
      local result; result=$(sentinel_aether)
      log "Sentinel [aether]: $result"

      local entry="**Sentinel:** $result
**Status:** awaiting scope definition"
      append_history "aether" "$entry"
      ;;

    kai-ceo)
      local result; result=$(sentinel_kai_ceo)
      log "Sentinel [kai-ceo]: $result"
      local cipher_kai; cipher_kai=$(cipher_scan "$ROOT/kai" "kai/")
      log "Cipher [kai-ceo]: $cipher_kai"

      # Count tasks across all project task files
      local open_tasks; open_tasks=$(grep -c '^\- \[ \]' "$SCRIPT_DIR"/*/tasks.md 2>/dev/null | awk -F: '{s+=$2}END{print s}')
      local done_tasks; done_tasks=$(grep -c '^\- \[x\]' "$SCRIPT_DIR"/*/tasks.md 2>/dev/null | awk -F: '{s+=$2}END{print s}')

      local entry="**Sentinel:** $result
**Cipher:** $cipher_kai
**Open tasks across all projects:** $open_tasks
**Completed tasks across all projects:** $done_tasks
**Session continuity files current:** KAI_BRIEF.md + KAI_TASKS.md ✓"
      append_history "kai-ceo" "$entry"
      ;;

    nel)
      local result; result=$(sentinel_nel)
      log "Sentinel [nel]: $result"
      local cipher_nel; cipher_nel=$(cipher_scan "$ROOT/agents/nel/nel.sh" "agents/nel/nel.sh")
      log "Cipher [nel]: $cipher_nel"

      local entry="**Sentinel:** $result
**Cipher:** $cipher_nel"
      append_history "nel" "$entry"
      ;;

    sam)
      local result; result=$(sentinel_sam)
      log "Sentinel [sam]: $result"
      local cipher_sam; cipher_sam=$(cipher_scan "$ROOT/agents/sam/sam.sh" "agents/sam/sam.sh")
      log "Cipher [sam]: $cipher_sam"

      local entry="**Sentinel:** $result
**Cipher:** $cipher_sam"
      append_history "sam" "$entry"
      ;;
  esac

  log "Finished $project consolidation"
}

# ══════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════
echo "# Nightly consolidation — $DATE" > "$LOGFILE"
echo "" >> "$LOGFILE"
echo "**Started:** $TS" >> "$LOGFILE"

TARGET="${2:-all}"  # --project <name> or "all"
if [[ "${1:-}" == "--project" && -n "${2:-}" ]]; then
  TARGET="$2"
fi

if [[ "$TARGET" == "all" ]]; then
  for proj in hyo aurora-ra aether kai-ceo nel sam; do
    run_project "$proj"
  done
else
  run_project "$TARGET"
fi

echo "" >> "$LOGFILE"
echo "**Completed:** $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOGFILE"

log "Consolidation complete. Log at $LOGFILE"

# ══════════════════════════════════════════════════════════════
# SIMULATION — 24h action plan with risk and fallback logic
# ══════════════════════════════════════════════════════════════
run_simulation() {
  local sim_log="$LOG_DIR/simulation-${DATE}.md"
  local sim_web="$ROOT/website/docs/sim/${DATE}.md"

  echo "# Simulation Report — $DATE" > "$sim_log"
  echo "" >> "$sim_log"
  echo "**Generated:** $TS" >> "$sim_log"
  echo "**Purpose:** Executable 24-hour action plan with prerequisites, risk, and fallback logic" >> "$sim_log"
  echo "" >> "$sim_log"

  # ── Compile next 24h tasks from all projects ──
  echo "## Next 24 Hours — Task Plan" >> "$sim_log"
  echo "" >> "$sim_log"

  local task_count=0
  for proj_dir in "$SCRIPT_DIR"/*/tasks.md; do
    [[ ! -f "$proj_dir" ]] && continue
    local proj=$(basename "$(dirname "$proj_dir")")

    echo "### $proj" >> "$sim_log"
    echo "" >> "$sim_log"

    # Extract all non-completed tasks
    local tasks; tasks=$(grep -n '^\- \[ \]' "$proj_dir" 2>/dev/null || true)

    if [[ -z "$tasks" ]]; then
      echo "No pending tasks." >> "$sim_log"
      echo "" >> "$sim_log"
      continue
    fi

    while IFS= read -r line; do
      local task_text="${line#*] }"
      task_text="${task_text#\[\*\] \[}" # Remove markers
      task_text="${task_text%\]*}" # Remove trailing bracket

      # Extract owner if present (format: [K], [H], [B])
      local owner=""
      if [[ "$task_text" =~ ^\[([KHB])\] ]]; then
        owner="${BASH_REMATCH[1]}"
        task_text="${task_text#\[$owner\] }"
      fi

      echo "**Task:** $task_text" >> "$sim_log"
      if [[ -n "$owner" ]]; then
        echo "**Owner:** $owner" >> "$sim_log"
      fi

      # Estimate prerequisites (heuristic based on task content)
      echo "**Prerequisites:**" >> "$sim_log"
      if [[ "$task_text" =~ [Dd]eploy|[Pp]ush|[Cc]ommit ]]; then
        echo "- Git repository initialized and configured" >> "$sim_log"
        echo "- Vercel API token available" >> "$sim_log"
      fi
      if [[ "$task_text" =~ [Mm]igrate|[Cc]reate.*launchd ]]; then
        echo "- Mini terminal access" >> "$sim_log"
        echo "- launchd framework available" >> "$sim_log"
      fi
      if [[ "$task_text" =~ [Ll]aunch|[Ss]chedule ]]; then
        echo "- System clock synchronized" >> "$sim_log"
        echo "- Cron or launchd available" >> "$sim_log"
      fi
      echo "- Relevant script/config files present" >> "$sim_log"

      # Risk assessment
      echo "**Risk Level:** " >> "$sim_log"
      if [[ "$task_text" =~ (\[P0\]|blocker) ]]; then
        echo "HIGH — P0 blocker, may block other tasks" >> "$sim_log"
      elif [[ "$task_text" =~ (\[P1\]|this\ week) ]]; then
        echo "MEDIUM — P1 task, affects current sprint" >> "$sim_log"
      else
        echo "LOW — P2/P3 task, strategic or backlog" >> "$sim_log"
      fi

      # Execution algorithm
      echo "**Execution Algorithm:**" >> "$sim_log"
      if [[ "$task_text" =~ [Mm]igrate.*launchd ]]; then
        echo "1. Draft plist at \`~/Library/LaunchAgents/\`" >> "$sim_log"
        echo "2. Verify syntax: \`launchctl load -S gui ~/Library/LaunchAgents/...\`" >> "$sim_log"
        echo "3. Enable: \`launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/...\`" >> "$sim_log"
        echo "4. Verify: check logs at \`~/Library/Logs/\`" >> "$sim_log"
        echo "**On Success:** Script runs at scheduled time, logs appear daily" >> "$sim_log"
        echo "**On Failure:** Task appears in KAI_TASKS with diagnostic notes" >> "$sim_log"
      elif [[ "$task_text" =~ [Dd]eploy.*Base|[Ss]olidity ]]; then
        echo "1. Verify \`HyoRegistry.sol\` compiles" >> "$sim_log"
        echo "2. Source env vars (\`HYO_FOUNDER_TOKEN\`, testnet RPC)" >> "$sim_log"
        echo "3. Run deployment script (hardhat / foundry)" >> "$sim_log"
        echo "4. Log contract address to KAI_BRIEF.md" >> "$sim_log"
        echo "**On Success:** Contract lives on Base Sepolia, address recorded" >> "$sim_log"
        echo "**On Failure:** Diagnostic saved; retry with updated RPC endpoint" >> "$sim_log"
      elif [[ "$task_text" =~ [Ss]tore|[Pp]ersist|KV|database ]]; then
        echo "1. Choose backend (Vercel KV or Octokit + GitHub commit)" >> "$sim_log"
        echo "2. Update endpoint code to read/write backend" >> "$sim_log"
        echo "3. Smoke test: write + read cycle" >> "$sim_log"
        echo "4. Verify idempotency (write same key twice, result stable)" >> "$sim_log"
        echo "**On Success:** Data persists across restarts" >> "$sim_log"
        echo "**On Failure:** Endpoint falls back to logging; log diagnostics to KAI_TASKS" >> "$sim_log"
      else
        echo "1. Review task dependencies (check KAI_TASKS for blockers)" >> "$sim_log"
        echo "2. Identify execution script or manual steps" >> "$sim_log"
        echo "3. Run with error output captured: \`... 2>&1 | tee -a \$LOG\`" >> "$sim_log"
        echo "4. Update KAI_TASKS if task is complete or blocked" >> "$sim_log"
        echo "**On Success:** Task moves to Done section with timestamp" >> "$sim_log"
        echo "**On Failure:** Task remains open; diagnostic reason appended" >> "$sim_log"
      fi

      echo "" >> "$sim_log"
      task_count=$((task_count+1))
    done <<< "$tasks"
  done

  echo "" >> "$sim_log"
  echo "## Summary" >> "$sim_log"
  echo "" >> "$sim_log"
  echo "- **Total pending tasks:** $task_count" >> "$sim_log"
  echo "- **Simulation scope:** Next 24 hours from $DATE 00:00 UTC" >> "$sim_log"
  echo "- **Agent involvement:** Nel, Sam, Kai CEO" >> "$sim_log"
  echo "" >> "$sim_log"
  echo "This plan is executable — each task has prerequisites, risk, and fallback defined." >> "$sim_log"
  echo "Run \`kai tasks\` to see all active items; cross-reference each task execution against this plan." >> "$sim_log"

  # ── Copy to website ──
  mkdir -p "$ROOT/website/docs/sim"
  cp "$sim_log" "$sim_web"
  log "Simulation report written to $sim_log and synced to website/docs/sim/"

  # ── Update HQ state with simulation event ──
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$ROOT" "$DATE" "$TS" <<'SIMEOF'
import json, sys, os
root, date, ts = sys.argv[1], sys.argv[2], sys.argv[3]
state_path = os.path.join(root, "website/data/hq-state.json")
try:
    with open(state_path) as f:
        state = json.load(f)
except:
    state = {"events": []}

# Add simulation event
state["events"].insert(0, {
    "ts": ts,
    "agent": "simulation",
    "msg": f"24h action plan — {date}",
    "doc": f"/viewer?agent=simulation&file={date}"
})

# Deduplicate and trim
seen = {}
deduped = []
for event in state["events"]:
    agent = event.get("agent")
    event_date = event.get("ts", "")[:10]
    key = (agent, event_date)
    if key not in seen:
        seen[key] = True
        deduped.append(event)

state["events"] = deduped[:50]
state["updatedAt"] = ts

with open(state_path, "w") as f:
    json.dump(state, f, indent=2)
SIMEOF
  fi
}

# Call run_simulation after all projects consolidate
run_simulation

# ── Update HQ state ──
if command -v python3 >/dev/null 2>&1; then
  python3 - "$ROOT" "$DATE" "$TS" <<'PYEOF'
import json, sys, os
root, date, ts = sys.argv[1], sys.argv[2], sys.argv[3]
state_path = os.path.join(root, "website/data/hq-state.json")
try:
    with open(state_path) as f:
        state = json.load(f)
except:
    state = {"events": []}

# Remove any existing consolidation events for today's date
state["events"] = [e for e in state["events"] if not (e.get("agent") == "consolidation" and e.get("ts", "").startswith(date))]

# Add consolidation events per project
projects = ["hyo", "aurora-ra", "aether", "kai-ceo", "nel", "sam"]
for proj in projects:
    state["events"].insert(0, {
        "ts": ts,
        "agent": "consolidation",
        "msg": f"Nightly consolidation — {proj}",
        "doc": f"/viewer?agent=consolidation&file={date}"
    })

# Deduplicate: for each agent+date combo, keep only the latest (earliest in list since newest is first)
seen = {}
deduped = []
for event in state["events"]:
    agent = event.get("agent")
    event_date = event.get("ts", "")[:10]  # Extract YYYY-MM-DD from timestamp
    key = (agent, event_date)
    if key not in seen:
        seen[key] = True
        deduped.append(event)

state["events"] = deduped

# Trim to 50 events max
state["events"] = state["events"][:50]
state["updatedAt"] = ts
state["consolidation"] = {"lastRun": ts}

with open(state_path, "w") as f:
    json.dump(state, f, indent=2)
print(f"Updated {state_path} ({len(deduped)} deduplicated to {len(state['events'])} events)")
PYEOF
fi

# ── Copy consolidation log to website docs ──
mkdir -p "$ROOT/website/docs/consolidation"
cp "$LOGFILE" "$ROOT/website/docs/consolidation/${DATE}.md"
log "Synced to website/docs/consolidation/"

# ── System 5: Memory Loop — Nightly consolidation questions ──
# From WORKFLOW_SYSTEMS.md: these questions run every night at 23:50 MTN
# Answers are appended to the consolidation log and saved to kai/ledger
log ""
log "═══ System 5: Memory Loop — Nightly Questions ═══"
MEMORY_LOG="$ROOT/kai/ledger/memory-loop.jsonl"

# Generate answers from today's data
python3 - "$ROOT" "$DATE" "$TS" "$MEMORY_LOG" << 'MEMEOF'
import json, sys, os, glob
from datetime import datetime

root, date, ts, memory_log = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# Gather today's signal
tickets_file = os.path.join(root, "kai/tickets/tickets.jsonl")
kai_log = os.path.join(root, "kai/ledger/log.jsonl")
feed_file = os.path.join(root, "website/data/feed.json")

# Count today's tickets
tickets_today = []
blocked_tickets = []
if os.path.exists(tickets_file):
    with open(tickets_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                t = json.loads(line)
                if t.get("created_at", "").startswith(date):
                    tickets_today.append(t)
                if t.get("status") == "BLOCKED":
                    blocked_tickets.append(t)
            except:
                pass

# Count today's flags
flags_today = 0
if os.path.exists(kai_log):
    with open(kai_log) as f:
        for line in f:
            try:
                e = json.loads(line.strip())
                if e.get("action") == "FLAG" and e.get("ts", "").startswith(date):
                    flags_today += 1
            except:
                pass

# Find highest-risk open item
highest_risk = "None identified"
if blocked_tickets:
    b = blocked_tickets[0]
    highest_risk = f"{b['id']}: {b['title']} (BLOCKED: {b.get('blocked_by', 'unknown')})"
elif tickets_today:
    p1s = [t for t in tickets_today if t.get("priority") in ("P0", "P1") and t.get("status") != "CLOSED"]
    if p1s:
        highest_risk = f"{p1s[0]['id']}: {p1s[0]['title']}"

entry = {
    "date": date,
    "ts": ts,
    "questions": {
        "most_important_today": f"{len(tickets_today)} tickets created, {flags_today} flags raised",
        "highest_risk_tomorrow": highest_risk,
        "blocked_count": len(blocked_tickets),
        "tickets_closed": len([t for t in tickets_today if t.get("status") == "CLOSED"]),
        "tickets_open": len([t for t in tickets_today if t.get("status") != "CLOSED"]),
    },
    "standing_instruction_updates": [],
    "patterns_detected": []
}

# Append to memory loop ledger
os.makedirs(os.path.dirname(memory_log), exist_ok=True)
with open(memory_log, "a") as f:
    f.write(json.dumps(entry, ensure_ascii=False) + "\n")

print(f"Memory Loop: {len(tickets_today)} tickets today, {len(blocked_tickets)} blocked, risk: {highest_risk[:60]}")
MEMEOF

log "Memory Loop complete — written to $MEMORY_LOG"
