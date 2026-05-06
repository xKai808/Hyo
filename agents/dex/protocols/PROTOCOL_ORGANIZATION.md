# PROTOCOL_ORGANIZATION.md
# Owner: Dex (System Memory Manager)
# Version: 1.0
# Date: 2026-05-05
# Status: ACTIVE

## Purpose

Dex owns system organization. This protocol defines how Dex detects, reports, and fixes structural issues in the Hyo codebase: silos, redundancies, patchwork, stale cross-references, and file drift.

Hyo directive (2026-05-05): "Parse through every file you have access to and see if it is necessary... siloed? redundant? necessary? removable? consolidatable? integrative? patchwork?"

---

## What Dex Does as System Organizer

### 1. Weekly Organization Audit
Every Saturday (after weekly-maintenance.sh), Dex runs a full system scan:

**Checks performed:**
- **Redundancy detection**: Files with >80% content overlap across the codebase
- **Silo detection**: Files with no incoming references from any other file
- **Stale cross-reference detection**: Files that reference paths that no longer exist
- **Patchwork detection**: Scripts that duplicate functionality of an existing script
- **Dual-path drift**: Files that should exist in both `website/` and `agents/sam/website/` but are missing from one (SE-010-011)
- **Temp file accumulation**: *.tmp*, *.new, *.bak at root or agent level
- **Archive candidates**: Files older than 30 days in research/raw or logs/ that weren't compressed

**Output**: `agents/dex/logs/organization-YYYY-MM-DD.md` — audit report with findings and recommended actions.

### 2. File Classification System
Each file Dex reviews gets one of these classifications:
- `NECESSARY` — actively used, no overlap, clear purpose
- `REDUNDANT` — duplicates another file's content or purpose (recommend merge)
- `SILOED` — no inbound references, no trigger, floating (recommend remove or wire)
- `STALE` — last modified >30d with no active consumers (recommend archive or remove)
- `PATCHWORK` — addresses a symptom instead of the root cause (flag for systemic fix)
- `INTEGRATIVE` — connects multiple subsystems, high-value, protect carefully
- `CONSOLIDATE-CANDIDATE` — similar purpose to another file, merge is safe

### 3. Dual-Path Compliance Check
Dex runs a dual-path audit weekly:
```bash
# Check that all HTML files in agents/sam/website/ also exist in website/
find agents/sam/website -name "*.html" | while read f; do
  rel="${f#agents/sam/}"
  [[ ! -f "$rel" ]] && echo "MISSING dual-path: $rel"
done
```
Any missing file is reported as P1. Dex does NOT auto-sync (that's GATE R2 in publish-to-feed.sh). Dex reports, human or Kai acts.

### 4. Cross-Reference Integrity
Dex validates that links referenced in key files actually exist:
- `KAI_BRIEF.md` — all file references
- `CLAUDE.md` — all protocol references
- `KNOWLEDGE.md` — all file paths
- `agents/*/PLAYBOOK.md` — all referenced scripts and protocols

Broken references are reported as P2 tickets.

### 5. Archive Enforcement
Dex verifies that `bin/archive-old-files.sh` ran correctly each Saturday:
- Checks `agents/*/archive/` exists and has current month entries
- Verifies no research/raw files older than 60 days remain unarchived
- Reports stragglers as P2

---

## When Organization Protocol Runs

| Trigger | Action |
|---|---|
| Saturday 03:30 MT (after weekly-maintenance) | Full organization audit |
| Any new file committed | Dex checks for dual-path compliance on research HTMLs |
| Agent reports "file not found" error | Dex cross-reference integrity scan |
| Hyo requests audit | `bash agents/dex/dex.sh --org-audit` |

---

## Output Format

Organization audit goes to `agents/dex/logs/organization-YYYY-MM-DD.md`:

```markdown
# Organization Audit — YYYY-MM-DD

## Summary
- NECESSARY: N files
- REDUNDANT: N files → recommended merges: X
- SILOED: N files → recommended removals: X
- STALE: N files → recommended archives: X
- PATCHWORK: N files → flagged for systemic fix

## Dual-Path Gaps
[List any files missing from website/]

## Stale Cross-References
[List any broken file references]

## Recommended Actions (priority order)
1. [highest impact action]
2. ...

## No-Action Items
[files reviewed and cleared]
```

---

## Decision Authority

- Dex detects and reports. Dex does NOT auto-delete files.
- Kai approves removal of REDUNDANT and SILOED files before action.
- Hyo approves any action that changes agent interfaces or spending.
- Archive candidates go through `bin/archive-old-files.sh` (automated, no approval needed for files >30d old).

---

## Integration Points

- `bin/weekly-maintenance.sh` → calls Dex org audit at step 4.7 (Saturday only)
- `bin/publish-to-feed.sh` GATE R2 → handles dual-path sync at publish time
- `bin/archive-old-files.sh` → handles file compression (Dex verifies, doesn't duplicate)
- `agents/dex/dex.sh` → add `--org-audit` flag to call this protocol on demand
