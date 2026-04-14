#!/usr/bin/env bash
# agents/nel/nel-qa-cycle.sh — Nel v2.0 Autonomous QA Cycle (runs every 6 hours)
#
# 10-Phase Quality Assurance Pipeline:
#   Phase 1: Link Validation (local + live)
#   Phase 2: Security Scan (secrets, permissions, exposed data)
#   Phase 2.5: GitHub Security Scan (repo secrets, history, gitignore coverage)
#   Phase 3: API Health (all endpoints respond correctly)
#   Phase 4: Data Integrity (JSONL valid, configs parse, no corruption)
#   Phase 5: Agent Health (all runners execute, daemons alive, logs fresh)
#   Phase 6: Deployment Verification (Vercel status, git clean, latest commit deployed)
#   Phase 7: Research Sync (website/docs/research matches agents/ra/research)
#   Phase 7.5: Rendered Output Verification (data files render on live site, not just exist)
#   Phase 8: Report & Dispatch (consolidate findings, flag issues, update ledger)
#
# Design principles (from nel-qa-architecture-research.md):
#   - Shift-left: catch before production, not after
#   - Closed-loop: every finding gets flagged, tracked, and verified
#   - Layered: each phase is independent, failure in one doesn't block others
#   - Deterministic: same input → same output, no flaky checks
#   - Fast: target <10 minutes total runtime

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
DISPATCH="$ROOT/bin/dispatch.sh"
LOGS="$ROOT/agents/nel/logs"
LEDGER="$ROOT/agents/nel/ledger"
TODAY=$(date +%Y-%m-%d)
NOW=$(date -u +%FT%TZ)
CYCLE_ID="nel-qa-$(date +%Y%m%d-%H%M)"
REPORT="$LOGS/${CYCLE_ID}.md"
FINDINGS=()
PHASE_RESULTS=()
TOTAL_ERRORS=0
TOTAL_WARNINGS=0
START_TIME=$(date +%s)

mkdir -p "$LOGS" "$LEDGER"

# ---- Helpers ----------------------------------------------------------------
add_finding() {
  local severity="$1" phase="$2" detail="$3"
  FINDINGS+=("$severity|$phase|$detail")
  if [[ "$severity" == "P0" ]] || [[ "$severity" == "P1" ]]; then
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
  else
    TOTAL_WARNINGS=$((TOTAL_WARNINGS + 1))
  fi
}

phase_result() {
  local phase="$1" status="$2" detail="$3"
  PHASE_RESULTS+=("$phase|$status|$detail")
  echo "[$NOW] Phase $phase: $status — $detail" >> "$REPORT"
}

# ---- Report Header ----------------------------------------------------------
cat > "$REPORT" <<EOF
# Nel QA Cycle Report

**Cycle:** $CYCLE_ID
**Started:** $NOW
**Agent:** nel.hyo v2.0
**Mode:** autonomous q6h

---

EOF

# ============================================================================
# PHASE 1: LINK VALIDATION
# ============================================================================
echo "## Phase 1: Link Validation" >> "$REPORT"
echo "" >> "$REPORT"

P1_ERRORS=0
P1_OUTPUT=""

if [[ -f "$ROOT/agents/nel/link-check.sh" ]]; then
  P1_OUTPUT=$(bash "$ROOT/agents/nel/link-check.sh" --full 2>&1) || true
  P1_ERRORS=$(echo "$P1_OUTPUT" | grep -c "^  ✗" 2>/dev/null || true)
  P1_ERRORS=${P1_ERRORS:-0}

  if [[ $P1_ERRORS -gt 0 ]]; then
    echo "**$P1_ERRORS broken links found:**" >> "$REPORT"
    echo '```' >> "$REPORT"
    echo "$P1_OUTPUT" | grep "^  ✗" | head -20 >> "$REPORT"
    echo '```' >> "$REPORT"
    add_finding "P1" "links" "$P1_ERRORS broken links detected"
    phase_result "1-links" "FAIL" "$P1_ERRORS broken links"
  else
    echo "All links validated. ✓" >> "$REPORT"
    phase_result "1-links" "PASS" "0 broken links"
  fi
