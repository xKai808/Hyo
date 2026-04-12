#!/usr/bin/env bash
# ~/Documents/Projects/Hyo/bin/kai.sh
#
# Kai CEO dispatcher. One command for every routine Hyo operation.
# This is the anti-copy-paste layer. If you find yourself pasting a multi-line
# curl or a verify sequence, it belongs in here as a subcommand.
#
# Install once:
#   echo 'alias kai="$HOME/Documents/Projects/Hyo/bin/kai.sh"' >> ~/.zshrc
#   source ~/.zshrc
#
# Then:
#   kai help
#   kai health
#   kai verify
#   kai deploy
#   kai mint aurora
#   kai news run
#   kai news latest
#   kai brief
#   kai tasks
#   kai scan secrets
#   kai sentinel
#   kai cipher
#   kai context

set -euo pipefail

# ---- repo root detection ----------------------------------------------------
if [[ -n "${HYO_ROOT:-}" ]] && [[ -d "$HYO_ROOT" ]]; then
  ROOT="$HYO_ROOT"
else
  ROOT="$HOME/Documents/Projects/Hyo"
fi

SECRETS="$ROOT/.secrets"
BIN="$ROOT/bin"
LOGS="$ROOT/agents/nel/logs"
TASKS="$ROOT/KAI_TASKS.md"
BRIEF="$ROOT/KAI_BRIEF.md"
API_BASE="${HYO_API_BASE:-https://www.hyo.world}"

mkdir -p "$LOGS"

