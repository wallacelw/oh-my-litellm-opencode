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

if ! command -v npm &>/dev/null; then
  echo "ERROR: npm is not installed. Install Node.js from https://nodejs.org/"
  exit 1
fi
echo "   npm: $(npm --version)"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Install from https://stedolan.github.io/jq/"
  exit 1
fi
echo "   jq: $(jq --version)"

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

# Try to reuse existing key by alias via /key/list + /key/info (slow, remote)
if [ -z "$VIRTUAL_KEY" ] && [ -n "${LITELLM_MASTER_KEY:-}" ]; then
  KEY_LIST=$(curl -sf -m 10 "$LITELLM_URL/key/list" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
  if [ -n "$KEY_LIST" ]; then
    KEY_LOOKUP_COUNT=0
    for KEY_ID in $(echo "$KEY_LIST" | jq -r '.keys[]' 2>/dev/null); do
      [ "$KEY_LOOKUP_COUNT" -ge 50 ] && { echo "   Stopped alias lookup after 50 keys."; break; }
      KEY_LOOKUP_COUNT=$((KEY_LOOKUP_COUNT + 1))
      KEY_INFO=$(curl -sf -m 10 "$LITELLM_URL/key/info?key=$KEY_ID" \
        -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
      if [ -n "$KEY_INFO" ]; then
        ALIAS=$(echo "$KEY_INFO" | jq -r '.info.key_alias // empty' 2>/dev/null)
        if [ "$ALIAS" = "claude-code" ]; then
          ALIAS_KEY=$(echo "$KEY_INFO" | jq -r '.info.key_name // empty' 2>/dev/null)
          if [ -n "$ALIAS_KEY" ] && [[ "$ALIAS_KEY" == sk-* ]]; then
            if [ "$DRY_RUN" = true ]; then
              echo "   Would test existing key by alias: ${ALIAS_KEY:0:8}...${ALIAS_KEY: -4}"
              VIRTUAL_KEY="$ALIAS_KEY"
            elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/messages" \
                 -H "x-api-key: $ALIAS_KEY" \
                 -H "Content-Type: application/json" \
                 -H "anthropic-version: 2023-06-01" \
                 -d '{"model":"claude-deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
              echo "   Existing virtual key (alias 'claude-code') is valid. Reusing: ${ALIAS_KEY:0:8}...${ALIAS_KEY: -4}"
              VIRTUAL_KEY="$ALIAS_KEY"
            else
              echo "   Existing virtual key (alias 'claude-code') is invalid or expired. Will mint new key."
            fi
            break
          fi
        fi
      fi
    done
  fi
fi

# Mint new key if needed
if [ -z "$VIRTUAL_KEY" ]; then
  if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    echo "  LITELLM_MASTER_KEY not set. Enter it (or Ctrl+C to abort):"
    read -r LITELLM_MASTER_KEY < /dev/tty
    if [ -z "$LITELLM_MASTER_KEY" ]; then
      echo "ERROR: LITELLM_MASTER_KEY is required to mint virtual keys."
      exit 1
    fi
    export LITELLM_MASTER_KEY
  fi
  if [ "$DRY_RUN" = true ]; then
    echo "   Would mint new virtual key with alias 'claude-code', unlimited budget & duration, all models"
  else
    echo "   Minting virtual key from LiteLLM (unlimited budget, unlimited duration)..."
    RESPONSE=$(retry_curl -o -sf -X POST "$LITELLM_URL/key/generate" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d '{"key_alias": "claude-code", "duration": null}' || true)
    if [ -z "$RESPONSE" ]; then
      echo "ERROR: Failed to mint virtual key after 3 attempts. Check LiteLLM health and master key."
      exit 1
    fi
    VIRTUAL_KEY=$(echo "$RESPONSE" | jq -r '.key')
    if [ -z "$VIRTUAL_KEY" ] || [ "$VIRTUAL_KEY" = "null" ]; then
      echo "ERROR: Failed to mint virtual key. Response: $RESPONSE"
      exit 1
    fi
    echo "   Virtual key minted: ${VIRTUAL_KEY:0:8}...${VIRTUAL_KEY: -4}"
  fi
fi
echo ""

# ── 4. Write settings.json ──
echo "4. Writing Claude Code CLI config..."

if [ "$DRY_RUN" = true ]; then
  echo "   Would write: $CLAUDE_SETTINGS (chmod 600)"
  echo ""
  echo "=== Dry run complete — no changes made ==="
  exit 0
fi

mkdir -p "$CLAUDE_CONFIG_DIR"

# Build settings.json — Claude Code's native config format
# The env block sets ANTHROPIC_* vars without needing shell exports
NEW_SETTINGS=$(jq -n \
  --arg base_url "http://127.0.0.1:4000" \
  --arg api_key "$VIRTUAL_KEY" \
  --arg model "claude-glm-5.2" \
  --arg fast_model "claude-deepseek-v3.2" \
  '{env: {ANTHROPIC_BASE_URL: $base_url, ANTHROPIC_API_KEY: $api_key, ANTHROPIC_MODEL: $model, ANTHROPIC_SMALL_FAST_MODEL: $fast_model}}')

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

# ── 5. Summary ──
echo "=== Installation complete ==="
echo ""
echo "Config files:"
echo "  Claude Code: $CLAUDE_SETTINGS (chmod 600)"
echo ""
echo "Versions:"
command -v claude &>/dev/null && echo "  claude:     $(claude --version 2>/dev/null || echo 'unknown')"
echo ""
echo "Default model: claude-glm-5.2"
echo "Fast model:    claude-deepseek-v3.2"
echo "All 6 models available via LiteLLM proxy (Anthropic Messages API)"
echo "LiteLLM proxy URL: $LITELLM_URL"
echo ""
echo "Next steps:"
echo "  1. Run:              claude --bare"
echo "  2. Validate:         $SCRIPT_DIR/5_validate.sh"
