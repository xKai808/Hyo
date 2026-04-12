#!/usr/bin/env python3
"""Pre-deploy validation for hyo.world.

Checks run before any git push or Vercel deploy:
1. hq-state.json doc links resolve to real .md files
2. All JS getElementById() calls have matching HTML id attributes
3. No dead onclick handlers (viewDoc/runAgent function calls without definitions)
4. Timestamps use Mountain Time offset (-06:00 or -07:00), not UTC (Z)
5. No orphaned data-view references (sidebar nav → view div mismatch)

Exit 0 = clean, exit 1 = failures found.
"""

import json
import os
import re
import sys

ROOT = os.environ.get("HYO_ROOT", os.path.join(os.path.expanduser("~"), "Documents", "Projects", "Hyo"))
WEBSITE = os.path.join(ROOT, "website")
HQ_HTML = os.path.join(WEBSITE, "hq.html")
HQ_STATE = os.path.join(WEBSITE, "data", "hq-state.json")
RESEARCH_HTML = os.path.join(WEBSITE, "research.html")

errors = []
warnings = []


def check_hq_state_doc_links():
    """Verify every doc link in hq-state.json resolves to a real .md file."""
    if not os.path.exists(HQ_STATE):
        warnings.append("hq-state.json not found — skipping doc link check")
        return

    with open(HQ_STATE) as f:
        state = json.load(f)

    docs_dir = os.path.join(WEBSITE, "docs")

    # Check events
    for event in state.get("events", []):
        doc = event.get("doc")
        if not doc:
            continue
        # Parse /viewer?agent=X&file=Y → docs/X/Y.md
        m = re.match(r"/viewer\?agent=(\w+)&file=([\w-]+)", doc)
        if m:
            agent, file_id = m.groups()
            md_path = os.path.join(docs_dir, agent, f"{file_id}.md")
            if not os.path.exists(md_path):
                errors.append(f"Dead doc link in hq-state.json event: {doc} → {md_path} not found")

    # Check agent sections with latestDoc
    for agent_key in ["ra", "sentinel", "sim", "cipher", "nel"]:
        section = state.get(agent_key, {})
        doc = section.get("latestDoc")
        if not doc:
            continue
        m = re.match(r"/viewer\?agent=(\w+)&file=([\w-]+)", doc)
        if m:
            agent, file_id = m.groups()
            md_path = os.path.join(docs_dir, agent, f"{file_id}.md")
            if not os.path.exists(md_path):
                errors.append(f"Dead doc link in hq-state.json [{agent_key}].latestDoc: {doc} → {md_path} not found")


def check_html_id_consistency(html_path, label):
    """Verify getElementById() calls match existing HTML id attributes."""
    if not os.path.exists(html_path):
        return

    with open(html_path) as f:
        content = f.read()

    # Extract all getElementById('xxx') calls
    js_ids = set(re.findall(r"getElementById\(['\"]([^'\"]+)['\"]\)", content))

    # Extract all id="xxx" attributes
    html_ids = set(re.findall(r'\bid=["\']([^"\']+)["\']', content))

    # Find orphans
    orphans = js_ids - html_ids
    for oid in sorted(orphans):
        # Skip if it's in a comment
        comment_pattern = rf"//.*getElementById\(['\"]" + re.escape(oid) + r"['\"]"
        if re.search(comment_pattern, content):
            continue
        errors.append(f"[{label}] getElementById('{oid}') has no matching HTML element")


def check_dead_function_calls(html_path, label):
    """Check for onclick handlers calling undefined functions."""
    if not os.path.exists(html_path):
        return

    with open(html_path) as f:
        content = f.read()

    # Find all onclick="functionName(...)" calls
    onclick_calls = set(re.findall(r'onclick=["\'](\w+)\(', content))

    # Find all function definitions
    func_defs = set(re.findall(r'function\s+(\w+)\s*\(', content))
    # Also check const/let/var assignments
    func_defs.update(re.findall(r'(?:const|let|var)\s+(\w+)\s*=\s*(?:function|\()', content))

    dead = onclick_calls - func_defs
    for fn in sorted(dead):
        errors.append(f"[{label}] onclick calls {fn}() but function is not defined")


def check_utc_timestamps():
    """Verify hq-state.json timestamps use Mountain Time, not UTC."""
    if not os.path.exists(HQ_STATE):
        return

    with open(HQ_STATE) as f:
        content = f.read()

    utc_stamps = re.findall(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', content)
    if utc_stamps:
        errors.append(f"hq-state.json has {len(utc_stamps)} UTC timestamp(s) — must use Mountain Time (-06:00 or -07:00)")
        for ts in utc_stamps[:3]:
            errors.append(f"  → {ts}")


def check_data_view_consistency():
    """Verify sidebar data-view attributes match view div ids."""
    if not os.path.exists(HQ_HTML):
        return

    with open(HQ_HTML) as f:
        content = f.read()

    # data-view="xxx" in nav items
    nav_views = set(re.findall(r'data-view=["\']([^"\']+)["\']', content))

    # id="v-xxx" view divs
    view_divs = set()
    for m in re.findall(r'\bid=["\']v-([^"\']+)["\']', content):
        view_divs.add(m)

    missing = nav_views - view_divs
    for v in sorted(missing):
        errors.append(f"Sidebar nav data-view='{v}' has no matching <div id='v-{v}'>")


def main():
    print("━━━ Pre-deploy validation ━━━\n")

    checks = [
        ("Doc link resolution", check_hq_state_doc_links),
        ("HTML ID consistency (hq.html)", lambda: check_html_id_consistency(HQ_HTML, "hq.html")),
        ("HTML ID consistency (research.html)", lambda: check_html_id_consistency(RESEARCH_HTML, "research.html")),
        ("Dead onclick handlers (hq.html)", lambda: check_dead_function_calls(HQ_HTML, "hq.html")),
        ("UTC timestamp check", check_utc_timestamps),
        ("Sidebar ↔ view consistency", check_data_view_consistency),
    ]

    for name, fn in checks:
        before = len(errors)
        fn()
        after = len(errors)
        status = "✓" if after == before else f"✗ ({after - before} issues)"
        print(f"  {status}  {name}")

    print()
    if warnings:
        for w in warnings:
            print(f"  ⚠  {w}")

    if errors:
        print(f"\n  ✗ {len(errors)} error(s) found — deploy blocked\n")
        for e in errors:
            print(f"    • {e}")
        print()
        return 1
    else:
        print("  ✓ All checks passed — safe to deploy\n")
        return 0


if __name__ == "__main__":
    sys.exit(main())
