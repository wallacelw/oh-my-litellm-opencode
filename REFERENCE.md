# oh-my-coding-maas-gateway — Reference

Reference documentation for both humans and agents. For the install procedure and per-script details, see **[INSTALLATION.md](./INSTALLATION.md)**. For the deterministic install procedure,
see **[SKILL.md](./SKILL.md)**. For a human-friendly overview, see
**[README.md](./README.md)**.

---

## Overview

### Key Contract

**Environment variables (`.env`):**

| Env var | Set by | Read by | Format | Rotate risk |
|---------|--------|---------|--------|------------|
| `HUAWEI_MAAS_API_KEY` | User (env var or prompt) | `01_env.sh`, `03_opencode.sh` | Non-empty, no placeholders | Low — update `.env` + restart LiteLLM |
| `HUAWEI_MAAS_API_KEY_COUNT` | `01_env.sh` (from env vars or prompt) | `01_env.sh`, `02_litellm.sh` | Integer ≥ 1 | Low — update `.env` + regenerate config |
| `HUAWEI_MAAS_API_KEY_0` | `01_env.sh` (auto, = main key) | `01_env.sh`, `02_litellm.sh` | Non-empty | Low — auto-set from main key |
| `HUAWEI_MAAS_API_KEY_1..N` | User (env var or prompt) | `01_env.sh`, `02_litellm.sh` | Non-empty | Low — update `.env` + regenerate config |
| `LITELLM_MASTER_KEY` | `01_env.sh` (auto or custom) | `03/04/05` via `helpers/keys.sh` | Must start with `sk-` | **High** — invalidates all virtual keys (`--force` to regenerate) |
| `LITELLM_SALT_KEY` | `01_env.sh` (auto or custom) | LiteLLM container | Random string | **High** — invalidates all virtual keys (`--force` to regenerate) |
| `DB_PASSWORD` | `01_env.sh` (auto or custom) | docker-compose, postgres | Random string | **High** — breaks DB auth (`--force` to regenerate) |
| `GRAFANA_ADMIN_PASSWORD` | `01_env.sh` (auto or custom) | docker-compose, `06_validate.sh` | Random string | Low — changes dashboard login only |
| `PROMETHEUS_RETENTION` | `01_env.sh` (default `30d`) | docker-compose | Prometheus duration (`Nd`/`Nh`/`Nw`) | None — config value |
| `HUAWEI_MAAS_ANTHROPIC_API_BASE` | `01_env.sh` (default `https://api-ap-southeast-1.modelarts-maas.com/anthropic`) | `02_litellm.sh` | URL | None — config value |
| `HUAWEI_MAAS_API_BASE` | `01_env.sh` (default `https://api-ap-southeast-1.modelarts-maas.com/openai/v1`) | `02_litellm.sh` | URL | None — config value |

**Virtual keys (stored in tool config files, not `.env`):**

| Key | Minted by | Stored in | Tied to |
|-----|-----------|-----------|---------|
| opencode virtual key | `03_opencode.sh` | `~/.config/opencode/opencode.json` (provider apiKey) | `LITELLM_MASTER_KEY` |
| Codex virtual key | `04_codex.sh` | `~/.codex/.env` as `LITELLM_CODEX_API_KEY` | `LITELLM_MASTER_KEY` |
| Claude Code virtual key | `05_claude_code.sh` | `~/.claude/settings.json` env block as `ANTHROPIC_API_KEY` | `LITELLM_MASTER_KEY` |

**Rules:**

- User/agent must NOT set `HUAWEI_MAAS_API_KEY_0` — `01_env.sh` sets it from the
  main key automatically.
- User/agent must export `HUAWEI_MAAS_API_KEY_COUNT` = 1 + number of extra keys.
- User/agent must export `HUAWEI_MAAS_API_KEY_1` through `HUAWEI_MAAS_API_KEY_N` for
  extra keys only.

### Architecture

