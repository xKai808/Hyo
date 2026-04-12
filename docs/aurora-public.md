# Aurora Public — design doc

*Author: Kai · Last updated: 2026-04-11*

## What this is

Ra (internal, Hyo-only) is a single daily brief about macro, finance, AI, and tech — the things Hyo specifically cares about.

**Aurora Public** is Ra's consumer-facing sibling. It's the same underlying pipeline — gather, persist, synthesize, archive — but every subscriber gets a brief tuned to their own topics, voice preferences, length, and depth. One engine, many briefs.

The product promise is simple enough to say in one line:

> Every morning, Aurora reads the world for you — only the parts you actually care about — and writes you a short brief in the voice you like. She remembers what she told you yesterday so she doesn't repeat herself.

Delivery is email first. Podcast is next (text-to-speech over the same synthesized brief, per-subscriber).

## Non-goals

- Not a feed reader. Aurora is opinionated, not neutral.
- Not a forwarding service. Nothing Aurora sends is just a link + headline.
- Not a dashboard. There is no app to log into. Aurora is a brief that arrives in your inbox.
- Not a personalization black box. The subscriber always knows what Aurora is tracking for them and can adjust in one tap.

## The intake problem

Forms are boring. Forms feel like paperwork. Forms are where people bounce.

But we do need structured data — topics, tone, length, depth, email — to generate a useful brief. The solution is a single page that *feels* like a chat but collects answers at the speed of a tap.

### Intake flow (first-run)

A single full-screen page at `hyo.world/aurora`. No multi-step wizard, no progress bar. The page reads like Aurora is introducing herself, and the subscriber answers by tapping.

```
        ·  ·  ·

  Hi, I'm Aurora. Every morning
  I read the world for you, then
  write you a short brief about
  the parts you actually care
  about. Let's figure out what
  I should bring you.

  ──────────────

  What makes you lean in?
  (pick as many as you want)

  [ politics ]  [ sports ]  [ finance ]
  [ AI ]  [ tech ]  [ crypto ]  [ startups ]
  [ fashion ]  [ gossip ]  [ social media ]
  [ health ]  [ science ]  [ music ]
  [ film & tv ]  [ food ]  [ travel ]
  [ gaming ]  [ books ]  [ design ]
  [ climate ]  [ space ]  [ real estate ]
  [ culture wars ]  [ labor & jobs ]

  ──────────────

  How edgy do you want my voice?
  ( gentle · balanced · sharp )

  ──────────────

  How deep should I go?
  ( headlines only · balanced · deep dives )

  ──────────────

  How long should each brief be?
  ( 3-min read · 6-min read · 12-min read )

  ──────────────

  Anything I should know about you?
  [ optional · 240 char free-text ]

  ──────────────

  Where should I send it?
  [ email ]

  [ Start my morning ]

        ·  ·  ·
```

Every control is a tap, a toggle, or one short text field. Total interaction time should be under 60 seconds. The free-text field is the only typing on the page; it's optional and exists specifically to capture *voice* signal the structured answers can't — occupation, specific obsessions, things to avoid, people they follow.

### Why not a form

Forms are rigid because they pretend every user fits the same slots. The chat framing is a small lie that unlocks a better UX: the user feels like they're talking to Aurora, not filling out a survey, and because she "asked" they're more forthcoming in the free-text.

### Why one page, not multi-step

Multi-step wizards lose 15-30% of users per step. A single page with progressive reveal (next block fades in when the previous block is touched) keeps the mental model of "this is fast" intact. The whole page scrolls if needed but nothing is hidden behind a Next button.

## Data model

Every subscriber becomes one record. MVP: JSONL on disk (the same pattern the rest of the stack uses). Follow-up: Vercel KV or Postgres when persistence becomes a P1.

