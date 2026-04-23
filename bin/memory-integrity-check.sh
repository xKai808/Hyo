#!/usr/bin/env bash
# bin/memory-integrity-check.sh
# Scans memory files for untagged facts, stale entries, and inferences past expiry.
# Runs daily via daily-maintenance.sh. Output: kai/ledger/memory-integrity.log
#
# See: kai/protocols/PROTOCOL_MEMORY_INTEGRITY.md for full rationale.

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
LOG="$ROOT/kai/ledger/memory-integrity.log"
INBOX="$ROOT/kai/ledger/hyo-inbox.jsonl"

issues=0
log() { echo "[$NOW_MT] $*" | tee -a "$LOG"; }

log "=== Memory Integrity Check — $TODAY ==="

python3 - "$ROOT" "$TODAY" << 'PYEOF'
import os, sys, re, json
from datetime import datetime, timedelta

root, today_str = sys.argv[1], sys.argv[2]
today = datetime.strptime(today_str, '%Y-%m-%d')
issues = []

# ── Files to check ────────────────────────────────────────────────────────────
check_files = [
    os.path.join(root, 'kai/memory/KNOWLEDGE.md'),
    os.path.join(root, 'kai/ledger/session-handoff.json'),
    os.path.join(root, 'KAI_BRIEF.md'),
]

# ── Tag patterns ──────────────────────────────────────────────────────────────
FACT_TAGS = re.compile(r'\[FACT-(READ|COMPUTED|STATED)[^\]]*(\d{4}-\d{2}-\d{2})[^\]]*\]')
INFERENCE_TAG = re.compile(r'\[INFERENCE[^\]]*(\d{4}-\d{2}-\d{2})[^\]]*\]')
STALE_TAG = re.compile(r'\[STALE')

# Lines that are factual claims (heuristic: contain numbers, specific names, percentages)
CLAIM_PATTERN = re.compile(
    r'(→|:\s+\$[\d.]+|\d+%|\d+K tokens|\d+MB|\d+\.\d+h|is logged (in|out)|'
    r'SICQ.*\d+|passed=\d+|failed=\d+|score.*\d+/100)'
)

for filepath in check_files:
    if not os.path.exists(filepath):
        continue
    fname = os.path.basename(filepath)

    if filepath.endswith('.json'):
        # Check session-handoff.json for staleness
        try:
            d = json.load(open(filepath))
            ended_at = d.get('ended_at', '')
            if ended_at:
                ended = datetime.fromisoformat(ended_at.replace('Z','+00:00'))
                age_h = (datetime.now(ended.tzinfo) - ended).total_seconds() / 3600
                if age_h > 48:
                    issues.append(f'[STALE] {fname}: session-handoff is {age_h:.0f}h old — treat all claims as unverified until re-read from live files')
        except Exception as e:
            issues.append(f'[ERROR] {fname}: could not parse — {e}')
        continue

    with open(filepath) as f:
        lines = f.readlines()

    for lineno, line in enumerate(lines, 1):
        line_s = line.strip()
        if not line_s or line_s.startswith('#'):
            continue

        # Check for inferences older than 48h
        inf_match = INFERENCE_TAG.search(line_s)
        if inf_match:
            inf_date_str = inf_match.group(1)
            try:
                inf_date = datetime.strptime(inf_date_str, '%Y-%m-%d')
                age_days = (today - inf_date).days
                if age_days >= 2:
                    issues.append(
                        f'[EXPIRED-INFERENCE] {fname}:{lineno}: '
                        f'inference is {age_days}d old — verify or remove: '
                        f'{line_s[:80]}'
                    )
            except ValueError:
                pass

        # Check for factual claims without any tag
        if CLAIM_PATTERN.search(line_s):
            has_tag = (FACT_TAGS.search(line_s) or
                      INFERENCE_TAG.search(line_s) or
                      STALE_TAG.search(line_s))
            # Skip lines that are headers, code blocks, or already tagged elsewhere in section
            if not has_tag and not line_s.startswith(('-', '*', '`', '|', '>', '!')):
                # Only flag if it looks like a standalone factual claim (not in code)
                if ':' in line_s or '→' in line_s:
                    issues.append(
                        f'[UNTAGGED-CLAIM] {fname}:{lineno}: '
                        f'factual claim without source tag: {line_s[:80]}'
                    )

        # Check for [FACT-*] entries with dates older than 7 days
        fact_match = FACT_TAGS.search(line_s)
        if fact_match:
            fact_date_str = fact_match.group(2)
            try:
                fact_date = datetime.strptime(fact_date_str, '%Y-%m-%d')
                age_days = (today - fact_date).days
                if age_days > 7:
                    issues.append(
                        f'[STALE-FACT] {fname}:{lineno}: '
                        f'fact is {age_days}d old without re-verification: '
                        f'{line_s[:80]}'
                    )
            except ValueError:
                pass

print(f'Issues found: {len(issues)}')
for issue in issues[:30]:  # cap output at 30
    print(f'  {issue}')

if len(issues) > 30:
    print(f'  ... and {len(issues)-30} more (see full log)')

# Write structured log for inbox escalation
output = {
    'ts': __import__('datetime').datetime.now().isoformat(),
    'date': today_str,
    'issues': issues,
    'issue_count': len(issues),
    'status': 'clean' if not issues else 'needs_review'
}

log_path = os.path.join(root, 'kai/ledger/memory-integrity-latest.json')
with open(log_path, 'w') as f:
    json.dump(output, f, indent=2)

# Escalate to Hyo inbox if there are expired inferences
expired = [i for i in issues if i.startswith('[EXPIRED-INFERENCE]')]
if expired:
    inbox_path = os.path.join(root, 'kai/ledger/hyo-inbox.jsonl')
    entry = {
        'ts': __import__('datetime').datetime.now().isoformat(),
        'from': 'memory-integrity-check',
        'priority': 'P1',
        'status': 'unread',
        'message': f'Memory integrity: {len(expired)} expired inference(s) need verification or removal. Check kai/ledger/memory-integrity-latest.json'
    }
    with open(inbox_path, 'a') as f:
        f.write(json.dumps(entry) + '\n')
    print(f'  → Escalated {len(expired)} expired inferences to Hyo inbox')
PYEOF

log "Memory integrity check complete"