# ---- color helpers ----------------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD=$(tput bold); DIM=$(tput dim); RED=$(tput setaf 1); GRN=$(tput setaf 2)
  YLW=$(tput setaf 3); BLU=$(tput setaf 4); MAG=$(tput setaf 5); RST=$(tput sgr0)
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; BLU=""; MAG=""; RST=""
fi

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s==>%s %s%s%s\n' "$BLU" "$RST" "$BOLD" "$*" "$RST"; }
ok()   { printf '%s✓%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '%s!%s %s\n' "$YLW" "$RST" "$*"; }
err()  { printf '%s✗%s %s\n' "$RED" "$RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---- env loader -------------------------------------------------------------
# Auto-discovery: scripts read env vars, kai.sh handles WHERE they come from.
# Search order (first hit wins):
#   1. $HYO_ENV_FILE (explicit override)
#   2. ~/security/hyo.env
#   3. ~/security/.env
#   4. ~/.config/hyo/env
#   5. $ROOT/.secrets/env
# File format: plain `KEY=value` or `export KEY=value` lines, # for comments.
# Any code that needs a credential should read ENV vars only, never hardcode
# filesystem paths. That way if you move /security, nothing breaks.
load_env_file() {
  local candidates=()
  [[ -n "${HYO_ENV_FILE:-}" ]] && candidates+=("$HYO_ENV_FILE")
  candidates+=(
    "$HOME/security/hyo.env"
    "$HOME/security/.env"
    "$HOME/.config/hyo/env"
    "$ROOT/.secrets/env"
  )
  for f in "${candidates[@]}"; do
    if [[ -f "$f" && -r "$f" ]]; then
      # shellcheck disable=SC1090
      set -a; source "$f"; set +a
      export HYO_ENV_FILE_LOADED="$f"
      return 0
    fi
  done
  return 1
}
load_env_file || true

# ---- token loader -----------------------------------------------------------
load_founder_token() {
  if [[ -n "${HYO_FOUNDER_TOKEN:-}" ]]; then
    printf '%s' "$HYO_FOUNDER_TOKEN"
    return 0
  fi
  if [[ -f "$SECRETS/founder.token" ]]; then
    tr -d '\n' < "$SECRETS/founder.token"
    return 0
  fi
  die "No founder token. Set HYO_FOUNDER_TOKEN env var or put it in $SECRETS/founder.token"
}

# ---- commands ---------------------------------------------------------------
cmd_help() {
  cat <<EOF
${BOLD}kai${RST} — CEO dispatcher for the Hyo stack

${BOLD}Health & deploy${RST}
  kai health              Check API is live and token is configured
  kai verify              Run full API smoke suite (health + 401 + mint)
  kai deploy              vercel --prod from website/

${BOLD}Agents${RST}
  kai mint <handle>       Mint an agent via founder endpoint
                          Optional: --file path.json for full payload
  kai agents              List agents in NFT/agents/

${BOLD}Newsletter (aurora)${RST}
  kai news run            Run aurora pipeline now (gather → synthesize → render)
  kai news latest         Open latest newsletter HTML in browser
  kai news logs           Tail today's aurora log

${BOLD}Kai ops${RST}
  kai brief               Print the session-continuity brief
  kai brief edit          Open KAI_BRIEF.md in \$EDITOR
  kai tasks               Show task queue (KAI_TASKS.md)
  kai tasks add "..."     Append a task
  kai tasks edit          Open KAI_TASKS.md in \$EDITOR
  kai context             Print hydration block to paste into a new Kai session
  kai save                Save a context snapshot for session recovery
  kai recover             View the latest context snapshot

${BOLD}Engineering (Sam)${RST}
  kai sam deploy          Git add, commit, push → Vercel deploy + verify live
  kai sam test            Run all tests (API endpoints, static files, JSON)
  kai sam build           Run build steps (npm, transpile, etc.)
  kai sam fix <issue>     Accept issue description, output fix command
  kai sam review          Scan recent changes, check for common issues

${BOLD}Defense agents${RST}
  kai sentinel            Run sentinel.hyo (QA agent) now
  kai cipher              Run cipher.hyo (security agent) now
  kai nel                 Run nel.hyo (system improvement agent) now
  kai scan secrets        Run gitleaks/trufflehog on the repo

${BOLD}Ra newsletter product manager${RST}
  kai ra run              Run Ra health check and reporting (product manager)
  kai ra index            Show the master archive index
  kai ra trends           Show the rolling trend report
  kai ra entity <slug>    Show one entity's timeline
  kai ra topic <slug>     Show one topic's timeline
  kai ra lab <slug>       Show one lab entry
  kai ra search <query>   Grep the entire archive
  kai ra since <date>     Show every entry on or after YYYY-MM-DD
  kai ra rebuild          Rebuild index + trends from existing files
  kai ra archive [date]   File a specific brief into the archive (default today)
  kai ra context [date]   Build .context.md from today's gather + archive

${BOLD}HQ dashboard${RST}
  kai push <agent> "msg"  Push a task result + event to hyo.world/hq
                          agent: ra|aurora|sentinel|cipher|sim|consolidation|aetherbot|ledger
                          Optional: --data '{"key":"val"}' for structured section update

${BOLD}Auto-deploy${RST}
  kai watch               Start file watcher — auto-deploys when website/ changes
  kai gitwatch            Start git watcher — auto-commit + push on website/ changes
                          Vercel GitHub integration handles the deploy.
                          Requires: brew install fswatch

${BOLD}Env${RST}
  HYO_ROOT=$ROOT
  HYO_API_BASE=$API_BASE
  HYO_ENV_FILE_LOADED=${HYO_ENV_FILE_LOADED:-<none>}
  kai env                 Show which env file was auto-loaded and which keys are set

EOF
}

cmd_env() {
  local sub="${1:-show}"; shift || true
  case "$sub" in
    show|"")
      hdr "env discovery"
      if [[ -n "${HYO_ENV_FILE_LOADED:-}" ]]; then
        ok "loaded env file: $HYO_ENV_FILE_LOADED"
      else
        warn "no env file auto-loaded"
        say ""
        say "Searched (in order):"
        say "  \$HYO_ENV_FILE override (currently: ${HYO_ENV_FILE:-<unset>})"
        say "  ~/security/hyo.env"
        say "  ~/security/.env"
        say "  ~/.config/hyo/env"
        say "  $ROOT/.secrets/env"
        say ""
        say "Quickest fix: ${BOLD}kai env set ANTHROPIC_API_KEY <your-key>${RST}"
      fi
      say ""
      hdr "detected credentials"
      local k v masked
      for k in ANTHROPIC_API_KEY GROK_API_KEY HYO_FOUNDER_TOKEN FRED_API_KEY OPENAI_API_KEY; do
        v="${!k:-}"
        if [[ -n "$v" ]]; then
          if [[ ${#v} -gt 12 ]]; then
            masked="${v:0:6}...${v: -4}"
          else
            masked="***"
          fi
          ok "$k set ($masked, ${#v} chars)"
        else
          warn "$k not set"
        fi
      done
      ;;
    set)
      local key="${1:-}"; local val="${2:-}"
      [[ -z "$key" || -z "$val" ]] && die 'usage: kai env set KEY value'
      # Target: first existing env file in search order, or fall back to
      # .secrets/env (always safe — gitignored, inside the repo)
      local target=""
      for f in "${HYO_ENV_FILE:-}" "$HOME/security/hyo.env" "$HOME/security/.env" \
               "$HOME/.config/hyo/env" "$SECRETS/env"; do
        [[ -z "$f" ]] && continue
        if [[ -f "$f" ]]; then target="$f"; break; fi
      done
      if [[ -z "$target" ]]; then
        target="$SECRETS/env"
        mkdir -p "$(dirname "$target")"
        chmod 700 "$(dirname "$target")" 2>/dev/null || true
        : > "$target"
        chmod 600 "$target"
        ok "created $target (mode 600)"
      fi
      # Upsert the key (remove old line, append new)
      local tmp
      tmp=$(mktemp)
      if [[ -f "$target" ]]; then
        grep -v "^[[:space:]]*\(export[[:space:]]\+\)\?${key}=" "$target" > "$tmp" || true
      fi
      printf '%s=%s\n' "$key" "$val" >> "$tmp"
      mv "$tmp" "$target"
      chmod 600 "$target"
      ok "set $key in $target"
      # Re-verify by reloading in a subshell
      if ( set -a; source "$target"; [[ -n "${!key:-}" ]] ); then
        ok "verified: $key loadable from $target"
      fi
      ;;
    path)
      say "${HYO_ENV_FILE_LOADED:-<none>}"
      ;;
    *)
      die 'usage: kai env [show|set KEY value|path]'
      ;;
  esac
}

cmd_health() {
  hdr "API health"
  local out
  if ! out=$(curl -sS "$API_BASE/api/health"); then
    err "API unreachable at $API_BASE"
    return 1
  fi
  echo "$out" | python3 -m json.tool
  # Parse JSON rigorously; compact and pretty forms both match
  if python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if d.get('founderTokenConfigured') else 1)" <<< "$out" 2>/dev/null; then
    ok "founder token configured in Vercel env"
  else
    warn "founder token NOT configured — set HYO_FOUNDER_TOKEN in Vercel env and redeploy"
  fi
}

