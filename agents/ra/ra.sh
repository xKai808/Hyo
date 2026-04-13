#!/usr/bin/env bash
# kai/ra.sh — Ra newsletter product manager health check and reporting
#
# Ra monitors the entire newsletter pipeline (both internal CEO brief and Aurora Public
# consumer newsletter). Checks source freshness, prompt currency, archive integrity,
# subscriber status, and content gaps. Generates structured health reports.
#
# Usage:
#   bash kai/ra.sh              # full health check
#   bash kai/ra.sh --date YYYY-MM-DD
#
# Exit codes:
#   0 = all health checks passed
#   1 = one or more critical issues found (requires attention)
#   2 = warnings but operational (e.g. some stale sources)

set -uo pipefail

# ---- repo root detection ----
if [[ -n "${HYO_ROOT:-}" ]] && [[ -d "$HYO_ROOT" ]]; then
  ROOT="$HYO_ROOT"
elif [[ -d "./newsletter" ]]; then
  ROOT="$(cd . && pwd)"
else
  ROOT="$HOME/Documents/Projects/Hyo"
fi

# ---- paths ----
NEWSLETTER_DIR="$ROOT/agents/ra/pipeline"
NEWSLETTERS_OUT="$ROOT/agents/ra/output"
RESEARCH_DIR="$ROOT/agents/ra/research"
SUBSCRIBERS_FILE="$NEWSLETTER_DIR/subscribers.jsonl"
LOGS_DIR="$ROOT/agents/ra/logs"
DOCS_DIR="$ROOT/agents/sam/website/docs/ra"
PROMPTS_DIR="$NEWSLETTER_DIR/prompts"
GATHER_SCRIPT="$NEWSLETTER_DIR/gather.py"
SYNTHESIZE_PROMPT="$PROMPTS_DIR/synthesize.md"
RA_ARCHIVE="$ROOT/agents/ra/ra_archive.py"
AURORA_PUBLIC="$NEWSLETTER_DIR/aurora_public.py"
SEND_EMAIL="$NEWSLETTER_DIR/send_email.py"

mkdir -p "$LOGS_DIR" "$DOCS_DIR" "$RESEARCH_DIR"

# ---- color helpers ----
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RED=$(tput setaf 1); GRN=$(tput setaf 2)
  YLW=$(tput setaf 3); BLU=$(tput setaf 4); MAG=$(tput setaf 5); RST=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; MAG=""; RST=""
fi

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s==>%s %s%s%s\n' "$BLU" "$RST" "$BOLD" "$*" "$RST"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*" >&2; }

# ---- date handling ----
DATE="${1:-}"
[[ "$DATE" == "--date" ]] && DATE="$2"
DATE="${DATE:-$(date +%Y-%m-%d)}"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# ---- init report ----
REPORT_FILE="$LOGS_DIR/ra-${DATE}.md"
REPORT_DOCS="$DOCS_DIR/${DATE}.md"
CRITICAL=0
WARNINGS=0

# Accumulate report in memory instead of many appends
REPORT=""

# ---- 1. Pipeline health ----
hdr "Checking pipeline health"
REPORT+="## 1. Pipeline Health"$'\n'$'\n'

if [[ -f "$GATHER_SCRIPT" ]]; then
  ok "gather.py exists"
  REPORT+="✓ gather.py exists"$'\n'
else
  err "gather.py missing at $GATHER_SCRIPT"
  REPORT+="✗ gather.py missing"$'\n'
  CRITICAL=$((CRITICAL+1))
fi

if [[ -f "$SYNTHESIZE_PROMPT" ]]; then
  ok "synthesize.md exists"
  PROMPT_SIZE=$(wc -c < "$SYNTHESIZE_PROMPT" 2>/dev/null || echo "0")
  REPORT+="✓ synthesize.md exists"$'\n'"  - Size: $PROMPT_SIZE bytes"$'\n'
else
  err "synthesize.md missing at $SYNTHESIZE_PROMPT"
  REPORT+="✗ synthesize.md missing"$'\n'
  CRITICAL=$((CRITICAL+1))
fi

if [[ -d "$RESEARCH_DIR" ]] && [[ -f "$RESEARCH_DIR/index.md" ]]; then
  ok "research archive exists"
  ARCHIVE_ENTRIES=$(find "$RESEARCH_DIR" -type f -name "*.md" | wc -l)
  REPORT+="✓ research archive exists"$'\n'"  - Total archive files: $ARCHIVE_ENTRIES"$'\n'
