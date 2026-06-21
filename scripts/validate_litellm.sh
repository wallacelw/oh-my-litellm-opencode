#!/usr/bin/env bash
# validate_litellm.sh — LiteLLM proxy validation (thin wrapper)
# Usage: ./scripts/validate_litellm.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/validate.sh" --litellm-only "$@"
