#!/usr/bin/env bash
set -euo pipefail

# ─── 05_claude_code.sh — Claude Code CLI tool (pipeline step 05, optional) ────
#
# Domain:        Claude Code CLI
# Order:         05 (after LiteLLM proxy is live)
# Optional:      yes (runs only if claude is in the selection)
# Description:   Install the Claude Code CLI, mint a LiteLLM virtual key
#                (alias "claude-code"), and write ~/.claude/settings.json
#                (env block pointing to the LiteLLM proxy via the Anthropic
#                Messages API). Disables the VSCode extension auto-install.
# Inputs:        .env (LITELLM_MASTER_KEY), --virtual-key, --dry-run
# Outputs:       ~/.claude/settings.json, ~/.claude.json
# Standalone:    yes — ./scripts/05_claude_code.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_CONFIG_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
LITELLM_URL="http://127.0.0.1:4000"
CURL_TIMEOUT=15

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/keys.sh"
LOG_TAG="claude"
source_env "$PROJECT_DIR"

# ── Parse args ──
VIRTUAL_KEY=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)       DRY_RUN=true ;;
    *) log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

log_step "Step 05 — Claude Code CLI"
[ "$DRY_RUN" = true ] && log_dim "(DRY RUN — no changes will be made)"

# ── 1. Check prerequisites ──
log_info "1. Checking prerequisites..."
prereq_ensure_apt "curl" curl curl
prereq_ensure_npm
prereq_ensure_apt "jq" jq jq

if curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/health/liveliness" &>/dev/null; then
  log_ok "LiteLLM proxy: reachable"
else
  log_error "LiteLLM proxy not reachable at $LITELLM_URL. Start it first."
  exit 1
fi

# ── 2. Install Claude Code CLI ──
log_info "2. Installing Claude Code CLI..."
if ! command -v claude &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    log_info "Would run: npm install -g @anthropic-ai/claude-code"
  else
    run_filtered "npm" npm install -g @anthropic-ai/claude-code
    log_ok "Installed: $(claude --version 2>/dev/null || echo 'unknown')"
  fi
else
  log_ok "Already installed: $(claude --version 2>/dev/null || echo 'unknown')"
fi

# ── 3. Acquire virtual key (idempotent) ──
log_info "3. Configuring LiteLLM virtual key..."

if [ -z "$VIRTUAL_KEY" ] && [ -f "$CLAUDE_SETTINGS" ]; then
  EXISTING_KEY=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/messages" \
         -H "x-api-key: $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -H "anthropic-version: 2023-06-01" \
         -d '{"model":"claude-deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
      log_ok "Existing virtual key is valid. Reusing: $(mask_key "$EXISTING_KEY")"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      log_info "Existing virtual key is invalid. Minting new key."
    fi
  fi
fi

if [ -z "$VIRTUAL_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    log_info "Would mint key (alias=claude-code, unlimited budget)"
    VIRTUAL_KEY="sk-dryrun-placeholder"
  else
    resolve_master_key "$PROJECT_DIR" || exit 1
    VIRTUAL_KEY=$(mint_or_reuse_key "claude-code" --no-budget)
    if [ -z "$VIRTUAL_KEY" ] || [[ "$VIRTUAL_KEY" != sk-* ]]; then
      log_error "Failed to mint virtual key."
      exit 1
    fi
    log_ok "Virtual key: $(mask_key "$VIRTUAL_KEY")"
  fi
fi

# ── 4. Write settings.json ──
log_info "4. Writing Claude Code CLI config..."
if [ "$DRY_RUN" = true ]; then
  log_info "Would write: $CLAUDE_SETTINGS, ~/.claude.json"
  echo ""
  log_ok "Dry run complete — no changes made"
  exit 0
fi

mkdir -p "$CLAUDE_CONFIG_DIR"

NEW_ENV_BLOCK=$(jq -n \
  --arg base_url "http://127.0.0.1:4000" \
  --arg api_key "$VIRTUAL_KEY" \
  --arg model "claude-glm-5.2" \
  --arg fast_model "claude-deepseek-v3.2" \
  '{env: {ANTHROPIC_BASE_URL: $base_url, ANTHROPIC_API_KEY: $api_key, ANTHROPIC_MODEL: $model, ANTHROPIC_SMALL_FAST_MODEL: $fast_model, CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL: "1"}}')

if [ -f "$CLAUDE_SETTINGS" ]; then
  EXISTING_SETTINGS=$(cat "$CLAUDE_SETTINGS")
  if echo "$EXISTING_SETTINGS" | jq -e . >/dev/null 2>&1; then
    MERGED_SETTINGS=$(echo "$EXISTING_SETTINGS" "$NEW_ENV_BLOCK" | jq -s '.[0] * .[1]')
    if [ "$MERGED_SETTINGS" = "$EXISTING_SETTINGS" ]; then
      log_info "settings.json unchanged — skipping write"
    else
      EXISTING_KEYS=$(echo "$EXISTING_SETTINGS" | jq -r 'keys | .[]' 2>/dev/null | sort | uniq)
      NON_ENV_KEYS=$(echo "$EXISTING_KEYS" | grep -v '^env$' || true)
      if [ -n "$NON_ENV_KEYS" ]; then
        log_warn "Overwriting existing settings with keys: $(echo "$NON_ENV_KEYS" | tr '\n' ' ')"
      fi
      cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
      echo "$MERGED_SETTINGS" > "$CLAUDE_SETTINGS"
      chmod 600 "$CLAUDE_SETTINGS"
      log_ok "Updated: $CLAUDE_SETTINGS (backup saved, merged env block)"
    fi
  else
    log_warn "Existing settings.json is invalid JSON — creating backup and overwriting"
    cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_ENV_BLOCK" > "$CLAUDE_SETTINGS"
    chmod 600 "$CLAUDE_SETTINGS"
    log_ok "Written: $CLAUDE_SETTINGS (backup saved)"
  fi
else
  echo "$NEW_ENV_BLOCK" > "$CLAUDE_SETTINGS"
  chmod 600 "$CLAUDE_SETTINGS"
  log_ok "Written: $CLAUDE_SETTINGS"
fi

# ── 5. Disable VSCode extension auto-install ──
log_info "5. Disabling VSCode extension auto-install..."
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$CLAUDE_JSON" ]; then
  CURRENT=$(jq '.autoInstallIdeExtension // empty' "$CLAUDE_JSON" 2>/dev/null || true)
  if [ "$CURRENT" = "false" ]; then
    log_info "autoInstallIdeExtension already false"
  else
    jq '.autoInstallIdeExtension = false' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
    log_ok "Set autoInstallIdeExtension=false in ~/.claude.json"
  fi
else
  echo '{"autoInstallIdeExtension": false}' > "$CLAUDE_JSON"
  log_ok "Created ~/.claude.json with autoInstallIdeExtension=false"
fi

if command -v code &>/dev/null; then
  if code --list-extensions 2>/dev/null | grep -qi "anthropic.claude-code"; then
    code --uninstall-extension anthropic.claude-code 2>/dev/null && \
      log_ok "Uninstalled anthropic.claude-code VSCode extension" || \
      log_warn "could not uninstall VSCode extension"
  else
    log_info "VSCode extension not installed — nothing to remove"
  fi
else
  log_info "VSCode CLI (code) not found — skipping extension check"
fi

echo ""
log_ok "Claude Code CLI installation complete"
log_info "Default model: claude-glm-5.2"
log_info "Run: claude --bare"
