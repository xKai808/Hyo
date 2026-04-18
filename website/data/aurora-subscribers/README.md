# aurora-subscribers/

Each file in this directory is a subscriber record: `{sub_id}.json`

## File format

```json
{
  "id": "sub_abc123",
  "email": "user@example.com",
  "name": "Display Name",
  "created": "2026-04-17T06:30:00-06:00",
  "status": "active",
  "source": "aurora.html",
  "token_salt": "determined deterministically — see aurora-data.js",
  "interests": {
    "topics": ["ai", "tech", "startups"],
    "voice": "balanced",
    "depth": "balanced",
    "length": "6min",
    "freetext": "optional free-text keywords"
  },
  "delivery": {
    "channel": "page",
    "cadence": "daily",
    "sendAt": "06:30",
    "timezone": "America/Denver"
  },
  "lastBriefDate": "2026-04-17",
  "briefs": [
    {
      "date": "2026-04-17",
      "subject": "Three AI stories that actually matter",
      "preview": "First 160 chars of the brief body...",
      "wordCount": 950,
      "file": "aurora-briefs/sub_abc123/2026-04-17.md"
    }
  ]
}
```

## Brief storage

Full brief markdown files live at:
  `data/aurora-briefs/{sub_id}/{YYYY-MM-DD}.md`

## Token auth

Tokens are derived deterministically:
  `sha256(sub_id + AURORA_TOKEN_SALT)[0:24]`

This means no token column in the subscriber record —
generate it fresh on every validation from the env secret.

## Created by

`aurora-subscribe.js` creates the base record on first subscribe.
`aurora_public.py::publish_to_page()` appends briefs after generation.
