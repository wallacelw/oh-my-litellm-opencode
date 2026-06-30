# oh-my-coding-maas-gateway

LiteLLM proxy routing Huawei MaaS models to opencode, Codex CLI, and Claude
Code CLI — with virtual keys, multi-key load balancing, dual-format endpoints,
and Prometheus + Grafana observability.

---

## What Is This?

A self-hosted gateway that sits between your coding tools and Huawei ModelArts
MaaS, giving you load balancing, virtual keys, budget tracking, and
observability — all through a single local proxy.

```
  Tools               LiteLLM (:4000)                  Huawei MaaS
  ─────               ───────────────                  ────────────

  opencode ──→ /v1/chat/completions ──→ openai/ provider ──→ MaaS OpenAI endpoint
  Codex CLI ──→ /v1/responses ────────→ openai/ provider ──→ MaaS OpenAI endpoint
  Claude Code ─→ /v1/messages ────────→ anthropic/ provider ─→ MaaS Anthropic endpoint

  LiteLLM: load-balances across N MaaS keys · PostgreSQL (:5432)
  Observability: LiteLLM ──/metrics──→ Prometheus (:9090) ──→ Grafana (:3000)
```

**6 models:** glm-5.2, glm-5.1, glm-5, deepseek-v4-pro, deepseek-v4-flash,
deepseek-v3.2

---

## Quick Start

Two ways to install:

### 👤 Human — run it yourself

```bash
git clone https://github.com/wallacelw/oh-my-coding-maas-gateway ~/oh-my-coding-maas-gateway
cd ~/oh-my-coding-maas-gateway
./scripts/0_bootstrap.sh
```

You'll get a menu to choose what to install. Enter your MaaS API key when
prompted. Prerequisites are installed automatically. That's it.

```bash
opencode          # or: codex  or:  claude --bare
```

### 🤖 Agent Installation (paste this prompt)

```
Install oh-my-coding-maas-gateway on this machine by following SKILL.md.

1. Fetch SKILL.md from:
   https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/SKILL.md
2. Follow the procedure — execute every step in order. For each step:
   check precondition, run action, verify postcondition. If a step fails,
   run the documented recovery. If recovery also fails, stop and report.
3. The install is complete when scripts/5_validate.sh exits 0 (Step 7).
4. Do NOT launch opencode. Report the summary from Step 8 and stop.

You will need to ask me for:
- Install mode: all, litellm, opencode, codex, or claude (default: all)
- Install directory (default: /home/oh-my-coding-maas-gateway)
- My Huawei MaaS API key (region: ap-southeast-1)
- How many extra MaaS keys for load balancing (default: 0)
- My sudo password if the system prompts for it

Rules:
- Do not skip steps. Do not improvise. Do not launch opencode.
- If anything is unclear, ask me before proceeding.
- If an existing installation is found, ask me: update in-place or fresh install.
- After install: I will rotate my MaaS keys (they were shared with you).
```

### 🤖 Agent Upgrade (paste this prompt)

```
Upgrade oh-my-coding-maas-gateway by following the Upgrade Procedure in SKILL.md.

1. Fetch SKILL.md from:
   https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/SKILL.md
2. Find the existing install directory (default: /home/oh-my-coding-maas-gateway).
3. Read the MaaS API key from .env — do NOT ask me for it.
   If .env is missing, stop and report.
4. Run: git -C "$PROJECT_DIR" pull --ff-only
   If pull fails, ask me: "Reset to origin/main? (y/n)"
5. Run: ./scripts/0_bootstrap.sh --agent --maas-key="$MAAS_KEY"
   (add --tool=... if the existing install used a specific mode)
6. The upgrade is complete when scripts/5_validate.sh exits 0.
7. Do NOT launch opencode. Report the summary and stop.

Rules:
- Do not skip steps. Do not improvise. Do not launch opencode.
- If validation fails, follow the recovery table in SKILL.md Step 7.
- After upgrade: I will rotate my MaaS keys if they were shared with you.
```

---

## What You Get

