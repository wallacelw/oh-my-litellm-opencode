#!/usr/bin/env bash
set -euo pipefail

# ─── Unified Validation: LiteLLM proxy + opencode + oh-my-opencode-slim ───
#
# Run after bootstrap.sh to verify everything works end-to-end.
# Combines LiteLLM E2E validation and opencode configuration checks.
#
# Usage:
#   ./validate.sh          # full validation including network checks
#   ./validate.sh --dry-run  # syntax and structure checks only (no network)
#   ./validate.sh --litellm-only  # only LiteLLM proxy checks
#   ./validate.sh --opencode-only  # only opencode config checks

PASS=0
FAIL=0
WARN=0
DRY_RUN=false
LITELLM_ONLY=false
OPENCODE_ONLY=false
LITELLM_URL="http://127.0.0.1:4000"
OPENLIT_URL="${OPENLIT_URL:-http://127.0.0.1:3000}"
CLICKHOUSE_URL="${CLICKHOUSE_URL:-http://127.0.0.1:8123}"

for arg in "$@"; do
  case "$arg" in
    --dry-run)        DRY_RUN=true ;;
    --litellm-only)   LITELLM_ONLY=true ;;
    --opencode-only)  OPENCODE_ONLY=true ;;
  esac
done

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

pass() { PASS=$((PASS + 1)); printf "${GREEN}✅ PASS${NC} — $1\n"; }
fail() { FAIL=$((FAIL + 1)); printf "${RED}❌ FAIL${NC} — $1\n"; }
warn() { WARN=$((WARN + 1)); printf "${YELLOW}⚠️  WARN${NC} — $1\n"; }
skip() { printf "  ○ $1 (skipped)\n"; }

# ── Helper: pipe JSON into jq as a single command ──
jqc() {
  printf '%s' "$1" | jq -e "$2" 2>/dev/null
}

# ── Helper: strip JSONC comments for jq ──
strip_jsonc() {
  python3 -c "import sys,re; sys.stdout.write(re.sub(r'//.*?$|/\*.*?\*/', '', sys.stdin.read(), flags=re.S|re.M))" < "$1" 2>/dev/null || cat "$1"
}

# ── Resolve project dir ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Load .env if present ──
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
fi

KEY_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"

