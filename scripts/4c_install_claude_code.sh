#!/usr/bin/env bash
set -euo pipefail

# ─── Claude Code CLI installer for Huawei MaaS via LiteLLM ───────────────
#
# Installs Claude Code CLI, mints a LiteLLM virtual key (alias "claude-code"),
# and writes ~/.claude/settings.json pointing to the LiteLLM proxy.
#
# Claude Code CLI uses the Anthropic Messages API (/v1/messages). LiteLLM
# forwards to Huawei MaaS's Anthropic-compatible endpoint
# (/anthropic/v1/messages) via anthropic/ provider deployments in config.yaml.
#
# Configuration is written to ~/.claude/settings.json (Claude Code's native
# settings file) using the env block. No shell exports or source needed.
#
# Prerequisites:
#   - LiteLLM proxy running on 127.0.0.1:4000
#   - npm installed (for Claude Code CLI installation)
#   - LITELLM_MASTER_KEY set in environment
#
# Usage:
#   ./4c_install_claude_code.sh                       # interactive
#   ./4c_install_claude_code.sh --virtual-key=sk-...  # use existing virtual key
#   ./4c_install_claude_code.sh --dry-run             # preview changes

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CLAUDE_CONFIG_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
LITELLM_URL="http://127.0.0.1:4000"
CURL_TIMEOUT=15

# ── Parse args ──
VIRTUAL_KEY=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)       DRY_RUN=true ;;
  esac
done

echo "=== Claude Code CLI installer for Huawei MaaS via LiteLLM ==="
if [ "$DRY_RUN" = true ]; then
  echo "   (DRY RUN — no changes will be made)"
fi
echo ""

# ── Helper: retry curl with backoff ──
retry_curl() {
  local capture=false
  if [ "$1" = "-o" ]; then capture=true; shift; fi
  local max_attempts=3 delay=2 attempt=1 response="" err=""
  while [ $attempt -le $max_attempts ]; do
    if [ "$capture" = true ]; then
      response=$(curl "$@" 2>/dev/null) && [ -n "$response" ] && echo "$response" && return 0
    else
      err=$(curl "$@" 2>&1) && return 0
    fi
    [ $attempt -lt $max_attempts ] && sleep $delay
    ((attempt++))
  done
  [ -n "$err" ] && echo "  curl error: $err" >&2
  return 1
}

# ── 1. Check prerequisites ──
echo "1. Checking prerequisites..."

source "$(dirname "${BASH_SOURCE[0]}")/lib/prereqs.sh"
prereq_ensure_npm
prereq_ensure_apt "jq" jq jq

# Check LiteLLM is reachable
if curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/health/liveliness" &>/dev/null; then
  echo "   LiteLLM proxy: reachable at $LITELLM_URL"
else
  echo "ERROR: LiteLLM proxy not reachable at $LITELLM_URL. Start it first with: docker compose up -d"
  exit 1
fi

echo ""

# ── 2. Install Claude Code CLI ──
echo "2. Installing Claude Code CLI..."
if ! command -v claude &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    echo "   Would run: npm install -g @anthropic-ai/claude-code"
  else
    npm install -g @anthropic-ai/claude-code
    echo "   Installed: $(claude --version 2>/dev/null || echo 'unknown')"
  fi
else
  echo "   Already installed: $(claude --version 2>/dev/null || echo 'unknown')"
fi
echo ""

# ── 3. Acquire virtual key (idempotent — reuse existing if valid) ──
echo "3. Configuring LiteLLM virtual key..."

# Try to reuse existing key from ~/.claude/settings.json (fast, local)
if [ -z "$VIRTUAL_KEY" ] && [ -f "$CLAUDE_SETTINGS" ]; then
  EXISTING_KEY=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      echo "   Would test existing key from settings.json: ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/messages" \
         -H "x-api-key: $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -H "anthropic-version: 2023-06-01" \
         -d '{"model":"claude-deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
      echo "   Existing virtual key from settings.json is valid. Reusing: ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      echo "   Existing virtual key from settings.json is invalid or expired. Will try alias lookup."
    fi
  fi
fi