```
  Tools               LiteLLM (:4000)                  Huawei MaaS
  ─────               ───────────────                  ────────────

  opencode ──→ /v1/chat/completions ──→ openai/ provider ──→ /openai/v1/chat/completions
  Codex CLI ──→ /v1/responses ────────→ openai/ provider ──→ /openai/v1/chat/completions
  Claude Code ─→ /v1/messages ────────→ anthropic/ provider ─→ /anthropic/v1/messages

  opencode: 7 agents (1 disabled), 4 presets (LiteLLM-Huawei-MaaS-Full default)
  Codex CLI: Responses API bridged to Chat Completions by LiteLLM
  Claude Code: Anthropic Messages API forwarded to MaaS Anthropic endpoint

  Each tool: separate virtual key (sk-...) · unlimited budget · all 6 models
  LiteLLM: load-balances across N MaaS API keys · PostgreSQL (:5432)
  Models: glm-5.2 · glm-5.1 · glm-5 · deepseek-v4-pro · deepseek-v4-flash · deepseek-v3.2

  Observability: LiteLLM ──/metrics──→ Prometheus (:9090) ──→ Grafana (:3000)
```

### Endpoints

**LiteLLM Proxy (local):**

| Endpoint | URL | Auth |
|----------|-----|------|
| Proxy base | `http://127.0.0.1:4000` | Virtual key (`sk-...`) |
| Chat Completions | `http://127.0.0.1:4000/v1/chat/completions` | Virtual key |
| Responses API | `http://127.0.0.1:4000/v1/responses` | Virtual key |
| Anthropic Messages | `http://127.0.0.1:4000/v1/messages` | Virtual key |
| Admin UI | `http://127.0.0.1:4000/ui` | Master key |
| Liveness | `http://127.0.0.1:4000/health/liveliness` | None |
| Health | `http://127.0.0.1:4000/health` | Master key |
| Metrics | `http://127.0.0.1:4000/metrics` | None (Prometheus format) |

**Observability (local):**

| Service | URL | Auth |
|----------|-----|------|
| Prometheus | `http://127.0.0.1:9090` | None (bound to localhost) |
| Grafana | `http://127.0.0.1:3000` | Anonymous (Viewer role) |

**Tool connections (what each tool points to):**

| Tool | Endpoint | API Format | Auth source |
|------|----------|------------|-------------|
| opencode (default) | `http://127.0.0.1:4000` → `/v1/chat/completions` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` (provider apiKey) |
| opencode (direct preset) | `https://api-ap-southeast-1.modelarts-maas.com/openai/v1` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` (provider apiKey) |
| Codex CLI | `http://127.0.0.1:4000/v1` → `/v1/responses` | OpenAI Responses (bridged to Chat Completions by LiteLLM) | `~/.codex/.env` (`LITELLM_CODEX_API_KEY`) |
| Claude Code CLI | `http://127.0.0.1:4000` → `/v1/messages` | Anthropic Messages | `~/.claude/settings.json` (env.ANTHROPIC_API_KEY) |

**Huawei MaaS upstream (remote):**

| Endpoint | URL | Auth |
|----------|-----|------|
| MaaS OpenAI-compatible | `https://api-ap-southeast-1.modelarts-maas.com/openai/v1/chat/completions` | MaaS API key (`Authorization: Bearer`) |
| MaaS Anthropic-compatible | `https://api-ap-southeast-1.modelarts-maas.com/anthropic/v1/messages` | MaaS API key (`x-api-key` header) |

### Scripts

| # | Script | Purpose |
|---|--------|---------|
| — | `bootstrap.sh` | End-to-end orchestrator: selection → core prereqs → dispatch steps → summary. Use --tool=all\|litellm\|opencode\|codex\|claude (comma-separated for combos) |
| 01 | `01_env.sh` | Generate `.env` with secrets + MaaS keys; configure git hooks |
| 02 | `02_litellm.sh` | Generate `configs/litellm/config.yaml` from `.env` + deploy Docker Compose |
| 03 | `03_opencode.sh` | Install opencode + plugin + mint key + write config |
| 04 | `04_codex.sh` | Install Codex CLI + mint key + write config + model catalog |
| 05 | `05_claude_code.sh` | Install Claude Code CLI + mint key + write settings + disable VSCode ext |
| 06 | `06_validate.sh` | Validate all components (--litellm-only, --opencode-only, --codex-only, --claude-code-only for scoped checks; --skip-opencode, --skip-codex, --skip-claude-code for partial runs) |
| — | `helpers/prereqs.sh` | Shared prerequisite installation helpers (prereq_ensure_apt/bun/npm/docker) |
| — | `helpers/keys.sh` | Key resolution + virtual key minting (resolve_master_key, mint_or_reuse_key) |
| — | `helpers/common.sh` | Shared utilities (logging, prompts, run_filtered, source_env, retry_curl, strip_jsonc, mask_key) |
| — | `helpers/models.sh` | Model catalog — single source of truth (MODELS array, sourced by 02_litellm.sh + 06_validate.sh) |

