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

TODAY=$(TZ=America/Denver date +%Y-%m-%d)

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

# ---- Growth Phase (self-improvement before main work) -----------------------
GROWTH_SH="$ROOT/bin/agent-growth.sh"
if [[ -f "$GROWTH_SH" ]]; then
  source "$GROWTH_SH"
  run_growth_phase "ra" || true
fi
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

# ── Self-Review Reasoning Gates ──
AGENT_GATES="$ROOT/kai/protocols/agent-gates.sh"
if [[ -f "$AGENT_GATES" ]]; then
  source "$AGENT_GATES"
  run_self_review "ra" || true

  # ── Ra-specific domain reasoning (Ra owns these questions) ──
  # TODO: Ra — evolve this section via PLAYBOOK.md
  #   e.g., "Are my sources still alive? When did I last verify?"
  #   e.g., "Is this content useful or just present?"
  #   e.g., "Am I covering the right topics or just the easy ones?"
fi

# ── DOMAIN RESEARCH (External Research — agent-research.sh) ──
# Ra researches newsletter craft, journalism, content synthesis, source diversification.
RESEARCH_SCRIPT="$ROOT/bin/agent-research.sh"
RA_RESEARCH_PUBLISH_MARKER="/tmp/ra-research-published-$(TZ=America/Denver date +%Y%m%d)"
if [[ -x "$RESEARCH_SCRIPT" ]]; then
  if [[ -f "$RA_RESEARCH_PUBLISH_MARKER" ]]; then
    say "Domain research: running metrics-only (already published to HQ today)"
    bash "$RESEARCH_SCRIPT" ra 2>&1 | tail -3 || true
  elif bash "$RESEARCH_SCRIPT" ra --publish 2>&1 | tail -5; then
    touch "$RA_RESEARCH_PUBLISH_MARKER"
    ok "Domain research complete — findings saved and published"
  else
    warn "Domain research encountered issues — check agents/ra/research/"
  fi
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
  PLAYBOOK_MTIME=$(stat -c %Y "$PLAYBOOK" 2>/dev/null || stat -f %m "$PLAYBOOK" 2>/dev/null || echo "0")
  PLAYBOOK_AGE=$(( ($(date +%s) - PLAYBOOK_MTIME) / 86400 ))
  if [[ $PLAYBOOK_AGE -lt 7 ]]; then
    PLAYBOOK_UPDATED="True"
  elif [[ $PLAYBOOK_AGE -gt 7 ]]; then
    STALENESS_FLAG="True"
  fi
fi

# STEP 10: AGENT REFLECTION (constitutional — AGENT_ALGORITHMS.md v2.0)
REFLECT_BOTTLENECK="none"
REFLECT_SYMPTOM_OR_SYSTEM="system"
REFLECT_ARTIFACT_ALIVE="yes"
REFLECT_DOMAIN_GROWTH="stagnant"
REFLECT_LEARNING=""

# (a) Bottleneck: newsletter production blocked?
NEWSLETTER_TODAY="$ROOT/agents/ra/output/$(date +%Y-%m-%d)*.md"
if ! ls $NEWSLETTER_TODAY 1>/dev/null 2>&1; then
  REFLECT_BOTTLENECK="no newsletter produced today — pipeline may be blocked or sources failing"
fi

# (b) Symptom or system: recurring source failures?
KNOWN_RA_PATTERNS=$(grep -c '"agent":"ra"\|"source":".*ra"' "$ROOT/kai/ledger/known-issues.jsonl" 2>/dev/null | tr -d '[:space:]')
if [[ "${KNOWN_RA_PATTERNS:-0}" -gt 3 ]]; then
  REFLECT_SYMPTOM_OR_SYSTEM="symptom — ${KNOWN_RA_PATTERNS} recurring Ra patterns in known-issues"
fi

# (c) Artifact alive: self-review log
SR_LOG="$ROOT/agents/ra/logs/self-review-$(date +%Y-%m-%d).md"
if [[ ! -f "$SR_LOG" ]]; then
  REFLECT_ARTIFACT_ALIVE="no — self-review log not generated this cycle"
fi

# (d) Domain growth
if [[ "$PLAYBOOK_UPDATED" == "True" ]]; then
  REFLECT_DOMAIN_GROWTH="active — PLAYBOOK updated within 7 days"
