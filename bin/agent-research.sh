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
            # Extract titles and descriptions from RSS/Atom (handle <item> blocks)
            import re
            # Try <item>-based extraction first (standard RSS)
            item_blocks = re.findall(r'<item[^>]*>(.*?)</item>', content, re.DOTALL)
            items = []
            if item_blocks:
                for block in item_blocks[:15]:
                    title_m = re.search(r'<title[^>]*>(.*?)</title>', block, re.DOTALL)
                    desc_m = re.search(r'<description[^>]*>(.*?)</description>', block, re.DOTALL)
                    link_m = re.search(r'<link[^>]*>(.*?)</link>', block, re.DOTALL)
                    t = re.sub(r'<!\[CDATA\[|\]\]>|<[^>]+>', '', title_m.group(1)).strip() if title_m else ""
                    d = re.sub(r'<!\[CDATA\[|\]\]>|<[^>]+>', '', desc_m.group(1)).strip()[:200] if desc_m else ""
                    l = re.sub(r'<!\[CDATA\[|\]\]>|<[^>]+>', '', link_m.group(1)).strip() if link_m else ""
                    if t:
                        items.append(f"- {t}" + (f": {d}" if d else "") + (f"\n  {l}" if l else ""))
            else:
                # Fallback: Atom <entry> or flat <title> tags
                titles = re.findall(r'<title[^>]*>(.*?)</title>', content, re.DOTALL)
                descriptions = re.findall(r'<description[^>]*>(.*?)</description>', content, re.DOTALL)
                for i, t in enumerate(titles[:10]):
                    t = re.sub(r'<!\[CDATA\[|\]\]>|<[^>]+>', '', t).strip()
                    d = ""
                    if i < len(descriptions):
                        d = re.sub(r'<!\[CDATA\[|\]\]>|<[^>]+>', '', descriptions[i]).strip()[:200]
                    if t and t not in ['', 'CDATA']:
                        items.append(f"- {t}" + (f": {d}" if d else ""))
            snippet = "\n".join(items[:15])
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
            "snippet": snippet[:5000],
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

# ── 2. Synthesize findings — THE THINKING STEP ──
# This is where the agent REASONS about what it found, not just saves it.
# It reads raw data, extracts SPECIFIC intel, compares against its own
# PLAYBOOK (weaknesses, blindspots, goals), and produces DECISIONS.
python3 - "$RESULTS_FILE" "$FINDINGS_FILE" "$AGENT" "$TODAY" "$SOURCES_FILE" "$ROOT" << 'PYEOF'
import json, sys, os, re
from datetime import datetime, timedelta

results_file = sys.argv[1]
findings_file = sys.argv[2]
agent = sys.argv[3]
today = sys.argv[4]
sources_file = sys.argv[5]
root = sys.argv[6]

with open(results_file) as f:
    results = json.load(f)

with open(sources_file) as f:
    config = json.load(f)

# ── Read agent's current state for self-aware analysis ──
playbook_path = os.path.join(root, "agents", agent, "PLAYBOOK.md")
priorities_path = os.path.join(root, "agents", agent, "PRIORITIES.md")
known_issues_path = os.path.join(root, "kai", "ledger", "known-issues.jsonl")

playbook_text = ""
if os.path.exists(playbook_path):
    with open(playbook_path) as f:
        playbook_text = f.read()

priorities_text = ""
if os.path.exists(priorities_path):
    with open(priorities_path) as f:
        priorities_text = f.read()

# Extract agent's own weaknesses and blindspots for comparison
def extract_list_section(text, header):
    pattern = rf'\*\*{header}:?\*\*\s*'
    match = re.search(pattern, text, re.IGNORECASE)
    if not match:
        return []
    start = match.end()
    # Stop at: next **Bold:** header, --- separator, or ## header
    next_stop = re.search(r'\*\*\w+:?\*\*|^---$|^##\s+', text[start:], re.MULTILINE)
    section = text[start:start + next_stop.start()].strip() if next_stop else text[start:].strip()
    items = []
    for line in section.split('\n'):
        line = line.strip()
        if line.startswith('- ') or line.startswith('* '):
            item = line.lstrip('- ').lstrip('* ').strip()
            # Skip checklist items ([ ] Phase 1: ...) — these are operational, not assessment
            if item.startswith('[ ]') or item.startswith('[x]'):
                continue
            if item and len(item) > 5:
                items.append(item)
    return items

