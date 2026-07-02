#!/usr/bin/env bash
set -euo pipefail

# ─── 03_opencode.sh — opencode tool (pipeline step 03, optional) ──────────────
#
# Domain:        opencode + oh-my-opencode-slim plugin
# Order:         03 (after LiteLLM proxy is live)
# Optional:      yes (runs only if opencode is in the selection)
# Description:   Install the opencode binary, the oh-my-opencode-slim plugin
#                (4 presets, 7 agents), mint a LiteLLM virtual key (alias
#                "opencode"), and write opencode.json + slim config pointing
#                to the LiteLLM proxy.
# Inputs:        .env (LITELLM_MASTER_KEY, HUAWEI_MAAS_API_KEY), --virtual-key,
#                --dry-run
# Outputs:       ~/.config/opencode/opencode.json,
#                ~/.config/opencode/oh-my-opencode-slim.json
# Standalone:    yes — ./scripts/03_opencode.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENCODE_DIR="$HOME/.config/opencode"
OPENCODE_CONFIG="$OPENCODE_DIR/opencode.json"

SLIM_VERSION="2.0.5"
OPENCODE_INSTALL_URL="https://opencode.ai/install"
CURL_TIMEOUT=15

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/keys.sh"
source_env "$PROJECT_DIR"

LOG_TAG="opencode"

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

log_step "Step 03 — opencode + oh-my-opencode-slim"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── 1. Check prerequisites ──
log_info "Checking prerequisites..."
prereq_ensure_apt "curl" curl curl
prereq_ensure_apt "jq"   jq   jq
prereq_ensure_bun

if curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/health/liveliness" &>/dev/null; then
  log_ok "LiteLLM proxy: reachable"
else
  log_error "LiteLLM proxy not reachable at http://127.0.0.1:4000. Start it first."
  exit 1
fi

# ── 2. Install opencode ──
log_info "Installing opencode..."
if ! command -v opencode &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    log_dim "Would run: curl -fsSL $OPENCODE_INSTALL_URL | bash"
  else
    TMPFILE=$(mktemp /tmp/opencode_install.XXXXXX.sh)
    if curl -fsSL --max-time 30 "$OPENCODE_INSTALL_URL" -o "$TMPFILE"; then
      run_filtered "opencode:installer" bash "$TMPFILE"
      log_ok "Installed: $(opencode --version 2>/dev/null)"
    else
      log_error "Failed to download opencode install script."
      rm -f "$TMPFILE"; exit 1
    fi
    rm -f "$TMPFILE"
  fi
else
  log_ok "Already installed: $(opencode --version 2>/dev/null || echo 'unknown')"
fi

# ── 3. Install oh-my-opencode-slim plugin ──
log_info "Installing oh-my-opencode-slim plugin (v${SLIM_VERSION})..."
if [ -f "$OPENCODE_DIR/oh-my-opencode-slim.json" ] || [ -f "$OPENCODE_DIR/oh-my-opencode-slim.jsonc" ]; then
  log_ok "Plugin already installed — skipping"
elif [ "$DRY_RUN" = true ]; then
  log_dim "Would run: bunx oh-my-opencode-slim@${SLIM_VERSION} install --companion=no"
else
  run_filtered "slim" bunx "oh-my-opencode-slim@${SLIM_VERSION}" install --companion=no
  log_ok "Plugin installed."
fi

# ── 4. Acquire virtual key (idempotent) ──
log_info "Configuring LiteLLM virtual key..."

