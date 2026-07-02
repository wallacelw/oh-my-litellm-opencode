#!/usr/bin/env bash
# common.sh — Shared utility helpers
#
# Source from any script:
#   source "$(dirname "${BASH_SOURCE[0]}")/helpers/common.sh"
#
# Provides:
#   source_env <project_dir>   — load .env into the environment (no-op if absent)
#   retry_curl [-o] curl_args  — retry curl with backoff (-o captures body)
#   strip_jsonc <file>         — strip // and /* */ comments outside strings
#   mask_key <key>             — print first8...last4 of a key
#
#   ── Logging (colored, action-labeled) ──
#   log_step "title"           — bold cyan section header
#   log_ok "msg"               — green ✓
#   log_info "msg"             — blue →
#   log_warn "msg"             — yellow ⚠ (stderr)
#   log_error "msg"            — red ✗ (stderr)
#   log_dim "msg"              — dim secondary text
#   log_action "who" "msg"     — dim [who] prefix for action labeling
#
#   ── Prompts (interactive, auto-default on non-TTY) ──
#   prompt_yesno "question" [y|n]  — returns 0 (yes) or 1 (no)
#   prompt_input "question" [default]  — echoes user input or default
#   prompt_password "question" [default]  — echoes password (no echo, or default)
#
#   ── Subprocess output filtering ──
#   run_filtered "tag" cmd...  — run cmd, filter noise, prefix lines with [tag]

# ── Color setup ──────────────────────────────────────────────
if [ -t 1 ]; then
  C_RESET="\033[0m"  C_BOLD="\033[1m"  C_DIM="\033[2m"
  C_RED="\033[31m"   C_GREEN="\033[32m" C_YELLOW="\033[33m"
  C_BLUE="\033[34m"  C_CYAN="\033[36m"
else
  C_RESET="" C_BOLD="" C_DIM=""
  C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi

# Action tag — each script overrides after sourcing.
LOG_TAG="${LOG_TAG:-bootstrap}"

# Load .env (if present) into the environment so scripts are self-sufficient.
# Usage: source_env "$PROJECT_DIR"
source_env() {
  local project_dir="$1"
  if [ -f "$project_dir/.env" ]; then
    # shellcheck source=/dev/null
    set -a; source "$project_dir/.env"; set +a
  fi
}

# Retry curl with backoff (3 attempts, 2s/4s delays).
# Usage: retry_curl [-o] curl_args...
#   -o  capture and echo response body (otherwise just check exit code)
retry_curl() {
  local capture=false
  if [ "$1" = "-o" ]; then capture=true; shift; fi
  local max_attempts=3 delay=2 attempt=1 response="" err=""
  while [ $attempt -le $max_attempts ]; do
    if [ "$capture" = true ]; then
      response=$(curl "$@" 2>/dev/null) && { echo "$response"; return 0; }
    else
      err=$(curl "$@" 2>&1) && return 0
    fi
    [ $attempt -lt $max_attempts ] && sleep $delay
    ((attempt++))
  done
  [ -n "$err" ] && echo "  curl error: $err" >&2
  return 1
}

# Strip JSONC comments (// and /* */) outside of quoted strings.
# Usage: strip_jsonc <file>   (prints cleaned JSON to stdout)
strip_jsonc() {
  python3 -c "
import sys
text = open(sys.argv[1]).read()
result = []
in_string = False
escape = False
i = 0
while i < len(text):
    c = text[i]
    if escape:
        result.append(c)
        escape = False
        i += 1
        continue
    if in_string:
        result.append(c)
        if c == '\\\\':
            escape = True
        elif c == '\"':
            in_string = False
        i += 1
        continue
    if c == '\"':
        in_string = True
        result.append(c)
        i += 1
        continue
    if c == '/' and i + 1 < len(text):
        if text[i+1] == '/':
            while i < len(text) and text[i] != '\\n':
                i += 1
            continue
        elif text[i+1] == '*':
            i += 2
            while i + 1 < len(text) and not (text[i] == '*' and text[i+1] == '/'):
                i += 1
            if i + 1 >= len(text):
                break
            i += 2
            continue
    result.append(c)
    i += 1
sys.stdout.write(''.join(result))
" < "$1" 2>/dev/null || cat "$1"
}

