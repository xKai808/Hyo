# PROTOCOL_PODCAST.md
# Vale — Daily Morning Brief Protocol
#
# VERSION: 1.0
# Author: Kai | Created: 2026-04-19
# Canonical location: agents/ra/PROTOCOL_PODCAST.md
#
# PURPOSE: Every execution of the podcast pipeline — automated or manual — follows
# this protocol. Any agent, any session, same voice. No drift.
#
# CHANGE HISTORY:
#   v1.0 (2026-04-19): Initial — voice spec locked, script architecture, failure modes,
#                      schedule verified, GPT model upgrade (gpt-4o-mini → gpt-4o)

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
- `—` (em-dash): natural spoken pause
- `[pause]`: explicit 1–2 second silence after the most important line in a section
- Contractions: always. "It's," "She didn't," "You'll"
- Second-person: "you" at least once per section
- Sentence fragments for impact. Like this. They work.
- Questions as transitions: "So what does that mean? Here's the thing."

---

## PART 5 — QUALITY GATE

Run after generation, before declaring done:

```bash
# 1. Word count check
python3 -c "
import sys
script = open('/tmp/last-podcast-script.txt').read() if __import__('os').path.exists('/tmp/last-podcast-script.txt') else ''
wc = len(script.split())
print(f'Words: {wc}')
assert wc >= 1200, f'FAIL: script too short ({wc} words) — sounds like a status report not a podcast'
assert wc <= 1800, f'WARN: script very long ({wc} words) — may exceed 12 min'
print('Word count: OK')
"

# 2. MP3 exists and is non-trivial
DATE=$(date +%Y-%m-%d)
ls -lh agents/sam/website/daily/podcast-${DATE}.mp3
# Should be > 1MB for a real podcast

# 3. Both paths synced
diff agents/sam/website/daily/podcast-${DATE}.mp3 website/daily/podcast-${DATE}.mp3 && echo "DUAL-PATH: OK" || echo "DUAL-PATH: FAIL"

# 4. Feed updated
python3 -c "
import json
f = json.load(open('agents/sam/website/data/feed.json'))
ids = [r.get('id') for r in f.get('reports',[])]
date = __import__('datetime').date.today().isoformat()
assert f'podcast-{date}' in ids, f'FAIL: podcast-{date} not in feed'
print('Feed entry: OK')
"
```

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

---

## PART 8 — KNOWN FAILURE MODES AND GATES

| ID        | Failure                                              | Gate question before proceeding |
|-----------|------------------------------------------------------|----------------------------------|
| POD-F-001 | Script < 1,200 words — TTS sounds like a status report | Did the GPT expansion reach 1,400+ words? Check log. |
| POD-F-002 | GPT expansion using gpt-4o-mini instead of gpt-4o   | Is `GPT_EXPAND_MODEL = "gpt-4o"` in podcast.py?     |
| POD-F-003 | Vale instructions shortened or removed               | Is full VALE_INSTRUCTIONS string intact in podcast.py? |
| POD-F-004 | MP3 in primary but not mirror path                  | Did `sync_mp3()` run without error? Check log.       |
| POD-F-005 | Feed updated but not committed/pushed               | Did git push succeed? Check "Committed and pushed" in log. |
| POD-F-006 | Ra newsletter missing — podcast skips World section | Is `agents/ra/output/DATE.md` present before 06:05?  |
| POD-F-007 | Morning report missing — podcast has no agent data  | Did the 05:00 morning report run complete?           |
| POD-F-008 | Script starts with date or "Welcome" — Vale sounds robotic | Check hook: does it start mid-thought?          |
| POD-F-009 | Agent sections are event-logs not character arcs    | Does each agent section follow goal→constraint→progress→vision? |
| POD-F-010 | TTS voice drifted from coral                        | Is `TTS_VOICE = "coral"` in podcast.py?              |

---

## PART 9 — KNOWN LIMITATIONS

1. **No music intro/outro.** The research (Part 9 of podcast-format doc) recommends a
   3–5 second instrumental intro and outro. This has not been implemented. The podcast
   starts cold. Future: prepend/append a short instrumental stinger via ffmpeg.

2. **No Aether-specific section when P&L is zero.** If `aether_pnl == 0.0`, the Aether
   narrative section is skipped. A near-flat week still has a story — the script should
   say so. Fix: always include Aether section with context even when P&L is minimal.

3. **GPT expansion doesn't know about prior episodes.** There are no callbacks to
   previous days. The research (Part 3, Technique 6) says callbacks reward loyal
   listeners. Future: pass last 3 days' topics as context to the expansion prompt.

4. **`[pause]` markers are in the spec but not enforced in TTS.** The gpt-4o-mini-tts
   model may or may not honor `[pause]` in the script text. More reliable: use em-dashes
   and sentence structure to cue natural pauses rather than explicit markers.

---

## PART 10 — REFERENCE

- Research: `docs/hyo-podcast-research.md` (50+ podcast analysis, voice selection rationale)
- Generator: `bin/podcast.py`
- Schedule: `kai/launchd/com.hyo.podcast.plist` (06:05 MT)
- Latest output: `agents/sam/website/daily/podcast-YYYY-MM-DD.mp3`
- Log: `agents/sam/logs/podcast.log`
- HQ feed type: `"type": "podcast"` in feed.json
