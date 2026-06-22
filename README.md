# oh-my-litellm-opencode

One command to deploy a production-ready AI coding stack: **LiteLLM proxy** routing through **Huawei ModelArts MaaS**, with **OpenLit + ClickHouse** observability, **opencode** bootstrap, virtual keys, 4 presets, and multi-key load balancing.

## What You Get

After running `bootstrap.sh`, you have:

- **5 production models** accessible through a single local proxy (`http://127.0.0.1:4000`)
- **Virtual key auth** — opencode uses a scoped key, not your master key
- **Multi-key load balancing** — add N MaaS keys, LiteLLM distributes traffic across all of them
- **Automatic fallback** — if a model fails, the next one in the array takes over
- **4 presets** — full/Lite variants via proxy or direct, switchable at runtime with `/preset`
- **Full observability** — OpenLit dashboards for cost, latency, errors, and per-request traces
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

**Startup order:** PostgreSQL + ClickHouse start in parallel → LiteLLM + OpenLit start in parallel (healthcheck-gated on their databases).

## Quick Start

### For AI agents (non-interactive)

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="your-key-from-modelarts-console"
./scripts/bootstrap.sh --maas-key="$HUAWEI_MAAS_API_KEY"
opencode
```

That's it. `bootstrap.sh --maas-key=KEY` is fully non-interactive — it auto-generates all secrets, starts Docker, mints a virtual key, writes configs, and validates.

### For humans (interactive)

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/bootstrap.sh          # prompts for MaaS key + any missing values
opencode
```

### Step-by-step (if not using bootstrap.sh)

```bash
./scripts/init_env.sh --auto    # generate .env with all secrets
./scripts/generate_config.sh    # build litellm_config.yaml from .env
docker compose up -d            # start all 4 services
./scripts/install.sh            # install opencode + plugin + mint key + write config
./scripts/validate.sh           # verify everything works
```

## Deployment Workflow

```
                    ┌──────────────────────────────────────────┐
                    │          bootstrap.sh                     │
                    │  (orchestrates all steps below)           │
                    └──────────────────────────────────────────┘
                                      │
                    ┌─────────────────┼─────────────────────┐
                    ▼                 ▼                     ▼
              Step 2: Check     Step 3: Deploy        Step 4: Install
              prerequisites     LiteLLM               opencode
                    │                 │                     │
                    │           ┌─────┼─────┐         ┌───┼───┐
                    │           ▼     ▼     ▼         ▼   ▼   ▼
                    │        init   docker  resolve   install  mint  write
                    │        _env  compose master    opencode  key   config
                    │           │     │     key      +plugin
                    │           │     │     │         │   │   │
                    │           ▼     ▼     ▼         ▼   ▼   ▼
                    │        .env   4 svcs  LITELLM_  .jsonc  .json
                    │        file  running MASTER_KEY  files   files
                    │                 │
                    └─────────────────┼─────────────────────┘
                                      ▼
                              Step 5: Validate
                              (55+ checks)
                                      │
                                      ▼
                              Step 6: Summary
                              (URLs, keys, next steps)
```

## Scripts

| Script | Purpose | Idempotent? |
|--------|---------|-------------|
| `bootstrap.sh` | End-to-end orchestrator: prereqs → deploy → install → validate | Yes — re-runs are no-ops |
| `init_env.sh` | Generate `.env` with secrets + MaaS keys | Yes (`--auto` preserves secrets) |
| `generate_config.sh` | Build `litellm_config.yaml` from `.env` | Yes — backs up existing |
| `install.sh` | Install opencode + plugin + mint key + write config | Yes — reuses existing key, diff-before-write |
| `mint-virtual-key.sh` | Mint a scoped virtual key (standalone) | Yes — reuses by alias |
| `validate.sh` | 55+ checks: Docker, health, config, inference, observability | Read-only |

### Key Script Details

**`init_env.sh` modes:**

| Mode | Secrets | MaaS keys | Use case |
|------|---------|-----------|----------|
| interactive (default) | Prompt each with generated defaults | Prompt each | Human, first-time |
| `--auto` | Auto-generate, **preserve on re-run** | From env var | AI agent, non-interactive |
| `--auto --force` | Regenerate all | From env var | Key rotation after security incident |