### Models

| Name | Input/Output | RPM | Cost (in/out per token) |
|------|-------------|-----|------------------------|
| `glm-5.2` | 192K/128K | 100 | $1.400 / $4.400 × 10⁻⁶ |
| `glm-5.1` | 192K/128K | 30 | $1.078 / $3.774 × 10⁻⁶ |
| `glm-5` | 192K/64K | 30 | $0.809 / $2.965 × 10⁻⁶ |
| `deepseek-v4-pro` | 1M/128K | 3 | $1.617 / $3.235 × 10⁻⁶ |
| `deepseek-v4-flash` | 1M/128K | 3 | $0.135 / $0.270 × 10⁻⁶ |
| `deepseek-v3.2` | 128K/32K | 700 | $0.270 / $0.404 × 10⁻⁶ |

### Core Rules

- Never commit `.env` or real keys
- Never change `LITELLM_SALT_KEY` after virtual keys exist
- Model names are case-sensitive — must match MaaS console exactly
- Config is generated by `02_litellm.sh` — never edit `configs/litellm/config.yaml` directly
- Master key is admin-only — opencode, Codex CLI, and Claude Code CLI use separate virtual keys
- LiteLLM baseURL: `http://127.0.0.1:4000` (no `/v1`)
- MaaS region-locked to `ap-southeast-1`

---

## LiteLLM

`configs/litellm/config.yaml` is generated by `02_litellm.sh` from `.env`.
Never edit it directly — change `.env` and re-run `02_litellm.sh`.

### config.yaml Structure

```yaml
model_list:
  # ── OpenAI deployments (for opencode + Codex CLI) ──
  - model_name: glm-5.2                    # base name
    litellm_params:
      model: openai/glm-5.2                # provider prefix
      api_base: os.environ/HUAWEI_MAAS_API_BASE
      api_key: os.environ/HUAWEI_MAAS_API_KEY_0
      use_chat_completions_api: true       # bridge Responses → Chat Completions
      tpm: 198000
      rpm: 100
    model_info:
      max_tokens: 198000
      max_input_tokens: 192000
      max_output_tokens: 128000
      input_cost_per_token: 0.0000014
      output_cost_per_token: 0.0000044

  # ── Anthropic deployments (for Claude Code CLI) ──
  - model_name: claude-glm-5.2             # claude- prefix
    litellm_params:
      model: anthropic/glm-5.2             # provider prefix
      api_base: os.environ/HUAWEI_MAAS_ANTHROPIC_API_BASE
      api_key: os.environ/HUAWEI_MAAS_API_KEY_0
      tpm: 198000
      rpm: 100
    model_info:
      max_tokens: 198000
      max_input_tokens: 192000
      max_output_tokens: 128000
      input_cost_per_token: 0.0000014
      output_cost_per_token: 0.0000044

litellm_settings:
  num_retries: 3
  request_timeout: 600
  stream_timeout: 60
  callbacks: ["prometheus"]
  prometheus_initialize_budget_metrics: true
  require_auth_for_metrics_endpoint: false

router_settings:
  cooldown_time: 30                        # seconds to cool down a failed deployment
  allowed_fails: 3                         # failures before cooldown kicks in
```

### Provider Types

Two provider types, each pointing to a different Huawei MaaS endpoint:

| Provider | Prefix | MaaS Endpoint | Auth Header | Used by |
|----------|--------|---------------|-------------|---------|
| OpenAI | `openai/` | `/openai/v1/chat/completions` | `Authorization: Bearer` | opencode, Codex CLI |
| Anthropic | `anthropic/` | `/anthropic/v1/messages` | `x-api-key` | Claude Code CLI |

### Dual-Format Deployments

Each model has two deployments — one OpenAI, one Anthropic — so all three tools
can use the same underlying MaaS models:

| Type | `model_name` | Provider model | Example |
|------|------------|----------------|---------|
| OpenAI | `{model}` | `openai/{model}` | `glm-5.2` → `openai/glm-5.2` |
| Anthropic | `claude-{model}` | `anthropic/{model}` | `claude-glm-5.2` → `anthropic/glm-5.2` |

The `claude-` prefix on Anthropic `model_name` avoids routing conflicts.
LiteLLM routes by `model_name`, not by request format. Without the prefix,
a `/v1/messages` request could hit the OpenAI deployment, triggering a broken
Anthropic→OpenAI→Anthropic translation that drops content.

### OpenAI Bridge

`use_chat_completions_api: true` on OpenAI deployments tells LiteLLM to bridge
Responses API → Chat Completions. This lets Codex CLI use `/v1/responses`
(which LiteLLM converts to `/v1/chat/completions` before forwarding to MaaS).

### Load Balancing

N MaaS API keys → N deployments per model per format. LiteLLM uses
`simple-shuffle` routing (round-robin with retry across deployments).

Total deployments: 6 models × N keys × 2 formats = 12N.

### model_info

Each deployment includes metadata for budget tracking and LiteLLM UI:

| Field | Purpose |
|-------|---------|
| `max_tokens` | Total token limit |
| `max_input_tokens` | Input token limit |
| `max_output_tokens` | Output token limit |
| `input_cost_per_token` | Cost per input token (USD) |
| `output_cost_per_token` | Cost per output token (USD) |

### Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `num_retries` | 3 | Retry across deployments on failure |
| `request_timeout` | 600 | Full request timeout (10 min) |
| `stream_timeout` | 60 | TTFT timeout (60s) |
| `callbacks` | `["prometheus"]` | Enable Prometheus metrics export |
| `prometheus_initialize_budget_metrics` | true | Emit budget metrics for all keys |
| `require_auth_for_metrics_endpoint` | false | Allow unauthenticated `/metrics` |
| `router_settings.cooldown_time` | 30 | Seconds to cool down a failed deployment |
| `router_settings.allowed_fails` | 3 | Failures before cooldown kicks in |

### Virtual Keys

Three virtual keys, all minted via `helpers/keys.sh` and tied to
`LITELLM_MASTER_KEY`. Changing the master key invalidates all virtual keys.

| Alias | Minted by | Stored in | Budget | Scope |
|-------|-----------|-----------|--------|-------|
| `opencode` | `03_opencode.sh` | `~/.config/opencode/opencode.json` (provider apiKey) | Unlimited | All models |
| `codex` | `04_codex.sh` | `~/.codex/.env` (`LITELLM_CODEX_API_KEY`) | Unlimited | All models |
| `claude-code` | `05_claude_code.sh` | `~/.claude/settings.json` (env.ANTHROPIC_API_KEY) | Unlimited | All models |

Each installer checks its own config file for an existing valid key first
(tool-specific path), then calls `mint_or_reuse_key` from `helpers/keys.sh`
which does alias lookup via `/key/list` + `/key/info` and mints a new key only
if no valid key is found.

### Observability

LiteLLM exposes a `/metrics` endpoint (Prometheus format). Prometheus
scrapes it every 15s. Grafana visualizes the data with a pre-provisioned
dashboard.

| Service | Port | Purpose |
|---------|------|---------|
| Prometheus | 9090 | Metrics storage + querying |
| Grafana | 3000 | Dashboard visualization (anonymous, no login) |

Prometheus TSDB retention is configurable via `PROMETHEUS_RETENTION` in `.env`
(default: `30d`).

**Dashboard** (`configs/grafana/dashboards/main.json`) — 28 panels across 6
sections, default 1h time window, 30s refresh:

1. **At-a-glance** — Active Requests, RPS, RPM, Error %, TPS, TPM, Models Healthy, Spend (8 stat panels)
2. **Latency** — TTFT by model, TPOT by model, End-to-end latency, LLM API latency, Proxy overhead, Queue wait (6 timeseries)
3. **Errors & Health** — Errors by model, Error status codes (pie), Deployment state (3 panels)
4. **Throughput & Capacity** — Total/Successful/Failed Requests (window), RPM by model, TPM by model (5 panels)
5. **Tokens** — Input tokens, Output tokens, Reasoning tokens (3 timeseries)
6. **Cost** — Total cost, Cost per model, Spend rate (3 panels)

Variables: `$model` (filter by model), `$provider` (filter by openai/anthropic),
`$window` (rate window: 1m/5m/15m/1h, default 15m).



---

## opencode

**Connection:** opencode → `/v1/chat/completions` → `openai/` provider → `/openai/v1/chat/completions`

opencode connects to LiteLLM via the OpenAI Chat Completions API. The
`oh-my-opencode-slim` plugin (installed via `bunx`) configures 4 presets and
agent→model mappings.

### Config Files

| File | Purpose |
|------|---------|
| `~/.config/opencode/opencode.json` | Provider config (LiteLLM + Huawei-MaaS direct), API key |
| `~/.config/opencode/oh-my-opencode-slim.json` | Plugin config: presets, agents, council |

The `LiteLLM` provider uses `@ai-sdk/openai-compatible` with
`baseURL: http://127.0.0.1:4000`. Models use base names (e.g., `glm-5.2`)
without provider prefix — the preset name (`LiteLLM/` vs `Huawei-MaaS/`)
determines routing.

### Plugin: oh-my-opencode-slim

`oh-my-opencode-slim` (v2.0.5) installed via `bunx`. Provides:

- **4 presets** — control routing (proxy vs direct) and model selection
- **7 agents** (1 disabled) — orchestrator, oracle, council, librarian, explorer, designer, fixer (observer disabled)
- **Council** — 3 councillors running in parallel for consensus decisions
- **Fallback chains** — each agent has a primary model and optional fallback

### Presets

| Preset | Route | Models |
|--------|-------|--------|
| **LiteLLM-Huawei-MaaS-Full** (default) | Proxy → MaaS | All 6 |
| **LiteLLM-Huawei-MaaS-Core** | Proxy → MaaS | 4 (no v4-pro/v4-flash) |
| **Huawei-MaaS-Full** | Direct → MaaS | All 6 |
| **Huawei-MaaS-Core** | Direct → MaaS | 4 (no v4-pro/v4-flash) |

Switch at runtime: `/preset LiteLLM-Huawei-MaaS-Core`

### Agent → Model Mapping

`A → B` = fallback chain. `(variant)` = reasoning effort. Model names omit
the provider prefix (preset name indicates LiteLLM proxy vs direct MaaS).

| Agent | LiteLLM-Full | LiteLLM-Core | MaaS-Full | MaaS-Core |
|-------|-------------|-------------|-----------|-----------|
| orchestrator | `glm-5.2` (high) | `glm-5.2` (high) | `glm-5.2` (high) | `glm-5.2` (high) |
| oracle | `glm-5.2` → `deepseek-v4-pro` (max) | `glm-5.2` → `deepseek-v3.2` (high) | `glm-5.2` → `deepseek-v4-pro` (max) | `glm-5.2` → `deepseek-v3.2` (high) |
| council | `glm-5.2` → `deepseek-v4-pro` (high) | `glm-5.2` → `deepseek-v3.2` (high) | `glm-5.2` → `deepseek-v4-pro` (high) | `glm-5.2` → `deepseek-v3.2` (high) |
| librarian | `deepseek-v3.2` (low) | `deepseek-v3.2` (low) | `deepseek-v3.2` (low) | `deepseek-v3.2` (low) |
| explorer | `deepseek-v3.2` (low) | `deepseek-v3.2` (medium) | `deepseek-v3.2` (low) | `deepseek-v3.2` (medium) |
| designer | `glm-5.1` → `deepseek-v3.2` (medium) | `glm-5.1` → `deepseek-v3.2` (medium) | `glm-5.1` → `deepseek-v3.2` (medium) | `glm-5.1` → `deepseek-v3.2` (medium) |
| fixer | `glm-5` → `deepseek-v3.2` (high) | `glm-5` → `deepseek-v3.2` (high) | `glm-5` → `deepseek-v3.2` (high) | `glm-5` → `deepseek-v3.2` (high) |

