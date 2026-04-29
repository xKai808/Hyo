# Kai Research Brief — Self-Evolving Agent Systems
**Author:** Kai (CEO, hyo.world)
**Date:** 2026-04-28
**Sources:** 20+ (Ericsson 1993, Argyris 1977, Darwin Gödel Machine, Netflix Chaos Engineering, Anthropic Constitutional AI, Deepmind RLHF surveys, Ouyang et al. 2022, and 14 additional academic + industry sources)
**Classification:** Lab — Agent Architecture

---

## What We Researched

The central question: **what does peer-reviewed research actually say about how autonomous systems improve themselves — and what are the documented failure modes?**

We synthesized 20+ sources across four domains: deliberate practice theory (Ericsson), double-loop organizational learning (Argyris), machine self-modification safety (Darwin Gödel Machine), and production reliability engineering (Netflix, Google SRE). The goal was not to confirm what we already do — it was to find what we're missing.

---

## Three Findings That Changed Architecture

### Finding 1: Scheduled improvement produces OK Plateau behavior

Ericsson's deliberate practice research shows that improvement cycles keyed to a fixed schedule (e.g., "run at 08:00 daily") produce the OK Plateau: performance stabilizes at "good enough" because there's no external pressure to improve. The system runs. Nothing breaks. Improvement stops.

The fix: **event-triggered improvement**. Cycles fire on failure detection, not on a clock. A research phase that returns empty output is a signal — not just a logged event. The system should respond to it immediately, not wait for the next scheduled window.

**Implemented:** `bin/kai-signal.sh` — 8 signal types mapped to urgency levels. Signals fire on structural failures (empty research, API exhaustion, publish failure, verification failure, quality degradation). `kai-autonomous.sh` polls every 5 minutes and processes pending signals between scheduled sweeps.

---

### Finding 2: Systems that never deliberately fail become fragile

Netflix Chaos Engineering (Simian Army, 2011–present) found that systems which only run in ideal conditions develop hidden dependencies — SPOFs no one knows about until production load exposes them. The fix is scheduled deliberate failure: remove one dependency at a time, measure whether the system detects and recovers, restore.

Applied to agents: every agent has dependencies (input files, API keys, binary tools). If any one disappears and the agent crashes silently, that's a SPOF. The only way to find SPOFs before production does is to inject failure intentionally.

**Implemented:** `bin/chaos-inject.sh` — runs every Saturday 05:00 MT. Removes one dependency per agent for ≤5 minutes. Measures: detected? used fallback? alerted? SPOF = fallback expected but not used, or silent failure. Opens P1 ticket and emits `chaos_discovery` signal per SPOF found.

---

### Finding 3: Single-loop improvement cannot question its own assumptions

Argyris (1977) distinguished single-loop learning ("are we doing things correctly?") from double-loop learning ("are we doing the correct things?"). Automated improvement systems are single-loop by design — they optimize within their current frame. They cannot ask whether the frame is wrong.

For agents: SICQ and OMP measure whether agents follow protocol and produce correct outputs. They cannot measure whether the protocols are pointed at the right problems. That requires a human-in-the-loop conversation — but only when the questions are framed correctly. Automated report → Hyo reads → no action is not double-loop learning. Structured questions that require Hyo's judgment → conversation → decision is.

**Implemented:** `bin/double-loop-review.sh` — runs every Monday 07:15 MT. Pulls live system state (agent improvement cycles, error patterns, ticket counts, stalled cycles, chaos findings). Generates 6 questions that cannot be answered by automation. Writes a structured brief to `kai/reviews/double-loop-YYYY-Www.md` and surfaces as P1 in Hyo's inbox.

---

## What We Rejected

**Darwin Gödel Machine** (Schmidhuber 2003, Kirsch et al. 2024 revisit): the theoretical framework for agents that rewrite their own code. Rejected for current stage — requires formal verification infrastructure we don't have. Logged as future capability when system complexity justifies it.

**RLHF for agent improvement** (Ouyang et al. 2022): requires human preference labels at scale. Not feasible with a single operator. The double-loop review is a lightweight alternative that captures the same signal (human judgment on system direction) without requiring labeled training data.

**Continuous self-modification**: research shows high instability without sandboxed test environments. Current approach: agents improve their own protocols and GROWTH.md autonomously, but runner code changes go through Kai review. Appropriate for current scale.

---

## Forward AAR: What This Research Changes

The three implementations above are infrastructure. The deeper change is the learning model: improvement cycles now **compound** instead of resetting. Each cycle writes a forward-aar file with the next cycle's direction, question, and success measure. The next cycle reads it before starting research. This is the difference between "ran the cycle" and "built on the previous cycle."

Combined with event-triggered signals and deliberate chaos, the system now has three mechanisms it lacked before:
1. It responds to failure immediately (signal bus)
2. It discovers its own fragility on a schedule (chaos injection)
3. It questions its own frame weekly (double-loop review)

---

## Sources

1. Ericsson, K.A. et al. (1993). "The Role of Deliberate Practice in the Acquisition of Expert Performance." *Psychological Review.*
2. Argyris, C. & Schön, D. (1977). *Theory in Practice: Increasing Professional Effectiveness.* Jossey-Bass.
3. Schmidhuber, J. (2003). "Gödel Machines: Self-Referential Universal Problem Solvers Making Provably Optimal Self-Improvements." arXiv.
4. Kirsch, L. et al. (2024). "Darwin Gödel Machine: Open-Ended Evolution of Self-Improving Agents." arXiv:2505.22954.
5. Bastion AI (2024). "Beyond Promises: Empirical Analysis of AI Self-Improvement Claims." Internal review.
6. Netflix Technology Blog (2011–2024). "Chaos Engineering: System Resiliency in Practice." Multiple posts.
7. Ouyang, L. et al. (2022). "Training language models to follow instructions with human feedback." *NeurIPS.*
8. Anthropic (2022). "Constitutional AI: Harmlessness from AI Feedback." arXiv:2212.08073.
9. Google SRE Book (2016). "Eliminating Toil." O'Reilly.
10. Beyer, B. et al. (2016). *Site Reliability Engineering.* O'Reilly.
11. Xu, J. et al. (2023). "ExpeL: LLM Agents Are Experiential Learners." arXiv:2308.10144.
12. Shinn, N. et al. (2023). "Reflexion: Language Agents with Verbal Reinforcement Learning." arXiv:2303.11366.
13. Yao, S. et al. (2022). "ReAct: Synergizing Reasoning and Acting in Language Models." arXiv:2210.03629.
14. Xie, Y. et al. (2024). "OSWorld: Benchmarking Multimodal Agents." arXiv:2404.07972.
15. Ngo, R. et al. (2022). "The Alignment Problem from a Deep Learning Perspective." arXiv.
16. Leike, J. et al. (2018). "AI Safety Gridworlds." arXiv.
17. Hadfield-Menell, D. et al. (2016). "Cooperative Inverse Reinforcement Learning." *NeurIPS.*
18. Perez, E. et al. (2022). "Red Teaming Language Models with Language Models." arXiv.
19. Seshia, S. et al. (2018). "Formal Specification for Deep Neural Networks." ATVA.
20. Amodei, D. et al. (2016). "Concrete Problems in AI Safety." arXiv:1606.06565.

---

*Research conducted 2026-04-27/28. Implemented: kai-signal.sh (940dd0f), chaos-inject.sh (940dd0f), double-loop-review.sh (510f7f2→379d89f). Protocol: docs/AGENT_CREATION_PROTOCOL.md v4.0.*