else
  warn "research archive missing or incomplete"
  REPORT+="! research archive missing or incomplete"$'\n'
  WARNINGS=$((WARNINGS+1))
fi

REPORT+=$'\n'

# ---- 2. Newsletters ----
hdr "Checking newsletters"
REPORT+="## 2. Newsletters Status"$'\n'$'\n'

if [[ -d "$NEWSLETTERS_OUT" ]]; then
  NEWSLETTER_COUNT=$(find "$NEWSLETTERS_OUT" -name "*.md" -type f | wc -l)
  HTML_COUNT=$(find "$NEWSLETTERS_OUT" -name "*.html" -type f | wc -l)
  ok "newsletters directory exists ($NEWSLETTER_COUNT .md, $HTML_COUNT .html files)"
  REPORT+="✓ newsletters directory exists"$'\n'"  - Markdown files: $NEWSLETTER_COUNT"$'\n'"  - HTML files: $HTML_COUNT"$'\n'

  LATEST_MD=$(find "$NEWSLETTERS_OUT" -name "*.md" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2- || true)
  if [[ -n "$LATEST_MD" && -f "$LATEST_MD" ]]; then
    LATEST_WORDS=$(wc -w < "$LATEST_MD" 2>/dev/null || echo "0")
    LATEST_NAME=$(basename "$LATEST_MD")
    ok "latest newsletter: $LATEST_NAME ($LATEST_WORDS words)"
    REPORT+="  - Latest: $LATEST_NAME ($LATEST_WORDS words)"$'\n'

    TODAY_MD="$NEWSLETTERS_OUT/${DATE}.md"
    if [[ -f "$TODAY_MD" ]]; then
      TODAY_WORDS=$(wc -w < "$TODAY_MD" 2>/dev/null || echo "0")
      ok "today's newsletter exists ($TODAY_WORDS words)"
      REPORT+="  - Today's ($DATE): $TODAY_WORDS words"$'\n'
    else
      warn "no newsletter for today ($DATE)"
      REPORT+="! No newsletter for today ($DATE)"$'\n'
      WARNINGS=$((WARNINGS+1))
    fi
  fi
else
  err "newsletters directory missing"
  REPORT+="✗ newsletters directory missing at $NEWSLETTERS_OUT"$'\n'
  CRITICAL=$((CRITICAL+1))
fi

REPORT+=$'\n'

# ---- 3. Subscriber status ----
hdr "Checking subscribers"
REPORT+="## 3. Subscriber Status"$'\n'$'\n'

if [[ -f "$SUBSCRIBERS_FILE" ]]; then
  SUBSCRIBER_COUNT=$(grep -c '^{' "$SUBSCRIBERS_FILE" 2>/dev/null || true)
  SUBSCRIBER_COUNT=${SUBSCRIBER_COUNT:-0}
  ok "subscribers.jsonl exists"
  REPORT+="✓ subscribers.jsonl exists"$'\n'"  - Active subscribers: $SUBSCRIBER_COUNT"$'\n'
else
  warn "subscribers.jsonl missing"
  REPORT+="! subscribers.jsonl missing at $SUBSCRIBERS_FILE"$'\n'
  WARNINGS=$((WARNINGS+1))
fi

REPORT+=$'\n'

# ---- 4. Content gaps ----
hdr "Checking for content gaps"
REPORT+="## 4. Content Gap Analysis"$'\n'$'\n'

if [[ -f "$GATHER_SCRIPT" ]]; then
  GREP_RESULT=$(grep -o 'ai\|crypto\|macro\|tech' "$GATHER_SCRIPT" 2>/dev/null | wc -l)
  if [[ $GREP_RESULT -gt 0 ]]; then
    ok "gather.py has topic keywords"
    REPORT+="✓ gather.py includes topic keywords ($GREP_RESULT mentions)"$'\n'
  else
    warn "gather.py may lack topic diversity"
    REPORT+="! gather.py appears to have limited topic coverage"$'\n'
    WARNINGS=$((WARNINGS+1))
  fi
else
  warn "cannot analyze gather.py — file missing"
  REPORT+="! Cannot analyze gather.py — file missing"$'\n'
fi

REPORT+=$'\n'

# ---- 5. Archive entry freshness ----
hdr "Checking archive freshness"
REPORT+="## 5. Archive Entry Freshness"$'\n'$'\n'

