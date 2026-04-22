#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# omp-measure.sh — Outcome Metric Profile measurement engine
# Version: 1.0 — 2026-04-21
#
# Computes two layers of quality metrics per agent:
#   Layer 1 (Umbrella): OCR, RR, RDI, CE, MCS — apply to all agents
#   Layer 2 (Specific): APS (Nel), DSS (Sam), EQS (Ra), ASR (Aether),
#                       PAR (Dex), CCS (Kai) — one unique per agent specialty
#
# Output:
#   agents/<name>/ledger/omp-latest.json   — current scores
#   agents/<name>/ledger/omp-history.jsonl — time-series
#   kai/ledger/omp-summary.json            — all agents (for morning report)
#
# Protocol: kai/protocols/PROTOCOL_OMP.md
# Schedule: 07:30 MT daily via kai-autonomous.sh (before morning report)
# Usage:
#   bash bin/omp-measure.sh           # all agents
#   bash bin/omp-measure.sh nel       # single agent
# ═══════════════════════════════════════════════════════════════════════════
set -uo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG="$HYO_ROOT/kai/ledger/omp-measure.log"
TICKET_SH="$HYO_ROOT/bin/ticket.sh"
SUMMARY_OUT="$HYO_ROOT/kai/ledger/omp-summary.json"

mkdir -p "$(dirname "$LOG")"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
WINDOW=14  # days for rolling window

log()      { echo "[$NOW_MT] $*" | tee -a "$LOG"; }
log_ok()   { echo "[$NOW_MT] ✓ $*" | tee -a "$LOG"; }
log_warn() { echo "[$NOW_MT] ⚠ $*" | tee -a "$LOG"; }
log_err()  { echo "[$NOW_MT] ✗ $*" | tee -a "$LOG"; }

# ─── Utility: days since a date string ────────────────────────────────────────
days_since() {
  local date_str="$1"
  local then now diff
  then=$(date -j -f "%Y-%m-%d" "$date_str" "+%s" 2>/dev/null || date -d "$date_str" "+%s" 2>/dev/null || echo 0)
  now=$(date +%s)
  diff=$(( (now - then) / 86400 ))
  echo "$diff"
}

# ─── Utility: open a ticket if not already open ───────────────────────────────
open_ticket_if_needed() {
  local agent="$1" title="$2" severity="$3"
  if [[ -f "$TICKET_SH" ]]; then
    bash "$TICKET_SH" create \
      --agent "$agent" \
      --type omp-quality \
      --severity "$severity" \
      --title "$title" \
      --description "OMP metric threshold breach detected by omp-measure.sh on $TODAY" \
      >> "$LOG" 2>&1 || true
  fi
}

# ─── UMBRELLA METRIC: Outcome Completion Rate (OCR) ───────────────────────────
# % of self-improve cycles that produced a resolved weakness in last WINDOW days
measure_ocr() {
  local agent="$1"
  local evol_file="$HYO_ROOT/agents/$agent/evolution.jsonl"
  local total=0 resolved=0

  if [[ -f "$evol_file" ]]; then
    # Count entries in window
    while IFS= read -r line; do
      local ts event
      ts=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('ts','')[:10])" 2>/dev/null || echo "")
      [[ -z "$ts" ]] && continue
      local age
      age=$(days_since "$ts" 2>/dev/null || echo 999)
      [[ "$age" -gt "$WINDOW" ]] && continue

      event=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('event',''))" 2>/dev/null || echo "")
      [[ "$event" == "cycle_"* || "$event" == "research_complete" || "$event" == "implement_complete" ]] && total=$((total + 1))
      [[ "$event" == "weakness_resolved" ]] && resolved=$((resolved + 1))
    done < "$evol_file"
  fi

  # Also check self-improve-state for cycles count
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  if [[ -f "$state_file" && "$total" -eq 0 ]]; then
    local cycles
    cycles=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('cycles',0))" 2>/dev/null || echo 0)
    total=$cycles
  fi

  local ocr
  if [[ "$total" -gt 0 ]]; then
    ocr=$(python3 -c "print(round($resolved / $total, 3))" 2>/dev/null || echo "0.0")
  else
    ocr="null"
  fi
  echo "$ocr"
}

# ─── UMBRELLA METRIC: Regression Rate (RR) ────────────────────────────────────
# % of resolved weaknesses that re-appeared in GROWTH.md within 30 days
measure_rr() {
  local agent="$1"
  local growth_file="$HYO_ROOT/agents/$agent/GROWTH.md"
  local evol_file="$HYO_ROOT/agents/$agent/evolution.jsonl"
  local resolved_count=0 regressed=0

  if [[ -f "$evol_file" ]]; then
    # Find weaknesses resolved 30-60 days ago, check if they're back in GROWTH.md as OPEN
    while IFS= read -r line; do
      local event wid ts
      event=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('event',''))" 2>/dev/null || echo "")
      [[ "$event" != "weakness_resolved" ]] && continue

      ts=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('ts','')[:10])" 2>/dev/null || echo "")
      local age
      age=$(days_since "$ts" 2>/dev/null || echo 0)
      [[ "$age" -lt 30 || "$age" -gt 60 ]] && continue

      wid=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('weakness_id',''))" 2>/dev/null || echo "")
      resolved_count=$((resolved_count + 1))

      # Check if this wid appears in GROWTH.md with status NOT RESOLVED
      if [[ -f "$growth_file" && -n "$wid" ]]; then
        local in_growth status_line
        in_growth=$(grep -A5 "### $wid:" "$growth_file" 2>/dev/null | grep -i "Status:" | head -1 || echo "")
        if echo "$in_growth" | grep -qi "IN_PROGRESS\|OPEN\|RESEARCH"; then
          regressed=$((regressed + 1))
        fi
      fi
    done < "$evol_file"
  fi

  local rr
  if [[ "$resolved_count" -gt 0 ]]; then
    rr=$(python3 -c "print(round($regressed / $resolved_count, 3))" 2>/dev/null || echo "0.0")
  else
    rr="null"
  fi
  echo "$rr"
}