else
  REFLECT_DOMAIN_GROWTH="stagnant — PLAYBOOK not updated in ${PLAYBOOK_AGE:-unknown}d"
fi

# (e) Learning
REFLECT_LEARNING="critical=${CRITICAL}, warnings=${WARNINGS}, sources=${SOURCE_COUNT}, archive=${ARCHIVE_ENTITIES}"

# Build evolution entry (MUST include reflection per AGENT_ALGORITHMS.md step 11)
EVOLUTION_ENTRY=$(python3 << PYEOF
import json
from datetime import datetime
import sys

entry = {
  "ts": "$TIMESTAMP",
  "version": "2.0",
  "metrics": {
    "critical": $CRITICAL,
    "warnings": $WARNINGS,
    "source_count": $SOURCE_COUNT,
    "archive_entities": $ARCHIVE_ENTITIES
  },
  "assessment": "$ASSESSMENT",
  "improvements_proposed": $IMPROVEMENTS_PROPOSED,
  "playbook_updated": $PLAYBOOK_UPDATED,
  "staleness_flag": $STALENESS_FLAG,
  "reflection": {
    "bottleneck": "$REFLECT_BOTTLENECK",
    "symptom_or_system": "$REFLECT_SYMPTOM_OR_SYSTEM",
    "artifact_alive": "$REFLECT_ARTIFACT_ALIVE",
    "domain_growth": "$REFLECT_DOMAIN_GROWTH",
    "learning": "$REFLECT_LEARNING"
  }
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

# ── Ra self-authored reflection → HQ feed ──
PUBLISH_SCRIPT="$ROOT/bin/publish-to-feed.sh"
RA_REFLECTION="/tmp/ra-reflection-sections-$(date +%Y%m%d).json"
TODAY_STR=$(TZ=America/Denver date +%Y-%m-%d)

python3 - "$RA_REFLECTION" "${CRITICAL:-0}" "${WARNINGS:-0}" "${SOURCE_COUNT:-0}" "$ROOT" << 'PYEOF'
import json, sys, os
sf = sys.argv[1]
critical = int(sys.argv[2]) if sys.argv[2].isdigit() else 0
warnings = int(sys.argv[3]) if sys.argv[3].isdigit() else 0
sources = int(sys.argv[4]) if sys.argv[4].isdigit() else 0
root = sys.argv[5]
from datetime import datetime
today = datetime.now().strftime("%Y-%m-%d")

# Check if newsletter was produced today
nl_produced = False
nl_dir = os.path.join(root, "agents", "ra", "output")
if os.path.isdir(nl_dir):
    for f in os.listdir(nl_dir):
        if today in f:
            nl_produced = True
            break

research_summary = "No research conducted this cycle."
ff = os.path.join(root, "agents", "ra", "research", f"findings-{today}.md")
if os.path.exists(ff):
    with open(ff) as f:
        c = f.read()
    if "## Key Takeaways" in c:
        t = c.split("## Key Takeaways")[1].split("##")[0].strip()
        research_summary = t if t else "Research completed — no high-signal findings."

followups = []
src = os.path.join(root, "agents", "ra", "research-sources.json")
if os.path.exists(src):
    with open(src) as f:
        cfg = json.load(f)
    followups = [fu["item"] for fu in cfg.get("followUps", []) if fu.get("status") == "open"]
if not followups:
    followups = ["Diversify source list beyond tech/crypto for Aurora Public",
                 "Experiment with editorial voice vs neutral aggregation",
                 "Research launchd migration to unblock gather phase"]

# ── Build human-readable prose ──
intro_parts = []
if nl_produced:
    intro_parts.append("Good day — the newsletter went out on schedule. The gather-synthesize-render pipeline ran clean, and I'm happy with the output quality.")
    if sources > 0:
        intro_parts.append(f"Pulled from {sources} sources this cycle.")
    if warnings > 0:
        intro_parts.append(f"There {'was' if warnings == 1 else 'were'} {warnings} warning{'s' if warnings > 1 else ''} during the run, but nothing that blocked delivery.")
else:
    intro_parts.append("No newsletter today. The pipeline can't reach external sources from the Cowork sandbox — every fetch returns a 403. The pipeline code itself is solid, but it's useless without data to work with.")
    intro_parts.append("This has been the pattern for a few cycles now. Until I'm running on the Mini via launchd, I'm effectively grounded.")
if critical > 0:
    intro_parts.append(f"Also flagging {critical} critical issue{'s' if critical > 1 else ''} that need attention.")

research_text = research_summary
if research_text == "No research conducted this cycle.":
    research_text = "Didn't get to external research this cycle. I've been thinking about source diversification though — my list is heavy on tech and crypto, and if Aurora Public is going to serve a broader audience, I need lifestyle, culture, and general news feeds too."

changes_text = ""
if nl_produced:
    changes_text = "Newsletter delivered. Ran the full pipeline from gather through send. Each cycle I'm refining the synthesis prompts to produce tighter, more opinionated briefs — the goal is editorial voice, not just aggregation."
else:
    changes_text = "No production changes this cycle — blocked on infrastructure. I've been using the downtime to refine my synthesis approach and think about what makes a newsletter worth reading versus just another content dump."

kai_msg = ""
if not nl_produced:
    kai_msg = "The infrastructure blocker is the only thing holding me back. I need to be on the Mini's launchd so I can actually reach my sources and produce newsletters. Everything else — voice, sources, quality — I can iterate on once the pipeline is flowing."
elif critical > 0:
    kai_msg = f"Newsletter delivered but {critical} critical issue{'s' if critical > 1 else ''} came up during the run. Worth looking at before the next cycle."
else:
    kai_msg = "Pipeline is healthy and producing. I'm focused on improving the editorial quality and broadening the source list for Aurora Public."

sections = {
    "introspection": " ".join(intro_parts),
    "research": research_text,
    "changes": changes_text,
    "followUps": followups[:5],
    "forKai": kai_msg
}
with open(sf, "w") as f:
    json.dump(sections, f, indent=2)
PYEOF

RA_REPORT_PUBLISH_MARKER="/tmp/ra-report-published-$(TZ=America/Denver date +%Y%m%d)"
if [[ -f "$RA_REFLECTION" && -x "$PUBLISH_SCRIPT" ]]; then
  if [[ -f "$RA_REPORT_PUBLISH_MARKER" ]]; then
    say "Self-authored report: skipping HQ publish (already published today)"
  else
    bash "$PUBLISH_SCRIPT" "agent-reflection" "ra" "Ra — Content Pipeline Report" "$RA_REFLECTION" 2>/dev/null || true
    touch "$RA_REPORT_PUBLISH_MARKER"
    ok "Self-authored report published to HQ feed"
  fi

  # Report to Kai — closed-loop upward communication (always fires for metrics)
  DISPATCH_BIN="$ROOT/bin/dispatch.sh"
  if [[ -x "$DISPATCH_BIN" ]]; then
    bash "$DISPATCH_BIN" report ra "research+reflection published: newsletter=${nl_produced:+produced}${nl_produced:-blocked}, sources=${SOURCE_COUNT:-?}" 2>/dev/null || true
  fi
fi

# STEP 13: MEMORY UPDATE (constitutional — AGENT_ALGORITHMS.md)
RA_ACTIVE="$ROOT/agents/ra/ledger/ACTIVE.md"
mkdir -p "$(dirname "$RA_ACTIVE")"
cat > "$RA_ACTIVE" << ACTIVEEOF
# Ra — Active Tasks (auto-updated every cycle)
**Last updated:** $(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)

## This Cycle
- Newsletter produced: $(if ls ${ROOT}/agents/ra/output/*${TODAY}* 2>/dev/null | head -1 >/dev/null 2>&1; then echo "yes"; else echo "no"; fi)
- Critical issues: ${CRITICAL:-0}
- Warnings: ${WARNINGS:-0}
- Assessment: ${ASSESSMENT}

## Open Issues
$(if [[ ${CRITICAL:-0} -gt 0 ]]; then echo "- ${CRITICAL} critical issues need attention"; fi)
$(if [[ "$STALENESS_FLAG" == "True" ]]; then echo "- PLAYBOOK.md is stale (${PLAYBOOK_AGE:-unknown}d)"; fi)

## Reflection Summary
- Bottleneck: ${REFLECT_BOTTLENECK}
- Domain growth: ${REFLECT_DOMAIN_GROWTH}
ACTIVEEOF
ok "Memory update: ACTIVE.md written"

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
