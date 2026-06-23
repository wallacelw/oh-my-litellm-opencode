#!/usr/bin/env bash
set -euo pipefail

# ─── opencode + oh-my-opencode-slim installer for Huawei MaaS via LiteLLM ───
#
# Prerequisites:
#   - Docker + Docker Compose V2 installed (for LiteLLM proxy)
#   - LiteLLM proxy running on 127.0.0.1:4000 (deployed by bootstrap.sh or docker compose up -d)
#   - bun installed (https://bun.sh)
#   - jq installed (https://stedolan.github.io/jq/)
#   - LITELLM_MASTER_KEY set in environment
#
# Usage:
#   ./3_install.sh                          # interactive — prompts for keys
#   ./3_install.sh --virtual-key=sk-...     # non-interactive — use existing virtual key
#   ./3_install.sh --dry-run                # preview changes without modifying anything

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OPENCODE_DIR="$HOME/.config/opencode"
OPENCODE_CONFIG="$OPENCODE_DIR/opencode.jsonc"

# ── Constants ──
SLIM_VERSION="2.0.5"
OPENCODE_INSTALL_URL="https://opencode.ai/install"
CURL_TIMEOUT=15

# ── Helper: retry curl with backoff ──
# Usage: retry_curl [-o] curl_args...
#   -o  capture and echo response body (otherwise just check exit code)
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

# ── Helper: strip JSONC comments for jq ──
# Only removes // comments outside of quoted strings
strip_jsonc() {
  python3 -c "
import sys
text = sys.stdin.read()
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

# ── Parse args ──
VIRTUAL_KEY=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)       DRY_RUN=true ;;
  esac
done

echo "=== opencode + oh-my-opencode-slim installer for Huawei MaaS ==="
if [ "$DRY_RUN" = true ]; then
  echo "   (DRY RUN — no changes will be made)"
fi
echo ""

# ── 1. Check prerequisites ──
echo "1. Checking prerequisites..."

if ! command -v bun &>/dev/null; then
  echo "ERROR: bun is not installed. Install from https://bun.sh"
  exit 1
fi
echo "   bun: $(bun --version)"

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is not installed. Install from https://stedolan.github.io/jq/"
  exit 1
fi
echo "   jq: $(jq --version)"

if ! command -v docker &>/dev/null; then
  echo "WARNING: docker is not installed. LiteLLM proxy requires Docker — opencode will work but cannot reach the proxy."
  echo "   Install: https://docs.docker.com/engine/install/"
else
  if docker compose version &>/dev/null; then
    echo "   docker compose: $(docker compose version --short 2>/dev/null)"
  else
    echo "WARNING: Docker Compose V2 not available. Install via 'apt install docker-compose-v2' or similar."
  fi
fi

if ! command -v opencode &>/dev/null; then
  echo "   opencode: not found — will install via curl"
else
  echo "   opencode: $(opencode --version 2>/dev/null || echo 'installed')"
fi

# Check LiteLLM is reachable
if curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/health/liveliness" &>/dev/null; then
  echo "   LiteLLM proxy: reachable at http://127.0.0.1:4000"
else
    echo "WARNING: LiteLLM proxy not reachable at http://127.0.0.1:4000. Start it first with: docker compose up -d"
fi

echo ""

# ── 2. Install opencode ──
echo "2. Installing opencode..."
if ! command -v opencode &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    echo "   Would run: curl -fsSL $OPENCODE_INSTALL_URL | bash"
  else
    TMPFILE=$(mktemp /tmp/opencode_install.XXXXXX.sh)
    if curl -fsSL --max-time 30 "$OPENCODE_INSTALL_URL" -o "$TMPFILE"; then
      bash "$TMPFILE"
      echo "   Installed: $(opencode --version 2>/dev/null)"
    else
      echo "ERROR: Failed to download opencode install script."
      rm -f "$TMPFILE"
      exit 1
    fi
    rm -f "$TMPFILE"
  fi
else
  INSTALLED_VERSION="$(opencode --version 2>/dev/null || echo 'unknown')"
  echo "   Already installed: $INSTALLED_VERSION"
fi
echo ""

# ── 3. Install oh-my-opencode-slim plugin ──
echo "3. Installing oh-my-opencode-slim plugin (v${SLIM_VERSION})..."
if [ -f "$OPENCODE_DIR/oh-my-opencode-slim.json" ] || [ -f "$OPENCODE_DIR/oh-my-opencode-slim.jsonc" ]; then
  echo "   Plugin already installed — skipping"
