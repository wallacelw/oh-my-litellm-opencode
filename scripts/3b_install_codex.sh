#!/usr/bin/env bash
set -euo pipefail

# ─── Codex CLI installer for Huawei MaaS via LiteLLM ─────────────────────────
#
# Installs OpenAI Codex CLI, mints a LiteLLM virtual key (alias "codex"),
# and writes ~/.codex/config.toml pointing to the LiteLLM proxy.
#
# Codex CLI uses the Responses API (/v1/responses) exclusively. LiteLLM
# auto-bridges Responses → Chat Completions for custom_openai providers,
# so no custom workaround is needed.
#
# Prerequisites:
#   - LiteLLM proxy running on 127.0.0.1:4000
#   - npm installed (for Codex CLI installation)
#   - LITELLM_MASTER_KEY set in environment
#
# Usage:
#   ./3b_install_codex.sh                       # interactive
#   ./3b_install_codex.sh --virtual-key=sk-...  # use existing virtual key
#   ./3b_install_codex.sh --dry-run             # preview changes

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CODEX_DIR="$HOME/.codex"
CODEX_CONFIG="$CODEX_DIR/config.toml"
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

echo "=== Codex CLI installer for Huawei MaaS via LiteLLM ==="
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

# ── 2. Install Codex CLI ──
echo "2. Installing Codex CLI..."
if ! command -v codex &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    echo "   Would run: npm install -g @openai/codex"
  else
    npm install -g @openai/codex
    echo "   Installed: $(codex --version 2>/dev/null || echo 'unknown')"
  fi
else
  echo "   Already installed: $(codex --version 2>/dev/null || echo 'unknown')"
fi
echo ""

# ── 3. Acquire virtual key (idempotent — reuse existing if valid) ──
echo "3. Configuring LiteLLM virtual key..."

# Try to reuse existing key by alias via /key/list + /key/info
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
        if [ "$ALIAS" = "codex" ]; then
          ALIAS_KEY=$(echo "$KEY_INFO" | jq -r '.info.key_name // empty' 2>/dev/null)
          if [ -n "$ALIAS_KEY" ] && [[ "$ALIAS_KEY" == sk-* ]]; then
            if [ "$DRY_RUN" = true ]; then
              echo "   Would test existing key by alias: ${ALIAS_KEY:0:8}...${ALIAS_KEY: -4}"
              VIRTUAL_KEY="$ALIAS_KEY"
            elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/responses" \
                 -H "Authorization: Bearer $ALIAS_KEY" \
                 -H "Content-Type: application/json" \
                 -d '{"model":"deepseek-v3.2","input":"ok"}'; then
              echo "   Existing virtual key (alias 'codex') is valid. Reusing: ${ALIAS_KEY:0:8}...${ALIAS_KEY: -4}"
              VIRTUAL_KEY="$ALIAS_KEY"
            fi
            break
          fi
        fi
      fi
    done
  fi
fi

# Try to reuse existing key from current Codex config
if [ -z "$VIRTUAL_KEY" ] && [ -f "$CODEX_CONFIG" ]; then
  EXISTING_KEY=$(grep -oP '^openai_api_key\s*=\s*"\K[^"]+' "$CODEX_CONFIG" 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      echo "   Would test existing key: ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/responses" \
         -H "Authorization: Bearer $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -d '{"model":"deepseek-v3.2","input":"ok"}'; then
      echo "   Existing virtual key is valid. Reusing: ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      echo "   Existing virtual key is invalid or expired. Minting new key."
    fi
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
    echo "   Would mint new virtual key with alias 'codex', unlimited budget & duration, all models"
  else
    echo "   Minting virtual key from LiteLLM (unlimited budget, unlimited duration)..."
    RESPONSE=$(retry_curl -o -sf -X POST "$LITELLM_URL/key/generate" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d '{"key_alias": "codex", "duration": null}' || true)
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

# ── 4. Write config.toml ──
echo "4. Writing Codex CLI config..."

if [ "$DRY_RUN" = true ]; then
  echo "   Would write: $CODEX_CONFIG (chmod 600)"
  echo "   Template: $PROJECT_DIR/configs/codex/config.toml.template"
  echo "   Substitution: <LITELLM_VIRTUAL_KEY> → ${VIRTUAL_KEY:0:8}..."
  echo "   Would write: $CODEX_DIR/auth.json (chmod 600)"
  echo ""
  echo "=== Dry run complete — no changes made ==="
  exit 0
fi

mkdir -p "$CODEX_DIR"

TEMPLATE="$PROJECT_DIR/configs/codex/config.toml.template"
NEW_CONFIG=$(sed "s|<LITELLM_VIRTUAL_KEY>|$VIRTUAL_KEY|" "$TEMPLATE")

if [ -f "$CODEX_CONFIG" ]; then
  EXISTING_CONFIG=$(cat "$CODEX_CONFIG")
  if [ "$NEW_CONFIG" = "$EXISTING_CONFIG" ]; then
    echo "   Config unchanged — skipping write"
  else
    cp "$CODEX_CONFIG" "$CODEX_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_CONFIG" > "$CODEX_CONFIG"
    chmod 600 "$CODEX_CONFIG"
    echo "   Updated: $CODEX_CONFIG (backup saved)"
  fi
else
  echo "$NEW_CONFIG" > "$CODEX_CONFIG"
  chmod 600 "$CODEX_CONFIG"
  echo "   Written: $CODEX_CONFIG"
fi
echo ""

# ── 5. Authenticate (skip login screen) ──
echo "5. Authenticating Codex CLI..."
CODEX_AUTH="$CODEX_DIR/auth.json"
NEW_AUTH=$(printf '{"auth_mode":"apikey","OPENAI_API_KEY":"%s"}' "$VIRTUAL_KEY")

if [ -f "$CODEX_AUTH" ]; then
  EXISTING_AUTH=$(cat "$CODEX_AUTH")
  if [ "$NEW_AUTH" = "$EXISTING_AUTH" ]; then
    echo "   Auth unchanged — skipping write"
  else
    echo "$NEW_AUTH" > "$CODEX_AUTH"
    chmod 600 "$CODEX_AUTH"
    echo "   Updated: $CODEX_AUTH"
  fi
else
  echo "$NEW_AUTH" > "$CODEX_AUTH"
  chmod 600 "$CODEX_AUTH"
  echo "   Written: $CODEX_AUTH"
fi
echo ""

# ── 6. Summary ──
echo "=== Installation complete ==="
echo ""
echo "Config files:"
echo "  Codex CLI:  $CODEX_CONFIG (chmod 600)"
echo "  Auth:       $CODEX_DIR/auth.json (chmod 600)"
echo ""
echo "Versions:"
command -v codex &>/dev/null && echo "  codex:      $(codex --version 2>/dev/null || echo 'unknown')"
echo ""
echo "Default model: glm-5.2"
echo "All 6 models available via LiteLLM proxy"
echo "LiteLLM proxy URL: $LITELLM_URL"
echo ""
echo "Next steps:"
echo "  1. Validate: $SCRIPT_DIR/5_validate.sh"
echo "  2. Run: codex"
