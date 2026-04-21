#!/usr/bin/env python3
"""
agents/dex/dex-cluster.py — Dex W2: Pattern Clustering + Root-Cause Analysis

Dex W2 fix: Phase 4 counted 120 patterns but gave zero signal — no clustering,
no root-cause grouping, no temporal correlation. This script answers:
  - "Which 120 issues are actually 5 root causes?"
  - "Which agent generates the most issues?"
  - "Does issue X correlate temporally with issue Y?"
  - "What are the top 3 issues to fix right now?"

Shipped: 2026-04-21 | Protocol: agents/dex/GROWTH.md W2

WHAT IT DOES:
  1. Reads known-issues.jsonl + session-errors.jsonl
  2. Clusters entries by root cause using token-overlap similarity (no ML needed)
  3. Detects temporal patterns (same issue recurring at consistent intervals)
  4. Extracts agent breakdown (which agent owns most issues)
  5. Ranks clusters by impact (frequency × recency weight)
  6. Outputs machine-readable cluster-report.json + human-readable CLUSTER_REPORT.md

CLUSTERING ALGORITHM (deterministic, no dependencies):
  - Tokenize description → stem to lowercase words
  - Cluster by: Jaccard similarity of token sets > 0.4 threshold
  - Merge overlapping clusters transitively (union-find)
  - Label cluster by most common token set representative

USAGE:
  python3 agents/dex/dex-cluster.py            # cluster all known-issues
  python3 agents/dex/dex-cluster.py --dry-run  # report only, no write
  python3 agents/dex/dex-cluster.py --json     # machine-readable output
  python3 agents/dex/dex-cluster.py --top 10   # show top N clusters only

OUTPUT:
  agents/dex/ledger/cluster-report.json — machine-readable
  agents/dex/research/CLUSTER_REPORT.md — human-readable
"""

from __future__ import annotations
import argparse
import datetime
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", str(Path.home() / "Documents" / "Projects" / "Hyo")))
CLUSTER_OUT = ROOT / "agents" / "dex" / "ledger" / "cluster-report.json"
REPORT_OUT = ROOT / "agents" / "dex" / "research" / "CLUSTER_REPORT.md"

NOW = datetime.datetime.now(datetime.timezone.utc).isoformat()
TODAY = datetime.date.today()

# Source JSONL files to cluster
SOURCE_FILES = [
    ROOT / "kai" / "ledger" / "known-issues.jsonl",
    ROOT / "kai" / "ledger" / "session-errors.jsonl",
]

# Stop words for tokenization
STOP_WORDS = {
    "a", "an", "the", "and", "or", "but", "is", "are", "was", "were",
    "in", "on", "at", "for", "to", "of", "with", "by", "from", "not",
    "no", "be", "been", "has", "have", "had", "do", "does", "did",
    "this", "that", "it", "its", "as", "if", "then", "than", "so",
    "--", "—", "->", "→",
}

# Agent keywords for classification
AGENT_KEYWORDS = {
    "nel": ["nel", "nel-", "cipher", "sentinel", "security", "gitignore", "leak", "secret"],
    "ra": ["ra", "ra-", "newsletter", "email", "pipeline", "render", "smtp", "aurora"],
    "sam": ["sam", "sam-", "deploy", "vercel", "build", "api", "endpoint", "website"],
    "aether": ["aether", "aether-", "analysis", "trading", "kalshi", "position", "balance", "pnl"],
    "dex": ["dex", "dex-", "jsonl", "ledger", "repair", "cluster", "audit"],
    "kai": ["kai", "kai-", "session", "memory", "hydration", "context", "brief", "task"],
    "ant": ["ant", "ant-", "credit", "spend", "cost", "billing", "openai", "gpt"],
}


def tokenize(text: str) -> frozenset[str]:
    """Tokenize text into a set of lowercase meaningful tokens."""
    tokens = re.findall(r'[a-zA-Z][a-zA-Z0-9_/-]*', text.lower())
    return frozenset(t for t in tokens if t not in STOP_WORDS and len(t) > 2)


def jaccard(a: frozenset, b: frozenset) -> float:
    """Jaccard similarity between two token sets."""
    if not a and not b:
        return 1.0
    intersection = len(a & b)
    union = len(a | b)
    return intersection / union if union > 0 else 0.0


