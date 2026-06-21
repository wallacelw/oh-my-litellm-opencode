---
name: oh-my-litellm-opencode
description: Deploy LiteLLM proxy (Docker Compose: litellm + postgres + prometheus + grafana) routing through Huawei ModelArts MaaS with multi-key load balancing, then bootstrap opencode + oh-my-opencode-slim with virtual key, dual providers, and 4 presets. TRIGGER when the task involves: LiteLLM proxy deployment, Huawei MaaS model routing, opencode + MaaS setup, full-stack AI coding bootstrap, oh-my-litellm-opencode, virtual key management, Prometheus/Grafana observability, custom_callbacks.py metrics, multi-key load balancing, docker compose with this stack, or any reference to LITELLM_MASTER_KEY, HUAWEI_MAAS_API_KEY.
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
- **LiteLLM baseURL: `http://0.0.0.0:4000`** (no `/v1` — SDK adds it; scripts use `127.0.0.1:4000`).
- **Disable `explore` and `general` agents.** Enable LSP. Use virtual keys (not master key) for opencode.
- **`jq --arg` for JSON substitution** — never `sed`.
- **Same-host only.**

## Architecture

```
Client → LiteLLM (:4000) → Huawei MaaS (ap-southeast-1)
               │               │
               │          ┌────┴────┐
               │          │ N API   │  (N = HUAWEI_MAAS_API_KEY_COUNT)
               │          │ keys    │  LiteLLM load-balances N deployments
               │          └────────┘
               ├── PostgreSQL (:5432)  — keys, usage, spend
               ├── Prometheus (:9090)  — /metrics scrape every 15s
               └── Grafana   (:3000)  — pre-built dashboard
```

Startup: PostgreSQL → LiteLLM → Prometheus → Grafana (all healthcheck-gated).

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
| `--auto` | Auto-generate | From env var | AI agent, non-interactive |

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

Fallback via model arrays in v2: `"model": ["primary", "fallback"]`.

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
| litellm | `ghcr.io/berriai/litellm:v1.83.14-stable.patch.3` | 4000 | 2g RAM, 2 CPU |
| db | `postgres:16-alpine` | (5432) | 512m RAM, 1 CPU |
| prometheus | `prom/prometheus:v3.3.1` | 9090 | 512m RAM, 1 CPU |
| grafana | `grafana/grafana:11.5.2` | 3000 | 256m RAM, 0.5 CPU |

## Metrics

**Built-in** (on `/metrics`): `litellm_proxy_total_requests_metric`, `litellm_request_total_latency_metric`, `litellm_spend_metric`, `litellm_input_tokens_metric`, `litellm_output_tokens_metric`, `litellm_deployment_state`.

**Custom** (`custom_callbacks.py`): `litellm_custom_ttft_seconds` (streaming), `litellm_custom_tpot_seconds` (always), `litellm_custom_itl_seconds` (streaming). Labeled: `model`, `model_group`, `api_provider`.

**PromQL examples:**
```promql
rate(litellm_proxy_total_requests_metric[5m]) * 60
histogram_quantile(0.99, rate(litellm_request_total_latency_metric_bucket[5m]))
rate(litellm_spend_metric[1d])
histogram_quantile(0.95, rate(litellm_custom_ttft_seconds_bucket[5m]))
```

## Operations

| Service | URL | Auth |
|---|---|---|
| LiteLLM API | `http://localhost:4000` | `Bearer <key>` |
| LiteLLM Admin UI | `http://localhost:4000/ui` | Master key |
| Prometheus | `http://localhost:9090` | None |
| Grafana | `http://localhost:3000` | admin / `GRAFANA_PASSWORD` |

**Backup:** `docker compose exec db pg_dump -U llmproxy litellm > backup.sql`
**Reset:** `docker compose down -v && docker compose up -d`
**Logs:** `docker compose logs litellm --tail 50`

## Repair Playbook

1. `docker compose ps` + `docker compose logs litellm --tail 50`
2. Verify `.env` has real MaaS key (not placeholder)
3. Check DB: `docker compose exec db pg_isready -d litellm -U llmproxy`
4. Check health: `curl -s http://localhost:4000/health -H "Authorization: Bearer $LITELLM_MASTER_KEY"`
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
| Port conflict | Check `ss -tlnp | grep -E ':4000|:9090|:3000'` |

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
| `init_env.sh --auto` non-interactive | Reads HUAWEI_MAAS_API_KEY from env, auto-generates rest, never prompts |
| opencode latest | `curl -fsSL https://opencode.ai/install \| bash` (no pinning — always latest) |
| LiteLLM image pinned | `v1.83.14-stable.patch.3` (no `latest`) |
| Timeouts consistent | `request_timeout: 600`, `stream_timeout: 60` |
| Resource limits | All 4 services have memory + CPU limits |
| Port conflicts detected | `bootstrap.sh` checks 4000/9090/3000 |
| `mint-virtual-key.sh` resilient | 3 retries with backoff; `--max-time 30` |
| Config substitution safe | `jq --arg` only, never `sed` |

## Sanitization Rules

- Never write real secrets into committed files. Use `.env` (gitignored, `0600`).
- Mask keys as `<prefix>...<suffix> (len=N)`.
- Use `jq --arg` for substitution, never `sed`.

## Verification Exit Criteria

- [ ] `.env` exists with all required variables (no placeholders), `0600` permissions
- [ ] `litellm_config.yaml` generated with `5 × N` deployments
- [ ] All 4 Docker services healthy
- [ ] LiteLLM liveness 200, `unhealthy_count: 0`
- [ ] Chat completion + streaming succeed
- [ ] Prometheus target `up`, Grafana 200
- [ ] Virtual key minting succeeds
- [ ] opencode.jsonc: both providers, valid virtual key, 5 models each, chmod 600
- [ ] oh-my-opencode-slim.json: 4 presets, default LiteLLM-Huawei-MaaS, council configured
- [ ] No real secrets in `git diff`
