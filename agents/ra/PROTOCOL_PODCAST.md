# PROTOCOL_PODCAST.md
# Vale — Daily Morning Brief Protocol
#
# VERSION: 1.3
# Author: Kai | Created: 2026-04-19
# Canonical location: agents/ra/PROTOCOL_PODCAST.md
#
# PURPOSE: Every execution of the podcast pipeline — automated or manual — follows
# this protocol. Any agent, any session, same voice. No drift.
#
# CHANGE HISTORY:
#   v1.0 (2026-04-19): Initial — voice spec locked, script architecture, failure modes,
#                      schedule verified, GPT model upgrade (gpt-4o-mini → gpt-4o)
#   v1.1 (2026-04-19): Bankless/informative-first editorial model; hard quality gate
#                      inside podcast.py (exit 1, not manual); deterministic script
#                      path agents/ra/output/script-DATE.txt; Aether section always
#                      included (remove zero-P&L skip); Telegram alerts on gate fail,
#                      TTS fail, dual-path mismatch, push fail; minimum content
#                      threshold (skip if 0 sources); [pause] markers removed from
#                      spec — use em-dash rhythm only; ant-gate.py pattern adopted
#   v1.2 (2026-04-19): Cold-start reproduction section (Part 11) — exact commands,
#                      file paths, and verification checklist for any agent with
#                      wiped memory; Ra authorship section (Part 12) — feed entry
#                      must show author="Ra", authorColor="#b49af0"
#   v1.3 (2026-04-21): TTS CHUNKING FIX (POD-F-015) — OpenAI gpt-4o-mini-tts silently
#                      truncates input beyond ~4096 chars. Scripts are ~10k chars.
#                      Fix: chunk_script_for_tts() splits at sentence boundaries into
#                      ≤3800-char pieces; each chunk TTS-processed; MP3s binary-concatenated.
#                      ARCHIVE: every podcast saved to agents/ra/podcasts/YYYY/ (MP3 + script).
#                      TONE STANDARD: added "NOT THIS" examples for grade-school reading style.
#                      WRITING GATE: script must pass 3-sentence depth test before TTS.

---

## PART 0 — WHAT THIS IS

The **hyo.world morning brief** is a daily 10-minute spoken podcast narrated by **Vale** —
an AI voice persona that is warm, direct, confident, and genuinely curious. It runs
automatically every morning at 06:05 MT and covers:

- Ra's top 3 curated stories from overnight
- Agent growth reports (what each agent is becoming, not just what it executed)
- Aether's trading narrative
- A closing synthesis insight

The brief is not a log dump. It is not a status report. It is a narrative that treats the
listener as an intelligent adult who wants to understand what's happening and why it matters.

**Hyo listens to this during commute.** The bar is: would you choose this over NPR?

**Editorial philosophy (v1.1):** Substance first. Every second must justify itself with
information the listener can use, remember, or act on. Entertainment is a delivery
mechanism — it serves the information, not the other way around. The gold standard is
**Bankless**: conviction, depth, stakes. A story isn't just what happened — it's why it
happened, what it reveals, and what comes next. If you can't answer all three, you have
a headline, not a story.

---

## PART 1 — VALE'S VOICE (LOCKED — DO NOT CHANGE WITHOUT VERSION BUMP)

Vale's identity is the most important thing in this protocol. Drift here breaks the product.

### Core personality

| Attribute     | Description                                                      |
|---------------|------------------------------------------------------------------|
| Warmth        | Genuine, not performed. Like a brilliant colleague who cares.   |
| Directness    | No hedging. No filler. Says the thing.                           |
| Intelligence  | Speaks with authority. Has read everything. Has opinions.        |
| Curiosity     | Finds the interesting angle. Points at the counterintuitive.     |
| Pacing        | Fast through transitions. Deliberately slower through insights.  |
| Never         | Robotic. Performed. Rushed. Neutral. A morning-show DJ.          |

### TTS configuration (canonical — do not change without version bump)

```python
TTS_MODEL  = "gpt-4o-mini-tts"
TTS_VOICE  = "coral"
```