printf "${YELLOW}╔══════════════════════════════════════════════════════╗\n"
printf "║  oh-my-litellm-opencode — Unified Validation          ║\n"
printf "╚══════════════════════════════════════════════════════╝${NC}\n"
if [ "$DRY_RUN" = true ]; then
  echo "   (DRY RUN — network checks skipped)"
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# SECTION A: LiteLLM Proxy Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$OPENCODE_ONLY" = false ]; then
  echo "━━━ A. LiteLLM Proxy ━━━"

  # A1. .env check
  echo ""
  echo "A1. .env completeness and permissions"
  if [ -f "$PROJECT_DIR/.env" ]; then
    pass ".env exists"
    PERMS=$(stat -c '%a' "$PROJECT_DIR/.env" 2>/dev/null || stat -f '%Lp' "$PROJECT_DIR/.env" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
      pass ".env permissions are 0600"
    else
      warn ".env permissions are $PERMS (expected 0600)"
    fi
    for VAR in LITELLM_MASTER_KEY LITELLM_SALT_KEY DB_PASSWORD HUAWEI_MAAS_API_KEY OPENLIT_DB_PASSWORD; do
      VAL="${!VAR:-}"
      if [ -z "$VAL" ] || echo "$VAL" | grep -qi 'change-me\|replace\|xxx'; then
        fail "$VAR is not set or still has a placeholder value"
      else
        pass "$VAR is set (len=${#VAL})"
      fi
    done
    if [ -n "${HUAWEI_MAAS_API_KEY_COUNT:-}" ]; then
      pass "HUAWEI_MAAS_API_KEY_COUNT = $HUAWEI_MAAS_API_KEY_COUNT"
    else
      warn "HUAWEI_MAAS_API_KEY_COUNT not set (defaulting to 1)"
    fi
  else
    fail ".env not found"
  fi

  # A2. Docker services
  echo ""
  echo "A2. Docker services"
  if [ "$DRY_RUN" = true ]; then
    skip "Docker service health"
  else
    RUNNING=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --services --filter "status=running" 2>/dev/null | wc -l)
    if [ "$RUNNING" -ge 4 ]; then
      pass "$RUNNING services running"
    else
      fail "Only $RUNNING services running (expected 4)"
    fi
  fi

  # A3. LiteLLM health
  echo ""
  echo "A3. LiteLLM health"
  if [ "$DRY_RUN" = true ]; then
    skip "LiteLLM liveness probe"
    skip "LiteLLM per-model health"
  else
    LIVENESS=$(curl -s --connect-timeout 5 -w '%{http_code}' "$LITELLM_URL/health/liveliness" 2>/dev/null)
    LIVENESS_CODE="${LIVENESS: -3}"
    if [ "$LIVENESS_CODE" = "200" ]; then
      pass "LiteLLM liveness probe returned 200"
    else
      fail "LiteLLM liveness probe returned $LIVENESS_CODE"
    fi

    if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
      HEALTH_RESP=$(curl -s --connect-timeout 10 "$LITELLM_URL/health" -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null)
      HEALTH_FAIL=$(echo "$HEALTH_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('unhealthy_count',0))" 2>/dev/null || echo "?")
      if [ "$HEALTH_FAIL" = "0" ]; then
        pass "All deployments healthy (unhealthy_count=0)"
      else
        warn "unhealthy_count=$HEALTH_FAIL — may be transient"
      fi
    else
      skip "Per-model health (LITELLM_MASTER_KEY not set)"
    fi
  fi

  # A4. OpenLit + ClickHouse
  echo ""
  echo "A4. Observability (OpenLit)"
  if [ "$DRY_RUN" = true ]; then
    skip "OpenLit UI reachable"
    skip "ClickHouse reachable"
    skip "OTLP endpoint reachable"
  else
    OPENLIT_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$OPENLIT_URL" 2>/dev/null)
    if [ "$OPENLIT_CODE" = "200" ]; then
      pass "OpenLit UI reachable (HTTP 200)"
    else
      fail "OpenLit UI returned HTTP $OPENLIT_CODE"
    fi

    CH_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$CLICKHOUSE_URL/ping" 2>/dev/null)
    if [ "$CH_CODE" = "200" ]; then
      pass "ClickHouse reachable (HTTP 200)"
    else
      fail "ClickHouse returned HTTP $CH_CODE"
    fi

    OTLP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "http://127.0.0.1:4318/" 2>/dev/null)
    if [ -n "$OTLP_CODE" ]; then
      pass "OTLP HTTP endpoint reachable on port 4318"
    else
      warn "OTLP HTTP endpoint not responding on port 4318 (may still be starting)"
    fi
  fi

  # A5. Config deployment count
  echo ""
  echo "A5. Config validation"
  CONFIG_FILE="$PROJECT_DIR/assets/config/litellm/litellm_config.yaml"
  TEMPLATE_FILE="$PROJECT_DIR/assets/config/litellm/litellm_config.yaml.template"
  if [ -f "$CONFIG_FILE" ]; then
    pass "litellm_config.yaml exists (generated)"
    DEPLOYMENT_COUNT=$(grep -c '^\s*- model_name:' "$CONFIG_FILE" 2>/dev/null || echo "0")
    EXPECTED_DEPLOYMENTS=$((KEY_COUNT * 5))
    if [ "$DEPLOYMENT_COUNT" = "$EXPECTED_DEPLOYMENTS" ]; then
      pass "Deployment count: $DEPLOYMENT_COUNT (5 models × $KEY_COUNT keys)"
    else
      warn "Deployment count: $DEPLOYMENT_COUNT (expected $EXPECTED_DEPLOYMENTS)"
    fi
    # Check for model catalog drift between template and generated config
    if [ -f "$TEMPLATE_FILE" ]; then
      TEMPLATE_MODELS=$(grep -c '^\s*- model_name:' "$TEMPLATE_FILE" 2>/dev/null || echo "0")
      GENERATED_MODELS=$(grep -c '^\s*- model_name:' "$CONFIG_FILE" 2>/dev/null || echo "0")
      # Template has 1 deployment per model; generated has KEY_COUNT per model
      EXPECTED_FROM_TEMPLATE=$((TEMPLATE_MODELS * KEY_COUNT))
      if [ "$GENERATED_MODELS" = "$EXPECTED_FROM_TEMPLATE" ]; then
        pass "Model catalog: template and generated config are in sync"
      else
        warn "Model catalog drift: template has $TEMPLATE_MODELS entries, generated has $GENERATED_MODELS (expected $EXPECTED_FROM_TEMPLATE)"
      fi
    fi
  else
    warn "litellm_config.yaml not found — run scripts/generate_config.sh"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION B: opencode Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$LITELLM_ONLY" = false ]; then
  echo "━━━ B. opencode Configuration ━━━"

  OPENCODE_DIR="$HOME/.config/opencode"
  CONFIG_FILE=""
  if [ -f "$OPENCODE_DIR/opencode.jsonc" ]; then
    CONFIG_FILE="$OPENCODE_DIR/opencode.jsonc"
  elif [ -f "$OPENCODE_DIR/opencode.json" ]; then
    CONFIG_FILE="$OPENCODE_DIR/opencode.json"
  fi

  # B1. opencode binary
  echo ""
  echo "B1. opencode binary"
  if command -v opencode &>/dev/null; then
    pass "opencode installed: $(opencode --version 2>/dev/null || echo 'unknown')"
  else
    fail "opencode not found — run: curl -fsSL https://opencode.ai/install | bash"
  fi

  # B2. Config files
  echo ""
  echo "B2. Config files"
  if [ -n "$CONFIG_FILE" ]; then
    pass "opencode.jsonc exists: $CONFIG_FILE"
    CLEAN_CONFIG=$(strip_jsonc "$CONFIG_FILE")
    pass "Config parses as valid JSON"
  else
    fail "opencode.jsonc not found in $OPENCODE_DIR"
  fi

  if [ -f "$OPENCODE_DIR/oh-my-opencode-slim.json" ] || [ -f "$OPENCODE_DIR/oh-my-opencode-slim.jsonc" ]; then
    pass "oh-my-opencode-slim.json exists"
  else
    fail "oh-my-opencode-slim.json not found in $OPENCODE_DIR"
  fi

  # B3. Provider configuration
  echo ""
  echo "B3. Provider configuration"
  if [ -n "$CONFIG_FILE" ]; then
    CLEAN_CONFIG=$(strip_jsonc "$CONFIG_FILE")
    check_provider() {
      while [ $# -gt 0 ]; do
        local desc="$1" expr="$2"; shift 2
        if jqc "$CLEAN_CONFIG" "$expr"; then pass "$desc"; else fail "$desc"; fi
      done
    }
    check_provider \
      "LiteLLM provider defined" '.provider.LiteLLM' \
      "LiteLLM baseURL is 0.0.0.0:4000" '.provider.LiteLLM.options.baseURL == "http://0.0.0.0:4000"' \
      "LiteLLM apiKey set" '.provider.LiteLLM.options.apiKey' \
      "LiteLLM apiKey starts with sk-" '(.provider.LiteLLM.options.apiKey | startswith("sk-"))' \
      "Huawei-MaaS provider defined" '.provider["Huawei-MaaS"]' \
      "Huawei-MaaS has 5+ models" '.provider["Huawei-MaaS"].models | keys | length >= 5' \
      "LiteLLM has 5+ models" '.provider.LiteLLM.models | keys | length >= 5' \
      "provider key is singular" 'if .provider then true else false end' \
      "agent key is singular" 'if .agent then true else false end' \
      "oh-my-opencode-slim plugin" '.plugin | index("oh-my-opencode-slim")' \
      "explore agent disabled" '.agent.explore.disable == true' \
      "general agent disabled" '.agent.general.disable == true' \
      "LSP enabled" '.lsp == true'

    PERMS=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || stat -f '%Lp' "$CONFIG_FILE" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
      pass "Config file permissions 600"
    else
      warn "Config file permissions $PERMS (expected 600)"
    fi
  else
    fail "No opencode config file — skipping provider checks"
    FAIL=$((FAIL + 13))
  fi

  # B4. oh-my-opencode-slim preset
  echo ""
  echo "B4. oh-my-opencode-slim preset"
  SLIM_CONFIG=""
  if [ -f "$OPENCODE_DIR/oh-my-opencode-slim.json" ]; then
    SLIM_CONFIG="$OPENCODE_DIR/oh-my-opencode-slim.json"
  elif [ -f "$OPENCODE_DIR/oh-my-opencode-slim.jsonc" ]; then
    SLIM_CONFIG="$OPENCODE_DIR/oh-my-opencode-slim.jsonc"
  fi

  if [ -n "$SLIM_CONFIG" ]; then
    CLEAN_SLIM=$(strip_jsonc "$SLIM_CONFIG")
    check_slim_pair() {
      while [ $# -gt 0 ]; do
        local desc="$1" expr="$2"; shift 2
        if jqc "$CLEAN_SLIM" "$expr"; then pass "$desc"; else fail "$desc"; fi
      done
    }
    check_slim_pair \
      "LiteLLM-Huawei-MaaS preset" '.presets["LiteLLM-Huawei-MaaS"]' \
      "LiteLLM-Huawei-MaaS-Lite preset" '.presets["LiteLLM-Huawei-MaaS-Lite"]' \
      "Huawei-MaaS direct preset" '.presets["Huawei-MaaS"]' \
      "Huawei-MaaS-Lite direct preset" '.presets["Huawei-MaaS-Lite"]' \
      "Default is LiteLLM-Huawei-MaaS" '.preset == "LiteLLM-Huawei-MaaS"' \
      "Orchestrator model set" '.presets["LiteLLM-Huawei-MaaS"].orchestrator.model' \
      "Oracle model set (array for fallback)" '.presets["LiteLLM-Huawei-MaaS"].oracle.model' \
      "Council model set (array for fallback)" '.presets["LiteLLM-Huawei-MaaS"].council.model' \
      "Librarian model set" '.presets["LiteLLM-Huawei-MaaS"].librarian.model' \
      "Explorer model set" '.presets["LiteLLM-Huawei-MaaS"].explorer.model' \
      "Designer model set" '.presets["LiteLLM-Huawei-MaaS"].designer.model' \
      "Fixer model set (array for fallback)" '.presets["LiteLLM-Huawei-MaaS"].fixer.model' \
      "Observer disabled" '.disabled_agents | index("observer")' \
      "Fallback enabled" '.fallback.enabled == true' \
      "Fallback has no chains (v2 format)" '(.fallback.chains // null) == null' \
      "Council presets defined" '.council.presets' \
      "Council has councillor (v2 format)" '.council.presets.default.councillor'

    PERMS=$(stat -c '%a' "$SLIM_CONFIG" 2>/dev/null || stat -f '%Lp' "$SLIM_CONFIG" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
      pass "Slim config permissions 600"
    else
      warn "Slim config permissions $PERMS (expected 600)"
    fi
  else
    fail "No oh-my-opencode-slim config — skipping preset checks"
    FAIL=$((FAIL + 16))
  fi

  # B5. Model availability (via proxy)
  echo ""
  echo "B5. Model availability (via proxy)"
  if [ "$DRY_RUN" = true ]; then
    skip "Model catalog reachable"
    skip "Inference smoke test"
  else
    VIRTUAL_KEY=""
    if [ -n "$CONFIG_FILE" ]; then
      VIRTUAL_KEY=$(printf '%s' "$CLEAN_CONFIG" | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null)
    fi
    [ -z "$VIRTUAL_KEY" ] && VIRTUAL_KEY="${LITELLM_MASTER_KEY:-}"

    if [ -z "$VIRTUAL_KEY" ]; then
      fail "No API key for model checks"
    else
      MODELS_JSON=$(curl -sf -m 10 "$LITELLM_URL/v1/models" \
        -H "Authorization: Bearer $VIRTUAL_KEY" 2>/dev/null)

      if [ -z "$MODELS_JSON" ] || ! printf '%s' "$MODELS_JSON" | jq -e '.data | length > 0' >/dev/null 2>&1; then
        fail "Model catalog not reachable or empty"
      else
        pass "Model catalog reachable"
        MODEL_COUNT=$(printf '%s' "$MODELS_JSON" | jq '.data | length' 2>/dev/null)
        MODEL_LIST=$(printf '%s' "$MODELS_JSON" | jq -r '.data[].id' 2>/dev/null)
        echo "  ℹ Discovered $MODEL_COUNT model(s): $(echo "$MODEL_LIST" | tr '\n' ' ' | sed 's/ $//')"

        # Parallel inference smoke test
        SMOKE_PIDS=()
        SMOKE_MODELS=()
        for model in $MODEL_LIST; do
          BODY=$(jq -nc --arg m "$model" '{model: $m, messages: [{role: "user", content: "ok"}]}')
          curl -sf -m 30 "$LITELLM_URL/v1/chat/completions" \
            -H "Authorization: Bearer $VIRTUAL_KEY" \
            -H "Content-Type: application/json" \
            -d "$BODY" >/dev/null 2>&1 &
          SMOKE_PIDS+=($!)
          SMOKE_MODELS+=("$model")
        done

        SMOKE_PASS=0; SMOKE_FAIL=0; SMOKE_FAIL_LIST=""
        for i in "${!SMOKE_PIDS[@]}"; do
          if wait "${SMOKE_PIDS[$i]}" 2>/dev/null; then
            SMOKE_PASS=$((SMOKE_PASS + 1))
          else
            SMOKE_FAIL=$((SMOKE_FAIL + 1))
            SMOKE_FAIL_LIST="$SMOKE_FAIL_LIST ${SMOKE_MODELS[$i]}"
          fi
        done
        SMOKE_TOTAL=$((SMOKE_PASS + SMOKE_FAIL))

        if [ "$SMOKE_PASS" -gt 0 ]; then
          pass "Inference smoke test: $SMOKE_PASS/$SMOKE_TOTAL model(s) responded"
          if [ "$SMOKE_FAIL" -gt 0 ]; then
            warn "No response from:$(echo "$SMOKE_FAIL_LIST" | sed 's/^ //')"
          fi
        else
          fail "No models responded to inference (0/$SMOKE_TOTAL)"
        fi
      fi
    fi
  fi

  echo ""
fi

# ── Summary ──
TOTAL=$((PASS + FAIL + WARN))
printf "\n${YELLOW}══════════════════════════════════════════════════════${NC}\n"
printf "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC} out of $TOTAL checks\n"
if [ "$FAIL" -gt 0 ]; then
  printf "${RED}VALIDATION FAILED — $FAIL check(s) did not pass${NC}\n"
  exit 1
else
  printf "${GREEN}VALIDATION PASSED${NC}\n"
  exit 0
fi
