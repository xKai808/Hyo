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

${BOLD}MCP Tunnel (sandbox connectivity)${RST}
  kai tunnel              Start MCP tunnel (cloudflared > localtunnel > ngrok)
  kai tunnel --method <m> Force tunnel method (cloudflared|localtunnel|ngrok)
  kai tunnel --help       Show tunnel setup help
  kai tunnel-daemon       Install/start persistent tunnel daemon (launchd)

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
                          agent: ra|aurora|sentinel|cipher|sim|consolidation|aether|dex
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
  local hook_file="$ROOT/agents/nel/security/deploy-hook"
  if [[ -f "$hook_file" ]]; then
    local hook
    hook=$(cat "$hook_file")
    local response
    response=$(curl -s -X POST "$hook" 2>/dev/null || echo '{}')
    local job_id
    job_id=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('job',{}).get('id','unknown'))" 2>/dev/null || echo "unknown")
    ok "deploy triggered via hook — job: $job_id"
    echo "  Monitor: https://vercel.com/dashboard" >&2
  else
    # Fallback: CLI deploy from parent dir so Vercel root-dir=website resolves correctly
    warn "deploy hook not found — trying CLI from project root"
    cd "$ROOT"
    npx vercel@latest --prod --yes --cwd website 2>/dev/null || \
      npx vercel@latest --prod --yes 2>/dev/null || \
      die "CLI deploy also failed — check agents/nel/security/deploy-hook"
    ok "deploy dispatched via CLI"
  fi
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
  local handoff="$ROOT/kai/ledger/session-handoff.json"
  if [[ -f "$handoff" ]]; then
    echo ""
    echo "★ READ THIS FIRST — session-handoff.json:"
    python3 -c "
