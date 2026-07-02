#!/usr/bin/env bash
set -euo pipefail

# ─── 02_litellm.sh — LiteLLM proxy + observability (pipeline step 02, core) ──
#
# Domain:        LiteLLM proxy + observability (Prometheus + Grafana)
# Order:         02 (after .env — tools need the proxy live)
# Optional:      no (core, always runs)
# Description:   Generate configs/litellm/config.yaml from .env (N deployments
#                per model per format, dual OpenAI + Anthropic), check required
#                ports are free, and deploy the Docker Compose stack
#                (LiteLLM + PostgreSQL + Prometheus + Grafana). Waits for
#                LiteLLM to become healthy.
# Inputs:        .env (HUAWEI_MAAS_API_KEY_0..N, HUAWEI_MAAS_API_KEY_COUNT,
#                HUAWEI_MAAS_API_BASE, HUAWEI_MAAS_ANTHROPIC_API_BASE)
# Outputs:       configs/litellm/config.yaml, running Docker Compose stack
# Standalone:    yes — ./scripts/02_litellm.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
CONFIG_FILE="$PROJECT_DIR/configs/litellm/config.yaml"

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/models.sh"
LOG_TAG="litellm"
prereq_ensure_apt "curl" curl curl
prereq_ensure_docker

# ── Parse args ──
ROUTING_STRATEGY="simple-shuffle"
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --routing-strategy=*) ROUTING_STRATEGY="${arg#--routing-strategy=}" ;;
    --dry-run)            DRY_RUN=true ;;
    *)
      echo "Usage: $0 [--routing-strategy=STRATEGY] [--dry-run]" >&2
      echo "  Strategies: simple-shuffle, least-busy, latency-based-routing, usage-based-routing, cost-based-routing" >&2
      exit 1
      ;;
  esac
done

log_step "Step 02 — LiteLLM proxy + observability"

# ── Port conflict check ──
for port in 4000 5432 9090 3000; do
  port_in_use=false
  if command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep -qE ":${port}\b"; then
    port_in_use=true
  elif command -v netstat &>/dev/null && netstat -tlnp 2>/dev/null | grep -qE ":${port}\b"; then
    port_in_use=true
  fi
  if [ "$port_in_use" = true ]; then
    log_warn "Port $port is already in use. Docker Compose may fail."
  fi
done

# ── Load .env ──
if [ ! -f "$ENV_FILE" ]; then
  log_error ".env not found. Run scripts/01_env.sh first."
  exit 1
fi
source_env "$PROJECT_DIR"

# ── Determine key count ──
KEY_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"
if [ "$KEY_COUNT" -lt 1 ]; then
  log_error "HUAWEI_MAAS_API_KEY_COUNT must be >= 1. Got: $KEY_COUNT"
  exit 1
fi

# ── Validate all keys exist ──
for i in $(seq 0 $((KEY_COUNT - 1))); do
  VAR="HUAWEI_MAAS_API_KEY_$i"
  VAL="${!VAR:-}"
  if [ -z "$VAL" ]; then
    log_error "$VAR is not set in .env. Each key must be present."
    exit 1
  fi
  if echo "$VAL" | grep -qi 'change-me\|replace\|xxx'; then
    log_error "$VAR still has a placeholder value."
    exit 1
  fi
done