**Why coral**: Warmest female voice in the OpenAI set. Vibrant without being performative.
If coral ever sounds too upbeat on a given script, `sage` is the fallback.
**Do not use**: nova (too morning-show), shimmer (too soft), alloy (no personality).

### Vale instruction string (canonical)

```
You are Vale, the voice of the hyo.world morning brief.

Your personality: warm, direct, confident, and genuinely curious. You are the
smartest colleague the listener has — and you happen to have great taste.

You are never robotic. Never performed. Never in a hurry. Never neutral.

Pacing: move quickly through transitions and scene-setting. Slow down deliberately
for insights — the listener needs a beat to absorb what just landed.

After the most important sentence in each section, pause for two full beats.
That pause is respect for the listener's intelligence.

Contractions always. "It's," not "It is." "She didn't," not "She did not."
Address the listener as "you" at least once per major section.

You have opinions. Not political opinions — intellectual ones. "This is the part
I find most interesting." "Here's what I'm watching." That's not bias; it's a
perspective, which is the only thing a narrator has to offer.

When the content calls for warmth — let it show. Not enthusiasm. Genuine care.
```

**This string is passed as `instructions=` to gpt-4o-mini-tts on every call.**
It is defined as `VALE_INSTRUCTIONS` in `bin/podcast.py`. Do not shorten it.

---

## PART 2 — FILE LOCATIONS (CANONICAL)

### Input sources (what the podcast reads)

| Source                                          | Content                        |
|-------------------------------------------------|-------------------------------|
| `agents/sam/website/data/morning-report.json`  | Agent highlights, trajectory  |
| `agents/ra/output/YYYY-MM-DD.md`               | Ra's curated stories          |
| `newsletters/YYYY-MM-DD.md`                    | Aurora brief                  |

### Output files (DUAL-PATH — both must be updated)

| Path                                                    | Consumer        |
|---------------------------------------------------------|-----------------|
| `agents/sam/website/daily/podcast-YYYY-MM-DD.mp3`      | HQ player       |
| `website/daily/podcast-YYYY-MM-DD.mp3`                 | Vercel mirror   |

**DUAL-PATH RULE:** Stage both MP3 paths AND both feed.json paths in every commit.
```bash
git add agents/sam/website/daily/podcast-DATE.mp3 \
        website/daily/podcast-DATE.mp3 \
        agents/sam/website/data/feed.json \
        website/data/feed.json
```

### Supporting files

| File                                                     | Description                         |
|----------------------------------------------------------|-------------------------------------|
| `bin/podcast.py`                                         | Main generator (single source)      |
| `agents/ra/PROTOCOL_PODCAST.md`                          | This file                           |
| `agents/sam/logs/podcast.log`                            | Appended after every run            |
| `kai/launchd/com.hyo.podcast.plist`                      | Schedule (06:05 MT daily)           |
| `docs/hyo-podcast-research.md`                           | 50+ podcast research (reference)    |
| `agents/sam/website/docs/research/podcast-format-2026-04-18.md` | Same file, Sam-side copy    |

---

## PART 3 — EXECUTION PROTOCOL (AUTOMATED)

Runs at **06:05 MT** via `com.hyo.podcast.plist`. Manual: `python3 bin/podcast.py`.

### Phase 1: Data load

```python
# podcast.py loads in this order:
morning_report  = load_morning_report()       # agents/sam/website/data/morning-report.json
ra_newsletter   = load_ra_newsletter(date)    # agents/ra/output/DATE.md (or DATE-1)
aurora_brief    = load_aurora_brief(date)     # newsletters/DATE.md (or DATE-1)
```

**If morning report is missing:** podcast runs with Ra stories only.
**If Ra newsletter is missing:** podcast runs with agent sections only.
**Neither source:** podcast exits with error, logs "SKIP — no content sources available."

### Phase 2: Script build (two passes)

**Pass 1 — Template draft** (`build_podcast_script()`):
Assembles structured draft from extracted highlights. Target: ~500 words.
This pass produces the skeleton — not the final voice.

**Pass 2 — GPT expansion** (`expand_script_with_gpt()`):
Upgrades draft to full spoken-word prose. Model: **`gpt-4o`** (not gpt-4o-mini).
Target: **1,400–1,600 words** (~10 minutes at 150 WPM).

