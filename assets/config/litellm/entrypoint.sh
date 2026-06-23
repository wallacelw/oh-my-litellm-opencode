#!/usr/bin/env bash
set -e

# ─── LiteLLM entrypoint ───

exec python -m litellm "$@"
