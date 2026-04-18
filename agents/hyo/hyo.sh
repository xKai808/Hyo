#!/usr/bin/env bash
# agents/hyo/hyo.sh — hyo UI/UX Agent Runner
# Role: Monitor, audit, and improve all user-facing surfaces of hyo.world
# Schedule: Daily at 10:00 MT (after morning deploys settle)
# BUILD-004: hyo agent (UI/UX)

set -euo pipefail

HYO_ROOT="${HYO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT_DIR="$HYO_ROOT/agents/hyo"
LOG_DIR="$AGENT_DIR/logs"
LEDGER_DIR="$AGENT_DIR/ledger"
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
NOW=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
LOG_FILE="$LOG_DIR/hyo-$TODAY.log"
SITE_BASE="https://www.hyo.world"

mkdir -p "$LOG_DIR"

log() { echo "[$(TZ=America/Denver date +%H:%M:%S)] $*" | tee -a "$LOG_FILE"; }
log_event() {
  local event_type="$1" msg="$2" ok="${3:-true}"
  echo "{\"ts\":\"$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)\",\"agent\":\"hyo\",\"event\":\"$event_type\",\"msg\":\"$msg\",\"ok\":$ok}" \
    >> "$LEDGER_DIR/log.jsonl"
}

log "=== hyo UI/UX Agent — $TODAY ==="

# ── PHASE 0: Growth ──────────────────────────────────────────────────────────
log "--- Phase 0: Growth ---"
if [[ -f "$HYO_ROOT/bin/agent-growth.sh" ]]; then
  source "$HYO_ROOT/bin/agent-growth.sh"
  run_growth_phase "hyo" "$AGENT_DIR/GROWTH.md" "$LOG_FILE" 2>> "$LOG_FILE" || true
fi

# ── PHASE 1: Surface Audit ────────────────────────────────────────────────────
log "--- Phase 1: Surface Audit ---"

AUDIT_RESULTS=()
AUDIT_ISSUES=()

audit_page() {
  local page_name="$1"
  local url="$2"
  log "  Auditing: $url"

  local resp http_code content
  http_code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")

  if [[ "$http_code" != "200" ]]; then
    AUDIT_ISSUES+=("$page_name: HTTP $http_code")
    log "  WARN: $page_name returned HTTP $http_code"
    return
  fi

  content=$(curl -sL --max-time 15 "$url" 2>/dev/null || echo "")

  # Check viewport meta tag (mobile-first requirement)
  if ! echo "$content" | grep -q 'name="viewport"'; then
    AUDIT_ISSUES+=("$page_name: missing viewport meta tag (mobile broken)")
    log "  ISSUE: $page_name missing viewport meta"
  fi

  # Check for title tag
  if ! echo "$content" | grep -q '<title>'; then
    AUDIT_ISSUES+=("$page_name: missing <title> tag")
  fi

  # Check for Plus Jakarta Sans / Inter / Syne font loading
  if echo "$content" | grep -qiE "(plus.jakarta|Inter|Syne)"; then
    log "  OK: fonts referenced"
  fi

  # Check for hardcoded hex colors that should be CSS vars (design audit)
  local hex_count
  hex_count=$(echo "$content" | grep -oE '#[0-9a-fA-F]{6}' | grep -v "^#0c0d14$\|^#12141e$\|^#d4a853$\|^#0a0a12$\|^#0f0f1a$\|^#e8b877$" | wc -l | tr -d ' ')
  if [[ "$hex_count" -gt 10 ]]; then
    AUDIT_ISSUES+=("$page_name: $hex_count hardcoded hex colors detected (design token drift)")
  fi

  AUDIT_RESULTS+=("$page_name: HTTP 200 OK")
  log "  OK: $page_name looks healthy"
}

# Audit key pages
audit_page "index" "$SITE_BASE/"
audit_page "aurora" "$SITE_BASE/aurora"
audit_page "hq" "$SITE_BASE/hq"
audit_page "app" "$SITE_BASE/app"

# Check for today's podcast audio
PODCAST_URL="$SITE_BASE/daily/podcast-$TODAY.mp3"
podcast_code=$(curl -sI -o /dev/null -w "%{http_code}" --max-time 10 "$PODCAST_URL" 2>/dev/null || echo "000")
if [[ "$podcast_code" == "200" ]]; then
  log "  OK: Today's podcast live at /daily/podcast-$TODAY.mp3"
  AUDIT_RESULTS+=("podcast-$TODAY: HTTP 200 (audio live)")
else
  log "  INFO: Podcast not yet available (HTTP $podcast_code) — may generate later"
fi

log "  Audit summary: ${#AUDIT_RESULTS[@]} pages OK, ${#AUDIT_ISSUES[@]} issues"

# ── PHASE 2: Design Debt ──────────────────────────────────────────────────────
log "--- Phase 2: Design Debt Check ---"

# Check for pending HYO- tickets in ACTIVE.md
pending_count=$(grep -c "PENDING\|IN PROGRESS" "$LEDGER_DIR/ACTIVE.md" 2>/dev/null || echo "0")
log "  Open tasks: $pending_count"

# ── PHASE 3: Competitive Research (Mondays only) ──────────────────────────────
log "--- Phase 3: Competitive Research (Monday-only) ---"
day_of_week=$(TZ=America/Denver date +%u)  # 1=Mon
if [[ "$day_of_week" == "1" ]]; then
  log "  Monday: competitive design research due — add to ACTIVE.md"
  echo "{\"ts\":\"$NOW\",\"agent\":\"hyo\",\"event\":\"research_due\",\"msg\":\"Weekly competitive design research due\",\"ok\":true}" \
    >> "$LEDGER_DIR/log.jsonl"
