# Entity: Marimo

**Slug:** `marimo`  
**Aliases:** Marimo, marimo notebook  
**Category:** tooling  
**Last enriched:** 2026-04-13T15:40:00-06:00

## Overview

On April 8, 2026, a critical pre-authentication remote code execution (RCE) vulnerability in Marimo—the reactive Python notebook framework favored by AI/ML researchers and data scientists—was publicly disclosed. Within 9 hours and 41 minutes, the first exploitation attempt appeared in the wild. Within 3 minutes of that, the attacker had pivoted from reconnaissance to credential theft on a compromised host.

CVE-2026-39987 (CVSS 9.3) exposed a fatal design flaw: the `/terminal/ws` WebSocket endpoint performs zero authentication validation before granting an interactive shell. All other WebSocket endpoints in Marimo correctly call `validate_auth()`. The terminal endpoint skips it entirely, checking only that the app is running and the platform supports it. An unauthenticated attacker with network access to a running Marimo instance can obtain a full PTY and execute arbitrary system commands.

The vulnerability matters not because of Marimo's market penetration (niche, but growing in research labs), but because it exposes the velocity of the software supply chain. Public disclosure to active exploitation in under 10 hours is the new normal. No public proof-of-concept existed. The attacker reverse-engineered the vulnerability from the advisory description alone and built a working exploit in real-time.

## Key Data Points

- **CVE Identifier:** CVE-2026-39987 (GHSA-2679-6mx9-h9xc)
- **CVSS Score:** 9.3 (critical)
- **Affected Versions:** Marimo ≤0.20.4 (all versions prior to fix)
- **Fixed Version:** 0.23.0
- **Vulnerability Class:** Pre-authenticated RCE via unauthenticated WebSocket
- **Time to Exploitation:** 9h 41m from disclosure to first wild attempt
- **Sophistication:** Custom exploit built from advisory text (no PoC code required)
- **Downstream Impact:** Marimo is embedded in research pipelines at AI labs, universities, and ML ops teams; potential supply chain risk for trained models, research data exfiltration

## Analysis

The Marimo CVE is less interesting as a specific vulnerability than as a symptom of infrastructure compression. The attack surface of modern AI/ML development has exploded: researchers use dozens of ephemeral tools (notebooks, package managers, API clients, container registries), each with its own auth/validation model. Marimo targets researchers, not enterprises; researchers typically run notebooks on shared research servers with minimal isolation. A researcher's compromised notebook = potential access to training datasets, proprietary model code, API keys, and research manuscripts pre-publication.

The attacker's operational pattern—from discovery to credential theft in under 10 minutes—suggests automated scanning. Multiple Marimo instances were likely probed simultaneously; the first 10 hours post-disclosure was a window for large-scale compromise before patching could propagate.

What makes this supply-chain relevant is the downstream chain: a compromised Marimo instance in a research lab could be used to exfiltrate training data, inject backdoors into models in development, or poison research codebases that get published to GitHub and then incorporated into other projects. The Cloud Security Alliance's STAR program has flagged AI development infrastructure compromise as a catastrophic risk precisely because of scenarios like this.

The real lesson: the industry cannot keep up with disclosure-to-patch velocity at the edge. Marimo maintainers fixed this in 0.23.0, but coordinated disclosure requires 60–90 days; vulnerabilities are being weaponized in hours.

## Outlook

**Immediate (next 72 hours):** Mass patching and automated scanning of exposed Marimo instances. Cloud hosting providers (AWS, GCP, Azure) will likely flag running Marimo instances with versions <0.23.0 as a security risk. Users with persistent notebooks in prod will race to update.

**Short-term (next 30 days):** Follow-on vulnerabilities in Marimo or similar research tools (Jupyter, JupyterLab, Pluto, Observable) will surface. The pressure on maintainers to secure WebSocket endpoints and adopt zero-trust auth will intensify. Public security audits of popular research notebooks will become table-stakes.

**Strategic (2026 onward):** Research organizations will begin isolating development infrastructure from production, enforcing signed/verified notebook distributions, and implementing network segmentation for researcher machines. The era of "research tools are toy tools" is ending.

The vulnerability is fixable. The velocity problem is systemic.

## Sources

- [Sysdig Threat Research: Marimo RCE Disclosure to Exploitation](https://webflow.sysdig.com/blog/marimo-oss-python-notebook-rce-from-disclosure-to-exploitation-under-10-hours)
- [The Hacker News: CVE-2026-39987 Marimo RCE](https://thehackernews.com/2026/04/marimo-rce-flaw-cve-2026-39987.html)
- [Cloud Security Alliance: AI Toolchain Attack Research](https://labs.cloudsecurityalliance.org/research/csa-research-note-marimo-rce-cve-2026-39987-ai-toolchain-202/)
- [SecurityWeek: Marimo Flaw Exploited Hours After Public Disclosure](https://www.securityweek.com/critical-marimo-flaw-exploited-hours-after-public-disclosure/)
- [BleepingComputer: Marimo Pre-Auth RCE Under Active Exploitation](https://www.bleepingcomputer.com/news/security/critical-marimo-pre-auth-rce-flaw-now-under-active-exploitation/)

---

## Timeline

### 2026-04-11
**Brief:** [2026-04-11](../../../newsletters/2026-04-11.md)

**Take:** Ten-hour CVE-to-exploit window is the new normal — software supply-chain velocity compressing hard

**Data:** RCE in Marimo Python notebook went from public disclosure to active exploit in under 10h

**Hinge:** Next zero-day to land on a popular dev tool will test whether the industry can keep up

**Confidence:** high