my_weaknesses = extract_list_section(playbook_text, "Weaknesses")
my_blindspots = extract_list_section(playbook_text, "Blindspots")
my_strengths = extract_list_section(playbook_text, "Strengths")

# ── AGENT-SPECIFIC INTELLIGENCE EXTRACTORS ──
# Each agent type knows what to look for in raw data.

def extract_cves(text):
    """Extract CVE identifiers from text."""
    return list(set(re.findall(r'CVE-\d{4}-\d{4,}', text)))

def extract_npm_vulns(text):
    """Extract npm package vulnerability mentions."""
    packages = re.findall(r'(?:npm|package|module)\s+[`"\']?([a-z@][a-z0-9\-_@/]+)[`"\']?\s+.*?(?:vulnerab|exploit|malicious)', text, re.IGNORECASE)
    return list(set(packages))

def extract_tools_mentioned(text):
    """Extract security/QA tool names from text."""
    tools = re.findall(r'\b(trivy|snyk|dependabot|renovate|semgrep|codeql|bandit|safety|npm.audit|gitleaks|trufflehog|grype|osv-scanner|socket\.dev|sonarqube|eslint-plugin-security)\b', text, re.IGNORECASE)
    return list(set(t.lower() for t in tools))

def extract_patterns(text):
    """Extract security patterns/techniques mentioned."""
    patterns = re.findall(r'\b(OWASP|XSS|CSRF|SSRF|SQL.injection|path.traversal|RCE|supply.chain|dependency.confusion|typosquatting|prototype.pollution|ReDoS)\b', text, re.IGNORECASE)
    return list(set(p.lower() for p in patterns))

def extract_versions(text):
    """Extract version numbers (for Node.js, npm packages, etc.)."""
    return list(set(re.findall(r'\b(?:v|version\s*)(\d+\.\d+(?:\.\d+)?)\b', text, re.IGNORECASE)))

def extract_urls(text):
    """Extract article/advisory URLs."""
    return list(set(re.findall(r'https?://[^\s<>"\')\]]+', text)))[:10]

def extract_rss_items(text):
    """Extract items from RSS feed content."""
    titles = re.findall(r'<title>([^<]+)</title>', text)
    links = re.findall(r'<link>([^<]+)</link>', text)
    items = []
    for i, title in enumerate(titles[:15]):
        if title in ['', 'CDATA', 'Node.js Blog: Vulnerability Reports']:
            continue
        link = links[i] if i < len(links) else ""
        items.append({"title": title.strip(), "link": link.strip()})
    return items

def extract_json_api(text):
    """Parse JSON API responses for structured data."""
    try:
        data = json.loads(text)
        if isinstance(data, dict):
            # NIST NVD format
            if "vulnerabilities" in data:
                vulns = data["vulnerabilities"]
                if isinstance(vulns, str):
                    # Truncated — parse what we can
                    return {"type": "nvd", "count": data.get("totalResults", "?"), "note": "CVE database accessible"}
                return {"type": "nvd", "count": len(vulns), "items": vulns[:5]}
            # HN Algolia format
            if "hits" in data:
                return {"type": "hn", "items": [{"title": h.get("title",""), "url": h.get("url",""), "points": h.get("points",0)} for h in data["hits"][:10]]}
            # CoinGecko format
            if "coins" in data:
                return {"type": "coingecko", "trending": [c.get("item",{}).get("name","") for c in data["coins"][:5]]}
            # Reddit format
            if "data" in data and "children" in data.get("data", {}):
                posts = data["data"]["children"]
                return {"type": "reddit", "items": [{"title": p["data"].get("title",""), "score": p["data"].get("score",0), "url": p["data"].get("url","")} for p in posts[:10]]}
        return {"type": "unknown", "keys": list(data.keys()) if isinstance(data, dict) else "array"}
    except:
        return None

