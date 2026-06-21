#!/usr/bin/env bash
set -euo pipefail

# ─── Mint a scoped virtual key from LiteLLM ───
#
# Usage:
#   ./mint-virtual-key.sh                                    # key with alias, budget 100, duration 30d
#   ./mint-virtual-key.sh --models=glm-5.1,deepseek-v3.2    # model-scoped key
#   ./mint-virtual-key.sh --budget=50 --duration=7d          # custom budget + duration
#   ./mint-virtual-key.sh --models=glm-5.1 --budget=10       # model-scoped with budget
#   ./mint-virtual-key.sh --alias=my-key                     # custom alias
#   ./mint-virtual-key.sh --no-budget                        # unlimited budget (dangerous)

# ── Parse args ──
MODELS=""
BUDGET="100"
DURATION=""
ALIAS="opencode"
NO_BUDGET=false
for arg in "$@"; do
  case "$arg" in
    --models=*)     MODELS="${arg#--models=}" ;;
    --budget=*)     BUDGET="${arg#--budget=}" ;;
    --duration=*)   DURATION="${arg#--duration=}" ;;
    --alias=*)      ALIAS="${arg#--alias=}" ;;
    --no-budget)    NO_BUDGET=true ;;
  esac
done

if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
  echo "ERROR: LITELLM_MASTER_KEY not set. Export it before running this script."
  exit 1
fi

# ── Build request body ──
JQ_ARGS=(--arg alias "$ALIAS")
JQ_FILTER='{key_alias: $alias'
if [ -n "$MODELS" ]; then
  MODELS_JSON=$(echo "$MODELS" | tr ',' '\n' | jq -R . | jq -s .)
  JQ_ARGS+=(--argjson models "$MODELS_JSON")
  JQ_FILTER+=', models: $models'
fi
if [ "$NO_BUDGET" = false ] && [ -n "$BUDGET" ]; then
  JQ_ARGS+=(--argjson budget "$BUDGET")
  JQ_FILTER+=', max_budget: $budget'
fi
if [ -n "$DURATION" ]; then
  JQ_ARGS+=(--arg duration "$DURATION")
  JQ_FILTER+=', duration: $duration'
fi
JQ_FILTER+='}'
BODY=$(jq -n "${JQ_ARGS[@]}" "$JQ_FILTER")

# ── Try to reuse existing key with same alias ──
# Falls back to minting if /key/list is unavailable or returns no match.
# This is intentional — the reuse is best-effort, not required.
LITELLM_URL="http://127.0.0.1:4000"
EXISTING_KEY=""
if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
  KEY_LIST=$(curl -sf -m 10 "$LITELLM_URL/key/list" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
  if [ -n "$KEY_LIST" ]; then
    # /key/list may not exist in all LiteLLM versions; jq failure is non-fatal
    EXISTING_KEY=$(echo "$KEY_LIST" | jq -r ".keys[] | select(.key_alias == \"$ALIAS\") | .key" 2>/dev/null | head -1 || true)
  fi
fi

if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
  # Validate the existing key still works
  if curl -sf -m 10 "$LITELLM_URL/v1/chat/completions" \
     -H "Authorization: Bearer $EXISTING_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"glm-5.1","messages":[{"role":"user","content":"ok"}],"max_tokens":1}' &>/dev/null; then
    echo "Existing virtual key with alias '$ALIAS' is valid. Reusing:"
    echo "  Key:    ${EXISTING_KEY:0:8}...${EXISTING_KEY: -4}"
    echo ""
    echo "To use this key, set it in opencode.jsonc:"
    echo "  .provider.LiteLLM.options.apiKey = \"$EXISTING_KEY\""
    echo ""
    echo "Or re-run install.sh:"
    echo "  ./install.sh --virtual-key=$EXISTING_KEY"
    exit 0
  else
    echo "Existing key with alias '$ALIAS' is invalid or expired. Minting new key."
  fi
fi

# ── Mint the key ──
echo "Minting virtual key from LiteLLM..."
echo "  Alias:   $ALIAS"
echo "  Models:  ${MODELS:-all}"
echo "  Budget:  $([ "$NO_BUDGET" = true ] && echo 'unlimited' || echo "\$${BUDGET}")"
echo "  Duration: ${DURATION}"
echo ""

# Retry curl with backoff (3 attempts, 5s/10s/15s delay)
MAX_ATTEMPTS=3
RESPONSE=""
for attempt in $(seq 1 $MAX_ATTEMPTS); do
  RESPONSE=$(curl -sf --connect-timeout 10 --max-time 30 -X POST http://127.0.0.1:4000/key/generate \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
    -H "Content-Type: application/json" \
    -d "$BODY" 2>/dev/null) && break
  if [ $attempt -lt $MAX_ATTEMPTS ]; then
    DELAY=$((attempt * 5))
    echo "  Attempt $attempt failed. Retrying in ${DELAY}s..."
    sleep $DELAY
  else
    echo "ERROR: Failed to mint virtual key after $MAX_ATTEMPTS attempts."
    echo "  Check that LiteLLM is healthy and LITELLM_MASTER_KEY is correct."
    exit 1
  fi
done

KEY=$(echo "$RESPONSE" | jq -r '.key')
KEY_ID=$(echo "$RESPONSE" | jq -r '.key_id // empty')

if [ -z "$KEY" ] || [ "$KEY" = "null" ]; then
  echo "ERROR: Failed to mint virtual key."
  echo "Response: $RESPONSE"
  exit 1
fi

echo "Virtual key minted successfully:"
echo "  Key:    ${KEY:0:8}...${KEY: -4}"
[ -n "$KEY_ID" ] && echo "  Key ID: $KEY_ID"
echo ""
echo "To use this key, set it in opencode.jsonc:"
echo "  .provider.LiteLLM.options.apiKey = \"$KEY\""
echo ""
echo "Or re-run install.sh:"
echo "  ./install.sh --virtual-key=$KEY"
