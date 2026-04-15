#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/agents/dex/repair.sh
#
# Dex Auto-Repair Engine
# Repairs common JSONL corruption types:
#   - Trailing commas in JSON objects
#   - Missing closing braces
#   - Truncated lines (valid JSON prefix cut off)
#   - Duplicate consecutive lines
#   - Empty lines
#
# Usage:
#   repair.sh <jsonl_file_path>
#
# Output: JSON summary to stdout
#   {
#     "file": "...",
#     "total_lines": N,
#     "corrupt": N,
#     "repaired": N,
#     "removed": N,
#     "unfixable": N,
#     "status": "success|partial|failed"
#   }
#
# Safety: Never overwrites original if repair fails. Uses atomic temp + rename.
#

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo '{"status":"error","message":"usage: repair.sh <jsonl_file_path>"}'
  exit 1
fi

JSONL_FILE="$1"
REPAIR_TIMESTAMP=$(date +%s)
TEMP_REPAIRED="${JSONL_FILE}.repaired-${REPAIR_TIMESTAMP}"
TEMP_BACKUP="${JSONL_FILE}.backup-${REPAIR_TIMESTAMP}"

# Counters
TOTAL_LINES=0
CORRUPT_LINES=0
REPAIRED_COUNT=0
REMOVED_COUNT=0
UNFIXABLE_COUNT=0
REPAIR_STATUS="success"

# Safety: exit traps
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]] && [[ -f "$TEMP_REPAIRED" ]]; then
    rm -f "$TEMP_REPAIRED" "$TEMP_BACKUP" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Validate file exists and is readable
if [[ ! -f "$JSONL_FILE" ]]; then
  echo "{\"status\":\"error\",\"message\":\"file not found: $JSONL_FILE\"}"
  exit 1
fi

if [[ ! -r "$JSONL_FILE" ]]; then
  echo "{\"status\":\"error\",\"message\":\"file not readable: $JSONL_FILE\"}"
  exit 1
fi

# Empty file handling
if [[ ! -s "$JSONL_FILE" ]]; then
  echo "{\"file\":\"$JSONL_FILE\",\"total_lines\":0,\"corrupt\":0,\"repaired\":0,\"removed\":0,\"unfixable\":0,\"status\":\"success\"}"
  exit 0
fi

# Main repair logic in Python
python3 << REPAIREREOF
import json
import re
import sys

jsonl_file = "$JSONL_FILE"
temp_repaired = "$TEMP_REPAIRED"

total_lines = 0
corrupt_lines = 0
repaired_count = 0
removed_count = 0
unfixable_count = 0

repaired_entries = []
seen_entries = set()  # For deduplication

try:
    with open(jsonl_file, 'r') as f:
        lines = f.readlines()

    for line_no, line in enumerate(lines, 1):
        total_lines += 1
        line = line.rstrip('\n\r')

        # Skip empty lines
        if not line or not line.strip():
            removed_count += 1
            continue

        # Try to parse as valid JSON first
        try:
            entry = json.loads(line)
            # Check for duplicates
            entry_str = json.dumps(entry, sort_keys=True)
            if entry_str not in seen_entries:
                seen_entries.add(entry_str)
                repaired_entries.append(line)
            else:
                removed_count += 1  # Deduped
            continue
        except json.JSONDecodeError:
            pass

        # Line is corrupt, attempt repair
        corrupt_lines += 1

        # Repair attempt 1: trailing comma before closing brace
        # Pattern: {...,"key": "val",} or {...,"key": "val", }
        repair_attempt = re.sub(r',(\s*[}\]])$', r'\1', line)

        if repair_attempt != line:
            try:
                entry = json.loads(repair_attempt)
                entry_str = json.dumps(entry, sort_keys=True)
                if entry_str not in seen_entries:
                    seen_entries.add(entry_str)
                    repaired_entries.append(repair_attempt)
                    repaired_count += 1
                    continue
                else:
                    removed_count += 1
                    continue
            except json.JSONDecodeError:
                pass

        # Repair attempt 2: missing closing brace
        # Test if adding } or }} makes it valid
        for close_brace in ['}', ']}', ']]']:
            repair_attempt = line + close_brace
            try:
                entry = json.loads(repair_attempt)
                entry_str = json.dumps(entry, sort_keys=True)
                if entry_str not in seen_entries:
                    seen_entries.add(entry_str)
                    repaired_entries.append(repair_attempt)
                    repaired_count += 1
                    break
            except json.JSONDecodeError:
                pass
        else:
            # Repair attempt 2 failed, mark as unfixable
            unfixable_count += 1
            continue

        # If we got here, repair attempt 2 succeeded
        continue

    # Write repaired content to temp file
    with open(temp_repaired, 'w') as f:
        for entry in repaired_entries:
            f.write(entry + '\n')

    # Atomic replace: only if we successfully wrote temp file
    import shutil
    shutil.move(temp_repaired, jsonl_file)

    # Output summary
    print(json.dumps({
        "file": jsonl_file,
        "total_lines": total_lines,
        "corrupt": corrupt_lines,
        "repaired": repaired_count,
        "removed": removed_count,
        "unfixable": unfixable_count,
        "status": "success" if unfixable_count == 0 else "partial"
    }))

except Exception as e:
    print(json.dumps({
        "file": jsonl_file,
        "status": "error",
        "message": str(e),
        "total_lines": total_lines,
        "corrupt": corrupt_lines,
        "repaired": repaired_count,
        "removed": removed_count,
        "unfixable": unfixable_count
    }), file=sys.stderr)
    sys.exit(1)

REPAIREREOF