# ── PROCESS EACH SOURCE WITH REAL EXTRACTION ──

follow_ups = config.get("followUps", [])
open_followups = [f for f in follow_ups if f.get("status") == "open"]

lines = []
lines.append(f"# {agent.capitalize()} Research Findings — {today}")
lines.append(f"")
lines.append(f"**Sources checked:** {len(results)}")
lines.append(f"**Successful:** {sum(1 for r in results if r['status'] == 'ok')}")
lines.append(f"**Agent weaknesses being tracked:** {len(my_weaknesses)}")
lines.append(f"**Open follow-ups:** {len(open_followups)}")
lines.append(f"")

# Accountability first
if open_followups:
    lines.append(f"## Follow-up Accountability")
    lines.append(f"")
    for fu in open_followups:
        age = (datetime.strptime(today, "%Y-%m-%d") - datetime.strptime(fu["date"], "%Y-%m-%d")).days
        stale = " **[STALE — {age}d]**" if age > 7 else ""
        lines.append(f"- [{fu['date']} +{age}d] {fu['item']} — {fu['status']}{stale}")
    lines.append(f"")

# Process sources
all_cves = []
all_tools = []
all_patterns = []
all_versions = []
all_rss_items = []
all_hn_items = []
all_reddit_items = []
specific_findings = []

lines.append(f"## Source Analysis")
lines.append(f"")

for r in results:
    if r["status"] != "ok":
        lines.append(f"### {r['name']} — FAILED")
        lines.append(f"")
        continue

    snippet = r.get("snippet", "")
    source_type = r.get("type", "html")
    focus = r.get("focus", "")

    lines.append(f"### {r['name']}")
    lines.append(f"**Focus:** {focus}")
    lines.append(f"**Data size:** {len(snippet)} chars")
    lines.append(f"")

    # Type-specific extraction
    if source_type == "rss":
        items = extract_rss_items(snippet)
        if items:
            lines.append(f"**Headlines ({len(items)}):**")
            for item in items[:8]:
                lines.append(f"- {item['title']}")
                if item.get('link'):
                    lines.append(f"  {item['link']}")
            all_rss_items.extend(items)
        lines.append(f"")

    elif source_type == "api":
        parsed = extract_json_api(snippet)
        if parsed:
            if parsed["type"] == "nvd":
                lines.append(f"**NVD Database:** {parsed.get('count', '?')} total CVEs indexed")
                if "items" in parsed:
                    for v in parsed["items"][:5]:
                        cve = v.get("cve", {})
                        cve_id = cve.get("id", "unknown")
                        desc = ""
                        for d in cve.get("descriptions", []):
                            if d.get("lang") == "en":
                                desc = d["value"][:150]
                                break
                        if desc:
                            lines.append(f"- **{cve_id}:** {desc}")
                            all_cves.append(cve_id)
            elif parsed["type"] == "hn":
                lines.append(f"**HN Front Page ({len(parsed['items'])} relevant):**")
                for item in parsed["items"][:5]:
                    lines.append(f"- [{item.get('points',0)} pts] {item['title']}")
                    if item.get('url'):
                        lines.append(f"  {item['url']}")
                all_hn_items.extend(parsed["items"])
            elif parsed["type"] == "reddit":
                lines.append(f"**Reddit ({len(parsed['items'])} posts):**")
                for item in parsed["items"][:5]:
                    lines.append(f"- [{item.get('score',0)}] {item['title']}")
                all_reddit_items.extend(parsed["items"])
        lines.append(f"")

    else:  # html
        # Extract structured intel from HTML
        cves = extract_cves(snippet)
        tools = extract_tools_mentioned(snippet)
        patterns = extract_patterns(snippet)
        versions = extract_versions(snippet)

        if cves:
            lines.append(f"**CVEs found:** {', '.join(cves[:10])}")
            all_cves.extend(cves)
        if tools:
            lines.append(f"**Tools mentioned:** {', '.join(tools)}")
            all_tools.extend(tools)
        if patterns:
            lines.append(f"**Security patterns:** {', '.join(patterns)}")
            all_patterns.extend(patterns)
        if versions:
            lines.append(f"**Versions referenced:** {', '.join(versions[:5])}")
            all_versions.extend(versions)
        if not any([cves, tools, patterns, versions]):
            # Fallback: extract first meaningful text block
            clean = re.sub(r'<[^>]+>', ' ', snippet)
            clean = re.sub(r'\s+', ' ', clean).strip()
            if len(clean) > 100:
                lines.append(f"**Content preview:** {clean[:300]}...")
        lines.append(f"")

    lines.append(f"")

