# PROTOCOL_SELF_IMPROVE_REPORT.md — Agent Self-Improvement Report Protocol
# VERSION: v1.0 | Author: Kai | Created: 2026-04-23

## PURPOSE
Governs self-improve-report entries published by agents after each improvement cycle.
These appear in HQ Research tab and tell Hyo what each agent learned and built.

## REQUIRED FEED SCHEMA
```json
{
  "type": "self-improve-report",
  "author": "<agent>",
  "sections": {
    "weakness": "W1/W2/W3 — weakness ID and title",
    "outcome": "what stage completed: research | implement | verify | resolved",
    "introspection": "what the agent learned about itself this cycle",
    "research": "what external sources informed the fix (with URLs)",
    "changes": "what code or config was changed — commit hash if shipped",
    "followUps": ["next concrete action"],
    "improvement_status": "current stage + confidence + ETA"
  }
}
```

## GATES BEFORE PUBLISH
1. weakness field contains a valid weakness ID (W1, W2, W3, E1, E2, E3)
2. outcome is one of: research, implement, verify, resolved
3. If outcome is 'resolved': changes field must contain a commit hash
4. Theater gate: changes must not say 'no changes' when outcome is 'implement'

## VERSION HISTORY
| v1.0 | 2026-04-23 | Initial — created during JSON/Protocol alignment audit |
