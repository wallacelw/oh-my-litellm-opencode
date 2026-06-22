# oh-my-litellm-opencode

Docker Compose deployment of [LiteLLM](https://github.com/BerriAI/litellm) as an OpenAI-compatible API proxy routing through **Huawei ModelArts MaaS** (ap-southeast-1) with PostgreSQL, [OpenLit](https://github.com/openlit/openlit) + ClickHouse for LLM observability, plus opencode + oh-my-opencode-slim bootstrap with virtual keys, dual providers, and 4 presets.

See [SKILL.md](./SKILL.md) for the agent-facing workflow and exit criteria.

## Quick Start

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="your-key-from-huawei-console"
./scripts/bootstrap.sh
opencode
```

### Guided setup

```bash
./scripts/init_env.sh              # interactive
./scripts/generate_config.sh
docker compose up -d
./scripts/install.sh
```

### Agent install (non-interactive)

```bash
export HUAWEI_MAAS_API_KEY="your-key"
./scripts/bootstrap.sh --maas-key="$HUAWEI_MAAS_API_KEY"
```

## Presets

| Preset | Models | Route |
|--------|--------|-------|
| **LiteLLM-Huawei-MaaS** (default) | All 5 | LiteLLM proxy → MaaS |
| **LiteLLM-Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | LiteLLM proxy → MaaS |
| **Huawei-MaaS** | All 5 | Direct to MaaS |
| **Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | Direct to MaaS |

Switch: `/preset LiteLLM-Huawei-MaaS-Lite`

## Endpoints

| Service | URL | Auth |
|---------|-----|------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key (in opencode.jsonc) |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key (from `.master-key`) |
| OpenLit UI | `http://127.0.0.1:3000` | None (local) |
| ClickHouse | `http://127.0.0.1:8123` | `default / OPENLIT_DB_PASSWORD` |

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `LITELLM_MASTER_KEY` | Yes | Admin key, must start with `sk-` |
| `LITELLM_SALT_KEY` | Yes | Encryption salt — **immutable after first virtual key** |
| `DB_PASSWORD` | Yes | PostgreSQL `llmproxy` user password |
| `HUAWEI_MAAS_API_KEY` | Yes | Main MaaS API key (ap-southeast-1) |
| `HUAWEI_MAAS_API_BASE` | Yes | `https://api-ap-southeast-1.modelarts-maas.com/openai/v1` |
| `HUAWEI_MAAS_API_KEY_COUNT` | Auto | Number of MaaS keys (set by init_env.sh) |
| `OPENLIT_DB_PASSWORD` | Yes | ClickHouse database password |

## Stack Versions

| Component | Version |
|-----------|---------|
| LiteLLM | v1.89.3 (pinned) |
| OpenLit | 1.22.0 (pinned) |
| ClickHouse | 24.4.1 (pinned) |
| PostgreSQL | 16-alpine |
| oh-my-opencode-slim | 2.0.4 (pinned) |
| opencode | latest (via curl) |
