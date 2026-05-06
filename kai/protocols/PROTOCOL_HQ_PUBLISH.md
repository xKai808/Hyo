# PROTOCOL_HQ_PUBLISH.md
# Version: 1.2
# Author: Kai
# Date: 2026-05-05
# Status: AUTHORITATIVE — every HQ publish must pass these gates
#
# v1.1 (2026-04-21): Added SECTION 7 — ARCHIVE REQUIREMENT.
# v1.2 (2026-05-05): Added research-drop type gates. Three failure modes observed
#   in session 34 and now gated:
#   (1) entry written to entries[] instead of reports[] → invisible in Research tab
#   (2) readLink pointing to .md file → 404 on Vercel (Vercel only serves .html)
#   (3) author capitalization mismatch → orphan filter group instead of merging with Kai
#   (4) no visual click-through verification → broken links declared "done" by Kai
#   All four now have hard gates. See SECTION 8.

---

## PURPOSE

Every item published to hyo.world HQ must follow this protocol. If an agent or Kai publishes
without following it, the content is either invisible, malformed, or unverifiable — all of which
create noise instead of signal for Hyo.

"Ensure anything that is published on HQ is following a protocol. If it doesn't, create one."
— Hyo, 2026-04-21

---

## ALGORITHM-FIRST: THE PUBLISH GATE

These gates run BEFORE any call to `bin/publish-to-feed.sh`. They are not suggestions.
A NO answer stops the publish and requires remediation.

```
PRE-PUBLISH ALGORITHM:

GATE 1: Does this content have a defined report type?
  → Valid types: morning-report, ceo-report, agent-reflection, newsletter,
                 podcast, aether-analysis, nel-report, sam-report, ra-report
  → NO valid type → do not publish; classify first

GATE 2: Does the content meet the minimum section requirements for its type?
  → See Section 3: Schema Requirements by Type
  → NO → do not publish incomplete content

GATE 3: Is the content about REAL work done, not theater?
  → "Research conducted" without specific sources = theater
  → "Improvement shipped" without commit hash = theater
  → "Analysis complete" without data = theater
  → THEATER DETECTED → do not publish; complete the work first

GATE 4: Is today's report a duplicate of a previously published one?
  → Check feed.json for same type + same date
  → YES duplicate → do not publish; update the existing entry if needed

GATE 5: Has the dual-path sync been verified?
  → Both website/data/feed.json AND agents/sam/website/data/feed.json must match
  → NO → sync before publishing

GATE 6: Is the content from a source that has authority to publish it?
  → Nel publishes nel-* types
  → Ra publishes ra-*, newsletter, podcast types
  → Sam publishes sam-* types
  → Aether publishes aether-analysis types
  → Kai publishes morning-report, ceo-report types
  → Dex publishes dex-* types
  → WRONG AUTHOR → route to correct agent

POST-PUBLISH VERIFICATION GATE (run immediately after publish):

GATE 7: Does the live feed at https://www.hyo.world/data/feed.json show the new entry?
  → Fetch and verify (via queue on Mini)
  → NO → deploy is pending; check Vercel; trigger deploy hook if needed

GATE 8: Does HQ render the entry correctly?
  → Fetch https://www.hyo.world and verify report card appears
  → NO → check schema match; may need service worker cache bump (sw.js CACHE version)

GATE 9 (research-drop only): Does the readLink file exist as .html on Vercel?
  → Vercel CANNOT serve .md files. readLink must point to an .html file.
  → Verify: fetch('<readLink>') in browser → must return HTTP 200, not 404
  → NO → create agents/sam/website/docs/research/<slug>.html first, then publish
  → Rule: readLink format is /docs/research/<slug> (no extension; cleanUrls finds .html)

GATE 10 (research-drop only): Is the entry in reports[] not entries[]?
  → The Research tab reads FEED_DATA.reports — it NEVER reads FEED_DATA.entries
  → Verify: python3 -c "import json; d=json.load(open('website/data/feed.json')); print(any(r['id']=='<id>' for r in d['reports']))"
  → NO → entry is invisible. Move from entries[] to reports[].

GATE 11 (research-drop only): Is author capitalized correctly?
  → Author field is case-sensitive. "kai" and "Kai" are different filter groups.
  → Kai's reports use "author": "Kai" (capital K).
  → Verify: grep '"author": "Kai"' website/data/feed.json | wc -l (should match existing count)

GATE 12: Visual click-through verification — MANDATORY, non-skippable.
  → Open hyo.world/hq in browser (fresh load)
  → Click Research in sidebar
  → Click the agent filter (e.g., Kai) — confirm entry appears at top
  → Scroll to the entry — confirm title, sections, confidence badge visible
  → Click "View full research paper →" link
  → Confirm HTTP 200 (page loads, no 404, no blank page)
  → Take screenshot
  → Publication is NOT complete until this step passes. "It should work" is not verification.
```

