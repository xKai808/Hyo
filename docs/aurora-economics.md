# docs/aurora-economics.md

**Written:** 2026-04-10
**Status:** migration plan, not yet executed
**Bottom line:** Aurora can run for $0/mo incremental cost if we route synthesis through Claude Code's headless mode.

---

## The problem

Hyo is already paying for:
- **Claude Max**: $200/mo (includes Claude Code with generous usage allowance)
- **ChatGPT Plus**: $20/mo (chat only — does NOT include API credits; API is separate pay-as-you-go)
- **X Premium**: $8/mo (verification only — does NOT include API access, contrary to popular belief)

Adding a Grok API key on top of that is pure duplication. We already have a world-class LLM sitting right next to aurora on the Mini — Claude Code. Use that.

## The plan

### Phase 1: route synthesize.py through `claude -p` (no API key, no cost)

Claude Code supports headless mode via the `-p` flag. You hand it a prompt on stdin, it returns a response on stdout. Perfect for pipeline integration, used in CI/CD by thousands of orgs. Reference: [Claude Code headless docs](https://code.claude.com/docs/en/headless).

**New `synthesize.py` flow:**

```python
import subprocess
from pathlib import Path

def synthesize_via_claude_code(intelligence_jsonl: Path, prompt_template: Path) -> str:
    """Call Claude Code in headless mode. Zero API key required — uses the
    logged-in Claude Max session on the Mini."""
    with open(prompt_template) as f:
        prompt = f.read()
    with open(intelligence_jsonl) as f:
        signal = f.read()

    full_prompt = f"{prompt}\n\n<signal>\n{signal}\n</signal>\n\nReturn the brief as markdown."

    result = subprocess.run(
        ["claude", "-p", full_prompt,
         "--output-format", "text",
         "--allowedTools", "Read"],  # read-only, no side effects
        capture_output=True,
        text=True,
        timeout=300,
    )
    if result.returncode != 0:
        raise RuntimeError(f"claude -p failed: {result.stderr}")
    return result.stdout
```

**Backend priority order** (update `aurora.hyo.json` pipeline.stages.synthesize.backends):
1. `claude-code:headless` — default, free under Max subscription
2. `anthropic:claude-sonnet-4-6` — API fallback if Claude Code unavailable (uses Max API credits)
3. `bundle` — static fallback if everything fails

Remove Grok entirely. It was a nice-to-have; we no longer have a nice-to-have budget.

### Phase 2: use ChatGPT's API sparingly for specific sub-tasks

ChatGPT Plus ($20/mo) does not include API credits by default, but you can use the same account for API access via pay-as-you-go billing. For aurora specifically, there's no strong case to add GPT — Claude Sonnet 4.6 is better for the brief synthesis task. Keep GPT in reserve for:
- Cross-model validation in sentinel.hyo (run brief through both, flag disagreements)
- Translation or multi-lingual briefs if we ever expand
- Function calling flows that OpenAI's API does better

### Phase 3: monetize aurora to cover the fixed costs

The whole point of hyo.world is that agents pay their own way. Aurora's path:
- **Phase 3a — friends & family**: offer the brief to 5-10 operators Hyo knows. Free tier for feedback, $5-10/mo for daily delivery. Revenue goal: $50/mo to cover X Premium + 1/4 of ChatGPT.
- **Phase 3b — public listing**: once hyo.world has at least 3 agents and a working review system, publish aurora as a hireable agent. Hyo keeps 100% of revenue (founding tier, fees waived). Revenue goal: $300-500/mo covering Claude Max + all ancillaries.
- **Phase 3c — differentiation**: aurora's moat is the synthesis prompt + source selection + Hyo's taste, not the underlying LLM. Competitors can't replicate that cheaply.

## Migration steps (do these in order)

1. **Verify Claude Code is logged in on the Mini**: `which claude && claude --version`. If not, `claude login` and use Hyo's Anthropic account.
2. **Add `claude -p` path to synthesize.py**: new function, backend selector, keep bundle fallback intact.
3. **Update `aurora.hyo.json`** pipeline.stages.synthesize.backends list.
4. **Dry-run**: `kai news run` — confirm the output is good.
5. **Remove any `GROK_API_KEY` references** from `.env`, `.env.example`, README.md, and synthesize.py.
6. **Update `newsletter/README.md`** to reflect the new zero-cost architecture.
7. **Commit** with message "aurora: migrate synthesis to Claude Code headless, remove Grok dependency".

## Cost model — before vs after

| Line item | Before | After |
|-----------|--------|-------|
| Grok API | variable, est $10-50/mo | $0 |
| Claude Max (fixed) | $200/mo | $200/mo |
| ChatGPT Plus (fixed) | $20/mo | $20/mo |
| X Premium (fixed) | $8/mo | $8/mo |
| **Aurora incremental cost** | **$10-50/mo** | **$0** |

## What this doesn't fix

- Still paying $200/mo for Claude Max. That's the Hyo.world CEO platform — not negotiable.
- Still paying $20/mo for ChatGPT Plus. Keep for personal use + cross-model validation.
- X Premium at $8/mo is flagged for review (see `docs/x-api-access.md` — verification doesn't give API access; if Hyo isn't actively posting, consider cancelling).

## Risks

- **Claude Code session expiry**: headless calls need an active logged-in session. If the Mini reboots and no one logs in, the cron run fails. Mitigation: sentinel.hyo checks for a recent successful synthesize every morning and pings Hyo if missing.
- **Rate limits**: Claude Max has generous but not infinite limits. A single daily synthesis is trivial — but if we add multiple agents using Claude Code, we need to watch concurrent usage.
- **Output format drift**: headless mode returns raw text. We need deterministic markdown structure for render.py to work. Fix: strict prompt template + a post-processing validator in render.py.

## Sources

- [Claude Code headless mode documentation](https://code.claude.com/docs/en/headless) — the `-p` flag and automation patterns
- [Headless Mode and CI/CD - SFEIR Institute](https://institute.sfeir.com/en/claude-code/claude-code-headless-mode-and-ci-cd/faq/) — community guide
- [X API Pricing 2026 - xpoz.ai](https://www.xpoz.ai/blog/guides/understanding-twitter-api-pricing-tiers-and-alternatives/) — confirms verification ≠ API access
