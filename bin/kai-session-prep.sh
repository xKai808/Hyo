#!/usr/bin/env bash
# bin/kai-session-prep.sh — Pre-Session Verified State Snapshot
#
# PURPOSE:
#   Compute verified truth for every system dimension before Kai speaks.
#   Writes kai/ledger/verified-state.json — Kai reads this first at session start.
#   Any claim Kai makes must come from this file or a fresh file read.
#   Assumption-based claims become impossible when truth is pre-computed.
#
# RUNS:
#   - By launchd at 05:30 MT daily (same window as flywheel-doctor)
#   - By kai-autonomous.sh before session-handoff.json is written
#   - Manually: HYO_ROOT=... bash bin/kai-session-prep.sh
#
# OUTPUT:
#   kai/ledger/verified-state.json — the authoritative current state
#
# ARCHITECTURE:
#   The root cause of Kai's assumption errors is not bad rules.
#   It's that verified data isn't ready when Kai needs it.
#   This script eliminates the gap: truth is always pre-computed,
#   Kai reads it, claims match reality. No prompting required.

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
NOW_MT=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
TODAY=$(TZ=America/Denver date +%Y-%m-%d)
OUT="$ROOT/kai/ledger/verified-state.json"

mkdir -p "$(dirname "$OUT")"

python3 - "$ROOT" "$NOW_MT" "$TODAY" "$OUT" << 'PYEOF'
import json, os, re, sys
from datetime import datetime, timezone, timedelta
from collections import defaultdict

root, ts, today, out_path = sys.argv[1:5]

state = {
    "verified_at": ts,
    "today": today,
    "computed_by": "kai-session-prep.sh",
    "note": "All values computed from source files. Kai must use this, not assumptions.",
}

# ── 1. API Credits (computed from scraped-credits.json + api-usage.jsonl) ────
try:
    with open(os.path.join(root, 'agents/ant/ledger/scraped-credits.json')) as f:
        scraped = json.load(f)
    with open(os.path.join(root, 'kai/ledger/api-usage.jsonl')) as f:
        records = [json.loads(l) for l in f if l.strip()]

    scrape_date = scraped['scraped_at'][:10]
    spend_ant = sum(float(r['cost_usd']) for r in records
                    if r.get('provider') == 'anthropic' and r.get('date','') >= scrape_date)
    spend_oai = sum(float(r['cost_usd']) for r in records
                    if r.get('provider') == 'openai' and r.get('date','') >= scrape_date)
    today_total = sum(float(r['cost_usd']) for r in records if r.get('date','') == today)

    state['credits'] = {
        'anthropic': {
            'remaining': round(scraped['anthropic']['remaining'] - spend_ant, 4),
            'total': scraped['anthropic']['total'],
            'scraped_at': scraped['scraped_at'],
            'spend_since_scrape': round(spend_ant, 4),
        },
        'openai': {
            'remaining': round(scraped['openai']['remaining'] - spend_oai, 4),
            'total': scraped['openai']['total'],
            'scraped_at': scraped['scraped_at'],
            'spend_since_scrape': round(spend_oai, 4),
        },
        'today_spend': round(today_total, 4),
        'source': 'scraped-credits.json + api-usage.jsonl',
    }
except Exception as e:
    state['credits'] = {'error': str(e)}

# ── 2. SICQ scores (from sicq-latest.json — written by flywheel-doctor) ─────
try:
    with open(os.path.join(root, 'kai/ledger/sicq-latest.json')) as f:
        sicq_data = json.load(f)
    scores = sicq_data.get('scores', {})
    below_min = {a: s for a, s in scores.items() if s <= 60}
    critical = {a: s for a, s in scores.items() if s <= 40}
    state['sicq'] = {
        'scores': scores,
        'below_minimum': below_min,
        'critical': critical,
        'system_healthy': len(critical) == 0,
        'computed_date': sicq_data.get('today'),
        'source': 'kai/ledger/sicq-latest.json',
    }
except Exception as e:
    state['sicq'] = {'error': str(e)}

# ── 3. OMP scores (from omp-summary.json) ────────────────────────────────────
try:
    with open(os.path.join(root, 'kai/ledger/omp-summary.json')) as f:
        omp_data = json.load(f)
    omp_scores = {a: int(d.get('overall', 0)) for a, d in omp_data.get('agents', {}).items()}
    state['omp'] = {
        'scores': omp_scores,
        'below_minimum': {a: s for a, s in omp_scores.items() if s < 70},
        'source': 'kai/ledger/omp-summary.json',
    }
except Exception as e:
    state['omp'] = {'error': str(e)}