# ── THINKING: What does this mean for ME? ──
lines.append(f"## My Analysis")
lines.append(f"")
lines.append(f"Here's what I ({agent}) extracted and what it means for my work:")
lines.append(f"")

# Deduplicate
all_cves = list(set(all_cves))
all_tools = list(set(all_tools))
all_patterns = list(set(all_patterns))

# Compare against my weaknesses
weakness_matches = []
for w in my_weaknesses:
    w_lower = w.lower()
    if "false positive" in w_lower and any(t in all_tools for t in ["semgrep", "codeql", "eslint-plugin-security"]):
        weakness_matches.append(f"My weakness '{w[:60]}...' — tools like {', '.join(t for t in all_tools if t in ['semgrep','codeql','eslint-plugin-security'])} could help reduce false positives")
    if "runtime" in w_lower and any(t in all_tools for t in ["trivy", "grype", "osv-scanner"]):
        weakness_matches.append(f"My weakness '{w[:60]}...' — runtime scanners like {', '.join(t for t in all_tools if t in ['trivy','grype','osv-scanner'])} could add this capability")
    if "dependency" in w_lower and any(t in all_tools for t in ["dependabot", "renovate", "snyk", "npm.audit", "safety"]):
        weakness_matches.append(f"My weakness '{w[:60]}...' — dependency tools {', '.join(t for t in all_tools if t in ['dependabot','renovate','snyk','npm.audit','safety'])} directly address this gap")
    if "api" in w_lower and any(p in all_patterns for p in ["owasp", "xss", "csrf", "ssrf", "sql injection"]):
        weakness_matches.append(f"My weakness '{w[:60]}...' — OWASP patterns found in research. I should integrate {', '.join(p for p in all_patterns if p in ['owasp','xss','csrf','ssrf','sql injection'])} testing")

if weakness_matches:
    lines.append(f"### Findings that address my weaknesses:")
    for wm in weakness_matches:
        lines.append(f"- {wm}")
    lines.append(f"")
else:
    lines.append(f"*No direct matches between today's findings and my {len(my_weaknesses)} tracked weaknesses. This could mean my sources need broadening or my weaknesses need different research.*")
    lines.append(f"")

# Blindspot analysis
blindspot_matches = []
for b in my_blindspots:
    b_lower = b.lower()
    if "dependency" in b_lower and all_cves:
        blindspot_matches.append(f"My blindspot '{b[:60]}...' — {len(all_cves)} CVEs found today. I'm not scanning for these. This is a real gap.")
    if "api" in b_lower and any(p in all_patterns for p in ["owasp", "xss", "csrf", "ssrf"]):
        blindspot_matches.append(f"My blindspot '{b[:60]}...' — attack patterns ({', '.join(all_patterns[:3])}) active in the wild. I have zero detection for these.")

if blindspot_matches:
    lines.append(f"### Blindspot alerts:")
    for bm in blindspot_matches:
        lines.append(f"- **WARNING:** {bm}")
    lines.append(f"")

# What I'm NOT seeing
lines.append(f"### What I'm not seeing:")
if not all_cves:
    lines.append(f"- No CVEs extracted from sources. Either my sources don't expose them clearly or my parsing needs improvement.")
if not all_tools:
    lines.append(f"- No competitor/alternative tools detected. My sources may be too general — need more targeted security tooling feeds.")
if not all_patterns:
    lines.append(f"- No attack pattern references found. Should add sources focused on active exploitation (e.g., CISA KEV catalog).")
lines.append(f"")

# ── DECISIONS: What I'm going to do about it ──
lines.append(f"## Decisions")
lines.append(f"")

decisions = []
new_followups = []