import json
d = json.load(open('$handoff'))
print(f\"  Session: {d.get('session_id','?')} | Ended: {d.get('ended_at','?')}\")
print(f\"  Top priority: {d.get('top_priority','?')}\")
p0s = d.get('open_p0s', [])
if p0s:
  print(f\"  Open P0s ({len(p0s)}): {p0s[0][:80]}\")
hyo = d.get('hyo_actions_pending', [])
if hyo:
  print(f\"  Hyo pending: {len(hyo)} action(s)\")
notes = d.get('next_session_steps', [])
if notes:
  print(f\"  Next steps: {len(notes)} defined in session-handoff.json\")
" 2>/dev/null || true
    echo ""
  fi
  cat <<EOF
Read these files in order before responding to anything:

0. $ROOT/kai/ledger/session-handoff.json   ← machine-readable handoff (TOP PRIORITY)
1. $BRIEF                                   ← session-continuity memory
2. $ROOT/kai/ledger/hyo-inbox.jsonl         ← Hyo direct messages (urgent)
3. $ROOT/kai/dispatch/                      ← today + yesterday dispatch transcripts
4. $ROOT/kai/memory/KNOWLEDGE.md            ← permanent knowledge layer
5. $ROOT/kai/memory/TACIT.md               ← Hyo preferences + hard rules
6. $TASKS                                   ← priority queue (★ NEXT SESSION block)
7. $ROOT/kai/ledger/session-errors.jsonl    ← Kai's mistake ledger
8. $ROOT/kai/protocols/EXECUTION_GATE.md    ← pre-action gate
9. $ROOT/kai/ledger/simulation-outcomes.jsonl ← last nightly sim

You are Kai, orchestrator of hyo.world. Hyo is the CEO and decision authority.
See kai/protocols/SESSION_CONTINUITY_PROTOCOL.md for the full start-of-session protocol.
Use kai.sh (aliased 'kai') for all routine operations — never copy-paste curl commands.

After hydration, give me a 4-line status:
1. What shipped last session
2. Top priority this session
3. Recommendation for next 15 minutes
4. Queue active: yes/no

EOF
}

cmd_session_close() {
  if [[ -x "$ROOT/bin/session-close.sh" ]]; then
    HYO_ROOT="$ROOT" bash "$ROOT/bin/session-close.sh" "$@"
  else
    die "session-close.sh not found at $ROOT/bin/session-close.sh"
  fi
}

cmd_session_prep() {
  if [[ -x "$ROOT/bin/session-prep.sh" ]]; then
    HYO_ROOT="$ROOT" bash "$ROOT/bin/session-prep.sh" "$@"
  else
    die "session-prep.sh not found at $ROOT/bin/session-prep.sh"
  fi
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

cmd_tunnel() {
  hdr "MCP tunnel (Cowork connectivity)"
  if [[ -x "$ROOT/agents/sam/mcp-server/tunnel.sh" ]]; then
    "$ROOT/agents/sam/mcp-server/tunnel.sh" "$@"
  else
    die "tunnel.sh not found at $ROOT/agents/sam/mcp-server/tunnel.sh"
  fi
}

cmd_bridge_install() {
  hdr "Installing kai-bridge daemon (launchd)"
  local plist="$ROOT/kai/launchd/com.hyo.kai-bridge.plist"
  local target="$HOME/Library/LaunchAgents/com.hyo.kai-bridge.plist"

  [[ ! -f "$plist" ]] && die "plist not found at $plist"

  mkdir -p "$(dirname "$target")"
  cp "$plist" "$target"
  chmod 644 "$target"
  ok "plist installed to $target"

  # Unload if already loaded
  launchctl unload "$target" 2>/dev/null || true
  launchctl load "$target"
  ok "kai-bridge daemon loaded"

  sleep 2
  say ""
  hdr "Bridge status"
  launchctl list com.hyo.kai-bridge 2>/dev/null || warn "daemon not running yet"
  say ""
  # Test health endpoint
  local health
  health=$(curl -s --max-time 3 "http://localhost:9876/health" 2>/dev/null || echo "")
  if [[ -n "$health" ]]; then
    ok "bridge is responding: $health"
  else
    warn "bridge not responding yet — check: tail -f /tmp/kai-bridge.log"
  fi
  say ""
  say "Bridge URL:  http://localhost:9876  (local)"
  say "Tailscale:   http://100.77.143.7:9876  (remote)"
  say "Logs:        tail -f /tmp/kai-bridge.log"
  say "Health:      kai bridge-health"
}

cmd_tunnel_daemon() {
  local sub="${1:-install}"; shift || true
  case "$sub" in
    install)
      hdr "Installing MCP tunnel daemon (launchd)"
      local plist="$ROOT/agents/sam/mcp-server/com.hyo.mcp-tunnel.plist"
      local target="$HOME/Library/LaunchAgents/com.hyo.mcp-tunnel.plist"

      [[ ! -f "$plist" ]] && die "plist not found at $plist"

      # Expand $HOME in the plist
      mkdir -p "$(dirname "$target")"
      sed "s|\$HOME|$HOME|g" "$plist" > "$target"
      chmod 644 "$target"
      ok "plist installed to $target"

      # Load it
      launchctl load "$target" 2>/dev/null || {
        warn "plist may already be loaded; unloading first..."
        launchctl unload "$target" 2>/dev/null || true
        launchctl load "$target"
      }
      ok "daemon loaded and will start on login"

      # Show status
      say ""
      hdr "Daemon status"
      launchctl list com.hyo.mcp-tunnel 2>/dev/null || warn "daemon not running yet"
      say ""
      say "To view logs: ${BOLD}tail -f /tmp/hyo-mcp-tunnel.log${RST}"
      ;;
    uninstall)
      hdr "Uninstalling MCP tunnel daemon"
      local target="$HOME/Library/LaunchAgents/com.hyo.mcp-tunnel.plist"
      if [[ -f "$target" ]]; then
        launchctl unload "$target" 2>/dev/null || warn "daemon not loaded"
        rm -f "$target"
        ok "daemon uninstalled"
      else
        warn "daemon not installed at $target"
      fi
      ;;
    start)
      hdr "Starting MCP tunnel daemon"
      launchctl start com.hyo.mcp-tunnel || {
        err "failed to start daemon"
        return 1
      }
      ok "daemon started"
      sleep 2
      tail -n 20 /tmp/hyo-mcp-tunnel.log 2>/dev/null || warn "no logs yet"
      ;;
    stop)
      hdr "Stopping MCP tunnel daemon"
      launchctl stop com.hyo.mcp-tunnel || {
        err "failed to stop daemon"
        return 1
      }
      ok "daemon stopped"
      ;;
    status)
      hdr "MCP tunnel daemon status"
      launchctl list com.hyo.mcp-tunnel 2>/dev/null || {
        warn "daemon not running"
        return 1
      }
      say ""
      if [[ -f /tmp/hyo-mcp-tunnel.log ]]; then
        say "Recent logs:"
        tail -n 10 /tmp/hyo-mcp-tunnel.log
      fi
      ;;
    logs)
      hdr "MCP tunnel daemon logs"
      [[ -f /tmp/hyo-mcp-tunnel.log ]] || {
        warn "no logs yet (daemon may not have run)"
        return 1
      }
      tail -f /tmp/hyo-mcp-tunnel.log
      ;;
    *)
      die "usage: kai tunnel-daemon {install|uninstall|start|stop|status|logs}"
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

    # ── VERIFY: fetch data endpoint to confirm push arrived ──
    say "${DIM}verifying push...${RST}"
    local hq_password="${HYO_HQ_PASSWORD:-}"
    if [[ -z "$hq_password" ]]; then
      say "${DIM}(HYO_HQ_PASSWORD not set — skipping verification)${RST}"
      return 0
    fi

    local verify_attempt=1
    local verify_max=2

    # Get session token via auth endpoint
    local auth_tmpfile
    auth_tmpfile=$(mktemp)
    local auth_http_code
    auth_http_code=$(curl -sS -o "$auth_tmpfile" -w '%{http_code}' -X POST "$API_BASE/api/hq?action=auth" \
      -H "Content-Type: application/json" \
      -d "{\"password\":\"$hq_password\"}") || {
      warn "failed to reach auth endpoint — skipping verification"
      rm -f "$auth_tmpfile"
      return 0
    }

    local auth_response
    auth_response=$(cat "$auth_tmpfile")
    rm -f "$auth_tmpfile"

    if [[ "$auth_http_code" != "200" ]] || ! echo "$auth_response" | grep -q '"ok":true'; then
      warn "auth failed (wrong password?) — skipping verification"
      return 0
    fi

    local session_token
    session_token=$(echo "$auth_response" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    if [[ -z "$session_token" ]]; then
      warn "failed to extract session token — skipping verification"
      return 0
    fi

    # Fetch data and verify agent section exists
    while [[ $verify_attempt -le $verify_max ]]; do
      local data_tmpfile
      data_tmpfile=$(mktemp)
      local data_http_code
      data_http_code=$(curl -sS -o "$data_tmpfile" -w '%{http_code}' -X GET "$API_BASE/api/hq?action=data" \
        -H "Authorization: Bearer $session_token") || {
        say "${DIM}attempt $verify_attempt/$verify_max: failed to reach data endpoint${RST}"
        rm -f "$data_tmpfile"
        verify_attempt=$((verify_attempt + 1))
        [[ $verify_attempt -le $verify_max ]] && sleep 1
        continue
      }

      local data_response
      data_response=$(cat "$data_tmpfile")
      rm -f "$data_tmpfile"

      # Check if agent section and pushed data appear in response
      if [[ "$data_http_code" == "200" ]] && echo "$data_response" | grep -q "\"$agent\""; then
        if echo "$data_response" | grep -q "lastRun"; then
          ok "verified: $agent data received and stored"
          return 0
        fi
      fi

      say "${DIM}attempt $verify_attempt/$verify_max: agent data not yet visible${RST}"
      verify_attempt=$((verify_attempt + 1))
      [[ $verify_attempt -le $verify_max ]] && sleep 1
    done

    warn "verification: $agent data not confirmed after $verify_max attempts"
  else
    warn "HQ responded ($http_code): $out"
  fi
}

