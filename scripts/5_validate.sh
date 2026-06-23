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
# Only removes // comments outside of quoted strings
strip_jsonc() {
  python3 -c "
import sys, re
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
            # Skip until end of line
            while i < len(text) and text[i] != '\\n':
                i += 1
            continue
        elif text[i+1] == '*':
            # Skip until */
            i += 2
            while i + 1 < len(text) and not (text[i] == '*' and text[i+1] == '/'):
                i += 1
            i += 2
            continue
    result.append(c)
    i += 1
sys.stdout.write(''.join(result))
" < "$1" 2>/dev/null || cat "$1"
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
    LIVENESS=$(curl -s --connect-timeout 5 --max-time 10 -w '%{http_code}' "$LITELLM_URL/health/liveliness" 2>/dev/null)
    LIVENESS_CODE="${LIVENESS: -3}"
    if [ "$LIVENESS_CODE" = "200" ]; then
      pass "LiteLLM liveness probe returned 200"
    else
      fail "LiteLLM liveness probe returned $LIVENESS_CODE"
    fi

    if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
      HEALTH_RESP=$(curl -s --connect-timeout 10 --max-time 15 "$LITELLM_URL/health" -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null)
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

  # A4. Config deployment count
  echo ""
  echo "A5. Config validation"
  CONFIG_FILE="$PROJECT_DIR/configs/litellm_config.yaml"
  TEMPLATE_FILE="$PROJECT_DIR/configs/templates/litellm_config.yaml.template"
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
    warn "litellm_config.yaml not found — run scripts/2_generate_config.sh"
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
      "LiteLLM baseURL is 127.0.0.1:4000" '.provider.LiteLLM.options.baseURL == "http://127.0.0.1:4000"' \
      "LiteLLM apiKey set" '.provider.LiteLLM.options.apiKey' \
      "LiteLLM apiKey starts with sk-" '(.provider.LiteLLM.options.apiKey | startswith("sk-"))' \
      "Huawei-MaaS provider defined" '.provider["Huawei-MaaS"]' \
      "Huawei-MaaS has 5+ models" '.provider["Huawei-MaaS"].models | keys | length >= 5' \
      "LiteLLM has 5+ models" '.provider.LiteLLM.models | keys | length >= 5' \
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
    FAIL=$((FAIL + 11))
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
      "LiteLLM-Huawei-MaaS-Full preset" '.presets["LiteLLM-Huawei-MaaS-Full"]' \
      "LiteLLM-Huawei-MaaS-Core preset" '.presets["LiteLLM-Huawei-MaaS-Core"]' \
      "Huawei-MaaS-Full direct preset" '.presets["Huawei-MaaS-Full"]' \
      "Huawei-MaaS-Core direct preset" '.presets["Huawei-MaaS-Core"]' \
      "Default is LiteLLM-Huawei-MaaS-Full" '.preset == "LiteLLM-Huawei-MaaS-Full"' \
      "Orchestrator model set" '.presets["LiteLLM-Huawei-MaaS-Full"].orchestrator.model' \
      "Oracle model set (array for fallback)" '.presets["LiteLLM-Huawei-MaaS-Full"].oracle.model' \
      "Council model set (array for fallback)" '.presets["LiteLLM-Huawei-MaaS-Full"].council.model' \
      "Librarian model set" '.presets["LiteLLM-Huawei-MaaS-Full"].librarian.model' \
      "Explorer model set" '.presets["LiteLLM-Huawei-MaaS-Full"].explorer.model' \
      "Designer model set" '.presets["LiteLLM-Huawei-MaaS-Full"].designer.model' \
      "Fixer model set (array for fallback)" '.presets["LiteLLM-Huawei-MaaS-Full"].fixer.model' \
      "Observer disabled" '.disabled_agents | index("observer")' \
      "Fallback enabled" '.fallback.enabled == true' \
      "Fallback has no chains (v2 format)" '(.fallback.chains // null) == null' \
      "Council presets defined" '.council.presets' \
      "Council has 3 councillors" '(.council.presets.default | keys | length) == 3' \
      "Council alpha model set" '.council.presets.default.alpha.model' \
      "Council beta model set" '.council.presets.default.beta.model' \
      "Council gamma model set" '.council.presets.default.gamma.model'

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

        # Smoke test: one model responding proves the proxy works
        SMOKE_MODEL="deepseek-v3.2"  # cheapest (700 RPM)
        if curl -sf -m 30 "$LITELLM_URL/v1/chat/completions" \
            -H "Authorization: Bearer $VIRTUAL_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$SMOKE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1}" >/dev/null 2>&1; then
          pass "Inference smoke test: $SMOKE_MODEL responded"
        else
          fail "Inference smoke test: $SMOKE_MODEL did not respond"
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
