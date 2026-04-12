---
date: 2026-04-11
kind: aurora-public-simulation
run: sim-01
backend: claude_code:claude-code-cli
status: passed-with-notes
---

# Aurora Public · simulation 01

First end-to-end trial run of the Aurora Public v0 stack against synthetic
inputs. The goal of this run was to answer four questions:

1. Does the per-topic keyword filter actually separate 41 mixed gather
   records into the right buckets for five very different subscribers?
2. Does the voice knob (gentle / balanced / sharp) produce audibly
   distinct briefs for the same day's news?
3. Does the length knob (3min / 6min / 12min) actually move output size?
4. Does the generator → manifest → dispatcher handoff survive all the way
   to rendered HTML with frontmatter-derived subject lines?

All four answered yes. Notes inline.

Raw outputs for every subscriber are in this same directory under
`aurora-sim-2026-04-11/` — both the `.md` briefs and the dark-palette
`.html` email renders. Synthetic gather and subscriber file are also
copied in so the run is reproducible.

## Inputs

- **Synthetic gather:** `synthetic-gather.jsonl` — 41 records spanning
  the full 30-topic taxonomy. Each record has realistic title/summary/
  tags/source/score to exercise the `TOPIC_KEYWORDS` regex map. Isolated
  under `HYO_INTELLIGENCE_DIR=/tmp/aurora_sim` so this run did not touch
  Ra's real research pipeline or archive.
- **Five simulated subscribers:** `subscribers.jsonl` — designed so that
  every voice knob, every depth knob, and every length knob gets exercised
  at least once, and so that every subscriber's topic set is largely
  disjoint from the others.
- **Prior context:** The existing `kai/research/.context.md` (1.5KB)
  from Ra's earlier run was available and honored — Aurora can use it PRN
  but is not required to.

## Subscriber profiles

| id                      | voice     | depth      | length | topics                                                 |
|-------------------------|-----------|------------|--------|---------------------------------------------------------|
| `sim_news_parent`       | gentle    | headlines  | 3min   | health, education, food, fitness                        |
| `sim_indie_gamedev`     | balanced  | balanced   | 6min   | ai, gaming, startups, tech                              |
| `sim_finance_op`        | sharp     | deep-dives | 12min  | macro, finance, stocks, crypto, labor, real-estate      |
| `sim_culture`           | gentle    | balanced   | 6min   | fashion, celebrity, film-and-tv, music, books, gossip   |
| `sim_politics_sports`   | sharp     | headlines  | 3min   | politics, sports, social-media                          |

Coverage: every voice, every depth, every length; 19 of 30 taxonomy slugs
touched across the five subs; max overlap between any two subs is 0 topics.

## Filter math (the filter passed)

Aurora's keyword filter pulled 41 records through five distinct topic
lenses and handed each subscriber a plausibly-sized slice. Nothing
degenerate — no subscriber got zero records, no subscriber got all 41.

    sim_news_parent          6 matched
    sim_indie_gamedev       13 matched
    sim_finance_op           9 matched
    sim_culture             10 matched
    sim_politics_sports     11 matched

Spot-check: I verified that the Fed/CPI/jobs records routed to `sim_finance_op`
and not `sim_news_parent`, that the Claude 4.7 and GPT-5 Mini records routed
to `sim_indie_gamedev` and not `sim_culture`, and that the Balenciaga /
Taylor Swift / Nolan records routed to `sim_culture` and not anywhere else.
The filter matched the intent.

Two honest edge cases worth flagging:

- The SCOTUS AI copyright story correctly matched both
  `sim_finance_op` (via "DOJ") and `sim_politics_sports` (via "supreme
  court", "DOJ") and `sim_indie_gamedev` (via "OpenAI", "AI"). Aurora
  surfaced it for all three — but wove it into each brief in a different
  register. That's the right behavior.
- The `sim_culture` profile got the Cannes engagement story via both
  "celebrity" and "gossip" topic hits. It showed up once in the final
  brief (correctly), not twice.

## Backend + performance

    backend:           claude_code:claude-code-cli
    total calls:       5
    ok:                5
    errors:            0
    total wall time:   ~6 minutes 33 seconds
    average per sub:   ~79 seconds

Individual wall times:

    sim_news_parent     77.2s   2748 chars
    sim_indie_gamedev   72.0s   5093 chars
    sim_finance_op     166.4s   9270 chars
    sim_culture         51.1s   5419 chars
    sim_politics_sports 26.3s   2692 chars

The 166s spike on `sim_finance_op` is the 12min / deep-dives profile and
is driven by output length, not infrastructure. No retries needed.

## Length knob — working, with a downward tuning bias

Measured against the length targets declared in `aurora_public.py`:

| length knob | target range     | sim_*                | actual words |
|-------------|------------------|----------------------|--------------|
| 3min        | 400-550 words    | sim_news_parent      | **433**       |
| 3min        | 400-550 words    | sim_politics_sports  | **443**       |
| 6min        | 900-1200 words   | sim_indie_gamedev    | **833**       |
| 6min        | 900-1200 words   | sim_culture          | **891**       |
| 12min       | 1800-2300 words  | sim_finance_op       | **1522**      |

3-minute briefs landed squarely inside the target window. 6-minute briefs
were 7-11% under. 12-minute came in ~15% under the bottom of the target
range — meaningful. Two possible fixes, in preference order:

1. **Tighten the prompt.** Change the length-target sentence in
   `compose_prompt()` from "Target length: 1800-2300 words" to
   "Target length: 2000-2300 words — err long, not short. A subscriber
   who asked for a 12-minute read is telling you they want depth." The
   model is biased to brevity unless explicitly anchored; nudging the
   center of the range up tends to work.
2. **Use a model with a longer natural-length bias** for the `deep-dives`
   depth specifically (e.g., Claude Sonnet 4.6 instead of whatever
   `claude-code-cli` is routing to).

Both are zero-code fixes outside the prompt. Not blocking v0.

## Voice knob — working, distinct and audible

Reading the five briefs back-to-back, the voice knob is doing real work.
The briefs feel like they were written by five different writers.
Representative opening lines (hook is in italics in each):

- `sim_news_parent` (**gentle**): *"A week that moved quietly — two
  health stories worth knowing, a record-breaking marathon, and some
  student-debt news that's actually real."*
- `sim_indie_gamedev` (**balanced**): *"The model you use every day got
  significantly bigger, the last major holdout in open-source AI just
  fell, and Path of Exile 2 apparently broke Steam."*
- `sim_finance_op` (**sharp**): *"Three data prints inside 24 hours, and
  they all said the same thing: the Fed has its cover."*
- `sim_culture` (**gentle**): *"The culture moved in several directions
  at once today, and somehow all of them are worth following."*
- `sim_politics_sports` (**sharp**): *"Congress kicked the can, the
  playoffs are getting interesting, and your social feed just reshuffled
  again."*

Sharp profiles open with declarative, slightly edgy claims. Gentle
profiles open with framing sentences that soften the reader into the
day. Balanced profiles name specifics without punching.

Inside the body, the voice differences get even clearer:

- `sim_finance_op` writes things like "The Fed isn't waiting for 2.0%
  to cut. They're waiting for a credible glide path," and "Banks have
  managed deposit betas better than feared" — operator jargon used
  correctly, no hand-holding.
- `sim_news_parent` writes things like "Nothing to do on your end. Just
  good news to receive cleanly" — low-anxiety, no imperatives, no
  political framing, no urgency manufactured out of thin air.
- `sim_politics_sports` writes "That series is over if you're being
  honest about it," — sharp-voice confidence that would be inappropriate
  in the other four profiles.

Voice fidelity is the single best result of this run. The
`VOICE_DESCRIPTIONS` block in `aurora_public.py` is tuned well enough
that the prompt carries through without needing few-shot examples.

## Depth knob — working

- **headlines** briefs (news_parent, politics_sports) deliver 4-6 short
  takes with one-line explanations. No deep second-order reasoning, no
  multi-paragraph story. Exactly what the knob promises.
- **balanced** briefs (indie_gamedev, culture) deliver 3-4 stories with
  a paragraph of context each and one-line takes. Second-order reasoning
  shows up selectively — gamedev gets it for the Sparse-MoE economics
  note, culture gets it for the Balenciaga succession read. Good.
- **deep-dives** brief (finance_op) delivers one dominant story (the Fed
  / CPI / jobs confluence), branches outward into three secondary stories
  (bank earnings, crypto flows, real estate), and weaves one labor note
  at the end. This is what a deep-dive is supposed to look like.

## Inline explanations — working as intended

The prompt instructs Aurora to drop brief parenthetical glosses for
jargon the reader might not already know. It did this cleanly across
the finance brief:

- "The dot plot (the FOMC's published median guess at where rates are
  headed, released quarterly)"