def classify_agent(text: str) -> str:
    """Classify which agent an issue belongs to."""
    text_lower = text.lower()
    scores = {}
    for agent, keywords in AGENT_KEYWORDS.items():
        score = sum(1 for kw in keywords if kw in text_lower)
        if score > 0:
            scores[agent] = score
    return max(scores, key=scores.get) if scores else "unknown"


def parse_ts(ts_str: str) -> datetime.datetime | None:
    """Parse ISO timestamp."""
    if not ts_str:
        return None
    try:
        return datetime.datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
    except ValueError:
        return None


def load_entries(files: list[Path]) -> list[dict]:
    """Load and normalize entries from JSONL files."""
    entries = []
    for path in files:
        if not path.exists():
            continue
        source = str(path.relative_to(ROOT))
        try:
            with open(path) as f:
                for i, line in enumerate(f, 1):
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        # Normalize fields
                        description = (
                            entry.get("description") or
                            entry.get("summary") or
                            entry.get("event") or
                            entry.get("message") or
                            ""
                        ).strip()
                        if not description:
                            continue
                        entries.append({
                            "source": source,
                            "line": i,
                            "ts": entry.get("ts") or entry.get("timestamp") or "",
                            "description": description,
                            "status": entry.get("status", "unknown"),
                            "severity": entry.get("severity", ""),
                            "agent": entry.get("agent") or classify_agent(description),
                            "tokens": tokenize(description),
                            "_raw": entry,
                        })
                    except json.JSONDecodeError:
                        pass
        except OSError:
            pass
    return entries


class UnionFind:
    """Simple union-find for cluster merging."""
    def __init__(self, n: int):
        self.parent = list(range(n))

    def find(self, x: int) -> int:
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x

    def union(self, x: int, y: int):
        px, py = self.find(x), self.find(y)
        if px != py:
            self.parent[px] = py


def cluster_entries(entries: list[dict], threshold: float = 0.4) -> list[list[int]]:
    """Cluster entries by Jaccard similarity. Returns list of clusters (each = list of indices)."""
    n = len(entries)
    uf = UnionFind(n)

    # O(n²) similarity pass — acceptable for <500 entries
    for i in range(n):
        for j in range(i + 1, n):
            sim = jaccard(entries[i]["tokens"], entries[j]["tokens"])
            if sim >= threshold:
                uf.union(i, j)

    # Group by cluster root
    clusters: dict[int, list[int]] = defaultdict(list)
    for i in range(n):
        clusters[uf.find(i)].append(i)

    return list(clusters.values())


def detect_temporal_patterns(entries: list[dict]) -> list[dict]:
    """Detect entries that recur at regular intervals."""
    patterns = []

    # Group by description similarity
    by_token_key: dict[frozenset, list[datetime.datetime]] = defaultdict(list)
    for e in entries:
        ts = parse_ts(e["ts"])
        if ts and e["tokens"]:
            # Use first 5 tokens as key
            key = frozenset(sorted(e["tokens"])[:5])
            by_token_key[key].append(ts)

    for key, timestamps in by_token_key.items():
        if len(timestamps) < 3:
            continue
        timestamps.sort()
        # Compute gaps between consecutive occurrences
        gaps = [(timestamps[i+1] - timestamps[i]).total_seconds()
                for i in range(len(timestamps)-1)]
        avg_gap = sum(gaps) / len(gaps)
        # Check if gaps are consistent (std dev < 20% of mean)
        variance = sum((g - avg_gap)**2 for g in gaps) / len(gaps)
        std_dev = variance ** 0.5
        consistency = 1 - (std_dev / avg_gap) if avg_gap > 0 else 0

        if consistency > 0.6 and avg_gap < 86400 * 7:  # <7 days between recurrences
            patterns.append({
                "tokens": list(key)[:5],
                "occurrences": len(timestamps),
                "avg_interval_hours": round(avg_gap / 3600, 1),
                "consistency_pct": round(consistency * 100, 1),
                "first_seen": timestamps[0].isoformat(),
                "last_seen": timestamps[-1].isoformat(),
            })

    return sorted(patterns, key=lambda x: -x["occurrences"])