# ---- command queue ----------------------------------------------------------
cmd_queue() {
  local QUEUE="$ROOT/kai/queue"
  local subcmd="${1:-status}"; shift || true

  case "$subcmd" in
    submit)
      # kai queue submit "git push origin main"
      local command="$*"
      [[ -z "$command" ]] && die "usage: kai queue submit <command>"
      local cmd_id="cmd-$(date +%s)-$$"
      local ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      local timeout="${KAI_QUEUE_TIMEOUT:-60}"

      python3 -c "
import json
cmd = {
  'id': '$cmd_id',
  'ts': '$ts',
  'command': '''$command''',
  'timeout': $timeout,
  'agent': 'kai'
}
with open('$QUEUE/pending/$cmd_id.json', 'w') as f:
  json.dump(cmd, f, indent=2)
print('$cmd_id')
"
      ok "queued: $cmd_id → $command"
      ;;
    status)
      local pending=$(ls "$QUEUE/pending/"*.json 2>/dev/null | wc -l | tr -d ' ')
      local running=$(ls "$QUEUE/running/"*.json 2>/dev/null | wc -l | tr -d ' ')
      local completed=$(ls "$QUEUE/completed/"*.json 2>/dev/null | wc -l | tr -d ' ')
      local failed=$(ls "$QUEUE/failed/"*.json 2>/dev/null | wc -l | tr -d ' ')
      say "Queue: ${pending} pending, ${running} running, ${completed} completed, ${failed} failed"
      ;;
    results)
      # Show recent results
      for f in $(ls -t "$QUEUE/completed/"*.json "$QUEUE/failed/"*.json 2>/dev/null | head -5); do
        python3 -c "
