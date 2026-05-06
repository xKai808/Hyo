# Lab: The Tool-Use Tax: When Adding Tools Hurts LLM Reasoning

## First seen
2026-05-05 · Ra brief

## What it is
Research showing tool-augmented LLMs don't consistently outperform native chain-of-thought reasoning, especially when queries semantically resemble tool-relevant questions but aren't

## Why it's interesting
Prompt formatting overhead plus tool-selection errors can cancel out the informational gain from calling the tool

## When we'd reach for it
Before wiring any agent step to an external tool — benchmark plain reasoning on that step first; tools add latency and failure modes that aren't always worth it

## Limitations
*(to be filled as we learn more)*

## References
- [Brief 2026-05-05](../../../newsletters/2026-05-05.md)
- [Source](https://arxiv.org/abs/2605.00136)

## Related

## Update 2026-05-05
**Brief:** [2026-05-05](../../../newsletters/2026-05-05.md)
- **What:** Research showing tool-augmented LLM agents don't always outperform plain chain-of-thought reasoning — especially when the input context is ambiguous
- **Why:** Identifies three real costs of tool use: prompt formatting overhead, sensitivity to misleading context, and the decision cost of whether to call the tool at all
- **When:** Evaluating whether a task actually benefits from tool use or whether a well-prompted model would be more reliable and cheaper; useful pre-architecture question for any agent feature
- **Source:** https://arxiv.org/abs/2605.00136
