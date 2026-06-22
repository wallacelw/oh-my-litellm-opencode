---
name: oh-my-litellm-opencode
description: Deploy LiteLLM proxy (Docker Compose: litellm + postgres + openlit + clickhouse) routing through Huawei ModelArts MaaS with multi-key load balancing, then bootstrap opencode + oh-my-opencode-slim with virtual key, dual providers, and 4 presets. TRIGGER when the task involves: LiteLLM proxy deployment, Huawei MaaS model routing, opencode + MaaS setup, full-stack AI coding bootstrap, oh-my-litellm-opencode, virtual key management, OpenLit observability, OTel/OTLP telemetry, multi-key load balancing, docker compose with this stack, or any reference to LITELLM_MASTER_KEY, HUAWEI_MAAS_API_KEY.
---

# oh-my-litellm-opencode

Deploy LiteLLM proxy → bootstrap opencode + oh-my-opencode-slim → mint virtual key → configure. Idempotent — safe to re-run.

## When to Use

| Situation | Route |
|---|---|
| Deploy full stack from scratch | `./scripts/bootstrap.sh` |
| LiteLLM already running | `./scripts/bootstrap.sh` (auto-detects) |
| Add/modify a model | Edit template → `generate_config.sh` → `docker compose restart litellm` |
| Troubleshoot | See **Repair Playbook** |
| Validate | `./scripts/validate.sh` |
| Switch presets | `/preset LiteLLM-Huawei-MaaS-Lite` |

**When NOT to use:** Direct MaaS calls without proxy, non-Huawei providers, multi-host/K8s.

## Required Inputs