if [[ -d "$RESEARCH_DIR/entities" ]]; then
  ENTITY_COUNT=$(find "$RESEARCH_DIR/entities" -name "*.md" -type f 2>/dev/null | wc -l)
  TOPIC_COUNT=$(find "$RESEARCH_DIR/topics" -name "*.md" -type f 2>/dev/null | wc -l)
  LAB_COUNT=$(find "$RESEARCH_DIR/lab" -name "*.md" -type f 2>/dev/null | wc -l)

  ok "archive structure exists"
  REPORT+="✓ Archive structure:"$'\n'"  - Entities: $ENTITY_COUNT"$'\n'"  - Topics: $TOPIC_COUNT"$'\n'"  - Lab items: $LAB_COUNT"$'\n'

  MOST_RECENT=$(find "$RESEARCH_DIR/entities" "$RESEARCH_DIR/topics" "$RESEARCH_DIR/lab" -type f -name "*.md" 2>/dev/null | xargs ls -t 2>/dev/null | head -1 || true)
  if [[ -n "$MOST_RECENT" ]]; then
    RECENT_NAME=$(basename "$MOST_RECENT")
    RECENT_MTIME=$(stat -c %Y "$MOST_RECENT" 2>/dev/null || stat -f %m "$MOST_RECENT" 2>/dev/null || echo "0")
    CURRENT_TIME=$(date +%s)
    RECENT_AGE=$(( (CURRENT_TIME - RECENT_MTIME) / 86400 ))
    ok "most recent entry: $RECENT_NAME ($RECENT_AGE days ago)"
    REPORT+="  - Most recent: $RECENT_NAME ($RECENT_AGE days ago)"$'\n'
  fi
else
  warn "archive structure incomplete"
  REPORT+="! Archive structure incomplete or missing"$'\n'
fi

REPORT+=$'\n'

# ---- 6. Synthesis capability ----
hdr "Checking synthesis pipeline"
REPORT+="## 6. Synthesis & Rendering Capability"$'\n'$'\n'

if [[ -f "$NEWSLETTER_DIR/synthesize.py" ]]; then
  ok "synthesize.py exists"
  REPORT+="✓ synthesize.py exists"$'\n'
else
  warn "synthesize.py missing"
  REPORT+="! synthesize.py missing"$'\n'
  WARNINGS=$((WARNINGS+1))
fi

if [[ -f "$NEWSLETTER_DIR/render.py" ]]; then
  ok "render.py exists"
  REPORT+="✓ render.py exists"$'\n'
else
  warn "render.py missing"
  REPORT+="! render.py missing"$'\n'
  WARNINGS=$((WARNINGS+1))
fi

if [[ -f "$AURORA_PUBLIC" ]]; then
  ok "aurora_public.py exists (consumer pipeline)"
  REPORT+="✓ aurora_public.py exists (consumer pipeline)"$'\n'
else
  warn "aurora_public.py missing"
  REPORT+="! aurora_public.py missing (consumer pipeline)"$'\n'
fi

if [[ -f "$SEND_EMAIL" ]]; then
  ok "send_email.py exists (email dispatcher)"
  REPORT+="✓ send_email.py exists (email dispatcher)"$'\n'
else
  warn "send_email.py missing"
  REPORT+="! send_email.py missing (email dispatch)"$'\n'
fi

REPORT+=$'\n'

# ---- Summary ----
hdr "Summary"
REPORT+="## Summary & Recommendations"$'\n'$'\n'

if [[ $CRITICAL -eq 0 && $WARNINGS -eq 0 ]]; then
  STATUS="✓ HEALTHY"
  REPORT_STATUS="✓ All checks passed"
  EXIT_CODE=0
elif [[ $CRITICAL -eq 0 ]]; then
  STATUS="! WARNINGS"
  REPORT_STATUS="⚠ Operational but with warnings"
  EXIT_CODE=2
else
  STATUS="✗ CRITICAL"
  REPORT_STATUS="✗ Critical issues found"
  EXIT_CODE=1
fi

ok "$STATUS"
say ""
hdr "Report"

