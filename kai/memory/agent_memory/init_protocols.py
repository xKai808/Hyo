#!/usr/bin/env python3
"""
kai/memory/agent_memory/init_protocols.py
==========================================
One-time (and idempotent) initialization of the memory engine.
Run this after first setup or after adding new protocols.

Registers all known publication protocols in procedural memory so that:
- A cold-start agent can call get_protocol("aether-daily-analysis")
  and get the exact file path to read
- The system is self-describing — no external doc needed to find protocols
"""

import os
import sys
from pathlib import Path

ROOT = Path(os.environ.get("HYO_ROOT", Path.home() / "Documents/Projects/Hyo"))
sys.path.insert(0, str(ROOT))

from kai.memory.agent_memory.memory_engine import init_db, register_protocol, observe_hyo

def main():
    conn = init_db()
    print(f"Memory DB initialized at {ROOT}/kai/memory/agent_memory/memory.db")

    # ── Register all publication protocols ──────────────────────────────────
    protocols = [
        {
            "name": "aether-daily-analysis",
            "file": "agents/aether/PROTOCOL_DAILY_ANALYSIS.md",
            "version": "1.0",
            "summary": "AetherBot daily analysis: log selection → Claude primary analysis → GPT adversarial cross-check → Claude synthesis → HQ feed publish. Self-contained for 3rd-party agent recovery."
        },
        {
            "name": "newsletter-daily",
            "file": "agents/ra/pipeline/PROTOCOL_NEWSLETTER.md",
            "version": "1.0",
            "summary": "Ra daily newsletter: topic research → content synthesis → HTML render → Vercel publish + email send. File: newsletter-YYYY-MM-DD.html"
        },
        {
            "name": "morning-report",
            "file": "bin/PROTOCOL_MORNING_REPORT.md",
            "version": "1.0",
            "summary": "Morning report: runs at 05:00 MT. Leads with agent growth/weaknesses, not operations. Pulls from all agent daily logs."
        },
        {
            "name": "nel-daily",
            "file": "agents/nel/PROTOCOL_DAILY.md",
            "version": "1.0",
            "summary": "Nel daily: security audit + QA scan + system health check. Published as nel-daily-YYYY-MM-DD."
        },
        {
            "name": "sam-daily",
            "file": "agents/sam/PROTOCOL_DAILY.md",
            "version": "1.0",
            "summary": "Sam daily: engineering work completed, Vercel deploy status, test results. Published as sam-daily-YYYY-MM-DD."
        },
        {
            "name": "kai-daily",
            "file": "kai/PROTOCOL_DAILY.md",
            "version": "1.0",
            "summary": "Kai CEO report: decisions made, work delegated, system changes, what Kai is tracking. Published as kai-daily-YYYY-MM-DD at 23:30 MT."
        },
    ]

    for p in protocols:
        file_path = ROOT / p["file"]
        register_protocol(p["name"], str(p["file"]), p["version"], p["summary"])
        exists = "✓" if file_path.exists() else "✗ MISSING"
        print(f"  [{exists}] {p['name']} → {p['file']}")

    # ── Seed critical semantic facts from KNOWLEDGE.md ──────────────────────
    # These are the facts that must survive even if KNOWLEDGE.md is unavailable
    from kai.memory.agent_memory.memory_engine import observe

    seed_facts = [
        ("Kai is the orchestrator, not the CEO. Hyo is the CEO and decision authority.", "instruction", "hyo"),
        ("AetherBot current deployed version: v253. Next build: v254. Never reuse version numbers.", "instruction", "hyo"),
        ("Correct Claude model strings: claude-opus-4-6, claude-sonnet-4-6, claude-haiku-4-5-20251001", "instruction", "hyo"),
        ("Stack must be model-agnostic. Never build on Anthropic Agent SDK or OpenAI Agents SDK.", "instruction", "hyo"),
        ("Timestamps: Mountain Time always. No UTC in user-facing output.", "instruction", "hyo"),
        ("Dual-path rule: any file in website/ must also be in agents/sam/website/", "instruction", "hyo"),
        ("Never give Hyo commands to copy/paste. Use kai/queue/exec.sh for all commands.", "instruction", "hyo"),
        ("AetherBot build requires Hyo's explicit 'approved' response before any build.", "instruction", "hyo"),
        ("Every commit must be followed by git push immediately. Committed ≠ done.", "instruction", "hyo"),
    ]

    print("\nSeeding critical semantic facts...")
    for content, etype, source in seed_facts:
        rid = observe(content, event_type=etype, source=source)
        status = f"stored (id={rid})" if rid else "already exists"
        print(f"  [{status}] {content[:60]}...")

    print(f"\nInit complete. Protocols registered: {len(protocols)}, Facts seeded: {len(seed_facts)}")
    conn.close()


if __name__ == "__main__":
    main()
