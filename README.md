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

## Install & Upgrade

Same one-liner for both — bootstrap detects an existing install and pulls
updates, or clones fresh if none found. Idempotent — preserves all secrets
and data.

### 👤 Human — run it yourself

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap clones itself, shows a menu to choose what to install, and prompts
for your MaaS API key. Prerequisites are installed automatically.

```bash
opencode          # or: codex  or:  claude --bare
```

After upgrade, restart opencode if it's running (exit and start fresh —
plugin/preset changes are not hot-reloaded). If the Grafana dashboard looks
stale: `docker compose restart grafana`.

### 🤖 Agent (paste this prompt)

```
Install or upgrade oh-my-coding-maas-gateway on this machine.

Fetch and follow SKILL.md:
  https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/SKILL.md

You are the supervisor and wrapper. Read the project docs first, present
a summary, ask me install or upgrade, then run bootstrap and relay every
prompt to me with context. After completion, give me next steps.
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

In interactive mode, you'll be prompted before each installation. Non-interactive
shells (piped stdin, CI) auto-confirm.

**Non-Debian systems** (RHEL, Alpine, Arch): Install the equivalent packages
manually — see the prerequisite table in [INSTALLATION.md](./INSTALLATION.md).
Docker daemon start requires systemd.

See [INSTALLATION.md](./INSTALLATION.md) for the per-script prerequisite table.

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

## Documentation

| File | For | Description |
|------|-----|-------------|
| **[INSTALLATION.md](./INSTALLATION.md)** | Everyone | Install process, pipeline, per-script details, flags, env vars, prerequisites, recovery, upgrade |
| **[SKILL.md](./SKILL.md)** | Agents | Agent procedure: run bootstrap, handle prompts, recovery |
| **[REFERENCE.md](./REFERENCE.md)** | Everyone | Architecture, config, env vars, tool integration, repair guide, lifecycle |
| **[CHANGELOG.md](./CHANGELOG.md)** | Everyone | Version history |
| **[AGENTS.md](./AGENTS.md)** | Contributors | Development rules, validation, commit conventions |