### Council

3 councillors run in parallel, all using glm-5.2, each with a different focus:

| Councillor | Model | Focus |
|------------|-------|-------|
| **alpha** | glm-5.2 | Deep reasoning, logical correctness, subtle bugs/edge cases |
| **beta** | glm-5.2 | Architecture, maintainability, trade-offs, long-term implications |
| **gamma** | glm-5.2 | Practical implementation, cost-efficiency, verification steps |

### Prerequisites

- `bun` — for `bunx oh-my-opencode-slim install`
- `jq` — for config parsing

---

## Codex CLI

**Connection:** Codex CLI → `/v1/responses` → `openai/` provider (bridged to Chat Completions by LiteLLM) → `/openai/v1/chat/completions`

Codex CLI connects to LiteLLM via the OpenAI Responses API. LiteLLM bridges
this to Chat Completions using `use_chat_completions_api: true`, then forwards
to Huawei MaaS's OpenAI endpoint.

### Config Files

| File | Purpose |
|------|---------|
| `~/.codex/config.toml` | Model provider config, default model, feature flags |
| `~/.codex/model_catalog.json` | Model metadata (context window, max tokens, reasoning levels) |
| `~/.codex/.env` | API key (`LITELLM_CODEX_API_KEY=sk-...`), auto-loaded by Codex CLI |

### Custom Provider

Codex CLI uses a custom `litellm_proxy` model provider instead of the
built-in `openai` provider:

```toml
[model_providers.litellm_proxy]
name = "LiteLLM Proxy"
base_url = "http://127.0.0.1:4000/v1"
env_key = "LITELLM_CODEX_API_KEY"
wire_api = "responses"
```

Why a custom provider:
- Codex CLI rejects overriding the reserved `openai` provider name.
- The built-in `openai` provider defaults to `wire_api = "responses_websocket"`
  (WebSocket), which has a bug in LiteLLM v1.89.3 when bridging to Chat
  Completions. Setting `wire_api = "responses"` forces HTTP SSE instead.
- The `env_key` field lets Codex CLI read the API key from `~/.codex/.env`
  automatically (via dotenvy), no shell exports needed.

### Feature Flags

- `multi_agent = false` — disabled because it sends `type: "namespace"` tools
  that Huawei MaaS rejects (only `type: "function"` is accepted).

### Model Selection

Models use base names (e.g., `glm-5.2`). All 6 models are available. Switch
at runtime with `--model`:

```bash
codex --model deepseek-v4-pro    # deep reasoning
codex --model glm-5.2            # general purpose (default)
codex --model deepseek-v3.2      # fast
```

### Prerequisites

- `npm` — for `npm install -g @openai/codex`
- `jq` — for parsing LiteLLM API responses
- `bubblewrap` (`bwrap`) — Codex CLI requires it for sandboxing

---

## Claude Code CLI

**Connection:** Claude Code → `/v1/messages` → `anthropic/` provider → `/anthropic/v1/messages`

Claude Code CLI connects to LiteLLM via the Anthropic Messages API. LiteLLM
forwards directly to Huawei MaaS's Anthropic-compatible endpoint using the
`anthropic/` provider prefix — no format conversion needed.

### Config Files

| File | Purpose |
|------|---------|
| `~/.claude/settings.json` | Runtime config: env vars, model selection (chmod 600) |
| `~/.claude.json` | IDE integration settings: `autoInstallIdeExtension: false` |

Claude Code reads `settings.json` automatically on startup — no `source` or
`export` needed. Run with `--bare` flag to skip keychain/OAuth checks:

```bash
claude --bare
```

Or add an alias: `alias claude='claude --bare'`

### Environment Variables

Set in the `env` block of `~/.claude/settings.json`:

| Variable | Value | Purpose |
|----------|-------|---------|
| `ANTHROPIC_BASE_URL` | `http://127.0.0.1:4000` | LiteLLM proxy URL (no `/v1`) |
| `ANTHROPIC_API_KEY` | `sk-...` (virtual key) | LiteLLM auth (alias: claude-code) |
| `ANTHROPIC_MODEL` | `claude-glm-5.2` | Primary model |
| `ANTHROPIC_SMALL_FAST_MODEL` | `claude-deepseek-v3.2` | Fast model for background tasks |
| `CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL` | `1` | Prevent VSCode extension auto-install |

### VSCode Extension Disabled

Claude Code auto-installs its VSCode extension when run from a VS Code terminal.
The installer prevents this two ways:

1. **`~/.claude.json`** — sets `autoInstallIdeExtension: false` (controls IDE integration)
2. **`CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1`** in settings.json env block (runtime override)

The installer also uninstalls the extension if already present (`code --uninstall-extension anthropic.claude-code`).

### Why `claude-` Prefix

LiteLLM routes requests by `model_name`, not by request format. If OpenAI
and Anthropic deployments share the same `model_name` (e.g., `glm-5.2`),
a `/v1/messages` request might randomly hit the OpenAI deployment, triggering
a broken Anthropic→OpenAI→Anthropic translation that drops content. The
`claude-` prefix (e.g., `claude-glm-5.2`) ensures `/v1/messages` always
routes to the Anthropic deployment directly.

### Model Selection

Models use `claude-` prefixed names (e.g., `claude-glm-5.2`) for the
Anthropic endpoint. All 6 models are available. Switch at runtime with
`--model`:

```bash
claude --bare --model claude-deepseek-v4-pro    # deep reasoning
claude --bare --model claude-glm-5.2            # general purpose (default)
claude --bare --model claude-deepseek-v3.2      # fast
```

### Prerequisites

- `npm` — for `npm install -g @anthropic-ai/claude-code`
- `jq` — for parsing LiteLLM API responses and writing settings.json

---

## Repair

| Symptom | Fix |
|---------|-----|
| LiteLLM won't start | `docker compose logs litellm --tail 50` |
| `litellm` keeps restarting | Check `docker compose logs db`, verify `DB_PASSWORD` |
| 401 Unauthorized | Key must start with `sk-` |
| 404 model not found | Model name case-sensitive |
| MaaS 403 | Verify key at https://console.huaweicloud.com/modelarts/ — region must be `ap-southeast-1` |
| `unhealthy_count > 0` | Check MaaS key/model/region — may be transient |
| Virtual key 403 | Check with `/key/info` — may be expired |
| Port conflict | `ss -tlnp \| grep -E ':(4000\|5432\|9090\|3000) '` |
| Validation fails | `./scripts/06_validate.sh` — see recovery table in [SKILL.md](./SKILL.md) Step 7 |
| Prometheus not scraping | Check `docker compose logs prometheus --tail 20`; verify `litellm:4000` reachable from Prometheus container |
| Grafana dashboard blank | Check datasource UID: `curl http://127.0.0.1:3000/api/datasources/name/Prometheus \| jq .uid` — must be `prometheus` |
| Grafana not loading | `docker compose restart grafana` |
| Grafana dashboard stale after upgrade | `docker compose restart grafana` — hard restart picks up provisioning changes |
| Claude Code `claude not found` | `npm install -g @anthropic-ai/claude-code` |
| Claude Code 401 | Check `ANTHROPIC_API_KEY` in `~/.claude/settings.json` env block — must start with `sk-` |
| Claude Code model rejected | Model name case-sensitive — use `claude-` prefixed names (e.g., `claude-glm-5.2`) |

### Lifecycle

| Action | Command |
|--------|---------|
| Graceful stop | `docker compose down` (preserves data volumes) |
| Start | `docker compose up -d` |
| Restart one service | `docker compose restart <service>` |
| Restart all | `docker compose restart` |
| View logs | `docker compose logs <service> --tail 50 -f` |
| Full reset | `docker compose down -v; rm -f .env` (destroys all data) |
