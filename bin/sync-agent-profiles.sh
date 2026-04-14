#!/usr/bin/env bash
# bin/sync-agent-profiles.sh — Sync agent profiles in feed.json from PLAYBOOKs
#
# This is the SELF-AUTHORING mechanism. Agents write their own PLAYBOOKs,
# and this script reads those PLAYBOOKs to populate the "agents" section
# of feed.json. Kai does NOT write agent profiles — agents do, through
# their PLAYBOOKs, PRIORITIES.md, and ACTIVE.md files.
#
# What gets synced per agent:
#   - responsibilities: from PLAYBOOK.md "Mission" section
#   - goals (short/medium/long): from PRIORITIES.md or PLAYBOOK.md assessment
#   - inProcess: from ACTIVE.md "This Cycle" or PRIORITIES.md "In Progress"
#   - pending: from ACTIVE.md "Open Issues" or PRIORITIES.md "Pending"
#
# Usage: bash bin/sync-agent-profiles.sh
#        Called by generate-morning-report.sh and healthcheck.sh
#
# Runs on Mini via launchd or queue. Safe to run from Cowork (no network needed).

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
FEED="$ROOT/website/data/feed.json"
AGENTS=("nel" "sam" "ra" "aether" "dex")
LOG_TAG="[sync-profiles]"

log() { echo "$LOG_TAG $(TZ='America/Denver' date +%H:%M:%S) $*"; }

if [[ ! -f "$FEED" ]]; then
  log "ERROR: feed.json not found at $FEED"
  exit 1
fi

log "Syncing agent profiles from PLAYBOOKs → feed.json"

python3 - "$FEED" "$ROOT" << 'PYEOF'
import json, sys, os, re

feed_path = sys.argv[1]
root = sys.argv[2]

AGENTS = ["nel", "sam", "ra", "aether", "dex"]
AGENT_META = {
    "nel":    {"name": "Nel",    "role": "System Improvement & Security", "icon": "\U0001F527", "color": "#6dd49c"},
    "sam":    {"name": "Sam",    "role": "Engineering & Infrastructure",  "icon": "\u2699\uFE0F", "color": "#7ec4e0"},
    "ra":     {"name": "Ra",     "role": "Newsletter & Content Intelligence", "icon": "\U0001F4F0", "color": "#b49af0"},
    "aether": {"name": "Aether", "role": "Trading & Financial Intelligence", "icon": "\U0001F4C8", "color": "#e8c96a"},
    "dex":    {"name": "Dex",    "role": "Data Integrity & System Intelligence", "icon": "\U0001F5C3\uFE0F", "color": "#e07060"},
}

def read_file(path):
    """Read file contents or return empty string."""
    if os.path.exists(path):
        with open(path) as f:
            return f.read()
    return ""

def extract_section(content, header, next_headers=None):
    """Extract content under a markdown header until the next header of same or higher level."""
    pattern = rf'^##?\s+{re.escape(header)}\s*$'
    match = re.search(pattern, content, re.MULTILINE | re.IGNORECASE)
    if not match:
        # Try partial match
        for line_num, line in enumerate(content.split('\n')):
            if header.lower() in line.lower() and line.strip().startswith('#'):
                start = content.index(line) + len(line)
                break
        else:
            return ""
    else:
        start = match.end()

    # Find next header of same or higher level
    remaining = content[start:]
    next_match = re.search(r'^##?\s+', remaining, re.MULTILINE)
    if next_match:
        return remaining[:next_match.start()].strip()
    return remaining.strip()

def extract_bullets(text):
    """Extract bullet points from text."""
    bullets = []
    for line in text.split('\n'):
        line = line.strip()
        if line.startswith('- ') or line.startswith('* '):
            # Strip markdown formatting
            item = re.sub(r'\*\*([^*]+)\*\*', r'\1', line[2:]).strip()
            # Strip checkbox markers
            item = re.sub(r'^\[[ x]\]\s*', '', item).strip()
            if item and len(item) > 3:
                bullets.append(item)
    return bullets