cmd_verify() {
  hdr "Full API smoke suite"

  say "1/3 health endpoint"
  curl -sS "$API_BASE/api/health" | python3 -m json.tool
  echo

  say "2/3 wrong-token rejection (expect 401)"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/api/register-founder" \
    -H 'content-type: application/json' \
    -d '{"token":"wrong","agent_name":"test"}')
  if [[ "$code" == "401" ]]; then
    ok "401 returned as expected"
  else
    err "Expected 401, got $code"
  fi
  echo

  say "3/3 marketplace 4-letter rejection"
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API_BASE/api/marketplace-request" \
    -H 'content-type: application/json' \
    -d '{"handle":"toolong","email":"test@hyo.world"}')
  if [[ "$code" == "400" ]]; then
    ok "400 returned for 4+ letter handle"
  else
    err "Expected 400, got $code"
  fi
}

cmd_validate() {
  hdr "Pre-deploy validation"
  HYO_ROOT="$ROOT" python3 "$BIN/predeploy-validate.py" || die "validation failed — fix issues before deploying"
  ok "validation passed"
}

cmd_deploy() {
  cmd_validate
  hdr "Deploying website to Vercel"
  cd "$ROOT/website"
  npx vercel@latest --prod --yes
  ok "deploy dispatched"
  sleep 5
  cmd_health
}

cmd_mint() {
  local handle="${1:-}"; shift || true
  local payload_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --file) payload_file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -z "$handle" && -z "$payload_file" ]] && die "usage: kai mint <handle> [--file payload.json]"

  local token
  token=$(load_founder_token)

  local tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT

  if [[ -n "$payload_file" ]]; then
    [[ ! -f "$payload_file" ]] && die "payload file not found: $payload_file"
    # inject token
    python3 -c "
import json, sys
with open('$payload_file') as f: d = json.load(f)
d['token'] = '$token'
json.dump(d, sys.stdout)
" > "$tmp"
  else
    cat > "$tmp" <<JSON
{
  "token": "$token",
  "agent_name": "$handle",
  "display_name": "$handle.hyo",
  "tagline": "Hyo-operated agent",
  "description": "Founder-tier agent operated by Hyo. Registered via kai.sh dispatcher on $(date -u +%Y-%m-%dT%H:%M:%SZ).",
  "endpoint_url": "https://www.hyo.world/agents/$handle",
  "runs_on": "mini",
  "archetype": "herald",
  "pricing_model": "internal",
  "rate": 0,
  "side": "HUMAN",
  "initial_tier": "founding"
}
JSON
  fi

  hdr "Minting agent"
  local resp
  resp=$(curl -sS -X POST "$API_BASE/api/register-founder" \
    -H 'content-type: application/json' \
    --data @"$tmp")
  echo "$resp" | python3 -m json.tool

  # Save response to a dated log
  local logf="$LOGS/mint-$(date -u +%Y%m%dT%H%M%SZ).json"
  echo "$resp" > "$logf"
  ok "mint response logged to $logf"
}

