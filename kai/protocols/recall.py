#!/usr/bin/env python3
"""
kai/protocols/recall.py — Resolution recall system

Searches past resolution reports for relevant prior art.
Used by all agents at STEP 0 of the Resolution Algorithm.

Usage:
    python3 kai/protocols/recall.py "morning report"
    python3 kai/protocols/recall.py --class "rendered-output-gap"
    python3 kai/protocols/recall.py --recent 5
    python3 kai/protocols/recall.py --agent nel
    python3 kai/protocols/recall.py --all
"""

import os
import sys
import glob
import json
import re
from datetime import datetime

ROOT = os.environ.get("HYO_ROOT", os.path.expanduser("~/Documents/Projects/Hyo"))
RESOLUTIONS_DIR = os.path.join(ROOT, "kai", "ledger", "resolutions")
KNOWN_ISSUES = os.path.join(ROOT, "kai", "ledger", "known-issues.jsonl")


def load_resolutions():
    """Load all resolution reports."""
    reports = []
    for path in sorted(glob.glob(os.path.join(RESOLUTIONS_DIR, "RES-*.md"))):
        with open(path) as f:
            content = f.read()
        # Extract metadata from the report
        report = {
            "path": path,
            "filename": os.path.basename(path),
            "content": content,
            "id": os.path.basename(path).replace(".md", ""),
        }
        # Extract tags if present
        tags_match = re.search(r"Tags:\s*(.+)", content)
        if tags_match:
            report["tags"] = [t.strip().lower() for t in tags_match.group(1).split(",")]
        else:
            report["tags"] = []

        # Extract class of failure
        class_match = re.search(r"Class of failure:\s*(.+)", content)
        if class_match:
            report["class"] = class_match.group(1).strip().lower()
        else:
            report["class"] = ""

        # Extract date
        date_match = re.search(r"Date:\s*(.+)", content)
        if date_match:
            report["date"] = date_match.group(1).strip()
        else:
            report["date"] = ""

        reports.append(report)
    return reports


def search_keyword(reports, keyword):
    """Search reports by keyword in content, tags, and class."""
    keyword_lower = keyword.lower()
    results = []
    for r in reports:
        score = 0
        if keyword_lower in r["content"].lower():
            score += 1
        if any(keyword_lower in tag for tag in r["tags"]):
            score += 3  # Tag matches are high signal
        if keyword_lower in r["class"]:
            score += 5  # Class matches are highest signal
        if score > 0:
            r["score"] = score
            results.append(r)
    return sorted(results, key=lambda x: x["score"], reverse=True)


def search_class(reports, failure_class):
    """Search reports by class of failure."""
    return [r for r in reports if failure_class.lower() in r["class"]]


def search_agent(reports, agent):
    """Search reports mentioning a specific agent."""
    return [r for r in reports if agent.lower() in r["content"].lower()]


def get_recent(reports, n=5):
    """Get the N most recent reports."""
    return reports[-n:] if len(reports) >= n else reports


def search_known_issues(keyword):
    """Search known-issues.jsonl for related patterns."""
    if not os.path.exists(KNOWN_ISSUES):
        return []
    results = []
    keyword_lower = keyword.lower()
    with open(KNOWN_ISSUES) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                desc = entry.get("description", "").lower()
                pattern = entry.get("pattern", "").lower()
                if keyword_lower in desc or keyword_lower in pattern:
                    results.append(entry)
            except json.JSONDecodeError:
                continue
    return results


def format_result(report, verbose=False):
    """Format a resolution for display."""
    lines = [f"\n{'='*60}"]
    lines.append(f"  {report['id']}  |  {report['date']}")
    if report["class"]:
        lines.append(f"  Class: {report['class']}")
    if report["tags"]:
        lines.append(f"  Tags: {', '.join(report['tags'])}")
    if verbose:
        # Show first 20 lines of content
        content_lines = report["content"].split("\n")[:20]
        lines.append("  ---")
        for cl in content_lines:
            lines.append(f"  {cl}")
        if len(report["content"].split("\n")) > 20:
            lines.append(f"  ... ({len(report['content'].split(chr(10)))} total lines)")
    lines.append(f"  File: {report['path']}")
    return "\n".join(lines)


def main():
    reports = load_resolutions()

    if len(sys.argv) < 2:
        print(f"Resolution recall system")
        print(f"Found {len(reports)} resolution reports in {RESOLUTIONS_DIR}")
        print(f"\nUsage:")
        print(f"  python3 {sys.argv[0]} 'keyword'        # search by keyword")
        print(f"  python3 {sys.argv[0]} --class 'name'    # search by failure class")
        print(f"  python3 {sys.argv[0]} --recent N         # show N most recent")
        print(f"  python3 {sys.argv[0]} --agent name       # search by agent")
        print(f"  python3 {sys.argv[0]} --all              # list all")
        return

    if sys.argv[1] == "--recent":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
        results = get_recent(reports, n)
        print(f"Last {n} resolutions:")
        for r in results:
            print(format_result(r))

    elif sys.argv[1] == "--class":
        if len(sys.argv) < 3:
            print("Usage: --class <failure_class>")
            return
        results = search_class(reports, sys.argv[2])
        print(f"Resolutions for class '{sys.argv[2]}': {len(results)} found")
        for r in results:
            print(format_result(r, verbose=True))

    elif sys.argv[1] == "--agent":
        if len(sys.argv) < 3:
            print("Usage: --agent <agent_name>")
            return
        results = search_agent(reports, sys.argv[2])
        print(f"Resolutions involving '{sys.argv[2]}': {len(results)} found")
        for r in results:
            print(format_result(r))

    elif sys.argv[1] == "--all":
        print(f"All {len(reports)} resolutions:")
        for r in reports:
            print(format_result(r))

    else:
        keyword = " ".join(sys.argv[1:])
        results = search_keyword(reports, keyword)
        ki_results = search_known_issues(keyword)

        print(f"Recall for '{keyword}':")
        print(f"  Resolution reports: {len(results)} matches")
        print(f"  Known issues: {len(ki_results)} matches")

        if results:
            print(f"\n--- Resolution Reports ---")
            for r in results[:5]:  # Top 5
                print(format_result(r, verbose=True))

        if ki_results:
            print(f"\n--- Known Issues ---")
            for ki in ki_results[:5]:
                pattern = ki.get("pattern", ki.get("description", "?")[:60])
                severity = ki.get("severity", "?")
                status = ki.get("status", "?")
                print(f"  [{severity}] [{status}] {pattern}")

        if not results and not ki_results:
            print("  No prior art found. This may be a new class of failure.")


if __name__ == "__main__":
    main()
