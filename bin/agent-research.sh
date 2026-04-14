#!/usr/bin/env bash
# bin/agent-research.sh — Agent research framework
#
# Each agent calls this to conduct domain-specific external research,
# save findings, update their PLAYBOOK, and publish to the feed.
#
# This is NOT a delegation to Ra. Each agent researches their own domain.
# Ra researches content/newsletters. Nel researches security. Sam researches infra.
#
# Usage: bash bin/agent-research.sh <agent> [--publish]
#        --publish: also publish findings to the HQ feed via publish-to-feed.sh
#
# Requirements: curl, python3, network access (runs on Mini via launchd, NOT Cowork sandbox)
#
# What this script does:
#   1. Reads the agent's research-sources.json for URLs to check
#   2. Fetches each URL, extracts relevant content
#   3. Saves raw findings to agents/<name>/research/raw/
#   4. Synthesizes findings into a research note
#   5. Updates the agent's PLAYBOOK.md "Research Log" section
#   6. Checks previous follow-ups for accountability
#   7. Writes new follow-ups
#   8. Optionally publishes to the HQ feed
#
# Each agent's research-sources.json format:
# {
#   "sources": [
#     {"name": "...", "url": "...", "type": "rss|api|html", "focus": "what to look for"}
#   ],
#   "followUps": [
#     {"date": "2026-04-13", "item": "...", "status": "open|done|dropped", "outcome": "..."}
#   ]
# }

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
AGENT="${1:?Usage: agent-research.sh <agent> [--publish]}"
PUBLISH="${2:-}"
TODAY=$(TZ="America/Denver" date +%Y-%m-%d)
NOW_MT=$(TZ="America/Denver" date +%Y-%m-%dT%H:%M:%S%z)

AGENT_HOME="$ROOT/agents/$AGENT"
RESEARCH_DIR="$AGENT_HOME/research"
RAW_DIR="$RESEARCH_DIR/raw"
SOURCES_FILE="$AGENT_HOME/research-sources.json"
PLAYBOOK="$AGENT_HOME/PLAYBOOK.md"
FINDINGS_FILE="$RESEARCH_DIR/findings-${TODAY}.md"
FEED_SECTIONS="/tmp/agent-research-${AGENT}-${TODAY}.json"

log() { echo "[${AGENT}-research] $(TZ='America/Denver' date +%H:%M:%S) $*"; }

mkdir -p "$RAW_DIR"

if [[ ! -f "$SOURCES_FILE" ]]; then
  log "ERROR: No research-sources.json found for $AGENT"
  log "Create $SOURCES_FILE with sources and focus areas"
  exit 1
fi

log "Starting research cycle for $AGENT"

# ── 1. Fetch external sources ──
FETCH_COUNT=0
FETCH_SUCCESS=0
FETCH_RESULTS=""

python3 - "$SOURCES_FILE" "$RAW_DIR" "$TODAY" "$AGENT" << 'PYEOF'
import json, sys, os, subprocess, hashlib
from datetime import datetime

sources_file = sys.argv[1]
raw_dir = sys.argv[2]
today = sys.argv[3]
agent = sys.argv[4]

with open(sources_file) as f:
    config = json.load(f)

sources = config.get("sources", [])
results = []

for src in sources:
    name = src.get("name", "unknown")
    url = src.get("url", "")
    src_type = src.get("type", "html")
    focus = src.get("focus", "")

    if not url:
        continue

    print(f"FETCHING: {name} ({url[:60]}...)")

    # Fetch with timeout
    try:
        r = subprocess.run(
            ["curl", "-sL", "--max-time", "15", "-A",
             "Mozilla/5.0 (compatible; HyoResearchBot/1.0)", url],
            capture_output=True, text=True, timeout=20
        )
        content = r.stdout[:50000]  # cap at 50KB

        if not content or len(content) < 100:
            print(f"  SKIP: empty or too small ({len(content)} bytes)")
            results.append({"name": name, "status": "empty", "focus": focus})
            continue

        # Save raw
        slug = hashlib.md5(url.encode()).hexdigest()[:8]
        raw_file = os.path.join(raw_dir, f"{today}-{agent}-{slug}.txt")
        with open(raw_file, "w") as f:
            f.write(f"# Source: {name}\n# URL: {url}\n# Fetched: {today}\n# Focus: {focus}\n\n")
            f.write(content[:20000])

        # Extract relevant snippets based on type
        if src_type == "rss":
            # Extract titles and descriptions from RSS/Atom
            import re
            titles = re.findall(r'<title[^>]*>(.*?)</title>', content, re.DOTALL)
            descriptions = re.findall(r'<description[^>]*>(.*?)</description>', content, re.DOTALL)
            items = []
            for i, t in enumerate(titles[:10]):
                t = re.sub(r'<[^>]+>', '', t).strip()
                d = ""
                if i < len(descriptions):
                    d = re.sub(r'<[^>]+>', '', descriptions[i]).strip()[:200]
                if t:
                    items.append(f"- {t}" + (f": {d}" if d else ""))
            snippet = "\n".join(items[:8])
        elif src_type == "api":
            # JSON API — extract top-level keys or first few items
            try:
                data = json.loads(content)
                if isinstance(data, list):
                    snippet = json.dumps(data[:5], indent=2)[:2000]
                elif isinstance(data, dict):
                    snippet = json.dumps({k: str(v)[:200] for k, v in list(data.items())[:10]}, indent=2)[:2000]
                else:
                    snippet = str(data)[:2000]
            except:
                snippet = content[:2000]
        else:
            # HTML — strip tags, get text
            import re
            text = re.sub(r'<script[^>]*>.*?</script>', '', content, flags=re.DOTALL)
            text = re.sub(r'<style[^>]*>.*?</style>', '', text, flags=re.DOTALL)
            text = re.sub(r'<[^>]+>', ' ', text)
            text = re.sub(r'\s+', ' ', text).strip()
            snippet = text[:3000]

        results.append({
            "name": name,
            "status": "ok",
            "focus": focus,
            "snippet": snippet[:2000],
            "raw_file": raw_file
        })
        print(f"  OK: {len(content)} bytes, saved to {raw_file}")

    except Exception as e:
        print(f"  ERROR: {e}")
        results.append({"name": name, "status": "error", "focus": focus, "error": str(e)[:100]})

