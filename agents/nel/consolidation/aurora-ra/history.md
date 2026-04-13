# Aurora / Ra — Consolidation History

**Purpose:** Compounding nightly log of the newsletter product (Ra = internal CEO brief, Aurora = consumer-facing). Each entry builds on the last.

---

## 2026-04-12 — Foundation night

**What exists today:**
- **Ra v2** — narrative essay format (Story / Also Moving / The Lab / Worth Sitting With / Kai's Desk). One brief shipped: `newsletters/2026-04-11.md` (2,254 words)
- **Aurora Public v0** — consumer-facing sibling. Per-subscriber output tuned by topics/voice/depth/length. Full pipeline: `aurora_public.py` → `send_email.py`. Passed simulation 01 (5 synthetic subscribers, all 5 briefs generated, 0 errors)
- **Research archive** — `kai/research/` with entities, topics, lab items. `ra_archive.py` (post-render) + `ra_context.py` (pre-synth). Information compounds across briefs
- **PRN continuity** — archive is a resource, not an obligation. Most briefs stand alone
- **Intake page** — `hyo.world/aurora.html` with 30-topic taxonomy, voice/depth/length knobs, 240-char freetext
- **Subscribe endpoint** — `/api/aurora-subscribe.js` validates and logs (Vercel function logs, not persistent)

**System improvements since last consolidation:**
- First consolidation — baseline established
- Synthesis prompt rewritten twice based on Hyo feedback (less density, fewer forced analogies, more narrative)
- Voice knob proven strongest signal in sim 01 (5 distinct writer voices)
- PRN fix prevents forced callbacks to old material

**What's compounding:**
- Research archive grows with every brief → Ra gets smarter over time
- Subscriber intake page live → collecting interest signals
- Sim 01 data archived in `kai/logs/aurora-sim-2026-04-11/` for reproducibility

**What's degrading or stuck:**
- Ra runs from recovery script, not automated — needs launchd plist on Mini
- Aurora subscriber persistence is Vercel logs only (no replay to JSONL)
- Length knob undershoots on 6min (9% under) and 12min (15% under)
- gather.py still Ra-biased — consumer topics need more sources
- No SPF/DKIM/DMARC on hyo.world → can't send real emails yet

**Sentinel findings (Aurora/Ra):**
- `newsletters/2026-04-11.md` exists, 13,980 bytes ✓
- `newsletters/2026-04-11.html` exists, 13,939 bytes ✓
- Research archive index exists and is current ✓
- Cowork scheduled task `aurora-hyo-daily` cannot reach sources (sandbox blocks egress)

**Cipher findings (Aurora/Ra):**
- No secrets in `newsletter/` directory ✓
- No API keys in `newsletter/prompts/` ✓
- `subscribers.jsonl` contains no real PII (placeholder only) ✓











## 2026-04-12 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 1
**Research archive entries:** 0


## 2026-04-13 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 1
**Research archive entries:** 0
