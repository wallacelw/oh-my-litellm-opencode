#!/usr/bin/env bash
# init_env.sh — Initialize .env for deployment
#
# Two modes:
#   interactive  (default)  — prompt for each secret, offer generated defaults
#   --auto                  — non-interactive agent mode; reads HUAWEI_MAAS_API_KEY
#                            from env var, auto-generates all other secrets,
#                            never prompts. Errors if HUAWEI_MAAS_API_KEY not set.
#                            Preserves existing secrets on re-run (idempotent).
#   --auto --force          — like --auto but regenerates all secrets
#                            (use after security incidents or to rotate keys)
#
# Usage:
#   ./scripts/1_init_env.sh              # interactive — you choose every value
#   ./scripts/1_init_env.sh --auto       # agent mode — idempotent, preserves secrets
#   ./scripts/1_init_env.sh --auto --force # agent mode — regenerate all secrets

set -euo pipefail

# ── Resolve project root ──────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_EXAMPLE="$PROJECT_ROOT/configs/.env.template"
ENV_FILE="$PROJECT_ROOT/.env"

# ── Parse mode ────────────────────────────────────────────────────
MODE="interactive"
FORCE=false
for arg in "$@"; do
  if [[ "$arg" == "--auto" ]]; then MODE="auto"
  elif [[ "$arg" == "--force" ]]; then FORCE=true
  elif [[ -n "$arg" ]]; then
    echo "Usage: $0 [--auto] [--force]" >&2; exit 1
  fi
done

# ── Helpers ───────────────────────────────────────────────────────
generate_secret() { python3 -c 'import secrets; print(secrets.token_urlsafe(32))'; }
generate_master_key() { echo "sk-$(generate_secret)"; }