**`bootstrap.sh` arguments:**

| Argument | Effect |
|----------|--------|
| (none) | Interactive — prompts for MaaS key |
| `--maas-key=KEY` | Non-interactive — uses provided key |
| `--virtual-key=sk-...` | Skip key minting — use existing key |
| `--dry-run` | Preview all changes without making them |

**Master key resolution** (bootstrap.sh): env var → `.master-key` file → `.env` file → interactive prompt.

## Presets

| Preset | Models | Route | When to use |
|--------|--------|-------|-------------|
| **LiteLLM-Huawei-MaaS** (default) | All 5 | LiteLLM proxy → MaaS | Production — budget tracking, load balancing, observability |
| **LiteLLM-Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | LiteLLM proxy → MaaS | Cost-saving — skip expensive models |
| **Huawei-MaaS** | All 5 | Direct to MaaS | Debugging proxy issues — bypass LiteLLM |
| **Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | Direct to MaaS | Debugging + cost-saving |

Switch at runtime: `/preset LiteLLM-Huawei-MaaS-Lite`

### Agent Assignments (default preset)

| Agent | Primary model | Variant | Fallback model | Rationale |
|-------|---------------|---------|----------------|-----------|
| orchestrator | glm-5.1 | high | — | Strongest GLM, reliable orchestrator |
| oracle | deepseek-v4-pro | max | glm-5.1 | Best reasoning, fallback to GLM |
| council | deepseek-v4-pro | high | glm-5.1 | Multi-model consensus, same pair |
| librarian | deepseek-v3.2 | low | — | Cheap, fast, good enough for docs |
| explorer | deepseek-v4-flash | low | deepseek-v3.2 | Fast search, fallback to cheapest |
| designer | glm-5 | medium | — | Good design sense, mid-tier |
| fixer | deepseek-v4-flash | high | glm-5 | Fast implementation, fallback to GLM |

## Models

| Name | Context (in/out) | RPM | TPM | Cost (in/out per token) | Role |
|------|------------------|-----|-----|------------------------|------|
| `glm-5.1` | 192K / 128K | 30 | 500K | $1.078 / $3.774 × 10⁻⁶ | Primary orchestrator |
| `glm-5` | 192K / 64K | 30 | 500K | $0.809 / $2.965 × 10⁻⁶ | Designer |
| `deepseek-v4-pro` | 1M / 128K | 3 | 30K | $1.617 / $3.235 × 10⁻⁶ | Oracle, council |
| `deepseek-v4-flash` | 1M / 128K | 3 | 30K | $0.135 / $0.270 × 10⁻⁶ | Explorer, fixer |
| `deepseek-v3.2` | 128K / 32K | 700 | 500K | $0.270 / $0.404 × 10⁻⁶ | Librarian, smoke test |

### Adding a new model

