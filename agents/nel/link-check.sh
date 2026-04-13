#!/usr/bin/env bash
# agents/nel/link-check.sh — Comprehensive link validation for hyo.world
#
# Checks:
#   1. All internal HTML links (href/src) resolve to actual files
#   2. All markdown relative links resolve
#   3. All live URLs on hyo.world respond with 200
#   4. All fetch() paths in JavaScript have corresponding files
#   5. All API endpoints respond correctly
#
# Usage:
#   bash agents/nel/link-check.sh           # full check
#   bash agents/nel/link-check.sh --live    # include live HTTP checks
#   bash agents/nel/link-check.sh --quick   # local-only, no HTTP
#
# Output: JSONL to stdout, summary to stderr

set -uo pipefail

ROOT="${HYO_ROOT:-$HOME/Documents/Projects/Hyo}"
WEBSITE="$ROOT/website"
DOMAIN="https://www.hyo.world"
MODE="${1:---full}"
ERRORS=0
WARNINGS=0
CHECKED=0
REPORT_LINES=()

log_result() {
  local status="$1" file="$2" link="$3" detail="${4:-}"
  CHECKED=$((CHECKED + 1))
  if [[ "$status" == "FAIL" ]]; then
    ERRORS=$((ERRORS + 1))
    REPORT_LINES+=("FAIL|$file|$link|$detail")
  elif [[ "$status" == "WARN" ]]; then
    WARNINGS=$((WARNINGS + 1))
    REPORT_LINES+=("WARN|$file|$link|$detail")
  fi
}

# ---- Phase 1: HTML internal links ------------------------------------------
echo "Phase 1: Checking HTML internal links..." >&2