cmd_agents() {
  hdr "Registered agents"
  ls -1 "$ROOT/NFT/agents/" 2>/dev/null | sed 's/^/  /'
}

cmd_news() {
  local sub="${1:-run}"; shift || true
  case "$sub" in
    run)
      hdr "Running aurora newsletter pipeline"
      cd "$ROOT/newsletter"
      local logf="$LOGS/aurora-$(date -u +%Y%m%dT%H%M%SZ).log"
      # Env is already loaded by kai.sh's load_env_file at top; re-export
      # anything the scheduled-task runner might have blanked
      if ! ./newsletter.sh 2>&1 | tee "$logf"; then
        err "newsletter.sh exited non-zero — see $logf"
        return 1
      fi
      ok "done — log: $logf"
      ;;
    latest)
      local latest
      latest=$(ls -1t "$ROOT/newsletters/"*.html 2>/dev/null | head -n1 || true)
      [[ -z "$latest" ]] && die "no newsletter HTML found in $ROOT/newsletters/"
      open "$latest"
      ok "opened $(basename "$latest")"
      ;;
    logs)
      local logf
      logf=$(ls -1t "$LOGS"/aurora-*.log 2>/dev/null | head -n1 || true)
      [[ -z "$logf" ]] && die "no aurora logs yet"
      tail -n 100 "$logf"
      ;;
    *)
      die "usage: kai news {run|latest|logs}"
      ;;
  esac
}

cmd_brief() {
  local sub="${1:-show}"
  case "$sub" in
    edit)
      "${EDITOR:-vi}" "$BRIEF"
      ;;
    show|"" |*)  # default: show; unknown sub-args fall through
      [[ ! -f "$BRIEF" ]] && die "No brief at $BRIEF"
      cat "$BRIEF"
      ;;
  esac
}

cmd_tasks() {
  local sub="${1:-show}"; shift || true
  case "$sub" in
    add)
      local task="$*"
      [[ -z "$task" ]] && die 'usage: kai tasks add "task description"'
      printf -- '- [ ] %s _(added %s)_\n' "$task" "$(date +%Y-%m-%d)" >> "$TASKS"
      ok "added: $task"
      ;;
    edit)
      "${EDITOR:-vi}" "$TASKS"
      ;;
    show|""|*)  # default: show; unknown sub-args fall through
      [[ ! -f "$TASKS" ]] && die "No task file at $TASKS"
      cat "$TASKS"
      ;;
  esac
}

cmd_context() {
  hdr "Hydration block (paste as first message to any new Kai session)"
  cat <<EOF

Read these files first, in order, before responding to anything:

1. $BRIEF
2. $TASKS
3. $ROOT/NFT/HyoRegistry_Notes.md
4. $ROOT/NFT/agents/ (list; read the ones relevant to the current task)
5. Most recent log in $LOGS

You are Kai, CEO of hyo.world. Hyo is the operator. The registry is deployed at https://www.hyo.world with serverless functions in website/api/. The founder bypass token lives in .secrets/founder.token. Use kai.sh (aliased as 'kai') for any routine operation — do not copy-paste curl commands.

After reading, give me a 3-line status: (1) what shipped since last session, (2) what's in the task queue, (3) what you recommend doing next.

EOF
}

cmd_save() {
  if [[ -x "$ROOT/kai/context-save.sh" ]]; then
    "$ROOT/kai/context-save.sh" "$@"
  else
    die "context-save.sh not found at $ROOT/kai/context-save.sh"
  fi
}

cmd_recover() {
  local latest="$ROOT/kai/context/LATEST.md"
  if [[ ! -f "$latest" ]]; then
    warn "no context snapshot yet — run: kai save"
    return 1
  fi
  hdr "Latest context snapshot"
  cat "$latest"
}

cmd_sentinel() {
  hdr "Running sentinel.hyo (QA agent)"
  if [[ -x "$ROOT/agents/nel/sentinel.sh" ]]; then
    "$ROOT/agents/nel/sentinel.sh"
  else
    warn "sentinel.sh not found at $ROOT/agents/nel/sentinel.sh — see agents/manifests/sentinel.hyo.json for spec"
  fi
}

