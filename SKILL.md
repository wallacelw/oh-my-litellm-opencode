---
name: oh-my-litellm-opencode
description: Deploy LiteLLM proxy (Docker Compose: litellm + postgres) routing through Huawei ModelArts MaaS with multi-key load balancing, then bootstrap opencode + oh-my-opencode-slim with virtual key, dual providers, and 4 presets. TRIGGER when the task involves: LiteLLM proxy deployment, Huawei MaaS model routing, opencode + MaaS setup, full-stack AI coding bootstrap, oh-my-litellm-opencode, virtual key management, multi-key load balancing, docker compose with this stack, or any reference to LITELLM_MASTER_KEY, HUAWEI_MAAS_API_KEY.
---

# oh-my-litellm-opencode

Deploy LiteLLM proxy → bootstrap opencode + oh-my-opencode-slim → mint virtual key → configure. **Idempotent — safe to re-run.**

## When to Use

| Situation | Route |
|---|---|
| Deploy full stack from scratch | `./scripts/bootstrap.sh` |
| LiteLLM already running | `./scripts/bootstrap.sh` (auto-detects, skips deploy) |
| Change MaaS key | `./scripts/bootstrap.sh --maas-key=NEW` (updates .env + regenerates config) |
| Add/modify a model | Edit `generate_config.sh` MODELS array → `generate_config.sh` → `docker compose restart litellm` |
| Add a MaaS key for load balancing | Add `HUAWEI_MAAS_API_KEY_N` to `.env`, increment COUNT → `generate_config.sh` → `docker compose restart litellm` |
| Change routing strategy | `./scripts/generate_config.sh --routing-strategy=least-busy && docker compose restart litellm` |
| Troubleshoot | See **Repair Playbook** |
| Validate | `./scripts/validate.sh` |
| Switch presets at runtime | `/preset LiteLLM-Huawei-MaaS-Lite` |

**When NOT to use:** Direct MaaS calls without proxy, non-Huawei providers, multi-host/K8s deployments.

## Required Inputs