else
  echo "link-check.sh not found — skipped" >> "$REPORT"
  add_finding "P2" "links" "link-check.sh missing"
  phase_result "1-links" "SKIP" "link-check.sh not found"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 2: SECURITY SCAN
# ============================================================================
echo "## Phase 2: Security Scan" >> "$REPORT"
echo "" >> "$REPORT"

P2_ISSUES=0

# Check for exposed secrets in tracked files
SECRETS_FOUND=$(git -C "$ROOT" grep -l -i "api[_-]key\|secret[_-]key\|password\s*=" -- '*.js' '*.py' '*.sh' '*.json' '*.md' 2>/dev/null | grep -v node_modules | grep -v '.secrets' | grep -v 'SKILL.md' || true)

# Filter out false positives (env var references, config templates)
REAL_SECRETS=0
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  # Check if file contains actual secret values (not just variable names)
  if grep -qP '(?:api[_-]key|secret|password)\s*[:=]\s*["\x27][A-Za-z0-9+/=]{20,}' "$ROOT/$file" 2>/dev/null; then
    REAL_SECRETS=$((REAL_SECRETS + 1))
    add_finding "P0" "security" "Possible secret in $file"
  fi
done <<< "$SECRETS_FOUND"

# Check .secrets directory permissions
if [[ -d "$ROOT/agents/nel/security" ]]; then
  SEC_MODE=$(stat -f %Mp%Lp "$ROOT/agents/nel/security" 2>/dev/null || stat -c %a "$ROOT/agents/nel/security" 2>/dev/null || echo "unknown")
  if [[ "$SEC_MODE" != "0700" ]] && [[ "$SEC_MODE" != "700" ]]; then
    add_finding "P1" "security" ".secrets directory mode is $SEC_MODE (should be 700)"
    P2_ISSUES=$((P2_ISSUES + 1))
  fi
fi

# Check if .secrets is gitignored
if ! git -C "$ROOT" check-ignore -q agents/nel/security 2>/dev/null; then
  add_finding "P0" "security" "agents/nel/security is NOT gitignored"
  P2_ISSUES=$((P2_ISSUES + 1))
fi

# Check for .env files that shouldn't exist
ENV_FILES=$(find "$ROOT" -name ".env" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -5)
if [[ -n "$ENV_FILES" ]]; then
  add_finding "P1" "security" "Found .env files: $ENV_FILES"
  P2_ISSUES=$((P2_ISSUES + 1))
fi

if [[ $REAL_SECRETS -eq 0 ]] && [[ $P2_ISSUES -eq 0 ]]; then
  echo "Security scan clean. ✓" >> "$REPORT"
  phase_result "2-security" "PASS" "No secrets exposed, permissions correct"
else
  echo "**$((REAL_SECRETS + P2_ISSUES)) security issues found.**" >> "$REPORT"
  phase_result "2-security" "FAIL" "$((REAL_SECRETS + P2_ISSUES)) issues"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 2.5: GITHUB SECURITY SCAN
# ============================================================================
echo "## Phase 2.5: GitHub Security Scan" >> "$REPORT"
echo "" >> "$REPORT"

P2_5_ISSUES=0
P2_5_FINDINGS=()