cmd_cipher() {
  hdr "Running cipher.hyo (security agent)"
  if [[ -x "$ROOT/agents/nel/cipher.sh" ]]; then
    "$ROOT/agents/nel/cipher.sh"
  else
    warn "cipher.sh not found at $ROOT/agents/nel/cipher.sh — see agents/manifests/cipher.hyo.json for spec"
  fi
}

cmd_nel() {
  hdr "Running nel.hyo (system improvement agent)"
  if [[ -x "$ROOT/agents/nel/nel.sh" ]]; then
    "$ROOT/agents/nel/nel.sh"
  else
    warn "nel.sh not found at $ROOT/agents/nel/nel.sh — see agents/manifests/nel.hyo.json for spec"
  fi
}

cmd_ra() {
  local sub="${1:-index}"; shift || true
  local research="$ROOT/agents/ra/research"
  case "$sub" in
    run)
      hdr "Running Ra newsletter product manager"
      if [[ -x "$ROOT/agents/ra/ra.sh" ]]; then
        "$ROOT/agents/ra/ra.sh" "$@"
      else
        die "ra.sh not found at $ROOT/agents/ra/ra.sh"
      fi
      ;;
    index)
      [[ -f "$research/index.md" ]] || {
        warn "no index yet — run: kai ra rebuild"
        return 1
      }
      cat "$research/index.md"
      ;;
    trends)
      [[ -f "$research/trends.md" ]] || {
        warn "no trends yet — run: kai ra rebuild"
        return 1
      }
      cat "$research/trends.md"
      ;;
    entity)
      local slug="${1:-}"
      [[ -z "$slug" ]] && die 'usage: kai ra entity <slug>'
      local f="$research/entities/$slug.md"
      [[ -f "$f" ]] || die "no entity at $f (see kai ra index)"
      cat "$f"
      ;;
    topic)
      local slug="${1:-}"
      [[ -z "$slug" ]] && die 'usage: kai ra topic <slug>'
      local f="$research/topics/$slug.md"
      [[ -f "$f" ]] || die "no topic at $f (see kai ra index)"
      cat "$f"
      ;;
    lab)
      local slug="${1:-}"
      [[ -z "$slug" ]] && die 'usage: kai ra lab <slug>'
      local f="$research/lab/$slug.md"
      [[ -f "$f" ]] || die "no lab entry at $f (see kai ra index)"
      cat "$f"
      ;;
    search)
      local q="$*"
      [[ -z "$q" ]] && die 'usage: kai ra search <query>'
      hdr "Archive results for: $q"
      grep -rniI --color=auto --include="*.md" "$q" "$research" || warn "no matches"
      ;;
    since)
      local date="${1:-}"
      [[ -z "$date" ]] && die 'usage: kai ra since YYYY-MM-DD'
      hdr "Archive entries on or after $date"
      grep -rnE --include="*.md" "^### 2[0-9]{3}-[0-9]{2}-[0-9]{2}" "$research" \
        | awk -F: -v d="$date" '{
            # reconstruct the date from the matched line
            n = split($0, p, "### ")
            if (n >= 2 && p[2] >= d) print
          }' || warn "no matches"
      ;;
    rebuild)
      HYO_ROOT="$ROOT" python3 "$ROOT/agents/ra/ra_archive.py" --rebuild-index
      ;;
    archive)
      local date="${1:-}"
      if [[ -n "$date" ]]; then
        HYO_ROOT="$ROOT" python3 "$ROOT/agents/ra/ra_archive.py" --date "$date"
      else
        HYO_ROOT="$ROOT" python3 "$ROOT/agents/ra/ra_archive.py"
      fi
      ;;
    context)
      local date="${1:-}"
      if [[ -n "$date" ]]; then
        HYO_ROOT="$ROOT" python3 "$ROOT/kai/ra_context.py" --date "$date"
      else
        HYO_ROOT="$ROOT" python3 "$ROOT/kai/ra_context.py"
      fi
      ;;
    *)
      die "usage: kai ra {run|index|trends|entity|topic|lab|search|since|rebuild|archive|context}"
      ;;
  esac
}