def parse_playbook(agent):
    """Parse an agent's PLAYBOOK.md for self-authored content."""
    playbook_path = os.path.join(root, "agents", agent, "PLAYBOOK.md")
    content = read_file(playbook_path)
    if not content:
        return {"mission": "", "strengths": [], "weaknesses": [], "blindspots": []}

    # Extract mission
    mission = extract_section(content, "Mission")
    if not mission:
        # Fallback: first paragraph after the title
        lines = content.split('\n')
        for i, line in enumerate(lines):
            if not line.strip() or line.startswith('#') or line.startswith('|') or line.startswith('-'):
                continue
            if len(line.strip()) > 20:
                mission = line.strip()
                break

    # Extract assessment sub-sections
    assessment = extract_section(content, "Current Assessment")
    strengths = []
    weaknesses = []
    blindspots = []

    if assessment:
        # Parse sub-sections — PLAYBOOKs use **Bold:** format, not ## headers
        def extract_bold_section(text, label):
            """Extract content after **Label:** until the next **Label:** or end."""
            pattern = rf'\*\*{label}:?\*\*\s*'
            match = re.search(pattern, text, re.IGNORECASE)
            if not match:
                return ""
            start = match.end()
            # Find next bold section marker
            next_bold = re.search(r'\*\*\w+:?\*\*', text[start:])
            if next_bold:
                return text[start:start + next_bold.start()].strip()
            return text[start:].strip()

        strength_text = extract_bold_section(assessment, "Strengths")
        if strength_text:
            strengths = [l.strip().lstrip('- ').strip() for l in strength_text.split('\n') if l.strip().startswith('-') or l.strip().startswith('*')]
            strengths = [s for s in strengths if len(s) > 3]

        weakness_text = extract_bold_section(assessment, "Weaknesses")
        if weakness_text:
            weaknesses = [l.strip().lstrip('- ').strip() for l in weakness_text.split('\n') if l.strip().startswith('-') or l.strip().startswith('*')]
            weaknesses = [s for s in weaknesses if len(s) > 3]

        blindspot_text = extract_bold_section(assessment, "Blindspots")
        if blindspot_text:
            blindspots = [l.strip().lstrip('- ').strip() for l in blindspot_text.split('\n') if l.strip().startswith('-') or l.strip().startswith('*')]
            blindspots = [s for s in blindspots if len(s) > 3]

    return {
        "mission": mission[:500] if isinstance(mission, str) else "",
        "strengths": strengths[:5],
        "weaknesses": weaknesses[:5],
        "blindspots": blindspots[:3]
    }

def parse_priorities(agent):
    """Parse PRIORITIES.md for goals."""
    pri_path = os.path.join(root, "agents", agent, "PRIORITIES.md")
    content = read_file(pri_path)

    goals = {"short": [], "medium": [], "long": []}

    if content:
        for key, headers in [("short", ["Short", "P0", "Immediate", "This Week"]),
                              ("medium", ["Medium", "P1", "This Month", "Next"]),
                              ("long", ["Long", "P2", "Vision", "Future"])]:
            for h in headers:
                section = extract_section(content, h)
                if section:
                    bullets = extract_bullets(section)
                    if bullets:
                        goals[key] = bullets[:3]
                        break

    return goals

def parse_active(agent):
    """Parse ACTIVE.md for in-process and pending items."""
    active_path = os.path.join(root, "agents", agent, "ledger", "ACTIVE.md")
    content = read_file(active_path)

    in_process = []
    pending = []

    if content:
        # "This Cycle" section → in process
        cycle = extract_section(content, "This Cycle")
        if cycle:
            in_process = extract_bullets(cycle)

        # "Open Issues" section → pending
        issues = extract_section(content, "Open Issues")
        if issues:
            pending = extract_bullets(issues)

    return {"inProcess": in_process[:5], "pending": pending[:5]}

def build_goals_from_assessment(playbook_data):
    """If no PRIORITIES.md, generate goals from PLAYBOOK weaknesses and blindspots."""
    goals = {"short": [], "medium": [], "long": []}

    # Short-term: address weaknesses
    for w in playbook_data.get("weaknesses", [])[:2]:
        goals["short"].append(f"Fix: {w}")

    # Medium-term: address blindspots
    for b in playbook_data.get("blindspots", [])[:2]:
        goals["medium"].append(f"Build capability: {b}")

    # Long-term: from strengths (extend them)
    for s in playbook_data.get("strengths", [])[:1]:
        goals["long"].append(f"Extend and automate: {s}")

    return goals

# ── Main: Build profiles ──

with open(feed_path) as f:
    feed = json.load(f)

# Preserve Kai's profile (Kai writes his own)
kai_profile = feed.get("agents", {}).get("kai", {
    "name": "Kai",
    "role": "CEO",
    "icon": "\U0001F454",
    "color": "#d4a853",
    "responsibilities": "Strategic direction, agent growth, system architecture, cross-agent coordination.",
    "goals": {"short": [], "medium": [], "long": []},
    "inProcess": [],
    "pending": []
})

agents_section = {"kai": kai_profile}

for agent in AGENTS:
    meta = AGENT_META[agent]
    playbook = parse_playbook(agent)
    priorities = parse_priorities(agent)
    active = parse_active(agent)

    # Use PRIORITIES.md goals if available, otherwise derive from PLAYBOOK assessment
    goals = priorities
    if not any(goals.values()):
        goals = build_goals_from_assessment(playbook)

    # Build responsibilities from mission (self-authored by agent)
    responsibilities = playbook["mission"] if playbook["mission"] else f"{meta['name']} — {meta['role']}. No self-authored mission yet. Update PLAYBOOK.md Mission section."

    profile = {
        "name": meta["name"],
        "role": meta["role"],
        "icon": meta["icon"],
        "color": meta["color"],
        "responsibilities": responsibilities,
        "goals": goals,
        "inProcess": active["inProcess"] if active["inProcess"] else ["No active tasks reported"],
        "pending": active["pending"] if active["pending"] else ["No pending items reported"]
    }

    agents_section[agent] = profile
    print(f"  {agent}: mission={'yes' if playbook['mission'] else 'no'}, "
          f"goals={sum(len(v) for v in goals.values())}, "
          f"inProcess={len(active['inProcess'])}, pending={len(active['pending'])}")

feed["agents"] = agents_section

with open(feed_path, "w") as f:
    json.dump(feed, f, indent=2)

print(f"Synced {len(AGENTS)} agent profiles to {feed_path}")
PYEOF

log "Profile sync complete"