if all_cves:
    decisions.append(f"Track {len(all_cves)} CVEs found today. Cross-reference against our package.json dependencies next cycle.")
    new_followups.append({"date": today, "item": f"Cross-reference {len(all_cves)} CVEs ({', '.join(all_cves[:3])}) against our dependencies", "status": "open", "outcome": ""})

if all_tools:
    tools_str = ", ".join(all_tools[:5])
    decisions.append(f"Evaluate tools: {tools_str}. Compare against my current cipher/sentinel approach.")
    new_followups.append({"date": today, "item": f"Evaluate tools ({tools_str}) for integration into QA cycle", "status": "open", "outcome": ""})

if weakness_matches:
    decisions.append(f"Address {len(weakness_matches)} weakness-to-finding matches. Prioritize the one with the most direct tool solution.")
    new_followups.append({"date": today, "item": f"Implement fix for top weakness match: {weakness_matches[0][:80]}", "status": "open", "outcome": ""})

if blindspot_matches:
    decisions.append(f"URGENT: {len(blindspot_matches)} blindspot(s) confirmed by active threats in the wild. Need to build detection capability.")

if all_rss_items:
    decisions.append(f"Read {len(all_rss_items)} RSS items. Top headlines logged for trend analysis.")

if all_hn_items:
    top = sorted(all_hn_items, key=lambda x: x.get("points",0), reverse=True)[:3]
    if top:
        decisions.append(f"Top HN discussions: {'; '.join(t['title'][:60] for t in top)}. Check if any apply to our stack.")

if not decisions:
    decisions.append("No actionable findings this cycle. Will diversify sources next run.")

for d in decisions:
    lines.append(f"- {d}")
lines.append(f"")

# ── GOALS UPDATE: What this changes about my priorities ──
lines.append(f"## Goal Impact")
lines.append(f"")
if weakness_matches or blindspot_matches:
    lines.append(f"This research changes my priorities:")
    if blindspot_matches:
        lines.append(f"- **NEW SHORT-TERM GOAL:** Build detection for {', '.join(all_patterns[:3]) if all_patterns else 'confirmed blindspot patterns'}")
    if weakness_matches:
        lines.append(f"- **UPDATED GOAL:** Accelerate fix for '{weakness_matches[0][:50]}...' — tools exist")
    if all_tools:
        lines.append(f"- **NEW MEDIUM-TERM GOAL:** Evaluate and integrate {all_tools[0]} into QA cycle")
else:
    lines.append(f"No priority changes from this research cycle. Current goals remain valid.")
lines.append(f"")

# ── METRICS ──
lines.append(f"## Research Metrics")
lines.append(f"")
lines.append(f"- CVEs extracted: {len(all_cves)}")
lines.append(f"- Tools discovered: {len(all_tools)}")
lines.append(f"- Attack patterns: {len(all_patterns)}")
lines.append(f"- RSS headlines: {len(all_rss_items)}")
lines.append(f"- HN discussions: {len(all_hn_items)}")
lines.append(f"- Reddit posts: {len(all_reddit_items)}")
lines.append(f"- Weakness matches: {len(weakness_matches)}")
lines.append(f"- Blindspot alerts: {len(blindspot_matches)}")
lines.append(f"- New follow-ups created: {len(new_followups)}")
lines.append(f"")

with open(findings_file, "w") as f:
    f.write("\n".join(lines))

# ── UPDATE follow-ups in research-sources.json ──
if new_followups:
    config["followUps"] = config.get("followUps", []) + new_followups
    with open(sources_file, "w") as f:
        json.dump(config, f, indent=2)

