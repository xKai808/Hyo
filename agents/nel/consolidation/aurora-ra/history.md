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

## 2026-04-14 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 2
**Research archive entries:** 0

## 2026-04-15 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 4
**Research archive entries:** 0

## 2026-04-16 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 5
**Research archive entries:** 0

## 2026-04-18 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 8
**Research archive entries:** 0

## 2026-04-19 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 9
**Research archive entries:** 0

## 2026-04-20 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 10
**Research archive entries:** 0

## 2026-04-21 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 11
**Research archive entries:** 0

## 2026-04-22 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 12
**Research archive entries:** 0

## 2026-04-23 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 13
**Research archive entries:** 0

## 2026-04-24 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 14
**Research archive entries:** 0

## 2026-04-25 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 15
**Research archive entries:** 0

## 2026-04-26 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 17
**Research archive entries:** 0

## 2026-04-27 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 18
**Research archive entries:** 0

## 2026-04-28 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 19
**Research archive entries:** 25


## 2026-05-01 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 23
**Research archive entries:** 48

## 2026-05-05 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 25
**Research archive entries:** 48

## 2026-05-06 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 27
**Research archive entries:** 63

## 2026-05-07 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 28
**Research archive entries:** 63

## 2026-05-08 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 29
**Research archive entries:** 63

## 2026-05-09 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 30
**Research archive entries:** 63

## 2026-05-10 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 31
**Research archive entries:** 63

## 2026-05-11 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 32
**Research archive entries:** 63

## 2026-05-12 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 33
**Research archive entries:** 63

## 2026-05-13 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 34
**Research archive entries:** 63

## 2026-05-14 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 35
**Research archive entries:** 63

## 2026-05-15 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 36
**Research archive entries:** 63

## 2026-05-16 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 37
**Research archive entries:** 63

## 2026-05-17 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 38
**Research archive entries:** 63

## 2026-05-18 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 39
**Research archive entries:** 63

## 2026-05-19 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 40
**Research archive entries:** 63

## 2026-05-20 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 41
**Research archive entries:** 63

## 2026-05-21 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 42
**Research archive entries:** 63

## 2026-05-22 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 43
**Research archive entries:** 63

## 2026-05-23 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 44
**Research archive entries:** 63

## 2026-05-24 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 45
**Research archive entries:** 63

## 2026-05-25 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 46
**Research archive entries:** 63

## 2026-05-26 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 47
**Research archive entries:** 63

## 2026-05-27 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 48
**Research archive entries:** 63

## 2026-05-28 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 49
**Research archive entries:** 63

## 2026-05-29 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 50
**Research archive entries:** 63

## 2026-05-30 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 51
**Research archive entries:** 63

## 2026-05-31 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 52
**Research archive entries:** 63

## 2026-06-01 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 53
**Research archive entries:** 63

## 2026-06-02 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 54
**Research archive entries:** 63

## 2026-06-03 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 55
**Research archive entries:** 63

## 2026-06-04 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 56
**Research archive entries:** 63

## 2026-06-05 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 57
**Research archive entries:** 63

## 2026-06-06 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 58
**Research archive entries:** 63

## 2026-06-07 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 59
**Research archive entries:** 63

## 2026-06-08 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 60
**Research archive entries:** 63

## 2026-06-09 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 61
**Research archive entries:** 63

## 2026-06-10 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 62
**Research archive entries:** 63

## 2026-06-11 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 63
**Research archive entries:** 63

## 2026-06-12 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 64
**Research archive entries:** 63

## 2026-06-13 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 65
**Research archive entries:** 63

## 2026-06-14 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 66
**Research archive entries:** 63

## 2026-06-15 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 67
**Research archive entries:** 63

## 2026-06-16 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 68
**Research archive entries:** 63

## 2026-06-17 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 69
**Research archive entries:** 63

## 2026-06-18 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 70
**Research archive entries:** 63

## 2026-06-19 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 71
**Research archive entries:** 63

## 2026-06-20 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 72
**Research archive entries:** 63

## 2026-06-21 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 73
**Research archive entries:** 63

## 2026-06-22 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 74
**Research archive entries:** 63

## 2026-06-23 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 75
**Research archive entries:** 63

## 2026-06-24 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 76
**Research archive entries:** 63

## 2026-06-25 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 77
**Research archive entries:** 63

## 2026-06-26 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 78
**Research archive entries:** 63

## 2026-06-27 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 79
**Research archive entries:** 63

## 2026-06-28 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 80
**Research archive entries:** 63

## 2026-06-29 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 81
**Research archive entries:** 63

## 2026-06-30 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 82
**Research archive entries:** 63

## 2026-07-01 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 83
**Research archive entries:** 63

## 2026-07-02 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 84
**Research archive entries:** 63

## 2026-07-03 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 85
**Research archive entries:** 63

## 2026-07-04 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 86
**Research archive entries:** 63

## 2026-07-05 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 87
**Research archive entries:** 63

## 2026-07-06 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 88
**Research archive entries:** 63

## 2026-07-07 — nightly consolidation

**Sentinel:** passed=4 failed=0
**Cipher:** leaks=0 in agents/ra/pipeline/
**Newsletters shipped:** 89
**Research archive entries:** 63