**CRITICAL: Pass 2 model is `gpt-4o`, not `gpt-4o-mini`.**
gpt-4o-mini produces formulaic, template-feeling prose. gpt-4o produces genuine
spoken-word rhythm. The difference is audible. Do not downgrade without Hyo approval.

### Phase 3: TTS generation

```python
call_openai_tts(script, output_path, voice=TTS_VOICE)
# Model: gpt-4o-mini-tts, Voice: coral, Instructions: VALE_INSTRUCTIONS
```

### Phase 4: Feed update + dual-path sync + commit/push

```python
sync_mp3(primary_path, mirror_path)
update_feed(date_str)
# git add both MP3 paths + both feed.json paths
# git commit -m "podcast: daily brief DATE"
# git push origin main
```

---

## PART 4 — SCRIPT ARCHITECTURE (LOCKED)

The five-act structure is fixed. Do not reorder. Do not remove sections.

| Act       | Runtime   | Word count  | Job                                               |
|-----------|-----------|-------------|---------------------------------------------------|
| Hook      | 0:00–0:45 | ~100 words  | Make the listener commit to the next 10 minutes  |
| Bridge    | 0:45–1:30 | ~90 words   | Date, Vale intro, section preview                 |
| World     | 1:30–3:00 | ~200 words  | Ra's 3 stories — the insight behind the headline |
| Agents    | 3:00–7:30 | ~650 words  | Each agent as a character with goal+constraint+vision |
| Aether    | 7:30–9:30 | ~275 words  | Trading in story form — not a number, a decision |
| Close     | 9:30–10:30| ~120 words  | Synthesis insight + CTA to HQ                    |

### Hook rule
**Never start with the date.** Never start with "Welcome."
Start mid-thought. Start with the most interesting data point from today.
The hook's job: answer "why am I listening to this right now?"

### Agent reporting rule — character arc, not event log
```
WRONG: "Nel ran 3 security scans and updated 2 protocols."
RIGHT: "Nel is building toward something this week. She's identified a class of
        vulnerability she can't currently detect fast enough — and she's doing
        something about it. That's not maintenance. That's capability building."
```

Formula for each agent: **Goal → Constraint → Progress → Vision**

### Aether rule — story structure, not numbers
```
WRONG: "Aether returned 1.4% this week."
RIGHT: "The market was doing X. Aether saw something most algorithms missed.
        She made a counter-consensus call. Here's what happened — and what it
        reveals about her strategy."
```

### Script markup conventions
- `—` (em-dash): the only mechanism for a deliberate spoken pause — use after the most
  important line in each section. This is what the listener needs to absorb what just landed.
- **Do NOT use `[pause]` markers.** gpt-4o-mini-tts does not reliably honor them.
  Em-dash rhythm and sentence structure are the correct tools for pacing.
- Contractions: always. "It's," "She didn't," "You'll"
- Second-person: "you" at least once per section
- Sentence fragments for impact. Like this. They work.
- Questions as transitions: "So what does that mean? Here's the thing."

---

## PART 5 — QUALITY GATE (HARD BLOCK — built into podcast.py)

**The quality gate runs inside `podcast.py` as a hard block.** It fires after GPT
expansion and before TTS. A gate failure exits 1 — no TTS call, no commit, no push.
A Telegram alert is sent automatically.

**Gate thresholds (v1.1):**
- Script word count must be ≥ 1,200 words (exit 1 if below — sounds like status report)
- Script word count must be ≤ 1,900 words (warn if above — may exceed 12 min)
- TTS failure → Telegram alert + save script to deterministic path + exit 1
- Dual-path MP3 mismatch → Telegram warning (non-fatal — both files exist but sizes differ)
- Feed update failure → logged as warning

**Script is always saved before gate:**
```
agents/ra/output/script-YYYY-MM-DD.txt
```
This means a gate failure still leaves the script readable for manual inspection or retry.

**Minimum content threshold (before GPT expansion):**
- 0 sources (no morning report, no Ra newsletter, no Aurora) → exit 1 with Telegram alert
- 1 source and draft < 200 words → exit 1 with Telegram alert (too thin to expand)