else
  if [ "$DRY_RUN" = true ]; then
    echo "   Would run: bunx oh-my-opencode-slim@${SLIM_VERSION} install --companion=yes"
  else
    bunx "oh-my-opencode-slim@${SLIM_VERSION}" install --companion=yes
    echo "   Plugin installed."
  fi
fi
echo ""

# ── 4. Acquire virtual key (idempotent — reuse existing if valid) ──
echo "4. Configuring LiteLLM virtual key..."

# Try to reuse existing key by alias via /key/list + /key/info (best-effort)
if [ -z "$VIRTUAL_KEY" ] && [ -n "${LITELLM_MASTER_KEY:-}" ]; then
  KEY_LIST=$(curl -sf -m 10 "http://127.0.0.1:4000/key/list" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
  if [ -n "$KEY_LIST" ]; then
    # /key/list returns key IDs; check /key/info for each to find matching alias
    # Limit lookups to avoid O(N) API calls with many keys
    KEY_LOOKUP_COUNT=0
    for KEY_ID in $(echo "$KEY_LIST" | jq -r '.keys[]' 2>/dev/null); do
      [ $KEY_LOOKUP_COUNT -ge 50 ] && { echo "   Stopped alias lookup after 50 keys."; break; }
      KEY_LOOKUP_COUNT=$((KEY_LOOKUP_COUNT + 1))
      KEY_INFO=$(curl -sf -m 10 "http://127.0.0.1:4000/key/info?key=$KEY_ID" \
        -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
      if [ -n "$KEY_INFO" ]; then
        ALIAS=$(echo "$KEY_INFO" | jq -r '.info.key_alias // empty' 2>/dev/null)
        if [ "$ALIAS" = "opencode" ]; then
          ALIAS_KEY=$(echo "$KEY_INFO" | jq -r '.info.key_name // empty' 2>/dev/null)
          if [ -n "$ALIAS_KEY" ] && [[ "$ALIAS_KEY" == sk-* ]]; then
            if [ "$DRY_RUN" = true ]; then
              echo "   Would test existing key by alias: ${ALIAS_KEY:0:8}...${ALIAS_KEY: -4}"
              VIRTUAL_KEY="$ALIAS_KEY"
             elif retry_curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/v1/chat/completions" \
                  -H "Authorization: Bearer $ALIAS_KEY" \
                  -H "Content-Type: application/json" \
                  -d '{"model":"deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
              echo "   Existing virtual key (alias 'opencode') is valid. Reusing: ${ALIAS_KEY:0:8}...${ALIAS_KEY: -4}"
              VIRTUAL_KEY="$ALIAS_KEY"
            fi
            break
          fi
        fi
      fi
    done
  fi
fi

# Try to reuse existing key from current opencode config
if [ -z "$VIRTUAL_KEY" ] && [ -f "$OPENCODE_CONFIG" ]; then
  EXISTING_KEY=$(strip_jsonc "$OPENCODE_CONFIG" | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "null" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      echo "   Would test existing key: ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/v1/chat/completions" \
         -H "Authorization: Bearer $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -d '{"model":"deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
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
    echo "   Would mint new virtual key with alias 'opencode', unlimited budget & duration, all models"
  else
    echo "   Minting virtual key from LiteLLM (unlimited budget, unlimited duration)..."
    RESPONSE=$(retry_curl -o -sf -X POST "http://127.0.0.1:4000/key/generate" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d '{"key_alias": "opencode", "duration": null}')
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

# ── 5. Write opencode.jsonc ──
echo "5. Writing opencode config..."

if [ "$DRY_RUN" = true ]; then
  echo "   Would write: $OPENCODE_CONFIG (chmod 600)"
   echo "   Template: $PROJECT_DIR/configs/templates/opencode.json.template"
  echo "   Substitutions: <LITELLM_VIRTUAL_KEY> → ${VIRTUAL_KEY:0:8}..., <HUAWEI_MAAS_API_KEY> → from env"
  echo ""
  echo "6. Writing oh-my-opencode-slim config..."
  echo "   Would write: $OPENCODE_DIR/oh-my-opencode-slim.json (chmod 600)"
  echo ""
  echo "=== Dry run complete — no changes made ==="
  exit 0
fi

mkdir -p "$OPENCODE_DIR"

# Get Huawei MaaS API key
HUAWEI_MAAS_API_KEY="${HUAWEI_MAAS_API_KEY:-}"
if [ -z "$HUAWEI_MAAS_API_KEY" ]; then
  echo "   Enter Huawei MaaS API key (or press Enter to skip direct provider):"
  read -r HUAWEI_MAAS_API_KEY < /dev/tty
fi

# Build opencode.jsonc from template using jq for JSON-safe substitution
TEMPLATE="$PROJECT_DIR/configs/templates/opencode.json.template"
TARGET="$OPENCODE_CONFIG"

NEW_CONFIG=$(jq --arg vk "$VIRTUAL_KEY" --arg mk "${HUAWEI_MAAS_API_KEY:-<HUAWEI_MAAS_API_KEY>}" \
  '.provider.LiteLLM.options.apiKey = $vk |
   .provider["Huawei-MaaS"].options.apiKey = $mk' \
  "$TEMPLATE")

if [ -z "$NEW_CONFIG" ] || ! echo "$NEW_CONFIG" | jq -e . >/dev/null 2>&1; then
  echo "ERROR: Failed to generate opencode config from template. Check $TEMPLATE is valid JSON."
  exit 1
fi

if [ -f "$TARGET" ]; then
  EXISTING_CONFIG=$(cat "$TARGET")
  if [ "$NEW_CONFIG" = "$EXISTING_CONFIG" ]; then
    echo "   Config unchanged — skipping write"
  else
    # Warn if existing config has non-LiteLLM providers
    EXISTING_PROVIDERS=$(strip_jsonc "$TARGET" | jq -r '.provider | keys[]' 2>/dev/null | grep -v '^LiteLLM$' | grep -v '^Huawei-MaaS$' || true)
    if [ -n "$EXISTING_PROVIDERS" ]; then
      echo "   WARNING: Existing config has non-LiteLLM/Huawei-MaaS providers: $EXISTING_PROVIDERS"
      echo "   These will be overwritten. Backing up."
    fi
    cp "$TARGET" "$TARGET.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_CONFIG" > "$TARGET"
    chmod 600 "$TARGET"
    echo "   Updated: $TARGET (backup saved)"
  fi
else
  echo "$NEW_CONFIG" > "$TARGET"
  chmod 600 "$TARGET"
  echo "   Written: $TARGET"
fi
echo ""

# ── 6. Write oh-my-opencode-slim.json ──
echo "6. Writing oh-my-opencode-slim config..."
SLIM_CONFIG="$OPENCODE_DIR/oh-my-opencode-slim.json"
SLIM_TEMPLATE="$PROJECT_DIR/configs/templates/oh-my-opencode-slim.json.template"

NEW_SLIM=$(cat "$SLIM_TEMPLATE")

if [ -z "$NEW_SLIM" ] || ! echo "$NEW_SLIM" | jq -e . >/dev/null 2>&1; then
  echo "ERROR: Failed to read slim template. Check $SLIM_TEMPLATE is valid JSON."
  exit 1
fi

if [ -f "$SLIM_CONFIG" ]; then
  EXISTING_SLIM=$(cat "$SLIM_CONFIG")
  if [ "$NEW_SLIM" = "$EXISTING_SLIM" ]; then
    echo "   Config unchanged — skipping write"
  else
    cp "$SLIM_CONFIG" "$SLIM_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_SLIM" > "$SLIM_CONFIG"
    chmod 600 "$SLIM_CONFIG"
    echo "   Updated: $SLIM_CONFIG (backup saved)"
  fi
else
  echo "$NEW_SLIM" > "$SLIM_CONFIG"
  chmod 600 "$SLIM_CONFIG"
  echo "   Written: $SLIM_CONFIG"
fi
echo ""

# ── 7. Summary ──
echo "=== Installation complete ==="
echo ""
echo "Config files:"
echo "  opencode:             $TARGET (chmod 600)"
echo "  oh-my-opencode-slim:  $SLIM_CONFIG (chmod 600)"
echo ""
echo "Versions:"
echo "  oh-my-opencode-slim:  v${SLIM_VERSION}"
command -v opencode &>/dev/null && echo "  opencode:             $(opencode --version 2>/dev/null || echo 'unknown')"
echo ""
echo "Preset: LiteLLM-Huawei-MaaS-Full (default) — all 5 models via LiteLLM"
echo "Core:    LiteLLM-Huawei-MaaS-Core — glm-5.1, glm-5, deepseek-v3.2 only"
echo "Direct: Huawei-MaaS-Full / Huawei-MaaS-Core — bypass LiteLLM proxy"
echo "Switch preset at runtime: /preset LiteLLM-Huawei-MaaS-Core"
echo ""
echo "LiteLLM proxy URL: http://127.0.0.1:4000"
echo ""
echo "Next steps:"
  echo "  1. Validate: $SCRIPT_DIR/5_validate.sh"
echo "  2. Run: opencode"