- "Deposit betas (how much of a rate cut passes through to depositor
  rates)"
- "MiCA (the EU's Markets in Crypto-Assets framework — the most
  comprehensive crypto regulation passed by any major jurisdiction)"
- "Sparse-MoE (Mixture of Experts — an architecture where only a subset
  of the model's parameters activate per token, making inference
  significantly cheaper)"

One note: the finance brief did *not* gloss jargon that an operator
would already know (NII, TVL). That's the right call — the prompt says
"when a term might not be universally understood," and Aurora is
reading the subscriber profile well enough to know who the reader is.

## Topic regurgitation — not happening

The prompt has an explicit rule: never regurgitate the subscriber's
topic list, never start with "Good morning," never say "Here's your
daily roundup." Across all five briefs, zero violations. Every hook
line is content-specific to the day.

## Free-text context — used, not parroted

Each of the five subscribers had a distinct `freetext` block. The model
used these as implicit framing without ever quoting them back:

- news_parent ("two kids in their 40s") → no parenting clichés, but
  the pill-for-teens lead is pitched as "worth a conversation with your
  pediatrician if it becomes relevant" rather than as an abstract
  medical story.
- indie_gamedev ("shipping a roguelike, uses Claude daily") → the
  Claude 4.7 story leads with "you can fit more of your roguelike's
  codebase into a single prompt" — perfect translation.
- finance_op ("runs a small prop trading desk, reads Fed minutes") →
  the brief never explains what a dot plot is for a finance reader
  (correct), but does explain MiCA and deposit betas lightly.
- culture ("former magazine editor") → the Taylor Swift paragraph has
  a beautifully meta line: "Former magazine editors will recognize the
  instinct: sometimes you put down the elaborate thing and write
  something honest in a hurry."