def score_cluster(cluster_indices: list[int], entries: list[dict]) -> float:
    """Score a cluster by impact: frequency × recency weight."""
    now = datetime.datetime.now(datetime.timezone.utc)
    score = 0.0
    for i in cluster_indices:
        e = entries[i]
        ts = parse_ts(e["ts"])
        age_days = (now - ts).days if ts else 30
        recency_weight = max(0.1, 1.0 - age_days / 60)
        severity_weight = {"P0": 3.0, "P1": 2.0, "P2": 1.5, "": 1.0}.get(
            e.get("severity", ""), 1.0
        )
        score += recency_weight * severity_weight
    return round(score, 2)


def analyze(entries: list[dict], top: int) -> dict:
    """Full cluster analysis. Returns structured report."""

    # Cluster
    cluster_groups = cluster_entries(entries)

    # Build cluster metadata
    clusters = []
    for group in cluster_groups:
        members = [entries[i] for i in group]
        # Representative: entry with most tokens (richest description)
        rep = max(members, key=lambda e: len(e["tokens"]))
        # Agent breakdown within cluster
        agent_counts: dict[str, int] = defaultdict(int)
        for m in members:
            agent_counts[m["agent"]] += 1
        dominant_agent = max(agent_counts, key=agent_counts.get)

        # Status breakdown
        statuses: dict[str, int] = defaultdict(int)
        for m in members:
            statuses[m["status"]] += 1

        # Time range
        timestamps = [parse_ts(m["ts"]) for m in members if m["ts"]]
        timestamps = [t for t in timestamps if t]
        first_seen = min(timestamps).isoformat() if timestamps else None
        last_seen = max(timestamps).isoformat() if timestamps else None

        clusters.append({
            "size": len(group),
            "score": score_cluster(group, entries),
            "label": rep["description"][:100],
            "dominant_agent": dominant_agent,
            "agent_breakdown": dict(agent_counts),
            "status_breakdown": dict(statuses),
            "first_seen": first_seen,
            "last_seen": last_seen,
            "sources": list({m["source"] for m in members}),
            "member_descriptions": [m["description"][:80] for m in members[:5]],
        })

    # Sort by score descending
    clusters.sort(key=lambda c: -c["score"])

    # Agent breakdown across all entries
    agent_totals: dict[str, int] = defaultdict(int)
    for e in entries:
        agent_totals[e["agent"]] += 1

    # Status breakdown
    status_totals: dict[str, int] = defaultdict(int)
    for e in entries:
        status_totals[e.get("status", "unknown")] += 1

    # Temporal patterns
    temporal = detect_temporal_patterns(entries)

    # Dedup candidates: clusters with size > 1 where all members have same root cause
    dedup_candidates = [c for c in clusters if c["size"] > 1]

    return {
        "generated_at": NOW,
        "total_entries": len(entries),
        "total_clusters": len(clusters),
        "singleton_clusters": sum(1 for c in clusters if c["size"] == 1),
        "multi_entry_clusters": sum(1 for c in clusters if c["size"] > 1),
        "agent_breakdown": dict(sorted(agent_totals.items(), key=lambda x: -x[1])),
        "status_breakdown": dict(status_totals),
        "top_clusters": clusters[:top],
        "temporal_patterns": temporal[:10],
        "dedup_candidates": dedup_candidates[:20],
        "signal_summary": {
            "noise_reduction": f"{len(entries)} entries → {len(clusters)} clusters ({round((1 - len(clusters)/len(entries))*100, 1)}% dedup rate)" if entries else "no data",
            "top_agent": max(agent_totals, key=agent_totals.get) if agent_totals else "none",
            "largest_cluster_size": clusters[0]["size"] if clusters else 0,
            "recurring_patterns": len(temporal),
        },
    }