# Try to reuse existing key from current opencode config (fast, local)
if [ -z "$VIRTUAL_KEY" ] && [ -f "$OPENCODE_CONFIG" ]; then
  EXISTING_KEY=$(strip_jsonc "$OPENCODE_CONFIG" | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/v1/chat/completions" \
         -H "Authorization: Bearer $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -d '{"model":"deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
      log_ok "Existing virtual key is valid. Reusing: $(mask_key "$EXISTING_KEY")"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      log_warn "Existing virtual key is invalid or expired. Minting new key."
    fi
  fi
fi

if [ -z "$VIRTUAL_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    log_dim "Would mint key (alias=opencode, unlimited budget)"
    VIRTUAL_KEY="sk-dryrun-placeholder"
  else
    resolve_master_key "$PROJECT_DIR" || exit 1
    VIRTUAL_KEY=$(mint_or_reuse_key "opencode" --no-budget)
    if [ -z "$VIRTUAL_KEY" ] || [[ "$VIRTUAL_KEY" != sk-* ]]; then
      log_error "Failed to mint virtual key."
      exit 1
    fi
    log_ok "Virtual key: $(mask_key "$VIRTUAL_KEY")"
  fi
fi

# ── 5. Write opencode.json ──
log_info "Writing opencode config..."
if [ "$DRY_RUN" = true ]; then
  log_dim "Would write: $OPENCODE_CONFIG"
  log_dim "Would write: $OPENCODE_DIR/oh-my-opencode-slim.json"
  log_step "Dry run complete — no changes made"
  exit 0
fi

mkdir -p "$OPENCODE_DIR"

# Huawei MaaS API key for the direct provider (from .env, already sourced)
HUAWEI_MAAS_API_KEY="${HUAWEI_MAAS_API_KEY:-}"
if [ -z "$HUAWEI_MAAS_API_KEY" ] && [ -t 0 ]; then
  HUAWEI_MAAS_API_KEY=$(prompt_input "Huawei MaaS API key (or press Enter to skip direct provider)" "")
fi

TEMPLATE="$PROJECT_DIR/configs/opencode/opencode.json.template"

if [ -z "$HUAWEI_MAAS_API_KEY" ] || [ "$HUAWEI_MAAS_API_KEY" = "<HUAWEI_MAAS_API_KEY>" ]; then
  log_warn "No Huawei MaaS API key provided — omitting Huawei-MaaS direct provider"
  NEW_CONFIG=$(jq --arg vk "$VIRTUAL_KEY" \
    '.provider.LiteLLM.options.apiKey = $vk | del(.provider["Huawei-MaaS"])' \
    "$TEMPLATE")
else
  NEW_CONFIG=$(jq --arg vk "$VIRTUAL_KEY" --arg mk "$HUAWEI_MAAS_API_KEY" \
    '.provider.LiteLLM.options.apiKey = $vk |
     .provider["Huawei-MaaS"].options.apiKey = $mk' \
    "$TEMPLATE")
fi

if [ -z "$NEW_CONFIG" ] || ! echo "$NEW_CONFIG" | jq -e . >/dev/null 2>&1; then
  log_error "Failed to generate opencode config from template."
  exit 1
fi

if [ -f "$OPENCODE_CONFIG" ]; then
  if [ "$NEW_CONFIG" = "$(cat "$OPENCODE_CONFIG")" ]; then
    log_dim "Config unchanged — skipping write"
  else
    cp "$OPENCODE_CONFIG" "$OPENCODE_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_CONFIG" > "$OPENCODE_CONFIG"
    chmod 600 "$OPENCODE_CONFIG"
    log_ok "Updated: $OPENCODE_CONFIG (backup saved)"
  fi
else
  echo "$NEW_CONFIG" > "$OPENCODE_CONFIG"
  chmod 600 "$OPENCODE_CONFIG"
  log_ok "Written: $OPENCODE_CONFIG"
fi

# ── 6. Write oh-my-opencode-slim.json ──
log_info "Writing oh-my-opencode-slim config..."
SLIM_CONFIG="$OPENCODE_DIR/oh-my-opencode-slim.json"
SLIM_TEMPLATE="$PROJECT_DIR/configs/opencode/oh-my-opencode-slim.json.template"
NEW_SLIM=$(cat "$SLIM_TEMPLATE")

if [ -z "$NEW_SLIM" ] || ! echo "$NEW_SLIM" | jq -e . >/dev/null 2>&1; then
  log_error "Failed to read slim template."
  exit 1
fi

if [ -f "$SLIM_CONFIG" ]; then
  if [ "$NEW_SLIM" = "$(cat "$SLIM_CONFIG")" ]; then
    log_dim "Config unchanged — skipping write"
  else
    cp "$SLIM_CONFIG" "$SLIM_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_SLIM" > "$SLIM_CONFIG"
    chmod 600 "$SLIM_CONFIG"
    log_ok "Updated: $SLIM_CONFIG (backup saved)"
  fi
else
  echo "$NEW_SLIM" > "$SLIM_CONFIG"
  chmod 600 "$SLIM_CONFIG"
  log_ok "Written: $SLIM_CONFIG"
fi

log_step "opencode installation complete"
log_dim "Preset: LiteLLM-Huawei-MaaS-Full (default) — all 6 models via LiteLLM"
log_dim "Switch preset: /preset LiteLLM-Huawei-MaaS-Core"
