#!/usr/bin/env bash
set -euo pipefail

# ─── bootstrap.sh — Install orchestrator (entry point) ────────────────────────
#
# Domain:        Orchestration
# Description:   Thin sequencer. Prompts for install location (default /home),
#                resolves the tool selection (interactive menu or --tool=),
#                ensures core prerequisites, runs the numbered pipeline steps
#                (01_env → 02_litellm → 03/04/05 tools → 06_validate), and
#                prints a colored summary. This is the only script a human
#                needs to run. Each step is independently runnable too.
#
# Usage:
#   ./bootstrap.sh                          # interactive — prompts + tool menu
#   ./bootstrap.sh --tool=all               # install all (default)
#   ./bootstrap.sh --tool=litellm           # LiteLLM proxy only
#   ./bootstrap.sh --tool=opencode,codex    # custom combo
#   ./bootstrap.sh --virtual-key=sk-...     # reuse existing opencode virtual key
#   ./bootstrap.sh --dry-run                # preview without changes
#
# Non-interactive (CI / agent):
#   HUAWEI_MAAS_API_KEY=$KEY ./bootstrap.sh --tool=opencode
# ──────────────────────────────────────────────────────────────────────────────

REPO_URL="https://github.com/wallacelw/oh-my-coding-maas-gateway"
REPO_NAME="oh-my-coding-maas-gateway"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo ".")"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Parse args (early — needed before standalone check) ──
VIRTUAL_KEY=""
DRY_RUN=false
TOOL_SPECIFIED=false
TOOL_SELECTION=""
for arg in "$@"; do
  case "$arg" in
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)       DRY_RUN=true ;;
    --tool=*)        TOOL_SPECIFIED=true; TOOL_SELECTION="${arg#--tool=}" ;;
    *)
      echo "Usage: $0 [--tool=all|litellm|opencode|codex|claude|opencode,codex,...] [--virtual-key=sk-...] [--dry-run]"
      exit 1
      ;;
  esac
done

# ── Standalone detection ──
# If helpers/common.sh doesn't exist, we're running outside the repo
# (e.g., curl | bash). Prompt for install dir, clone, and re-exec.
if [ ! -f "$SCRIPT_DIR/helpers/common.sh" ]; then
  echo ""
  echo "=== $REPO_NAME — Standalone bootstrap ==="
  echo ""
  default_parent="/home"
  if [ -t 0 ]; then
    echo -n "  Where to install? [$default_parent]: "
    read -r install_parent < /dev/tty || install_parent="$default_parent"
    install_parent="${install_parent:-$default_parent}"
  else
    install_parent="$default_parent"
  fi
  target_dir="$install_parent/$REPO_NAME"
  if [ -d "$target_dir/.git" ]; then
    echo "  Existing install found at $target_dir — pulling updates..."
    cd "$target_dir"
    git pull --ff-only
  else
    echo "  Cloning to $target_dir..."
    git clone "$REPO_URL" "$target_dir"
    cd "$target_dir"
  fi
  exec ./scripts/bootstrap.sh "$@"
fi

# ── Now in the repo — source helpers ──
LITELLM_URL="http://127.0.0.1:4000"
source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
LOG_TAG="bootstrap"

# ── Defaults ──
INSTALL_OPENCODE=true
INSTALL_CODEX=true
INSTALL_CLAUDE_CODE=true

# ── Parse --tool= into INSTALL_* flags ──
if [ "$TOOL_SPECIFIED" = true ]; then
  INSTALL_OPENCODE=false
  INSTALL_CODEX=false
  INSTALL_CLAUDE_CODE=false
  IFS=',' read -ra TOOL_PARTS <<< "$TOOL_SELECTION"
  for part in "${TOOL_PARTS[@]}"; do
    case "$part" in
      all)       INSTALL_OPENCODE=true; INSTALL_CODEX=true; INSTALL_CLAUDE_CODE=true ;;
      litellm)   ;;
      opencode)  INSTALL_OPENCODE=true ;;
      codex)     INSTALL_CODEX=true ;;
      claude)    INSTALL_CLAUDE_CODE=true ;;
      *)
        log_error "Unknown tool '$part' in --tool=$TOOL_SELECTION"
        log_dim "Valid values: all, litellm, opencode, codex, claude (or comma-separated combo)"
        exit 1
        ;;
    esac
  done
fi

# ── Banner ──
echo ""
echo -e "${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║  oh-my-coding-maas-gateway — Bootstrap                 ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚══════════════════════════════════════════════════════╝${C_RESET}"
echo ""

