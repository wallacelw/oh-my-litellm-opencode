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

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/bootstrap.sh          # prompts for MaaS key + extra keys
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

### Installation flow

Follow these steps in order. This is the exact flow an AI agent should execute when installing this stack for a user.

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
for port in 4000 4317 4318 8123 9000 3000; do
  ss -tlnp 2>/dev/null | grep -q ":${port} " && echo "PORT $port IN USE" || true
done
```

If any port is in use, tell the user which ports are occupied and ask them to stop the conflicting services before proceeding.

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
# Wait up to 90s for all 4 services to report healthy
for i in $(seq 1 18); do
  HEALTHY=$(docker compose ps --format json 2>/dev/null | jq -r '.Health' 2>/dev/null | sort -u)
  [ "$HEALTHY" = "healthy" ] && echo "All healthy" && break
  echo "Waiting... ($((i*5))s)"
  sleep 5
done
docker compose ps  # final status
```

All 4 services (litellm, db, clickhouse, openlit) must show `healthy`. If any are unhealthy after 90s, check `docker compose logs <service> --tail 20` and consult the [Repair Playbook in SKILL.md](https://github.com/wallacelw/oh-my-litellm-opencode/blob/main/SKILL.md).

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

All checks must pass. If any fail, consult the [Repair Playbook in SKILL.md](https://github.com/wallacelw/oh-my-litellm-opencode/blob/main/SKILL.md).

**Step 12 — Send summary report to user**

Report the following to the user:

```
✅ Installation complete!

Services:
  LiteLLM Proxy:    http://127.0.0.1:4000
  LiteLLM Admin UI: http://127.0.0.1:4000/ui
  OpenLit Dashboard: http://127.0.0.1:3000  (user@openlit.io / openlituser)
  ClickHouse:       http://127.0.0.1:8123

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

### Core rules (must always hold)

- Never commit `.env` or real keys
- Never change `LITELLM_SALT_KEY` after virtual keys exist
- Model names are case-sensitive — must match MaaS console exactly
- Config is generated by `scripts/generate_config.sh` — never edit `litellm_config.yaml` directly
- Master key is admin-only — opencode uses virtual keys
- LiteLLM baseURL: `http://127.0.0.1:4000` (no `/v1`)

### Operational reference

Full details are in **[SKILL.md](https://github.com/wallacelw/oh-my-litellm-opencode/blob/main/SKILL.md)**: core rules, presets & agent assignments, models & costs, multi-key load balancing, observability setup, upgrade paths, repair playbook, determinism guarantees, and verification exit criteria.