import json
with open('$f') as fh:
  r = json.load(fh)
  status = '✓' if r['exit_code'] == 0 else '✗'
  print(f\"{status} [{r['id']}] exit={r['exit_code']} ({r['duration_s']}s): {r['command'][:60]}\")
  if r.get('stdout','').strip():
    for line in r['stdout'].strip().split('\n')[:3]:
      print(f'    {line}')
" 2>/dev/null
      done
      ;;
    process)
      # Run worker once (process all pending)
      bash "$ROOT/kai/queue/worker.sh"
      ;;
    watch)
      # Start continuous worker
      bash "$ROOT/kai/queue/worker.sh" --watch
      ;;
    install)
      # Install launchd daemon
      local plist_src="$QUEUE/com.hyo.queue-worker.plist"
      local plist_dst="$HOME/Library/LaunchAgents/com.hyo.queue-worker.plist"
      launchctl bootout "gui/$(id -u)/com.hyo.queue-worker" 2>/dev/null || true
      sleep 1
      cp "$plist_src" "$plist_dst"
      launchctl bootstrap "gui/$(id -u)" "$plist_dst"
      ok "queue worker daemon installed and running"
      ;;
    log)
      tail -20 "$QUEUE/worker.log" 2>/dev/null || warn "no worker log yet"
      ;;
    *)
      say "usage: kai queue {submit|status|results|process|watch|install|log}"
      ;;
  esac
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
  report)             bash "$ROOT/bin/kai-report.sh" "$@" ;;
  api)                bash "$ROOT/bin/api-usage.sh" "$@" ;;
  sam)                bash "$ROOT/agents/sam/sam.sh" "$@" ;;
  aether|ab)       bash "$ROOT/agents/aether/aether.sh" "$@" ;;
  dex)             bash "$ROOT/agents/dex/dex.sh" "$@" ;;
  trade)
    # Shortcut: kai trade '{"pair":"BTC/USD","side":"buy","pnl":12.50,"strategy":"Grid Bot"}'
    bash "$ROOT/agents/aether/aether.sh" --record-trade "${1:-'{}'}"
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
  session-close|sc)   cmd_session_close "$@" ;;
  session-prep|sp)    cmd_session_prep "$@" ;;
  dispatch|d)         bash "$ROOT/bin/dispatch.sh" "$@" ;;
  simulate|sim)       bash "$ROOT/bin/dispatch.sh" simulate ;;
  dhealth)            bash "$ROOT/bin/dispatch.sh" health ;;
  memory)             bash "$ROOT/bin/dispatch.sh" memory ;;
  tunnel)             cmd_tunnel "$@" ;;
  tunnel-daemon)      cmd_tunnel_daemon "$@" ;;
  queue|q)            cmd_queue "$@" ;;
  audit)              bash "$ROOT/kai/queue/daily-audit.sh" ;;
  exec|x)             bash "$ROOT/kai/queue/exec.sh" "$@" ;;
  bridge)             bash "$ROOT/bin/kai-bridge-call.sh" "$@" ;;
  bridge-install)     cmd_bridge_install ;;
  bridge-health)      curl -s "http://100.77.143.7:9876/health" 2>/dev/null | python3 -m json.tool || echo "bridge unreachable" ;;
  ant-update)         bash "$ROOT/bin/ant-update.sh" "$@" ;;
  ant-install)        cp "$ROOT/agents/ant/com.hyo.ant-daily.plist" ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/com.hyo.ant-daily.plist && echo "[ant-install] Ant daily schedule installed (23:45 MT)" ;;
  ant-monthly-close)  python3 -c "
