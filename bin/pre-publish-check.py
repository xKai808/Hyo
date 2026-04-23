#!/usr/bin/env python3
"""
bin/pre-publish-check.py — Pre-Publish Dedup Algorithm
Called by every agent runner before writing to feed.json.

USAGE:
    python3 bin/pre-publish-check.py \
        --agent nel \
        --type nel-daily \
        --title "Nel Daily Report — 2026-04-22" \
        --content "text to check for overlap..."

EXIT:
    0 — OK to publish
    1 — DUPLICATE DETECTED (>60% overlap with recent entry)
    2 — ERROR (check stderr)

ALGORITHM:
    1. Read last 48h of feed entries matching this agent/type
    2. Extract key terms from each (nouns, named entities, numbers)
    3. Compute Jaccard similarity between incoming content and recent entries
    4. If max similarity >0.60 → block with explanation of matching entry
    5. If 0.40-0.60 → warn but allow (log to dedup.jsonl)
    6. <0.40 → allow and log
"""
import sys, os, json, re, argparse
from datetime import datetime, timezone, timedelta
from collections import Counter

ROOT = os.environ.get('HYO_ROOT', os.path.expanduser('~/Documents/Projects/Hyo'))
FEED_PATH = os.path.join(ROOT, 'agents/sam/website/data/feed.json')
DEDUP_LOG = os.path.join(ROOT, 'kai/ledger/dedup.jsonl')
# Daily operational reports (nel-daily, sam-daily, etc.) inherently cover
# the same recurring topics every day — security scans, P&L, health checks.
# Blocking them at 60% would prevent legitimate daily reporting.
# Research drops and reflections have no such exception — they should be unique.
DAILY_REPORT_TYPES = {
    'nel-daily', 'sam-daily', 'ra-daily', 'aether-daily', 'kai-daily',
    'morning-report', 'aether-analysis', 'newsletter', 'nel-qa'
}
BLOCK_THRESHOLD_DAILY   = 0.90  # daily reports: only block near-identical copies
BLOCK_THRESHOLD_RESEARCH = 0.60  # research/reflection: block at 60%
WARN_THRESHOLD  = 0.50
LOOKBACK_HOURS  = 48

def extract_terms(text):
    """Extract meaningful terms for overlap comparison."""
    text = re.sub(r'<[^>]+>', ' ', text)          # strip HTML
    text = re.sub(r'https?://\S+', ' ', text)      # strip URLs
    text = re.sub(r'[^\w\s$%\-\.]', ' ', text)     # strip punctuation
    words = text.lower().split()
    # Filter: keep words >3 chars, exclude stop words
    stop = {'the','and','for','that','this','with','from','have','been','will',
            'not','are','was','were','has','had','can','but','they','their',
            'our','all','its','one','each','also','than','then','when','what'}
    terms = [w for w in words if len(w) > 3 and w not in stop]
    return Counter(terms)

def jaccard(a, b):
    """Jaccard similarity between two Counter term sets."""
    if not a or not b:
        return 0.0
    set_a = set(a.keys())
    set_b = set(b.keys())
    intersection = len(set_a & set_b)
    union = len(set_a | set_b)
    return intersection / union if union > 0 else 0.0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--agent',   required=True)
    parser.add_argument('--type',    required=True)
    parser.add_argument('--title',   default='')
    parser.add_argument('--content', default='')
    parser.add_argument('--date',    default=datetime.now().strftime('%Y-%m-%d'))
    args = parser.parse_args()

    # Load feed
    try:
        with open(FEED_PATH) as f:
            feed = json.load(f)
    except Exception as e:
        print(f'[pre-publish-check] ERROR: Cannot read feed.json: {e}', file=sys.stderr)
        sys.exit(2)

    reports = feed.get('reports', [])
    cutoff = datetime.now(timezone.utc) - timedelta(hours=LOOKBACK_HOURS)

    # Filter recent entries from same agent/type
    recent = []
    for r in reports:
        # Skip same-date entries of same type (today's version replaces, not duplicates)
        if r.get('date', '') == args.date and r.get('type', '') == args.type:
            continue
        ts = r.get('timestamp', '')
        try:
            dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
            if dt.astimezone(timezone.utc) < cutoff:
                continue
        except Exception:
            continue
        # Same agent or same type
        if r.get('author', '').lower() == args.agent.lower() or r.get('type', '') == args.type:
            recent.append(r)

    if not recent:
        print(f'[pre-publish-check] OK: No recent similar entries — safe to publish')
        sys.exit(0)

    # Build term set for incoming content
    incoming_text = args.title + ' ' + args.content
    incoming_terms = extract_terms(incoming_text)

    # Check overlap against each recent entry
    max_sim = 0.0
    max_entry = None
    for r in recent:
        sections = r.get('sections', {})
        entry_text = r.get('title', '') + ' ' + ' '.join(
            str(v) for v in sections.values() if isinstance(v, str)
        )
        entry_terms = extract_terms(entry_text)
        sim = jaccard(incoming_terms, entry_terms)
        if sim > max_sim:
            max_sim = sim
            max_entry = r

    # Apply type-appropriate threshold
    is_daily = args.type in DAILY_REPORT_TYPES
    block_threshold = BLOCK_THRESHOLD_DAILY if is_daily else BLOCK_THRESHOLD_RESEARCH

    # Log result
    log_entry = {
        'ts': datetime.now().astimezone().isoformat(),
        'agent': args.agent,
        'type': args.type,
        'date': args.date,
        'is_daily': is_daily,
        'threshold_used': block_threshold,
        'similarity': round(max_sim, 3),
        'matched_id': max_entry.get('id') if max_entry else None,
        'result': 'BLOCK' if max_sim >= block_threshold else ('WARN' if max_sim >= WARN_THRESHOLD else 'OK')
    }
    try:
        with open(DEDUP_LOG, 'a') as f:
            f.write(json.dumps(log_entry) + '\n')
    except Exception:
        pass

    if max_sim >= block_threshold:
        print(f'[pre-publish-check] DUPLICATE BLOCKED: {round(max_sim*100)}% overlap with {max_entry.get("id")} ({max_entry.get("date")}) [threshold: {round(block_threshold*100)}%]')
        print(f'  Matching entry title: {max_entry.get("title", "")}')
        print(f'  To override: set PRE_PUBLISH_OVERRIDE=1')
        if os.environ.get('PRE_PUBLISH_OVERRIDE') == '1':
            print('[pre-publish-check] OVERRIDE active — allowing publish despite duplicate')
            sys.exit(0)
        sys.exit(1)
    elif max_sim >= WARN_THRESHOLD:
        print(f'[pre-publish-check] WARN: {round(max_sim*100)}% overlap with {max_entry.get("id")} — allowing but logging')
        sys.exit(0)
    else:
        print(f'[pre-publish-check] OK: max overlap {round(max_sim*100)}% — safe to publish')
        sys.exit(0)

if __name__ == '__main__':
    main()