# Write results for the shell to pick up
results_file = os.path.join(raw_dir, f"{today}-{agent}-results.json")
with open(results_file, "w") as f:
    json.dump(results, f, indent=2)
print(f"RESULTS: {results_file}")
print(f"FETCHED: {sum(1 for r in results if r['status'] == 'ok')}/{len(results)}")
PYEOF

RESULTS_FILE="$RAW_DIR/${TODAY}-${AGENT}-results.json"
if [[ ! -f "$RESULTS_FILE" ]]; then
  log "ERROR: Research fetch produced no results"
  exit 1
fi

FETCH_SUCCESS=$(python3 -c "import json; d=json.load(open('$RESULTS_FILE')); print(sum(1 for r in d if r['status']=='ok'))")
FETCH_COUNT=$(python3 -c "import json; d=json.load(open('$RESULTS_FILE')); print(len(d))")
log "Fetched $FETCH_SUCCESS/$FETCH_COUNT sources successfully"

# ── 2. Synthesize findings ──
python3 - "$RESULTS_FILE" "$FINDINGS_FILE" "$AGENT" "$TODAY" "$SOURCES_FILE" << 'PYEOF'
import json, sys, os

results_file = sys.argv[1]
findings_file = sys.argv[2]
agent = sys.argv[3]
today = sys.argv[4]
sources_file = sys.argv[5]

with open(results_file) as f:
    results = json.load(f)

with open(sources_file) as f:
    config = json.load(f)

# Check previous follow-ups for accountability
follow_ups = config.get("followUps", [])
open_followups = [f for f in follow_ups if f.get("status") == "open"]

# Build findings document
lines = []
lines.append(f"# {agent.capitalize()} Research Findings — {today}")
lines.append(f"")
lines.append(f"**Sources checked:** {len(results)}")
lines.append(f"**Successful:** {sum(1 for r in results if r['status'] == 'ok')}")
lines.append(f"")

# Accountability: check on previous follow-ups
if open_followups:
    lines.append(f"## Follow-up Accountability")
    lines.append(f"")
    for fu in open_followups:
        lines.append(f"- **{fu['date']}:** {fu['item']} — STATUS: {fu['status']}")
    lines.append(f"")
    lines.append(f"*These were open from previous research. Addressed this cycle? Update research-sources.json.*")
    lines.append(f"")

# Source findings
lines.append(f"## Source Findings")
lines.append(f"")

takeaways = []
new_followups = []

for r in results:
    if r["status"] != "ok":
        lines.append(f"### {r['name']} — FAILED ({r.get('error', r['status'])})")
        lines.append(f"")
        continue

    lines.append(f"### {r['name']}")
    lines.append(f"**Focus:** {r.get('focus', 'general')}")
    lines.append(f"")

    snippet = r.get("snippet", "")
    if snippet:
        # Summarize: first 500 chars as preview
        preview = snippet[:500].replace('\n', ' ').strip()
        lines.append(f"**Preview:** {preview}...")
        lines.append(f"")

        # Generate a takeaway from the focus + content
        focus = r.get("focus", "").lower()
        if any(w in snippet.lower() for w in ["new", "release", "update", "launch", "announce"]):
            takeaways.append(f"New development found in {r['name']} — review for integration potential")
        if any(w in snippet.lower() for w in ["vulnerability", "cve", "security", "breach", "exploit"]):
            takeaways.append(f"Security finding from {r['name']} — evaluate applicability to our system")
        if any(w in snippet.lower() for w in ["best practice", "pattern", "architecture", "framework"]):
            takeaways.append(f"Pattern/practice found in {r['name']} — compare against current approach")

    lines.append(f"")

# Takeaways
lines.append(f"## Key Takeaways")
lines.append(f"")
if takeaways:
    for t in takeaways:
        lines.append(f"- {t}")
else:
    lines.append(f"- No high-signal findings this cycle. Sources may need diversification.")