import json, os, datetime
prev = (datetime.date.today().replace(day=1) - datetime.timedelta(days=1)).strftime('%Y-%m')
path = os.path.join('$ROOT', 'agents/ant/ledger', f'monthly-{prev}.json')
if not os.path.exists(path): print(f'No ledger for {prev}'); exit(0)
with open(path) as f: d = json.load(f)
d['status'] = 'closed'; d['closed_at'] = datetime.datetime.utcnow().isoformat() + 'Z'
with open(path, 'w') as f: json.dump(d, f, indent=2)
print(f'Closed {path}')
" ;;
  agent-goals|goals)  HYO_ROOT="$ROOT" bash "$ROOT/bin/agent-goals-sync.sh" "$@" ;;
  desktop)            ssh -p 31781 -L 5900:localhost:5900 kai@bore.pub -fN 2>/dev/null; sleep 1; open vnc://localhost ;;
  ssh-mini)           ssh -p 31781 kai@bore.pub ;;
  nel-qa)             bash "$ROOT/agents/nel/nel-qa-cycle.sh" "$@" ;;
  link-check|lc)      bash "$ROOT/agents/nel/link-check.sh" "$@" ;;
  sync-research)      bash "$ROOT/kai/queue/sync-research.sh" ;;
  ticket|t)           bash "$ROOT/bin/ticket.sh" "$@" ;;
  podcast)            HYO_ROOT="$ROOT" python3 "$ROOT/bin/podcast.py" "$@" ;;
  podcast-dry)        HYO_ROOT="$ROOT" python3 "$ROOT/bin/podcast.py" --dry-run "$@" ;;
  podcast-script)     HYO_ROOT="$ROOT" python3 "$ROOT/bin/podcast.py" --script-only "$@" ;;

  # inject-feedback: wire Hyo feedback directly into an agent's GROWTH.md
  # Usage: kai inject-feedback <agent> "<feedback summary>" [P0|P1|P2]
  # This is the most important signal in the system — Hyo's corrections feed directly
  # into the improvement cycle rather than stopping at session-errors.jsonl
  inject-feedback|feedback)
    FEEDBACK_AGENT="${2:-}"
    FEEDBACK_TEXT="${3:-}"
    FEEDBACK_PRIORITY="${4:-P1}"
    TODAY_F=$(TZ=America/Denver date +%Y-%m-%d)
    NOW_F=$(TZ=America/Denver date +%Y-%m-%dT%H:%M:%S%z)
    if [[ -z "$FEEDBACK_AGENT" || -z "$FEEDBACK_TEXT" ]]; then
      err "Usage: kai inject-feedback <agent> \"<feedback>\" [P0|P1|P2]"
      exit 1
    fi
    GROWTH_FILE="$ROOT/agents/$FEEDBACK_AGENT/GROWTH.md"
    if [[ ! -f "$GROWTH_FILE" ]]; then
      err "GROWTH.md not found for $FEEDBACK_AGENT at $GROWTH_FILE"
      exit 1
    fi
    # Find next available W-ID
    NEXT_ID=$(python3 -c "
import re
content = open('$GROWTH_FILE').read()
ids = re.findall(r'^### W(\d+):', content, re.MULTILINE)
nums = [int(x) for x in ids] if ids else [0]
print('W' + str(max(nums) + 1))
" 2>/dev/null || echo "W99")
    # Append new weakness from Hyo feedback
    cat >> "$GROWTH_FILE" << GROWTH_ENTRY

### $NEXT_ID: Hyo Feedback — $FEEDBACK_TEXT
**Severity:** $FEEDBACK_PRIORITY
**Status:** active — injected from Hyo feedback $TODAY_F

**Evidence:**
Hyo directly flagged this issue in a session on $TODAY_F.

**Root cause:**
Under investigation — needs research phase to identify root cause.

**Fix approach:**
Research phase will determine specific fix approach.
GROWTH_ENTRY
    echo "✓ Injected as $NEXT_ID into $FEEDBACK_AGENT/GROWTH.md"
    # Also create a P1 ticket
    HYO_ROOT="$ROOT" bash "$ROOT/bin/ticket.sh" create \
      --agent "$FEEDBACK_AGENT" \
      --title "Hyo feedback → $NEXT_ID: $FEEDBACK_TEXT" \
      --priority "$FEEDBACK_PRIORITY" \
      --type "improvement" \
      --created-by "kai-inject-feedback" 2>/dev/null && echo "✓ Ticket opened"
    # Log to session-errors.jsonl too
    python3 -c "
import json
from datetime import datetime
entry = {'ts': '$NOW_F', 'category': 'hyo-feedback', 'agent': '$FEEDBACK_AGENT',
         'description': '$FEEDBACK_TEXT', 'growth_id': '$NEXT_ID',
         'prevention': 'Injected into GROWTH.md for self-improve flywheel'}
with open('$ROOT/kai/ledger/session-errors.jsonl', 'a') as f:
    f.write(json.dumps(entry) + '\n')
" 2>/dev/null || true
    echo "✓ Logged to session-errors.jsonl"
    ;;

  flywheel-doctor|doctor)    HYO_ROOT="$ROOT" bash "$ROOT/bin/flywheel-doctor.sh" "$@" ;;
  self-improve|improve)      HYO_ROOT="$ROOT" bash "$ROOT/bin/agent-self-improve.sh" "$@" ;;
  cross-agent-review|review) HYO_ROOT="$ROOT" bash "$ROOT/bin/cross-agent-review.sh" "$@" ;;
  omp|omp-measure)           HYO_ROOT="$ROOT" bash "$ROOT/bin/omp-measure.sh" "$@" ;;

  *)                  err "unknown subcommand: $sub"; cmd_help; exit 1 ;;
esac
