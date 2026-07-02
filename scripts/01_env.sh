#!/usr/bin/env bash
set -euo pipefail

# ─── 01_env.sh — Environment & secrets (pipeline step 01, core) ───────────────
#
# Domain:        Environment & secrets
# Order:         01 (first — everything needs .env)
# Optional:      no (core, always runs)
# Description:   Generate/update .env with immutable secrets, Huawei MaaS API
#                keys, and endpoint URLs. For each secret, prompts to use an
#                auto-generated value or enter a custom one (non-interactive
#                defaults to auto). Collects the MaaS key from the
#                HUAWEI_MAAS_API_KEY env var or an interactive prompt.
#                Configures git hooks to block committing secrets.
# Inputs:        HUAWEI_MAAS_API_KEY (env var or prompt),
#                HUAWEI_MAAS_API_KEY_COUNT + HUAWEI_MAAS_API_KEY_1..N (env vars
#                or prompt), --force (regenerate secrets)
# Outputs:       .env (chmod 600), git hooks configured
# Standalone:    yes — ./scripts/01_env.sh
# ──────────────────────────────────────────────────────────────────────────────

# ── Resolve project root ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_EXAMPLE="$PROJECT_DIR/configs/.env.template"
ENV_FILE="$PROJECT_DIR/.env"

# ── Cleanup trap for temp file (R5) ──
trap 'rm -f "$ENV_FILE.tmp" 2>/dev/null' EXIT INT TERM

# ── Helpers ──
source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
LOG_TAG="env"
prereq_ensure_apt "python3" python3 python3
prereq_ensure_apt "git"     git     git

generate_secret() { python3 -c 'import secrets; print(secrets.token_urlsafe(32))'; }
generate_master_key() { echo "sk-$(generate_secret)"; }

# ── Parse args ──
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    *) log_error "Usage: $0 [--force]"; exit 1 ;;
  esac
done

log_step "Step 01 — Environment & secrets"

# ── Check env template exists ──
if [ ! -f "$ENV_EXAMPLE" ]; then
  log_error "$ENV_EXAMPLE not found."
  exit 1
fi

