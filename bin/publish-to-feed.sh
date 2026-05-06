#!/usr/bin/env bash
# bin/publish-to-feed.sh — Publish a report entry to the HQ feed
#
# Used by agent runners and Kai to post reports to the feed.
# Each call appends one report entry to website/data/feed.json.
#
# Usage:
#   bash bin/publish-to-feed.sh <type> <author> <title> <json-sections-file>
#
# Types: morning-report, ceo-report, agent-reflection, research-drop
# Sections file: a JSON file with the report sections (varies by type)
#
# Example:
#   bash bin/publish-to-feed.sh agent-reflection nel "Nel — Overnight Reflection" /tmp/nel-sections.json
#
# The sections JSON format depends on report type:
#   agent-reflection: {"introspection":"...","research":"...","changes":"...","followUps":["..."],"forKai":"..."}
#   ceo-report:       {"direction":"...","priorities":["..."],"agentGrowth":"...","risks":"..."}
#   research-drop:    {"topic":"...","finding":"...","implications":"...","nextSteps":["..."]}

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
FEED="$ROOT/website/data/feed.json"
FEED_GIT="$ROOT/agents/sam/website/data/feed.json"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)
MONTH_KEY=$(echo "$TODAY" | cut -c1-7)

TYPE="${1:?Usage: publish-to-feed.sh <type> <author> <title> <sections-json-file>}"
AUTHOR="${2:?Missing author}"
TITLE="${3:?Missing title}"
SECTIONS_FILE="${4:?Missing sections JSON file}"

if [[ ! -f "$SECTIONS_FILE" ]]; then
  echo "ERROR: sections file not found: $SECTIONS_FILE" >&2
  exit 1
fi

# ── SCHEMA REGISTRY GATE ─────────────────────────────────────────────────────
# Every report type must have a protocol AND a schema. New types without both are blocked.
# Gate question: "Does kai/schemas/{type}.schema.json exist?" NO → block (create protocol first).
SCHEMA_FILE="$ROOT/kai/schemas/$(echo "$TYPE" | tr '-' '_').schema.json"
if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "ERROR: SCHEMA GATE BLOCKED — type '$TYPE' has no schema file at $SCHEMA_FILE" >&2
  echo "  Create kai/protocols/PROTOCOL_$(echo "$TYPE" | tr '[:lower:]-' '[:upper:]_').md first, then add schema." >&2
  HYO_ROOT="$ROOT" bash "$ROOT/bin/ticket.sh" create \
    --agent "kai" \
    --title "Missing schema: $TYPE has no schema file — create protocol and schema before publishing" \
    --priority "P1" 2>/dev/null || true
  exit 1
fi