# Try to reuse existing key from environment (fast, local)
if [ -z "$VIRTUAL_KEY" ] && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  EXISTING_KEY="$ANTHROPIC_API_KEY"
  if [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      echo "   Would test existing key from env: ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/messages" \
         -H "x-api-key: $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -H "anthropic-version: 2023-06-01" \
         -d '{"model":"claude-deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
      echo "   Existing virtual key from env is valid. Reusing: ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      echo "   Existing virtual key from env is invalid or expired. Will try alias lookup."
    fi
  fi
fi

# Mint new key via 3_mint_key.sh if needed
if [ -z "$VIRTUAL_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "   Would mint key via 3_mint_key.sh --alias=claude-code --no-budget --quiet"
    VIRTUAL_KEY="sk-dryrun-placeholder"
  else
    VIRTUAL_KEY=$("$SCRIPT_DIR/3_mint_key.sh" --alias=claude-code --no-budget --quiet)
    if [ -z "$VIRTUAL_KEY" ] || [[ "$VIRTUAL_KEY" != sk-* ]]; then
      echo "ERROR: Failed to mint virtual key."
      exit 1
    fi
    echo "   Virtual key: ${VIRTUAL_KEY:0:8}...${VIRTUAL_KEY: -4}"
  fi
fi
echo ""

# ── 4. Write settings.json ──
echo "4. Writing Claude Code CLI config..."

if [ "$DRY_RUN" = true ]; then
  echo "   Would write: $CLAUDE_SETTINGS (chmod 600)"
  echo "   Would write: ~/.claude.json (autoInstallIdeExtension=false)"
  echo "   Would uninstall: anthropic.claude-code VSCode extension (if present)"
  echo ""
  echo "=== Dry run complete — no changes made ==="
  exit 0
fi

mkdir -p "$CLAUDE_CONFIG_DIR"

# Build settings.json — Claude Code's native config format
# The env block sets ANTHROPIC_* vars without needing shell exports
# CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1 prevents VSCode extension auto-install
NEW_SETTINGS=$(jq -n \
  --arg base_url "http://127.0.0.1:4000" \
  --arg api_key "$VIRTUAL_KEY" \
  --arg model "claude-glm-5.2" \
  --arg fast_model "claude-deepseek-v3.2" \
  '{env: {ANTHROPIC_BASE_URL: $base_url, ANTHROPIC_API_KEY: $api_key, ANTHROPIC_MODEL: $model, ANTHROPIC_SMALL_FAST_MODEL: $fast_model, CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL: "1"}}')

if [ -f "$CLAUDE_SETTINGS" ]; then
  EXISTING_SETTINGS=$(cat "$CLAUDE_SETTINGS")
  if [ "$NEW_SETTINGS" = "$EXISTING_SETTINGS" ]; then
    echo "   settings.json unchanged — skipping write"
  else
    cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_SETTINGS" > "$CLAUDE_SETTINGS"
    chmod 600 "$CLAUDE_SETTINGS"
    echo "   Updated: $CLAUDE_SETTINGS (backup saved)"
  fi
else
  echo "$NEW_SETTINGS" > "$CLAUDE_SETTINGS"
  chmod 600 "$CLAUDE_SETTINGS"
  echo "   Written: $CLAUDE_SETTINGS (chmod 600)"
fi
echo ""

# ── 5. Disable VSCode extension auto-install ──
echo "5. Disabling VSCode extension auto-install..."

# ~/.claude.json controls IDE integration (separate from settings.json)
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$CLAUDE_JSON" ]; then
  CURRENT=$(jq '.autoInstallIdeExtension // empty' "$CLAUDE_JSON" 2>/dev/null || true)
  if [ "$CURRENT" = "false" ]; then
    echo "   autoInstallIdeExtension already false in ~/.claude.json"
  else
    jq '.autoInstallIdeExtension = false' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
    echo "   Set autoInstallIdeExtension=false in ~/.claude.json"
  fi
else
  echo '{"autoInstallIdeExtension": false}' > "$CLAUDE_JSON"
  echo "   Created ~/.claude.json with autoInstallIdeExtension=false"
fi

# Uninstall VSCode extension if already installed
if command -v code &>/dev/null; then
  if code --list-extensions 2>/dev/null | grep -qi "anthropic.claude-code"; then
    code --uninstall-extension anthropic.claude-code 2>/dev/null && \
      echo "   Uninstalled anthropic.claude-code VSCode extension" || \
      echo "   Warning: could not uninstall VSCode extension"
  else
    echo "   VSCode extension not installed — nothing to remove"
  fi
else
  echo "   VSCode CLI (code) not found — skipping extension check"
fi
echo ""

# ── 6. Summary ──
echo "=== Installation complete ==="
echo ""
echo "Config files:"
echo "  Claude Code: $CLAUDE_SETTINGS (chmod 600)"
echo "  IDE disable: ~/.claude.json (autoInstallIdeExtension=false)"
echo ""
echo "Versions:"
command -v claude &>/dev/null && echo "  claude:     $(claude --version 2>/dev/null || echo 'unknown')"
echo ""
echo "Default model: claude-glm-5.2"
echo "Fast model:    claude-deepseek-v3.2"
echo "All 6 models available via LiteLLM proxy (Anthropic Messages API)"
echo "LiteLLM proxy URL: $LITELLM_URL"
echo "VSCode extension: disabled (CLI-only)"
echo ""
echo "Next steps:"
echo "  1. Run:              claude --bare"
echo "  2. Validate:         $SCRIPT_DIR/5_validate.sh"