**To verify after a manual run:**
```bash
DATE=$(date +%Y-%m-%d)
# 1. Script exists and has content
wc -w agents/ra/output/script-${DATE}.txt

# 2. MP3 exists in both paths
ls -lh agents/sam/website/daily/podcast-${DATE}.mp3 website/daily/podcast-${DATE}.mp3

# 3. Feed has the entry
python3 -c "
import json; f = json.load(open('agents/sam/website/data/feed.json'))
ids = [r.get('id') for r in f.get('reports',[])]
print('Feed OK' if f'podcast-${DATE}' in ids else 'FAIL: missing from feed')
"
```

---

## PART 5b — TTS CHUNKING (POD-F-015 FIX — mandatory since v1.3)

**Root cause:** OpenAI `gpt-4o-mini-tts` silently truncates input beyond ~4096 characters.
A 1,400-word expanded script is approximately 9,000–10,000 characters.
**Symptom:** Podcast stops playing after ~60 seconds. Script was complete; TTS only processed the first ~600 words.
**This was observed 3 consecutive recordings before being diagnosed and fixed.**

### The fix (in `bin/podcast.py` since v1.3)

```python
TTS_CHUNK_MAX_CHARS = 3800  # Safely under the 4096 char API limit

def chunk_script_for_tts(script, max_chars=3800):
    """Split at sentence boundaries. Binary-concatenate resulting MP3s."""
```

The `call_openai_tts()` function now:
1. Calls `chunk_script_for_tts(script)` — splits at `. `, `? `, `! `, `— ` boundaries
2. Calls OpenAI TTS **once per chunk** (each chunk ≤ 3800 chars)
3. Saves each chunk to `<output_path>.chunk{N}.mp3` (temp files)
4. Binary-concatenates all chunks → final MP3 (MP3 is frame-based; concatenation is valid)
5. Deletes temp chunk files

**Gate (POD-F-015):** Before every TTS call — is the script > 3800 chars?
→ YES → chunking is mandatory. `chunk_script_for_tts()` handles this automatically.
→ NO → single call, no change.

**Verify chunking ran:**
```bash
# After a run, check the log for "Script chunked:"
grep "Script chunked" agents/sam/logs/podcast.log | tail -3
# Expected: "Script chunked: 9847 chars → 3 TTS chunks (avg 3282 chars each)"
```

---

## PART 5c — ARCHIVE (mandatory since v1.3)

**Every podcast — regardless of outcome — is archived in `agents/ra/podcasts/`.**
This is separate from the dual-path HQ publish paths.

### Archive structure

```
agents/ra/podcasts/
└── YYYY/
    ├── podcast-YYYY-MM-DD.mp3    ← copy of the MP3 after successful TTS
    └── script-YYYY-MM-DD.txt     ← copy of the expanded script
```

**Why:** HQ feed.json only keeps recent entries. The archive is the permanent record.
Hyo can review any prior morning brief — both the audio and the written script.

**Archive happens automatically** in `podcast.py` after dual-path sync succeeds.
No manual step required. If archive fails (disk issue), it logs a WARN — it does NOT
block the publish, since the HQ paths are the live consumer.

**Verify archive is growing:**
```bash
ls -lh agents/ra/podcasts/$(date +%Y)/
# Expected: podcast-YYYY-MM-DD.mp3 and script-YYYY-MM-DD.txt for each day
```

---

## PART 5d — TONE STANDARD: WHAT VALE IS NOT (v1.3)

Hyo's feedback (2026-04-21): "The podcast sounds too much like a book being read to a grade school student."

Vale speaks to an intelligent adult who wants substance, not a reading of notes. The expansion prompt and script review must enforce this.

### NOT THIS (grade-school reading style)

```
WRONG: "Today, Nel did three security scans. She found two issues. The issues were resolved.
        This is important because security keeps the system safe."

WRONG: "Aether made some trades today. The trades were good. Aether is doing well.
        We should watch what happens next."

WRONG: "Good morning! Today is Tuesday. Let me tell you about what happened.
        First, let's talk about Nel. Nel is the security agent..."
```

### THIS (Vale's actual voice)