1. Find name/rate/price in [MaaS console](https://console.huaweicloud.com/modelarts/)
2. Add entry to `generate_config.sh` `MODELS` array (match MaaS name exactly, case-sensitive)
3. Set non-zero `input_cost_per_token` / `output_cost_per_token` (per-token, not per-1K)
4. `./scripts/generate_config.sh && docker compose restart litellm`

## Multi-Key Load Balancing

With N MaaS API keys, each model gets N deployments. LiteLLM load-balances across them. **Effective RPM/TPM = per-key × N.**

```bash
# Add a second key in .env:
HUAWEI_MAAS_API_KEY_COUNT=2
HUAWEI_MAAS_API_KEY_1="your-second-key"

# Regenerate config and restart:
./scripts/generate_config.sh && docker compose restart litellm
```

**Routing strategies** (set via `generate_config.sh --routing-strategy=`):

| Strategy | Behavior | Best for |
|----------|----------|----------|
| `simple-shuffle` (default) | Random across healthy deployments | General use |
| `least-busy` | Fewest in-flight requests | Low-latency |
| `latency-based-routing` | Lowest average latency | Latency-sensitive |
| `usage-based-routing` | Least total usage | Even distribution |
| `cost-based-routing` | Lowest cost deployment | Cost optimization |

## Endpoints

| Service | URL | Auth | Purpose |
|---------|-----|------|---------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key (`sk-...`) | API proxy — all model calls go here |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key | Key management, spend tracking |
| OpenLit UI | `http://127.0.0.1:3000` | None (local) | Dashboards: cost, latency, traces |
| ClickHouse HTTP | `http://127.0.0.1:8123` | `default / OPENLIT_DB_PASSWORD` | SQL analytics over traces |

## Environment Variables

All stored in `.env` (gitignored, `0600` permissions). Generated by `init_env.sh`.

| Variable | Required | Description | Mutable? |
|----------|----------|-------------|----------|
| `LITELLM_MASTER_KEY` | Yes | Admin key, must start with `sk-` | ⚠️ Changing requires `docker compose up -d` |
| `LITELLM_SALT_KEY` | Yes | Encryption salt | **No** — changing invalidates all virtual keys |
| `DB_PASSWORD` | Yes | PostgreSQL `llmproxy` user | ⚠️ Changing requires DB recreation |
| `HUAWEI_MAAS_API_KEY` | Yes | Main MaaS API key (ap-southeast-1) | Yes — `bootstrap.sh --maas-key=NEW` updates it |
| `HUAWEI_MAAS_API_BASE` | Yes | MaaS endpoint URL | No — region-locked to ap-southeast-1 |
| `HUAWEI_MAAS_API_KEY_COUNT` | Auto | Number of MaaS keys (set by init_env.sh) | Yes — manually or via init_env.sh |
| `HUAWEI_MAAS_API_KEY_N` | Auto | Indexed keys (_0, _1, ...) | Yes — add more for load balancing |
| `OPENLIT_DB_PASSWORD` | Yes | ClickHouse database password | ⚠️ Changing requires `docker compose up -d` |

## Observability

**Telemetry pipeline:** LiteLLM → OTLP → OpenLit → ClickHouse

Every API call is automatically traced. You get:

- **OpenLit dashboards** (pre-built): cost per model/day/key, token usage, latency, error rates
- **Distributed traces**: opencode → LiteLLM → MaaS — click any trace to inspect timing, model selection, retries
- **OTel GenAI metrics**: `gen_ai.client.operation.duration`, `gen_ai.client.token.usage`, `gen_ai.client.token.cost`, `gen_ai.server.time_to_first_token`, `gen_ai.client.operation.time_per_output_chunk`
- **ClickHouse SQL** (30-day retention):
  ```sql
  SELECT model, sum(cost) FROM otel_traces WHERE timestamp > now() - INTERVAL 1 DAY GROUP BY model
  ```

## Stack Versions

| Component | Version | Why |
|-----------|---------|-----|
| LiteLLM | v1.89.3 (pinned) | Stable release with OTel callback support |
| OpenLit | 1.22.0 (pinned) | LLM observability with embedded OTel Collector |
| ClickHouse | 24.4.1 (pinned) | 30-day trace storage, SQL analytics |
| PostgreSQL | 16-alpine | LiteLLM key/spend DB |
| oh-my-opencode-slim | 2.0.4 (pinned) | Preset engine with model fallback arrays |
| opencode | latest (via curl) | AI coding tool — always installs latest |

## Operations

### Daily operations

```bash
docker compose logs litellm --tail 50   # LiteLLM logs
docker compose logs openlit --tail 50    # OpenLit traces
docker compose ps                        # Service status
```

### Backup & reset

```bash
docker compose exec db pg_dump -U llmproxy litellm > backup.sql    # Backup
docker compose down -v && docker compose up -d                       # Full reset (destroys data)
```

### Proxy settings

| Setting | Value | Meaning |
|---------|-------|---------|
| `request_timeout` | 600 | Full request: 10 min |
| `stream_timeout` | 60 | TTFT only: 60s |
| `routing_strategy` | `simple-shuffle` | Random across healthy deployments |
| `cooldown_time` | 30 | Seconds to cool down a failed deployment |
| `allowed_fails` | 3 | Failures before cooldown kicks in |
| `num_retries` | 3 | Retry across deployments on transient failure |

---

See [SKILL.md](./SKILL.md) for the full operational reference: core rules, upgrade paths, repair playbook, determinism guarantees, and verification exit criteria.