# ── Install directory prompt ──
current_parent="$(dirname "$PROJECT_DIR")"
if [ -t 0 ]; then
  install_parent=$(prompt_input "Install directory (project will be in \$INSTALL_DIR/$REPO_NAME)" "$current_parent")
else
  install_parent="$current_parent"
fi
target_dir="$install_parent/$REPO_NAME"

if [ "$target_dir" != "$PROJECT_DIR" ]; then
  if [ -d "$target_dir/.git" ]; then
    log_info "Project already exists at $target_dir"
    if prompt_yesno "Switch to existing installation?" y; then
      cd "$target_dir"
      exec ./scripts/bootstrap.sh "$@"
    fi
  elif [ "$DRY_RUN" = true ]; then
    log_dim "Would clone: $REPO_URL → $target_dir"
  else
    log_info "Cloning project to $target_dir..."
    git clone "$REPO_URL" "$target_dir"
    cd "$target_dir"
    exec ./scripts/bootstrap.sh "$@"
  fi
fi

log_info "Project dir: $PROJECT_DIR"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── Core prerequisites ──
log_step "Core prerequisites"
log_action "bootstrap" "Ensuring: git, python3, curl, jq"
prereq_ensure_apt "git"     git     git
prereq_ensure_apt "python3" python3 python3
prereq_ensure_apt "curl"    curl    curl
prereq_ensure_apt "jq"      jq     jq

# ── Tool selection (menu if --tool= not given) ──
if [ "$TOOL_SPECIFIED" = false ] && [ -t 0 ]; then
  log_step "Select installation scope"
  echo -e "  ${C_BOLD}1)${C_RESET} Default — LiteLLM + opencode + Codex + Claude Code"
  echo -e "  ${C_BOLD}2)${C_RESET} LiteLLM only"
  echo -e "  ${C_BOLD}3)${C_RESET} LiteLLM + opencode"
  echo -e "  ${C_BOLD}4)${C_RESET} LiteLLM + Codex"
  echo -e "  ${C_BOLD}5)${C_RESET} LiteLLM + Claude Code"
  echo -e "  ${C_BOLD}6)${C_RESET} Custom — toggle each component"
  echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "
  choice=""
  read -r choice < /dev/tty || choice="1"
  case "${choice:-1}" in
    1) INSTALL_OPENCODE=true;  INSTALL_CODEX=true;  INSTALL_CLAUDE_CODE=true ;;
    2) INSTALL_OPENCODE=false; INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=false ;;
    3) INSTALL_OPENCODE=true;  INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=false ;;
    4) INSTALL_OPENCODE=false; INSTALL_CODEX=true;  INSTALL_CLAUDE_CODE=false ;;
    5) INSTALL_OPENCODE=false; INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=true ;;
    6)
      log_dim "Custom selection (LiteLLM is always installed):"
      prompt_yesno "Install opencode?" n && INSTALL_OPENCODE=true || INSTALL_OPENCODE=false
      prompt_yesno "Install Codex?" n    && INSTALL_CODEX=true    || INSTALL_CODEX=false
      prompt_yesno "Install Claude Code?" n && INSTALL_CLAUDE_CODE=true || INSTALL_CLAUDE_CODE=false
      ;;
    *)
      log_warn "Invalid choice. Defaulting to all."
      INSTALL_OPENCODE=true; INSTALL_CODEX=true; INSTALL_CLAUDE_CODE=true
      ;;
  esac
fi

# ── Show selected scope ──
echo ""
log_info "Installation scope:"
echo -e "    ${C_DIM}LiteLLM:${C_RESET}      yes (always)"
echo -e "    ${C_DIM}opencode:${C_RESET}     $( [ "$INSTALL_OPENCODE" = true ] && echo "${C_GREEN}yes${C_RESET}" || echo "${C_DIM}no${C_RESET}" )"
echo -e "    ${C_DIM}Codex:${C_RESET}        $( [ "$INSTALL_CODEX" = true ] && echo "${C_GREEN}yes${C_RESET}" || echo "${C_DIM}no${C_RESET}" )"
echo -e "    ${C_DIM}Claude Code:${C_RESET}  $( [ "$INSTALL_CLAUDE_CODE" = true ] && echo "${C_GREEN}yes${C_RESET}" || echo "${C_DIM}no${C_RESET}" )"

# ── Selection-driven prerequisite summary (prereq → needed by) ──
log_dim "Prerequisites to install (as needed):"
echo ""

