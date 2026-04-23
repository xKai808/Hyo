#!/usr/bin/env python3
"""
bin/context-optimizer.py — Context window optimization tools
Source: Anthropic Compaction API (88% history reduction) + prompt caching research

USAGE:
    # Check current hydration token cost
    python3 bin/context-optimizer.py --audit

    # Generate compaction instructions for Anthropic API
    python3 bin/context-optimizer.py --compaction-prompt

    # Rotate stale JSONL files (run nightly)
    python3 bin/context-optimizer.py --rotate-logs

    # Generate context summary for session start
    python3 bin/context-optimizer.py --session-summary
"""

import os, json, sys, argparse
from pathlib import Path

ROOT = os.environ.get('HYO_ROOT', os.path.expanduser('~/Documents/Projects/Hyo'))

CACHEABLE_BLOCKS = [
    # These blocks should be tagged cache_control: {type: ephemeral} in API calls
    # They are stable for entire sessions → 90% cost reduction on re-reads
    ('CLAUDE.md', 'System identity, role, operating rules — stable'),
    ('KAI_BRIEF.md', 'Session state, current priorities — stable per session'),
    ('kai/memory/KNOWLEDGE.md', 'Permanent knowledge layer — rarely changes'),
    ('kai/memory/TACIT.md', 'Hyo preferences — rarely changes'),
]

NEVER_INJECT = [
    # Files that must NEVER be fully loaded into context
    ('kai/tickets/tickets.jsonl', '55MB+, 14M tokens — use search_tickets() tool instead'),
    ('agents/sam/website/data/feed.json', '295KB, 76K tokens — use get_feed_summary() tool instead'),
]

COMPACTION_INSTRUCTIONS = """
You are summarizing a Cowork session with Kai, the AI orchestrator for hyo.world.

PRESERVE VERBATIM (do not summarize):
- All ticket IDs (e.g. TASK-20260423-*)
- All commit SHAs
- Protocol version numbers (e.g. v2.6, v1.4)
- Exact error messages Hyo reported
- Any explicit corrections Hyo made to Kai's work
- Open P0 and P1 tickets
- Exact file paths of files that were modified

PRESERVE AS STRUCTURED SUMMARY:
- What was shipped (function/file → what it does)
- What was broken and how it was fixed
- What Hyo explicitly approved or rejected
- Current system state (balances, scores, health)

DISCARD:
- Intermediate reasoning that led to a decision (keep only the decision)
- Repeated tool call results (keep only the final successful result)
- Failed attempts before the working solution
- Generic explanations of concepts already understood

SESSION CONTINUITY:
After compaction, Kai must be able to answer without re-reading files:
- What is the current Anthropic credit balance?
- What was the last thing shipped?
- What is the top open P0?
- What did Hyo explicitly ask to NOT do?
"""

def audit_context():
    """Show token cost of all hydration files."""
    print("=== Context Audit ===\n")
    total = 0
    for name, desc in [
        ('KAI_BRIEF.md', 'Session state'),
        ('KAI_TASKS.md', 'Task queue'),
        ('kai/memory/KNOWLEDGE.md', 'Permanent knowledge'),
        ('kai/memory/TACIT.md', 'Hyo preferences'),
        ('kai/ledger/verified-state.json', 'System state'),
        ('kai/ledger/session-handoff.json', 'Session handoff'),
        ('kai/ledger/hyo-inbox.jsonl', 'Inbox messages'),
        ('kai/ledger/known-issues.jsonl', 'Known issues'),
        ('kai/ledger/session-errors.jsonl', 'Session errors'),
    ]:
        path = os.path.join(ROOT, name)
        if os.path.exists(path):
            size = os.path.getsize(path)
            tokens = size // 4
            cost = tokens / 1_000_000 * 3.0
            total += size
            print(f"  {name:<45} {size/1024:>7.1f}KB {tokens:>8,} tokens  ${cost:.4f}")
    
    print(f"\n  {'TOTAL':<45} {total/1024:>7.1f}KB {total//4:>8,} tokens  ${total//4/1_000_000*3:.4f}")
    print(f"\n  Target: <50KB (<12,500 tokens) per session start")
    print(f"  Savings opportunity: prompt caching = 90% off stable blocks")
    print(f"\nFiles to NEVER load (use tools instead):")
    for name, reason in NEVER_INJECT:
        path = os.path.join(ROOT, name)
        if os.path.exists(path):
            size = os.path.getsize(path)
            print(f"  ⛔ {name}: {size/1024:.0f}KB — {reason}")

def compaction_prompt():
    """Print compaction instructions for Anthropic Compaction API."""
    print(COMPACTION_INSTRUCTIONS)

def rotate_logs(max_entries=100):
    """Rotate JSONL log files, keeping only recent entries."""
    log_files = [
        'kai/ledger/known-issues.jsonl',
        'kai/ledger/session-errors.jsonl',
        'kai/ledger/hyo-inbox.jsonl',
    ]
    for rel in log_files:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path): continue
        with open(path) as f:
            lines = [l for l in f if l.strip()]
        if len(lines) > max_entries:
            keep = lines[-max_entries:]
            with open(path, 'w') as f:
                for line in keep:
                    f.write(line)
            print(f"Rotated {rel}: {len(lines)} → {len(keep)} entries")
        else:
            print(f"OK {rel}: {len(lines)} entries (under {max_entries} limit)")

def session_summary():
    """Generate a compact session start summary (replaces large file reads)."""
    try:
        with open(os.path.join(ROOT, 'kai/ledger/verified-state.json')) as f:
            vs = json.load(f)
        with open(os.path.join(ROOT, 'kai/ledger/session-handoff.json')) as f:
            sh = json.load(f)
        
        summary = {
            'credits': {
                'anthropic': vs.get('credits', {}).get('anthropic', {}).get('remaining'),
                'openai': vs.get('credits', {}).get('openai', {}).get('remaining'),
            },
            'sicq_critical': vs.get('sicq', {}).get('critical', {}),
            'open_p0_count': len(vs.get('open_tickets', {}).get('p0', [])),
            'reports_missing': vs.get('report_freshness', {}).get('missing_today', []),
            'top_priority': sh.get('top_priority', '')[:100],
            'shipped_last': sh.get('shipped_this_session', [])[:3],
        }
        
        print(json.dumps(summary, indent=2))
        tokens = len(json.dumps(summary)) // 4
        print(f"\n# Compact summary: ~{tokens} tokens (vs 71,000 for full hydration)")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--audit', action='store_true')
    parser.add_argument('--compaction-prompt', action='store_true')
    parser.add_argument('--rotate-logs', action='store_true')
    parser.add_argument('--session-summary', action='store_true')
    args = parser.parse_args()
    
    if args.audit:
        audit_context()
    elif args.compaction_prompt:
        compaction_prompt()
    elif getattr(args, 'rotate_logs'):
        rotate_logs()
    elif getattr(args, 'session_summary'):
        session_summary()
    else:
        audit_context()