---

## SECTION 1: WHAT QUALIFIES FOR PUBLICATION

### Publishable: Real work with verifiable evidence

- Agent shipped an improvement (commit hash required)
- Analysis ran and produced actionable output (specific data required)
- Newsletter sent to subscribers (delivery confirmation required)
- Security scan completed (pass/fail counts required)
- Daily reflection with actual findings (not "everything is fine")
- Morning report with per-agent status (shipped/building/researching/stalled)
- CEO report with decisions made and evidence

### NOT Publishable: Theater

- "Conducted research" with no specific sources or findings
- "Monitoring the situation" with no new data
- "Working on improvements" with no shipped code
- Empty agent reflections ("no issues detected" when no checks ran)
- Duplicate reports for the same date
- Reports generated but not verified against live data

### Publication Frequency Limits

| Type | Max per day | Minimum content |
|---|---|---|
| morning-report | 1 | Per-agent status for all 5 agents |
| ceo-report | 1 | Decisions made, work delegated, risks |
| agent-reflection | 2 per agent | Specific findings, improvement status |
| aether-analysis | 1 | Balance confirmed, trade analysis, recommendations |
| newsletter | 1 | Full content, subscriber delivery confirmed |
| nel-report | 1 | QA pass/fail counts, security findings |
| sam-report | 1 | Deployment status, API health, improvements |

---

## SECTION 2: REPORT TYPES AND THEIR TRIGGERS

| Report Type | Author | Trigger | Schedule |
|---|---|---|---|
| `morning-report` | Kai | generate-morning-report.sh | 05:00 MT daily |
| `ceo-report` | Kai | kai-daily-report.sh | 23:30 MT daily |
| `aether-analysis` | Aether | aether.sh publish block | 22:45 MT Mon-Fri |
| `nel-report` | Nel | nel.sh Phase 8 | 22:00 MT daily |
| `sam-report` | Sam | sam.sh final phase | 22:30 MT daily |
| `ra-report` | Ra | ra.sh final phase | After newsletter send |
| `newsletter` | Ra | newsletter.sh | 03:00 MT daily |
| `podcast` | Ra | podcast.py | 06:00 MT daily |
| `agent-reflection` | Any agent | agent runner final phase | Per runner schedule |
| `research-drop` | Kai | Manual / session publish | On demand |

---

## SECTION 3: SCHEMA REQUIREMENTS BY REPORT TYPE

### morning-report (REQUIRED keys)

```json
{
  "type": "morning-report",
  "date": "YYYY-MM-DD",
  "author": "Kai",
  "sections": {
    "summary": "<executive summary: agents_shipped/building/researching/stalled counts>",
    "agents": {
      "<agent>": {
        "shipped_since_last": "<specific commit or 'Nothing shipped'>",
        "highest_priority_issue": "<ONE issue, data-driven>",
        "next_action": "<specific enough to execute in 6h>",
        "action_type": "research|instrumentation|build|deployment",
        "priority_evidence": "<specific data from Phase 1 metrics>"
      }
    },
    "biggest_risk": "<one sentence>",
    "biggest_win": "<one sentence>",
    "growth_trajectory": "expanding|stable|contracting"
  }
}
```

### aether-analysis (REQUIRED keys)

```json
{
  "type": "aether-analysis",
  "date": "YYYY-MM-DD",
  "author": "AetherBot",
  "sections": {
    "balance_confirmed": "<$XXX.XX — must match Kalshi app>",
    "net_pnl": "<today's P&L>",
    "trades_analyzed": "<count>",
    "gpt_crosscheck_ran": true,
    "recommendation": "<BUILD|COLLECT|MONITOR with specific action>",
    "health_flags": "<count and description>",
    "external_factors": "<macro/geopolitical/Kalshi factors assessed>"
  }
}
```

### agent-reflection (REQUIRED keys)

```json
{
  "type": "agent-reflection",
  "date": "YYYY-MM-DD",
  "author": "<agent name>",
  "sections": {
    "introspection": "<what the agent observed about itself this cycle>",
    "research": "<what was researched, sources consulted>",
    "changes": "<what was changed/shipped — specific, with evidence>",
    "followUps": ["<action 1>", "<action 2>"],
    "forKai": "<summary for orchestrator: what Kai needs to know>",
    "bluf": "<bottom line up front — 1 sentence>",
    "improvement_status": "<current GROWTH weakness + stage + evidence>"
  }
}
```
Note: `five_questions` and `bluf` may also appear from ARIC v2 agents.
Updated 2026-04-23 to match actual schema generated by agent runners.