if [[ -f "$ROOT/agents/nel/github-security-scan.sh" ]]; then
  P2_5_OUTPUT=$(bash "$ROOT/agents/nel/github-security-scan.sh" 2>&1) || true

  # Parse JSONL output line by line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^{\"type ]] || continue

    # Extract fields from JSON
    type=$(echo "$line" | grep -oP '(?<="type":")[^"]+')
    severity=$(echo "$line" | grep -oP '(?<="severity":")[^"]+')
    file=$(echo "$line" | grep -oP '(?<="file":")[^"]+')
    detail=$(echo "$line" | grep -oP '(?<="detail":")[^"]*')

    P2_5_FINDINGS+=("$severity|$type|$file|$detail")
    [[ "$severity" == "P0" ]] || [[ "$severity" == "P1" ]] && P2_5_ISSUES=$((P2_5_ISSUES + 1))
  done <<< "$P2_5_OUTPUT"

  if [[ $P2_5_ISSUES -gt 0 ]]; then
    echo "**${#P2_5_FINDINGS[@]} GitHub security findings found:**" >> "$REPORT"
    echo "" >> "$REPORT"
    for finding in "${P2_5_FINDINGS[@]}"; do
      IFS='|' read -r sev ftype fname fdetail <<< "$finding"
      echo "- \`$fname\` [$sev] $ftype: $fdetail" >> "$REPORT"
    done
    echo "" >> "$REPORT"
    phase_result "2.5-github" "FAIL" "${#P2_5_FINDINGS[@]} security issues"

    # Flag each finding
    for finding in "${P2_5_FINDINGS[@]}"; do
      IFS='|' read -r sev ftype fname fdetail <<< "$finding"
      add_finding "$sev" "github-security" "$fdetail"
    done
  else
    echo "GitHub security scan clean. ✓" >> "$REPORT"
    phase_result "2.5-github" "PASS" "0 exposed secrets, gitignore coverage OK"
  fi
else
  echo "github-security-scan.sh not found — skipped" >> "$REPORT"
  add_finding "P2" "github-security" "github-security-scan.sh missing"
  phase_result "2.5-github" "SKIP" "github-security-scan.sh not found"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 3: API HEALTH
# ============================================================================
echo "## Phase 3: API Health" >> "$REPORT"
echo "" >> "$REPORT"

P3_FAILS=0
API_ENDPOINTS=("/api/health" "/api/usage" "/api/hq?action=data")

for ep in "${API_ENDPOINTS[@]}"; do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://www.hyo.world${ep}" 2>/dev/null || echo "000")
  if [[ "$STATUS" == "200" ]]; then
    echo "- \`$ep\` → $STATUS ✓" >> "$REPORT"
  else
    echo "- \`$ep\` → $STATUS ✗" >> "$REPORT"
    P3_FAILS=$((P3_FAILS + 1))
    add_finding "P1" "api" "$ep returned HTTP $STATUS"
  fi
done

if [[ $P3_FAILS -eq 0 ]]; then
  phase_result "3-api" "PASS" "All ${#API_ENDPOINTS[@]} endpoints healthy"
else
  phase_result "3-api" "FAIL" "$P3_FAILS/${#API_ENDPOINTS[@]} endpoints down"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 4: DATA INTEGRITY
# ============================================================================
echo "## Phase 4: Data Integrity" >> "$REPORT"
echo "" >> "$REPORT"

P4_ISSUES=0