| Service | URL | Auth | Purpose |
|---------|-----|------|---------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key | API gateway |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key | View keys, spend, deployments |
| Grafana Dashboard | `http://127.0.0.1:3000` | Anonymous | 34-panel observability dashboard |
| Prometheus | `http://127.0.0.1:9090` | None | Metrics storage |
| PostgreSQL | `localhost:5432` (internal) | — | LiteLLM database |

**Coding tools installed:**

| Tool | Activate | API Format | Config location |
|------|----------|------------|-----------------|
| opencode | `opencode` | OpenAI Chat Completions | `~/.config/opencode/opencode.json` |
| Codex CLI | `codex` | OpenAI Responses (bridged) | `~/.codex/config.toml` |
| Claude Code CLI | `claude --bare` | Anthropic Messages | `~/.claude/settings.json` |

Each tool gets its own virtual key with unlimited budget and access to all
models. opencode also gets 4 presets and 7 agents via the
oh-my-opencode-slim plugin.

---

## Install Modes

Interactive menu appears when you run bootstrap. Or use `--tool=` flag:

| Choice | Flag | What gets installed |
|--------|------|-------------------|
| 1 (default) | `--tool=all` | LiteLLM + opencode + Codex + Claude Code |
| 2 | `--tool=litellm` | LiteLLM proxy only |
| 3 | `--tool=opencode` | LiteLLM + opencode |
| 4 | `--tool=codex` | LiteLLM + Codex CLI |
| 5 | `--tool=claude` | LiteLLM + Claude Code CLI |
| 6 | `--tool=opencode,codex` | Custom combo (comma-separated) |

---

## Prerequisites

**OS:** Linux (Debian/Ubuntu with systemd recommended).

**Auto-installed** by the scripts as needed (no manual setup required):
git, python3, curl, jq, docker + compose, bun, npm/node, bubblewrap.

In interactive mode, you'll be prompted before each installation. In agent
mode (`--agent`), everything installs automatically.

**Non-Debian systems** (RHEL, Alpine, Arch): Install the equivalent packages
manually — see the package mapping table in [SKILL.md](./SKILL.md) Step 2.
Docker daemon start requires systemd.

---

## After Install

### Using opencode

```bash
opencode
# Switch preset: /preset LiteLLM-Huawei-MaaS-Core
# Available presets:
#   LiteLLM-Huawei-MaaS-Full  (default, all 6 models via proxy)
#   LiteLLM-Huawei-MaaS-Core  (4 models, no v4-pro/v4-flash)
#   Huawei-MaaS-Full          (direct, bypass proxy)
#   Huawei-MaaS-Core          (direct, bypass proxy)
```

If opencode was already running, exit it first (`/exit` or Ctrl+C).

### Using Codex CLI

```bash
codex
codex --model deepseek-v4-pro    # deep reasoning
codex --model deepseek-v3.2      # fast
```

### Using Claude Code CLI

```bash
claude --bare
claude --bare --model claude-deepseek-v4-pro    # deep reasoning
```

### Monitoring

- **Grafana:** `http://127.0.0.1:3000` — 34-panel dashboard (anonymous, no
  login). 6 sections: At-a-glance, Latency, Errors & Health, Throughput &
  Capacity, Tokens, Cost. Time window selectable (default 15m).
- **LiteLLM Admin UI:** `http://127.0.0.1:4000/ui` — view deployments, virtual
  keys, spend, budgets. Login: `admin` / your master key.

---

## Upgrade

```bash
cd ~/oh-my-coding-maas-gateway
git pull
./scripts/0_bootstrap.sh    # idempotent — preserves all secrets and data
```

After upgrade, restart opencode if it's running (exit and start fresh —
plugin/preset changes are not hot-reloaded).

If Grafana dashboard looks stale after upgrade: `docker compose restart grafana`

---

## Documentation

| File | For | Description |
|------|-----|-------------|
| **[SKILL.md](./SKILL.md)** | Agents | Deterministic install procedure (8 steps, agent-first) |
| **[REFERENCE.md](./REFERENCE.md)** | Everyone | Architecture, config, env vars, tool integration, repair guide, lifecycle |
| **[CHANGELOG.md](./CHANGELOG.md)** | Everyone | Version history |
| **[AGENTS.md](./AGENTS.md)** | Contributors | Development rules, validation, commit conventions |
