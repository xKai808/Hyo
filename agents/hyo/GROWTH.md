# hyo Agent — GROWTH.md
**Created:** 2026-04-18 | **Review cycle:** Weekly

---

## Current Weaknesses

### W1: No Automated Visual Regression Detection
**What:** hyo audits pages manually by fetching HTML and checking patterns. There is no baseline screenshot or computed style comparison. Visual regressions (e.g., a CSS change breaking mobile layout) only get caught if hyo manually checks the right page at the right time.

**Evidence:** The deploy pipeline crash in session 15 (symlink conversion broke Vercel) went undetected for 5+ hours before Hyo noticed. A visual regression check at deploy time would have caught it immediately.

**What structural change would prevent this class of problem?**
→ After every deploy, fetch key pages and compare computed layout metrics (viewport width rendered content, font loading status, above-fold element presence) against a stored baseline.

**Improvement ticket:** IMP-HYO-001

---

### W2: No Mobile-First Audit Capability
**What:** hyo's audit phase runs in a headless/curl-based environment with no browser rendering. It can check HTML structure but cannot validate actual rendered output on mobile viewports (375px, 390px). Flexbox, CSS Grid, and media query behavior cannot be verified without render.

**Evidence:** The "fixed widths without responsive breakpoints" issue in HQ was only caught because Hyo reported it — hyo's audit would not have caught the rendered result.

**What structural change would prevent this class of problem?**
→ Integrate with a headless browser (Playwright or Puppeteer on Mini) to take viewport screenshots at 375px and 1440px. Compare against last-good screenshots.

**Improvement ticket:** IMP-HYO-002

---

### W3: No Design System Enforcement
**What:** The website has evolved across 15+ sessions. Design tokens (colors, spacing, typography) are partially defined in CSS custom properties but inconsistently applied. Some files use hardcoded hex values, some use var(), some use different naming conventions. hyo has no automated check to detect design drift.

**Evidence:** During session 11, the Aether dashboard used hardcoded terminal colors (#0d0d0d, #00ff88) until Hyo pointed out they didn't match the site's design. This could have been caught by an automated CSS audit.

**What structural change would prevent this class of problem?**
→ Build a CSS token scanner that runs on each deploy. Flag any hardcoded color values that should use CSS custom properties. Track a "design debt score" over time.

**Improvement ticket:** IMP-HYO-003

---

## Active Improvements

| ID | Weakness | Status | Target date |
|----|---------|--------|-------------|
| IMP-HYO-001 | Visual regression baseline | PLANNED | 2026-05-02 |
| IMP-HYO-002 | Mobile viewport audit | PLANNED | 2026-05-09 |
| IMP-HYO-003 | Design system enforcement | PLANNED | 2026-05-16 |

---

## Self-Set Goals

**30-day goal (by 2026-05-18):**
- IMP-HYO-001 shipped: post-deploy layout metrics baseline working
- Complete audit of all 7 main website pages (index, aurora, hq, app, aurora-page, marketplace, register)
- Zero mobile layout regressions in new deploys

**60-day goal (by 2026-06-18):**
- IMP-HYO-002 shipped: Playwright mobile screenshot comparison working
- Aurora-page subscriber experience scores ≥ 8/10 on perceived quality
- HQ dashboard mobile usability issues resolved (currently some overflow on small screens)

**90-day goal (by 2026-07-18):**
- Full design system audit complete — all hardcoded colors migrated to CSS vars
- Mobile Lighthouse score ≥ 90 for hyo.world, hyo.world/hq, hyo.world/aurora
- Visual regression catch rate: 100% (no deploy-time regressions go undetected)

---

## Growth Log

| Date | Weakness | Action | Result |
|------|---------|--------|--------|
| 2026-04-18 | All three | Documented weaknesses, created IMP tickets | Baseline established |
