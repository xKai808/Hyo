# Lab: AgentFloor: Routing Agent Tasks to Right-Sized Models

## First seen
2026-05-05 · Ra brief

## What it is
A 30-task benchmark that identifies which parts of agent workflows actually require frontier models vs. smaller open-weight models

## Why it's interesting
Most agent calls are routine and structured; small models handle the lower tiers reliably, frontier models only needed at the top

## When we'd reach for it
When optimizing agent pipeline cost and latency — route simple structured steps to small models, reserve frontier inference for genuine reasoning steps

## Limitations
*(to be filled as we learn more)*

## References
- [Brief 2026-05-05](../../../newsletters/2026-05-05.md)
- [Source](https://arxiv.org/abs/2605.00334)

## Related