cmd_scan() {
  local what="${1:-secrets}"
  case "$what" in
    secrets)
      hdr "Scanning for leaked secrets"
      if command -v gitleaks >/dev/null 2>&1; then
        gitleaks detect --source "$ROOT" --no-banner --verbose || true
      else
        warn "gitleaks not installed — brew install gitleaks"
      fi
      if command -v trufflehog >/dev/null 2>&1; then
        trufflehog filesystem "$ROOT" --exclude-paths="$ROOT/.gitleaksignore" 2>/dev/null || true
      else
        warn "trufflehog not installed — brew install trufflesecurity/trufflehog/trufflehog"
      fi
      ;;
    *)
      die "usage: kai scan secrets"
      ;;
  esac
}

# ---- hq push ---------------------------------------------------------------
cmd_push() {
  local agent="${1:-}"; shift || true
  local event="${1:-}"; shift || true
  local data_json="{}"

  # parse --data flag
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --data) data_json="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  if [[ -z "$agent" ]]; then
    die "usage: kai push <agent> \"event message\" [--data '{...}']"
  fi

  local token
  token=$(load_founder_token) || die "no founder token — cannot push to HQ"

  hdr "Pushing to HQ: $agent"

  local payload
  # Build JSON without printf to avoid brace doubling
  payload="{\"agent\":\"$agent\",\"event\":\"$event\",\"data\":$data_json}"

  say "${DIM}payload: $payload${RST}"

  local tmpfile
  tmpfile=$(mktemp)
  local http_code
  http_code=$(curl -sS -o "$tmpfile" -w '%{http_code}' -X POST "$API_BASE/api/hq?action=push" \
    -H "Content-Type: application/json" \
    -H "x-founder-token: $token" \
    -d "$payload") || { err "failed to reach $API_BASE/api/hq?action=push"; rm -f "$tmpfile"; return 1; }

  local out
  out=$(cat "$tmpfile")
  rm -f "$tmpfile"

  say "${DIM}http $http_code${RST}"

  if [[ "$http_code" == "200" ]] && echo "$out" | grep -q '"ok":true'; then
    ok "pushed to HQ"
  else
    warn "HQ responded ($http_code): $out"
  fi
}

# ---- dispatch ---------------------------------------------------------------
sub="${1:-help}"; shift || true
case "$sub" in
  help|-h|--help)     cmd_help ;;
  health)             cmd_health "$@" ;;
  verify)             cmd_verify "$@" ;;
  validate)           cmd_validate "$@" ;;
  deploy)             cmd_deploy "$@" ;;
  mint)               cmd_mint "$@" ;;
  agents)             cmd_agents "$@" ;;
  news)               cmd_news "$@" ;;
  brief)              cmd_brief "$@" ;;
  tasks)              cmd_tasks "$@" ;;
  context)            cmd_context "$@" ;;
  save)               cmd_save "$@" ;;
  recover)            cmd_recover "$@" ;;
  sentinel)           cmd_sentinel "$@" ;;
  cipher)             cmd_cipher "$@" ;;
  nel)                cmd_nel "$@" ;;
  scan)               cmd_scan "$@" ;;
  ra)                 cmd_ra "$@" ;;
  push)               cmd_push "$@" ;;
  sam)                bash "$ROOT/agents/sam/sam.sh" "$@" ;;
  aetherbot|ab)       bash "$ROOT/agents/aetherbot/aetherbot.sh" "$@" ;;
  ledger)             bash "$ROOT/agents/ledger/ledger.sh" "$@" ;;
  trade)
    # Shortcut: kai trade '{"pair":"BTC/USD","side":"buy","pnl":12.50,"strategy":"Grid Bot"}'
    bash "$ROOT/agents/aetherbot/aetherbot.sh" --record-trade "${1:-'{}'}"
    ;;
  watch)              bash "$ROOT/bin/watch-deploy.sh" ;;
  gitwatch)           bash "$ROOT/bin/watch-commit.sh" ;;
  gitpush)
    cmd_validate
    hdr "Pushing to origin/main"
    cd "$ROOT" && git push origin main
    ok "pushed to origin/main"
    ;;
  env)                cmd_env "$@" ;;
  consolidate)        bash "$ROOT/agents/nel/consolidation/consolidate.sh" "$@" ;;
  dispatch|d)         bash "$ROOT/bin/dispatch.sh" "$@" ;;
  simulate|sim)       bash "$ROOT/bin/dispatch.sh" simulate ;;
  dhealth)            bash "$ROOT/bin/dispatch.sh" health ;;
  memory)             bash "$ROOT/bin/dispatch.sh" memory ;;
  *)                  err "unknown subcommand: $sub"; cmd_help; exit 1 ;;
esac