CURL_TOOLS="bootstrap, litellm, validate"
JQ_TOOLS="bootstrap, validate"
[ "$INSTALL_OPENCODE" = true ]   && CURL_TOOLS+=", opencode"  && JQ_TOOLS+=", opencode"
[ "$INSTALL_CODEX" = true ]      && CURL_TOOLS+=", codex"     && JQ_TOOLS+=", codex"
[ "$INSTALL_CLAUDE_CODE" = true ] && CURL_TOOLS+=", claude"   && JQ_TOOLS+=", claude"

NPM_TOOLS=""
[ "$INSTALL_CODEX" = true ]       && NPM_TOOLS="codex"
[ "$INSTALL_CLAUDE_CODE" = true ] && NPM_TOOLS="${NPM_TOOLS:+$NPM_TOOLS, }claude"

printf "    ${C_DIM}%-14s %s${C_RESET}\n" "git"          "— bootstrap, env"
printf "    ${C_DIM}%-14s %s${C_RESET}\n" "python3"      "— bootstrap, env"
printf "    ${C_DIM}%-14s %s${C_RESET}\n" "curl"         "— $CURL_TOOLS"
printf "    ${C_DIM}%-14s %s${C_RESET}\n" "jq"           "— $JQ_TOOLS"
printf "    ${C_DIM}%-14s %s${C_RESET}\n" "docker"       "— litellm"
[ "$INSTALL_OPENCODE" = true ]    && printf "    ${C_DIM}%-14s %s${C_RESET}\n" "bun"        "— opencode"
[ -n "$NPM_TOOLS" ]               && printf "    ${C_DIM}%-14s %s${C_RESET}\n" "npm/node"   "— $NPM_TOOLS"
[ "$INSTALL_CODEX" = true ]       && printf "    ${C_DIM}%-14s %s${C_RESET}\n" "bubblewrap" "— codex"

# ── Helper to run a step ──
run_step() {
  local step_name="$1"; shift
  log_step "$step_name"
  if [ "$DRY_RUN" = true ]; then
    log_dim "Would run: $*"
  else
    "$@"
  fi
}

# ── Step 01: Environment & secrets ──
if [ "$DRY_RUN" = true ]; then
  log_step "Step 01: Environment & secrets"
  log_dim "Would run: scripts/01_env.sh"
else
  "$SCRIPT_DIR/01_env.sh"
fi

# ── Step 02: LiteLLM proxy + observability ──
run_step "Step 02: LiteLLM proxy + observability" \
  "$SCRIPT_DIR/02_litellm.sh" $([ "$DRY_RUN" = true ] && echo "--dry-run")

# ── Step 03: opencode (optional) ──
if [ "$INSTALL_OPENCODE" = true ]; then
  OPENCODE_ARGS=()
  [ -n "$VIRTUAL_KEY" ] && OPENCODE_ARGS+=("--virtual-key=$VIRTUAL_KEY")
  [ "$DRY_RUN" = true ] && OPENCODE_ARGS+=("--dry-run")
  run_step "Step 03: opencode" "$SCRIPT_DIR/03_opencode.sh" "${OPENCODE_ARGS[@]}"
else
  log_dim "(skipping opencode)"
fi

# ── Step 04: Codex CLI (optional) ──
if [ "$INSTALL_CODEX" = true ]; then
  CODEX_ARGS=()
  [ "$DRY_RUN" = true ] && CODEX_ARGS+=("--dry-run")
  run_step "Step 04: Codex CLI" "$SCRIPT_DIR/04_codex.sh" "${CODEX_ARGS[@]}"
else
  log_dim "(skipping Codex CLI)"
fi

# ── Step 05: Claude Code CLI (optional) ──
if [ "$INSTALL_CLAUDE_CODE" = true ]; then
  CLAUDE_ARGS=()
  [ "$DRY_RUN" = true ] && CLAUDE_ARGS+=("--dry-run")
  run_step "Step 05: Claude Code CLI" "$SCRIPT_DIR/05_claude_code.sh" "${CLAUDE_ARGS[@]}"
else
  log_dim "(skipping Claude Code CLI)"
fi