# ── Read existing secrets to preserve (idempotent) ──
EXISTING_MASTER_KEY=""
EXISTING_SALT_KEY=""
EXISTING_DB_PASSWORD=""
EXISTING_GRAFANA_PASSWORD=""
EXISTING_PROM_RETENTION=""
EXISTING_MAAS_BASE=""
EXISTING_MAAS_ANTHROPIC_BASE=""
EXISTING_MAAS_KEY=""
EXISTING_KEY_COUNT=""
EXISTING_EXTRA_KEYS=()
if [ -f "$ENV_FILE" ]; then
  EXISTING_MASTER_KEY="$(grep -oP '^LITELLM_MASTER_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_SALT_KEY="$(grep -oP '^LITELLM_SALT_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_DB_PASSWORD="$(grep -oP '^DB_PASSWORD="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_GRAFANA_PASSWORD="$(grep -oP '^GRAFANA_ADMIN_PASSWORD="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_PROM_RETENTION="$(grep -oP '^PROMETHEUS_RETENTION="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_MAAS_BASE="$(grep -oP '^HUAWEI_MAAS_API_BASE="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_MAAS_ANTHROPIC_BASE="$(grep -oP '^HUAWEI_MAAS_ANTHROPIC_API_BASE="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_MAAS_KEY="$(grep -oP '^HUAWEI_MAAS_API_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_KEY_COUNT="$(grep -oP '^HUAWEI_MAAS_API_KEY_COUNT="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  # Read existing extra keys (R2: validate numeric before comparison)
  if [ -n "$EXISTING_KEY_COUNT" ]; then
    if [[ ! "$EXISTING_KEY_COUNT" =~ ^[0-9]+$ ]]; then
      log_error "HUAWEI_MAAS_API_KEY_COUNT in existing .env is non-numeric: '$EXISTING_KEY_COUNT'"
      exit 1
    fi
    if [ "$EXISTING_KEY_COUNT" -gt 1 ]; then
      for i in $(seq 1 $((EXISTING_KEY_COUNT - 1))); do
        VAR="HUAWEI_MAAS_API_KEY_$i"
        VAL="$(grep -oP "^${VAR}=\"?\K[^\"]+" "$ENV_FILE" 2>/dev/null || true)"
        [ -n "$VAL" ] && EXISTING_EXTRA_KEYS+=("$VAL")
      done
    fi
  fi
fi

# ── Generate / preserve secrets ──
# Immutable secrets are preserved on re-run (changing them breaks existing
# deployments). --force regenerates all (for key rotation).
# For fresh installs or --force, prompt for each: auto-generated or custom.

IS_FRESH=true
[ -f "$ENV_FILE" ] && [ "$FORCE" != true ] && IS_FRESH=false

# Auto-generate defaults
AUTO_MASTER_KEY="$(generate_master_key)"
AUTO_SALT_KEY="$(generate_secret)"
AUTO_DB_PASSWORD="$(generate_secret)"
AUTO_GRAFANA_PASSWORD="$(generate_secret)"
AUTO_PROM_RETENTION="30d"
MAAS_API_BASE="https://api-ap-southeast-1.modelarts-maas.com/openai/v1"
MAAS_ANTHROPIC_BASE="https://api-ap-southeast-1.modelarts-maas.com/anthropic"

if [ "$IS_FRESH" = false ]; then
  # Validate existing secrets are non-empty before preserving
  [ -n "$EXISTING_MASTER_KEY" ]       && MASTER_KEY="$EXISTING_MASTER_KEY"       || IS_FRESH=true
  [ -n "$EXISTING_SALT_KEY" ]         && SALT_KEY="$EXISTING_SALT_KEY"           || IS_FRESH=true
  [ -n "$EXISTING_DB_PASSWORD" ]      && DB_PASSWORD="$EXISTING_DB_PASSWORD"     || IS_FRESH=true
  [ -n "$EXISTING_GRAFANA_PASSWORD" ] && GRAFANA_PASSWORD="$EXISTING_GRAFANA_PASSWORD" || IS_FRESH=true
  [ -n "$EXISTING_PROM_RETENTION" ]   && PROM_RETENTION="$EXISTING_PROM_RETENTION" || IS_FRESH=true
  if [ "$IS_FRESH" = false ]; then
    log_ok "Preserving existing secrets (idempotent). Use --force to regenerate."
  else
    log_warn "Some existing secrets are empty or missing — regenerating."
  fi
fi

# Preserve MaaS base URLs from existing .env if present (R1: always, not just when IS_FRESH=false)
[ -n "$EXISTING_MAAS_BASE" ] && MAAS_API_BASE="$EXISTING_MAAS_BASE"
[ -n "$EXISTING_MAAS_ANTHROPIC_BASE" ] && MAAS_ANTHROPIC_BASE="$EXISTING_MAAS_ANTHROPIC_BASE"

if [ "$IS_FRESH" = true ]; then
  # Fresh install or --force — prompt for each secret
  if [ "$FORCE" = true ] && [ -f "$ENV_FILE" ]; then
    log_warn "Regenerating all secrets (--force). Existing virtual keys will be invalidated."
  fi

  log_step "Secret configuration"
  log_dim "For each secret, choose auto-generated or enter a custom value."
  echo ""

  MASTER_KEY=$(prompt_password "LITELLM_MASTER_KEY (proxy auth)" "$AUTO_MASTER_KEY")
  SALT_KEY=$(prompt_password "LITELLM_SALT_KEY (virtual key signing)" "$AUTO_SALT_KEY")
  DB_PASSWORD=$(prompt_password "DB_PASSWORD (PostgreSQL)" "$AUTO_DB_PASSWORD")
  GRAFANA_PASSWORD=$(prompt_password "GRAFANA_ADMIN_PASSWORD" "$AUTO_GRAFANA_PASSWORD")

  echo ""
  PROM_RETENTION=$(prompt_input "PROMETHEUS_RETENTION (e.g. 30d, 14d, 7d)" "$AUTO_PROM_RETENTION")
fi

# ── Collect MaaS API key (env var or prompt) ──
log_step "Huawei MaaS API key"
MAAS_API_KEY="${HUAWEI_MAAS_API_KEY:-}"
if [ -z "$MAAS_API_KEY" ] && [ -n "$EXISTING_MAAS_KEY" ]; then
  MAAS_API_KEY="$EXISTING_MAAS_KEY"
  log_ok "HUAWEI_MAAS_API_KEY preserved from existing .env"
fi
if [ -n "$MAAS_API_KEY" ]; then
  log_ok "HUAWEI_MAAS_API_KEY set from environment"
elif [ -t 0 ]; then
  echo ""
  MAAS_API_KEY=$(prompt_input "Enter Huawei MaaS API key (region ap-southeast-1)" "")
else
  log_error "HUAWEI_MAAS_API_KEY is required. Set it as an env var or run interactively."
  exit 1
fi

# ── Collect extra MaaS keys for load balancing (env vars or prompt) ──
EXTRA_KEYS=()
if [ -n "${HUAWEI_MAAS_API_KEY_COUNT:-}" ]; then
  # R2: validate numeric before comparison
  if [[ ! "$HUAWEI_MAAS_API_KEY_COUNT" =~ ^[0-9]+$ ]]; then
    log_error "HUAWEI_MAAS_API_KEY_COUNT is non-numeric: '$HUAWEI_MAAS_API_KEY_COUNT'"
    exit 1
  fi
  if [ "$HUAWEI_MAAS_API_KEY_COUNT" -gt 1 ]; then
    for i in $(seq 1 $((HUAWEI_MAAS_API_KEY_COUNT - 1))); do
      VAR="HUAWEI_MAAS_API_KEY_$i"
      VAL="${!VAR:-}"
      [ -n "$VAL" ] && EXTRA_KEYS+=("$VAL")
    done
    # R3: warn if actual count doesn't match declared count
    actual_count=$(( 1 + ${#EXTRA_KEYS[@]} ))
    if [ "$actual_count" -ne "$HUAWEI_MAAS_API_KEY_COUNT" ]; then
      log_warn "HUAWEI_MAAS_API_KEY_COUNT=$HUAWEI_MAAS_API_KEY_COUNT but only $actual_count key(s) provided. Using actual count."
    fi
    [ ${#EXTRA_KEYS[@]} -gt 0 ] && log_ok "${#EXTRA_KEYS[@]} extra MaaS key(s) from environment"
  fi
elif [ ${#EXISTING_EXTRA_KEYS[@]} -gt 0 ]; then
  EXTRA_KEYS=("${EXISTING_EXTRA_KEYS[@]}")
  log_ok "${#EXTRA_KEYS[@]} extra MaaS key(s) preserved from existing .env"
elif [ -t 0 ]; then
  echo ""
  log_dim "Additional MaaS API keys for load balancing."
  log_dim "Each extra key multiplies effective RPM/TPM across all models."
  log_dim "Press Enter without typing anything to skip (0 extra keys)."
  echo ""
  while true; do
    EXTRA_NUM=$(( ${#EXTRA_KEYS[@]} + 1 ))
    extra_key=$(prompt_input "MaaS API key #$EXTRA_NUM (or press Enter to finish)" "")
    [ -z "$extra_key" ] && break
    EXTRA_KEYS+=("$extra_key")
    log_ok "Extra key #$EXTRA_NUM added"
  done
fi

KEY_COUNT=$(( 1 + ${#EXTRA_KEYS[@]} ))

# ── Validate ──
ERRORS=0
if [[ ! "$MASTER_KEY" == sk-* ]]; then
  log_error "LITELLM_MASTER_KEY must start with 'sk-'."
  ERRORS=$((ERRORS + 1))
fi
if [ -z "$MAAS_API_KEY" ]; then
  log_error "HUAWEI_MAAS_API_KEY is required."
  ERRORS=$((ERRORS + 1))
fi
if [[ "$MAAS_API_KEY" == *"change-me"* ]] || [[ "$MAAS_API_KEY" == *"xxx"* ]]; then
  log_error "HUAWEI_MAAS_API_KEY still has a placeholder value."
  ERRORS=$((ERRORS + 1))
fi
for i in "${!EXTRA_KEYS[@]}"; do
  key="${EXTRA_KEYS[$i]}"
  if [ -z "$key" ]; then
    log_error "Additional MaaS API key $((i + 1)) is empty."
    ERRORS=$((ERRORS + 1))
  elif [[ "$key" == *"change-me"* ]] || [[ "$key" == *"xxx"* ]]; then
    log_error "Additional MaaS API key $((i + 1)) still has a placeholder value."
    ERRORS=$((ERRORS + 1))
  fi
done
if [[ ! "$PROM_RETENTION" =~ ^([0-9]+)([dhw])$ ]]; then
  log_error "PROMETHEUS_RETENTION must be a Prometheus duration like 30d, 14d, 7d. Got: $PROM_RETENTION"
  ERRORS=$((ERRORS + 1))
fi
if [ "$ERRORS" -gt 0 ]; then
  echo ""
  log_error "Validation failed with $ERRORS error(s)."
  exit 1
fi

# ── Write .env ──
cat > "$ENV_FILE.tmp" <<EOF
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
for i in "${!EXTRA_KEYS[@]}"; do
  echo "HUAWEI_MAAS_API_KEY_$((i + 1))=\"${EXTRA_KEYS[$i]}\"" >> "$ENV_FILE.tmp"
done
cat >> "$ENV_FILE.tmp" <<EOF

# ── MaaS Endpoint ──────────────────────────────────
HUAWEI_MAAS_API_BASE="${MAAS_API_BASE}"

# ── MaaS Anthropic Endpoint ───────────────────────
HUAWEI_MAAS_ANTHROPIC_API_BASE="${MAAS_ANTHROPIC_BASE}"
EOF
chmod 600 "$ENV_FILE.tmp"
mv "$ENV_FILE.tmp" "$ENV_FILE"
trap - EXIT INT TERM

# ── Configure git hooks (prevent committing secrets) ──
if [ -d "$PROJECT_DIR/.githooks" ]; then
  CURRENT_HOOKS=$(git -C "$PROJECT_DIR" config --local core.hooksPath 2>/dev/null || true)
  if [ "$CURRENT_HOOKS" != ".githooks" ]; then
    git -C "$PROJECT_DIR" config core.hooksPath .githooks
    log_ok "Git hooks configured (.githooks/pre-commit blocks .env and secrets)"
  fi
fi

# ── Warn if --force was used ──
if [ "$FORCE" = true ]; then
  echo ""
  log_warn "All secrets were regenerated (--force). Restart Docker to apply:"
  log_dim "docker compose up -d"
  log_dim "Existing virtual keys are invalidated — re-run tool installs to mint new ones."
fi

# ── Summary ──
echo ""
log_ok ".env written: $ENV_FILE (chmod 600)"
log_dim "HUAWEI_MAAS_API_KEY   = $(mask_key "$MAAS_API_KEY")"
log_dim "MAAS API key count    = ${KEY_COUNT}"
log_dim "LITELLM_MASTER_KEY    = $(mask_key "$MASTER_KEY")"
log_dim "PROMETHEUS_RETENTION  = ${PROM_RETENTION}"
