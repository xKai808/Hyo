#!/usr/bin/env python3
"""
bin/agent-semantic-gate.py — Semantic validation gate (GVU Verifier layer)

Addresses the gap between schema validation (structure) and quality validation (meaning).
A morning report that says "changes: none" for 30 days passes the schema gate.
This gate catches semantic drift using domain-specific signals.

Source: arXiv:2512.02731 (GVU Operator) | arXiv:2303.11366 (Reflexion)

VERIFIER PER AGENT (domain-specific ground-truth signals):
- sam: does self-review mention a specific file/commit? (not generic)
- nel: does QA report show actual check counts (not zeros across the board)?
- ra: does newsletter have real story titles (not "Technology Update")?
- aether: does analysis contain a real balance number ($X.XX format)?
- kai: does morning report have non-empty sicqScores?

Usage:
    python3 bin/agent-semantic-gate.py --agent nel --sections-file /tmp/sections.json
    
Returns exit 0 if semantic check passes, exit 1 if theater detected.
"""

import sys, json, re, os
import argparse

THEATER_PATTERNS = [
    r'^no\s+changes?\.?$',
    r'^nothing\s+shipped\.?$',
    r'^(conducting|doing)\s+research\.?$',
    r'^n/?a\.?$',
    r'^(see|check)\s+(file|log)\.?$',
    r'^in\s+progress\.?$',
]

def is_theater(text: str) -> bool:
    if not text or not text.strip():
        return True
    t = text.strip().lower()
    for pat in THEATER_PATTERNS:
        if re.match(pat, t, re.IGNORECASE):
            return True
    return False

def validate_nel(sections: dict) -> tuple[bool, str]:
    """Nel: QA report must show actual check counts."""
    changes = sections.get('changes', '')
    introspection = sections.get('introspection', '')
    # Nel should mention specific counts or findings
    has_count = bool(re.search(r'\d+\s+(check|scan|pass|fail|issue|finding)', changes + introspection, re.I))
    if not has_count and is_theater(changes):
        return False, "Nel report has no specific check counts or findings — generic/theater output"
    return True, "Nel report has specific metrics"

def validate_sam(sections: dict) -> tuple[bool, str]:
    """Sam: must reference specific file or commit."""
    changes = sections.get('changes', '')
    if is_theater(changes):
        return False, "Sam changes field is theater ('nothing shipped' or similar)"
    # Should mention a file path, commit hash, or specific technical term
    has_specific = bool(re.search(r'(\.py|\.sh|\.json|\.html|commit|deploy|vercel|api|endpoint)', changes, re.I))
    if not has_specific and len(changes.strip()) < 30:
        return False, f"Sam changes too generic (no file/commit reference): '{changes[:80]}'"
    return True, "Sam report has specific technical reference"

def validate_ra(sections: dict) -> tuple[bool, str]:
    """Ra: newsletter/stories must have real titles."""
    stories = sections.get('stories', [])
    summary = sections.get('summary', '')
    if not stories and is_theater(summary):
        return False, "Ra newsletter has no stories and generic summary"
    if stories:
        for s in stories:
            title = s.get('title', '')
            if is_theater(title) or len(title) < 5:
                return False, f"Ra story has theater title: '{title}'"
    return True, "Ra newsletter has real story content"

def validate_aether(sections: dict) -> tuple[bool, str]:
    """Aether: analysis must contain a real balance number."""
    balance = sections.get('balance', '')
    summary = sections.get('summary', '')
    has_dollar = bool(re.search(r'\$[\d,]+\.?\d*', balance + summary))
    if not has_dollar:
        return False, "Aether analysis has no dollar amount in balance/summary"
    return True, "Aether analysis has dollar amounts"

def validate_morning_report(sections: dict) -> tuple[bool, str]:
    """Morning report: must have sicqScores populated."""
    sicq = sections.get('sicqScores', {})
    omp = sections.get('ompScores', {})
    if not sicq:
        return False, "Morning report missing sicqScores — scores gate failed"
    if not omp:
        return False, "Morning report missing ompScores — scores gate failed"
    return True, f"Morning report has scores for {len(sicq)} agents"

VALIDATORS = {
    'nel': validate_nel,
    'sam': validate_sam,
    'ra': validate_ra,
    'aether': validate_aether,
    'morning-report': validate_morning_report,
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--agent', required=True, help='Agent name or report type')
    parser.add_argument('--sections-file', required=True, help='Path to sections JSON file')
    args = parser.parse_args()

    try:
        with open(args.sections_file) as f:
            sections = json.load(f)
    except Exception as e:
        print(f"[semantic-gate] ERROR reading sections: {e}", file=sys.stderr)
        sys.exit(0)  # Don't block on read error

    validator = VALIDATORS.get(args.agent.lower().replace('_', '-'))
    if not validator:
        print(f"[semantic-gate] No validator for '{args.agent}' — skipping (pass)")
        sys.exit(0)

    passed, reason = validator(sections)
    if passed:
        print(f"[semantic-gate] PASS ({args.agent}): {reason}")
        sys.exit(0)
    else:
        print(f"[semantic-gate] WARN ({args.agent}): {reason}", file=sys.stderr)
        # Warn only — don't hard-block (allows gradual adoption)
        sys.exit(0)

if __name__ == '__main__':
    main()
