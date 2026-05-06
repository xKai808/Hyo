# Lab: AgentFloor: Small-Model Routing in Agent Pipelines

## First seen
2026-05-05 · Ra brief

## What it is
A benchmark that maps which parts of an agent workflow actually require frontier intelligence vs. small models

## Why it's interesting
Organizes 30 tasks into a six-tier capability ladder; small open-weight models reliably handle tiers 1–3, making a model router justified by data rather than intuition

## When we'd reach for it
Any time you're building a multi-step agent pipeline and want to reduce cost without sacrificing quality — route routine calls (parsing, lookup, formatting) to small models; escalate only for tier 5–6 reasoning

## Limitations
*(to be filled as we learn more)*

## References
- [Brief 2026-05-05](../../../newsletters/2026-05-05.md)
- [Source](https://arxiv.org/abs/2605.00334)

## Related

## Update 2026-05-05
**Brief:** [2026-05-05](../../../newsletters/2026-05-05.md)
- **What:** A 30-task benchmark organized as a six-tier capability ladder showing which agentic tasks actually require large frontier models versus small open-weight ones
- **Why:** Most production agent calls are short, structured, and routine — the benchmark quantifies how far down you can route without losing quality, mapping directly to cost and latency
- **When:** Designing multi-model agent pipelines where you want to minimize frontier model calls without degrading output quality; any agent system where cost-per-call matters
- **Source:** https://arxiv.org/abs/2605.00334