prompt_value() {
  local varname="$1" description="$2" default="$3" is_secret="${4:-yes}"

  if [[ "$MODE" == "auto" ]]; then
    # Auto mode: use env var or default, never prompt
    local val="${!varname:-$default}"
    echo "$val"
    return
  fi

  # Interactive: prompt the user
  local display_default
  if [[ "$is_secret" == "yes" && ${#default} -gt 8 ]]; then
    display_default="${default:0:6}...${default: -4}"
  else
    display_default="$default"
  fi

  local prompt_text
  if [[ -n "$default" ]]; then
    prompt_text="  $description [$display_default]: "
  else
    prompt_text="  $description: "
  fi

  if [[ -t 0 ]]; then
    read -r -p "$prompt_text" input < /dev/tty
  else
    read -r input
  fi

  echo "${input:-$default}"
}

# ── Banner ────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════"
echo "  LiteLLM Huawei MaaS Proxy — Environment Setup"
echo "  Mode: $MODE"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Check env template exists ────────────────────────────────────
if [[ ! -f "$ENV_EXAMPLE" ]]; then
  echo "ERROR: $ENV_EXAMPLE not found." >&2; exit 1
fi

# ── Check if .env already exists ─────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  if [[ "$MODE" == "auto" ]]; then
    # In auto mode, preserve immutable secrets from existing .env to avoid
    # breaking existing deployments (LiteLLM started with old MASTER_KEY, etc.)
    EXISTING_MASTER_KEY="$(grep -oP '^LITELLM_MASTER_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    EXISTING_SALT_KEY="$(grep -oP '^LITELLM_SALT_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    EXISTING_DB_PASSWORD="$(grep -oP '^DB_PASSWORD="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    EXISTING_GRAFANA_PASSWORD="$(grep -oP '^GRAFANA_ADMIN_PASSWORD="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    EXISTING_PROM_RETENTION="$(grep -oP '^PROMETHEUS_RETENTION="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    EXISTING_MAAS_KEY="$(grep -oP '^HUAWEI_MAAS_API_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    EXISTING_MAAS_BASE="$(grep -oP '^HUAWEI_MAAS_API_BASE="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    EXISTING_MAAS_ANTHROPIC_BASE="$(grep -oP '^HUAWEI_MAAS_ANTHROPIC_API_BASE="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
    echo "WARNING: .env already exists. Overwriting in auto mode (preserving secrets if set)."
  else
    echo "WARNING: .env already exists. Overwriting will regenerate all values."
    read -r -p "  Overwrite? [y/N]: " overwrite < /dev/tty
    if [[ "${overwrite,,}" != "y" ]]; then
      echo "Aborting. Edit .env manually or remove it first."; exit 0
    fi
  fi
fi

# ── Generate defaults ────────────────────────────────────────────
DEFAULT_MASTER_KEY=$(generate_master_key)
DEFAULT_SALT_KEY=$(generate_secret)
DEFAULT_DB_PASSWORD=$(generate_secret)
DEFAULT_GRAFANA_PASSWORD=$(generate_secret)
DEFAULT_PROM_RETENTION="30d"
DEFAULT_MAAS_BASE="https://api-ap-southeast-1.modelarts-maas.com/openai/v1"
DEFAULT_MAAS_ANTHROPIC_BASE="https://api-ap-southeast-1.modelarts-maas.com/anthropic"

# ── Idempotency: preserve secrets in auto mode ────────────────────
# Changing these breaks existing deployments:
#   MASTER_KEY → admin access to LiteLLM
#   SALT_KEY   → invalidates all virtual keys
#   DB_PASSWORD → PostgreSQL auth
# With --force, all secrets are regenerated (for key rotation).
if [[ "$MODE" == "auto" && "$FORCE" != true ]]; then
  if [[ -n "${EXISTING_MASTER_KEY:-}" ]]; then
    DEFAULT_MASTER_KEY="$EXISTING_MASTER_KEY"
    echo "  Reusing existing LITELLM_MASTER_KEY (idempotent)"
  fi
  if [[ -n "${EXISTING_SALT_KEY:-}" ]]; then
    DEFAULT_SALT_KEY="$EXISTING_SALT_KEY"
    echo "  Reusing existing LITELLM_SALT_KEY (idempotent — preserves virtual keys)"
  fi
  if [[ -n "${EXISTING_DB_PASSWORD:-}" ]]; then
    DEFAULT_DB_PASSWORD="$EXISTING_DB_PASSWORD"
    echo "  Reusing existing DB_PASSWORD (idempotent)"
  fi
  if [[ -n "${EXISTING_GRAFANA_PASSWORD:-}" ]]; then
    DEFAULT_GRAFANA_PASSWORD="$EXISTING_GRAFANA_PASSWORD"
    echo "  Reusing existing GRAFANA_ADMIN_PASSWORD (idempotent)"
  fi
  if [[ -n "${EXISTING_PROM_RETENTION:-}" ]]; then
    DEFAULT_PROM_RETENTION="$EXISTING_PROM_RETENTION"
    echo "  Reusing existing PROMETHEUS_RETENTION (idempotent)"
  fi
  if [[ -n "${EXISTING_MAAS_KEY:-}" && -z "${HUAWEI_MAAS_API_KEY:-}" ]]; then
    DEFAULT_MAAS_KEY="$EXISTING_MAAS_KEY"
    echo "  Reusing existing HUAWEI_MAAS_API_KEY (idempotent)"
  fi
  if [[ -n "${EXISTING_MAAS_BASE:-}" && -z "${HUAWEI_MAAS_API_BASE:-}" ]]; then
    DEFAULT_MAAS_BASE="$EXISTING_MAAS_BASE"
    echo "  Reusing existing HUAWEI_MAAS_API_BASE (idempotent)"
  fi
  if [[ -n "${EXISTING_MAAS_ANTHROPIC_BASE:-}" && -z "${HUAWEI_MAAS_ANTHROPIC_API_BASE:-}" ]]; then
    DEFAULT_MAAS_ANTHROPIC_BASE="$EXISTING_MAAS_ANTHROPIC_BASE"
    echo "  Reusing existing HUAWEI_MAAS_ANTHROPIC_API_BASE (idempotent)"
  fi
fi

# ── Collect values ────────────────────────────────────────────────
echo "Configuring secrets and endpoints..."
echo ""

MASTER_KEY=$(prompt_value "LITELLM_MASTER_KEY" "LITELLM_MASTER_KEY (admin key, must start with sk-)" "$DEFAULT_MASTER_KEY" "yes")
SALT_KEY=$(prompt_value "LITELLM_SALT_KEY" "LITELLM_SALT_KEY (key encryption salt, immutable after first virtual key)" "$DEFAULT_SALT_KEY" "yes")
DB_PASSWORD=$(prompt_value "DB_PASSWORD" "DB_PASSWORD (PostgreSQL llmproxy user)" "$DEFAULT_DB_PASSWORD" "yes")
GRAFANA_PASSWORD=$(prompt_value "GRAFANA_ADMIN_PASSWORD" "GRAFANA_ADMIN_PASSWORD (Grafana dashboard admin)" "$DEFAULT_GRAFANA_PASSWORD" "yes")
PROM_RETENTION=$(prompt_value "PROMETHEUS_RETENTION" "PROMETHEUS_RETENTION (Prometheus TSDB retention, min 7d for baselines)" "$DEFAULT_PROM_RETENTION" "no")
MAAS_API_KEY=$(prompt_value "HUAWEI_MAAS_API_KEY" "HUAWEI_MAAS_API_KEY (main key from ModelArts MaaS console, ap-southeast-1)" "${DEFAULT_MAAS_KEY:-}" "yes")
MAAS_API_BASE=$(prompt_value "HUAWEI_MAAS_API_BASE" "HUAWEI_MAAS_API_BASE (MaaS endpoint URL)" "$DEFAULT_MAAS_BASE" "no")
MAAS_ANTHROPIC_BASE=$(prompt_value "HUAWEI_MAAS_ANTHROPIC_API_BASE" "HUAWEI_MAAS_ANTHROPIC_API_BASE (MaaS Anthropic endpoint URL)" "$DEFAULT_MAAS_ANTHROPIC_BASE" "no")

# ── Collect additional MaaS API keys ───────────
EXTRA_KEYS=()
if [[ "$MODE" == "interactive" ]]; then
  echo "  Enter additional MaaS API keys (comma-separated, or press Enter for none):"
  if [[ -t 0 ]]; then
    read -r extra_input < /dev/tty
  else
    read -r extra_input
  fi
  if [[ -n "${extra_input:-}" ]]; then
    IFS=',' read -ra EXTRA_KEYS <<< "$extra_input"
  fi
elif [[ "$MODE" == "auto" ]]; then
  # In auto mode, read extra keys from env vars exported by bootstrap.sh
  AUTO_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"
  for i in $(seq 1 $((AUTO_COUNT - 1))); do
    VAR="HUAWEI_MAAS_API_KEY_$i"
    VAL="${!VAR:-}"
    if [[ -n "$VAL" ]]; then
      EXTRA_KEYS+=("$VAL")
    fi
  done
  if [[ ${#EXTRA_KEYS[@]} -gt 0 ]]; then
    echo "  Found ${#EXTRA_KEYS[@]} additional MaaS API key(s) from environment"
  fi
fi

# Total key count: 1 (main) + extras
KEY_COUNT=$((1 + ${#EXTRA_KEYS[@]}))

# ── Validate ──────────────────────────────────────────────────────
ERRORS=0

if [[ ! "$MASTER_KEY" == sk-* ]]; then
  echo "ERROR: LITELLM_MASTER_KEY must start with 'sk-'. Got: ${MASTER_KEY:0:6}..." >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ -z "$MAAS_API_KEY" ]]; then
  echo "ERROR: HUAWEI_MAAS_API_KEY is required. Get it from https://console.huaweicloud.com/modelarts/" >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ "$MAAS_API_KEY" == *"change-me"* ]] || [[ "$MAAS_API_KEY" == *"xxx"* ]]; then
  echo "ERROR: HUAWEI_MAAS_API_KEY still has a placeholder value." >&2
  ERRORS=$((ERRORS + 1))
fi

# Validate extra keys
for i in "${!EXTRA_KEYS[@]}"; do
  key="${EXTRA_KEYS[$i]}"
  if [[ -z "$key" ]]; then
    echo "ERROR: Additional MaaS API key $((i + 1)) is empty." >&2
    ERRORS=$((ERRORS + 1))
  elif [[ "$key" == *"change-me"* ]] || [[ "$key" == *"xxx"* ]]; then
    echo "ERROR: Additional MaaS API key $((i + 1)) still has a placeholder value." >&2
    ERRORS=$((ERRORS + 1))
  fi
done

# Validate Prometheus retention (must be >= 7d for 7-day baseline recording rules)
if [[ "$PROM_RETENTION" =~ ^([0-9]+)([dhw])$ ]]; then
  RET_NUM="${BASH_REMATCH[1]}"
  RET_UNIT="${BASH_REMATCH[2]}"
  # Convert to days for comparison
  case "$RET_UNIT" in
    d) RET_DAYS="$RET_NUM" ;;
    h) RET_DAYS=$(( RET_NUM / 24 )) ;;
    w) RET_DAYS=$(( RET_NUM * 7 )) ;;
  esac
  if [[ "$RET_DAYS" -lt 7 ]]; then
    echo "ERROR: PROMETHEUS_RETENTION must be >= 7d (recording rules use 7-day windows). Got: $PROM_RETENTION" >&2
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "ERROR: PROMETHEUS_RETENTION must be a Prometheus duration like 30d, 14d, 7d. Got: $PROM_RETENTION" >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo "" >&2
  echo "Validation failed with $ERRORS error(s). Fix the above and re-run." >&2
  exit 1
fi

# ── Write .env ────────────────────────────────────────────────────
cat > "$ENV_FILE" <<EOF
# ── Proxy Auth ───────────────────────────────────
LITELLM_MASTER_KEY="${MASTER_KEY}"
LITELLM_SALT_KEY="${SALT_KEY}"

# ── Database ─────────────────────────────────────
DB_PASSWORD="${DB_PASSWORD}"

# ── Grafana ──────────────────────────────────────
GRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"

# ── Prometheus ───────────────────────────────────
PROMETHEUS_RETENTION="${PROM_RETENTION}"

# ── Huawei MaaS ──────────────────────────────────
HUAWEI_MAAS_API_KEY="${MAAS_API_KEY}"
HUAWEI_MAAS_API_KEY_COUNT=${KEY_COUNT}
HUAWEI_MAAS_API_KEY_0="${MAAS_API_KEY}"
EOF

# Write extra keys
for i in "${!EXTRA_KEYS[@]}"; do
  echo "HUAWEI_MAAS_API_KEY_$((i + 1))=\"${EXTRA_KEYS[$i]}\"" >> "$ENV_FILE"
done

cat >> "$ENV_FILE" <<EOF

# ── MaaS Endpoint ──────────────────────────────────
HUAWEI_MAAS_API_BASE="${MAAS_API_BASE}"
EOF

cat >> "$ENV_FILE" <<EOF

# ── MaaS Anthropic Endpoint ───────────────────────
HUAWEI_MAAS_ANTHROPIC_API_BASE="${MAAS_ANTHROPIC_BASE}"
EOF

chmod 600 "$ENV_FILE"

# ── Warn if --force was used ──────────────────────────────────────
if [[ "$MODE" == "auto" && "$FORCE" == true ]]; then
  echo ""
  echo "WARNING: All secrets were regenerated (--force). You must restart Docker to pick up the new values:"
  echo "  docker compose up -d"
  echo "Existing virtual keys are invalidated — re-run install.sh to mint new ones."
fi

# ── Generate litellm_config.yaml ─────────────────────────────────
echo ""
echo "Generating litellm_config.yaml..."
"$SCRIPT_DIR/2_generate_config.sh"
echo "Config generation successful."

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
echo "  .env written to $ENV_FILE"
echo "  Permissions: $(stat -c '%a' "$ENV_FILE" 2>/dev/null || stat -f '%Lp' "$ENV_FILE")"
echo ""
echo "  Values set:"
echo "    LITELLM_MASTER_KEY  = ${MASTER_KEY:0:8}...${MASTER_KEY: -4}"
echo "    LITELLM_SALT_KEY    = ${SALT_KEY:0:6}...${SALT_KEY: -4}"
echo "    DB_PASSWORD         = ${DB_PASSWORD:0:6}...${DB_PASSWORD: -4}"
echo "    GRAFANA_ADMIN_PASSWORD = ${GRAFANA_PASSWORD:0:6}...${GRAFANA_PASSWORD: -4}"
echo "    PROMETHEUS_RETENTION   = ${PROM_RETENTION}"
echo "    HUAWEI_MAAS_API_KEY = ${MAAS_API_KEY:0:6}...${MAAS_API_KEY: -4}"
echo "    MaaS API key count  = ${KEY_COUNT} (${KEY_COUNT} deployment(s) per model, $((KEY_COUNT * 6)) total)"
if [[ "$KEY_COUNT" -gt 1 ]]; then
  for i in "${!EXTRA_KEYS[@]}"; do
    echo "    Additional key $((i + 1))   = ${EXTRA_KEYS[$i]:0:6}...${EXTRA_KEYS[$i]: -4}"
  done
fi
echo "    HUAWEI_MAAS_API_BASE= $MAAS_API_BASE"
echo "    HUAWEI_MAAS_ANTHROPIC_API_BASE= $MAAS_ANTHROPIC_BASE"
echo ""
echo "  Next steps:"
echo "    docker compose up -d"
echo "    ./scripts/5_validate.sh --litellm-only"
echo "══════════════════════════════════════════════════════"
