#!/usr/bin/env bash
# bin/kai-report.sh — ERROR-TO-GATE subcommand: ship a human-readable Kai report to HQ.
#
# Why this exists (SE-011-001):
#   Kai has repeatedly shipped protocol/architecture work (ARIC, queue, etc.)
#   by committing code and docs into the repo, but never surfacing a
#   human-readable brief on HQ. The user's view = HQ. No HQ entry = invisible.
#   This script is the gate: no protocol or architecture session closes
#   without calling `kai report`.
#
# Usage:
#   bash bin/kai-report.sh <report-file> <title> [--sections key=val,key=val,...]
#
# Or (smart mode — recommended):
#   bash bin/kai-report.sh <report-file> <title>
#     → reads the .md file, splits on H2 headings ("## Section Title"),
#       auto-builds sections JSON, publishes as ceo-report by Kai.
#
# Examples:
#   kai report agents/kai/reports/kai-aric-rollout-2026-04-15.md \
#              "Kai — ARIC rollout & research-access brief"
#
# Gate semantics:
#   - Logs call to kai/ledger/reports.jsonl with timestamp, file, title, feed-id.
#   - Fails if the report file doesn't exist.
#   - Fails if publish-to-feed.sh fails.
#   - On success, prints the feed entry ID.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
REPORTS_LEDGER="$ROOT/kai/ledger/reports.jsonl"
mkdir -p "$(dirname "$REPORTS_LEDGER")"

usage() {
  echo "Usage: kai report <report-file.md> <title>" >&2
  echo "       kai report --audit       (show recent report ledger)" >&2
  exit 1
}

# Audit mode — show what's been reported
if [[ "${1:-}" == "--audit" ]]; then
  if [[ -f "$REPORTS_LEDGER" ]]; then
    echo "Recent Kai reports (last 10):"
    tail -10 "$REPORTS_LEDGER" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        d = json.loads(line)
        print(f\"  {d.get('timestamp','?')}  [{d.get('feed_id','?')}]  {d.get('title','')}\")
    except Exception:
        continue
"
  else
    echo "No reports logged yet."
  fi
  exit 0
fi

REPORT_FILE="${1:-}"
TITLE="${2:-}"

[[ -z "$REPORT_FILE" ]] && usage
[[ -z "$TITLE" ]] && usage

if [[ ! -f "$REPORT_FILE" ]]; then
  echo "ERROR: report file not found: $REPORT_FILE" >&2
  exit 1
fi

# Build sections JSON by splitting on H2 headings
SECTIONS_FILE=$(mktemp)
trap 'rm -f "$SECTIONS_FILE"' EXIT

python3 - "$REPORT_FILE" "$SECTIONS_FILE" <<'PYEOF'
import json, re, sys

src, dst = sys.argv[1:3]
with open(src, "r", errors="replace") as f:
    text = f.read()

sections = {}

# Use first H1 or intro paragraph as "summary"
intro_m = re.search(r"^#\s+.*?\n+(.+?)(?=\n##\s|\Z)", text, re.DOTALL | re.MULTILINE)
if intro_m:
    intro = intro_m.group(1).strip()
    # Skip meta/date lines and take the first substantive paragraph
    paras = [p.strip() for p in re.split(r"\n\s*\n", intro) if p.strip()]
    # Pick first paragraph not starting with **Date:** or similar metadata
    summary = ""
    for p in paras:
        if not re.match(r"^\*\*(Date|Author|Type|For|Origin):", p) and len(p) > 40:
            summary = p[:1200]
            break
    if summary:
        sections["summary"] = summary

# Split on H2 headings
h2_pattern = re.compile(r"^##\s+(.+?)$", re.MULTILINE)
h2s = list(h2_pattern.finditer(text))
for i, m in enumerate(h2s):
    heading = m.group(1).strip()
    start = m.end()
    end = h2s[i+1].start() if i+1 < len(h2s) else len(text)
    body = text[start:end].strip()
    # Short key for JSON
    key = re.sub(r"[^a-z0-9]+", "-", heading.lower()).strip("-")
    key = key[:40] or f"section-{i}"
    # Cap length per section
    sections[key] = body[:4000]

# Always include a readLink back to the raw markdown (Kai agent sub-page not wired yet)
sections["readLink"] = ""

with open(dst, "w") as f:
    json.dump(sections, f, ensure_ascii=False, indent=2)

print(f"[kai-report] built {len(sections)} sections from {src}")
PYEOF

if [[ $? -ne 0 ]]; then
  echo "ERROR: failed to build sections JSON" >&2
  exit 1
fi

# Publish
echo "[kai-report] publishing to HQ feed..."
bash "$ROOT/bin/publish-to-feed.sh" ceo-report kai "$TITLE" "$SECTIONS_FILE"
PUB_RC=$?

if [[ $PUB_RC -ne 0 ]]; then
  echo "ERROR: publish failed (rc=$PUB_RC)" >&2
  exit $PUB_RC
fi

# Derive the feed id (publish-to-feed.sh prints it to stdout)
# Fallback: scan the feed for the newest ceo-report-kai entry
FEED_ID=$(python3 -c "
import json
try:
    with open('$ROOT/website/data/feed.json') as f:
        d = json.load(f)
    for r in d.get('reports', []):
        if r.get('author','').lower()=='kai' and r.get('type')=='ceo-report':
            print(r.get('id',''))
            break
except Exception:
    pass
")

# Log to ledger
NOW=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
python3 -c "
import json, sys
entry = {
    'timestamp': '$NOW',
    'file': '$REPORT_FILE',
    'title': '''$TITLE''',
    'feed_id': '$FEED_ID'
}
with open('$REPORTS_LEDGER', 'a') as f:
    f.write(json.dumps(entry) + '\n')
"

echo "[kai-report] OK — feed_id=$FEED_ID, logged to $REPORTS_LEDGER"