```json
{
  "id": "sub_26k1q_9f8a2lx",
  "email": "alex@example.com",
  "created": "2026-04-11T19:04:17Z",
  "status": "active",
  "interests": {
    "topics": ["ai", "startups", "crypto", "film-and-tv"],
    "voice": "sharp",
    "depth": "balanced",
    "length": "6min",
    "freetext": "indie game dev, very online, hates crypto hype but pays attention to infra"
  },
  "delivery": {
    "channel": "email",
    "cadence": "daily",
    "sendAt": "06:30",
    "timezone": "America/Denver"
  },
  "lastSent": null,
  "lastBriefId": null,
  "history": []
}
```

Subscribers are stored at `newsletter/subscribers.jsonl` on the runtime host (one JSON object per line, append-only). `newsletter/aurora_public.py` reads the file, filters to `status: active`, and generates one brief per line.

The Vercel subscribe endpoint (`/api/aurora-subscribe`) initially logs + returns 200 + emits a ticket id. Follow-up: write subscribers to Vercel KV and have the Mini pull from there.

## Topic taxonomy

Topics are chosen from a fixed vocabulary so the generator can reliably filter gather records and the archive can reliably slot entities under topics. MVP vocabulary:

```
politics · finance · macro · crypto · stocks · startups · tech · ai
social-media · fashion · gossip · celebrity · entertainment
film-and-tv · music · books · gaming · sports
health · fitness · food · travel
science · climate · space · design · architecture
real-estate · labor · culture-wars · education
```

Each topic maps to a set of gather keywords + allowlisted sources. E.g. `fashion` → `["fashion", "runway", "haute couture", "streetwear", "designer"]` plus sources `[vogue, businessoffashion, hypebeast, ...]`.

Gather is still a single shared run — we don't run gather per subscriber. Instead, the gather stage pulls a wide net (every topic in the vocabulary has at least 3 sources), and the per-subscriber generator filters down.

## Generation pipeline

```
┌────────────────┐
│  gather.py     │  once per day, wide net
│  (shared)      │  → today.jsonl
└────────┬───────┘
         │
         ▼
┌────────────────┐
│ ra_context.py  │  PRN continuity from archive
│ (per subscriber)│  → .context.<sub_id>.md
└────────┬───────┘
         │
         ▼
┌────────────────────┐
│ aurora_public.py   │  one LLM call per subscriber
│  - load profile    │  → briefs/<date>/<sub_id>.md
│  - filter gather   │
│  - build prompt    │
│  - call LLM        │
│  - render HTML     │
└────────┬───────────┘
         │
         ▼
┌────────────────┐
│ send_email.py  │  delivers to subscriber's inbox
│                │  → mark lastSent
└────────┬───────┘
         │
         ▼
┌────────────────┐
│ ra_archive.py  │  one archive, shared across
│ (Hyo-voice only)│  subscribers. Only Ra's own
│                │  brief fills the archive.
└────────────────┘
```

### Why only Ra (Hyo-voice) fills the archive

Aurora Public runs hundreds of LLM calls per day — one per subscriber — each producing a brief tuned to that person. If we archived every brief, the archive would balloon and its signal would blur.

The archive is Kai's and Hyo's research notebook. It captures *what we think is true* about entities, topics, and capabilities. Ra's internal Hyo-voice brief is the one that makes those judgments crisply, so Ra is the sole archive author. Aurora Public *reads* from the archive (for continuity and fact-grounding) but doesn't *write* to it.

One corollary: if a subscriber's topic area is one Ra never covers (gossip, fashion), the archive has no prior takes for them. That's fine — Aurora Public still gets the trend pulse and lab notes as loose context, and the gather records are always fresh.

## Voice and length knobs

The synthesis prompt takes three knobs from the subscriber profile:

- **voice**: `gentle` | `balanced` | `sharp`
  - *gentle*: warm, careful, no political jabs, light-touch humor
  - *balanced*: Ra's default — opinionated but not provocative
  - *sharp*: edgy, first-mover, willing to call things dumb
- **depth**: `headlines-only` | `balanced` | `deep-dives`
  - *headlines-only*: one-line takes, no analogies, no lab section
  - *balanced*: 2-3 stories with light context + a lab item
  - *deep-dives*: one dominant story with real explanation + a lab item + a "worth sitting with" closing