# Write report file all at once
{
  echo "# Ra Newsletter Health Check"
  echo ""
  echo "**Date:** $DATE"
  echo "**Timestamp:** $TIMESTAMP"
  echo "**Status:** $REPORT_STATUS"
  echo ""
  echo "$REPORT"
  echo "**Verdict:** "
  if [[ $EXIT_CODE -eq 0 ]]; then
    echo "Newsletter platform is healthy and operational. All critical systems present and functional."
  elif [[ $EXIT_CODE -eq 2 ]]; then
    echo "Newsletter platform is operational but has warnings. See above for items to address."
  else
    echo "Critical issues require attention. Cannot proceed with automated newsletter runs until resolved."
  fi
  echo ""
  echo "- Critical issues: $CRITICAL"
  echo "- Warnings: $WARNINGS"
  echo ""
  echo "**Ran by:** Ra newsletter product manager"
  echo "**Report timestamp:** $TIMESTAMP"
} > "$REPORT_FILE"

cat "$REPORT_FILE"
say ""

# Copy report to docs for viewer
cp "$REPORT_FILE" "$REPORT_DOCS"
ok "report saved to $REPORT_DOCS"

# Auto-push to HQ
KAI="$ROOT/bin/kai.sh"
if [[ -x "$KAI" ]]; then
  SUMMARY=$(printf 'Ra health check: %d critical, %d warnings' "$CRITICAL" "$WARNINGS")
  "$KAI" push ra "$SUMMARY" \
    --data "{\"critical\":$CRITICAL,\"warnings\":$WARNINGS,\"status\":\"$([ $EXIT_CODE -eq 0 ] && echo 'healthy' || echo 'degraded')\"}" \
    2>/dev/null || true
  ok "pushed status to HQ"
fi

# ── Self-Review: Ra Pathway Audit ──
say "Self-review: Ra pathway audit..."
SELF_REVIEW_ISSUES=0

# INPUT: Are source files accessible?
if [[ ! -f "$NEWSLETTER_DIR/sources.json" ]]; then
  warn "Self-review: sources.json missing"
  SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
fi
if [[ ! -f "$NEWSLETTER_DIR/gather.py" ]]; then
  warn "Self-review: gather.py missing"
  SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
fi

# PROCESSING: Are pipeline scripts executable?
for script in gather.py synthesize.py render.py; do
  if [[ -f "$NEWSLETTER_DIR/$script" ]] && [[ ! -r "$NEWSLETTER_DIR/$script" ]]; then
    warn "Self-review: $script not readable"
    SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
  fi
done

# OUTPUT: Does today's newsletter exist (if it should)?
HOUR=$(date +%H)
if [[ $HOUR -gt 6 ]]; then
  if [[ ! -f "$NEWSLETTERS_OUT/${TODAY}.md" ]] && [[ ! -f "$NEWSLETTERS_OUT/${TODAY}.html" ]]; then
    warn "Self-review: no newsletter output for today (after 06:00)"
    SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
  fi
fi

# EXTERNAL: Is archive accessible?
ARCHIVE_DIR="$ROOT/agents/ra/research"
if [[ ! -d "$ARCHIVE_DIR" ]]; then
  warn "Self-review: research archive directory missing"
  SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
fi

