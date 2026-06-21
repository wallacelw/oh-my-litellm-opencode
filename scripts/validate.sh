#!/usr/bin/env bash
set -uo pipefail

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
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"

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
  local file="$1"
  if command -v python3 &>/dev/null; then
    python3 -c "
import sys
def strip_jsonc(s):
    out = []; i = 0; n = len(s)
    while i < n:
        if s[i] == '\"':
            j = i + 1
            while j < n:
                if s[j] == '\\\\': j += 2; continue
                if s[j] == '\"': break
                j += 1
            out.append(s[i:j+1]); i = j + 1; continue
        if i+1 < n and s[i] == '/' and s[i+1] == '*':
            j = s.find('*/', i+2)
            if j == -1: j = n-2
            out.append(' '); i = j + 2; continue
        if i+1 < n and s[i] == '/' and s[i+1] == '/':
            j = s.find('\n', i+2)
            if j == -1: i = n
            else: i = j
            continue
        out.append(s[i]); i += 1
    return ''.join(out)
sys.stdout.write(strip_jsonc(sys.stdin.read()))
" < "$file"
  elif command -v node &>/dev/null; then
    node -e "const fs=require('fs'); const s=fs.readFileSync('$file','utf8'); const r=s.replace(/\\/\\/.*$/gm,'').replace(/\\/\\*[\\s\\S]*?\\*\\//g,''); process.stdout.write(r);" 2>/dev/null
  elif jq -e . "$file" &>/dev/null; then
    cat "$file"
  else
    echo "ERROR: Cannot parse JSONC file '$file'" >&2
    return 1
  fi
}

# ── Resolve project dir ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Load .env if present ──
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
fi

KEY_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"
MAAS_API_BASE="${HUAWEI_MAAS_API_BASE:-https://api-ap-southeast-1.modelarts-maas.com/openai/v1}"

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
    for VAR in LITELLM_MASTER_KEY LITELLM_SALT_KEY DB_PASSWORD HUAWEI_MAAS_API_KEY; do
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

  # A4. Prometheus & Grafana
  echo ""
  echo "A4. Observability"
  if [ "$DRY_RUN" = true ]; then
    skip "Prometheus target"
    skip "Grafana reachable"
  else
    PROM_HEALTH=$(curl -s --connect-timeout 5 "$PROMETHEUS_URL/api/v1/targets" 2>/dev/null | \
      python3 -c "import sys,json; d=json.load(sys.stdin); ts=d['data']['activeTargets']; print(ts[0]['health'] if ts else 'none')" 2>/dev/null || echo "error")
    if [ "$PROM_HEALTH" = "up" ]; then
      pass "Prometheus target litellm is up"
    else
      fail "Prometheus target health: $PROM_HEALTH (expected up)"
    fi

    GRAFANA_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$GRAFANA_URL" 2>/dev/null)
    if [ "$GRAFANA_CODE" = "200" ] || [ "$GRAFANA_CODE" = "302" ]; then
      pass "Grafana reachable (HTTP $GRAFANA_CODE)"
    else
      fail "Grafana returned HTTP $GRAFANA_CODE"
    fi
  fi

  # A5. Config deployment count
  echo ""
  echo "A5. Config validation"
  CONFIG_FILE="$PROJECT_DIR/assets/config/litellm/litellm_config.yaml"
  if [ -f "$CONFIG_FILE" ]; then
    pass "litellm_config.yaml exists (generated)"
    DEPLOYMENT_COUNT=$(grep -c '^\s*- model_name:' "$CONFIG_FILE" 2>/dev/null || echo "0")
    EXPECTED_DEPLOYMENTS=$((KEY_COUNT * 5))
    if [ "$DEPLOYMENT_COUNT" = "$EXPECTED_DEPLOYMENTS" ]; then
      pass "Deployment count: $DEPLOYMENT_COUNT (5 models × $KEY_COUNT keys)"
    else
      warn "Deployment count: $DEPLOYMENT_COUNT (expected $EXPECTED_DEPLOYMENTS)"
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
    fail "opencode not found — run: bun install -g opencode"
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
    check_jq() {
      local desc="$1" expr="$2"
      if jqc "$CLEAN_CONFIG" "$expr"; then pass "$desc"; else fail "$desc"; fi
    }
    check_jq "LiteLLM provider defined" '.provider.LiteLLM'
    check_jq "LiteLLM baseURL is 0.0.0.0:4000" '.provider.LiteLLM.options.baseURL == "http://0.0.0.0:4000"'
    check_jq "LiteLLM apiKey set" '.provider.LiteLLM.options.apiKey'
    check_jq "LiteLLM apiKey starts with sk-" '(.provider.LiteLLM.options.apiKey | startswith("sk-"))'
    check_jq "Huawei-MaaS provider defined" '.provider["Huawei-MaaS"]'
    check_jq "Huawei-MaaS has 5+ models" '.provider["Huawei-MaaS"].models | keys | length >= 5'
    check_jq "LiteLLM has 5+ models" '.provider.LiteLLM.models | keys | length >= 5'
    check_jq "provider key is singular" 'if .provider then true else false end'
    check_jq "agent key is singular" 'if .agent then true else false end'
    check_jq "oh-my-opencode-slim plugin" '.plugin | index("oh-my-opencode-slim")'
    check_jq "explore agent disabled" '.agent.explore.disable == true'
    check_jq "general agent disabled" '.agent.general.disable == true'
    check_jq "LSP enabled" '.lsp == true'

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
    check_slim() {
      local desc="$1" expr="$2"
      if jqc "$CLEAN_SLIM" "$expr"; then pass "$desc"; else fail "$desc"; fi
    }
    check_slim "LiteLLM-Huawei-MaaS preset" '.presets["LiteLLM-Huawei-MaaS"]'
    check_slim "LiteLLM-Huawei-MaaS-Lite preset" '.presets["LiteLLM-Huawei-MaaS-Lite"]'
    check_slim "Huawei-MaaS direct preset" '.presets["Huawei-MaaS"]'
    check_slim "Huawei-MaaS-Lite direct preset" '.presets["Huawei-MaaS-Lite"]'
    check_slim "Default is LiteLLM-Huawei-MaaS" '.preset == "LiteLLM-Huawei-MaaS"'
    check_slim "Orchestrator model set" '.presets["LiteLLM-Huawei-MaaS"].orchestrator.model'
    check_slim "Oracle model set" '.presets["LiteLLM-Huawei-MaaS"].oracle.model'
    check_slim "Council model set" '.presets["LiteLLM-Huawei-MaaS"].council.model'
    check_slim "Librarian model set" '.presets["LiteLLM-Huawei-MaaS"].librarian.model'
    check_slim "Explorer model set" '.presets["LiteLLM-Huawei-MaaS"].explorer.model'
    check_slim "Designer model set" '.presets["LiteLLM-Huawei-MaaS"].designer.model'
    check_slim "Fixer model set" '.presets["LiteLLM-Huawei-MaaS"].fixer.model'
    check_slim "Observer disabled" '.disabled_agents | index("observer")'
    check_slim "Fallback enabled" '.fallback.enabled == true'
    check_slim "Fallback chains defined" '.fallback.chains | length > 0'
    check_slim "Council presets defined" '.council.presets'
    check_slim "Council has alpha/beta/gamma" '.council.presets.default | .alpha and .beta and .gamma'

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