lines.append(f"")

# New follow-ups
lines.append(f"## New Follow-ups")
lines.append(f"")
lines.append(f"*Add items here that need action next cycle. Update research-sources.json followUps.*")
lines.append(f"")

with open(findings_file, "w") as f:
    f.write("\n".join(lines))

print(f"Findings written: {findings_file} ({len(lines)} lines)")
print(f"Takeaways: {len(takeaways)}")
PYEOF

log "Findings synthesized to $FINDINGS_FILE"

# ── 3. Update PLAYBOOK research log ──
if [[ -f "$PLAYBOOK" ]]; then
  # Check if Research Log section exists
  if grep -q "## Research Log" "$PLAYBOOK" 2>/dev/null; then
    # Prepend today's entry to the Research Log section
    python3 - "$PLAYBOOK" "$TODAY" "$FETCH_SUCCESS" "$FETCH_COUNT" "$FINDINGS_FILE" << 'PYEOF'
import sys

playbook = sys.argv[1]
today = sys.argv[2]
success = sys.argv[3]
total = sys.argv[4]
findings = sys.argv[5]

with open(playbook, "r") as f:
    content = f.read()

entry = f"\n- **{today}:** Researched {success}/{total} sources. See `research/findings-{today}.md` for details.\n"

# Insert after ## Research Log header
marker = "## Research Log"
if marker in content:
    idx = content.index(marker) + len(marker)
    # Find end of line
    nl = content.index("\n", idx)
    content = content[:nl+1] + entry + content[nl+1:]
    with open(playbook, "w") as f:
        f.write(content)
    print(f"PLAYBOOK updated with research entry for {today}")
else:
    print("No Research Log section found in PLAYBOOK")
PYEOF
  else
    # Add Research Log section
    cat >> "$PLAYBOOK" << RLEOF

## Research Log

- **$TODAY:** Researched ${FETCH_SUCCESS}/${FETCH_COUNT} sources. See \`research/findings-${TODAY}.md\` for details.
RLEOF
    log "Added Research Log section to PLAYBOOK"
  fi
fi

# ── 4. Publish to feed if requested ──
if [[ "$PUBLISH" == "--publish" ]]; then
  # Build the feed sections JSON
  INTROSPECTION=$(python3 -c "
import json
with open('$RESULTS_FILE') as f:
    r = json.load(f)
ok = sum(1 for x in r if x['status']=='ok')
fail = sum(1 for x in r if x['status']!='ok')
sources = [x['name'] for x in r if x['status']=='ok']
print(f'Checked {ok} sources today ({fail} failed). Sources: {\", \".join(sources[:5])}.' if sources else f'All {fail} source fetches failed — need to review source list.')
")

  RESEARCH_SUMMARY=$(python3 -c "
import json
with open('$RESULTS_FILE') as f:
    r = json.load(f)
findings = []
for x in r:
    if x['status'] == 'ok' and 'snippet' in x:
        s = x['snippet'][:200].replace('\"','\\\\\"').replace('\n',' ')
        findings.append(f\"{x['name']}: {s[:100]}...\")
print(' | '.join(findings[:3]) if findings else 'No notable findings this cycle.')
")

  FOLLOWUP_JSON=$(python3 -c "
import json
with open('$SOURCES_FILE') as f:
    c = json.load(f)
fus = [f['item'] for f in c.get('followUps',[]) if f.get('status')=='open']
print(json.dumps(fus[:5]))
")

  python3 - "$FEED_SECTIONS" "$INTROSPECTION" "$RESEARCH_SUMMARY" "$FOLLOWUP_JSON" << 'PYEOF'
import json, sys
out = sys.argv[1]
intro = sys.argv[2]
research = sys.argv[3]
followups = json.loads(sys.argv[4])

sections = {
    "introspection": intro,
    "research": research,
    "changes": "Research findings saved. PLAYBOOK updated with research log entry. Raw data archived.",
    "followUps": followups if followups else ["Review today's findings and identify integration candidates"],
    "forKai": "Review my research findings and help me prioritize which to integrate first."
}
with open(out, "w") as f:
    json.dump(sections, f, indent=2)
print(f"Feed sections written to {out}")
PYEOF

  PUBLISH_SCRIPT="$ROOT/bin/publish-to-feed.sh"
  if [[ -x "$PUBLISH_SCRIPT" ]]; then
    bash "$PUBLISH_SCRIPT" "agent-reflection" "$AGENT" \
      "${AGENT^} — Research & Reflection" "$FEED_SECTIONS"
    log "Published research report to feed"
  fi
fi

# ── 5. Sync to research archive ──
RESEARCH_ARCHIVE="$ROOT/agents/ra/research"
AGENT_ARCHIVE="$RESEARCH_ARCHIVE/briefs"
mkdir -p "$AGENT_ARCHIVE"
cp "$FINDINGS_FILE" "$AGENT_ARCHIVE/${AGENT}-${TODAY}.md" 2>/dev/null || true
log "Findings archived to $AGENT_ARCHIVE/${AGENT}-${TODAY}.md"

log "Research cycle complete for $AGENT"