# ── 4. Report freshness (which reports exist for today) ──────────────────────
try:
    feed_path = os.path.join(root, 'agents/sam/website/data/feed.json')
    with open(feed_path) as f:
        feed = json.load(f)
    reports = feed.get('reports', [])
    today_types = {r.get('type') for r in reports if r.get('date') == today}
    required = {'morning-report', 'nel-daily', 'sam-daily', 'ra-daily', 'aether-daily'}
    state['report_freshness'] = {
        'published_today': sorted(today_types),
        'missing_today': sorted(required - today_types),
        'complete': len(required - today_types) == 0,
        'source': 'agents/sam/website/data/feed.json',
    }
except Exception as e:
    state['report_freshness'] = {'error': str(e)}

# ── 5. Stale ACTIVE.md tickets (>72h open without resolution) ────────────────
stale_tickets = []
agents_to_check = ['nel', 'sam', 'ra', 'aether', 'dex']
kai_active = os.path.join(root, 'kai/ledger/ACTIVE.md')
active_paths = (
    [(a, os.path.join(root, f'agents/{a}/ledger/ACTIVE.md')) for a in agents_to_check] +
    [('kai', kai_active)]
)
now_epoch = datetime.now(timezone.utc).timestamp()
for agent, path in active_paths:
    if not os.path.exists(path): continue
    with open(path) as f:
        content = f.read()
    blocks = re.split(r'\n(?=- \*\*)', content)
    for block in blocks:
        id_m = re.search(r'\*\*(\S+)\*\*', block)
        if not id_m: continue
        if re.search(r'Status:\s*(CLOSED|RESOLVED|COMPLETED)', block, re.I): continue
        timestamps = re.findall(r'(?:Delegated|Created)[:\s]+(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z?)', block)
        if not timestamps: continue
        try:
            dt = datetime.fromisoformat(min(timestamps).replace('Z', '+00:00'))
            age_h = (now_epoch - dt.timestamp()) / 3600
            if age_h > 72:
                stale_tickets.append({'agent': agent, 'ticket': id_m.group(1), 'age_h': round(age_h,1)})
        except Exception:
            pass
state['stale_tickets'] = {
    'count': len(stale_tickets),
    'tickets': stale_tickets,
    'source': 'agents/*/ledger/ACTIVE.md',
}

# ── 6. Open P0/P1 tickets from tickets.jsonl ─────────────────────────────────
try:
    tickets_path = os.path.join(root, 'kai/tickets/tickets.jsonl')
    open_p0 = []; open_p1 = []
    with open(tickets_path) as f:
        for line in f:
            if not line.strip(): continue
            t = json.loads(line)
            if t.get('status') in ('CLOSED','RESOLVED','ARCHIVED'): continue
            p = t.get('priority','')
            if p == 'P0': open_p0.append({'id': t.get('id'), 'title': t.get('title','')[:80]})
            elif p == 'P1': open_p1.append({'id': t.get('id'), 'title': t.get('title','')[:80]})
    state['open_tickets'] = {
        'p0': open_p0, 'p1_count': len(open_p1),
        'p1_sample': open_p1[:5],
        'source': 'kai/tickets/tickets.jsonl',
    }
except Exception as e:
    state['open_tickets'] = {'error': str(e)}

# ── 7. Aether last analysis balance (verified from analysis file) ─────────────
try:
    analysis_path = os.path.join(root, f'agents/aether/analysis/Analysis_{today}.txt')
    if not os.path.exists(analysis_path):
        state['aether_balance'] = {'status': 'no_analysis_today'}
    else:
        with open(analysis_path) as f:
            text = f.read()
        opening = closing = None
        for line in text.split('\n'):
            cells = [c.strip() for c in line.split('|') if c.strip()]
            if len(cells) >= 3:
                try:
                    o = float(re.search(r'\$([0-9]+\.[0-9]+)', cells[1]).group(1))
                    c = float(re.search(r'\$([0-9]+\.[0-9]+)', cells[2]).group(1))
                    if 50 < o < 500 and 50 < c < 500:
                        opening = o; closing = c; break
                except Exception: pass
        subtotals = [float(m.group(1) + m.group(2))
                     for line in text.split('\n')
                     for m in [re.search(r'[Ss]ubtotal[:\s]+([+-])\$([0-9]+\.[0-9]+)', line)]
                     if m]
        trade_sum = round(sum(subtotals), 4) if subtotals else None
        balance_delta = round(closing - opening, 4) if opening and closing else None
        gap = round(abs(trade_sum - balance_delta), 4) if trade_sum is not None and balance_delta is not None else None
        state['aether_balance'] = {
            'opening': opening, 'closing': closing,
            'balance_delta': balance_delta,
            'trade_pnl_sum': trade_sum,
            'reconciliation_gap': gap,
            'reconciled': gap is not None and gap <= 0.10,
            'source': f'agents/aether/analysis/Analysis_{today}.txt',
        }
except Exception as e:
    state['aether_balance'] = {'error': str(e)}

