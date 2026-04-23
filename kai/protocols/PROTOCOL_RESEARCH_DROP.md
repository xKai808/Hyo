# PROTOCOL_RESEARCH_DROP.md — Agent Research Drop Protocol
# VERSION: v1.0 | Author: Kai | Created: 2026-04-23

## PURPOSE
Governs research-drop entries published by any agent to the HQ Research tab.
A research-drop represents external intelligence that an agent gathered during its ARIC cycle.
It is NOT operational reporting — it is pure research output.

## REQUIRED FEED SCHEMA
```json
{
  "type": "research-drop",
  "author": "<agent>",
  "sections": {
    "topic": "What was researched (specific, not vague)",
    "finding": "The specific finding — what is true now that wasn't known before",
    "sources": ["URL1", "URL2"],
    "implication": "What this means for the system or Hyo",
    "confidence": "HIGH | MEDIUM | LOW"
  }
}
```

## THEATER GATE (enforced in publish-to-feed.sh)
- finding must not be 'conducting research' or 'researching topic'
- sources must contain at least 1 URL
- topic must be specific (not 'AI' or 'crypto')

## VERSION HISTORY
| v1.0 | 2026-04-23 | Initial — created during JSON/Protocol alignment audit |