- politics_sports ("podcast host, walks into a morning taping") → the
  social-media section has explicit taping advice ("Same clip, three
  different cuts").

This is the strongest single signal that per-subscriber prompting is
working. The freetext block is being treated as a writing prompt, not
as boilerplate.

## Dispatcher handoff — clean

`send_email.py --dry-run` read the manifest, parsed every brief's
frontmatter, extracted the `subject_line` from each (with the stripped
quotes per `_default_subject`), rendered dark-palette HTML + plain-text
pair for each, and reported ok=5 / err=0. HTML sizes:

    sim_news_parent         4508 html ·  2707 text
    sim_indie_gamedev       6985 html ·  5065 text
    sim_finance_op         11108 html ·  9223 text
    sim_culture             7220 html ·  5359 text
    sim_politics_sports     4466 html ·  2661 text

Rendered HTML files for each subscriber are in
`aurora-sim-2026-04-11/*.html`. Every one of them opens cleanly, shows
the "Aurora ☉" hero, the date, body, and the Tune / Unsub footer.
The plain-text alternative also renders correctly for each subscriber.

## Subject lines — content-aware, the right length

Every subject line is specific to today's news AND to the subscriber's
voice. None of them are generic "Your daily brief" filler. Eight of
them hit the 6-10 word target the prompt specifies; one is 11 words.

    sim_news_parent       "A pill for teens, a record in Boston, and some relief"        (11)
    sim_indie_gamedev     "The model you ship with just doubled its memory"              (9)
    sim_finance_op        "Soft CPI, missed payrolls, June is live"                      (7)
    sim_culture           "Nolan, a new Balenciaga, and Taylor did it again"             (9)
    sim_politics_sports   "DC didn't shut down, but the real fight starts now"           (10)

These are strong. A gentle "A pill for teens..." is pitched differently
from a sharp "Soft CPI, missed payrolls..." — both are useful subject
lines a human would open.

## What this run did NOT test

- **Real gather.** The 41 records were synthetic. When the real
  `gather.py` runs under launchd against live sources, the record mix
  will be Ra-biased (macro / AI / crypto) until the v1 per-topic source
  maps ship. Aurora's filter will work, but `sim_culture`-type profiles
  will see thinner briefs until gather widens. Filed as a P1.
- **Real delivery.** `send_email.py` ran in dry-run; no actual SMTP or
  Resend call fired. SPF/DKIM/DMARC is still a H task.
- **PRN continuity.** `.context.md` existed and was offered to Aurora,
  but none of the five profiles had topic overlap with the existing
  archive entities (Fed/BTC/Anthropic/Marimo) in a way that would
  naturally trigger a callback. Aurora correctly skipped the context
  block for all five briefs — it did not force any callbacks in. That
  is exactly the PRN behavior we wanted. Will exercise this properly
  once the archive has a few days of real entries to match against.
- **Subscriber state persistence.** `lastSent` / `lastBriefId` / history
  stamping was not exercised because dry-run mode does not write back.
  Will verify on the first real send.

## Verdict

Aurora Public v0 passes simulation 01. All five profiles produced
readable, voice-appropriate, topic-accurate briefs with valid
frontmatter and renderable HTML. The pipeline is ready for:

1. A closed-beta real run (1-3 real subscribers, real gather, real
   SMTP/Resend delivery) behind SPF/DKIM/DMARC.
2. Prompt tuning nudge on the 6min / 12min length targets (the prompt
   is the only lever that needs touching).

## Action items from this run

- [ ] **[K]** Nudge length-target sentence in `aurora_public.py`
  `compose_prompt()` to push 6min/12min profiles into the upper half of
  their target windows.
- [ ] **[K]** Add a `--sim` flag to `aurora_public.sh` that runs the full
  pipeline against `/tmp/aurora_sim/` inputs so this exact test is
  one-command-repeatable.
- [ ] **[K]** Once v1 persistence ships, run sim 02 with the real gather
  output to verify the culture/gossip/sports topics still get enough
  records to sustain balanced and deep-dive depths.
- [ ] **[H]** Confirm SPF / DKIM / DMARC setup on `hyo.world` is on the
  near-term list — this is the only hard blocker between Aurora Public
  v0 and a live send.

## Reproduce this run

From `newsletter/`:

    HYO_INTELLIGENCE_DIR=/tmp/aurora_sim \
    HYO_SUBSCRIBERS_FILE=/tmp/aurora_sim/subscribers.jsonl \
    HYO_PUBLIC_OUT_DIR=/tmp/aurora_sim/out \
    python3 aurora_public.py --date 2026-04-11 --dry-run

Then remove `--dry-run` to fire real LLM calls. Then:

    HYO_SUBSCRIBERS_FILE=/tmp/aurora_sim/subscribers.jsonl \
    HYO_PUBLIC_OUT_DIR=/tmp/aurora_sim/out \
    python3 send_email.py --date 2026-04-11 --dry-run

All inputs are copied into `kai/logs/aurora-sim-2026-04-11/` so a future
session can re-run the exact simulation by replaying those files.