def render_markdown(data: dict) -> str:
    """Render human-readable cluster report."""
    lines = []
    sig = data["signal_summary"]

    lines.append("# Dex Pattern Cluster Report")
    lines.append(f"**Generated:** {data['generated_at'][:10]}")
    lines.append(f"**Total entries analyzed:** {data['total_entries']}")
    lines.append(f"**Noise reduction:** {sig['noise_reduction']}")
    lines.append("")

    lines.append("## Signal Summary")
    lines.append(f"- Multi-entry clusters: **{data['multi_entry_clusters']}** (same root cause, different timestamps)")
    lines.append(f"- Singleton clusters: **{data['singleton_clusters']}** (unique issues)")
    lines.append(f"- Recurring temporal patterns: **{sig['recurring_patterns']}**")
    lines.append(f"- Highest-volume agent: **{sig['top_agent']}**")
    lines.append(f"- Largest cluster: **{sig['largest_cluster_size']} entries** with same root cause")
    lines.append("")

    lines.append("## Agent Breakdown")
    lines.append("| Agent | Issues |")
    lines.append("|-------|--------|")
    for agent, count in sorted(data["agent_breakdown"].items(), key=lambda x: -x[1]):
        lines.append(f"| {agent} | {count} |")
    lines.append("")

    lines.append("## Top Issue Clusters (by impact score)")
    for i, c in enumerate(data["top_clusters"][:15], 1):
        open_count = c["status_breakdown"].get("open", c["status_breakdown"].get("active", 0))
        lines.append(f"\n### Cluster {i} — {c['label']}")
        lines.append(f"- **Size:** {c['size']} entries | **Score:** {c['score']} | **Agent:** {c['dominant_agent']}")
        if c["first_seen"] and c["last_seen"]:
            lines.append(f"- **Range:** {c['first_seen'][:10]} → {c['last_seen'][:10]}")
        lines.append(f"- **Status:** {c['status_breakdown']}")
        if len(c["member_descriptions"]) > 1:
            lines.append("- **Sample entries:**")
            for desc in c["member_descriptions"][:3]:
                lines.append(f"  - {desc}")

    if data["temporal_patterns"]:
        lines.append("\n## Temporal Patterns (recurring at consistent intervals)")
        lines.append("| Pattern | Occurrences | Avg Interval | Consistency | Last Seen |")
        lines.append("|---------|-------------|--------------|-------------|-----------|")
        for p in data["temporal_patterns"][:8]:
            label = " ".join(p["tokens"][:4])
            lines.append(
                f"| {label} | {p['occurrences']} | {p['avg_interval_hours']}h | "
                f"{p['consistency_pct']}% | {p['last_seen'][:10]} |"
            )

    lines.append("")
    lines.append("## Deduplication Candidates")
    lines.append("The following clusters contain multiple entries with the same root cause.")
    lines.append("Consider merging them into a single canonical issue:")
    for c in data["dedup_candidates"][:10]:
        lines.append(f"\n- **{c['label']}** ({c['size']} entries, {c['dominant_agent']})")
        for desc in c["member_descriptions"][:2]:
            lines.append(f"  - {desc}")

    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Dex pattern cluster analyzer")
    ap.add_argument("--dry-run", action="store_true", help="Report only, no file writes")
    ap.add_argument("--json", action="store_true", help="Output JSON summary")
    ap.add_argument("--top", type=int, default=20, help="Top N clusters to include (default: 20)")
    args = ap.parse_args()

    print(f"=== Dex Pattern Cluster — {TODAY} ===", file=sys.stderr)

    entries = load_entries(SOURCE_FILES)
    if not entries:
        print("No entries found in source files", file=sys.stderr)
        return 1

    print(f"  Loaded {len(entries)} entries from {len(SOURCE_FILES)} sources", file=sys.stderr)
    print(f"  Clustering (Jaccard threshold=0.4)...", file=sys.stderr)

    data = analyze(entries, args.top)

    sig = data["signal_summary"]
    print(f"  {sig['noise_reduction']}", file=sys.stderr)
    print(f"  Top agent: {sig['top_agent']} | Recurring patterns: {sig['recurring_patterns']}", file=sys.stderr)
    print(f"  Largest cluster: {sig['largest_cluster_size']} entries same root cause", file=sys.stderr)

    if not args.dry_run:
        CLUSTER_OUT.parent.mkdir(parents=True, exist_ok=True)
        REPORT_OUT.parent.mkdir(parents=True, exist_ok=True)
        with open(CLUSTER_OUT, "w") as f:
            json.dump(data, f, indent=2)
        md = render_markdown(data)
        with open(REPORT_OUT, "w") as f:
            f.write(md)
        print(f"  Written: {CLUSTER_OUT.relative_to(ROOT)}", file=sys.stderr)
        print(f"  Written: {REPORT_OUT.relative_to(ROOT)}", file=sys.stderr)

    if args.json:
        print(json.dumps(data, indent=2))

    return 0


if __name__ == "__main__":
    sys.exit(main())