# ── Model catalog ──
# (Sourced from helpers/models.sh)
MODEL_COUNT=${#MODELS[@]}
TOTAL_DEPLOYMENTS=$((KEY_COUNT * MODEL_COUNT * 2))

# ── Backup existing config ──
if [ -f "$CONFIG_FILE" ]; then
  BACKUP="${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  cp "$CONFIG_FILE" "$BACKUP"
  log_info "Backed up existing config to $(basename "$BACKUP")"
fi

# ── Generate config ──
{
  echo "model_list:"
  echo ""
  echo "  # ───────── Huawei MaaS OpenAI Models (${KEY_COUNT} deployment(s) per model, ${KEY_COUNT} * ${MODEL_COUNT} total) ───────────"
  echo "  # (Anthropic section below adds an equal batch — total: 2 * ${KEY_COUNT} * ${MODEL_COUNT})"
  echo ""

  for model_entry in "${MODELS[@]}"; do
    IFS=':' read -r model_name tpm rpm max_tokens max_input max_output input_cost output_cost <<< "$model_entry"

    for i in $(seq 0 $((KEY_COUNT - 1))); do
      if [ "$KEY_COUNT" -gt 1 ]; then
        echo "  # ── deployment $i (key _${i}) ──"
      fi
      echo "  - model_name: $model_name"
      echo "    litellm_params:"
      echo "      model: openai/$model_name"
      echo "      api_base: os.environ/HUAWEI_MAAS_API_BASE"
      echo "      api_key: os.environ/HUAWEI_MAAS_API_KEY_$i"
      echo "      use_chat_completions_api: true"
      echo "      tpm: $tpm"
      echo "      rpm: $rpm"
      echo "    model_info:"
      echo "      max_tokens: $max_tokens"
      echo "      max_input_tokens: $max_input"
      echo "      max_output_tokens: $max_output"
      echo "      input_cost_per_token: $input_cost"
      echo "      output_cost_per_token: $output_cost"
      echo ""
    done
  done

  echo ""
  echo "  # ───────── Huawei MaaS Anthropic Models (for Claude Code CLI) ───────────"
  echo "  # Anthropic-compatible endpoint (/anthropic/v1/messages)"
  echo "  # Prefixed with claude- to avoid routing conflicts with OpenAI deployments"
  echo "  # (LiteLLM routes by model_name; same name for both formats causes"
  echo "  #  /v1/messages to sometimes hit the OpenAI deployment, losing content)"
  echo ""

  for model_entry in "${MODELS[@]}"; do
    IFS=':' read -r model_name tpm rpm max_tokens max_input max_output input_cost output_cost <<< "$model_entry"

    for i in $(seq 0 $((KEY_COUNT - 1))); do
      if [ "$KEY_COUNT" -gt 1 ]; then
        echo "  # ── deployment $i (key _${i}) ──"
      fi
      echo "  - model_name: claude-$model_name"
      echo "    litellm_params:"
      echo "      model: anthropic/$model_name"
      echo "      api_base: os.environ/HUAWEI_MAAS_ANTHROPIC_API_BASE"
      echo "      api_key: os.environ/HUAWEI_MAAS_API_KEY_$i"
      echo "      tpm: $tpm"
      echo "      rpm: $rpm"
      echo "    model_info:"
      echo "      max_tokens: $max_tokens"
      echo "      max_input_tokens: $max_input"
      echo "      max_output_tokens: $max_output"
      echo "      input_cost_per_token: $input_cost"
      echo "      output_cost_per_token: $output_cost"
      echo ""
    done
  done

  echo ""
  echo "litellm_settings:"
  echo "  num_retries: 3 # retry call 3 times across deployments"
  echo "  request_timeout: 600 # full request: 10 min"
  echo "  stream_timeout: 60 # TTFT only: 60s"
  echo "  drop_params: True"
  echo "  set_verbose: False"
  echo "  callbacks: [\"prometheus\"]"
  echo "  prometheus_initialize_budget_metrics: true"
  echo "  require_auth_for_metrics_endpoint: false"
  echo "  ui_theme_config:"
  echo "    logo_url: \"https://upload.wikimedia.org/wikipedia/en/thumb/0/04/Huawei_Standard_logo.svg/3840px-Huawei_Standard_logo.svg.png\""
  echo "    favicon_url: \"https://upload.wikimedia.org/wikipedia/en/thumb/0/04/Huawei_Standard_logo.svg/3840px-Huawei_Standard_logo.svg.png\""
  echo ""
  echo "router_settings:"
  echo "  routing_strategy: $ROUTING_STRATEGY"
  echo "  num_retries: 3"
  echo "  cooldown_time: 30 # seconds to cool down a failed deployment"
  echo "  allowed_fails: 3 # failures before cooldown kicks in"
  echo ""
  echo "general_settings:"
  echo "  database_connection_pool_limit: 10"
  echo "  database_connection_timeout: 60"
  echo "  allow_client_side_credentials: true"
  echo "  background_health_checks: true # periodically health-check all deployments"
  echo "  health_check_interval: 300 # seconds between background health checks"

} > "$CONFIG_FILE"

log_ok "Generated: $CONFIG_FILE"
log_info "Deployments: ${TOTAL_DEPLOYMENTS} total (${KEY_COUNT} per model × ${MODEL_COUNT} models × 2 formats)"
log_info "Routing strategy: $ROUTING_STRATEGY"
if [ "$KEY_COUNT" -gt 1 ]; then
  echo ""
  log_info "Effective capacity (per model):"
  for model_entry in "${MODELS[@]}"; do
    IFS=':' read -r model_name tpm rpm _ <<< "$model_entry"
    total_rpm=$((rpm * KEY_COUNT))
    total_tpm=$((tpm * KEY_COUNT))
    log_dim "  $model_name: $total_rpm RPM, $total_tpm TPM ($KEY_COUNT × $rpm RPM, $KEY_COUNT × $tpm TPM)"
  done
fi

# ── Pre-flight MaaS key validation ──
log_info "Validating MaaS API key..."
MAAS_BASE="${HUAWEI_MAAS_API_BASE:-https://api-ap-southeast-1.modelarts-maas.com/openai/v1}"
MAAS_KEY_0="${HUAWEI_MAAS_API_KEY_0:-${HUAWEI_MAAS_API_KEY:-}}"
if [ -n "$MAAS_KEY_0" ] && [ "$DRY_RUN" != true ]; then
  if ! curl -sf -m 10 "$MAAS_BASE/models" -H "Authorization: Bearer $MAAS_KEY_0" &>/dev/null; then
    log_warn "MaaS API key validation failed — endpoint may be unreachable or key invalid. Continuing anyway (LiteLLM will retry)."
  else
    log_ok "MaaS API key valid"
  fi
fi

# ── Deploy Docker Compose ──
echo ""
if [ "$DRY_RUN" = true ]; then
  log_info "Would run: docker compose up -d"
  exit 0
fi

log_info "Starting Docker Compose (idempotent — no-op if already running)..."
run_filtered "docker" docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d

# Restart LiteLLM if config changed (bind mount — compose won't auto-restart)
if [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ] && ! diff -q "$BACKUP" "$CONFIG_FILE" &>/dev/null; then
  log_info "Config changed — restarting LiteLLM to load new config..."
  run_filtered "docker" docker compose -f "$PROJECT_DIR/docker-compose.yml" restart litellm
fi

# Wait for LiteLLM to become healthy
LITELLM_URL="http://127.0.0.1:4000"
if curl -sf -m 15 "$LITELLM_URL/health/liveliness" &>/dev/null; then
  log_ok "LiteLLM already healthy."
else
  log_info "Waiting for LiteLLM to become healthy (up to 90s)..."
  local_waited=0
  while [ $local_waited -lt 90 ]; do
    if curl -sf -m 15 "$LITELLM_URL/health/liveliness" &>/dev/null; then
      log_ok "LiteLLM healthy after ~${local_waited}s."
      break
    fi
    printf "  ."
    sleep 5
    local_waited=$((local_waited + 5))
  done
  if [ $local_waited -ge 90 ]; then
    echo ""
    log_error "LiteLLM did not become healthy within 90s. Check: docker compose logs"
    exit 1
  fi
fi