for html in "$WEBSITE"/*.html; do
  [[ -f "$html" ]] || continue
  basename_html=$(basename "$html")

  # Extract href="..." and src="..." values (skip external URLs and anchors)
  while IFS= read -r link; do
    # Clean up the link
    link=$(echo "$link" | sed 's/^["'\'']//' | sed 's/["'\''"]$//' | sed 's/#.*//' | sed 's/?.*//')
    [[ -z "$link" ]] && continue
    [[ "$link" =~ ^https?:// ]] && continue
    [[ "$link" =~ ^mailto: ]] && continue
    [[ "$link" =~ ^javascript: ]] && continue
    [[ "$link" == "/" ]] && continue
    [[ "$link" =~ ^\$ ]] && continue  # JS template/regex patterns
    [[ "$link" =~ ^\{ ]] && continue  # Template expressions

    # Resolve the link relative to website/
    if [[ "$link" == /* ]]; then
      target="$WEBSITE${link}"
    else
      target="$WEBSITE/$link"
    fi

    # Check with and without .html extension
    if [[ ! -e "$target" ]] && [[ ! -e "${target}.html" ]] && [[ ! -d "$target" ]]; then
      log_result "FAIL" "$basename_html" "$link" "File not found: $target"
    fi
  done < <(grep -oP '(?:href|src)=["'\''"]([^"'\''"]*)["'\''""]' "$html" 2>/dev/null | sed 's/^[^=]*=["'\'']//' | sed 's/["'\''"]$//' | sort -u)
done

# ---- Phase 2: JavaScript fetch() paths -------------------------------------
echo "Phase 2: Checking JavaScript fetch paths..." >&2

for html in "$WEBSITE"/*.html; do
  [[ -f "$html" ]] || continue
  basename_html=$(basename "$html")

  # Extract fetch('/path/...') patterns
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ "$path" =~ ^https?:// ]] && continue
    [[ "$path" == /api/* ]] && continue  # API routes checked separately

    # Resolve relative to website root
    target="$WEBSITE${path}"
    if [[ ! -e "$target" ]] && [[ ! -d "$(dirname "$target")" ]]; then
      log_result "FAIL" "$basename_html" "fetch($path)" "Fetched path not found"
    fi
  done < <(grep -oP "fetch\(['\"]([^'\"]*)['\"]" "$html" 2>/dev/null | sed "s/fetch(['\"]//;s/['\"]$//" | sort -u)
done

# ---- Phase 3: Markdown relative links --------------------------------------
echo "Phase 3: Checking markdown relative links..." >&2

find "$ROOT" -maxdepth 4 -name "*.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -type f 2>/dev/null | while IFS= read -r md; do
  # Extract [text](path) links
  while IFS= read -r link; do
    [[ "$link" =~ ^https?:// ]] && continue
    [[ "$link" =~ ^mailto: ]] && continue
    [[ "$link" =~ ^# ]] && continue

    dir=$(dirname "$md")
    resolved="$dir/$link"
    if [[ ! -e "$resolved" ]] && [[ ! -e "${resolved%.md}" ]]; then
      rel_md=${md#"$ROOT/"}
      log_result "WARN" "$rel_md" "$link" "Markdown link target not found"
    fi
  done < <(grep -oP '\[[^\]]*\]\(([^)]+)\)' "$md" 2>/dev/null | sed 's/.*(\([^)]*\)).*/\1/' | sort -u)
done

# ---- Phase 4: Live URL checks (if --live or --full) ------------------------
if [[ "$MODE" != "--quick" ]]; then
  echo "Phase 4: Checking live URLs on $DOMAIN..." >&2

  # Check all HTML pages
  for html in "$WEBSITE"/*.html; do
    [[ -f "$html" ]] || continue
    page=$(basename "$html" .html)
    url="$DOMAIN/$page"
    [[ "$page" == "index" ]] && url="$DOMAIN"

    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo "000")
    if [[ "$status" != "200" ]]; then
      log_result "FAIL" "LIVE" "$url" "HTTP $status"
    fi
    CHECKED=$((CHECKED + 1))
  done

  # Check API endpoints
  for endpoint in /api/health /api/usage; do
    status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$DOMAIN$endpoint" 2>/dev/null || echo "000")
    if [[ "$status" != "200" ]]; then
      log_result "FAIL" "API" "$endpoint" "HTTP $status"
    fi
    CHECKED=$((CHECKED + 1))
  done

  # Check research files referenced in index.md
  if [[ -f "$WEBSITE/docs/research/index.md" ]]; then
    while IFS= read -r ref; do
      status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$DOMAIN/docs/research/$ref" 2>/dev/null || echo "000")
      if [[ "$status" != "200" ]]; then
        log_result "FAIL" "RESEARCH" "/docs/research/$ref" "HTTP $status"
      fi
      CHECKED=$((CHECKED + 1))
    done < <(grep -oP '\]\((?:entities|topics|lab)/[^)]+\)' "$WEBSITE/docs/research/index.md" 2>/dev/null | sed 's/\](//;s/)//' | sort -u)
  fi
fi

# ---- Output ----------------------------------------------------------------
TS=$(date -u +%FT%TZ)

# JSONL output to stdout
echo "{\"ts\":\"$TS\",\"tool\":\"nel-link-check\",\"mode\":\"$MODE\",\"checked\":$CHECKED,\"errors\":$ERRORS,\"warnings\":$WARNINGS}"

if [[ ${#REPORT_LINES[@]} -gt 0 ]]; then
  for line in "${REPORT_LINES[@]}"; do
    IFS='|' read -r status file link detail <<< "$line"
    echo "{\"ts\":\"$TS\",\"status\":\"$status\",\"file\":\"$file\",\"link\":\"$link\",\"detail\":\"$detail\"}"
  done
fi

# Summary to stderr
echo "" >&2
echo "=== Link Check Summary ===" >&2
echo "Checked: $CHECKED | Errors: $ERRORS | Warnings: $WARNINGS" >&2

if [[ $ERRORS -gt 0 ]]; then
  echo "BROKEN LINKS:" >&2
  for line in "${REPORT_LINES[@]}"; do
    IFS='|' read -r status file link detail <<< "$line"
    [[ "$status" == "FAIL" ]] && echo "  ✗ [$file] $link — $detail" >&2
  done
  exit 1
fi

exit 0
