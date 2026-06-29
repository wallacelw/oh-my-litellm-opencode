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
#   ./0_bootstrap.sh                                    # interactive — installs all (litellm + opencode + codex + claude-code)
#   ./0_bootstrap.sh --maas-key=KEY                     # non-interactive (agent mode)
#   ./0_bootstrap.sh --agent --maas-key=KEY             # agent mode: non-interactive, fail-fast, validate + summary
#   ./0_bootstrap.sh --virtual-key=sk-...               # use existing virtual key (skip minting)
#   ./0_bootstrap.sh --litellm-only                     # LiteLLM proxy only, skip tool installation
#   ./0_bootstrap.sh --opencode-only                    # LiteLLM + opencode (skip Codex CLI)
#   ./0_bootstrap.sh --codex-only                       # LiteLLM + Codex CLI (skip opencode)
#   ./0_bootstrap.sh --claude-code-only                   # LiteLLM + Claude Code CLI (skip opencode + Codex)
#   ./0_bootstrap.sh --dry-run                          # preview changes
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
AGENT_MODE=false
LITELLM_ONLY=false
OPENCODE_ONLY=false
CODEX_ONLY=false
CLAUDE_CODE_ONLY=false

# ── Parse command-line arguments ──
for arg in "$@"; do
  case "$arg" in
    --maas-key=*)       MAAS_KEY="${arg#--maas-key=}" ;;
    --virtual-key=*)    VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --agent)            AGENT_MODE=true ;;
    --litellm-only)     LITELLM_ONLY=true ;;
    --opencode-only)    OPENCODE_ONLY=true ;;
    --codex-only)       CODEX_ONLY=true ;;
    --claude-code-only)  CLAUDE_CODE_ONLY=true ;;
    --dry-run)          DRY_RUN=true ;;
    *)
      echo "ERROR: Unknown argument: $arg"
      echo "Usage: $0 [--maas-key=KEY] [--agent] [--virtual-key=sk-...] [--litellm-only|--opencode-only|--codex-only|--claude-code-only] [--dry-run]"
      exit 1
      ;;
  esac
done