# Validate mandatory fields from schema
if [[ -f "$SECTIONS_FILE" ]] && [[ -f "$SCHEMA_FILE" ]]; then
  SCHEMA_CHECK=$(python3 -c "
import json, sys
with open('$SECTIONS_FILE') as f:
    sections = json.load(f)
with open('$SCHEMA_FILE') as f:
    schema = json.load(f)
mandatory = schema.get('mandatory', [])
missing = [m for m in mandatory if not sections.get(m)]
if missing:
    print('MISSING:' + ','.join(missing))
else:
    print('OK')
" 2>/dev/null || echo "OK")
  if [[ "$SCHEMA_CHECK" == MISSING:* ]]; then
    MISSING_FIELDS="${SCHEMA_CHECK#MISSING:}"
    echo "WARN: Schema validation: mandatory fields missing from $TYPE: $MISSING_FIELDS" >&2
    echo "  Protocol: $(python3 -c \"import json; print(json.load(open('$SCHEMA_FILE')).get('_protocol','unknown'))\" 2>/dev/null)" >&2
    # Warn only (not block) — allows partial publishes while teams migrate to full schema compliance
  fi
fi

# ── RESEARCH-DROP HARD GATES (v1.2 — added 2026-05-05 after session 34 failures) ──
# These gates run BEFORE any write. They cannot be bypassed by forgetting to read a protocol.
# Root cause: Kai published research-drop entries that were (a) invisible in Research tab
# because they went into entries[] not reports[], (b) linked to .md files that Vercel 404s.
# The fix is CODE, not prose — these gates block the publish if conditions aren't met.
if [[ "$TYPE" == "research-drop" ]]; then

  # GATE R1: readLink must NOT end in .md — Vercel only serves .html files
  READ_LINK=$(python3 -c "
import json, sys
try:
    s = json.load(open('$SECTIONS_FILE'))
    print(s.get('readLink', ''))
except: print('')
" 2>/dev/null || echo "")
  if [[ "$READ_LINK" == *.md ]]; then
    echo "ERROR: RESEARCH-DROP GATE R1 BLOCKED — readLink ends in .md: '$READ_LINK'" >&2
    echo "  Vercel cannot serve .md files. Use /docs/research/<slug> (no extension)." >&2
    echo "  Create agents/sam/website/docs/research/<slug>.html first." >&2
    exit 1
  fi

  # GATE R2: The HTML file for readLink must exist before publishing the feed entry
  if [[ -n "$READ_LINK" ]]; then
    # readLink format: /docs/research/<slug> → file: agents/sam/website/docs/research/<slug>.html
    SLUG=$(basename "$READ_LINK")
    HTML_PATH="$ROOT/agents/sam/website/docs/research/${SLUG}.html"
    if [[ ! -f "$HTML_PATH" ]]; then
      echo "ERROR: RESEARCH-DROP GATE R2 BLOCKED — HTML file does not exist: $HTML_PATH" >&2
      echo "  Create the HTML document BEFORE writing the feed entry." >&2
      echo "  readLink: $READ_LINK → expected file: $HTML_PATH" >&2
      exit 1
    fi
    echo "[publish] GATE R2 PASSED: HTML file exists at $HTML_PATH"
  fi

  # GATE R3: Write a VERIFY_PENDING flag — healthcheck sees this as unresolved
  # until visual verification is confirmed (GATE 12 in protocol).
  # This ensures "published" cannot mean "not visually verified."
  VERIFY_FLAG="$ROOT/kai/ledger/verify-pending.jsonl"
  VERIFY_ID="research-drop-$(TZ=America/Denver date +%Y%m%d%H%M%S)"
  echo "{\"id\":\"$VERIFY_ID\",\"type\":\"research-drop\",\"title\":\"$TITLE\",\"readLink\":\"$READ_LINK\",\"ts\":\"$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)\",\"status\":\"PENDING_VISUAL_VERIFY\"}" >> "$VERIFY_FLAG"
  echo "[publish] GATE R3: Visual verification pending. ID: $VERIFY_ID"
  echo "  → After publish, open hyo.world/hq Research tab, click the entry, click readLink."
  echo "  → Confirm HTTP 200, then run: kai verify-publish $VERIFY_ID"

fi

# ─── THEATER DETECTION GATE ──────────────────────────────────────────────────
# Research-drop publishes must include sources. Blocks theater ("did research"
# without citations). Gate 3 from PROTOCOL_HQ_PUBLISH.md.
if [[ "$TYPE" == "research-drop" ]]; then
  SOURCES_CHECK=$(python3 -c "
import json, sys
with open('$SECTIONS_FILE') as f:
    s = json.load(f)
finding = str(s.get('finding',''))
sources = str(s.get('sources',''))
# Theater = no URL-like string in finding or sources
import re
has_source = bool(re.search(r'https?://', finding + sources))
print('ok' if has_source else 'blocked')
")
  if [[ "$SOURCES_CHECK" == "blocked" ]]; then
    echo "ERROR: THEATER GATE BLOCKED — research-drop has no sources (no URLs in finding/sources). Add citations before publishing." >&2
    HYO_ROOT="$ROOT" bash "$ROOT/bin/ticket.sh" create \
      --agent "kai" \
      --title "Theater gate: research-drop missing sources ($TITLE)" \
      --priority "P1" 2>/dev/null || true
    exit 1
  fi
fi

# ── PRE-PUBLISH DEDUP GATE ────────────────────────────────────────────────────
# Blocks publish if content has >60% Jaccard overlap with a recent entry.
# Prevents research redundancy across agents and repeat-publishing same content.
# Override: PRE_PUBLISH_OVERRIDE=1 bash publish-to-feed.sh ...
# Gate question: "Did dedup check pass?" NO → exit 1 (unless override set)
if [[ -f "$ROOT/bin/pre-publish-check.py" ]] && [[ "${SKIP_DEDUP:-0}" != "1" ]]; then
    SECTIONS_PREVIEW=""
    if [[ -f "$SECTIONS_FILE" ]]; then
        SECTIONS_PREVIEW=$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(' '.join(str(v) for v in d.values() if isinstance(v, str))[:500])
except: pass
" "$SECTIONS_FILE" 2>/dev/null || true)
    fi
    DEDUP_RESULT=$(HYO_ROOT="$ROOT" python3 "$ROOT/bin/pre-publish-check.py" \
        --agent "$AUTHOR" \
        --type "$TYPE" \
        --title "$TITLE" \
        --content "$SECTIONS_PREVIEW" 2>&1)
    DEDUP_EXIT=$?
    echo "[publish-to-feed] Dedup check: $DEDUP_RESULT"
    if [[ $DEDUP_EXIT -eq 1 ]]; then
        echo "ERROR: DEDUP GATE BLOCKED — duplicate content detected. Set PRE_PUBLISH_OVERRIDE=1 to force." >&2
        exit 1
    fi
fi

# Agent metadata lookup (bash 3.x compatible — no associative arrays)
AUTHOR_LC=$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')

case "$AUTHOR_LC" in
  kai)    ICON="👔"; COLOR="#d4a853" ;;
  nel)    ICON="🔧"; COLOR="#6dd49c" ;;
  sam)    ICON="⚙️"; COLOR="#7ec4e0" ;;
  ra)     ICON="📰"; COLOR="#b49af0" ;;
  aurora) ICON="🌅"; COLOR="#f0a060" ;;
  aether) ICON="📈"; COLOR="#e8c96a" ;;
  dex)    ICON="🗃️"; COLOR="#e07060" ;;
  *)      ICON="📋"; COLOR="#888888" ;;