### research-drop (REQUIRED keys) — v1.2

**Critical rules for this type:**
- Entry goes in `reports[]` array — NOT `entries[]`
- `readLink` must point to an `.html` file served by Vercel — `.md` files return 404
- `author` must be `"Kai"` (capital K) to merge with existing Kai filter group
- The `.html` file at `agents/sam/website/docs/research/<slug>.html` MUST be committed before the feed.json entry is written

```json
{
  "id": "<slug>-YYYY-MM-DD",
  "type": "research-drop",
  "title": "...",
  "author": "Kai",
  "authorIcon": "👔",
  "authorColor": "#d4a853",
  "timestamp": "YYYY-MM-DDTHH:MM:SS-06:00",
  "date": "YYYY-MM-DD",
  "sections": {
    "topic": "<one paragraph: what was researched and why>",
    "finding": "<numbered list of key findings>",
    "implications": "<what this means for the Hyo system>",
    "confidence": "HIGH | MEDIUM | LOW",
    "nextSteps": ["<action 1>", "<action 2>", "<action 3>"],
    "readLink": "/docs/research/<slug>"
  }
}
```

**Publish sequence for research-drop:**
1. Write `agents/sam/website/docs/research/<slug>.html` (dark-themed HTML rendering the research)
2. Commit the HTML file: `git add ... && git commit -m "research: add <slug>.html"`
3. Verify it exists: `ls agents/sam/website/docs/research/<slug>.html`
4. Write the feed.json entry (to `reports[]` array, position 0, both paths)
5. Commit feed.json: `git commit -m "publish: <title> to HQ Research tab"`
6. Push both commits: `git push origin main`
7. Wait 15–30s for Vercel deploy
8. Verify live: `fetch('/data/feed.json?t='+Date.now())` → confirm in reports
9. Browser: Research tab → Kai filter → entry visible
10. Browser: click readLink → HTTP 200 (GATE 12 — mandatory visual verification)

### nel-report (REQUIRED keys)

```json
{
  "type": "nel-report",
  "date": "YYYY-MM-DD",
  "author": "Nel",
  "sections": {
    "qa_pass_count": "<N>",
    "qa_fail_count": "<N>",
    "security_findings": "<list or 'none'>",
    "dependency_audit": "<clean|vulnerable — with count>",
    "false_positives_resolved": "<N>",
    "overall_status": "HEALTHY|DEGRADED|CRITICAL"
  }
}
```

---

## SECTION 4: THE PUBLISH COMMAND

All publishes use `bin/publish-to-feed.sh`. Direct writes to feed.json are PROHIBITED.

```bash
# Standard publish (all agents use this pattern):
SECTIONS_FILE="/tmp/<agent>-sections-$(date +%Y%m%d).json"
cat > "$SECTIONS_FILE" << 'EOF'
{
  "summary": "...",
  ... (type-specific required keys)
}
EOF

bash "$ROOT/bin/publish-to-feed.sh" \
  "<report_type>" \
  "<agent_name>" \
  "<Title — Agent Name: Description>" \
  "$SECTIONS_FILE"

# Verify immediately after:
bash "$ROOT/bin/verify-live.sh" --quick 2>/dev/null || echo "WARN: live verify pending"
```

---

## SECTION 5: POST-PUBLISH VERIFICATION

Every publish must be followed by verification. Non-negotiable.

```bash
# Step 1: Verify feed.json has the new entry (local)
python3 -c "
import json
with open('$ROOT/website/data/feed.json') as f:
    d = json.load(f)
today_reports = [r for r in d.get('reports', []) if r.get('date', '') == '$(date +%Y-%m-%d)']
print(f'Today reports in local feed: {len(today_reports)}')
for r in today_reports[-3:]:
    print(f'  - {r.get(\"type\")} | {r.get(\"author\")} | {r.get(\"title\", \"\")[:50]}')
"

# Step 2: Verify live site has updated (via queue on Mini)
# If Vercel auto-deploys from GitHub: wait 60s after push, then verify
# If manual deploy needed: trigger deploy hook first

# Step 3: If live site does NOT match local after 5 minutes:
bash "$ROOT/bin/kai.sh" deploy  # triggers deploy hook
```

---

## SECTION 6: TRIGGER AND ENFORCEMENT

**Trigger**: Every agent runner's final phase calls publish-to-feed.sh
**Execute**: bin/publish-to-feed.sh validates schema → writes to feed.json → dual-path sync
**Verify**: bin/verify-live.sh --quick confirms live site reflects the publish

**Enforcement by Nel**:
- Nel's daily QA run checks: "Did all scheduled reports publish today?"
- Uses bin/report-completeness-check.sh at 07:00 MT
- Missing reports → P1 ticket opened automatically

