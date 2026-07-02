#!/usr/bin/env bash
# keys.sh — Shared key resolution and virtual-key minting helpers
#
# Source from any script:
#   source "$(dirname "${BASH_SOURCE[0]}")/helpers/keys.sh"
#
# Requires helpers/common.sh to be sourced first (for retry_curl).
#
# Provides:
#   resolve_master_key <project_dir>
#       Sets LITELLM_MASTER_KEY from: env var → .env → prompt (tty) / error.
#       Returns 1 if the key cannot be obtained.
#
#   mint_or_reuse_key <alias> [--models=M] [--budget=N] [--no-budget] [--duration=D] [--dry-run]
#       Reuses an existing valid virtual key with the given alias if one exists,
#       otherwise mints a new one. Prints the key (sk-...) to stdout.
#       Returns 1 on failure. Requires LITELLM_MASTER_KEY to be set.

# Resolve LITELLM_MASTER_KEY from environment, .env, or interactive prompt.
resolve_master_key() {
  local project_dir="$1"

  # 1. Already set in environment
  if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    return 0
  fi

  # 2. Read from .env
  if [ -f "$project_dir/.env" ]; then
    local found_key
    found_key="$(grep -oP '^LITELLM_MASTER_KEY="?\K[^"]+' "$project_dir/.env" 2>/dev/null || true)"
    if [ -n "$found_key" ]; then
      LITELLM_MASTER_KEY="$found_key"
      export LITELLM_MASTER_KEY
      return 0
    fi
  fi

  # 3. Prompt if interactive, else fail
  if [ -t 0 ]; then
    echo "  LITELLM_MASTER_KEY not found in env or .env." >&2
    echo "  Enter LITELLM_MASTER_KEY (or Ctrl+C to abort):" >&2
    read -r LITELLM_MASTER_KEY < /dev/tty
    if [ -z "$LITELLM_MASTER_KEY" ]; then
      echo "ERROR: LITELLM_MASTER_KEY is required to mint virtual keys." >&2
      return 1
    fi
    export LITELLM_MASTER_KEY
    return 0
  fi

  echo "ERROR: LITELLM_MASTER_KEY not found. Set it in .env or environment." >&2
  return 1
}

# Mint or reuse a scoped virtual key from LiteLLM.
# Prints the key to stdout. Log messages go to stderr.
mint_or_reuse_key() {
  local alias="$1"; shift
  local models="" budget="100" duration="" no_budget=false dry_run=false
  for arg in "$@"; do
    case "$arg" in
      --models=*)     models="${arg#--models=}" ;;
      --budget=*)     budget="${arg#--budget=}" ;;
      --duration=*)   duration="${arg#--duration=}" ;;
      --no-budget)    no_budget=true ;;
      --dry-run)      dry_run=true ;;
    esac
  done

  if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    echo "ERROR: LITELLM_MASTER_KEY not set. Call resolve_master_key first." >&2
    return 1
  fi

  local litellm_url="http://127.0.0.1:4000"

  # ── Dry run ──
  if [ "$dry_run" = true ]; then
    echo "sk-dryrun-placeholder"
    return 0
  fi

  # ── Build request body ──
  local jq_args=(--arg alias "$alias")
  local jq_filter='{key_alias: $alias'
  if [ -n "$models" ]; then
    local models_json
    models_json=$(echo "$models" | tr ',' '\n' | jq -R . | jq -s .)
    jq_args+=(--argjson models "$models_json")
    jq_filter+=', models: $models'
  fi
  if [ "$no_budget" = false ] && [ -n "$budget" ]; then
    jq_args+=(--argjson budget "$budget")
    jq_filter+=', max_budget: $budget'
  fi
  if [ -n "$duration" ]; then
    jq_args+=(--arg duration "$duration")
    jq_filter+=', duration: $duration'
  fi
  jq_filter+='}'
  local body
  body=$(jq -n "${jq_args[@]}" "$jq_filter")

  # ── Try to reuse existing key with same alias ──
  local existing_key=""
  local key_list
  key_list=$(curl -sf -m 10 "$litellm_url/key/list" \
    -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
  if [ -n "$key_list" ]; then
    local key_lookup_count=0
    local key_id key_info found_alias
    for key_id in $(echo "$key_list" | jq -r '.keys[]' 2>/dev/null); do
      if [ "$key_lookup_count" -ge 50 ]; then
        echo "  WARNING: Key lookup capped at 50 keys. If alias '$alias' exists beyond #50, a new key will be minted." >&2
        break
      fi
      key_lookup_count=$((key_lookup_count + 1))
      key_info=$(curl -sf -m 10 "$litellm_url/key/info?key=$key_id" \
        -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
      if [ -n "$key_info" ]; then
        found_alias=$(echo "$key_info" | jq -r '.info.key_alias // empty' 2>/dev/null)
        if [ "$found_alias" = "$alias" ]; then
          existing_key=$(echo "$key_info" | jq -r '.info.key_name // empty' 2>/dev/null)
          break
        fi
      fi
    done
  fi

  if [ -n "$existing_key" ] && [[ "$existing_key" == sk-* ]]; then
    # Validate the existing key still works (free /v1/models endpoint)
    if curl -sf -m 10 "$litellm_url/v1/models" \
       -H "Authorization: Bearer $existing_key" &>/dev/null; then
      echo "$existing_key"
      return 0
    fi
    echo "  Existing key with alias '$alias' is invalid or expired. Minting new key." >&2
  fi

  # ── Mint the key (retry with backoff) ──
  local max_attempts=3 response=""
  for attempt in $(seq 1 $max_attempts); do
    response=$(curl -sf --connect-timeout 10 --max-time 30 -X POST "$litellm_url/key/generate" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "$body" 2>/dev/null) && break
    if [ "$attempt" -lt $max_attempts ]; then
      local delay=$((attempt * 5))
      echo "  Attempt $attempt failed. Retrying in ${delay}s..." >&2
      sleep "$delay"
    else
      echo "ERROR: Failed to mint virtual key after $max_attempts attempts." >&2
      echo "  Check that LiteLLM is healthy and LITELLM_MASTER_KEY is correct." >&2
      return 1
    fi
  done

  local key
  key=$(echo "$response" | jq -r '.key')
  if [ -z "$key" ] || [ "$key" = "null" ]; then
    echo "ERROR: Failed to mint virtual key." >&2
    echo "Response: $response" >&2
    return 1
  fi

  echo "$key"
}