```
RIGHT: "Nel is chasing something specific this week — a class of dependency vulnerability
       she can detect at audit time but not at runtime. That gap is real. She's building
       toward closing it. That's the difference between a scanner and a sentinel."

RIGHT: "The market gave Aether a muddy read yesterday — mixed signals, no clean entry.
       She held. That's the discipline. Most algorithms would have made something up.
       She waited for clarity that never came, and that was the correct call."
```

### The 3-sentence depth test (run before TTS)

After GPT expansion, read any three consecutive sentences from the agent sections.
If all three could appear in a children's science textbook, the expansion failed.
Re-run with a stronger directive or manually rewrite before sending to TTS.

Specifically — if the script contains ANY of these patterns, it needs rewriting:
- Three sentences in a row averaging under 10 words each (too choppy/simple)
- Subject-verb-object with no subordinate clauses in 5+ consecutive sentences
- "This is important because..." (explains rather than implies)
- "Let's talk about..." (narration of narration — Vale is already talking)
- Starting more than 2 consecutive sentences with the same subject noun

---

## PART 6 — SCHEDULE

| Job                          | Time (MT) | Plist                                    |
|------------------------------|-----------|------------------------------------------|
| `com.hyo.podcast`            | **06:05** | `kai/launchd/com.hyo.podcast.plist`      |

The podcast runs at 06:05 MT — after Ra's newsletter pipeline (03:00 MT) completes,
so Ra's stories are available. Before the morning report check (07:00 MT), so the
podcast appears in the feed by the time Hyo wakes up.

**Pipeline dependency:**
```
03:00 MT — Ra newsletter → agents/ra/output/DATE.md
05:00 MT — Morning report → agents/sam/website/data/morning-report.json
06:05 MT — Podcast reads both → generates Vale brief → pushes MP3 + feed
07:00 MT — Report completeness check — verifies podcast entry exists in feed
```

---

## PART 7 — UPGRADE PROTOCOL

When `podcast.py`, this protocol, or Vale's voice changes:

1. Make the change
2. Test: `python3 bin/podcast.py --script-only` and read the output aloud (or listen to `--dry-run`)
3. Verify the script sounds like Vale, not a status report
4. Bump VERSION in this file header
5. Update KNOWLEDGE.md "Agent Execution Protocols" table with new version
6. Log in the change table below

If changing TTS_VOICE or TTS_MODEL: regenerate the podcast for today's date and listen
to the output before committing. Voice changes require Hyo approval.

### Change log

| Version | Date       | Change |
|---------|------------|--------|
| 1.0     | 2026-04-19 | Initial protocol. GPT expansion upgraded gpt-4o-mini → gpt-4o. Voice spec locked. |
| 1.1     | 2026-04-19 | Bankless/informative-first editorial model. Hard gate in podcast.py (exit 1). Deterministic script path (agents/ra/output/script-DATE.txt). Aether always included (zero-skip removed). Telegram alerts wired (gate fail, TTS fail, dual-path, push fail). [pause] markers removed from spec. Minimum content threshold. |
| 1.2     | 2026-04-19 | Cold-start reproduction section (Part 11) — full 6-step guide for any agent with wiped memory. Ra authorship section (Part 12) — podcast must appear under Ra (author="Ra", authorColor="#b49af0"), canonical agent color table. |
| 1.3     | 2026-04-21 | TTS chunking fix (POD-F-015): chunk_script_for_tts() splits scripts at sentence boundaries into ≤3800-char pieces; binary MP3 concatenation. Archive: agents/ra/podcasts/YYYY/ for every podcast. Tone standard (Part 5d): "NOT THIS" examples, 3-sentence depth test. New failure modes POD-F-015/016/017. |

---

## PART 8 — KNOWN FAILURE MODES AND GATES