# Validate all JSONL files
while IFS= read -r jsonl; do
  if [[ -s "$jsonl" ]]; then
    BAD_LINES=$(python3 -c "
import json, sys
bad = 0
for i, line in enumerate(open('$jsonl'), 1):
    line = line.strip()
    if not line: continue
    try: json.loads(line)
    except: bad += 1
print(bad)
" 2>/dev/null || echo "1")
    if [[ "$BAD_LINES" -gt 0 ]]; then
      rel=${jsonl#"$ROOT/"}
      add_finding "P2" "data" "$BAD_LINES corrupt lines in $rel"
      P4_ISSUES=$((P4_ISSUES + 1))
    fi
  fi
done < <(find "$ROOT" -name "*.jsonl" -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "*/queue/completed/*" 2>/dev/null)

# Validate JSON configs
for cfg in "$ROOT/website/data/usage-config.json" "$ROOT/website/data/hq-state.json"; do
  if [[ -f "$cfg" ]]; then
    if ! python3 -c "import json; json.load(open('$cfg'))" 2>/dev/null; then
      rel=${cfg#"$ROOT/"}
      add_finding "P1" "data" "Invalid JSON: $rel"
      P4_ISSUES=$((P4_ISSUES + 1))
    fi
  fi
done

if [[ $P4_ISSUES -eq 0 ]]; then
  echo "All data files valid. ✓" >> "$REPORT"
  phase_result "4-data" "PASS" "JSONL + JSON configs valid"
else
  echo "**$P4_ISSUES data integrity issues.**" >> "$REPORT"
  phase_result "4-data" "FAIL" "$P4_ISSUES corrupt files"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 5: AGENT HEALTH
# ============================================================================
echo "## Phase 5: Agent Health" >> "$REPORT"
echo "" >> "$REPORT"

P5_ISSUES=0
AGENTS=("nel" "sam" "ra" "aether" "dex")

for agent in "${AGENTS[@]}"; do
  RUNNER="$ROOT/agents/$agent/$agent.sh"
  if [[ ! -f "$RUNNER" ]]; then
    add_finding "P1" "agents" "$agent runner missing: $RUNNER"
    P5_ISSUES=$((P5_ISSUES + 1))
    continue
  fi
  if [[ ! -x "$RUNNER" ]]; then
    add_finding "P2" "agents" "$agent runner not executable"
    P5_ISSUES=$((P5_ISSUES + 1))
  fi

  # Check for recent log (within 48h)
  LATEST_LOG=$(find "$ROOT/agents/$agent/logs" -name "*.log" -o -name "*.md" 2>/dev/null | sort -r | head -1)
  if [[ -n "$LATEST_LOG" ]]; then
    LOG_AGE=$(( ($(date +%s) - $(stat -f %m "$LATEST_LOG" 2>/dev/null || stat -c %Y "$LATEST_LOG" 2>/dev/null || echo 0)) / 3600 ))
    if [[ $LOG_AGE -gt 48 ]]; then
      add_finding "P2" "agents" "$agent last log is ${LOG_AGE}h old (>48h stale)"
      P5_ISSUES=$((P5_ISSUES + 1))
    fi
  fi

  # Check PLAYBOOK.md freshness
  if [[ -f "$ROOT/agents/$agent/PLAYBOOK.md" ]]; then
    PB_AGE=$(( ($(date +%s) - $(stat -f %m "$ROOT/agents/$agent/PLAYBOOK.md" 2>/dev/null || stat -c %Y "$ROOT/agents/$agent/PLAYBOOK.md" 2>/dev/null || echo 0)) / 86400 ))
    if [[ $PB_AGE -gt 14 ]]; then
      add_finding "P1" "agents" "$agent PLAYBOOK.md is ${PB_AGE}d old (>14d critical)"
      P5_ISSUES=$((P5_ISSUES + 1))
    elif [[ $PB_AGE -gt 7 ]]; then
      add_finding "P2" "agents" "$agent PLAYBOOK.md is ${PB_AGE}d old (>7d stale)"
      P5_ISSUES=$((P5_ISSUES + 1))
    fi
  fi
done

# Check launchd daemons
EXPECTED_DAEMONS=("com.hyo.queue-worker" "com.hyo.dex" "com.hyo.aether" "com.hyo.mcp-tunnel" "com.hyo.consolidation" "com.hyo.simulation" "com.hyo.aurora")
RUNNING_DAEMONS=$(launchctl list 2>/dev/null | grep "com.hyo" | awk '{print $3}' || true)

for daemon in "${EXPECTED_DAEMONS[@]}"; do
  if ! echo "$RUNNING_DAEMONS" | grep -q "$daemon"; then
    add_finding "P1" "agents" "Daemon $daemon not running"
    P5_ISSUES=$((P5_ISSUES + 1))
  fi
done

if [[ $P5_ISSUES -eq 0 ]]; then
  echo "All agents healthy. ✓" >> "$REPORT"
  phase_result "5-agents" "PASS" "${#AGENTS[@]} agents + ${#EXPECTED_DAEMONS[@]} daemons OK"
else
  echo "**$P5_ISSUES agent health issues.**" >> "$REPORT"
  phase_result "5-agents" "FAIL" "$P5_ISSUES issues"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 6: DEPLOYMENT VERIFICATION
# ============================================================================
echo "## Phase 6: Deployment Verification" >> "$REPORT"
echo "" >> "$REPORT"

P6_ISSUES=0

# Check git status
DIRTY=$(git -C "$ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [[ "$DIRTY" -gt 10 ]]; then
  add_finding "P2" "deploy" "$DIRTY uncommitted changes in repo"
  P6_ISSUES=$((P6_ISSUES + 1))
fi

# Check if local HEAD matches remote
LOCAL_HEAD=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
REMOTE_HEAD=$(git -C "$ROOT" rev-parse origin/main 2>/dev/null || echo "unknown")
if [[ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]] && [[ "$LOCAL_HEAD" != "unknown" ]]; then
  add_finding "P2" "deploy" "Local HEAD ($LOCAL_HEAD) != remote ($REMOTE_HEAD)"
  P6_ISSUES=$((P6_ISSUES + 1))
fi

# Check Vercel deployment status (via live site response)
SITE_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://www.hyo.world" 2>/dev/null || echo "000")
if [[ "$SITE_STATUS" != "200" ]]; then
  add_finding "P0" "deploy" "hyo.world returned HTTP $SITE_STATUS"
  P6_ISSUES=$((P6_ISSUES + 1))
fi

if [[ $P6_ISSUES -eq 0 ]]; then
  echo "Deployment healthy. ✓" >> "$REPORT"
  phase_result "6-deploy" "PASS" "Site live, git synced"
else
  echo "**$P6_ISSUES deployment issues.**" >> "$REPORT"
  phase_result "6-deploy" "FAIL" "$P6_ISSUES issues"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 7: RESEARCH SYNC
# ============================================================================
echo "## Phase 7: Research Sync" >> "$REPORT"
echo "" >> "$REPORT"

P7_ISSUES=0
SRC="$ROOT/agents/ra/research"
DST="$ROOT/website/docs/research"

if [[ -d "$SRC" ]] && [[ -d "$DST" ]]; then
  # Count files in each
  SRC_COUNT=$(find "$SRC" -name "*.md" -not -path "*/briefs/*" | wc -l | tr -d ' ')
  DST_COUNT=$(find "$DST" -name "*.md" -not -path "*/briefs/*" | wc -l | tr -d ' ')

  if [[ "$SRC_COUNT" -ne "$DST_COUNT" ]]; then
    add_finding "P2" "research" "Research out of sync: source=$SRC_COUNT, website=$DST_COUNT"
    P7_ISSUES=$((P7_ISSUES + 1))
    # Auto-fix: run sync
    if [[ -f "$ROOT/kai/queue/sync-research.sh" ]]; then
      bash "$ROOT/kai/queue/sync-research.sh" 2>/dev/null
      echo "Auto-synced research files." >> "$REPORT"
    fi
  fi

  if [[ $P7_ISSUES -eq 0 ]]; then
    echo "Research in sync ($SRC_COUNT files). ✓" >> "$REPORT"
    phase_result "7-research" "PASS" "$SRC_COUNT files synced"
  else
    phase_result "7-research" "FIXED" "Auto-synced $SRC_COUNT → $DST_COUNT"
  fi
else
  echo "Research directories missing." >> "$REPORT"
  add_finding "P2" "research" "Missing research directories"
  phase_result "7-research" "FAIL" "Directories missing"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 7.5: RENDERED OUTPUT VERIFICATION
# ============================================================================
# Purpose: verify that key data files ACTUALLY RENDER on the live site.
# Files existing and APIs returning 200 is not enough — we must confirm
# the HTML has the rendering code and the data structure matches what
# the frontend expects. This phase catches "data exists but user can't
# see it" failures (the morning report gap from session 8).
#
# Checks:
#   1. Morning report: JSON exists + hq.html references it + today's date
#   2. Aether metrics: JSON has currentWeek with real balance (not $1000 default)
#   3. Aether strategies: strategies array is populated (not empty or placeholder)
#   4. Data-to-HTML binding: every JSON data file has a corresponding render function
echo "## Phase 7.5: Rendered Output Verification" >> "$REPORT"
echo "" >> "$REPORT"

P75_ISSUES=0

# ── Check 1: Morning Report ──
MR_JSON="$ROOT/website/data/morning-report.json"
HQ_HTML="$ROOT/website/hq.html"

if [[ -f "$MR_JSON" ]]; then
  # Verify JSON has today's date (or yesterday if before 05:00)
  MR_DATE=$(python3 -c "import json; print(json.load(open('$MR_JSON')).get('date',''))" 2>/dev/null || echo "")
  MR_AGE_DAYS=999
  if [[ -n "$MR_DATE" ]]; then
    MR_EPOCH=$(date -j -f "%Y-%m-%d" "$MR_DATE" +%s 2>/dev/null || date -d "$MR_DATE" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    MR_AGE_DAYS=$(( (NOW_EPOCH - MR_EPOCH) / 86400 ))
  fi

  if [[ $MR_AGE_DAYS -gt 1 ]]; then
    add_finding "P1" "render" "Morning report stale: date=$MR_DATE (${MR_AGE_DAYS} days old)"
    P75_ISSUES=$((P75_ISSUES + 1))
  fi

  # Verify hq.html has rendering code for morning report
  if [[ -f "$HQ_HTML" ]]; then
    if ! grep -q "mrSummary\|loadMorningReport\|morning-report" "$HQ_HTML" 2>/dev/null; then
      add_finding "P0" "render" "Morning report JSON exists but hq.html has NO rendering code — user cannot see it"
      P75_ISSUES=$((P75_ISSUES + 1))
    fi
  fi
else
  add_finding "P1" "render" "Morning report JSON missing: $MR_JSON"
  P75_ISSUES=$((P75_ISSUES + 1))
fi

# ── Check 2: Aether Metrics Real Data ──
AETHER_JSON="$ROOT/website/data/aether-metrics.json"
if [[ -f "$AETHER_JSON" ]]; then
  AETHER_BALANCE=$(python3 -c "
import json
d = json.load(open('$AETHER_JSON'))
cw = d.get('currentWeek', d.get('currentPeriod', {}))
print(cw.get('currentBalance', 0))
" 2>/dev/null || echo "0")

  # Check for default/placeholder balance
  if [[ "$AETHER_BALANCE" == "1000.0" ]] || [[ "$AETHER_BALANCE" == "1000" ]] || [[ "$AETHER_BALANCE" == "0" ]]; then
    add_finding "P1" "render" "Aether metrics shows default balance (\$$AETHER_BALANCE) — not real trading data"
    P75_ISSUES=$((P75_ISSUES + 1))
  fi

  # ── Check 3: Aether Strategies Populated ──
  STRATEGY_COUNT=$(python3 -c "
import json
d = json.load(open('$AETHER_JSON'))
cw = d.get('currentWeek', d.get('currentPeriod', {}))
strategies = cw.get('strategies', [])
print(len(strategies))
" 2>/dev/null || echo "0")

  if [[ "$STRATEGY_COUNT" -lt 2 ]]; then
    add_finding "P2" "render" "Aether strategies: only $STRATEGY_COUNT found (expected 6 real strategies)"
    P75_ISSUES=$((P75_ISSUES + 1))
  fi

  # Verify hq.html has Aether rendering that handles current structure
  if [[ -f "$HQ_HTML" ]]; then
    if ! grep -q "abStrategiesTable\|loadAetherMetrics" "$HQ_HTML" 2>/dev/null; then
      add_finding "P0" "render" "Aether metrics JSON exists but hq.html has NO rendering code"
      P75_ISSUES=$((P75_ISSUES + 1))
    fi
  fi
else
  add_finding "P1" "render" "Aether metrics JSON missing: $AETHER_JSON"
  P75_ISSUES=$((P75_ISSUES + 1))
fi

# ── Check 4: Data-to-HTML Binding Audit ──
# Every JSON in website/data/ should have at least one reference in hq.html
if [[ -f "$HQ_HTML" ]]; then
  UNBOUND=0
  for json_file in "$ROOT"/website/data/*.json; do
    [[ ! -f "$json_file" ]] && continue
    local_name=$(basename "$json_file")
    if ! grep -q "$local_name" "$HQ_HTML" 2>/dev/null; then
      add_finding "P2" "render" "Data file $local_name has no reference in hq.html — may not render"
      UNBOUND=$((UNBOUND + 1))
      P75_ISSUES=$((P75_ISSUES + 1))
    fi
  done
fi

if [[ $P75_ISSUES -eq 0 ]]; then
  echo "All rendered outputs verified: morning report current, Aether real data, strategies populated, all JSON files bound. ✓" >> "$REPORT"
  phase_result "7.5-render" "PASS" "All outputs verified"
else
  echo "Rendered output issues found: $P75_ISSUES" >> "$REPORT"
  phase_result "7.5-render" "FAIL" "$P75_ISSUES render issues"
fi
echo "" >> "$REPORT"

# ============================================================================
# PHASE 8: REPORT & DISPATCH
# ============================================================================
echo "## Phase 8: Summary & Dispatch" >> "$REPORT"
echo "" >> "$REPORT"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "**Runtime:** ${DURATION}s" >> "$REPORT"
echo "**Errors:** $TOTAL_ERRORS" >> "$REPORT"
echo "**Warnings:** $TOTAL_WARNINGS" >> "$REPORT"
echo "" >> "$REPORT"

# Phase summary table
echo "| Phase | Status | Detail |" >> "$REPORT"
echo "|-------|--------|--------|" >> "$REPORT"
for pr in "${PHASE_RESULTS[@]}"; do
  IFS='|' read -r phase status detail <<< "$pr"
  echo "| $phase | $status | $detail |" >> "$REPORT"
done
echo "" >> "$REPORT"

# List all findings
if [[ ${#FINDINGS[@]} -gt 0 ]]; then
  echo "### Findings" >> "$REPORT"
  echo "" >> "$REPORT"
  for finding in "${FINDINGS[@]}"; do
    IFS='|' read -r sev phase detail <<< "$finding"
    echo "- **[$sev]** ($phase) $detail" >> "$REPORT"
  done
  echo "" >> "$REPORT"
fi

# Dispatch flags for P0/P1 issues
for finding in "${FINDINGS[@]}"; do
  IFS='|' read -r sev phase detail <<< "$finding"
  if [[ "$sev" == "P0" ]] || [[ "$sev" == "P1" ]]; then
    bash "$DISPATCH" flag nel "$sev" "$detail" 2>/dev/null || true
  fi
done

# Write ledger entry
echo "{\"ts\":\"$NOW\",\"cycle\":\"$CYCLE_ID\",\"duration\":$DURATION,\"errors\":$TOTAL_ERRORS,\"warnings\":$TOTAL_WARNINGS,\"phases\":${#PHASE_RESULTS[@]}}" >> "$LEDGER/nel-qa.jsonl"

# Auto-commit + push if there were auto-fixes
if [[ $P7_ISSUES -gt 0 ]] || [[ $DIRTY -gt 0 ]]; then
  cd "$ROOT"
  git add -A 2>/dev/null
  git commit -m "nel-qa: auto-fix from cycle $CYCLE_ID" 2>/dev/null || true
  git push origin main 2>/dev/null || true
fi

echo "" >> "$REPORT"
echo "---" >> "$REPORT"
echo "*Nel QA Cycle $CYCLE_ID complete. Next cycle in ~6 hours.*" >> "$REPORT"

# Final output
echo "Nel QA Cycle $CYCLE_ID: ${DURATION}s, $TOTAL_ERRORS errors, $TOTAL_WARNINGS warnings"
echo "Report: $REPORT"

if [[ $TOTAL_ERRORS -gt 0 ]]; then
  exit 1
fi
exit 0
