#!/usr/bin/env bash
# bin/validate-hq-js.sh — JS syntax gate for hq.html
# Run before EVERY commit that touches hq.html.
# Exit 1 if any <script> block has a syntax error.

set -uo pipefail
ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
FILE="${1:-$ROOT/agents/sam/website/hq.html}"

[[ ! -f "$FILE" ]] && echo "[validate-hq-js] ERROR: $FILE not found" >&2 && exit 1

ERRORS=$(python3 - "$FILE" << 'PYEOF'
import sys, re, subprocess, json

html_file = sys.argv[1]
with open(html_file) as f:
    html = f.read()

# Extract all <script> blocks (not type=module, not src=)
blocks = []
pos = 0
while True:
    start = html.find('<script', pos)
    if start == -1: break
    tag_end = html.find('>', start)
    tag = html[start:tag_end+1]
    end = html.find('</script>', tag_end)
    if end == -1: break
    if 'src=' not in tag and 'type=' not in tag:
        blocks.append((len(blocks)+1, html[tag_end+1:end]))
    pos = end + 9

errors = 0
for idx, content in blocks:
    # Write to temp file and use node to check syntax
    import tempfile, os
    with tempfile.NamedTemporaryFile(mode='w', suffix='.js', delete=False) as tmp:
        tmp.write(content)
        tmp_path = tmp.name
    result = subprocess.run(['node', '--check', tmp_path], capture_output=True, text=True)
    os.unlink(tmp_path)
    if result.returncode == 0:
        print(f'OK script {idx} ({len(content)} chars)')
    else:
        err = result.stderr.strip().split('\n')[0] if result.stderr else 'unknown error'
        print(f'FAIL script {idx}: {err}')
        errors += 1

sys.exit(errors)
PYEOF
)
EXIT=$?
echo "$ERRORS"
[[ $EXIT -eq 0 ]] && echo "[validate-hq-js] PASS — all script blocks valid" && exit 0
echo "[validate-hq-js] FAIL — fix JS errors before committing hq.html" >&2 && exit 1