esac

AUTHOR_NAME=$(echo "$AUTHOR_LC" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')

# Generate unique ID
REPORT_ID="${TYPE}-${AUTHOR_LC}-${TODAY}-$(date +%H%M%S)"

python3 - "$FEED" "$REPORT_ID" "$TYPE" "$AUTHOR_NAME" "$ICON" "$COLOR" \
          "$NOW_MT" "$TODAY" "$MONTH_KEY" "$TITLE" "$SECTIONS_FILE" "$ROOT" <<'PYEOF'
import json, sys, os, subprocess

feed_path    = sys.argv[1]
report_id    = sys.argv[2]
report_type  = sys.argv[3]
author       = sys.argv[4]
icon         = sys.argv[5]
color        = sys.argv[6]
timestamp    = sys.argv[7]
date         = sys.argv[8]
month_key    = sys.argv[9]
title        = sys.argv[10]
sections_file= sys.argv[11]
hyo_root     = sys.argv[12] if len(sys.argv) > 12 else os.path.expanduser("~/Documents/Projects/Hyo")

# ── SCHEMA VALIDATION GATE ──────────────────────────────────────────────────
# Each report type has REQUIRED section keys that the HQ renderer expects.
# If keys don't match → block publish, auto-create ticket.
# This gate exists because session 11 published a morning-report with
# ceo-report keys (direction/priorities/agentGrowth/risks) instead of
# the renderer's expected keys (summary/wentWell/needsAttention/agentHighlights).
# Result: HQ showed empty content. Hyo caught it. Never again.
REQUIRED_KEYS = {
    "morning-report":    {"summary"},
    "aether-analysis":   {"summary", "balance", "trades", "risk"},
    "ceo-report":        {"direction"},
    "agent-reflection":  {"introspection"},
    "newsletter":        set(),  # flexible
    "research-drop":     {"topic", "finding"},
    "self-improve-report": {"weakness", "outcome"},   # from agent-self-improve.sh
}
RECOMMENDED_KEYS = {
    "morning-report":    {"summary", "wentWell", "needsAttention", "agentHighlights"},
    "aether-analysis":   {"summary", "balance", "trades", "risk", "btc"},
}

# Read sections
with open(sections_file) as f:
    sections = json.load(f)

# Validate
required = REQUIRED_KEYS.get(report_type, set())
section_keys = set(sections.keys())
missing = required - section_keys
if missing:
    err_msg = f"SCHEMA GATE BLOCKED: {report_type} missing required keys: {missing}. Got: {section_keys}"
    print(f"ERROR: {err_msg}", file=sys.stderr)
    # Auto-create ticket
    ticket_sh = os.path.join(hyo_root, "bin", "ticket.sh")
    if os.path.exists(ticket_sh):
        ticket_title = f"Schema validation failed: {report_type} missing {missing}"
        subprocess.run(["bash", ticket_sh, "create", "--agent", "kai",
                        "--title", ticket_title, "--priority", "P0"], capture_output=True)
        print(f"Auto-created P0 ticket for schema failure", file=sys.stderr)
    sys.exit(1)

# Warn on recommended but don't block
recommended = RECOMMENDED_KEYS.get(report_type, set())
rec_missing = recommended - section_keys
if rec_missing:
    print(f"WARNING: {report_type} missing recommended keys: {rec_missing}. Feed card may render incomplete.", file=sys.stderr)

# Build entry
entry = {
    "id": report_id,
    "type": report_type,
    "title": title,
    "author": author,
    "authorIcon": icon,
    "authorColor": color,
    "timestamp": timestamp,
    "date": date,
    "sections": sections
}

# Read existing feed
feed = {"lastUpdated": timestamp, "today": date, "agents": {}, "reports": [], "history": {}}
if os.path.exists(feed_path):
    try:
        with open(feed_path) as f:
            feed = json.load(f)
    except:
        pass

# Update — SE-011-010: dedup by report ID before appending
feed["lastUpdated"] = timestamp
feed["today"] = date
existing_ids = {r.get("id") for r in feed.get("reports", [])}
if report_id in existing_ids:
    # Replace existing entry with updated version
    feed["reports"] = [r for r in feed["reports"] if r.get("id") != report_id]
feed["reports"].append(entry)
feed["reports"].sort(key=lambda r: r.get("timestamp", ""), reverse=True)

# History
if month_key not in feed.get("history", {}):
    months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    m_idx = int(month_key.split("-")[1]) - 1
    label = f"{months[m_idx]} {month_key.split('-')[0]}"
    feed["history"][month_key] = {"label": label, "reports": []}

if report_id not in feed["history"][month_key]["reports"]:
    feed["history"][month_key]["reports"].append(report_id)

with open(feed_path, "w") as f:
    json.dump(feed, f, indent=2)

print(f"Published to feed: [{report_type}] {title} by {author}")
PYEOF

# Dual-write: keep git-tracked copy in sync
if [[ -f "$FEED" && -f "$FEED_GIT" && "$FEED" != "$FEED_GIT" ]]; then
  cp "$FEED" "$FEED_GIT"
fi

# ─── ARCHIVE STEP (PROTOCOL_HQ_PUBLISH.md Section 7) ─────────────────────────
# Every publish saves to agents/[agent]/archive/YYYY/MM/[agent]-[type]-DATE.json
# This creates an immutable, browsable record of everything ever published.
AUTHOR_LC_ARCHIVE=$(echo "$AUTHOR" | tr '[:upper:]' '[:lower:]')
YEAR=$(TZ="America/Denver" date +%Y)
MONTH=$(TZ="America/Denver" date +%m)
ARCHIVE_DIR="$ROOT/agents/$AUTHOR_LC_ARCHIVE/archive/$YEAR/$MONTH"
mkdir -p "$ARCHIVE_DIR"
ARCHIVE_FILE="$ARCHIVE_DIR/${AUTHOR_LC_ARCHIVE}-${TYPE}-${TODAY}.json"

python3 - "$SECTIONS_FILE" "$ARCHIVE_FILE" "$REPORT_ID" "$TYPE" "$AUTHOR" "$NOW_MT" "$TITLE" << 'ARCHEOF'
import json, sys
sections_file, archive_file, report_id, rtype, author, ts, title = sys.argv[1:8]
with open(sections_file) as f:
    sections = json.load(f)
archive_entry = {
    "id": report_id,
    "type": rtype,
    "title": title,
    "author": author,
    "published_at": ts,
    "sections": sections
}
# Append mode: keep all daily versions if run multiple times
existing = []
try:
    with open(archive_file) as f:
        existing = json.load(f)
        if not isinstance(existing, list):
            existing = [existing]
except:
    pass
# Dedup by id
ids = {e.get("id") for e in existing}
if report_id not in ids:
    existing.append(archive_entry)
with open(archive_file, "w") as f:
    json.dump(existing, f, indent=2)
print(f"Archived to {archive_file}")
ARCHEOF

echo "Feed entry published: $REPORT_ID"

# ── COMMIT + PUSH: every publish must reach Vercel, not just local disk ──
# Without this, HQ never updates. Reports go to /dev/null.
cd "$ROOT" && git add \
  "website/data/feed.json" \
  "agents/sam/website/data/feed.json" \
  "agents/${AUTHOR_LC_ARCHIVE}/archive/" \
  2>/dev/null || true

git diff --cached --quiet 2>/dev/null || \
  git commit -m "publish: ${TYPE} by ${AUTHOR} — ${TITLE:0:60}" \
    --author="Kai (CEO, hyo.world) <kai@hyo.world>" \
    2>/dev/null || true

git push origin main 2>/dev/null && echo "Feed pushed to remote" || \
  echo "WARN: push failed — queuing retry" && \
  echo "{\"id\":\"feed-push-retry-$(date +%s)\",\"command\":\"cd ~/Documents/Projects/Hyo && git push origin main\",\"ts\":\"$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)\",\"timeout\":60,\"agent\":\"kai\"}" \
  > "$ROOT/kai/queue/pending/feed-push-retry-$(date +%s).json"
