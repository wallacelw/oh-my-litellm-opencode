#!/bin/sh
# Patch LiteLLM health check probe messages for Huawei MaaS compatibility.
# "Hey how's it going?" triggers the Huawei MaaS content moderation filter;
# replace it with "What's 1 + 1?" which passes. Use double quotes so the
# apostrophe in the replacement is literal; use . wildcard for the apostrophe
# in the search pattern to avoid quoting issues.
# Patch both the /app/litellm/ source and the venv site-packages copy.
for f in \
  /app/litellm/proxy/health_check.py \
  /app/.venv/lib/python3.13/site-packages/litellm/proxy/health_check.py; do
  sed -i "s/Hey how.s it going/What's 1 + 1/" "$f" 2>/dev/null
done

exec /app/docker/prod_entrypoint.sh "$@"