- **Huawei MaaS API key** — from [ModelArts console](https://console.huaweicloud.com/modelarts/). Mandatory.
- **Additional MaaS API keys** (optional) — for load balancing (multiplies effective RPM/TPM).
- **MaaS region** — `ap-southeast-1` only. Do not swap regions.
- **Model IDs** — verify in MaaS console, do not guess (case-sensitive).
- **LITELLM_SALT_KEY** — immutable after first virtual key.

All collected by `./scripts/init_env.sh` (interactive or `--auto`).

## Prerequisites

bun, jq, Docker + Compose V2, git, python3, `HUAWEI_MAAS_API_KEY` env var.

## Core Rules

- **Never commit `.env` or real keys.** Secrets in `.env` (gitignored, `0600`).
- **Never change `LITELLM_SALT_KEY` after virtual keys exist.** Recovery = `docker compose down -v` + fresh start.
- **Model names case-sensitive.** Must match MaaS console.
- **MaaS region-locked** to `ap-southeast-1`.
- **Config is generated** by `scripts/generate_config.sh`. Never edit `litellm_config.yaml` directly.
- **Config read-only at startup.** Changes require `docker compose restart litellm`.
- **Non-zero pricing required** on every model for budget enforcement.
- **Master key admin-only.** Mint virtual keys per team/service.
- **Proxy is sole egress** for MaaS traffic (centralized budgets/rate limits/audit).
- **LiteLLM provider uses `@ai-sdk/openai-compatible`** (not `openai`).
- **Model keys: `openai/<model>`** in LiteLLM provider. **Presets: `LiteLLM/openai/<model>`** (3-part).
- **LiteLLM baseURL: `http://127.0.0.1:4000`** (no `/v1` — SDK adds it).
- **Disable `explore` and `general` agents.** Enable LSP. Use virtual keys (not master key) for opencode.
- **`jq --arg` for JSON substitution** — never `sed`.
- **Same-host only.**
- **Mask secrets** as `<prefix>...<suffix> (len=N)` in logs.

## Architecture

```
Client → LiteLLM (:4000) → Huawei MaaS (ap-southeast-1)
                 │               │
                 │          ┌────┴────┐
                 │          │ N API   │  (N = HUAWEI_MAAS_API_KEY_COUNT)
                 │          │ keys    │  LiteLLM load-balances N deployments
                 │          └────────┘
                 ├── PostgreSQL (:5432)  — keys, usage, spend
                 └── OpenLit (:3000)    — LLM observability (traces + metrics + dashboards)
                       ↑ OTLP (:4317/:4318) — from LiteLLM "otel" callback
                       └── ClickHouse (:8123/:9000)    — 30-day storage, SQL analytics
```

Startup: PostgreSQL + ClickHouse (parallel) → LiteLLM + OpenLit (parallel, healthcheck-gated).

## Deployment Workflow

**For AI agents (non-interactive):**
```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
export HUAWEI_MAAS_API_KEY="<your-key>"
./scripts/bootstrap.sh --maas-key="$HUAWEI_MAAS_API_KEY"
```

That's it. `bootstrap.sh --maas-key=KEY` is fully non-interactive — it uses `init_env.sh --auto` internally, auto-generates all secrets, starts Docker, mints a virtual key, writes configs, and validates.

**For humans (interactive):**
```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/bootstrap.sh          # prompts for MaaS key + any missing values
```

**Step-by-step (if not using bootstrap.sh):**
```bash
./scripts/init_env.sh --auto    # agent mode: reads HUAWEI_MAAS_API_KEY from env
./scripts/generate_config.sh
docker compose up -d
./scripts/install.sh            # reads LITELLM_MASTER_KEY from .env
./scripts/validate.sh
```

### init_env.sh modes

| Mode | Secrets | MaaS keys | Use case |
|------|---------|-----------|----------|
| interactive | Prompt each | Prompt each | Human, first-time |
| `--auto` | Auto-generate, preserve on re-run | From env var | AI agent, non-interactive |
| `--auto --force` | Regenerate all | From env var | Key rotation after security incident |

### Master Key Resolution (bootstrap.sh)

Priority: env var → `.master-key` file → `.env` file → interactive prompt.

## Multi-Key Load Balancing

With N MaaS API keys, each model has N deployments. LiteLLM load-balances across them. Effective RPM/TPM = per-key × N.

| Variable | Set by | Description |
|---|---|---|
| `HUAWEI_MAAS_API_KEY` | Manual / init_env.sh | Main key (mandatory) |
| `HUAWEI_MAAS_API_KEY_COUNT` | init_env.sh | Total keys (1 + extra) |
| `HUAWEI_MAAS_API_KEY_N` | init_env.sh | Indexed keys (_0, _1, ...) |

**Add a key:** Add `HUAWEI_MAAS_API_KEY_N=<key>` to `.env`, increment COUNT, `generate_config.sh`, `docker compose restart litellm`.

**Change routing:** `./scripts/generate_config.sh --routing-strategy=least-busy && docker compose restart litellm`

Strategies: `simple-shuffle` (default), `least-busy`, `latency-based-routing`, `usage-based-routing`, `cost-based-routing`.

## opencode Bootstrap

Handled by `bootstrap.sh` or `install.sh`:

1. **Install opencode** — `curl -fsSL https://opencode.ai/install | bash` (latest stable)
2. **Install plugin** — `bunx oh-my-opencode-slim@2.0.4 install`
3. **Mint virtual key** — reuse existing if valid, else mint unlimited key via LiteLLM
4. **Write opencode.jsonc** — jq substitution on template:
   ```bash
   jq --arg vk "$VIRTUAL_KEY" --arg mk "$MAAS_KEY" \
     '.provider.LiteLLM.options.apiKey = $vk |
      .provider["Huawei-MaaS"].options.apiKey = $mk' \
     assets/config/opencode/opencode.jsonc.example > ~/.config/opencode/opencode.jsonc
   ```
5. **Write oh-my-opencode-slim.json** — copy template to `~/.config/opencode/`
6. **Validate** — `scripts/validate.sh`

## Presets

| Preset | Models | Route |
|--------|--------|-------|
| **LiteLLM-Huawei-MaaS** (default) | All 5 | LiteLLM proxy → MaaS |
| **LiteLLM-Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | LiteLLM proxy → MaaS |
| **Huawei-MaaS** | All 5 | Direct to MaaS |
| **Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | Direct to MaaS |

### Agent Assignments (LiteLLM-Huawei-MaaS)

| Agent | Model | Variant | Fallback |
|-------|-------|---------|----------|
| orchestrator | glm-5.1 | high | — |
| oracle | deepseek-v4-pro | max | glm-5.1 |
| council | deepseek-v4-pro | high | glm-5.1 |
| librarian | deepseek-v3.2 | low | — |
| explorer | deepseek-v4-flash | low | deepseek-v3.2 |
| designer | glm-5 | medium | — |
| fixer | deepseek-v4-flash | high | glm-5 |

Fallback via model arrays (oh-my-opencode-slim v2 format): `"model": ["primary", "fallback"]`.

Council: single `councillor` per preset (deepseek-v4-pro/high).

## Models

| Name | in / out | RPM | TPM | Cost (in/out per token) |
|---|---|---|---|---|
| `glm-5.1` | 192K / 128K | 30 | 500K | $1.078 / $3.774 × 10⁻⁶ |
| `glm-5` | 192K / 64K | 30 | 500K | $0.809 / $2.965 × 10⁻⁶ |
| `deepseek-v4-pro` | 1M / 128K | 3 | 30K | $1.617 / $3.235 × 10⁻⁶ |
| `deepseek-v4-flash` | 1M / 128K | 3 | 30K | $0.135 / $0.270 × 10⁻⁶ |
| `deepseek-v3.2` | 128K / 32K | 700 | 500K | $0.270 / $0.404 × 10⁻⁶ |

### Adding a new model

1. Find name/rate/price in [MaaS console](https://console.huaweicloud.com/modelarts/)
2. Add entry to `litellm_config.yaml.template` (match MaaS name exactly)
3. Set non-zero `input_cost_per_token` / `output_cost_per_token` (per-token, not per-1K)
4. `./scripts/generate_config.sh && docker compose restart litellm`

## Proxy Settings

| Setting | Value | Meaning |
|---|---|---|
| `request_timeout` | 600 | Full request: 10 min |
| `stream_timeout` | 60 | TTFT: 60s |
| `routing_strategy` | `simple-shuffle` | Random across healthy deployments |
| `cooldown_time` | 30 | Seconds to cool down failed deployment |
| `allowed_fails` | 3 | Failures before cooldown |

## Docker Compose

| Service | Image | Port | Resources |
|---|---|---|---|
| litellm | `ghcr.io/berriai/litellm:v1.89.3` | 4000 | 2g RAM, 2 CPU |
| db | `postgres:16-alpine` | (5432) | 512m RAM, 1 CPU |
| clickhouse | `clickhouse/clickhouse-server:24.4.1` | 8123, 9000 | 512m RAM, 1 CPU |
| openlit | `ghcr.io/openlit/openlit:1.22.0` | 3000, 4317, 4318 | 512m RAM, 1 CPU |

## Metrics

**Telemetry pipeline:** LiteLLM → OpenLit (OTLP) → ClickHouse

**OTel GenAI metrics** (via `"otel"` callback):
- `gen_ai.client.operation.duration` — end-to-end request latency
- `gen_ai.client.token.usage` — input/output token counts
- `gen_ai.client.token.cost` — per-request cost with provider pricing
- `gen_ai.server.time_to_first_token` — TTFT (streaming)
- `gen_ai.client.operation.time_per_output_chunk` — TPOT

**Distributed traces:** Every request traced end-to-end (opencode → LiteLLM → MaaS). Click any trace in OpenLit UI to inspect timing, model selection, retries, and errors.

**OpenLit dashboards** (pre-built):
- Cost per model, per day, per key
- Token usage breakdown (input/output/cache)
- Latency comparison across models
- Error rates and failure drilldown
- Request-level trace inspection

**ClickHouse SQL** for custom analytics (30-day retention):
```sql
SELECT model, sum(cost) FROM otel_traces WHERE timestamp > now() - INTERVAL 1 DAY GROUP BY model
```

## Operations

| Service | URL | Auth |
|---|---|---|
| LiteLLM API | `http://127.0.0.1:4000` | `Bearer <key>` |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key |
| OpenLit UI | `http://127.0.0.1:3000` | None (local) |
| ClickHouse | `http://127.0.0.1:8123` | `default / OPENLIT_DB_PASSWORD` |

**Backup:** `docker compose exec db pg_dump -U llmproxy litellm > backup.sql`
**Reset:** `docker compose down -v && docker compose up -d`
**Logs:** `docker compose logs litellm --tail 50`
**Traces:** `docker compose logs openlit --tail 50`

## Upgrade Path

### Upgrade LiteLLM

1. Check [releases](https://github.com/BerriAI/litellm/releases) for breaking changes
2. Edit `docker-compose.yml`: change `ghcr.io/berriai/litellm:v1.89.3` → new version
3. `docker compose pull litellm && docker compose up -d litellm`
4. `./scripts/validate.sh --litellm-only`

### Upgrade OpenLit

1. Check [releases](https://github.com/openlit/openlit/releases) for breaking changes
2. Edit `docker-compose.yml`: change `ghcr.io/openlit/openlit:1.22.0` → new version
3. `docker compose pull openlit && docker compose up -d openlit`
4. Verify OpenLit UI at `http://127.0.0.1:3000`

### Upgrade ClickHouse

1. Check [releases](https://github.com/ClickHouse/ClickHouse/releases) for backward compatibility
2. Edit `docker-compose.yml`: change `clickhouse/clickhouse-server:24.4.1` → new version
3. `docker compose pull clickhouse && docker compose up -d clickhouse`
4. Verify: `curl http://127.0.0.1:8123/ping`

### Upgrade oh-my-opencode-slim

1. Check [releases](https://github.com/nicepkg/oh-my-opencode-slim/releases) for config format changes
2. Edit `scripts/install.sh`: change `SLIM_VERSION="2.0.4"` → new version
3. Edit `assets/config/opencode/oh-my-opencode-slim.json.example`: update `$schema` URL
4. `bunx oh-my-opencode-slim@<new-version> install`
5. `./scripts/install.sh` (re-writes config with diff-before-write)

### Upgrade opencode

opencode is always installed via `curl -fsSL https://opencode.ai/install | bash` (latest). To force upgrade:
```bash
curl -fsSL https://opencode.ai/install | bash
```

## Repair Playbook

1. `docker compose ps` + `docker compose logs litellm --tail 50`
2. Verify `.env` has real MaaS key (not placeholder)
3. Check DB: `docker compose exec db pg_isready -d litellm -U llmproxy`
4. Check health: `curl -s http://127.0.0.1:4000/health -H "Authorization: Bearer $LITELLM_MASTER_KEY"`
5. Fix issue (see table below)
6. `docker compose restart litellm` if config changed
7. `scripts/validate.sh`

### Common failure modes

| Symptom | Fix |
|---|---|
| `litellm` keeps restarting | Check `docker compose logs db`, verify `DB_PASSWORD` |
| 401 | Verify `Authorization: Bearer sk-...` header |
| 404 model not found | Model name case-sensitive, must match MaaS console |
| `LITELLM_SALT_KEY` error | Use original salt; if lost, `docker compose down -v` |
| MaaS 403 | Verify key in console; region must be `ap-southeast-1` |
| `unhealthy_count > 0` | Check MaaS key, model ID, region |
| Budget not consumed | Set non-zero `input_cost_per_token` / `output_cost_per_token` |
| Virtual key 403 | Check key with `/key/info` |
| Plugin not loaded | Re-run `bunx oh-my-opencode-slim@2.0.4 install` |
| Fallback not triggering | Set `fallback.enabled: true`, use model arrays |
| Port conflict | Check `ss -tlnp | grep -E ':4000|:4317|:4318|:8123|:9000|:3000'` |
| OpenLit not receiving data | Check `docker compose logs openlit`, verify OTEL_EXPORTER_OTLP_ENDPOINT |
| ClickHouse down | Check `curl http://127.0.0.1:8123/ping` |

### Bootstrap Rollback

| Failed at | Rollback |
|---|---|
| init_env.sh ran | `rm .env .master-key` |
| docker compose up ran | `docker compose down; rm .env` |
| Plugin installed | `rm ~/.config/opencode/oh-my-opencode-slim.json*` |
| opencode.jsonc written | `rm ~/.config/opencode/opencode.jsonc*` |

**Full reset:** `docker compose down -v; rm -f .env .master-key; rm -f ~/.config/opencode/opencode.jsonc* ~/.config/opencode/oh-my-opencode-slim.json*`

### Determinism Guarantees

| Property | Mechanism |
|---|---|
| `init_env.sh --auto` non-interactive | Preserves all secrets on re-run (MASTER_KEY, SALT_KEY, DB_PASSWORD, OPENLIT_DB_PASSWORD) — true no-op |
| opencode latest | `curl -fsSL https://opencode.ai/install \| bash` (no pinning — always latest) |
| docker compose up -d | Idempotent — always run, no-op if services already up |
| mint-virtual-key.sh | Reuses existing key by alias; mints only if missing or invalid |
| install.sh configs | Diff-before-write — skip if unchanged |
| LiteLLM image pinned | `v1.89.3` (no `latest`) |
| OpenLit image pinned | `1.22.0` (no `latest`) |
| ClickHouse image pinned | `24.4.1` (no `latest`) |
| Timeouts consistent | `request_timeout: 600`, `stream_timeout: 60` |
| Resource limits | All 4 services have memory + CPU limits |
| Port conflicts detected | `bootstrap.sh` checks 4000/4317/4318/8123/9000/3000 |
| `mint-virtual-key.sh` resilient | 3 retries with backoff; `--max-time 30` |
| Config substitution safe | `jq --arg` only, never `sed` |

## Verification Exit Criteria

- [ ] `.env` exists with all required variables (no placeholders), `0600` permissions
- [ ] `litellm_config.yaml` generated with `5 × N` deployments
- [ ] All 4 Docker services healthy
- [ ] LiteLLM liveness 200, `unhealthy_count: 0`
- [ ] Chat completion + streaming succeed
- [ ] OpenLit UI reachable, ClickHouse healthy
- [ ] OTLP endpoint responding on port 4318
- [ ] Virtual key minting succeeds
- [ ] opencode.jsonc: both providers, valid virtual key, 5 models each, chmod 600
- [ ] oh-my-opencode-slim.json: 4 presets, default LiteLLM-Huawei-MaaS, council configured
- [ ] No real secrets in `git diff`
