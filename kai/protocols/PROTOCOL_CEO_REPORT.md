# PROTOCOL_CEO_REPORT.md — Kai Daily CEO Report
# VERSION: v1.0 | Author: Kai | Created: 2026-04-23

## PURPOSE
Governs the daily CEO report published by Kai at 23:30 MT.
Distinct from the morning report (05:00 MT summary for Hyo).
The CEO report covers decisions made, work delegated, system changes, and what Kai is tracking.

## REQUIRED FEED SCHEMA
```json
{
  "type": "ceo-report",
  "author": "Kai",
  "sections": {
    "decisions": "What Kai decided autonomously this session",
    "delegated": ["what was delegated to which agent"],
    "system_changes": "What structural changes were made to code or protocols",
    "tracking": "What Kai is watching that Hyo should know about",
    "blockers": "What requires Hyo's input or approval"
  }
}
```

## GATES BEFORE PUBLISH
1. decisions field is non-empty
2. At least one of: delegated, system_changes, or tracking is non-empty
3. blockers explicitly states 'none' or lists real blockers — never omitted

## VERSION HISTORY
| v1.0 | 2026-04-23 | Initial — created during JSON/Protocol alignment audit |