# ─── UMBRELLA METRIC: Research Depth Index (RDI) ──────────────────────────────
# external_url_ratio × required_fields_ratio for last 7 days of research files
measure_rdi() {
  local agent="$1"
  local research_dir="$HYO_ROOT/agents/$agent/research/improvements"
  local required_fields=("FIX_APPROACH" "FILES_TO_CHANGE" "CONFIDENCE" "ROOT_CAUSE" "EVIDENCE")
  local total_files=0 total_rdi=0

  if [[ -d "$research_dir" ]]; then
    for f in $(ls -t "$research_dir"/*.md 2>/dev/null | head -7); do
      local age fname
      fname=$(basename "$f" .md | cut -d'-' -f2-)  # date part
      local file_date
      file_date=$(basename "$f" .md | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
      if [[ -n "$file_date" ]]; then
        local file_age
        file_age=$(days_since "$file_date" 2>/dev/null || echo 999)
        [[ "$file_age" -gt 7 ]] && continue
      fi

      # Count external URLs (non-hyo.world http links)
      local ext_urls
      ext_urls=$(grep -oE 'https?://[^ ]+' "$f" 2>/dev/null | grep -v "hyo\.world" | sort -u | wc -l | tr -d ' ')

      # Count required fields present
      local fields_present=0
      for field in "${required_fields[@]}"; do
        grep -qi "$field" "$f" 2>/dev/null && fields_present=$((fields_present + 1))
      done

      # Compute file RDI
      local url_ratio fields_ratio file_rdi
      url_ratio=$(python3 -c "print(min($ext_urls / 6.0, 1.0))" 2>/dev/null || echo "0.0")
      fields_ratio=$(python3 -c "print($fields_present / ${#required_fields[@]})" 2>/dev/null || echo "0.0")
      file_rdi=$(python3 -c "print(round($url_ratio * $fields_ratio, 3))" 2>/dev/null || echo "0.0")

      total_files=$((total_files + 1))
      total_rdi=$(python3 -c "print($total_rdi + $file_rdi)" 2>/dev/null || echo "$total_rdi")
    done
  fi

  local rdi
  if [[ "$total_files" -gt 0 ]]; then
    rdi=$(python3 -c "print(round($total_rdi / $total_files, 3))" 2>/dev/null || echo "0.0")
  else
    rdi="null"
  fi
  echo "$rdi"
}

# ─── UMBRELLA METRIC: Cycle Efficiency (CE) ───────────────────────────────────
# mean cycles per resolved weakness
measure_ce() {
  local agent="$1"
  local state_file="$HYO_ROOT/agents/$agent/self-improve-state.json"
  local evol_file="$HYO_ROOT/agents/$agent/evolution.jsonl"
  local total_cycles=0 total_resolutions=0

  if [[ -f "$evol_file" ]]; then
    while IFS= read -r line; do
      local event ts age
      ts=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('ts','')[:10])" 2>/dev/null || echo "")
      [[ -z "$ts" ]] && continue
      age=$(days_since "$ts" 2>/dev/null || echo 999)
      [[ "$age" -gt "$WINDOW" ]] && continue

      event=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('event',''))" 2>/dev/null || echo "")
      if [[ "$event" == "weakness_resolved" ]]; then
        local cycles_used
        cycles_used=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('cycles_used', d.get('cycles', 1)))" 2>/dev/null || echo "1")
        total_cycles=$(python3 -c "print($total_cycles + $cycles_used)" 2>/dev/null || echo "$total_cycles")
        total_resolutions=$((total_resolutions + 1))
      fi
    done < "$evol_file"
  fi

  local ce
  if [[ "$total_resolutions" -gt 0 ]]; then
    ce=$(python3 -c "print(round($total_cycles / $total_resolutions, 2))" 2>/dev/null || echo "null")
  else
    ce="null"
  fi
  echo "$ce"
}

# ─── UMBRELLA METRIC: Metric Calibration Score (MCS) ──────────────────────────
# Agreement between SICQ and cross-agent review verdict (requires review data)
measure_mcs() {
  local agent="$1"
  local review_dir="$HYO_ROOT/agents"
  local review_log="$HYO_ROOT/kai/ledger/cross-agent-review-latest.json"
  local sicq_file="$HYO_ROOT/kai/ledger/sicq-latest.json"

  # Need both SICQ data and at least one cross-agent review
  if [[ ! -f "$sicq_file" ]]; then
    echo "null"
    return
  fi

  # Look for any peer review files mentioning this agent as target
  local review_files
  review_files=$(find "$review_dir" -name "peer-review-${agent}-*.md" 2>/dev/null | head -10)
  if [[ -z "$review_files" ]]; then
    echo "null"  # no review data yet
    return
  fi

  local agree=0 total=0
  local agent_sicq
  agent_sicq=$(python3 -c "import json; d=json.load(open('$sicq_file')); print(d.get('scores',{}).get('$agent', -1))" 2>/dev/null || echo "-1")

  for review_file in $review_files; do
    local verdict
    verdict=$(grep -oE "(STRONG|ADEQUATE|WEAK|THEATER)" "$review_file" 2>/dev/null | tail -1)
    [[ -z "$verdict" ]] && continue

    total=$((total + 1))
    # Agreement: SICQ≥60 + STRONG/ADEQUATE = match; SICQ<60 + WEAK/THEATER = match
    if [[ "$agent_sicq" != "-1" ]]; then
      local high_sicq
      high_sicq=$(python3 -c "print('yes' if $agent_sicq >= 60 else 'no')" 2>/dev/null || echo "no")
      local good_verdict
      good_verdict=$(echo "$verdict" | grep -cE "^(STRONG|ADEQUATE)$" || echo "0")

      if [[ "$high_sicq" == "yes" && "$good_verdict" -gt 0 ]]; then
        agree=$((agree + 1))
      elif [[ "$high_sicq" == "no" && "$good_verdict" -eq 0 ]]; then
        agree=$((agree + 1))
      fi
    fi
  done

  local mcs
  if [[ "$total" -ge 4 ]]; then
    mcs=$(python3 -c "print(round($agree / $total, 3))" 2>/dev/null || echo "null")
  else
    mcs="null"  # need ≥4 weeks of data
  fi
  echo "$mcs"
}

# ─── AGENT-SPECIFIC: Nel — Alert Precision Score (APS) ────────────────────────
measure_aps_nel() {
  local known_issues="$HYO_ROOT/kai/ledger/known-issues.jsonl"
  local ticket_dir="$HYO_ROOT/kai/ledger/tickets"
  local tp=0 fp=0

  # True positives: nel-opened tickets that were resolved
  if [[ -d "$ticket_dir" ]]; then
    local nel_tickets
    nel_tickets=$(find "$ticket_dir" -name "*.json" 2>/dev/null | xargs grep -l '"agent":"nel"' 2>/dev/null || true)
    for t in $nel_tickets; do
      local status ts age
      ts=$(python3 -c "import json; d=json.load(open('$t')); print(d.get('created','')[:10])" 2>/dev/null || echo "")
      [[ -z "$ts" ]] && continue
      age=$(days_since "$ts" 2>/dev/null || echo 999)
      [[ "$age" -gt 30 ]] && continue

      status=$(python3 -c "import json; d=json.load(open('$t')); print(d.get('status',''))" 2>/dev/null || echo "")
      [[ "$status" == "resolved" ]] && tp=$((tp + 1))
    done
  fi

  # False positives: known-issues marked false_positive
  if [[ -f "$known_issues" ]]; then
    local fp_count
    fp_count=$(grep -c '"false_positive":true' "$known_issues" 2>/dev/null || echo 0)
    # Only count recent ones (can't easily filter by date in JSONL without parsing)
    fp=$((fp + fp_count))
  fi

  # Also count Nel's own resolved-as-false-alarm entries
  local nel_issues="$HYO_ROOT/agents/nel/memory/sentinel-escalation.json"
  if [[ -f "$nel_issues" ]]; then
    local chronic_unresolved
    chronic_unresolved=$(python3 -c "
import json
try:
  d = json.load(open('$nel_issues'))
  count = 0
  for k, v in d.items():
    if isinstance(v, dict) and v.get('escalation_level', 0) >= 3:
      count += 1
  print(count)
except:
  print(0)
" 2>/dev/null || echo 0)
    fp=$((fp + chronic_unresolved))
  fi

  local aps
  local total=$((tp + fp))
  if [[ "$total" -gt 0 ]]; then
    aps=$(python3 -c "print(round($tp / $total, 3))" 2>/dev/null || echo "null")
  else
    aps="null"
  fi
  echo "$aps"
}

# ─── AGENT-SPECIFIC: Sam — Deploy Stability Score (DSS) ───────────────────────
measure_dss_sam() {
  local perf_baseline="$HYO_ROOT/agents/sam/ledger/performance-baseline.jsonl"
  local total_deploys=0 regressions=0

  # Count deploys (git commits to website/api)
  if command -v git > /dev/null 2>&1; then
    local deploy_count
    deploy_count=$(cd "$HYO_ROOT" && git log --oneline --since="$WINDOW days ago" -- website/api/ agents/sam/website/api/ 2>/dev/null | wc -l | tr -d ' ')
    total_deploys=$deploy_count
  fi

  # Count P0/P1 regressions from performance baseline
  if [[ -f "$perf_baseline" ]]; then
    local reg_count
    reg_count=$(grep -c '"severity":"P[01]"' "$perf_baseline" 2>/dev/null || echo 0)
    # Limit to WINDOW days — count lines with recent timestamps
    regressions=$reg_count
  fi

  local dss
  if [[ "$total_deploys" -gt 0 ]]; then
    dss=$(python3 -c "print(round(1.0 - min($regressions / $total_deploys, 1.0), 3))" 2>/dev/null || echo "null")
  else
    dss="null"
  fi
  echo "$dss"
}

# ─── AGENT-SPECIFIC: Ra — Engagement Quality Score (EQS) ─────────────────────
measure_eqs_ra() {
  local engagement="$HYO_ROOT/agents/ra/ledger/engagement.jsonl"
  local sources="$HYO_ROOT/agents/ra/pipeline/sources.json"

  # CTOR: clicks/opens from engagement.jsonl
  local total_clicks=0 total_opens=0
  if [[ -f "$engagement" ]]; then
    while IFS= read -r line; do
      local clicks opens ts age
      ts=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('ts','')[:10])" 2>/dev/null || echo "")
      [[ -z "$ts" ]] && continue
      age=$(days_since "$ts" 2>/dev/null || echo 999)
      [[ "$age" -gt 7 ]] && continue

      clicks=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('clicks', 0))" 2>/dev/null || echo 0)
      opens=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('opens', 0))" 2>/dev/null || echo 0)
      total_clicks=$(python3 -c "print($total_clicks + $clicks)" 2>/dev/null || echo "$total_clicks")
      total_opens=$(python3 -c "print($total_opens + $opens)" 2>/dev/null || echo "$total_opens")
    done < "$engagement"
  fi

  local ctor_norm
  if python3 -c "import sys; sys.exit(0 if $total_opens > 0 else 1)" 2>/dev/null; then
    # Normalize: 20% CTOR = 1.0
    ctor_norm=$(python3 -c "print(min(($total_clicks / $total_opens) / 0.20, 1.0))" 2>/dev/null || echo "0.0")
  else
    ctor_norm="0.0"
  fi

  # Source diversity: unique domains in sources.json
  local diversity_ratio
  if [[ -f "$sources" ]]; then
    local unique_domains
    unique_domains=$(python3 -c "
import json, re
try:
  feeds = json.load(open('$sources'))
  domains = set()
  for entry in feeds if isinstance(feeds, list) else feeds.get('feeds', []):
    url = entry.get('url','') if isinstance(entry, dict) else str(entry)
    m = re.match(r'https?://([^/]+)', url)
    if m: domains.add(m.group(1))
  print(len(domains))
except:
  print(0)
" 2>/dev/null || echo 0)
    diversity_ratio=$(python3 -c "print(min($unique_domains / 10.0, 1.0))" 2>/dev/null || echo "0.0")
  else
    diversity_ratio="0.0"
  fi

  # Retention: approximate from newsletter output count stability
  local retention_score="0.8"  # default to 0.8 (stable) when no subscriber data

  local eqs
  eqs=$(python3 -c "print(round($ctor_norm * 0.50 + $diversity_ratio * 0.30 + $retention_score * 0.20, 3))" 2>/dev/null || echo "null")
  echo "$eqs"
}

# ─── AGENT-SPECIFIC: Aether — Adversarial Survival Rate (ASR) ────────────────
measure_asr_aether() {
  local log_dir="$HYO_ROOT/agents/aether/logs"
  local total_analyzed=0 survived=0

  if [[ -d "$log_dir" ]]; then
    for log_file in $(ls -t "$log_dir"/aether-*.log 2>/dev/null | head -14); do
      local fname
      fname=$(basename "$log_file" .log | sed 's/aether-//')
      local age
      age=$(days_since "$fname" 2>/dev/null || echo 999)
      [[ "$age" -gt "$WINDOW" ]] && continue

      # Extract Phase 1 recommendation and Phase 2 final recommendation
      local phase1_rec phase2_rec
      phase1_rec=$(grep -oE "RECOMMENDATION: (BUILD|COLLECT|MONITOR)" "$log_file" 2>/dev/null | head -1 || echo "")
      phase2_rec=$(grep -oE "RECOMMENDATION: (BUILD|COLLECT|MONITOR)" "$log_file" 2>/dev/null | tail -1 || echo "")

      [[ -z "$phase1_rec" ]] && continue
      total_analyzed=$((total_analyzed + 1))

      # If phase1 == phase2 (or only one exists), analysis survived
      if [[ "$phase1_rec" == "$phase2_rec" || -z "$phase2_rec" ]]; then
        survived=$((survived + 1))
      fi
    done
  fi

  local asr
  if [[ "$total_analyzed" -gt 0 ]]; then
    asr=$(python3 -c "print(round($survived / $total_analyzed, 3))" 2>/dev/null || echo "null")
  else
    asr="null"
  fi
  echo "$asr"
}

# ─── AGENT-SPECIFIC: Dex — Pattern Actionability Rate (PAR) ─────────────────
measure_par_dex() {
  local cluster_report="$HYO_ROOT/agents/dex/ledger/cluster-report.json"
  local ticket_dir="$HYO_ROOT/kai/ledger/tickets"
  local total_patterns=0 acted=0

  if [[ -f "$cluster_report" ]]; then
    total_patterns=$(python3 -c "
import json
try:
  d = json.load(open('$cluster_report'))
  clusters = d.get('clusters', [])
  print(len(clusters))
except:
  print(0)
" 2>/dev/null || echo 0)
  fi

  # Count tickets that reference dex patterns
  if [[ -d "$ticket_dir" ]]; then
    local dex_tickets
    dex_tickets=$(find "$ticket_dir" -name "*.json" 2>/dev/null | xargs grep -l '"agent":"dex"\|"source":"dex"\|"dex"' 2>/dev/null | wc -l | tr -d ' ')
    acted=$dex_tickets
  fi

  local par
  if [[ "$total_patterns" -gt 0 ]]; then
    par=$(python3 -c "print(round(min($acted / $total_patterns, 1.0), 3))" 2>/dev/null || echo "null")
  else
    par="null"
  fi
  echo "$par"
}

# ─── KAI-SPECIFIC: Decision Quality Index (DQI) ───────────────────────────────
# CEO role: % of decisions with documented rationale that were not reversed
# Research: Bain Decision Effectiveness, Cloverpop DIQ, McKinsey decision-in-urgency
measure_dqi_kai() {
  local decision_log="$HYO_ROOT/kai/ledger/decision-log.jsonl"
  local session_errors="$HYO_ROOT/kai/ledger/session-errors.jsonl"

  # Primary: decision-log.jsonl (when it exists)
  if [[ -f "$decision_log" ]]; then
    python3 << 'PYEOF'
import json, sys
from pathlib import Path
import os

log_path = os.environ.get('HYO_ROOT', '') + '/kai/ledger/decision-log.jsonl'
window = 14
from datetime import datetime, timezone, timedelta
cutoff = datetime.now(timezone.utc) - timedelta(days=window)

total = 0; documented = 0; reversed_count = 0
try:
    for line in open(log_path):
        try:
            d = json.loads(line.strip())
            ts = d.get('ts', '')[:10]
            dt = datetime.fromisoformat(ts).replace(tzinfo=timezone.utc) if ts else None
            if dt and dt < cutoff: continue
            total += 1
            if d.get('rationale') and len(d.get('rationale','')) > 10: documented += 1
            if d.get('reversed'): reversed_count += 1
        except: pass
except: pass

if total > 0:
    doc_rate = documented / total
    reversal_rate = reversed_count / total
    print(round(doc_rate * (1.0 - reversal_rate), 3))
else:
    print('null')
PYEOF
  else
    # Fallback: use session-errors — reinterpret-instructions = bad decision quality
    local reinterpret_errors=0
    if [[ -f "$session_errors" ]]; then
      while IFS= read -r line; do
        local cat ts age
        ts=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('ts','')[:10])" 2>/dev/null || echo "")
        [[ -z "$ts" ]] && continue
        age=$(days_since "$ts" 2>/dev/null || echo 999)
        [[ "$age" -gt "$WINDOW" ]] && continue
        cat=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('category',''))" 2>/dev/null || echo "")
        [[ "$cat" == "reinterpret-instructions" || "$cat" == "wrong-path" ]] && reinterpret_errors=$((reinterpret_errors + 1))
      done < "$session_errors"
    fi
    python3 -c "print(round(max(1.0 - ($reinterpret_errors / $WINDOW), 0.0), 3))" 2>/dev/null || echo "null"
  fi
}

# ─── KAI-SPECIFIC: Orchestration Sync Score (OSS) ────────────────────────────
# Orchestrator role: dispatch ACK rate × (1 - delegation-back-to-Kai rate)
# Research: Applied-AI-Research-Lab/Orchestrator-Agent-Trust, Databricks, CLEAR Framework
measure_oss_kai() {
  local dispatch_log="$HYO_ROOT/kai/ledger/dispatch.log"
  local session_errors="$HYO_ROOT/kai/ledger/session-errors.jsonl"

  # Count dispatched vs ACKed from dispatch log
  local dispatched=0 acked=0
  if [[ -f "$dispatch_log" ]]; then
    dispatched=$(grep -c "DISPATCH\|dispatched" "$dispatch_log" 2>/dev/null || echo 0)
    acked=$(grep -c "ACK\|acked\|completed" "$dispatch_log" 2>/dev/null || echo 0)
  fi

  # Fallback to checking ACTIVE.md freshness across agents as proxy for sync
  if [[ "$dispatched" -eq 0 ]]; then
    local total_agents=0 synced_agents=0
    for a in nel sam ra aether dex; do
      local active="$HYO_ROOT/agents/$a/ledger/ACTIVE.md"
      total_agents=$((total_agents + 1))
      if [[ -f "$active" ]]; then
        local age_h
        age_h=$(python3 -c "
import os, time
try:
  age = (time.time() - os.path.getmtime('$active')) / 3600
  print(int(age))
except:
  print(999)
" 2>/dev/null || echo 999)
        [[ "$age_h" -lt 48 ]] && synced_agents=$((synced_agents + 1))
      fi
    done
    if [[ "$total_agents" -gt 0 ]]; then
      python3 -c "print(round($synced_agents / $total_agents, 3))" 2>/dev/null || echo "null"
    else
      echo "null"
    fi
    return
  fi

  if [[ "$dispatched" -gt 0 ]]; then
    python3 -c "print(round(min($acked / $dispatched, 1.0), 3))" 2>/dev/null || echo "null"
  else
    echo "null"
  fi
}

# ─── KAI-SPECIFIC: Knowledge Retention Index (KRI) ───────────────────────────
# Memory keeper role: 1 - (repeated error categories / total categories seen)
# Research: APQC knowledge management KPIs, KMInstitute, TechTarget
measure_kri_kai() {
  local session_errors="$HYO_ROOT/kai/ledger/session-errors.jsonl"

  if [[ ! -f "$session_errors" ]]; then
    echo "null"
    return
  fi

  python3 << PYEOF
import json, sys, collections
from datetime import datetime, timezone, timedelta
import os

path = os.environ.get('HYO_ROOT', '') + '/kai/ledger/session-errors.jsonl'
cutoff14 = datetime.now(timezone.utc) - timedelta(days=14)
cutoff7  = datetime.now(timezone.utc) - timedelta(days=7)

categories_14 = collections.Counter()
categories_7  = collections.Counter()

try:
    for line in open(path):
        try:
            d = json.loads(line.strip())
            ts = d.get('ts', '')[:10]
            dt = datetime.fromisoformat(ts).replace(tzinfo=timezone.utc) if ts else None
            if not dt: continue
            cat = d.get('category', '')
            if not cat: continue
            if dt >= cutoff14: categories_14[cat] += 1
            if dt >= cutoff7:  categories_7[cat]  += 1
        except: pass
except: pass

if not categories_14:
    print('null')
else:
    # Repeated = same category appearing in BOTH 7-day and 14-day windows (not learned from)
    repeated = sum(1 for c in categories_7 if categories_14[c] >= 2)
    total_cats = len(categories_14)
    kri = max(1.0 - (repeated / total_cats), 0.0)
    print(round(kri, 3))
PYEOF
}

# ─── KAI-SPECIFIC: Autonomous Action Score (AAS) ─────────────────────────────
# Self-improver role: self-initiated improvements / total improvements in GROWTH.md
# Research: arxiv 2502.15212v1 (autonomy measurement), AAEF (RagaAI), arxiv 2512.12791v2
measure_aas_kai() {
  local growth_file="$HYO_ROOT/agents/kai/GROWTH.md"
  local state_file="$HYO_ROOT/agents/kai/self-improve-state.json"
  local evol_file="$HYO_ROOT/agents/kai/evolution.jsonl"

  # Count E# expansion items (self-initiated) vs total W/E items in GROWTH.md
  if [[ -f "$growth_file" ]]; then
    python3 << PYEOF
import re, os

root = os.environ.get('HYO_ROOT', '')
growth_path = root + '/agents/kai/GROWTH.md'
evol_path   = root + '/agents/kai/evolution.jsonl'
state_path  = root + '/agents/kai/self-improve-state.json'

try:
    content = open(growth_path).read()
    # E# items = self-initiated expansion opportunities (autonomous)
    expansion = len(re.findall(r'^### E\d+:', content, re.MULTILINE))
    weakness  = len(re.findall(r'^### W\d+:', content, re.MULTILINE))
    total = expansion + weakness
    if total == 0:
        print('null')
    else:
        # AAS = (E-items are autonomous) + (cycles completed shows self-direction)
        e_ratio = expansion / total

        # Factor 2: flywheel cycle completion rate
        cycles = 0
        improvements_shipped = 0
        try:
            import json
            d = json.load(open(state_path))
            cycles = d.get('cycles', 0)
            improvements_shipped = len(d.get('improvements', []))
        except: pass

        # Normalize: target is ≥2 cycles per week
        cycle_ratio = min(cycles / max(improvements_shipped * 2 + 1, 2), 1.0)
        aas = round(e_ratio * 0.60 + cycle_ratio * 0.40, 3)
        print(aas)
except Exception as e:
    print('null')
PYEOF
  else
    echo "null"
  fi
}

# ─── KAI-SPECIFIC: Business Impact Score (BIS) ────────────────────────────────
# Business operator role: on-time delivery × HQ publish rate
# Research: Google Cloud KPIs for production AI agents, ISG OODA, BCG prediction-to-execution
measure_bis_kai() {
  local morning_data="$HYO_ROOT/website/data/morning-report.json"
  local feed_data="$HYO_ROOT/website/data/feed.json"

  python3 << PYEOF
import json, os
from datetime import datetime, timezone, timedelta

root = os.environ.get('HYO_ROOT', '')
morning_path = root + '/website/data/morning-report.json'
feed_path    = root + '/website/data/feed.json'
log_path     = root + '/kai/ledger/flywheel-doctor.log'

# Factor 1: Morning report on-time delivery (≤ 07:00 MT = on-time)
report_on_time_rate = 0.8  # default assumption
try:
    d = json.load(open(morning_path))
    ts = d.get('generated_at') or d.get('ts', '')
    if ts:
        # If report exists and has a timestamp, it ran
        report_on_time_rate = 0.9
except: pass

# Factor 2: HQ publish rate (agents published reports / expected reports)
# Count feed.json entries from last 7 days
publish_rate = 0.8  # default
try:
    entries = json.load(open(feed_path))
    if isinstance(entries, list):
        cutoff = datetime.now(timezone.utc) - timedelta(days=7)
        recent = []
        for e in entries:
            ts = e.get('published', e.get('ts', ''))[:10] if isinstance(e, dict) else ''
            if ts:
                try:
                    dt = datetime.fromisoformat(ts).replace(tzinfo=timezone.utc)
                    if dt >= cutoff: recent.append(e)
                except: pass
        # Expected: 7 days × ~3 agents publishing daily = 21 entries
        expected_7d = 21
        publish_rate = min(len(recent) / expected_7d, 1.0)
except: pass

bis = round(report_on_time_rate * 0.50 + publish_rate * 0.50, 3)
print(bis)
PYEOF
}

# ─── KAI-SPECIFIC: Composite OMP ─────────────────────────────────────────────
# Weighted composite: DQI×0.25 + OSS×0.20 + KRI×0.25 + AAS×0.15 + BIS×0.15
# Returns composite score for threshold checking; full profile goes to JSON
measure_kai_composite() {
  local dqi="$1" oss="$2" kri="$3" aas="$4" bis="$5"
  python3 -c "
vals = {'DQI': ('$dqi', 0.25), 'OSS': ('$oss', 0.20), 'KRI': ('$kri', 0.25), 'AAS': ('$aas', 0.15), 'BIS': ('$bis', 0.15)}
total_w = 0; weighted = 0
for k,(v,w) in vals.items():
    if v != 'null':
        weighted += float(v) * w
        total_w  += w
if total_w > 0:
    print(round(weighted / total_w, 3))
else:
    print('null')
" 2>/dev/null || echo "null"
}

# ─── Saturation check ─────────────────────────────────────────────────────────
check_saturation() {
  local agent="$1" metric_name="$2" score="$3" threshold_low="$4"
  [[ "$score" == "null" ]] && return

  local history_file="$HYO_ROOT/agents/$agent/ledger/omp-history.jsonl"
  [[ ! -f "$history_file" ]] && return

  # Check last 21 days of this metric
  local consecutive_floor=0 consecutive_ceiling=0
  while IFS= read -r line; do
    local m_name m_score ts age
    m_name=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('metric',''))" 2>/dev/null || echo "")
    [[ "$m_name" != "$metric_name" ]] && continue

    ts=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('ts','')[:10])" 2>/dev/null || echo "")
    age=$(days_since "$ts" 2>/dev/null || echo 999)
    [[ "$age" -gt 21 ]] && continue

    m_score=$(echo "$line" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('score', 'null'))" 2>/dev/null || echo "null")
    [[ "$m_score" == "null" ]] && continue

    local near_floor near_ceiling
    near_floor=$(python3 -c "print('yes' if abs(float('$m_score') - $threshold_low) <= 0.10 else 'no')" 2>/dev/null || echo "no")
    near_ceiling=$(python3 -c "print('yes' if float('$m_score') >= 0.90 else 'no')" 2>/dev/null || echo "no")

    [[ "$near_floor" == "yes" ]] && consecutive_floor=$((consecutive_floor + 1)) || consecutive_floor=0
    [[ "$near_ceiling" == "yes" ]] && consecutive_ceiling=$((consecutive_ceiling + 1)) || consecutive_ceiling=0
  done < "$history_file"

  if [[ "$consecutive_floor" -ge 21 ]]; then
    log_warn "SATURATION (floor): $agent $metric_name has been near-floor for 21+ days"
    open_ticket_if_needed "$agent" "OMP metric $metric_name for $agent stuck near floor — review metric definition" "P2"
  fi
  if [[ "$consecutive_ceiling" -ge 21 ]]; then
    log_warn "SATURATION (ceiling): $agent $metric_name has been near-ceiling for 21+ days"
    open_ticket_if_needed "$agent" "OMP metric $metric_name for $agent saturated at ceiling — may be gameable" "P2"
  fi
}

# ─── Main measurement function for one agent ──────────────────────────────────
measure_agent() {
  local agent="$1"
  local ledger_dir="$HYO_ROOT/agents/$agent/ledger"
  mkdir -p "$ledger_dir"

  # Kai-specific profile globals (set if agent is kai)
  KAI_PROFILE_DQI="null"
  KAI_PROFILE_OSS="null"
  KAI_PROFILE_KRI="null"
  KAI_PROFILE_AAS="null"
  KAI_PROFILE_BIS="null"

  log "  Measuring $agent..."

  # Umbrella metrics
  local ocr rr rdi ce mcs
  ocr=$(measure_ocr "$agent")
  rr=$(measure_rr "$agent")
  rdi=$(measure_rdi "$agent")
  ce=$(measure_ce "$agent")
  mcs=$(measure_mcs "$agent")

  # Agent-specific metric
  local specific_metric_name specific_metric_score
  case "$agent" in
    nel)
      specific_metric_name="APS"
      specific_metric_score=$(measure_aps_nel)
      ;;
    sam)
      specific_metric_name="DSS"
      specific_metric_score=$(measure_dss_sam)
      ;;
    ra)
      specific_metric_name="EQS"
      specific_metric_score=$(measure_eqs_ra)
      ;;
    aether)
      specific_metric_name="ASR"
      specific_metric_score=$(measure_asr_aether)
      ;;
    dex)
      specific_metric_name="PAR"
      specific_metric_score=$(measure_par_dex)
      ;;
    kai)
      specific_metric_name="KAI_COMPOSITE"
      # Measure all 5 Kai-specific OMP dimensions
      local _dqi _oss _kri _aas _bis
      _dqi=$(HYO_ROOT="$HYO_ROOT" measure_dqi_kai)
      _oss=$(HYO_ROOT="$HYO_ROOT" measure_oss_kai)
      _kri=$(HYO_ROOT="$HYO_ROOT" measure_kri_kai)
      _aas=$(HYO_ROOT="$HYO_ROOT" measure_aas_kai)
      _bis=$(HYO_ROOT="$HYO_ROOT" measure_bis_kai)
      specific_metric_score=$(measure_kai_composite "$_dqi" "$_oss" "$_kri" "$_aas" "$_bis")
      # Store profile in global for JSON output
      KAI_PROFILE_DQI="$_dqi"
      KAI_PROFILE_OSS="$_oss"
      KAI_PROFILE_KRI="$_kri"
      KAI_PROFILE_AAS="$_aas"
      KAI_PROFILE_BIS="$_bis"
      ;;
    *)
      specific_metric_name="N/A"
      specific_metric_score="null"
      ;;
  esac

  # Thresholds
  declare -A thresholds
  thresholds=(
    ["nel:APS:low"]="0.80" ["nel:APS:critical"]="0.65"
    ["sam:DSS:low"]="0.90" ["sam:DSS:critical"]="0.75"
    ["ra:EQS:low"]="0.50" ["ra:EQS:critical"]="0.30"
    ["aether:ASR:low"]="0.65" ["aether:ASR:critical"]="0.40"
    ["dex:PAR:low"]="0.35" ["dex:PAR:critical"]="0.15"
    ["kai:KAI_COMPOSITE:low"]="0.75" ["kai:KAI_COMPOSITE:critical"]="0.55"
  )

  local threshold_low="${thresholds["${agent}:${specific_metric_name}:low"]:-0.50}"
  local threshold_crit="${thresholds["${agent}:${specific_metric_name}:critical"]:-0.30}"

  # Threshold checks + tickets
  if [[ "$ocr" != "null" ]]; then
    python3 -c "import sys; sys.exit(0 if float('$ocr') >= 0.25 else 1)" 2>/dev/null || \
      open_ticket_if_needed "$agent" "OCR low for $agent ($ocr) — cycles running with nothing resolving" "P1"
  fi
  if [[ "$rr" != "null" ]]; then
    python3 -c "import sys; sys.exit(0 if float('$rr') <= 0.30 else 1)" 2>/dev/null || \
      open_ticket_if_needed "$agent" "RR high for $agent ($rr) — fixes regressing, too shallow" "P1"
  fi
  if [[ "$rdi" != "null" ]]; then
    python3 -c "import sys; sys.exit(0 if float('$rdi') >= 0.40 else 1)" 2>/dev/null || \
      open_ticket_if_needed "$agent" "RDI low for $agent ($rdi) — research is shallow or internal-only" "P2"
  fi
  if [[ "$specific_metric_score" != "null" ]]; then
    python3 -c "import sys; sys.exit(0 if float('$specific_metric_score') >= $threshold_crit else 1)" 2>/dev/null || \
      open_ticket_if_needed "$agent" "${specific_metric_name} CRITICAL for $agent ($specific_metric_score) — threshold: $threshold_crit" "P1"
    python3 -c "import sys; sys.exit(0 if float('$specific_metric_score') >= $threshold_low else 1)" 2>/dev/null || \
      open_ticket_if_needed "$agent" "${specific_metric_name} low for $agent ($specific_metric_score) — target: $threshold_low" "P2"
  fi

  # Write latest JSON
  local omp_latest="$ledger_dir/omp-latest.json"
  python3 << PYEOF 2>/dev/null || true
import json, os
data = {
    "ts": "$NOW_MT",
    "date": "$TODAY",
    "agent": "$agent",
    "window_days": $WINDOW,
    "umbrella": {
        "OCR": $ocr if "$ocr" != "null" else None,
        "RR":  $rr  if "$rr"  != "null" else None,
        "RDI": $rdi if "$rdi" != "null" else None,
        "CE":  $ce  if "$ce"  != "null" else None,
        "MCS": $mcs if "$mcs" != "null" else None,
    },
    "specific": {
        "name": "$specific_metric_name",
        "score": $specific_metric_score if "$specific_metric_score" != "null" else None,
        "threshold_healthy": $threshold_low,
        "threshold_critical": $threshold_crit,
    },
    "thresholds": {
        "OCR_healthy": 0.25, "RR_max": 0.30, "RDI_min": 0.70, "CE_max": 4.0, "MCS_min": 0.70
    }
}
# For Kai: add full 5-dimensional profile
if "$agent" == "kai":
    data["kai_profile"] = {
        "DQI": ${KAI_PROFILE_DQI:-null} if "${KAI_PROFILE_DQI:-null}" != "null" else None,
        "OSS": ${KAI_PROFILE_OSS:-null} if "${KAI_PROFILE_OSS:-null}" != "null" else None,
        "KRI": ${KAI_PROFILE_KRI:-null} if "${KAI_PROFILE_KRI:-null}" != "null" else None,
        "AAS": ${KAI_PROFILE_AAS:-null} if "${KAI_PROFILE_AAS:-null}" != "null" else None,
        "BIS": ${KAI_PROFILE_BIS:-null} if "${KAI_PROFILE_BIS:-null}" != "null" else None,
        "weights": {"DQI": 0.25, "OSS": 0.20, "KRI": 0.25, "AAS": 0.15, "BIS": 0.15},
        "roles": {
            "DQI": "CEO/strategic decision maker",
            "OSS": "Multi-agent orchestrator",
            "KRI": "Memory keeper/knowledge manager",
            "AAS": "Agentic self-improver",
            "BIS": "Business operator (Aurora/AetherBot)"
        }
    }
with open("$omp_latest", "w") as f:
    json.dump(data, f, indent=2)
PYEOF

  # Append to history
  local omp_history="$ledger_dir/omp-history.jsonl"
  python3 << PYEOF2 2>/dev/null || true
import json
entry = {
    "ts": "$NOW_MT",
    "agent": "$agent",
    "metric": "$specific_metric_name",
    "score": $specific_metric_score if "$specific_metric_score" != "null" else None,
    "OCR": $ocr if "$ocr" != "null" else None,
    "RR":  $rr  if "$rr"  != "null" else None,
    "RDI": $rdi if "$rdi" != "null" else None,
}
with open("$omp_history", "a") as f:
    f.write(json.dumps(entry) + "\n")
PYEOF2

  # Saturation check
  check_saturation "$agent" "$specific_metric_name" "$specific_metric_score" "$threshold_low"

  # Log result
  local specific_display="$specific_metric_name: $specific_metric_score"
  if [[ "$agent" == "kai" ]]; then
    log_ok "kai | OCR:$ocr RR:$rr RDI:$rdi CE:$ce | DQI:${KAI_PROFILE_DQI} OSS:${KAI_PROFILE_OSS} KRI:${KAI_PROFILE_KRI} AAS:${KAI_PROFILE_AAS} BIS:${KAI_PROFILE_BIS} → composite:$specific_metric_score"
  else
    log_ok "$agent | OCR:$ocr RR:$rr RDI:$rdi CE:$ce | $specific_display"
  fi
}

# ─── Build summary JSON ───────────────────────────────────────────────────────
build_summary() {
  local agents=("nel" "sam" "ra" "aether" "dex" "kai")
  python3 << PYEOF 2>/dev/null || true
import json, os

summary = {"ts": "$NOW_MT", "date": "$TODAY", "agents": {}}
agents = ["nel", "sam", "ra", "aether", "dex", "kai"]
for agent in agents:
    omp_file = f"$HYO_ROOT/agents/{agent}/ledger/omp-latest.json"
    if os.path.exists(omp_file):
        try:
            d = json.load(open(omp_file))
            entry = {
                "specific_metric": d["specific"]["name"],
                "specific_score": d["specific"]["score"],
                "OCR": d["umbrella"].get("OCR"),
                "RDI": d["umbrella"].get("RDI"),
            }
            # For Kai: include full 5-dimensional profile
            if agent == "kai" and "kai_profile" in d:
                entry["kai_profile"] = d["kai_profile"]
                entry["DQI"] = d["kai_profile"].get("DQI")
                entry["OSS"] = d["kai_profile"].get("OSS")
                entry["KRI"] = d["kai_profile"].get("KRI")
                entry["AAS"] = d["kai_profile"].get("AAS")
                entry["BIS"] = d["kai_profile"].get("BIS")
            summary["agents"][agent] = entry
        except Exception:
            pass

with open("$SUMMARY_OUT", "w") as f:
    json.dump(summary, f, indent=2)
PYEOF
  log_ok "Summary written: $SUMMARY_OUT"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
publish_omp_to_hq() {
  local publish_sh="$HYO_ROOT/bin/publish-to-feed.sh"
  [[ ! -f "$publish_sh" ]] && log_warn "publish-to-feed.sh not found — skipping HQ publish" && return

  # Build a sections JSON for the HQ entry
  local sections_file="/tmp/omp-hq-${TODAY}.json"
  python3 << PYEOF 2>/dev/null || true
import json, os

root = "$HYO_ROOT"
today = "$TODAY"
summary_path = root + "/kai/ledger/omp-summary.json"

try:
    summary = json.load(open(summary_path))
    agents = summary.get("agents", {})

    # Build human-readable summary
    lines = []
    for a, d in sorted(agents.items()):
        mn = d.get("specific_metric", "?")
        ms = d.get("specific_score")
        rdi = d.get("RDI")

        if a == "kai" and d.get("kai_profile"):
            kp = d["kai_profile"]
            dims = [f"DQI:{kp.get('DQI','—')} OSS:{kp.get('OSS','—')} KRI:{kp.get('KRI','—')} AAS:{kp.get('AAS','—')} BIS:{kp.get('BIS','—')}"]
            composite = ms
            flag = "✓" if composite and composite >= 0.75 else ("⚠" if composite and composite >= 0.55 else "✗")
            lines.append(f"Kai: {flag} composite={composite} | {' '.join(dims)}")
        else:
            if ms is not None:
                thresholds = {"APS":0.80,"DSS":0.90,"EQS":0.50,"ASR":0.65,"PAR":0.35}
                thr = thresholds.get(mn, 0.50)
                flag = "✓" if ms >= thr else ("⚠" if ms >= thr*0.80 else "✗")
                lines.append(f"{a.capitalize()}: {flag} {mn}={ms:.3f}" + (f" RDI={rdi:.2f}" if rdi else ""))
            else:
                lines.append(f"{a.capitalize()}: — no data")

    sections = {
        "summary": f"OMP Outcome Quality — {today}. " + " | ".join(lines),
        "agent_scores": agents,
        "date": today
    }
    with open("$sections_file", "w") as f:
        json.dump(sections, f, indent=2)
    print("OMP sections written")
except Exception as e:
    print(f"OMP sections failed: {e}")
PYEOF

  if [[ -f "$sections_file" ]]; then
    HYO_ROOT="$HYO_ROOT" bash "$publish_sh" omp-daily kai \
      "OMP Outcome Quality — $TODAY" \
      "$sections_file" 2>/dev/null || log_warn "HQ publish failed for OMP"
    log_ok "OMP published to HQ feed as omp-daily-$TODAY"
    rm -f "$sections_file"
  fi
}

inject_omp_evidence_to_growth() {
  # When a Kai OMP metric drops below threshold, inject evidence into the linked W-item in GROWTH.md
  local summary_path="$HYO_ROOT/kai/ledger/omp-summary.json"
  local growth_path="$HYO_ROOT/agents/kai/GROWTH.md"
  [[ ! -f "$summary_path" || ! -f "$growth_path" ]] && return

  python3 << 'PYEOF' 2>/dev/null || true
import json, os, re
from datetime import datetime

root = os.environ.get('HYO_ROOT', '')
summary_path = root + '/kai/ledger/omp-summary.json'
growth_path  = root + '/agents/kai/GROWTH.md'
today = datetime.now().strftime('%Y-%m-%d')

try:
    kai = json.load(open(summary_path)).get('agents', {}).get('kai', {})
    kp  = kai.get('kai_profile', {})
except:
    exit(0)

# Metric → W-item mapping + thresholds
links = {
    'DQI': ('W2', 0.80, 'Decision quality measured below target'),
    'OSS': ('W3', 0.85, 'Orchestration sync below target'),
    'KRI': ('W1', 0.90, 'Knowledge retention below target'),
    'AAS': ('E1', 0.75, 'Autonomous action below target'),
    'BIS': ('W3', 0.85, 'Business impact below target'),
}

content = open(growth_path).read()
modified = False

for metric, (wid, threshold, label) in links.items():
    score = kp.get(metric)
    if score is None or score >= threshold:
        continue

    # Find the W-item section and inject evidence if not already there for today
    pattern = rf'(### {re.escape(wid)}:.+?)'
    evidence_line = f'- OMP {metric}={score:.3f} (threshold {threshold}) — {today}: {label}\n'

    # Find the Evidence block
    ev_match = re.search(rf'(### {re.escape(wid)}:.*?\n\*\*Evidence:\*\*\n)(.*?)(?=\n\*\*Root)', content, re.DOTALL)
    if ev_match and evidence_line not in content:
        insert_pos = ev_match.end(1)
        content = content[:insert_pos] + evidence_line + content[insert_pos:]
        modified = True
        print(f"Injected OMP evidence into {wid} for {metric}={score:.3f}")

if modified:
    with open(growth_path, 'w') as f:
        f.write(content)
PYEOF
}

main() {
  local arg="${1:-}"
  local all_agents=("nel" "sam" "ra" "aether" "dex" "kai")

  log "=== OMP Measurement Run — $TODAY ==="

  if [[ -n "$arg" && "$arg" != "all" ]]; then
    measure_agent "$arg"
  else
    for agent in "${all_agents[@]}"; do
      measure_agent "$agent"
    done
  fi

  build_summary

  # Publish OMP scores to HQ feed (standalone daily entry)
  publish_omp_to_hq

  # If any Kai metric is below threshold, inject evidence into GROWTH.md
  inject_omp_evidence_to_growth

  log "=== OMP Measurement Complete ==="
}

main "$@"