# ── Mode validation ──
MODE_COUNT=0
[ "$LITELLM_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$OPENCODE_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$CODEX_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$CLAUDE_CODE_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
if [ "$MODE_COUNT" -gt 1 ]; then
  echo "ERROR: --litellm-only, --opencode-only, --codex-only, and --claude-code-only are mutually exclusive."
  exit 1
fi

# ── Derive install flags ──
# Default (no flags): install everything
INSTALL_OPENCODE=true
INSTALL_CODEX=true
INSTALL_CLAUDE_CODE=true
if [ "$LITELLM_ONLY" = true ]; then
  INSTALL_OPENCODE=false
  INSTALL_CODEX=false
  INSTALL_CLAUDE_CODE=false
elif [ "$OPENCODE_ONLY" = true ]; then
  INSTALL_CODEX=false
  INSTALL_CLAUDE_CODE=false
elif [ "$CODEX_ONLY" = true ]; then
  INSTALL_OPENCODE=false
  INSTALL_CLAUDE_CODE=false
elif [ "$CLAUDE_CODE_ONLY" = true ]; then
  INSTALL_OPENCODE=false
  INSTALL_CODEX=false
fi

# ── Agent mode validation ──
if [ "$AGENT_MODE" = true ] && [ -z "$MAAS_KEY" ]; then
  echo "ERROR: --agent requires --maas-key=KEY"
  exit 1
fi

# ── Mutual exclusion: --litellm-only and --virtual-key ──
if [ "$LITELLM_ONLY" = true ] && [ -n "$VIRTUAL_KEY" ]; then
  echo "ERROR: --litellm-only and --virtual-key are mutually exclusive."
  exit 1
fi

# ── Virtual key only applies to opencode ──
if [ "$CODEX_ONLY" = true ] && [ -n "$VIRTUAL_KEY" ]; then
  echo "ERROR: --codex-only and --virtual-key are mutually exclusive (--virtual-key is for opencode)."
  exit 1
fi

if [ "$CLAUDE_CODE_ONLY" = true ] && [ -n "$VIRTUAL_KEY" ]; then
  echo "ERROR: --claude-code-only and --virtual-key are mutually exclusive (--virtual-key is for opencode)."
  exit 1
fi

# ── Resolve LITELLM_MASTER_KEY from multiple sources ──
# Returns the key on stdout; log messages go to stderr.
resolve_master_key() {
  # 1. Environment variable
  if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    echo "  Found LITELLM_MASTER_KEY in environment" >&2
    echo "$LITELLM_MASTER_KEY"
    return 0
  fi

  # 2. .env file
  if [ -f "$PROJECT_DIR/.env" ]; then
    local found_key
    found_key="$(grep -oP '^LITELLM_MASTER_KEY="?\K[^"]+' "$PROJECT_DIR/.env" 2>/dev/null || true)"
    if [ -n "$found_key" ]; then
      echo "  Found LITELLM_MASTER_KEY in $PROJECT_DIR/.env" >&2
      echo "$found_key"
      return 0
    fi
  fi

  return 1
}

# ── Prompt for LITELLM_MASTER_KEY if not found automatically ──
prompt_master_key() {
  if [ "$AGENT_MODE" = true ]; then
    echo "ERROR: LITELLM_MASTER_KEY not found. Set it in .env or environment before running with --agent."
    exit 1
  fi
  if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    echo "  LITELLM_MASTER_KEY not found in env or .env files."
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

if [ "$INSTALL_OPENCODE" = true ]; then
  check_prereq "bun"   bun     "install from https://bun.sh (needed for oh-my-opencode-slim plugin)"
  check_prereq "jq"    jq      "install from https://stedolan.github.io/jq/"
fi
if [ "$INSTALL_CODEX" = true ]; then
  check_prereq "npm"   npm     "install from https://nodejs.org/ (needed for Codex CLI)"
  check_prereq "jq"    jq      "install from https://stedolan.github.io/jq/"
fi
if [ "$INSTALL_CLAUDE_CODE" = true ]; then
  check_prereq "npm"   npm     "install from https://nodejs.org/ (needed for Claude Code CLI)"
  check_prereq "jq"    jq      "install from https://stedolan.github.io/jq/"
fi
if [ "$INSTALL_CODEX" = true ]; then
  check_prereq "bwrap" bwrap   "install with: apt-get install -y bubblewrap (needed for Codex CLI sandboxing)"
fi
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
  if [ "$AGENT_MODE" = true ]; then
    echo "ERROR: HUAWEI_MAAS_API_KEY is required in agent mode."; exit 1
  elif [ "$DRY_RUN" = true ]; then
    MAAS_KEY="<HUAWEI_MAAS_API_KEY>"
  else
    echo ""; echo "  Enter Huawei MaaS API key:"; read -r MAAS_KEY < /dev/tty
    [ -z "$MAAS_KEY" ] && { echo "ERROR: MaaS API key is required."; PREREQ_OK=false; }
  fi
else
  echo "  ✓ Huawei MaaS API key set"
fi
[ "$PREREQ_OK" = false ] && { echo ""; echo "ERROR: Prerequisites missing. Install them and re-run."; exit 1; }

# ── Configure git hooks (prevent committing secrets) ──
if [ -d "$PROJECT_DIR/.githooks" ]; then
  CURRENT_HOOKS=$(git -C "$PROJECT_DIR" config --local core.hooksPath 2>/dev/null || true)
  if [ "$CURRENT_HOOKS" != ".githooks" ]; then
    git -C "$PROJECT_DIR" config core.hooksPath .githooks
    echo "  ✓ Git hooks configured (.githooks/pre-commit blocks .env and secrets)"
  fi
fi

export HUAWEI_MAAS_API_KEY="$MAAS_KEY"
export HUAWEI_MAAS_API_KEY_0="$MAAS_KEY"

# ── Collect extra MaaS API keys for load balancing ──
EXTRA_KEY_COUNT=0
if [ "$AGENT_MODE" = true ]; then
  # Agent mode: read extra keys from env vars (HUAWEI_MAAS_API_KEY_1, _2, etc.)
  AUTO_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"
  SEQUENTIAL_IDX=1
  for i in $(seq 1 $((AUTO_COUNT - 1))); do
    VAR="HUAWEI_MAAS_API_KEY_$i"
    VAL="${!VAR:-}"
    if [ -n "$VAL" ]; then
      # Re-export with sequential numbering to avoid sparse indices
      export "HUAWEI_MAAS_API_KEY_$SEQUENTIAL_IDX=$VAL"
      EXTRA_KEY_COUNT=$SEQUENTIAL_IDX
      SEQUENTIAL_IDX=$((SEQUENTIAL_IDX + 1))
    fi
  done
  if [ "$EXTRA_KEY_COUNT" -gt 0 ]; then
    echo "  ✓ $((1 + EXTRA_KEY_COUNT)) MaaS API keys total (main + $EXTRA_KEY_COUNT extra)"
  else
    echo "  Using 1 MaaS API key (no load balancing)"
  fi
elif [ "$DRY_RUN" = true ]; then
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
if [ "$AGENT_MODE" = false ]; then
  if [ "$EXTRA_KEY_COUNT" -gt 0 ]; then
    echo "  ✓ $((1 + EXTRA_KEY_COUNT)) MaaS API keys total (main + $EXTRA_KEY_COUNT extra)"
  else
    echo "  Using 1 MaaS API key (no load balancing)"
  fi
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Deploy LiteLLM
print_step "3" "Deploy LiteLLM"

# ── Port conflict check ──
for port in 4000 5432 9090 3000; do
  if command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep -q ":${port} "; then
    echo "  WARNING: Port $port is already in use. Docker Compose may fail."
  elif command -v netstat &>/dev/null && netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
    echo "  WARNING: Port $port is already in use. Docker Compose may fail."
  fi
done

# ── 3a. Ensure .env exists ──
if [ ! -f "$PROJECT_DIR/.env" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "  Would run: scripts/1_init_env.sh --auto"
  else
    echo "  .env not found. Running init_env.sh --auto ..."
    (cd "$PROJECT_DIR" && ./scripts/1_init_env.sh --auto)
  fi
else
  # If --maas-key was provided and differs from .env, update .env
  ENV_MAAS_KEY=$(grep -oP '^HUAWEI_MAAS_API_KEY="?\K[^"]+' "$PROJECT_DIR/.env" 2>/dev/null || true)
  if [ -n "$MAAS_KEY" ] && [ "$MAAS_KEY" != "$ENV_MAAS_KEY" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  Would update HUAWEI_MAAS_API_KEY in .env and regenerate config"
    else
      echo "  Updating HUAWEI_MAAS_API_KEY in .env (key changed)..."
      # Safe .env update: replace key=value lines without sed injection risk
      python3 -c "
import sys
key, val, path = sys.argv[1], sys.argv[2], sys.argv[3]
lines = []
with open(path) as f:
    for line in f:
        if line.startswith(key + '=') or line.startswith(key + '=\"'):
            lines.append(f'{key}=\"{val}\"\n')
        else:
            lines.append(line)
with open(path, 'w') as f:
    f.writelines(lines)
" HUAWEI_MAAS_API_KEY "$MAAS_KEY" "$PROJECT_DIR/.env"
      python3 -c "
import sys
key, val, path = sys.argv[1], sys.argv[2], sys.argv[3]
lines = []
with open(path) as f:
    for line in f:
        if line.startswith(key + '=') or line.startswith(key + '=\"'):
            lines.append(f'{key}=\"{val}\"\n')
        else:
            lines.append(line)
with open(path, 'w') as f:
    f.writelines(lines)
" HUAWEI_MAAS_API_KEY_0 "$MAAS_KEY" "$PROJECT_DIR/.env"
      echo "  Config will be regenerated in Step 3."
      # Warn about stale extra keys
      ENV_KEY_COUNT=$(grep -oP '^HUAWEI_MAAS_API_KEY_COUNT=\K\d+' "$PROJECT_DIR/.env" 2>/dev/null || echo "1")
      if [ "$ENV_KEY_COUNT" -gt 1 ]; then
        echo "  NOTE: Extra MaaS keys (HUAWEI_MAAS_API_KEY_1..) were NOT updated. Rotate them manually if needed."
      fi
    fi
  fi
  # Check for missing env vars (e.g. upgrading from an older version)
  MISSING_VARS=""
  for required_var in GRAFANA_ADMIN_PASSWORD PROMETHEUS_RETENTION; do
    if ! grep -q "^${required_var}=" "$PROJECT_DIR/.env" 2>/dev/null; then
      MISSING_VARS="$MISSING_VARS $required_var"
    fi
  done
  if [ -n "$MISSING_VARS" ]; then
    if [ "$DRY_RUN" = true ]; then
      echo "  Would run init_env.sh --auto to add missing vars:$MISSING_VARS"
    else
      echo "  Missing env vars:$MISSING_VARS — running init_env.sh --auto to fill in (preserves existing secrets)..."
      (cd "$PROJECT_DIR" && ./scripts/1_init_env.sh --auto)
    fi
  else
    echo "  .env exists — skipping init_env.sh"
  fi
fi

# ── 3b. Deploy LiteLLM (config + Docker Compose) ──
if [ "$DRY_RUN" = true ]; then
  echo "  Would run: 2_deploy_litellm.sh --dry-run"
  LITELLM_MASTER_KEY="<LITELLM_MASTER_KEY>"
else
  (cd "$PROJECT_DIR" && ./scripts/2_deploy_litellm.sh)
fi

# ── 3c. Resolve master key ──
if [ "$DRY_RUN" = true ]; then
  LITELLM_MASTER_KEY="<LITELLM_MASTER_KEY>"
else
  try_resolve_master_key || prompt_master_key
fi

export LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-}"

# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Install tools (opencode + Codex CLI)
# ──────────────────────────────────────────────────────────────────────────────
print_step "4" "Install tools and configure"

# ── 4a. opencode ──
if [ "$INSTALL_OPENCODE" = true ]; then
  echo "  ── opencode + oh-my-opencode-slim ──"
  INSTALL_CMD=("$SCRIPT_DIR/4a_install_opencode.sh")
  [ -n "$VIRTUAL_KEY" ] && INSTALL_CMD+=("--virtual-key=$VIRTUAL_KEY")
  [ "$DRY_RUN" = true ] && INSTALL_CMD+=("--dry-run")

  if [ "$DRY_RUN" = true ]; then
    echo "  Would run: ${INSTALL_CMD[*]}"
  else
    "${INSTALL_CMD[@]}"
    echo "  opencode installation and configuration complete."
  fi
  echo ""
else
  echo "  (skipping opencode installation)"
fi

# ── 4b. Codex CLI ──
if [ "$INSTALL_CODEX" = true ]; then
  echo "  ── Codex CLI ──"
  CODEX_CMD=("$SCRIPT_DIR/4b_install_codex.sh")
  [ "$DRY_RUN" = true ] && CODEX_CMD+=("--dry-run")

  if [ "$DRY_RUN" = true ]; then
    echo "  Would run: ${CODEX_CMD[*]}"
  else
    "${CODEX_CMD[@]}"
    echo "  Codex CLI installation and configuration complete."
  fi
  echo ""
else
  echo "  (skipping Codex CLI installation)"
fi

# ── 4c. Claude Code CLI ──
if [ "$INSTALL_CLAUDE_CODE" = true ]; then
  echo "  ── Claude Code CLI ──"
  CLAUDE_CMD=("$SCRIPT_DIR/4c_install_claude_code.sh")
  [ "$DRY_RUN" = true ] && CLAUDE_CMD+=("--dry-run")

  if [ "$DRY_RUN" = true ]; then
    echo "  Would run: ${CLAUDE_CMD[*]}"
  else
    "${CLAUDE_CMD[@]}"
    echo "  Claude Code CLI installation and configuration complete."
  fi
  echo ""
else
  echo "  (skipping Claude Code CLI installation)"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Step 5: Validate
# ──────────────────────────────────────────────────────────────────────────────
print_step "5" "Validate"

VALIDATE_CMD=("$SCRIPT_DIR/5_validate.sh")
[ "$DRY_RUN" = true ] && VALIDATE_CMD+=("--dry-run")
if [ "$INSTALL_OPENCODE" = false ] && [ "$INSTALL_CODEX" = false ] && [ "$INSTALL_CLAUDE_CODE" = false ]; then
  VALIDATE_CMD+=("--litellm-only")
elif [ "$INSTALL_OPENCODE" = false ] && [ "$INSTALL_CODEX" = false ]; then
  VALIDATE_CMD+=("--claude-code-only")
elif [ "$INSTALL_OPENCODE" = false ] && [ "$INSTALL_CLAUDE_CODE" = false ]; then
  VALIDATE_CMD+=("--codex-only")
elif [ "$INSTALL_CODEX" = false ] && [ "$INSTALL_CLAUDE_CODE" = false ]; then
  VALIDATE_CMD+=("--opencode-only")
fi

if [ "$DRY_RUN" = true ]; then
  echo "  Would run: ${VALIDATE_CMD[*]}"
  VALIDATE_RC=0
else
  "${VALIDATE_CMD[@]}" || VALIDATE_RC=$?
  if [ "${VALIDATE_RC:-0}" -ne 0 ]; then
    echo "  Validation FAILED (exit code $VALIDATE_RC)."
  else
    echo "  Validation complete."
  fi
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
echo "Grafana:           http://127.0.0.1:3000 (anonymous, no login)"
echo "Prometheus:        http://127.0.0.1:9090"
if [ "$LITELLM_ONLY" = true ]; then
  echo ""
  echo "Mode:              LiteLLM-only (no tools)"
  echo ""
  echo "Next steps:"
  echo "  1. LiteLLM Admin UI: ${LITELLM_URL}/ui"
  echo "  2. To add opencode later:"
  echo "     ./scripts/0_bootstrap.sh --maas-key=\"\$KEY\" --opencode-only"
  echo "  3. To add Codex CLI later:"
  echo "     ./scripts/0_bootstrap.sh --maas-key=\"\$KEY\" --codex-only"
  echo "  4. To add Claude Code CLI later:"
  echo "     ./scripts/0_bootstrap.sh --maas-key=\"\$KEY\" --claude-code-only"
  echo "  5. Or mint a virtual key only:"
  echo "     ./scripts/3_mint_key.sh"
  if [ "$AGENT_MODE" = true ]; then
    echo ""
    echo "⚠️  Security: API keys were shared with the agent via command line"
    echo "   and environment variables. Rotate them to prevent unauthorized use."
    echo ""
    echo "  1. Get new MaaS key(s) from https://console.huaweicloud.com/modelarts/"
    echo "  2. Edit .env: replace HUAWEI_MAAS_API_KEY and HUAWEI_MAAS_API_KEY_1..N"
    echo "  3. Regenerate config: ./scripts/2_deploy_litellm.sh"
    echo "  4. Restart LiteLLM:  docker compose restart litellm"
    echo "  5. Re-validate:      ./scripts/5_validate.sh --litellm-only"
  fi
else
  if [ "$INSTALL_OPENCODE" = true ]; then
    echo "opencode config:    ~/.config/opencode/opencode.json"
    echo "plugin config:      ~/.config/opencode/oh-my-opencode-slim.json"
    # Show virtual key (masked) from config
    FINAL_VK=$(python3 -c "
import sys, json
text = open(sys.argv[1]).read()
# Quick JSONC strip: remove // line comments outside strings
result, in_str, esc, i = [], False, False, 0
while i < len(text):
    c = text[i]
    if esc: result.append(c); esc = False; i += 1; continue
    if in_str:
        result.append(c)
        if c == '\\\\': esc = True
        elif c == '\"': in_str = False
        i += 1; continue
    if c == '\"': in_str = True; result.append(c); i += 1; continue
    if c == '/' and i+1 < len(text) and text[i+1] == '/':
        while i < len(text) and text[i] != '\n': i += 1
        continue
    result.append(c); i += 1
d = json.loads(''.join(result))
print(d.get('provider',{}).get('LiteLLM',{}).get('options',{}).get('apiKey',''))
" "$HOME/.config/opencode/opencode.json" 2>/dev/null || true)
    if [ -n "$FINAL_VK" ]; then
      echo "opencode key:       ${FINAL_VK:0:8}...${FINAL_VK: -4}"
    fi
  fi
  if [ "$INSTALL_CODEX" = true ]; then
    echo "Codex CLI config:   ~/.codex/config.toml"
    CODEX_VK=""
    if [ -f "$HOME/.codex/.env" ]; then
      CODEX_VK=$(grep -oP '^LITELLM_CODEX_API_KEY=\K.*' "$HOME/.codex/.env" 2>/dev/null || true)
    fi
    if [ -n "$CODEX_VK" ]; then
      echo "Codex CLI key:      ${CODEX_VK:0:8}...${CODEX_VK: -4}"
    fi
  fi
  if [ "$INSTALL_CLAUDE_CODE" = true ]; then
    echo "Claude Code config: ~/.claude/settings.json"
    CLAUDE_VK=""
    if [ -f "$HOME/.claude/settings.json" ]; then
      CLAUDE_VK=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
    fi
    if [ -n "$CLAUDE_VK" ]; then
      echo "Claude Code key:    ${CLAUDE_VK:0:8}...${CLAUDE_VK: -4}"
    fi
  fi
  echo ""
  if [ "$AGENT_MODE" = true ]; then
    echo "Next steps:"
    if [ "$INSTALL_OPENCODE" = true ]; then
      echo "  1. Restart opencode to apply the new configuration:"
      echo "       - Exit any running opencode session (Ctrl+C or /exit)"
      echo "       - Start fresh: opencode"
      echo "  2. Switch preset: /preset LiteLLM-Huawei-MaaS-Core"
    fi
    if [ "$INSTALL_CODEX" = true ]; then
      echo "  ${INSTALL_OPENCODE:+3}. Run Codex CLI: codex"
    fi
    if [ "$INSTALL_CLAUDE_CODE" = true ]; then
      echo "  4. Run Claude Code CLI: claude --bare"
    fi
    echo ""
    echo "⚠️  Security: API keys were shared with the agent via command line"
    echo "   and environment variables. Rotate them to prevent unauthorized use."
    echo ""
    echo "  1. Get new MaaS key(s) from https://console.huaweicloud.com/modelarts/"
    echo "  2. Edit .env: replace HUAWEI_MAAS_API_KEY and HUAWEI_MAAS_API_KEY_1..N"
    echo "  3. Regenerate config: ./scripts/2_deploy_litellm.sh"
    echo "  4. Restart LiteLLM:  docker compose restart litellm"
    echo "  5. Re-validate:      ./scripts/5_validate.sh"
    echo ""
    echo "  Note: Virtual key is still valid — it's tied to LITELLM_MASTER_KEY,"
    echo "  not MaaS keys. No need to re-mint unless you also rotate the master key."
  else
    if [ "$INSTALL_OPENCODE" = true ]; then
      echo "Preset: LiteLLM-Huawei-MaaS-Full (default) — all 6 models via LiteLLM"
      echo "Core:    LiteLLM-Huawei-MaaS-Core — 4 models (no v4-pro/v4-flash)"
      echo "Direct: Huawei-MaaS-Full / Huawei-MaaS-Core — bypass LiteLLM proxy"
    fi
    echo ""
    echo "Next steps:"
    if [ "$INSTALL_OPENCODE" = true ]; then
      echo "  1. Restart opencode if it's already running (exit and start fresh)"
      echo "  2. Run: opencode"
      echo "  3. Verify preset: status bar should show LiteLLM-Huawei-MaaS-Full"
      echo "  4. Switch preset: /preset LiteLLM-Huawei-MaaS-Core"
    fi
    if [ "$INSTALL_CODEX" = true ]; then
      echo "  ${INSTALL_OPENCODE:+5}. Run Codex CLI: codex"
    fi
  fi
fi

# If validation failed, exit with its code (after showing summary + warning)
if [ "${VALIDATE_RC:-0}" -ne 0 ]; then
  exit "$VALIDATE_RC"
fi
