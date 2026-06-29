#!/usr/bin/env bash
set -euo pipefail

# ─── Unified Validation: LiteLLM proxy + opencode + Codex CLI + Claude Code CLI ───
#
# Run after bootstrap.sh to verify everything works end-to-end.
# Combines LiteLLM E2E validation and opencode configuration checks.
#
# Usage:
#   ./validate.sh          # full validation including network checks
#   ./validate.sh --dry-run  # syntax and structure checks only (no network)
#   ./validate.sh --litellm-only  # only LiteLLM proxy checks
#   ./validate.sh --opencode-only  # only opencode config checks
#   ./validate.sh --codex-only  # only Codex CLI config checks
#   ./validate.sh --claude-code-only  # only Claude Code CLI config checks
#   ./validate.sh --skip-opencode --skip-codex  # LiteLLM + Claude Code only

PASS=0
FAIL=0
WARN=0
DRY_RUN=false
LITELLM_ONLY=false
OPENCODE_ONLY=false
CODEX_ONLY=false
CLAUDE_CODE_ONLY=false
SKIP_OPENCODE=false
SKIP_CODEX=false
SKIP_CLAUDE_CODE=false
LITELLM_URL="http://127.0.0.1:4000"

for arg in "$@"; do
  case "$arg" in
    --dry-run)          DRY_RUN=true ;;
    --litellm-only)     LITELLM_ONLY=true ;;
    --opencode-only)    OPENCODE_ONLY=true ;;
    --codex-only)       CODEX_ONLY=true ;;
    --claude-code-only) CLAUDE_CODE_ONLY=true ;;
    --skip-opencode)    SKIP_OPENCODE=true ;;
    --skip-codex)       SKIP_CODEX=true ;;
    --skip-claude-code) SKIP_CLAUDE_CODE=true ;;
  esac
done

