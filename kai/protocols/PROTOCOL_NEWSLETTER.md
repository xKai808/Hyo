# PROTOCOL_NEWSLETTER.md — Ra Newsletter Protocol
#
# VERSION: v1.0
# Author: Kai | Created: 2026-04-23
# Canonical: kai/protocols/PROTOCOL_NEWSLETTER.md
#
# PURPOSE: Governs the Ra newsletter product — schema, content requirements,
#   rendering rules, and gate conditions for HQ publication.
#   Companion to PROTOCOL_PODCAST.md (audio) and PROTOCOL_HQ_PUBLISH.md (gate).

---

## PART 1 — FEED ENTRY SCHEMA (MANDATORY FIELDS)

Every `newsletter` type entry published to feed.json MUST contain:

```json
{
  "id": "newsletter-ra-YYYY-MM-DD",
  "type": "newsletter",
  "author": "Ra",
  "authorIcon": "📰",
  "date": "YYYY-MM-DD",
  "sections": {
    "summary": "1-2 sentence BLUF of today's brief",
    "stories": [
      {
        "title": "Story title (≤60 chars)",
        "take": "1-2 sentence human take on the story",
        "watch": "What to watch for (optional)",
        "category": "tech|ai|macro|crypto|apps|other"
      }
    ],
    "topics": ["tag1", "tag2"],
    "readLink": "/daily/newsletter-YYYY-MM-DD"
  }
}
```

**Gate question:** Does sections.stories exist and have ≥1 item? NO → block publish.
**Gate question:** Does sections.summary exist and is non-empty? NO → block publish.
**Gate question:** Does sections.readLink point to an accessible HTML file? NO → block publish.

---

## PART 2 — CONTENT REQUIREMENTS

**Summary (BLUF):** Must state (1) number of stories and (2) lead topic. Max 2 sentences.

**Stories:** 3-5 per newsletter. Each story must have:
- `title`: The topic, not the headline
- `take`: Ra's original analysis (not a summary of the source)
- `category`: One of the allowed values (lowercase)

**Forbidden in published output:**
- Code fences (```yaml, ```json) — synthesize.py strip_llm_artifacts() handles this
- YAML front-matter metadata blocks
- "Here is your newsletter:" preamble text
- Raw URLs without context

---

## PART 3 — RENDERING (HQ)

The `renderNewsletter(s, report)` function in hq.html handles this type.
- Summary rendered as `<p>` with `font-weight:500`
- Stories rendered as styled cards with category color borders
- Topics rendered as chip badges
- readLink rendered as a "Read full brief" button pointing to `/daily/newsletter-YYYY-MM-DD`

**Terminal font root cause (fixed 2026-04-23):**
- synthesize.py emits unclosed ```yaml block → entire newsletter renders as `<pre><code>`
- Fixed: strip_llm_artifacts() in synthesize.py strips unclosed fences before write
- Fixed: render.py strip_preamble_code_blocks() handles unclosed fences as fallback

---

## PART 4 — GATES BEFORE PUBLISH

1. HTML file must exist at `website/daily/newsletter-YYYY-MM-DD.html`
2. HTML file must NOT contain `<pre><code` blocks at the top level
3. Feed entry must have all mandatory sections
4. Run through PROTOCOL_HQ_PUBLISH.md gates before writing to feed.json

---

## PART 5 — VERSION HISTORY

| Version | Date       | Change |
|---------|------------|--------|
| v1.0    | 2026-04-23 | Initial — created after audit found no standalone newsletter protocol |
