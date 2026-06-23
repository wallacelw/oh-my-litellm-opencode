#!/usr/bin/env bash
set -euo pipefail

# ─── oh-my-litellm-opencode Bootstrap ────────────────────────────────────────
#
# End-to-end orchestrator: deploy LiteLLM proxy → install
# opencode + oh-my-opencode-slim → mint virtual key → configure → validate.
#
# Idempotent — safe to re-run.
#
# This is a single-repo skill. LiteLLM proxy and opencode config live together.
# No monorepo extraction needed — just git clone this repo.
#
# Canonical path: /home/oh-my-litellm-opencode
#
# Usage:
#   ./bootstrap.sh                                    # interactive — prompts for keys
#   ./bootstrap.sh --maas-key=KEY                     # non-interactive (agent mode)
#   ./bootstrap.sh --virtual-key=sk-...               # use existing virtual key (skip minting)
#   ./bootstrap.sh --dry-run                          # preview changes
# ──────────────────────────────────────────────────────────────────────────────

# ── Constants ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LITELLM_URL="http://127.0.0.1:4000"
CURL_TIMEOUT=15

# ── Defaults ──
MAAS_KEY=""
VIRTUAL_KEY=""
DRY_RUN=false

# ── Parse command-line arguments ──
for arg in "$@"; do
  case "$arg" in
    --maas-key=*)       MAAS_KEY="${arg#--maas-key=}" ;;
    --virtual-key=*)    VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)          DRY_RUN=true ;;
    *)
      echo "ERROR: Unknown argument: $arg"
      echo "Usage: $0 [--maas-key=KEY] [--virtual-key=sk-...] [--dry-run]"
      exit 1
      ;;
  esac
done