with open(out_path, 'w') as f:
    json.dump(state, f, indent=2)
print(f"verified-state.json written: {out_path}")
for k, v in state.items():
    if isinstance(v, dict) and 'error' not in v:
        print(f"  {k}: OK")
    elif isinstance(v, dict) and 'error' in v:
        print(f"  {k}: ERROR — {v['error']}")
PYEOF

# ── Write session-handoff.json (automated, no prompting required) ─────────────
# This replaces the manual session-close step for handoff purposes.
# The handoff is computed entirely from existing files — no human input needed.
# session-close.sh still handles daily note, commit queue, and verification.
# The handoff runs every 15 min so every session starts with fresh continuity data.

HANDOFF="$ROOT/kai/ledger/session-handoff.json"
TASKS="$ROOT/KAI_TASKS.md"

python3 - "$ROOT" "$NOW_MT" "$TODAY" "$HANDOFF" "$TASKS" << 'PYEOF'
import json, sys, os, re, glob
from datetime import datetime, timezone

root, ts, today, handoff_path, tasks_path = sys.argv[1:6]

# Top priority: read from KAI_TASKS.md ★ NEXT SESSION block
top_priority = "See KAI_TASKS.md ★ block"
try:
    with open(tasks_path) as f:
        content = f.read()
    # Find the ★ block
    m = re.search(r'★.*?NEXT SESSION.*?\n(.*?)(?=\n★|\n##|\Z)', content, re.DOTALL | re.IGNORECASE)
    if m:
        lines = [l.strip() for l in m.group(1).split('\n') if l.strip() and not l.strip().startswith('#')]
        if lines:
            top_priority = lines[0].lstrip('- *').strip()[:200]
except Exception:
    pass

# What shipped: last 5 meaningful commits (exclude autonomous script commits)
shipped = []
try:
    import subprocess
    result = subprocess.run(
        ['git', '-C', root, 'log', '--oneline', '-20', '--no-merges'],
        capture_output=True, text=True, timeout=10
    )
    for line in result.stdout.strip().split('\n'):
        msg = line[8:].strip()  # skip hash
        # Skip autonomous/housekeeping commits
        if any(skip in msg.lower() for skip in ['aether: metrics', 'newsletter: publish', 'ant: daily', 'nel-qa:']):
            continue
        shipped.append(msg)
        if len(shipped) >= 5:
            break
except Exception:
    shipped = ["See git log"]

# Open P0s from tickets
open_p0s = []
try:
    tickets_path = os.path.join(root, 'kai/tickets/tickets.jsonl')
    with open(tickets_path) as f:
        for line in f:
            if not line.strip(): continue
            t = json.loads(line)
            if t.get('priority') == 'P0' and t.get('status') not in ('CLOSED','RESOLVED','ARCHIVED'):
                open_p0s.append(t.get('id','?') + ': ' + t.get('title','')[:80])
except Exception:
    pass

# Hyo-pending actions (from KAI_TASKS [H] markers)
hyo_pending = []
try:
    items = re.findall(r'- \[ \] \*\*\[H\]\*\* \*\*(.*?)\*\*', content)
    hyo_pending = [i.strip() for i in items[:5]]
except Exception:
    pass

# Queued commits
queued = [os.path.basename(p) for p in glob.glob(os.path.join(root, 'kai/queue/pending/*.json'))]

# Memory freshness
freshness = {}
for label, path in [
    ('kai_brief', 'KAI_BRIEF.md'),
    ('kai_tasks', 'KAI_TASKS.md'),
    ('knowledge', 'kai/memory/KNOWLEDGE.md'),
    ('tacit', 'kai/memory/TACIT.md'),
]:
    full = os.path.join(root, path)
    if os.path.exists(full):
        mtime = datetime.fromtimestamp(os.path.getmtime(full)).strftime('%Y-%m-%dT%H:%M:%S')
        freshness[label] = mtime
    else:
        freshness[label] = 'missing'

handoff = {
    "session_id": f"auto-{today}",
    "ended_at": ts,
    "written_by": "kai-session-prep.sh (automated — no prompting required)",
    "top_priority": top_priority,
    "shipped_this_session": shipped,
    "open_p0s": open_p0s,
    "hyo_actions_pending": hyo_pending,
    "commits_queued": queued,
    "commits_to_verify": ["Run: git log --oneline -8"],
    "memory_freshness": freshness,
    "prep_failures": [],
    "continuity_protocol": "kai/protocols/SESSION_CONTINUITY_PROTOCOL.md",
    "notes": "Auto-written every 15min by kai-session-prep.sh. No manual session-close required for continuity."
}

with open(handoff_path, 'w') as f:
    json.dump(handoff, f, indent=2)
print(f"session-handoff.json auto-written: top_priority={top_priority[:60]}")
PYEOF
