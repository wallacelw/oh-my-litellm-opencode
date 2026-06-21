# oh-my-litellm-opencode

Docker Compose deployment of [LiteLLM](https://github.com/BerriAI/litellm) as an OpenAI-compatible API proxy routing through **Huawei ModelArts MaaS** (ap-southeast-1) with PostgreSQL persistence, Prometheus metrics, Grafana dashboards, plus opencode + oh-my-opencode-slim bootstrap with virtual keys, dual providers, and 4 presets.

This repo ships **runtime stack files** for deterministic clone-and-run deployment. See [SKILL.md](./SKILL.md) for the agent-facing workflow, validation sequence, and exit criteria.

## Layout

```
README.md                                       this file
SKILL.md                                        agent-facing workflow and trigger rules
docker-compose.yml                              4-service Docker stack
assets/config/
  litellm/
    litellm_config.yaml.template                 model catalog template (tracked in git)
    litellm_config.yaml                          generated config (gitignored)
    custom_callbacks.py                          TTFT/TPOT/ITL Prometheus callback
    prometheus.yml                               15s scrape config
    .env.example                                 environment template
    grafana/
      └── provisioning/
          ├── datasources/prometheus.yml         auto-linked Prometheus datasource
          └── dashboards/
              ├── dashboards.yml                 file-based dashboard provider
              └── litellm_overview.json          pre-built overview dashboard
  opencode/
    opencode.jsonc.example                       opencode provider + model template
    oh-my-opencode-slim.json.example             presets, fallback, council template
scripts/
  bootstrap.sh                                   end-to-end orchestrator (idempotent)
  init_env.sh                                    interactive .env setup
  generate_config.sh                             generates litellm_config.yaml from .env
  install.sh                                     opencode + plugin + config installer
  mint-virtual-key.sh                            mint scoped key from LiteLLM
  validate.sh                                    unified validation (LiteLLM + opencode)
  validate_litellm.sh                            LiteLLM-specific E2E validation
```

## Skill Level

**Level 2 — Tested in production.**

## Applicable Scenario

Single-host AI gateway for centralized key management, spend tracking, rate limiting, and LLM traffic observability on Huawei Cloud MaaS — plus a complete AI coding environment from bare machine to working opencode with multi-agent orchestration, virtual key isolation, and model failover.

## Business Problem Addressed

| Problem | Impact |
|---|---|
| No centralized MaaS API key control | Developers bypass spend tracking and rate limiting |
| No LLM latency/throughput/cost visibility | Issues discovered late or not at all |
| No per-team budget enforcement | Single runaway client can consume entire MaaS quota |
| No audit trail | Who called which model, when, at what cost is untracked |
| No single command to bootstrap AI coding | Manual, error-prone setup |
| opencode defaults to OpenAI/Anthropic | No Huawei MaaS integration out of the box |
| No fallback when models are unavailable | Errors instead of graceful degradation |

## Required Knowledge

- Huawei Cloud ModelArts MaaS (ap-southeast-1)
- Docker Compose on a single Linux host
- Prometheus + Grafana observability fundamentals
- LiteLLM proxy configuration (model routing, callbacks, virtual keys)
- opencode CLI and oh-my-opencode-slim plugin configuration
- @ai-sdk/openai-compatible provider for custom endpoints

## Required Tools

| Tool | Version | Purpose |
|---|---|---|
| LiteLLM proxy | v1.83.14-stable.patch.3 | OpenAI-compatible API gateway |
| PostgreSQL | 16-alpine | Key storage, usage logs, spend records |
| Prometheus | v3.3.1 | LLM metrics scraping and TSDB |
| Grafana | 11.5.2 | Pre-built latency/spend/token dashboard |
| Huawei MaaS API | ap-southeast-1 | Upstream LLM inference |
| opencode | latest | AI coding CLI |
| oh-my-opencode-slim | v1.1.1 | Agent orchestration plugin |
| bun | latest | JavaScript runtime for opencode |
| jq | latest | JSON-safe config substitution |
| Docker | 20.10+ with Compose V2 | Container orchestration |

## Workflow

1. **Clone** — `git clone https://github.com/wallacelw/oh-my-litellm-opencode`
2. **Configure** — `./scripts/init_env.sh` (guided) or manual `.env` setup
3. **Deploy LiteLLM** — `docker compose up -d`. Healthcheck-gated chain: PostgreSQL → LiteLLM → Prometheus → Grafana.
4. **Install opencode** — `bun install -g opencode`
5. **Install plugin** — `bunx oh-my-opencode-slim@1.1.1 install`
6. **Mint virtual key** — `./scripts/mint-virtual-key.sh --no-budget`
7. **Configure** — opencode.jsonc + oh-my-opencode-slim.json with dual providers and 4 presets
8. **Validate** — `./scripts/validate.sh`
9. **Run** — `opencode`

Or use the single-command bootstrap: `./scripts/bootstrap.sh`

## Expected Outputs

- 4-service Docker Compose stack, all healthy
- OpenAI-compatible endpoint on `localhost:4000` with 5 configured models
- Pre-built Grafana dashboard with request rates, latency percentiles, spend, token rates, and custom TTFT/TPOT/ITL histograms
- Virtual key management API for multi-user budget enforcement
- opencode.jsonc with dual providers, all 5 models, chmod 600
- oh-my-opencode-slim.json with 4 presets, fallback chains, council councillors
- All 7 agent roles mapped to MaaS models

## Validation

See [SKILL.md](./SKILL.md) **Verification Exit Criteria** — combined checklist covering `.env` completeness, service health, per-model health, sync/streaming completions, metrics, Grafana, virtual key minting, opencode config, and preset validation.

## Reusable Assets

| Asset | Description |
|---|---|
| `docker-compose.yml` | 4-service stack with healthcheck chain, YAML anchor, named volumes |
| `assets/config/litellm/litellm_config.yaml.template` | Model catalog template with `openai/` prefix, MaaS endpoint, per-model tpm/rpm and pricing |
| `assets/config/litellm/litellm_config.yaml` | Generated config (gitignored), created by `generate_config.sh` |
| `assets/config/litellm/custom_callbacks.py` | TTFT/TPOT/ITL Prometheus histograms labeled by model/group/provider |
| `assets/config/litellm/prometheus.yml` | 15s scrape job targeting `litellm:4000` |
| `assets/config/litellm/grafana/provisioning/` | Auto-linked Prometheus datasource + pre-built dashboard |
| `assets/config/litellm/.env.example` | Template with all required and optional variables |
| `assets/config/opencode/opencode.jsonc.example` | Template for opencode provider + model config |
| `assets/config/opencode/oh-my-opencode-slim.json.example` | Template for presets, fallback, council config |
| `scripts/bootstrap.sh` | End-to-end idempotent orchestrator |
| `scripts/init_env.sh` | Interactive .env setup (manual, agent-guided, or CI) |
| `scripts/generate_config.sh` | Generates litellm_config.yaml from .env and template |
| `scripts/install.sh` | opencode + plugin + config installer |
| `scripts/mint-virtual-key.sh` | Mint scoped key from LiteLLM |
| `scripts/validate.sh` | Unified validation (LiteLLM + opencode) |
| `scripts/validate_litellm.sh` | LiteLLM-specific E2E validation |

## KPIs

| Metric | Target | Description |
|---|---|---|
| Proxy uptime | > 99.9% | Measured by `/health/liveliness` |
| P99 latency overhead | < 50ms | Proxy latency above direct MaaS call |
| Spend tracking accuracy | 100% | Every call logged with model, tokens, cost |
| Custom metric coverage | Streaming calls | TTFT and ITL for streaming; TPOT for all requests |
| Dashboard freshness | < 15s | Prometheus scrape interval |
| Budget enforcement | Zero bypass | All clients use virtual keys, never raw MaaS key |
| Deployment distribution | Even | Requests evenly distributed across N deployments per model |
| Bootstrap success | First run | Full stack deploys without manual intervention |
| Preset activation | First try | LiteLLM-Huawei-MaaS preset loads without errors |
| Model availability | 5/5 | All models reachable via LiteLLM proxy |

## Common Risks

| Risk | Impact | Mitigation |
|---|---|---|
| `LITELLM_SALT_KEY` changed after virtual keys exist | All keys unreadable | Never change salt after first key; if lost, `down -v` and start fresh |
| Model name typo in config | 404 at runtime | Model names are case-sensitive; verify in MaaS console |
| Zero pricing on a model | Budgets don't consume spend | Set non-zero `input_cost_per_token` and `output_cost_per_token` |
| MaaS API key expired or wrong region | 403 from upstream | Verify key in MaaS console; region must be `ap-southeast-1` |
| `.env` committed to git | All secrets leaked | `.env` is gitignored; never `git add .env` |
| Config change without restart | New settings not applied | `docker compose restart litellm` after edits |
| One MaaS API key expired (multi-key) | Partial degradation | Monitor cooldown events in Grafana; rotate expired key |
| opencode won't start | Wrong provider npm package | Use `@ai-sdk/openai-compatible`, not `openai` |
| Plugin not loaded | No presets available | Re-run: `bunx oh-my-opencode-slim@1.1.1 install` |
| Virtual key expired | 401 errors | Mint new key with `--no-budget` |

## Quick Start

### From scratch (fresh machine)

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="your-key-from-huawei-console"
# Optional: export HUAWEI_MAAS_EXTRA_API_KEYS="key2,key3"  # for multi-key load balancing
./scripts/bootstrap.sh
opencode
```

### Guided setup (recommended)

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/init_env.sh              # interactive — choose each secret, prompts for extra keys
./scripts/generate_config.sh       # generates litellm_config.yaml from .env
docker compose up -d
./scripts/validate_litellm.sh
# Then install opencode:
./scripts/install.sh
```

### LiteLLM already running on this machine

```bash
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="your-key"
./scripts/bootstrap.sh    # auto-detects LiteLLM on :4000, skips deployment
```

### Non-interactive (CI/CD)

```bash
./scripts/bootstrap.sh --maas-key="$MAAS_KEY" --maas-keys="key2,key3" --virtual-key="sk-..."
```

### Validate an existing setup

```bash
./scripts/validate.sh
```

## Presets

| Preset | Models | Route |
|--------|--------|-------|
| **LiteLLM-Huawei-MaaS** (default) | All 5 | LiteLLM proxy → MaaS |
| **LiteLLM-Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | LiteLLM proxy → MaaS |
| **Huawei-MaaS** | All 5 | Direct to MaaS |
| **Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | Direct to MaaS |

Switch at runtime:
```
/preset LiteLLM-Huawei-MaaS-Lite
/preset Huawei-MaaS
```

## Endpoints

| Service | URL | Auth |
|---------|-----|-------------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key (in opencode.jsonc) |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key (from `.master-key`) |
| Prometheus | `http://127.0.0.1:9090` | None |
| Grafana | `http://127.0.0.1:3000` | admin / (from `.env`) |

## Config Files

| File | Location | Permissions |
|------|----------|-------------|
| opencode.jsonc | `~/.config/opencode/opencode.jsonc` | 600 |
| oh-my-opencode-slim.json | `~/.config/opencode/oh-my-opencode-slim.json` | 600 |

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `LITELLM_MASTER_KEY` | Yes | — | Admin key. Must start with `sk-`. |
| `LITELLM_SALT_KEY` | Yes | — | Encryption salt for stored keys. **Immutable after first virtual key.** |
| `DB_PASSWORD` | Yes | — | PostgreSQL `llmproxy` user password. |
| `HUAWEI_MAAS_API_KEY` | Yes | — | Main MaaS API key from ModelArts console (CN-Hong Kong region). |
| `HUAWEI_MAAS_API_BASE` | Yes | — | `https://api-ap-southeast-1.modelarts-maas.com/openai/v1` |
| `HUAWEI_MAAS_API_KEY_COUNT` | Auto | 1 | Number of MaaS API keys (set by init_env.sh). |
| `HUAWEI_MAAS_API_KEY_N` | Auto | — | Indexed keys (0, 1, 2...). Set by init_env.sh. |
| `HUAWEI_MAAS_EXTRA_API_KEYS` | No | — | Comma-separated extra keys for CI mode. |
| `PROMETHEUS_RETENTION` | No | `15d` | TSDB retention. |
| `GRAFANA_PASSWORD` | No | `admin` | Admin password. |
