# Ra Research Archive

Persistent memory for Ra (aurora.hyo). Every time Ra produces a daily brief, the archive captures the raw signal, Kai's interpretations, and the durable capability notes so that nothing researched today is forgotten tomorrow.

**Core principle:** information is power; *information over time* is leverage. The archive turns Ra from "today's news briefing" into "a growing library that shows trends, movements, and directions."

**Read access:** any Claude session, any sub-agent, any employee — everything is plain markdown, grep-able, and committable to git.

## Layout

```
kai/research/
├── README.md              ← this file
├── index.md               ← auto-generated master index (rebuilt every run)
├── trends.md              ← auto-generated rolling trend report
│
├── briefs/                ← symlinks/pointers to ../../newsletters/YYYY-MM-DD.md
│
├── raw/                   ← YYYY-MM-DD.jsonl copies of gather output
│
├── entities/              ← per-entity running timelines
│   └── <slug>.md          ← e.g. fed.md, bitcoin.md, marimo.md
│
├── topics/                ← per-topic running timelines
│   └── <slug>.md          ← e.g. macro-rates.md, agent-supply-chain.md
│
└── lab/                   ← durable capability notes
    └── <slug>.md          ← e.g. ai-scientist-v2.md, browser-extension-risk.md
```

## How each file is structured

### `entities/<slug>.md`

A running timeline of every Ra take on one entity. Chronological, newest-first. Each entry:

```markdown
### 2026-04-11 — Ra v2
**Brief:** [2026-04-11](../../../newsletters/2026-04-11.md)
**Take:** <one-sentence summary of Ra's interpretation that day>
**Data:** <one-line factual snapshot, e.g. "Held 3.50–3.75%, dot plot unchanged">
**Hinge:** <what catalyst Ra named as the next inflection point>
**Confidence:** <low / medium / high>
```

Entities have aliases so `fed`, `FOMC`, `Powell's Fed`, and `central bank` all point to the same file.

### `topics/<slug>.md`

Same shape but topic-level — "agent-supply-chain" as a theme, not "Marimo" as an entity. Topics cluster related entities and let us see *category-level* movement over time.

### `lab/<slug>.md`

Durable capability notes. One file per new capability/technique/tool. Appended when Ra discovers it, updated whenever we learn more. Template:

```markdown
# Lab: <name>

## First seen
2026-04-11 · Ra brief

## What it is
<plain-language description>

## Why it's interesting
<the real mechanism, not the hype>

## When we'd reach for it
<concrete problem shapes where this is the right tool>

## Limitations
<known tradeoffs, failure modes>

## References
- [Brief YYYY-MM-DD](../../../newsletters/YYYY-MM-DD.md)
- external links, papers, implementation notes

## Related
<links to other lab entries>
```

### `index.md`

Auto-generated every Ra run. Lists all entities, topics, and lab entries with their last-seen date and brief count. Sortable by recency.

### `trends.md`

Auto-generated every Ra run. Computes rolling counts of how often each entity/topic has appeared over the last 7, 30, and 90 days and flags:

- **Rising:** appearing more frequently recently
- **Falling:** appearing less frequently recently
- **Steady:** consistent presence
- **New this week:** first appearance in the last 7 days

This is the "show us directions, trends, movements" feature. It's mechanical — no interpretation, just counts and deltas — which means Ra itself can *read* it each morning and decide what to write about.

## The loop

Every time `newsletter.sh` runs, three things happen in order:

1. **Pre-synthesize: `ra_context.py`** reads today's raw gather records, matches entities/topics against the archive, and writes `kai/research/.context.md`. This file holds the "prior takes" block that gets injected into synthesize's context so Ra can say *"last time we covered the Fed on April 11, we said X; today's update is Y."*

2. **Synthesize** runs normally but is instructed by the prompt to use `.context.md` if present and to output structured metadata (entities, topics, lab items) in the brief's frontmatter.

3. **Post-render: `ra_archive.py`** parses the rendered brief's frontmatter, appends timeline entries to every referenced entity/topic file, creates or updates lab files, rebuilds `index.md`, recomputes `trends.md`, and copies the raw gather jsonl into `kai/research/raw/`.

The archive grows one day at a time, automatically.

## CLI

```
kai ra search <query>     # grep the whole archive
kai ra entity <slug>      # show one entity's timeline
kai ra topic <slug>       # show one topic's timeline
kai ra lab <slug>         # show one lab entry
kai ra index              # show the master index
kai ra trends             # show the trend report
kai ra since <YYYY-MM-DD> # show everything archived since a date
```

## Why this matters

Without the archive, Ra forgets yesterday's research the moment it ships. With the archive, every brief *compounds*. Ra can cite its own prior takes, correct them when wrong, track trends that individual briefs can't see, and hand the whole library to any agent we spin up later. Six months from now, when we hit a block on a new project and need to know "what have we already learned about X," the answer is `kai ra search X` — not "let me re-research this from scratch."

That's the compounding loop. Information over time, organized, referenced, durable.