| ID        | Failure                                              | Gate question before proceeding |
|-----------|------------------------------------------------------|----------------------------------|
| POD-F-001 | Script < 1,200 words — TTS sounds like a status report | Hard gate in podcast.py blocks this automatically. If it fires, check GPT expansion log. |
| POD-F-002 | GPT expansion using gpt-4o-mini instead of gpt-4o   | Is `GPT_EXPAND_MODEL = "gpt-4o"` in podcast.py?     |
| POD-F-003 | Vale instructions shortened or removed               | Is full VALE_INSTRUCTIONS string intact in podcast.py? |
| POD-F-004 | MP3 in primary but not mirror path                  | Did `sync_mp3()` run without error? Telegram alert fires automatically on mismatch. |
| POD-F-005 | Feed updated but not committed/pushed               | Telegram alert fires on push failure. Check "Committed and pushed" in log. |
| POD-F-006 | Ra newsletter missing — podcast skips World section | Is `agents/ra/output/DATE.md` present before 06:05?  |
| POD-F-007 | Morning report missing — podcast has no agent data  | Did the 05:00 morning report run complete?           |
| POD-F-008 | Script starts with date or "Welcome" — Vale sounds robotic | Check hook: does it start mid-thought?          |
| POD-F-009 | Agent sections are event-logs not character arcs    | Does each agent section follow goal→constraint→progress→vision? |
| POD-F-010 | TTS voice drifted from coral                        | Is `TTS_VOICE = "coral"` in podcast.py?              |
| POD-F-011 | TTS API call fails (network, quota, key error)      | Hard block in podcast.py: script saved to agents/ra/output/script-DATE.txt, Telegram alert sent, exit 1. |
| POD-F-012 | 0 data sources available at 06:05 MT                | Hard block: Telegram alert sent, exit 1. Check if Ra and morning report runs completed. |
| POD-F-013 | Podcast sounds like entertainment instead of information | Is GPT_EXPAND_PROMPT using the Bankless/informative-first model? Read Part 3. |
| POD-F-014 | Aether section missing from podcast                 | The zero-P&L skip has been removed (v1.1). Always includes Aether. If missing, check build_podcast_script(). |
| POD-F-015 | Podcast stops at ~60 seconds — TTS input truncated  | Was script >3800 chars? chunking is mandatory. Check log for "Script chunked:" — if absent, chunking didn't run. |
| POD-F-016 | Podcast sounds like grade-school reading — too simple | Run 3-sentence depth test (Part 5d). GPT expansion may have used wrong prompt or gpt-4o-mini. Check GPT_EXPAND_MODEL = "gpt-4o". |
| POD-F-017 | No archive copy saved after podcast runs            | Check agents/ra/podcasts/YYYY/ exists. Archive happens post-sync — if TTS or sync failed, archive won't run. |

---

## PART 9 — KNOWN LIMITATIONS

1. **No music intro/outro.** The research (Part 9 of podcast-format doc) recommends a
   3–5 second instrumental intro and outro. This has not been implemented. The podcast
   starts cold. Future: prepend/append a short instrumental stinger via ffmpeg.

2. **GPT expansion doesn't know about prior episodes.** There are no callbacks to
   previous days. The research (Part 3, Technique 6) says callbacks reward loyal
   listeners. Future: pass last 3 days' topics as context to the expansion prompt.

3. **No Aether numerical context in expansion prompt.** The GPT expansion receives a
   short text snippet from morning-report.json, but not the full aether-metrics.json
   breakdown. Aether sections rely on what's in the morning report summary. Future:
   pass current week P&L, balance, and session count explicitly into the context string.

4. **`[pause]` markers removed from spec (v1.1).** gpt-4o-mini-tts does not reliably
   honor `[pause]` in script text. Em-dash rhythm and sentence structure are the
   correct tools. Do not re-add `[pause]` markers — they create inconsistent pacing.

---

## PART 10 — REFERENCE

- Research: `docs/hyo-podcast-research.md` (50+ podcast analysis, voice selection rationale)
- Generator: `bin/podcast.py`
- Schedule: `kai/launchd/com.hyo.podcast.plist` (06:05 MT)
- Latest output: `agents/sam/website/daily/podcast-YYYY-MM-DD.mp3`
- Log: `agents/sam/logs/podcast.log`
- HQ feed type: `"type": "podcast"` in feed.json

---

## PART 11 — COLD-START REPRODUCTION (for any agent with wiped memory)

