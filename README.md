# oh-my-litellm-opencode

One command to deploy a production-ready AI coding stack: **LiteLLM proxy** routing through **Huawei ModelArts MaaS**, with **OpenLit + ClickHouse** observability, **opencode** bootstrap, virtual keys, 4 presets, and multi-key load balancing.

## What You Get

- **5 production models** via a single local proxy (`http://127.0.0.1:4000`)
- **Virtual key auth** — opencode uses a scoped key, not your master key
- **Multi-key load balancing** — add N MaaS keys, effective RPM/TPM = per-key × N
- **Automatic fallback** — if a model fails, the next in the array takes over
- **4 presets** — full/Lite × proxy/direct, switchable at runtime with `/preset`
- **Full observability** — OpenLit dashboards with ITL, TTFT, TPOT, cost, traces
- **30-day analytics** — ClickHouse SQL over all traces and metrics

## Architecture

```
 opencode                    LiteLLM Proxy (:4000)              Huawei MaaS
 ─────────                   ─────────────────────              ─────────────
 orchestrator ─┐                                    ┌───────→ glm-5.1
 oracle ───────┤                                    ├───────→ glm-5
 council ──────┤    virtual key (sk-...)            ├───────→ deepseek-v4-pro
 librarian ────┤──────────────────────→  LiteLLM  ──┤───────→ deepseek-v4-flash
 explorer ─────┤    (scoped, unlimited)   │         └───────→ deepseek-v3.2
 designer ─────┤                        │
 fixer ────────┘                        │    N API keys (load-balanced)
                                        │    LiteLLM fans out each model
                                        │    across N deployments
                                        │
                              ┌─────────┴──────────┐
                              │                    │
                         PostgreSQL (:5432)    OpenLit (:3000)
                         keys · spend · usage   dashboards · traces
                                                │
                                           OTLP (:4317/:4318)
                                                │
                                          ClickHouse (:8123)
                                          30-day SQL analytics
```

Startup: PostgreSQL + ClickHouse (parallel) → LiteLLM + OpenLit (parallel, healthcheck-gated).

## Quick Start

### AI agents

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="your-key-from-modelarts-console"
./scripts/bootstrap.sh --maas-key="$HUAWEI_MAAS_API_KEY"
opencode
```

With `--maas-key=KEY`, the main key is pre-filled. You'll be prompted for extra keys for load balancing (press Enter to skip). All secrets are auto-generated.

### Humans

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/bootstrap.sh          # prompts for MaaS key + extra keys
opencode
```

### Step-by-step

```bash
./scripts/init_env.sh --auto    # generate .env with all secrets
./scripts/generate_config.sh    # build litellm_config.yaml from .env
docker compose up -d            # start all 4 services
./scripts/install.sh            # install opencode + plugin + mint key + write config
./scripts/validate.sh           # verify everything works
```

## Endpoints

| Service | URL | Auth |
|---------|-----|------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key (`sk-...`) |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key |
| OpenLit UI | `http://127.0.0.1:3000` | `user@openlit.io` / `openlituser` (change after first login) |
| ClickHouse | `http://127.0.0.1:8123` | `default / OPENLIT_DB_PASSWORD` |

## For AI Agents

### Install (copy-paste ready)

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="<your-maas-key>"
./scripts/bootstrap.sh --maas-key="$HUAWEI_MAAS_API_KEY"
opencode
```

That's it. `bootstrap.sh` is idempotent — safe to re-run.

### What you need before running

- **Huawei MaaS API key** — get it from [ModelArts console](https://console.huaweicloud.com/modelarts/) (region: `ap-southeast-1`)
- **Prerequisites on the host**: bun, jq, Docker + Compose V2, git, python3

### What bootstrap.sh does

1. Generates `.env` with all secrets (master key, salt, DB passwords) — preserves on re-run
2. Starts 4 Docker services: LiteLLM proxy, PostgreSQL, ClickHouse, OpenLit
3. Installs opencode + oh-my-opencode-slim plugin
4. Mints a virtual key scoped for opencode (reuses existing by alias)
5. Writes opencode.jsonc + oh-my-opencode-slim.json (4 presets, fallback enabled)
6. Validates everything (55+ checks)
7. Prints summary with URLs and next steps

### After install

- **opencode** is ready — just run `opencode`, it uses the proxy at `http://127.0.0.1:4000`
- **Presets**: switch at runtime with `/preset LiteLLM-Huawei-MaaS-Lite`
- **Observability**: OpenLit dashboard at `http://127.0.0.1:3000` (login: `user@openlit.io` / `openlituser`)
- **Add MaaS keys for load balancing**: add `HUAWEI_MAAS_API_KEY_N=<key>` to `.env`, increment `HUAWEI_MAAS_API_KEY_COUNT`, then `./scripts/generate_config.sh && docker compose restart litellm`
- **Validate**: `./scripts/validate.sh`
- **Full reset**: `docker compose down -v; rm -f .env .master-key`

### Core rules (must always hold)

- Never commit `.env` or real keys
- Never change `LITELLM_SALT_KEY` after virtual keys exist
- Model names are case-sensitive — must match MaaS console exactly
- Config is generated by `scripts/generate_config.sh` — never edit `litellm_config.yaml` directly
- Master key is admin-only — opencode uses virtual keys
- LiteLLM baseURL: `http://127.0.0.1:4000` (no `/v1`)

### Operational reference

Full details are in **[SKILL.md](https://github.com/wallacelw/oh-my-litellm-opencode/blob/main/SKILL.md)**: core rules, presets & agent assignments, models & costs, multi-key load balancing, observability setup, upgrade paths, repair playbook, determinism guarantees, and verification exit criteria.