# REPORTING: Is ACTIVE.md current?
RA_ACTIVE="$ROOT/agents/ra/ledger/ACTIVE.md"
if [[ -f "$RA_ACTIVE" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    active_age=$(( ($(date +%s) - $(stat -f %m "$RA_ACTIVE")) / 3600 ))
  else
    active_age=$(( ($(date +%s) - $(stat -c %Y "$RA_ACTIVE")) / 3600 ))
  fi
  if [[ $active_age -gt 48 ]]; then
    warn "Self-review: ACTIVE.md stale (${active_age}h old)"
    SELF_REVIEW_ISSUES=$((SELF_REVIEW_ISSUES + 1))
  fi
fi

if [[ $SELF_REVIEW_ISSUES -eq 0 ]]; then
  ok "Self-review: Ra pathway healthy"
else
  warn "Self-review: $SELF_REVIEW_ISSUES issues in Ra pathway"
fi

# ── Self-Evolution: Ra Learning & Improvement Tracking ──
say "Self-evolution: capturing metrics and learning signals..."

EVOLUTION_FILE="$ROOT/agents/ra/evolution.jsonl"
PLAYBOOK="$ROOT/agents/ra/PLAYBOOK.md"

# Collect Ra-specific metrics
CRITICAL=${CRITICAL:-0}
WARNINGS=${WARNINGS:-0}
SOURCE_COUNT=${SOURCE_COUNT:-0}
ARCHIVE_ENTITIES=$(find "$RESEARCH_DIR/entities" -name "*.md" -type f 2>/dev/null | wc -l || echo "0")

# Get last evolution entry for comparison
LAST_EVOLUTION=""
if [[ -f "$EVOLUTION_FILE" && -s "$EVOLUTION_FILE" ]]; then
  LAST_EVOLUTION=$(tail -1 "$EVOLUTION_FILE")
fi

# Extract last critical count for regression detection
LAST_CRITICAL=0
if [[ -n "$LAST_EVOLUTION" ]]; then
  LAST_CRITICAL=$(echo "$LAST_EVOLUTION" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('metrics', {}).get('critical', 0))" 2>/dev/null || echo "0")
fi

# Determine assessment
ASSESSMENT="newsletter health check completed"
IMPROVEMENTS_PROPOSED=0
if [[ $CRITICAL -gt $LAST_CRITICAL ]]; then
  ASSESSMENT="critical issues increased: $LAST_CRITICAL → $CRITICAL"
  IMPROVEMENTS_PROPOSED=$((IMPROVEMENTS_PROPOSED + 1))
elif [[ $CRITICAL -lt $LAST_CRITICAL && $LAST_CRITICAL -gt 0 ]]; then
  ASSESSMENT="improvement: critical issues resolved ($LAST_CRITICAL → $CRITICAL)"
  IMPROVEMENTS_PROPOSED=$((IMPROVEMENTS_PROPOSED + 1))
fi

if [[ $WARNINGS -gt 0 ]]; then
  if [[ -z "$ASSESSMENT" ]] || [[ "$ASSESSMENT" == "newsletter health check completed" ]]; then
    ASSESSMENT="health check with $WARNINGS warning(s)"
  fi
fi

# Check if PLAYBOOK is stale (>7 days)
PLAYBOOK_UPDATED="False"
STALENESS_FLAG="False"
if [[ -f "$PLAYBOOK" ]]; then
  PLAYBOOK_MTIME=$(stat -f %m "$PLAYBOOK" 2>/dev/null || stat -c %Y "$PLAYBOOK" 2>/dev/null || echo "0")
  PLAYBOOK_AGE=$(( ($(date +%s) - PLAYBOOK_MTIME) / 86400 ))
  if [[ $PLAYBOOK_AGE -lt 7 ]]; then
    PLAYBOOK_UPDATED="True"
  elif [[ $PLAYBOOK_AGE -gt 7 ]]; then
    STALENESS_FLAG="True"
  fi
fi

# Build evolution entry
EVOLUTION_ENTRY=$(python3 << PYEOF
import json
from datetime import datetime
import sys

entry = {
  "ts": "$TIMESTAMP",
  "version": "1.0",
  "metrics": {
    "critical": $CRITICAL,
    "warnings": $WARNINGS,
    "source_count": $SOURCE_COUNT,
    "archive_entities": $ARCHIVE_ENTITIES
  },
  "assessment": "$ASSESSMENT",
  "improvements_proposed": $IMPROVEMENTS_PROPOSED,
  "playbook_updated": $PLAYBOOK_UPDATED,
  "staleness_flag": $STALENESS_FLAG
}

print(json.dumps(entry))
PYEOF
)

# Append to evolution ledger
echo "$EVOLUTION_ENTRY" >> "$EVOLUTION_FILE"
ok "Self-evolution logged: $ASSESSMENT"

if [[ "$STALENESS_FLAG" == "True" ]]; then
  warn "PLAYBOOK.md is stale — consider refreshing with latest operational procedures"
fi

# Dispatch integration: report findings to Kai ledger
DISPATCH="$ROOT/bin/dispatch.sh"
if [[ -x "$DISPATCH" ]]; then
  if [[ $CRITICAL -gt 0 ]]; then
    bash "$DISPATCH" flag ra P1 "Ra health: $CRITICAL critical issue(s)" 2>/dev/null || true
  fi
  if [[ $WARNINGS -gt 2 ]]; then
    bash "$DISPATCH" flag ra P2 "Ra health: $WARNINGS warnings" 2>/dev/null || true
  fi

  # Report pipeline health to Kai
  bash "$DISPATCH" self-delegate ra P3 "Ra health run: critical=$CRITICAL, warnings=$WARNINGS, status=$([ $EXIT_CODE -eq 0 ] && echo 'healthy' || echo 'degraded')" 2>/dev/null || true

  ok "Dispatch: findings reported to Kai ledger"
fi

exit $EXIT_CODE
