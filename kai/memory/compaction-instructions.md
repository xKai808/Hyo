# Compaction Instructions for Cowork Sessions
# Used by Anthropic's built-in Compaction API when context grows long
# Reference: CLAUDE.md hydration protocol

## PRESERVE VERBATIM (never summarize these)
- All ticket IDs (TASK-YYYYMMDD-*)
- All git commit SHAs
- Protocol versions (e.g. PROTOCOL_DAILY_ANALYSIS.md v2.6)
- Exact error messages Hyo reported
- Explicit corrections Hyo made ("You said X but actually Y")
- Open P0/P1 tickets (title + status)
- Current system health values (credits remaining, SICQ scores)
- Specific file names that were modified

## PRESERVE AS STRUCTURED SUMMARY
- What shipped this session (function/file → what it does, one line each)
- What Hyo approved or rejected (decision + reason)
- Bugs found and how fixed
- Current verified-state values: credits, scores, report freshness

## DISCARD COMPLETELY
- Intermediate reasoning chains that led to a decision (keep only the decision)
- Repeated tool call results (keep only final successful result)
- Failed attempts before the working solution
- Generic explanations Kai gave that are already in KNOWLEDGE.md
- Tool call outputs that were just verification (e.g. "SYNTAX OK")
- Pleasantries and session management messages

## AFTER COMPACTION: KAI MUST BE ABLE TO ANSWER
- What is the Anthropic credit balance?
- What was the last thing shipped (with commit SHA)?
- What is the top open P0?
- What did Hyo explicitly say NOT to do this session?
- What protocol version is currently active for each agent?