# ── Step 06: Validate ──
VALIDATE_ARGS=()
[ "$DRY_RUN" = true ] && VALIDATE_ARGS+=("--dry-run")
[ "$INSTALL_OPENCODE" = false ] && VALIDATE_ARGS+=("--skip-opencode")
[ "$INSTALL_CODEX" = false ] && VALIDATE_ARGS+=("--skip-codex")
[ "$INSTALL_CLAUDE_CODE" = false ] && VALIDATE_ARGS+=("--skip-claude-code")
set +e
run_step "Step 06: Validate" "$SCRIPT_DIR/06_validate.sh" "${VALIDATE_ARGS[@]}"
VALIDATE_RC=$?
set -e

# ── Summary ──
echo ""
echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}  Bootstrap complete${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}══════════════════════════════════════════════════════${C_RESET}"
echo ""
echo -e "  ${C_DIM}Project dir:${C_RESET}       $PROJECT_DIR"
echo -e "  ${C_DIM}LiteLLM proxy:${C_RESET}     $LITELLM_URL"
echo -e "  ${C_DIM}LiteLLM Admin UI:${C_RESET}  ${LITELLM_URL}/ui"
echo -e "  ${C_DIM}Grafana:${C_RESET}           http://127.0.0.1:3000 (anonymous, no login)"
echo -e "  ${C_DIM}Prometheus:${C_RESET}        http://127.0.0.1:9090"

if [ "$INSTALL_OPENCODE" = true ] && [ -f "$HOME/.config/opencode/opencode.json" ]; then
  echo -e "  ${C_DIM}opencode config:${C_RESET}   ~/.config/opencode/opencode.json"
  FINAL_VK=$(strip_jsonc "$HOME/.config/opencode/opencode.json" 2>/dev/null \
    | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null || true)
  [ -n "$FINAL_VK" ] && echo -e "  ${C_DIM}opencode key:${C_RESET}      $(mask_key "$FINAL_VK")"
fi
if [ "$INSTALL_CODEX" = true ] && [ -f "$HOME/.codex/.env" ]; then
  echo -e "  ${C_DIM}Codex CLI config:${C_RESET}   ~/.codex/config.toml"
  CODEX_VK=$(grep -oP '^LITELLM_CODEX_API_KEY=\K.*' "$HOME/.codex/.env" 2>/dev/null || true)
  [ -n "$CODEX_VK" ] && echo -e "  ${C_DIM}Codex CLI key:${C_RESET}      $(mask_key "$CODEX_VK")"
fi
if [ "$INSTALL_CLAUDE_CODE" = true ] && [ -f "$HOME/.claude/settings.json" ]; then
  echo -e "  ${C_DIM}Claude Code config:${C_RESET} ~/.claude/settings.json"
  CLAUDE_VK=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
  [ -n "$CLAUDE_VK" ] && echo -e "  ${C_DIM}Claude Code key:${C_RESET}    $(mask_key "$CLAUDE_VK")"
fi

echo ""
echo -e "  ${C_BOLD}Next steps:${C_RESET}"
[ "$INSTALL_OPENCODE" = true ] && echo -e "    opencode:  exit any running session, then run: ${C_CYAN}opencode${C_RESET}"
[ "$INSTALL_CODEX" = true ] && echo -e "    Codex:     ${C_CYAN}codex${C_RESET}"
[ "$INSTALL_CLAUDE_CODE" = true ] && echo -e "    Claude:    ${C_CYAN}claude --bare${C_RESET}"
echo ""
echo -e "  ${C_YELLOW}⚠ Security:${C_RESET} API keys were shared via environment variables and command line."
echo -e "    ${C_DIM}Rotate your MaaS keys to prevent unauthorized use:${C_RESET}"
echo -e "      ${C_DIM}1. Get new key(s) from https://console.huaweicloud.com/modelarts/${C_RESET}"
echo -e "      ${C_DIM}2. Edit .env: replace HUAWEI_MAAS_API_KEY and HUAWEI_MAAS_API_KEY_1..N${C_RESET}"
echo -e "      ${C_DIM}3. Regenerate config: ./scripts/02_litellm.sh${C_RESET}"
echo -e "      ${C_DIM}4. Restart LiteLLM:  docker compose restart litellm${C_RESET}"
echo -e "      ${C_DIM}5. Re-validate:      ./scripts/06_validate.sh${C_RESET}"
echo ""
echo -e "  ${C_BOLD}Restart your shell${C_RESET} (or open a new terminal) to clear exported environment"
echo -e "  variables and apply all changes:"
echo -e "    ${C_CYAN}exec \"\$SHELL\"${C_RESET}    ${C_DIM}# or close and reopen your terminal${C_RESET}"

exit "$VALIDATE_RC"