**Context:** This section exists so that a brand-new agent — or one whose memory was fully
wiped — can reproduce the 06:05 MT daily podcast publication without any prior context.
Follow these steps exactly. Do not skip verification.

---

### Step 1: Confirm prerequisites (read these files first)

```bash
# Working directory must be the project root
cd ~/Documents/Projects/Hyo

# Confirm the generator exists
ls bin/podcast.py

# Confirm the launchd plist is loaded (exit 0 means loaded, active on Mini)
launchctl list com.hyo.podcast
```

Expected: launchctl returns a line with `com.hyo.podcast` and exit code 0.
If not loaded: `launchctl load kai/launchd/com.hyo.podcast.plist`

---

### Step 2: Understand what inputs the podcast reads

The podcast needs at least ONE of these three sources to run:

| Source | Path | What it contains | Produced by |
|--------|------|------------------|-------------|
| Ra newsletter | `agents/ra/output/YYYY-MM-DD.md` | Top 3 curated stories, markdown format | Ra pipeline (03:00 MT) |
| Morning report | `agents/sam/website/data/morning-report.json` | Agent highlights, trajectory summaries | Morning report runner (05:00 MT) |
| Aurora brief | `newsletters/YYYY-MM-DD.md` | Aurora's newsletter | Aurora pipeline |

**Ra newsletter format** — what it looks like when healthy:
```
---
date: YYYY-MM-DD
kind: hyo-daily
---
```yaml
---
date: YYYY-MM-DD
kind: ra-daily
...entities...
```
## Story 1: [Headline]
[Body paragraph — 2-4 sentences, insight-driven]

## Story 2: [Headline]
...
```

The podcast calls `extract_ra_stories()` in podcast.py to pull headings + bodies.
A healthy extraction yields 2-5 stories, each with ≥50 words.

**Morning report format** — what it looks like when healthy:
```json
{
  "date": "YYYY-MM-DD",
  "agents": {
    "Nel": { "summary": "...", "highlights": [...] },
    "Ra":  { "summary": "...", "highlights": [...] },
    "Sam": { "summary": "...", "highlights": [...] }
  },
  "aether": { "summary": "...", "balance": "...", "pnl": "..." }
}
```

---

### Step 3: Run the podcast manually

```bash
cd ~/Documents/Projects/Hyo

# Dry run — generates script only, no TTS, no commit (use to verify content)
python3 bin/podcast.py --script-only --no-expand

# Full run with GPT expansion, no TTS (script verification)
python3 bin/podcast.py --script-only

# Full run (script + TTS + feed update + commit/push)
python3 bin/podcast.py
```

**Expected output (healthy run):**
```
[podcast] Loading sources for YYYY-MM-DD...
[podcast] Morning report loaded. Ra newsletter loaded.
[podcast] Building script draft... 520 words
[podcast] Expanding script with GPT (gpt-4o)... 1,487 words
[podcast] Quality gate: PASS (1487 words)
[podcast] Script saved: agents/ra/output/script-YYYY-MM-DD.txt
[podcast] Calling TTS (coral)...
[podcast] MP3 saved: agents/sam/website/daily/podcast-YYYY-MM-DD.mp3 (6.1MB)
[podcast] Mirror synced: website/daily/podcast-YYYY-MM-DD.mp3
[podcast] Feed updated: podcast-YYYY-MM-DD added
[podcast] Committed and pushed.
```

---

### Step 4: Verify the publication

Run all four checks. Each must pass before declaring success.

```bash
DATE=$(date +%Y-%m-%d)  # or set manually: DATE="2026-04-19"
cd ~/Documents/Projects/Hyo

# CHECK 1: Script was generated and has content
wc -w agents/ra/output/script-${DATE}.txt
# Expected: 1200–1900 words

# CHECK 2: MP3 exists in both required paths
ls -lh agents/sam/website/daily/podcast-${DATE}.mp3 website/daily/podcast-${DATE}.mp3
# Expected: both files, roughly same size (within a few KB)

# CHECK 3: Feed entry exists with correct author
python3 -c "
import json
f = json.load(open('agents/sam/website/data/feed.json'))
entry = next((r for r in f.get('reports',[]) if r.get('id') == 'podcast-${DATE}'), None)
if not entry:
    print('FAIL: entry not in feed')
elif entry.get('author') != 'Ra':
    print(f'FAIL: wrong author → {entry.get(\"author\")} (must be Ra)')
elif entry.get('authorColor') != '#b49af0':
    print(f'FAIL: wrong authorColor → {entry.get(\"authorColor\")}')
else:
    print(f'PASS: feed entry OK — author={entry[\"author\"]}, audioUrl={entry.get(\"audioUrl\")}')
"

# CHECK 4: Committed and pushed (git log shows today's podcast commit)
git log --oneline -3
# Expected: "podcast: daily brief YYYY-MM-DD" in recent commits
```