# ── UPDATE PRIORITIES.md if research changed goals ──
if weakness_matches or blindspot_matches:
    pri_updates = []
    if blindspot_matches:
        pri_updates.append(("P0", f"[RESEARCH] Build detection for confirmed blindspot: {blindspot_matches[0][:80]}"))
    if weakness_matches:
        pri_updates.append(("P1", f"[RESEARCH] Fix weakness using discovered tool: {weakness_matches[0][:80]}"))
    if all_tools:
        pri_updates.append(("P2", f"[RESEARCH] Evaluate {all_tools[0]} for integration into QA cycle"))

    pri_path = os.path.join(root, "agents", agent, "PRIORITIES.md")
    if os.path.exists(pri_path):
        with open(pri_path) as f:
            pri_content = f.read()
        # Append to Active Priority Queue
        for pri, desc in pri_updates:
            if desc not in pri_content:
                entry = f"| ? | {pri} | {desc} | OPEN | {today} |\n"
                if "| # |" in pri_content:
                    # Find last row of table
                    table_end = pri_content.rfind("\n\n", 0, pri_content.find("## Daily Research"))
                    if table_end > 0:
                        pri_content = pri_content[:table_end] + "\n" + entry + pri_content[table_end:]
        with open(pri_path, "w") as f:
            f.write(pri_content)
        print(f"PRIORITIES.md updated with {len(pri_updates)} research-driven items")

print(f"Findings written: {findings_file} ({len(lines)} lines)")
print(f"CVEs: {len(all_cves)}, Tools: {len(all_tools)}, Patterns: {len(all_patterns)}")
print(f"Weakness matches: {len(weakness_matches)}, Blindspot alerts: {len(blindspot_matches)}")
print(f"New follow-ups: {len(new_followups)}")
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
# Build feed entry from the REAL analysis (not templates)
if [[ "$PUBLISH" == "--publish" ]]; then
  python3 - "$FEED_SECTIONS" "$FINDINGS_FILE" "$RESULTS_FILE" "$SOURCES_FILE" "$AGENT" << 'PYEOF'
import json, sys, os, re

out = sys.argv[1]
findings_path = sys.argv[2]
results_path = sys.argv[3]
sources_path = sys.argv[4]
agent = sys.argv[5]

with open(findings_path) as f:
    findings = f.read()

with open(results_path) as f:
    results = json.load(f)

with open(sources_path) as f:
    config = json.load(f)

ok = sum(1 for r in results if r["status"] == "ok")
total = len(results)

# Extract the My Analysis section from findings
analysis = ""
if "## My Analysis" in findings:
    analysis = findings.split("## My Analysis")[1].split("## Decisions")[0].strip()
    # Clean markdown formatting for feed display
    analysis = re.sub(r'\*\*([^*]+)\*\*', r'\1', analysis)
    analysis = re.sub(r'###\s+', '', analysis)
    analysis = analysis[:500]

# Extract Decisions section
decisions = ""
if "## Decisions" in findings:
    decisions = findings.split("## Decisions")[1].split("## Goal Impact")[0].strip()
    decisions = re.sub(r'\*\*([^*]+)\*\*', r'\1', decisions)
    decisions = decisions[:400]

# Extract metrics
metrics = ""
if "## Research Metrics" in findings:
    metrics = findings.split("## Research Metrics")[1].strip()
    metrics = metrics[:300]

# Get follow-ups
followups = [fu["item"] for fu in config.get("followUps", []) if fu.get("status") == "open"]

sections = {
    "introspection": f"Researched {ok}/{total} sources. {analysis}" if analysis else f"Checked {ok}/{total} sources. No deep analysis produced.",
    "research": decisions if decisions else "No actionable findings this cycle.",
    "changes": metrics if metrics else f"Research data saved. {ok} sources processed.",
    "followUps": followups[:5] if followups else ["Broaden source list for higher signal"],
    "forKai": f"I found {'matches against my weaknesses' if 'weakness match' in findings.lower() else 'no direct weakness matches'}. {'BLINDSPOT CONFIRMED — need help building detection.' if 'blindspot alert' in findings.lower() else 'Current priorities unchanged.'}"
}

with open(out, "w") as f:
    json.dump(sections, f, indent=2)
print(f"Feed sections written to {out}")
PYEOF

  PUBLISH_SCRIPT="$ROOT/bin/publish-to-feed.sh"
  if [[ -x "$PUBLISH_SCRIPT" ]]; then
    AGENT_TITLE=$(echo "$AGENT" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
    bash "$PUBLISH_SCRIPT" "agent-reflection" "$AGENT" \
      "$AGENT_TITLE — Research & Reflection" "$FEED_SECTIONS"
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