**Enforcement by Kai**:
- morning-report is Kai's daily responsibility
- If morning-report fails: P0 (Hyo reads this at day start)
- ceo-report is Kai's nightly responsibility

**Who updates this protocol?**
- Kai owns this protocol
- When a new report type is added, update Section 3 immediately
- When schema changes, update Section 3 and publish-to-feed.sh validation in same commit

---

## SECTION 7: ARCHIVE REQUIREMENT (v1.1 — Hyo directive 2026-04-21)

**Every item published to HQ must also be saved to a permanent archive folder.**

Hyo's directive: "This applies to anything published on HQ. We need to save copies into well-organized folders and well-labeled files."

### Archive folder structure

```
agents/
└── [agent]/
    └── archive/
        └── YYYY/
            └── MM/
                └── [agent]-[type]-YYYY-MM-DD.[ext]
```

Examples:
```
agents/nel/archive/2026/04/nel-report-2026-04-21.json
agents/ra/archive/2026/04/ra-daily-2026-04-21.md
agents/ra/archive/2026/04/newsletter-2026-04-21.md
agents/ra/podcasts/2026/podcast-2026-04-21.mp3       ← podcast has its own archive folder
agents/ra/podcasts/2026/script-2026-04-21.txt
kai/archive/2026/04/morning-report-2026-04-21.json
kai/archive/2026/04/ceo-report-2026-04-21.md
agents/aether/archive/2026/04/aether-analysis-2026-04-21.json
agents/sam/archive/2026/04/sam-report-2026-04-21.json
```

### File naming convention

Format: `[agent]-[type]-YYYY-MM-DD.[ext]`

| Report type | Agent | Filename pattern | Extension |
|---|---|---|---|
| morning-report | kai | morning-report-YYYY-MM-DD.json | .json |
| ceo-report | kai | ceo-report-YYYY-MM-DD.md | .md |
| nel-report | nel | nel-report-YYYY-MM-DD.json | .json |
| sam-report | sam | sam-report-YYYY-MM-DD.json | .json |
| ra-report | ra | ra-daily-YYYY-MM-DD.md | .md |
| newsletter | ra | newsletter-YYYY-MM-DD.md | .md |
| podcast | ra | podcast-YYYY-MM-DD.mp3 (in podcasts/) | .mp3 |
| aether-analysis | aether | aether-analysis-YYYY-MM-DD.json | .json |
| aether-daily | aether | aether-daily-YYYY-MM-DD.md | .md |
| agent-reflection | [agent] | [agent]-reflection-YYYY-MM-DD.json | .json |

### Archive gate (runs as part of the post-publish step)

```
ARCHIVE GATE — added to publish-to-feed.sh or each agent runner:

GATE A1: After successful publish to feed.json, was an archive copy written?
  → Location: agents/[agent]/archive/YYYY/MM/[filename]
  → YES → continue
  → NO  → write archive copy now; do NOT mark publish as complete without it

GATE A2: Does the archive filename include the date?
  → YES: [agent]-[type]-YYYY-MM-DD.[ext] → OK
  → NO  → rename before saving

GATE A3: Was the archive directory created (mkdir -p) if it doesn't exist?
  → YES → OK
  → NO  → create it; never fail silently
```

### Implementation in each agent runner

Each runner's publish phase must include an archive step:

```bash
# Archive after successful publish (add to each agent runner)
YEAR=$(date +%Y)
MONTH=$(date +%m)
DATE=$(date +%Y-%m-%d)
ARCHIVE_DIR="$ROOT/agents/$AGENT/archive/$YEAR/$MONTH"
mkdir -p "$ARCHIVE_DIR"

# Copy the output to archive with date-labeled filename
cp "$REPORT_FILE" "$ARCHIVE_DIR/${AGENT}-${REPORT_TYPE}-${DATE}.${EXT}"
echo "[archive] Saved: $ARCHIVE_DIR/${AGENT}-${REPORT_TYPE}-${DATE}.${EXT}"
```

### What the archive is NOT

- The archive is NOT the live feed (that's `website/data/feed.json`)
- The archive is NOT the working output dir (that's `agents/[agent]/logs/` or `output/`)
- The archive does NOT replace the dual-path publish — both still required
- Archive write failure does NOT block the publish — log WARN and continue

### Archive is permanent — do not auto-delete

Archive files are never auto-deleted. They are the complete historical record of everything published to HQ.
Manual archival review happens during PROTOCOL_SYSTEM_MAINTENANCE.md redundancy audits.
The only deletion of archive files requires explicit Hyo approval.

<!-- Last reviewed: 2026-04-21 by protocol-staleness-check.sh -->