# ── Resolve LITELLM_MASTER_KEY from multiple sources ──
# Returns the key on stdout; log messages go to stderr.
resolve_master_key() {
  # 1. Environment variable
  if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    echo "  Found LITELLM_MASTER_KEY in environment" >&2
    echo "$LITELLM_MASTER_KEY"
    return 0
  fi

  # 2. .master-key file
  if [ -f "$PROJECT_DIR/.master-key" ]; then
    local found_key
    found_key="$(cat "$PROJECT_DIR/.master-key")"
    if [ -n "$found_key" ]; then
      echo "  Found LITELLM_MASTER_KEY in $PROJECT_DIR/.master-key" >&2
      echo "$found_key"
      return 0
    fi
  fi

  # 3. .env file
  if [ -f "$PROJECT_DIR/.env" ]; then
    local found_key
    found_key="$(grep -oP '^LITELLM_MASTER_KEY="?\K[^"]+' "$PROJECT_DIR/.env" 2>/dev/null || true)"
    if [ -n "$found_key" ]; then
      echo "  Found LITELLM_MASTER_KEY in $PROJECT_DIR/.env" >&2
      # Cache to .master-key for faster future resolution
      echo "$found_key" > "$PROJECT_DIR/.master-key"
      chmod 600 "$PROJECT_DIR/.master-key"
      echo "$found_key"
      return 0
    fi
  fi

  return 1
}

# ── Prompt for LITELLM_MASTER_KEY if not found automatically ──
prompt_master_key() {
  if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    echo "  LITELLM_MASTER_KEY not found in env, .master-key, or .env files."
    echo "  Enter LITELLM_MASTER_KEY (or Ctrl+C to abort):"
    read -r LITELLM_MASTER_KEY < /dev/tty
    if [ -z "$LITELLM_MASTER_KEY" ]; then
      echo "ERROR: LITELLM_MASTER_KEY is required to mint virtual keys."
      exit 1
    fi
  fi
}

# ── Try to resolve master key from files/env, set LITELLM_MASTER_KEY ──
try_resolve_master_key() {
  LITELLM_MASTER_KEY="$(resolve_master_key)" || return 1
  return 0
}

# ── Wait for LiteLLM to become healthy (up to 90s) ──
wait_for_litellm() {
  echo "  Waiting for LiteLLM to become healthy (up to 90s)..."
  local waited=0
  while [ $waited -lt 90 ]; do
    if curl -sf -m "$CURL_TIMEOUT" "$LITELLM_URL/health/liveliness" &>/dev/null; then
      echo "  ✓ LiteLLM healthy after ~${waited}s."
      return 0
    fi
    printf "  ."
    sleep 5
    waited=$((waited + 5))
  done
  echo ""
  echo "ERROR: LiteLLM did not become healthy within 90s. Check: docker compose logs"
  exit 1
}

print_step() { echo ""; echo "─── Step ${1}: ${2} ───"; }

# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Banner
# ──────────────────────────────────────────────────────────────────────────────
echo ""
echo "=== oh-my-litellm-opencode Bootstrap ==="
echo "   Project dir: $PROJECT_DIR"
[ "$DRY_RUN" = true ] && echo "   (DRY RUN — no changes will be made)"

# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Check prerequisites
# ──────────────────────────────────────────────────────────────────────────────
print_step "2" "Check prerequisites"

PREREQ_OK=true

check_prereq() {
  local name="$1" cmd="$2"
  if ! command -v "$cmd" &>/dev/null; then
    echo "  ✗ $name NOT found — $3"
    PREREQ_OK=false
  else
    echo "  ✓ $name: $($cmd --version 2>/dev/null | head -1 || echo 'found')"
  fi
}

check_prereq "bun"     bun     "install from https://bun.sh (needed for oh-my-opencode-slim plugin)"
check_prereq "jq"      jq      "install from https://stedolan.github.io/jq/"
check_prereq "docker"  docker  "install from https://docs.docker.com/engine/install/"
check_prereq "git"     git     "install git"
check_prereq "python3" python3 "install Python 3"

if command -v docker &>/dev/null && ! docker compose version &>/dev/null; then
  echo "  ✗ docker compose V2 NOT found"
  PREREQ_OK=false
fi

# Resolve MaaS key
if [ -z "$MAAS_KEY" ]; then MAAS_KEY="${HUAWEI_MAAS_API_KEY:-}"; fi
if [ -z "$MAAS_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    MAAS_KEY="<HUAWEI_MAAS_API_KEY>"
  else
    echo ""; echo "  Enter Huawei MaaS API key:"; read -r MAAS_KEY < /dev/tty
    [ -z "$MAAS_KEY" ] && { echo "ERROR: MaaS API key is required."; PREREQ_OK=false; }
  fi
else
  echo "  ✓ Huawei MaaS API key set"
fi
[ "$PREREQ_OK" = false ] && { echo ""; echo "ERROR: Prerequisites missing. Install them and re-run."; exit 1; }

export HUAWEI_MAAS_API_KEY="$MAAS_KEY"
export HUAWEI_MAAS_API_KEY_0="$MAAS_KEY"

# ── Collect extra MaaS API keys for load balancing ──
# Always prompt — user can press Enter to skip (0 extra keys)
EXTRA_KEY_COUNT=0
if [ "$DRY_RUN" = true ]; then
  echo "  (Would prompt for additional MaaS API keys)"
else
  echo ""
  echo "  ── Additional MaaS API keys for load balancing ──"
  echo "  Each extra key multiplies effective RPM/TPM across all models."
  echo "  Press Enter without typing anything to skip (0 extra keys)."
  echo ""
  while true; do
    EXTRA_NUM=$((EXTRA_KEY_COUNT + 1))
    read -r -p "  Enter MaaS API key #$EXTRA_NUM (or press Enter to finish): " extra_key < /dev/tty
    [ -z "$extra_key" ] && break
    EXTRA_KEY_COUNT=$EXTRA_NUM
    export "HUAWEI_MAAS_API_KEY_$EXTRA_NUM=$extra_key"
    echo "  ✓ Extra key #$EXTRA_NUM added"
  done
fi
export HUAWEI_MAAS_API_KEY_COUNT=$((1 + EXTRA_KEY_COUNT))
if [ "$EXTRA_KEY_COUNT" -gt 0 ]; then
  echo "  ✓ $((1 + EXTRA_KEY_COUNT)) MaaS API keys total (main + $EXTRA_KEY_COUNT extra)"
else
  echo "  Using 1 MaaS API key (no load balancing)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Deploy LiteLLM
print_step "3" "Deploy LiteLLM"

# ── Port conflict check ──
for port in 4000; do
  if command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    echo "  WARNING: Port $port is already in use. Docker Compose may fail."
  elif command -v netstat &>/dev/null && netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
    echo "  WARNING: Port $port is already in use. Docker Compose may fail."
  fi
done

# ── 3a. Ensure .env exists ──
if [ ! -f "$PROJECT_DIR/.env" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "  Would run: scripts/init_env.sh --auto"
  else
    echo "  .env not found. Running init_env.sh --auto ..."
    (cd "$PROJECT_DIR" && ./scripts/init_env.sh --auto)
  fi
else
  # If --maas-key was provided and differs from .env, update .env
  if [ -n "$MAAS_KEY" ] && [ "$MAAS_KEY" != "${HUAWEI_MAAS_API_KEY:-}" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  Would update HUAWEI_MAAS_API_KEY in .env and regenerate config"
    else
      echo "  Updating HUAWEI_MAAS_API_KEY in .env (key changed)..."
      sed -i "s|^HUAWEI_MAAS_API_KEY=.*|HUAWEI_MAAS_API_KEY=\"$MAAS_KEY\"|" "$PROJECT_DIR/.env"
      sed -i "s|^HUAWEI_MAAS_API_KEY_0=.*|HUAWEI_MAAS_API_KEY_0=\"$MAAS_KEY\"|" "$PROJECT_DIR/.env" 2>/dev/null || true
      echo "  Regenerating litellm_config.yaml..."
      (cd "$PROJECT_DIR" && ./scripts/generate_config.sh)
    fi
  fi
  echo "  .env exists — skipping init_env.sh"
fi

# ── 3b. Start Docker Compose (idempotent) ──
if [ "$DRY_RUN" = true ]; then
  echo "  Would run: docker compose up -d"
  LITELLM_MASTER_KEY="<LITELLM_MASTER_KEY>"
else
  echo "  Starting Docker Compose (idempotent — no-op if already running)..."
  docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
  # Only wait if not already healthy
  if curl -sf -m "$CURL_TIMEOUT" "$LITELLM_URL/health/liveliness" &>/dev/null; then
    echo "  LiteLLM already healthy."
  else
    wait_for_litellm
  fi
fi

# ── 3c. Resolve master key ──
if [ "$DRY_RUN" = true ]; then
  LITELLM_MASTER_KEY="<LITELLM_MASTER_KEY>"
else
  try_resolve_master_key || prompt_master_key
fi

export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Install opencode + plugin + configure
# ──────────────────────────────────────────────────────────────────────────────
print_step "4" "Install opencode, plugin, and configure"

INSTALL_CMD=("$SCRIPT_DIR/install.sh")
[ -n "$VIRTUAL_KEY" ] && INSTALL_CMD+=("--virtual-key=$VIRTUAL_KEY")
[ "$DRY_RUN" = true ] && INSTALL_CMD+=("--dry-run")

if [ "$DRY_RUN" = true ]; then
  echo "  Would run: ${INSTALL_CMD[*]}"
else
  "${INSTALL_CMD[@]}"
  echo "  Installation and configuration complete."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: Validate
# ──────────────────────────────────────────────────────────────────────────────
print_step "5" "Validate"

VALIDATE_CMD=("$SCRIPT_DIR/validate.sh")
[ "$DRY_RUN" = true ] && VALIDATE_CMD+=("--dry-run")

if [ "$DRY_RUN" = true ]; then
  echo "  Would run: ${VALIDATE_CMD[*]}"
else
  "${VALIDATE_CMD[@]}"
  echo "  Validation complete."
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 6: Summary
# ──────────────────────────────────────────────────────────────────────────────
print_step "6" "Summary"

if [ "$DRY_RUN" = true ]; then
  echo ""; echo "=== Dry run complete — no changes made ==="; exit 0
fi

echo ""
echo "=== Bootstrap complete ==="
echo ""
echo "Project dir:       $PROJECT_DIR"
echo "LiteLLM proxy:     $LITELLM_URL"
echo "LiteLLM Admin UI:  ${LITELLM_URL}/ui"
echo "opencode config:    ~/.config/opencode/opencode.jsonc"
echo "plugin config:      ~/.config/opencode/oh-my-opencode-slim.json"
# Show virtual key (masked) from config
FINAL_VK=$(jq -r '.provider.LiteLLM.options.apiKey // empty' "$HOME/.config/opencode/opencode.jsonc" 2>/dev/null || true)
if [ -n "$FINAL_VK" ]; then
  echo "Virtual key:        ${FINAL_VK:0:8}...${FINAL_VK: -4}"
fi
echo ""
echo "Preset: LiteLLM-Huawei-MaaS (default) — all 5 models via LiteLLM"
echo "Fallback: LiteLLM-Huawei-MaaS-Lite — 3 models (no v4-pro/v4-flash)"
echo "Direct: Huawei-MaaS / Huawei-MaaS-Lite — bypass LiteLLM proxy"
echo ""
echo "Next steps:"
echo "  1. Run: opencode"
echo "  2. Verify preset: status bar should show LiteLLM-Huawei-MaaS"
echo "  3. Switch preset: /preset LiteLLM-Huawei-MaaS-Lite"