- **Huawei MaaS API key** — from [ModelArts console](https://console.huaweicloud.com/modelarts/). Mandatory.
- **Additional MaaS API keys** (optional) — for load balancing (multiplies effective RPM/TPM).
- **MaaS region** — `ap-southeast-1` only. Do not swap regions.
- **Model IDs** — verify in MaaS console, do not guess (case-sensitive).
- **LITELLM_SALT_KEY** — immutable after first virtual key.

All collected by `./scripts/init_env.sh` (interactive or `--auto`).

## Prerequisites

bun, jq, Docker + Compose V2, git, python3, `HUAWEI_MAAS_API_KEY` env var.

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
                                  PostgreSQL (:5432)
                                  keys · spend · usage
```

**Startup order:** PostgreSQL starts → LiteLLM starts (healthcheck-gated on db).

**Data flow:**
1. opencode sends request to LiteLLM with virtual key
2. LiteLLM validates key, selects healthy deployment, forwards to MaaS
3. MaaS responds → LiteLLM records usage/spend in PostgreSQL

## Core Rules

These invariants must always hold. Violating them breaks the system.

- **Never commit `.env` or real keys.** Secrets in `.env` (gitignored, `0600`).
- **Never change `LITELLM_SALT_KEY` after virtual keys exist.** Recovery = `docker compose down -v` + fresh start.
- **Model names are case-sensitive.** Must match MaaS console exactly.
- **MaaS region-locked** to `ap-southeast-1`. Do not change `HUAWEI_MAAS_API_BASE`.
- **Config is generated** by `scripts/generate_config.sh`. Never edit `litellm_config.yaml` directly.
- **Config is read-only at startup.** Changes require `docker compose restart litellm`.
- **Non-zero pricing required** on every model for budget enforcement.
- **Master key is admin-only.** Mint virtual keys per team/service — never use master key in opencode.
- **Proxy is sole egress** for MaaS traffic (centralized budgets/rate limits/audit).
- **LiteLLM provider uses `@ai-sdk/openai-compatible`** (not `openai`).
- **Model keys: `openai/<model>`** in LiteLLM provider. **Preset references: `LiteLLM/openai/<model>`** (3-part).
- **LiteLLM baseURL: `http://127.0.0.1:4000`** (no `/v1` — SDK adds it).
- **Disable `explore` and `general` agents.** Enable LSP. Use virtual keys (not master key) for opencode.
- **`jq --arg` for JSON substitution** — never `sed` on JSON files.
- **Same-host only.** No multi-host or K8s support.
- **Mask secrets** as `<prefix>...<suffix>` in all log output.

## Deployment Workflow

### For AI agents (12-step interactive flow)

Follow these steps in order when installing this stack for a user.

**Step 1 — Ask for the main MaaS API key**

Ask the user: "What is your Huawei ModelArts MaaS API key? (get it from https://console.huaweicloud.com/modelarts/, region ap-southeast-1)"

Store the response as `MAAS_KEY`. Do not proceed without it.

**Step 2 — Validate the key**

Before investing time in the full install, verify the key works:

```bash
curl -sf -m 10 "https://maas-api.ap-southeast-1.myhuaweicloud.com/v1/infers" \
  -H "Authorization: Bearer $MAAS_KEY" >/dev/null 2>&1 && echo "OK" || echo "INVALID"
```

If invalid, tell the user and go back to step 1. Common causes: typo, expired key, wrong region.

**Step 3 — Ask for additional keys**

Ask the user: "How many additional MaaS API keys do you want for load balancing? (0 for none, each key multiplies effective RPM/TPM)"

If the answer is > 0, prompt for each key one by one:
- "Additional MaaS key 1:" → store as `MAAS_KEY_1`
- "Additional MaaS key 2:" → store as `MAAS_KEY_2`
- ...and so on

If 0, skip.

**Step 4 — Check prerequisites and install missing ones**

```bash
# Check what's missing
command -v bun >/dev/null 2>&1 || echo "MISSING: bun"
command -v jq >/dev/null 2>&1 || echo "MISSING: jq"
command -v docker >/dev/null 2>&1 || echo "MISSING: docker"
command -v git >/dev/null 2>&1 || echo "MISSING: git"
command -v python3 >/dev/null 2>&1 || echo "MISSING: python3"
```

Install missing prerequisites using these commands:

| Tool | Install command | Notes |
|------|----------------|-------|
| bun | `curl -fsSL https://bun.sh/install \| bash` | Restart shell after install |
| jq | `sudo apt-get install -y jq` (Debian/Ubuntu) or `brew install jq` (macOS) | |
| git | `sudo apt-get install -y git` (Debian/Ubuntu) or `brew install git` (macOS) | Usually pre-installed |
| python3 | `sudo apt-get install -y python3` (Debian/Ubuntu) or `brew install python3` (macOS) | Usually pre-installed |
| docker | **Cannot be automated** — ask user to install manually: https://docs.docker.com/get-docker/ | Must also start the daemon |

Do not proceed until all prerequisites are installed.

**Step 5 — Check Docker is running**

```bash
docker info >/dev/null 2>&1 && echo "OK" || echo "Docker daemon not running"
```

If not running, ask the user to start Docker and retry. Do not proceed until the daemon is up.

**Step 6 — Check for existing installation**

```bash
[ -d /home/oh-my-litellm-opencode ] && echo "EXISTS" || echo "FRESH"
```

If the directory exists, ask the user: "An existing installation was found. Do you want to (a) update it in-place or (b) remove and reinstall fresh?" If (b): `rm -rf /home/oh-my-litellm-opencode`.

**Step 7 — Check port availability**

```bash
ss -tlnp 2>/dev/null | grep -q ":4000 " && echo "PORT 4000 IN USE" || true
```

If port 4000 is in use, tell the user and ask them to stop the conflicting service before proceeding.

**Step 8 — Install LiteLLM and related services**

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode

# Set up environment with the keys collected in steps 1-3
export HUAWEI_MAAS_API_KEY="$MAAS_KEY"
# If additional keys were provided:
export HUAWEI_MAAS_API_KEY_COUNT="<1 + number of additional keys>"
export HUAWEI_MAAS_API_KEY_1="$MAAS_KEY_1"  # if provided
export HUAWEI_MAAS_API_KEY_2="$MAAS_KEY_2"  # if provided

./scripts/init_env.sh --auto
./scripts/generate_config.sh
docker compose up -d
```

**Step 9 — Wait for services to be healthy**

```bash
# Wait up to 90s for both services to report healthy
for i in $(seq 1 18); do
  HEALTHY=$(docker compose ps --format json 2>/dev/null | jq -r '.Health' 2>/dev/null | sort -u)
  [ "$HEALTHY" = "healthy" ] && echo "All healthy" && break
  echo "Waiting... ($((i*5))s)"
  sleep 5
done
docker compose ps  # final status
```

Both services (litellm, db) must show `healthy`. If any are unhealthy after 90s, check `docker compose logs <service> --tail 20` and consult the Repair Playbook below.

**Step 10 — Install opencode and oh-my-opencode-slim**

```bash
./scripts/install.sh
```

This installs opencode, the oh-my-opencode-slim plugin (with `--companion=yes` for the floating desktop status window), mints or reuses a virtual key, and writes all config files. It is idempotent — safe to re-run.

**Virtual key reuse** (handled automatically by install.sh — no separate step needed):
- If a key with alias "opencode" already exists in LiteLLM → smoke test → reuse if valid
- If `opencode.jsonc` already has a key → smoke test → reuse if valid
- Otherwise → mint new key with alias "opencode", unlimited budget, unlimited duration

**Step 11 — Validate**

```bash
./scripts/validate.sh
```

All checks must pass. If any fail, consult the Repair Playbook below.

**Step 12 — Send summary report to user**

Report the following to the user:

```
✅ Installation complete!

Services:
  LiteLLM Proxy:    http://127.0.0.1:4000
  LiteLLM Admin UI: http://127.0.0.1:4000/ui

Next steps:
  1. Run `opencode` to start coding
  2. Switch presets at runtime: /preset LiteLLM-Huawei-MaaS-Lite

⚠️  Security: If any API keys were visible in your terminal during
    installation, you should rotate them. To replace a key:
    1. Get a new key from the MaaS console
    2. Edit .env: replace HUAWEI_MAAS_API_KEY (or HUAWEI_MAAS_API_KEY_N)
    3. Run: ./scripts/generate_config.sh && docker compose restart litellm
    4. Run: ./scripts/validate.sh
```

### For humans (interactive)

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/bootstrap.sh          # prompts for MaaS key + any missing values
```

### Step-by-step (if not using bootstrap.sh)

```bash
./scripts/init_env.sh --auto    # agent mode: reads HUAWEI_MAAS_API_KEY from env
./scripts/generate_config.sh    # build litellm_config.yaml from .env
docker compose up -d            # start both services
./scripts/install.sh            # install opencode + plugin + mint key + write config
./scripts/validate.sh           # verify everything works
```

### bootstrap.sh step-by-step

| Step | Action | Idempotency |
|------|--------|-------------|
| 2 | Check prerequisites (bun, jq, docker, git, python3, MaaS key) | Read-only |
| 3a | Ensure `.env` exists (runs `init_env.sh --auto` if missing) | Skips if `.env` exists; updates key if `--maas-key` differs |
| 3b | Start Docker Compose | `docker compose up -d` is no-op if already running |
| 3c | Resolve master key (env → `.master-key` → `.env` → prompt) | Caches to `.master-key` for faster future resolution |
| 4 | Install opencode + plugin + mint key + write config | Reuses existing key by alias; diff-before-write on configs |
| 5 | Validate (55+ checks) | Read-only |
| 6 | Summary (URLs, keys, next steps) | Read-only |

### init_env.sh modes

| Mode | Secrets | MaaS keys | Use case |
|------|---------|-----------|----------|
| interactive (default) | Prompt each with generated defaults | Prompt each (comma-separated) | Human, first-time |
| `--auto` | Auto-generate, **preserve on re-run** | Main from env var + extras from env vars | AI agent (bootstrap.sh provides env vars) |
| `--auto --force` | Regenerate all | Main from env var + extras from env vars | Key rotation after security incident |

**Important:** `--auto --force` regenerates `LITELLM_MASTER_KEY` and `LITELLM_SALT_KEY`. You must run `docker compose up -d` afterward to pick up the new values. All existing virtual keys are invalidated — re-run `install.sh` to mint new ones.

### Master Key Resolution (bootstrap.sh)

Priority: env var → `.master-key` file → `.env` file → interactive prompt.

When found in `.env`, the key is cached to `.master-key` (chmod 600) for faster future resolution.

## Multi-Key Load Balancing

With N MaaS API keys, each model has N deployments. LiteLLM load-balances across them. **Effective RPM/TPM = per-key × N.**

| Variable | Set by | Description |
|---|---|---|
| `HUAWEI_MAAS_API_KEY` | Manual / init_env.sh | Main key (mandatory) |
| `HUAWEI_MAAS_API_KEY_COUNT` | init_env.sh | Total keys (1 + extra) |
| `HUAWEI_MAAS_API_KEY_N` | init_env.sh | Indexed keys (_0, _1, ...) |

**Add a key:**
1. Add `HUAWEI_MAAS_API_KEY_N=<key>` to `.env`
2. Increment `HUAWEI_MAAS_API_KEY_COUNT`
3. `./scripts/generate_config.sh && docker compose restart litellm`

**Change routing:** `./scripts/generate_config.sh --routing-strategy=least-busy && docker compose restart litellm`

Strategies: `simple-shuffle` (default), `least-busy`, `latency-based-routing`, `usage-based-routing`, `cost-based-routing`.

## opencode Bootstrap

Handled by `bootstrap.sh` or `install.sh`:

1. **Install opencode** — `curl -fsSL https://opencode.ai/install | bash` (latest stable, download-then-execute)
2. **Install plugin + companion** — `bunx oh-my-opencode-slim@2.0.4 install --companion=yes` (skips if already installed; downloads native companion binary for live agent status window)
3. **Mint virtual key** — reuse existing by alias (up to 50 key lookups), else mint unlimited key via LiteLLM
4. **Write opencode.jsonc** — `jq --arg` substitution on template (diff-before-write, backup on change)
5. **Write oh-my-opencode-slim.json** — copy template (diff-before-write, backup on change)
6. **Validate** — `scripts/validate.sh`

### Virtual key reuse logic (install.sh)

1. If `--virtual-key=sk-...` provided → use it directly
2. If `LITELLM_MASTER_KEY` available → query `/key/list` → iterate up to 50 keys → `/key/info` for each → find alias "opencode" → smoke test with `deepseek-v3.2` (700 RPM, cheapest) → reuse if valid
3. If existing `opencode.jsonc` has a key → smoke test → reuse if valid
4. Otherwise → mint new key with alias "opencode", unlimited budget, unlimited duration

## Presets

| Preset | Models | Route | When to use |
|--------|--------|-------|-------------|
| **LiteLLM-Huawei-MaaS** (default) | All 5 | LiteLLM proxy → MaaS | Production — budget tracking, load balancing |
| **LiteLLM-Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | LiteLLM proxy → MaaS | Cost-saving — skip expensive models |
| **Huawei-MaaS** | All 5 | Direct to MaaS | Debugging proxy issues — bypass LiteLLM |
| **Huawei-MaaS-Lite** | 3 (no v4-pro/v4-flash) | Direct to MaaS | Debugging + cost-saving |

### Agent Assignments (LiteLLM-Huawei-MaaS)

| Agent | Model | Variant | Fallback | Rationale |
|-------|-------|---------|----------|-----------|
| orchestrator | glm-5.1 | high | — | Strongest GLM, reliable orchestrator |
| oracle | deepseek-v4-pro | max | glm-5.1 | Best reasoning, fallback to GLM |
| council | deepseek-v4-pro | high | glm-5.1 | Multi-model consensus, same pair |
| librarian | deepseek-v3.2 | low | — | Cheap, fast, good enough for docs |
| explorer | deepseek-v4-flash | low | deepseek-v3.2 | Fast search, fallback to cheapest |
| designer | glm-5 | medium | — | Good design sense, mid-tier |
| fixer | deepseek-v4-flash | high | glm-5 | Fast implementation, fallback to GLM |

Fallback via model arrays (oh-my-opencode-slim v2 format): `"model": ["primary", "fallback"]`.

Council: single `councillor` per preset (deepseek-v4-pro/high), executed in parallel with 3 retries.

## Models

| Name | Context (in/out) | RPM | TPM | Cost (in/out per token) |
|---|---|---|---|---|
| `glm-5.1` | 192K / 128K | 30 | 500K | $1.078 / $3.774 × 10⁻⁶ |
| `glm-5` | 192K / 64K | 30 | 500K | $0.809 / $2.965 × 10⁻⁶ |
| `deepseek-v4-pro` | 1M / 128K | 3 | 30K | $1.617 / $3.235 × 10⁻⁶ |
| `deepseek-v4-flash` | 1M / 128K | 3 | 30K | $0.135 / $0.270 × 10⁻⁶ |
| `deepseek-v3.2` | 128K / 32K | 700 | 500K | $0.270 / $0.404 × 10⁻⁶ |

### Adding a new model

1. Find name/rate/price in [MaaS console](https://console.huaweicloud.com/modelarts/)
2. Add entry to `generate_config.sh` `MODELS` array (match MaaS name exactly, case-sensitive)
3. Set non-zero `input_cost_per_token` / `output_cost_per_token` (per-token, not per-1K)
4. `./scripts/generate_config.sh && docker compose restart litellm`

## Docker Compose

| Service | Image | Port | Resources | Depends on |
|---|---|---|---|---|
| litellm | `ghcr.io/berriai/litellm:v1.89.3` | 4000 | 2g RAM, 2 CPU | db (healthy) |
| db | `postgres:16-alpine` | (5432) | 512m RAM, 1 CPU | — |

All services: `restart: unless-stopped`, json-file logs (10m × 3 rotations), memory + CPU limits.

All passwords use `:?` fail-fast syntax — Docker Compose refuses to start if any required variable is missing from `.env`.

## Operations

| Service | URL | Auth |
|---|---|---|
| LiteLLM API | `http://127.0.0.1:4000` | `Bearer <key>` |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key |

**Backup:** `docker compose exec db pg_dump -U llmproxy litellm > backup.sql`
**Reset:** `docker compose down -v && docker compose up -d`
**Logs:** `docker compose logs litellm --tail 50`

## Upgrade Path

### Upgrade LiteLLM

1. Check [releases](https://github.com/BerriAI/litellm/releases) for breaking changes
2. Edit `docker-compose.yml`: change `ghcr.io/berriai/litellm:v1.89.3` → new version
3. `docker compose pull litellm && docker compose up -d litellm`
4. `./scripts/validate.sh --litellm-only`

### Upgrade oh-my-opencode-slim

1. Check [releases](https://github.com/nicepkg/oh-my-opencode-slim/releases) for config format changes
2. Edit `scripts/install.sh`: change `SLIM_VERSION="2.0.4"` → new version
3. Edit `configs/templates/oh-my-opencode-slim.json.template`: update `$schema` URL
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
| `litellm` keeps restarting | Check `docker compose logs db`, verify `DB_PASSWORD` matches `.env` |
| 401 Unauthorized | Verify `Authorization: Bearer sk-...` header — key must start with `sk-` |
| 404 model not found | Model name case-sensitive, must match MaaS console exactly |
| `LITELLM_SALT_KEY` error | Use original salt; if lost, `docker compose down -v` and start fresh |
| MaaS 403 | Verify key in console; region must be `ap-southeast-1` |
| `unhealthy_count > 0` | Check MaaS key, model ID, region — may be transient, wait 30s |
| Budget not consumed | Set non-zero `input_cost_per_token` / `output_cost_per_token` in model catalog |
| Virtual key 403 | Check key with `/key/info?key=<key_id>` — may be expired or revoked |
| Plugin not loaded | Re-run `bunx oh-my-opencode-slim@2.0.4 install` |
| Fallback not triggering | Set `fallback.enabled: true`, use model arrays (not strings) |
| Port conflict | Check `ss -tlnp \| grep ':4000'` |
| `.env` has `:?` error | All required variables must be set — run `init_env.sh` |

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
| `init_env.sh --auto` non-interactive | Preserves all 3 secrets on re-run (MASTER_KEY, SALT_KEY, DB_PASSWORD) — true no-op |
| opencode latest | `curl -fsSL https://opencode.ai/install \| bash` (no pinning — always latest) |
| docker compose up -d | Idempotent — always run, no-op if services already up and config unchanged |
| Virtual key reuse | install.sh reuses existing key by alias (up to 50 lookups); mints only if missing or invalid |
| install.sh configs | Diff-before-write — skip if unchanged, backup if changed |
| `--maas-key=NEW` key change | Updates `.env` + regenerates `litellm_config.yaml` + Docker picks up on `up -d` |
| LiteLLM image pinned | `v1.89.3` (no `latest`) |
| Docker passwords fail-fast | `:?` syntax — Compose refuses to start if any required variable is missing |
| Timeouts consistent | `request_timeout: 600`, `stream_timeout: 60` |
| Resource limits | Both services have memory + CPU limits (no unbounded containers) |
| Port conflicts detected | `bootstrap.sh` checks 4000 before starting |
| `mint-virtual-key.sh` resilient | 3 retries with backoff (5s/10s/15s); `--max-time 30` on all curls |
| Config substitution safe | `jq --arg` only, never `sed` on JSON |
| All curls have timeouts | `--max-time` or `-m` on every curl call (no hanging) |
| Interactive reads safe | All `read -r` calls use `< /dev/tty` (safe in piped stdin contexts) |
| JSONC parsing safe | State-machine `strip_jsonc()` — not regex — handles comments inside strings correctly |

## Verification Exit Criteria

Run `./scripts/validate.sh` after bootstrap. All checks must pass:

- [ ] `.env` exists with all required variables (no placeholders), `0600` permissions
- [ ] `litellm_config.yaml` generated with `5 × N` deployments
- [ ] Both Docker services healthy
- [ ] LiteLLM liveness 200, `unhealthy_count: 0`
- [ ] Virtual key minting succeeds (starts with `sk-`)
- [ ] opencode.jsonc: both providers (LiteLLM + Huawei-MaaS), valid virtual key, 5 models each, chmod 600
- [ ] oh-my-opencode-slim.json: 4 presets, default LiteLLM-Huawei-MaaS, council configured, fallback enabled
- [ ] Inference smoke test: model responds via proxy
- [ ] No real secrets in `git diff`