- **length**: `3min` | `6min` | `12min` → target word counts 500, 1100, 2200

The generator composes a short system-prompt header that encodes these and prepends it to the core Ra synthesis prompt. The rest of the prompt — especially the archive contract and the PRN continuity rules — stays identical.

## Email template

A clean, readable HTML email that degrades to plaintext. No tracking pixels, no marketing fluff, no images-as-layout. The template is deliberately spartan:

```
Subject: {subject_line}    (generated by LLM as part of synthesis)

--- plain text ---
Good morning, {first_name}.

{brief body}

--
Aurora ☉ read the world for you this morning.
Tune her: hyo.world/aurora/tune/{unsub_token}
Pause or unsubscribe: hyo.world/aurora/unsub/{unsub_token}
```

(The ☉ is the only visual flourish — a unicode sun, not an image.)

The HTML version wraps the same content in a 580px-wide single-column layout with a serif display font for the hook and a monospace voice for the section markers. Matches `ra-email.css` (to be created alongside `render.py`).

## Security, privacy, deliverability

- Emails are the only PII we store. Name is optional (free-text field extraction). We do not store IP, user agent, device fingerprint, referral.
- Every email has a one-tap unsubscribe via a signed token. No login required to unsubscribe.
- Every email has a one-tap "tune" link that loads the intake page pre-filled with the subscriber's current profile. Changing any control updates the record.
- Subscribers are never shared, never sold, never aggregated into a profile beyond what this file describes.
- SPF / DKIM / DMARC must be configured on `hyo.world` before we send at any real volume. MVP is fine to send from `aurora@hyo.world` via Resend or similar — both handle signing out of the box.

## What ships in v0 (this session)

- `docs/aurora-public.md` — this file
- `website/aurora.html` — the intake page
- `website/api/aurora-subscribe.js` — the signup endpoint
- `newsletter/aurora_public.py` — per-subscriber generator
- `newsletter/send_email.py` — email dispatcher (SMTP + Resend backends)
- `newsletter/aurora_public.sh` — pipeline wrapper
- `newsletter/subscribers.jsonl` — empty file placeholder, real subscribers appended here

## What's explicitly v1 (next session)

- Persistent subscriber storage (Vercel KV or GitHub via @octokit)
- The `/tune` flow (intake page loads pre-filled from token)
- The `/unsub` flow (one-tap unsub endpoint)
- Real email deliverability setup (SPF/DKIM/DMARC on hyo.world)
- Automated per-topic source maps for gather so gather actually pulls the wide net
- Per-subscriber rate tracking so Aurora doesn't send if a subscriber's inbox bounces twice in a row

## What's v2+ (future)

- Podcast delivery: TTS the synthesized brief per subscriber, attach MP3 to the email or serve as RSS
- Cross-subscriber trend signals (when 20% of subscribers have the same topic ping, Ra picks it up)
- Subscriber-facing archive: "what did Aurora tell me last week about X?"
- Paid tier: deeper briefs, earlier delivery, longer archive window
- Hyo.world agent page for Aurora Public as a featured public agent

## Open questions (for Hyo to resolve when convenient, not blocking v0)

1. Do we want Aurora Public to *look* like Ra (same dark/ochre palette) or have its own identity? Starting assumption: same family, slightly lighter — Ra is pre-dawn, Aurora is dawn.
2. Free or paid from day one? Starting assumption: free v0, paid tier comes when we have 100+ actives.
3. Which email provider? Resend is the modern serverless default; Postmark if we want the most boring reliable thing; SMTP via a provider we already pay for if that's cheaper. Starting assumption: Resend, because it has the cleanest API and takes three minutes to set up.
4. Do we need a landing page selling the product before the intake page, or is the intake page itself the landing page? Starting assumption: the intake page IS the landing page. The first block is the pitch; the rest is the onboarding.