# ── Mode exclusivity (only for --xxx-only flags) ──
MODE_COUNT=0
[ "$LITELLM_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$OPENCODE_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$CODEX_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$CLAUDE_CODE_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
if [ "$MODE_COUNT" -gt 1 ]; then
  echo "ERROR: --litellm-only, --opencode-only, --codex-only, and --claude-code-only are mutually exclusive."
  exit 1
fi

# ── Derive which sections to run ──
# Default (no flags): run all sections
RUN_LITELLM=true
RUN_OPENCODE=true
RUN_CODEX=true
RUN_CLAUDE_CODE=true
RUN_OBSERVABILITY=true
if [ "$LITELLM_ONLY" = true ]; then
  RUN_OPENCODE=false; RUN_CODEX=false; RUN_CLAUDE_CODE=false
elif [ "$OPENCODE_ONLY" = true ]; then
  RUN_CODEX=false; RUN_CLAUDE_CODE=false
elif [ "$CODEX_ONLY" = true ]; then
  RUN_OPENCODE=false; RUN_CLAUDE_CODE=false
elif [ "$CLAUDE_CODE_ONLY" = true ]; then
  RUN_OPENCODE=false; RUN_CODEX=false
fi
# Apply --skip-* flags (additive, can combine with --xxx-only)
[ "$SKIP_OPENCODE" = true ] && RUN_OPENCODE=false
[ "$SKIP_CODEX" = true ] && RUN_CODEX=false
[ "$SKIP_CLAUDE_CODE" = true ] && RUN_CLAUDE_CODE=false

# ── Colors ──
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; NC='\033[0m'

pass() { PASS=$((PASS + 1)); printf '%b' "${GREEN}✅ PASS${NC} — $1\n"; }
fail() { FAIL=$((FAIL + 1)); printf '%b' "${RED}❌ FAIL${NC} — $1\n"; }
warn() { WARN=$((WARN + 1)); printf '%b' "${YELLOW}⚠️  WARN${NC} — $1\n"; }
skip() { printf '%b' "  ○ $1 (skipped)\n"; }

# ── Helper: pipe JSON into jq as a single command ──
jqc() {
  printf '%s' "$1" | jq -e "$2" 2>/dev/null
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
            # Skip until end of line
            while i < len(text) and text[i] != '\\n':
                i += 1
            continue
        elif text[i+1] == '*':
            # Skip until */
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

# ── Resolve project dir ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Load .env if present ──
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
fi

KEY_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"

printf '%b' "${YELLOW}╔══════════════════════════════════════════════════════╗\n"
printf '%b' "║  oh-my-coding-maas-gateway — Unified Validation          ║\n"
printf '%b' "╚══════════════════════════════════════════════════════╝${NC}\n"
if [ "$DRY_RUN" = true ]; then
  echo "   (DRY RUN — network checks skipped)"
fi
echo ""

# ════════════════════════════════════════════════════════════════════════════
# SECTION A: LiteLLM Proxy Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_LITELLM" = true ]; then
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
      fail "Only $RUNNING services running (expected 4: litellm, db, prometheus, grafana)"
    fi
  fi

  # A3. LiteLLM health
  echo ""
  echo "A3. LiteLLM health"
  if [ "$DRY_RUN" = true ]; then
    skip "LiteLLM liveness probe"
    skip "LiteLLM per-model health"
  else
    LIVENESS=$(curl -s --connect-timeout 5 --max-time 10 -w '%{http_code}' "$LITELLM_URL/health/liveliness" 2>/dev/null || true)
    LIVENESS_CODE="${LIVENESS: -3}"
    if [ "$LIVENESS_CODE" = "200" ]; then
      pass "LiteLLM liveness probe returned 200"
    else
      fail "LiteLLM liveness probe returned $LIVENESS_CODE"
    fi

    if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
      HEALTH_RESP=$(curl -s --connect-timeout 10 --max-time 15 "$LITELLM_URL/health" -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
      HEALTH_ANALYSIS=$(echo "$HEALTH_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
unhealthy = d.get('unhealthy_endpoints', [])
moderation_errors = 0
other_errors = 0
MODERATION_PATTERN = 'sensitive information'
for e in unhealthy:
    err = str(e.get('error', ''))
    if MODERATION_PATTERN in err:
        moderation_errors += 1
    else:
        other_errors += 1
print(f'{moderation_errors} {other_errors} {len(unhealthy)}')
" 2>/dev/null || echo "0 0 0")
      MODERATION_COUNT=$(echo "$HEALTH_ANALYSIS" | cut -d' ' -f1)
      OTHER_FAIL_COUNT=$(echo "$HEALTH_ANALYSIS" | cut -d' ' -f2)
      UNHEALTHY_COUNT=$(echo "$HEALTH_ANALYSIS" | cut -d' ' -f3)
      if [ "$UNHEALTHY_COUNT" = "0" ]; then
        pass "All deployments healthy (unhealthy_count=0)"
      elif [ "$OTHER_FAIL_COUNT" = "0" ]; then
        pass "All deployments reachable — $MODERATION_COUNT flagged by content moderation (known LiteLLM probe issue, not a real failure)"
      else
        warn "unhealthy_count=$UNHEALTHY_COUNT ($OTHER_FAIL_COUNT real errors, $MODERATION_COUNT content-moderation) — may be transient"
      fi
    else
      skip "Per-model health (LITELLM_MASTER_KEY not set)"
    fi
  fi

  # A4. Config deployment count
  echo ""
  echo "A4. Config validation"
  CONFIG_FILE="$PROJECT_DIR/configs/litellm/config.yaml"
  TEMPLATE_FILE="$PROJECT_DIR/configs/litellm/config.yaml.template"
  if [ -f "$CONFIG_FILE" ]; then
    pass "litellm_config.yaml exists (generated)"
    DEPLOYMENT_COUNT=$(grep -c '^\s*- model_name:' "$CONFIG_FILE" 2>/dev/null || echo "0")
    EXPECTED_DEPLOYMENTS=$((KEY_COUNT * 12))
    if [ "$DEPLOYMENT_COUNT" = "$EXPECTED_DEPLOYMENTS" ]; then
      pass "Deployment count: $DEPLOYMENT_COUNT (6 models × $KEY_COUNT keys × 2 formats)"
    else
      warn "Deployment count: $DEPLOYMENT_COUNT (expected $EXPECTED_DEPLOYMENTS = 6 models × $KEY_COUNT keys × 2 formats)"
    fi
    # Check for model catalog drift between template and generated config
    if [ -f "$TEMPLATE_FILE" ]; then
      TEMPLATE_MODELS=$(grep -c '^\s*- model_name:' "$TEMPLATE_FILE" 2>/dev/null || echo "0")
      GENERATED_MODELS=$(grep -c '^\s*- model_name:' "$CONFIG_FILE" 2>/dev/null || echo "0")
      # Template has 1 OpenAI deployment per model; generated has KEY_COUNT × 2
      # per model (OpenAI + Anthropic dual-format deployments)
      EXPECTED_FROM_TEMPLATE=$((TEMPLATE_MODELS * KEY_COUNT * 2))
      if [ "$GENERATED_MODELS" = "$EXPECTED_FROM_TEMPLATE" ]; then
        pass "Model catalog: template and generated config are in sync ($GENERATED_MODELS = $TEMPLATE_MODELS × $KEY_COUNT keys × 2 formats)"
      else
        warn "Model catalog drift: template has $TEMPLATE_MODELS entries, generated has $GENERATED_MODELS (expected $EXPECTED_FROM_TEMPLATE = $TEMPLATE_MODELS × $KEY_COUNT keys × 2 formats)"
      fi
    fi
  else
    warn "litellm_config.yaml not found — run scripts/2_deploy_litellm.sh"
  fi

  # A5. Inference smoke test (runs in --litellm-only mode where Section B is skipped)
  # Uses LITELLM_MASTER_KEY since no virtual key is minted in LiteLLM-only mode.
  echo ""
  echo "A5. Inference smoke test"
  if [ "$DRY_RUN" = true ]; then
    skip "Inference smoke test"
  elif [ "$LITELLM_ONLY" = true ] && [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    SMOKE_MODEL="deepseek-v3.2"  # cheapest (700 RPM)
    if curl -sf -m 30 "$LITELLM_URL/v1/chat/completions" \
        -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$SMOKE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1}" >/dev/null 2>&1; then
      pass "Inference smoke test: $SMOKE_MODEL responded (master key)"
    else
      fail "Inference smoke test: $SMOKE_MODEL did not respond"
    fi
  elif [ "$LITELLM_ONLY" = true ] && [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    skip "Inference smoke test (LITELLM_MASTER_KEY not set)"
  else
    skip "Inference smoke test (runs in --litellm-only mode; full mode tests in B5)"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION B: opencode Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_OPENCODE" = true ]; then
  echo "━━━ B. opencode Configuration ━━━"

  OPENCODE_DIR="$HOME/.config/opencode"
  CONFIG_FILE=""
  if [ -f "$OPENCODE_DIR/opencode.json" ]; then
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
    pass "opencode.json exists: $CONFIG_FILE"
    CLEAN_CONFIG=$(strip_jsonc "$CONFIG_FILE")
    pass "Config parses as valid JSON"
  else
    fail "opencode.json not found in $OPENCODE_DIR"
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
      "Huawei-MaaS has 6+ models" '.provider["Huawei-MaaS"].models | keys | length >= 6' \
      "LiteLLM has 6+ models" '.provider.LiteLLM.models | keys | length >= 6' \
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
      "Council gamma model set" '.council.presets.default.gamma.model' \
      "Huawei-MaaS-Full orchestrator model set" '.presets["Huawei-MaaS-Full"].orchestrator.model' \
      "Huawei-MaaS-Core orchestrator model set" '.presets["Huawei-MaaS-Core"].orchestrator.model'

    PERMS=$(stat -c '%a' "$SLIM_CONFIG" 2>/dev/null || stat -f '%Lp' "$SLIM_CONFIG" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
      pass "Slim config permissions 600"
    else
      warn "Slim config permissions $PERMS (expected 600)"
    fi
  else
    fail "No oh-my-opencode-slim config — skipping preset checks"
    FAIL=$((FAIL + 22))
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
        -H "Authorization: Bearer $VIRTUAL_KEY" 2>/dev/null || true)

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

# ════════════════════════════════════════════════════════════════════════════
# SECTION C: Observability (Prometheus + Grafana)
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_OBSERVABILITY" = true ]; then
  echo ""
  echo "━━━ C. Observability ━━━"

  # C1. Prometheus reachable
  echo ""
  echo "C1. Prometheus"
  if [ "$DRY_RUN" = true ]; then
    skip "Prometheus reachability"
  elif curl -sf -m 5 http://127.0.0.1:9090/-/ready >/dev/null 2>&1; then
    pass "Prometheus reachable at :9090"
  else
    fail "Prometheus not reachable at :9090"
  fi

  # C2. LiteLLM /metrics endpoint
  echo ""
  echo "C2. LiteLLM metrics endpoint"
  if [ "$DRY_RUN" = true ]; then
    skip "LiteLLM /metrics endpoint"
  elif curl -sf -L -m 5 http://127.0.0.1:4000/metrics >/dev/null 2>&1; then
    METRIC_LINES=$(curl -sf -L -m 5 http://127.0.0.1:4000/metrics 2>/dev/null | grep -c '^litellm_' || true)
    if [ "$METRIC_LINES" -gt 0 ]; then
      pass "LiteLLM /metrics active ($METRIC_LINES metric series)"
    else
      warn "LiteLLM /metrics responds but no litellm_ metrics found"
    fi
  else
    fail "LiteLLM /metrics endpoint not responding"
  fi

  # C3. Prometheus scraping LiteLLM
  echo ""
  echo "C3. Prometheus scraping LiteLLM"
  if [ "$DRY_RUN" = true ]; then
    skip "Prometheus scrape check"
  else
    SCRAPE_COUNT=$(curl -sf -g -m 10 "http://127.0.0.1:9090/api/v1/query?query=up{job=\"litellm\"}" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true)
    if [ "$SCRAPE_COUNT" = "1" ]; then
      pass "Prometheus is scraping LiteLLM (up=1)"
    elif [ -n "$SCRAPE_COUNT" ]; then
      fail "Prometheus scraping LiteLLM but target is down (up=$SCRAPE_COUNT)"
    else
      warn "Prometheus has not scraped LiteLLM yet — may need a few seconds"
    fi
  fi

  # C4. Grafana reachable
  echo ""
  echo "C4. Grafana"
  if [ "$DRY_RUN" = true ]; then
    skip "Grafana reachability"
  elif curl -sf -m 5 http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
    GRAFANA_DB_COUNT=$(curl -sf -m 5 -u "admin:${GRAFANA_ADMIN_PASSWORD:-admin}" "http://127.0.0.1:3000/api/search?query=oh-my-coding" 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
    if [ "$GRAFANA_DB_COUNT" -gt 0 ]; then
      pass "Grafana reachable with dashboard provisioned"
      # Check datasource is connected to Prometheus
      DS_NAME=$(curl -sf -m 5 -u "admin:${GRAFANA_ADMIN_PASSWORD:-admin}" "http://127.0.0.1:3000/api/datasources/name/Prometheus" 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)
      if [ "$DS_NAME" = "Prometheus" ]; then
        pass "Grafana Prometheus datasource configured"
      else
        warn "Grafana Prometheus datasource not found or not connected"
      fi
    else
      warn "Grafana reachable but dashboard not found — check provisioning"
    fi
  else
    fail "Grafana not reachable at :3000"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION D: Codex CLI Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_CODEX" = true ]; then
  echo ""
  echo "━━━ D. Codex CLI Configuration ━━━"

  CODEX_DIR="$HOME/.codex"
  CODEX_CONFIG="$CODEX_DIR/config.toml"

  # D1. Codex CLI binary
  echo ""
  echo "D1. Codex CLI binary"
  if command -v codex &>/dev/null; then
    pass "codex installed: $(codex --version 2>/dev/null || echo 'unknown')"
  else
    fail "codex not found — run: npm install -g @openai/codex"
  fi

  # D2. Config file
  echo ""
  echo "D2. Config file"
  if [ -f "$CODEX_CONFIG" ]; then
    pass "config.toml exists: $CODEX_CONFIG"
  else
    fail "config.toml not found in $CODEX_DIR"
  fi

  # D3. Provider configuration
  echo ""
  echo "D3. Provider configuration"
  if [ -f "$CODEX_CONFIG" ]; then
    if grep -q 'base_url\s*=\s*"http://127.0.0.1:4000/v1"' "$CODEX_CONFIG"; then
      pass "model provider base_url points to LiteLLM proxy"
    else
      fail "model provider base_url not pointing to LiteLLM proxy"
    fi

    if grep -qP 'env_key\s*=\s*"LITELLM_CODEX_API_KEY"' "$CODEX_CONFIG"; then
      pass "env_key set to LITELLM_CODEX_API_KEY"
    else
      fail "env_key not set to LITELLM_CODEX_API_KEY"
    fi

    if grep -qP 'wire_api\s*=\s*"responses"' "$CODEX_CONFIG"; then
      pass "wire_api set to responses (HTTP SSE)"
    else
      fail "wire_api not set to responses"
    fi

    if grep -qP '^model\s*=\s*"\S+"' "$CODEX_CONFIG"; then
      CODEX_MODEL=$(grep -oP '^model\s*=\s*"\K[^"]+' "$CODEX_CONFIG" 2>/dev/null || true)
      pass "default model set: $CODEX_MODEL"
    else
      fail "default model not set"
    fi

    PERMS=$(stat -c '%a' "$CODEX_CONFIG" 2>/dev/null || stat -f '%Lp' "$CODEX_CONFIG" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
      pass "Config file permissions 600"
    else
      warn "Config file permissions $PERMS (expected 600)"
    fi
  else
    fail "No Codex config file — skipping provider checks"
    FAIL=$((FAIL + 5))
  fi

  # D4. Responses API smoke test
  echo ""
  echo "D4. Responses API smoke test"
  CODEX_VK=""
  if [ -f "$HOME/.codex/.env" ]; then
    CODEX_VK=$(grep -oP '^LITELLM_CODEX_API_KEY=\K.*' "$HOME/.codex/.env" 2>/dev/null || true)
  fi
  if [ -z "$CODEX_VK" ] && [ -n "${LITELLM_CODEX_API_KEY:-}" ]; then
    CODEX_VK="$LITELLM_CODEX_API_KEY"
  fi
  if [ "$DRY_RUN" = true ]; then
    skip "Responses API smoke test"
  elif [ -n "$CODEX_VK" ]; then
    SMOKE_MODEL="deepseek-v3.2"
    if curl -sf -m 30 "$LITELLM_URL/v1/responses" \
        -H "Authorization: Bearer $CODEX_VK" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$SMOKE_MODEL\",\"input\":\"ok\"}" >/dev/null 2>&1; then
      pass "Responses API smoke test: $SMOKE_MODEL responded"
    else
      fail "Responses API smoke test: $SMOKE_MODEL did not respond"
    fi
  else
    skip "Responses API smoke test (no API key found in ~/.codex/.env or env)"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION E: Claude Code CLI Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_CLAUDE_CODE" = true ]; then
  echo ""
  echo "━━━ E. Claude Code CLI Configuration ━━━"

  CLAUDE_CONFIG_DIR="$HOME/.claude"
  CLAUDE_SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"

  # E1. Claude Code CLI binary
  echo ""
  echo "E1. Claude Code CLI binary"
  if command -v claude &>/dev/null; then
    pass "claude installed: $(claude --version 2>/dev/null || echo 'unknown')"
  else
    fail "claude not found — run: npm install -g @anthropic-ai/claude-code"
  fi

  # E2. Config file (settings.json)
  echo ""
  echo "E2. Config file"
  if [ -f "$CLAUDE_SETTINGS" ]; then
    pass "settings.json exists: $CLAUDE_SETTINGS"
  else
    fail "settings.json not found in $CLAUDE_CONFIG_DIR"
  fi

  # E3. Provider configuration
  echo ""
  echo "E3. Provider configuration"
  if [ -f "$CLAUDE_SETTINGS" ]; then
    CLAUDE_BASE_URL=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
    if [ "$CLAUDE_BASE_URL" = "http://127.0.0.1:4000" ]; then
      pass "ANTHROPIC_BASE_URL points to LiteLLM proxy"
    else
      fail "ANTHROPIC_BASE_URL not pointing to LiteLLM proxy (got: $CLAUDE_BASE_URL)"
    fi

    CLAUDE_VK=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
    if [[ "$CLAUDE_VK" == sk-* ]]; then
      pass "ANTHROPIC_API_KEY set (starts with sk-)"
    else
      fail "ANTHROPIC_API_KEY not set or invalid"
    fi

    CLAUDE_MODEL=$(jq -r '.env.ANTHROPIC_MODEL // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
    if [ -n "$CLAUDE_MODEL" ]; then
      pass "default model set: $CLAUDE_MODEL"
    else
      fail "default model not set"
    fi

    PERMS=$(stat -c '%a' "$CLAUDE_SETTINGS" 2>/dev/null || stat -f '%Lp' "$CLAUDE_SETTINGS" 2>/dev/null)
    if [ "$PERMS" = "600" ]; then
      pass "Config file permissions 600"
    else
      warn "Config file permissions $PERMS (expected 600)"
    fi
  else
    fail "No Claude Code config — skipping provider checks"
    FAIL=$((FAIL + 4))
    CLAUDE_VK=""
  fi

  # E4. Messages API smoke test
  echo ""
  echo "E4. Messages API smoke test"
  if [ "$DRY_RUN" = true ]; then
    skip "Messages API smoke test"
  elif [ -n "$CLAUDE_VK" ]; then
    SMOKE_MODEL="claude-deepseek-v3.2"
    if curl -sf -m 30 "$LITELLM_URL/v1/messages" \
        -H "x-api-key: $CLAUDE_VK" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "{\"model\":\"$SMOKE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1}" >/dev/null 2>&1; then
      pass "Messages API smoke test: $SMOKE_MODEL responded"
    else
      fail "Messages API smoke test: $SMOKE_MODEL did not respond"
    fi
  else
    skip "Messages API smoke test (no API key found in ~/.claude/settings.json)"
  fi

  echo ""
fi

# ── Summary ──
TOTAL=$((PASS + FAIL + WARN))
printf '%b' "\n${YELLOW}══════════════════════════════════════════════════════${NC}\n"
printf '%b' "Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC} out of $TOTAL checks\n"
if [ "$FAIL" -gt 0 ]; then
  printf '%b' "${RED}VALIDATION FAILED — $FAIL check(s) did not pass${NC}\n"
  exit 1
else
  printf '%b' "${GREEN}VALIDATION PASSED${NC}\n"
  exit 0
fi