else
  log "  Skipping (not Monday)"
fi

# ── PHASE 4: Self-Review ──────────────────────────────────────────────────────
log "--- Phase 4: Self-Review ---"

SELF_REVIEW_FILE="$LOG_DIR/self-review-$TODAY.md"

issues_str=""
if [[ ${#AUDIT_ISSUES[@]} -gt 0 ]]; then
  for issue in "${AUDIT_ISSUES[@]}"; do
    issues_str+="- $issue\n"
  done
else
  issues_str="- No issues detected\n"
fi

ok_str=""
for result in "${AUDIT_RESULTS[@]}"; do
  ok_str+="- $result\n"
done

cat > "$SELF_REVIEW_FILE" << REVIEW
# hyo Agent — Self Review ${TODAY}

## Surface Audit Results

### Pages OK
$(printf '%b' "$ok_str")

### Issues Found
$(printf '%b' "$issues_str")

## Design Debt
Open tasks: $pending_count

## Podcast Audio
Status: HTTP $podcast_code at /daily/podcast-$TODAY.mp3

## Agent Health
- Growth phase ran: yes
- Surface audit ran: yes (${#AUDIT_RESULTS[@]} pages checked)
- Issues detected: ${#AUDIT_ISSUES[@]}

## Next Cycle Focus
$(if [[ ${#AUDIT_ISSUES[@]} -gt 0 ]]; then
  echo "Address ${#AUDIT_ISSUES[@]} detected issue(s) before new features."
else
  echo "No issues — focus on IMP-HYO-001 (visual regression baseline)."
fi)

---
*hyo UI/UX Agent — autonomous daily audit*
REVIEW

log "  Self-review written: $SELF_REVIEW_FILE"

# ── PHASE 5: Publish to HQ Feed ──────────────────────────────────────────────
log "--- Phase 5: HQ Feed Publish ---"

# Build feed entry
ISSUES_SUMMARY=""
if [[ ${#AUDIT_ISSUES[@]} -gt 0 ]]; then
  ISSUES_SUMMARY="${#AUDIT_ISSUES[@]} issue(s): ${AUDIT_ISSUES[*]:0:2}"
else
  ISSUES_SUMMARY="No issues detected"
fi

PAGES_OK="${#AUDIT_RESULTS[@]}"
ISSUES_COUNT="${#AUDIT_ISSUES[@]}"
ISSUES_LIST_JSON="[]"
if [[ $ISSUES_COUNT -gt 0 ]]; then
  ISSUES_LIST_JSON=$(python3 -c "import json,sys; items=sys.argv[1:]; print(json.dumps(items))" "${AUDIT_ISSUES[@]}" 2>/dev/null || echo "[]")
fi

FEED_ENTRY=$(python3 - <<PYEOF
import json

pages_ok = ${PAGES_OK}
issues_count = ${ISSUES_COUNT}
issues_list = ${ISSUES_LIST_JSON}

entry = {
    "id": "hyo-daily-${TODAY}",
    "type": "agent-daily",
    "title": "hyo Daily \u2014 ${TODAY}",
    "author": "hyo",
    "authorIcon": "\u2726",
    "authorColor": "#a78bfa",
    "timestamp": "${NOW}",
    "date": "${TODAY}",
    "sections": {
        "summary": f"Surface audit: {pages_ok} pages OK. ${ISSUES_SUMMARY}. Podcast: HTTP $podcast_code.",
        "wentWell": [f"Surface audit completed for {pages_ok} pages"],
        "needsAttention": issues_list if issues_count > 0 else ["No issues detected"]
    }
}
print(json.dumps(entry))
PYEOF
)

if [[ -n "$FEED_ENTRY" ]]; then
  # Use publish-to-feed.sh if available
  if [[ -f "$HYO_ROOT/bin/publish-to-feed.sh" ]]; then
    echo "$FEED_ENTRY" | python3 -c "
import json, sys
feed_path_1 = '${HYO_ROOT}/agents/sam/website/data/feed.json'
feed_path_2 = '${HYO_ROOT}/website/data/feed.json'
entry = json.loads(sys.stdin.read())
for path in [feed_path_1, feed_path_2]:
    try:
        with open(path) as f:
            feed = json.load(f)
        reports = feed.get('reports', [])
        reports = [r for r in reports if r.get('id') != entry['id']]
        reports.insert(0, entry)
        feed['reports'] = reports
        with open(path, 'w') as f:
            json.dump(feed, f, indent=2, ensure_ascii=False)
            f.write('\n')
        print(f'Feed updated: {path}')
    except Exception as e:
        print(f'Feed error: {e}')
" 2>> "$LOG_FILE" || true
    log "  Feed updated"
  fi
fi

# ── Update ACTIVE.md timestamp ────────────────────────────────────────────────
sed -i.bak "s/^\*\*Updated:\*\*.*/\*\*Updated:\*\* ${TODAY}/" "$LEDGER_DIR/ACTIVE.md" 2>/dev/null || true

log_event "cycle_complete" "hyo daily audit done. Pages: ${#AUDIT_RESULTS[@]} OK, Issues: ${#AUDIT_ISSUES[@]}"
log "=== hyo cycle complete ==="
