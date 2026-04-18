# hyo Agent — PRIORITIES.md
**Updated:** 2026-04-18

---

## P0 — This Week

1. **Complete surface audit of all 7 main pages** — index, aurora, hq, app, aurora-page, marketplace, register. Document issues in ACTIVE.md.
2. **Aurora-page audio player testing** — verify the podcast audio card renders correctly and displays on mobile.
3. **app.html mobile review** — just shipped today. Verify 375px viewport renders correctly.

---

## P1 — This Month

1. **IMP-HYO-001: Deploy-time layout baseline** — after any deploy, auto-check that above-fold elements are present on key pages.
2. **HQ mobile nav usability** — the bottom nav bar was added in session 13. Verify it doesn't overlap content on various screen sizes.
3. **Aurora landing page copywriting** — based on RESEARCH-001+002 findings, update copy to address the "I could build this myself" objection. Reference Jason Borck LAB-001.
4. **Email template design** — the magic link email (aurora-magic-link.js) uses inline HTML. Needs mobile testing at 375px.

---

## Research Mandate

Each cycle, hyo investigates one external design/UX question:
- What are the best practices for AI product onboarding in 2026?
- What makes newsletter apps "sticky" on mobile? (Morning Brew, Readless, Apple News)
- What dark-mode design patterns perform best for daily reading?
- How do top PWAs handle offline state gracefully?

---

## Carryover from Session Backlog

- LAB-001: Aurora landing page positioning update ("built for you, not by you" angle)
- DEPLOY-002: Change Vercel root dir from `website/` to `agents/sam/website/` (unblocks symlink)
- Podcast player accessibility: add `aria-label` to audio element
