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
- **Desktop companion** — floating status window showing live agent activity

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

### Humans

**Prerequisites:** bun, jq, Docker + Compose V2, git, python3. Install Docker from https://docs.docker.com/get-docker/ if missing.

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/bootstrap.sh          # prompts for MaaS key + extra keys
./scripts/validate.sh           # verify everything works
opencode
```

### AI agents

See **[For AI Agents](#for-ai-agents)** below for the exact step-by-step flow.

### Step-by-step (manual)

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

Read **[SKILL.md](https://github.com/wallacelw/oh-my-litellm-opencode/blob/main/SKILL.md)** — it contains the exact 12-step installation flow you should follow, including:

1. Ask user for main MaaS key
2. Validate the key before proceeding
3. Ask for additional keys for load balancing
4. Check prerequisites and install missing ones
5. Check Docker daemon is running
6. Check for existing installation
7. Check port availability
8. Install LiteLLM and related services
9. Wait for services to be healthy
10. Install opencode + oh-my-opencode-slim + companion
11. Validate
12. Send summary report with key rotation instructions

SKILL.md also contains core rules, presets, models, observability, upgrade paths, repair playbook, and determinism guarantees.