# Print a masked form of a key: first8...last4
# Usage: mask_key "sk-abcdef..."
mask_key() {
  local key="$1"
  if [ -n "$key" ] && [ ${#key} -ge 12 ]; then
    echo "${key:0:8}...${key: -4}"
  else
    echo "$key"
  fi
}

# ── Logging functions ────────────────────────────────────────

log_step() {
  echo -e "\n${C_BOLD}${C_CYAN}━━━ $* ━━━${C_RESET}"
}

log_ok() {
  echo -e "  ${C_GREEN}✓${C_RESET} $*"
}

log_info() {
  echo -e "  ${C_BLUE}→${C_RESET} $*"
}

log_warn() {
  echo -e "  ${C_YELLOW}⚠${C_RESET} $*" >&2
}

log_error() {
  echo -e "  ${C_RED}✗${C_RESET} $*" >&2
}

log_dim() {
  echo -e "  ${C_DIM}$*${C_RESET}"
}

# Action-labeled output: shows who is performing the action.
# Usage: log_action "opencode:installer" "Downloading binary..."
log_action() {
  local tag="$1"; shift
  echo -e "  ${C_DIM}[$tag]${C_RESET} $*"
}

# ── Prompt functions ─────────────────────────────────────────
# All prompts auto-default on non-interactive (piped stdin / CI).

# Yes/no prompt. Returns 0 for yes, 1 for no.
# Usage: prompt_yesno "Use auto-generated value?" y
prompt_yesno() {
  local question="$1" default="${2:-y}"
  local hint
  if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  if [ ! -t 0 ]; then
    [ "$default" = "y" ] && return 0 || return 1
  fi
  echo -ne "  ${C_BOLD}${C_CYAN}?${C_RESET} ${C_BOLD}$question${C_RESET} ${C_DIM}$hint${C_RESET} " >&2
  local answer
  read -r answer < /dev/tty
  case "${answer:-}" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    *) [ "$default" = "y" ] && return 0 || return 1 ;;
  esac
}

# Text input prompt with optional default. Echoes the result.
# Usage: prompt_input "Install directory" "/home"
prompt_input() {
  local question="$1" default="${2:-}"
  local hint=""
  [ -n "$default" ] && hint=" ${C_DIM}(default: $default)${C_RESET}"
  if [ ! -t 0 ]; then
    echo "$default"; return
  fi
  echo -ne "  ${C_BOLD}${C_CYAN}?${C_RESET} ${C_BOLD}$question${C_RESET}$hint: " >&2
  local answer
  read -r answer < /dev/tty
  echo "${answer:-$default}"
}

# Password prompt with optional auto-generated default.
# If default is provided and TTY: offers to use it or enter custom.
# If non-TTY: echoes the default.
# Usage: prompt_password "DB_PASSWORD" "$auto_generated_value"
prompt_password() {
  local label="$1" default="$2"
  if [ ! -t 0 ]; then
    echo "$default"; return
  fi
  echo -e "  ${C_BOLD}${C_CYAN}?${C_RESET} ${C_BOLD}$label${C_RESET}" >&2
  echo -e "    ${C_DIM}Auto-generated: $(mask_key "$default")${C_RESET}" >&2
  if prompt_yesno "Use auto-generated value?" y; then
    echo "$default"
    return
  fi
  echo -ne "  ${C_BOLD}Enter custom value${C_RESET}: " >&2
  local answer
  read -r answer < /dev/tty
  echo "$answer"
}

# ── Subprocess output filtering ──────────────────────────────
# Run a command, capture output, filter known noise (star prompts,
# npm warnings, blank lines), and display remaining lines with a
# dim [tag] prefix. Returns the command's exit code.
# Usage: run_filtered "slim" bunx oh-my-opencode-slim@2.0.5 install --companion=no
run_filtered() {
  local tag="$1"; shift
  local rc output line
  output=$("$@" 2>&1 </dev/null) && rc=0 || rc=$?
  while IFS= read -r line; do
    case "$line" in
      *"star"*|*"Star"*|*"⭐"*|*"github.com/"*"star"*) continue ;;
      *"npm warn"*|*"npm WARN"*|*"npm notice"*) continue ;;
      *"warning:"*"deprecated"*) continue ;;
      "") continue ;;
    esac
    echo -e "  ${C_DIM}[$tag] $line${C_RESET}"
  done <<< "$output"
  return $rc
}