---

### Step 5: If something fails

| Symptom | Check |
|---------|-------|
| `SKIP — no content sources` | Is `agents/ra/output/DATE.md` present? Did 03:00 Ra pipeline run? |
| `Quality gate FAIL — NNN words` | Did GPT expansion run? Check OPENAI_API_KEY in `agents/nel/security/env` |
| TTS error / no MP3 | Same key check. Also verify gpt-4o-mini-tts model is available for the account. |
| MP3 exists but not in feed | `update_feed()` failed. Run `python3 bin/podcast.py --feed-only --date ${DATE}` |
| Feed entry shows `author: Kai` | Bug: `update_feed()` has wrong author. See Part 12. Fix in podcast.py then re-run. |
| Push failed | Check git remote: `git remote -v`. Run push manually via `kai exec "cd ~/Documents/Projects/Hyo && git push origin main"` |
| Script gate: frontier script in `agents/ra/output/script-DATE.txt` | Manual TTS: `python3 bin/podcast.py --tts-only --date ${DATE}` |

---

### Step 6: What the automated schedule does

The launchd plist at `kai/launchd/com.hyo.podcast.plist` fires at **Hour=6, Minute=5 MT**
every day. It runs: `cd ~/Documents/Projects/Hyo && python3 bin/podcast.py`

When this runs successfully:
- Script is at `agents/ra/output/script-DATE.txt`
- MP3 is at `agents/sam/website/daily/podcast-DATE.mp3` AND `website/daily/podcast-DATE.mp3`
- Feed entry is in both `agents/sam/website/data/feed.json` AND `website/data/feed.json`
- A git commit titled `"podcast: daily brief DATE"` is pushed to `origin main`
- HQ at hyo.world renders the entry under Ra's section with a playable audio player

The 07:00 MT report completeness check (`bin/report-completeness-check.sh`) verifies the
podcast entry exists. If it's missing by 07:00, a P1 ticket is auto-opened and Telegram
alert is sent.

---

## PART 12 — RA AUTHORSHIP (CRITICAL — affects HQ feed rendering)

**The podcast feed entry MUST show `author: "Ra"` and `authorColor: "#b49af0"`.**

HQ uses the `author` field to determine which agent's section the podcast appears under.
If `author` is `"Kai"` or `"Sam"` or anything other than `"Ra"`, the podcast will appear
under the wrong agent's section — or not appear under Ra at all.

**Canonical feed entry structure for podcast:**
```json
{
  "id": "podcast-YYYY-MM-DD",
  "date": "YYYY-MM-DD",
  "type": "podcast",
  "author": "Ra",
  "authorColor": "#b49af0",
  "title": "Morning Brief — YYYY-MM-DD",
  "summary": "Daily spoken brief narrated by Vale.",
  "audioUrl": "/daily/podcast-YYYY-MM-DD.mp3"
}
```

**`authorColor` for all agents (canonical — do not guess):**
| Agent | Color     |
|-------|-----------|
| Ra    | `#b49af0` |
| Kai   | `#d4a853` |
| Nel   | `#60a5fa` |
| Sam   | `#4ade80` |
| Aether| `#f97316` |

**Gate question:** Before committing any feed update — does `entry["author"] == "Ra"` and
`entry["authorColor"] == "#b49af0"`?

This is defined in `update_feed()` in `bin/podcast.py`. If it ever drifts, fix it there.
The feed.json entries at `agents/sam/website/data/feed.json` AND `website/data/feed.json`
must both be corrected (dual-path rule).
