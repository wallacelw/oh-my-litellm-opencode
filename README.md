# oh-my-litellm-opencode

LiteLLM proxy routing Huawei MaaS models to opencode, Codex CLI, and Claude
Code CLI — with virtual keys, multi-key load balancing, dual-format endpoints,
and Prometheus + Grafana observability.

## What You Get

- **LiteLLM proxy** on `:4000` — load balancing, virtual keys, budget tracking
- **opencode** — 4 presets, 7 agents, `oh-my-opencode-slim` plugin
- **Codex CLI** — OpenAI Responses API bridged to Chat Completions by LiteLLM
- **Claude Code CLI** — Anthropic Messages API via LiteLLM proxy
- **Prometheus + Grafana** on `:9090` / `:3000` — 12-panel dashboard, no login
- **6 models** — glm-5.2, glm-5.1, glm-5, deepseek-v4-pro, deepseek-v4-flash, deepseek-v3.2
- **Dual-format endpoints** — OpenAI (`/v1/chat/completions`) + Anthropic (`/v1/messages`)

## Quick Start

**Prerequisites:** Linux, Docker, bun, jq, npm, bubblewrap.

```bash
# 1. Install prerequisites (skip any you already have)
curl -fsSL https://bun.sh/install | bash
sudo apt-get install -y jq npm bubblewrap
# Docker: https://docs.docker.com/get-docker/

# 2. Clone and deploy
git clone https://github.com/wallacelw/oh-my-litellm-opencode
cd oh-my-litellm-opencode
./scripts/0_bootstrap.sh      # prompts for MaaS key

# 3. Verify
./scripts/5_validate.sh       # 74 checks

# 4. Use
opencode                      # or: codex  or:  claude --bare
```

Grafana dashboard: `http://127.0.0.1:3000` (anonymous, no login).

If opencode was already running, exit it (`/exit` or Ctrl+C) and start fresh.

## Install Modes

| Flag | What gets installed |
|------|-------------------|
| *(none)* | LiteLLM + opencode + Codex CLI + Claude Code CLI |
| `--litellm-only` | LiteLLM proxy only |
| `--opencode-only` | LiteLLM + opencode |
| `--codex-only` | LiteLLM + Codex CLI |
| `--claude-code-only` | LiteLLM + Claude Code CLI |

```bash
./scripts/0_bootstrap.sh --litellm-only    # example: proxy only
```

## One-Click Agent Install

Paste this into any coding agent:

```
Install oh-my-litellm-opencode on this machine by following the procedure in
SKILL.md exactly, top to bottom.

1. Fetch and read SKILL.md from:
   https://raw.githubusercontent.com/wallacelw/oh-my-litellm-opencode/main/SKILL.md
2. Follow the procedure in SKILL.md — execute every step in order.
   For each step: check the precondition, run the action, verify the
   postcondition. If a step fails, run the documented recovery. If recovery
   also fails, stop and report the error to me.
3. Step 4 handles cloning to the install directory (chosen in Step 1).
4. The install is complete when scripts/5_validate.sh exits 0 (Step 9).
5. Do NOT launch opencode. Report the summary from Step 10 and stop.

You will need to ask me for:
- Install mode: full (LiteLLM + opencode + Codex CLI + Claude Code CLI), litellm-only, opencode-only, codex-only, or claude-code-only (default: full)
- Install directory (default: /home/oh-my-litellm-opencode)
- My Huawei MaaS API key (region: ap-southeast-1)
- How many extra MaaS keys for load balancing (default: 0)
- Permission to install missing prerequisites (batch ask once)
- My sudo password if the system prompts for it

Rules:
- Do not skip steps. Do not improvise. Do not launch opencode.
- If anything is unclear, ask me before proceeding.
- If an existing installation is found, ask me: update in-place or fresh install.
- After install: I will rotate my MaaS keys (they were shared with you).
```

## One-Click Agent Upgrade

Paste this to upgrade an existing installation:

```
Upgrade oh-my-litellm-opencode on this machine by following Section D
(Upgrade Procedure) in SKILL.md.

1. Fetch and read SKILL.md from:
   https://raw.githubusercontent.com/wallacelw/oh-my-litellm-opencode/main/SKILL.md
2. Find the existing install directory (default: /home/oh-my-litellm-opencode).
   Look for a .git directory inside it.
3. Read the MaaS API key from .env in the install directory — do NOT ask me
   for it. If .env is missing or the key is not there, stop and report.
4. Run: git -C "$PROJECT_DIR" pull --ff-only
   If pull fails, ask me: "Reset to origin/main? (y/n)"
5. Run bootstrap with the key from .env:
   ./scripts/0_bootstrap.sh --agent --maas-key="$MAAS_KEY"
   (add --litellm-only, --opencode-only, --codex-only, or --claude-code-only
   if the existing install used one of those modes)
   Bootstrap is idempotent — it preserves all existing secrets and data.
6. The upgrade is complete when scripts/5_validate.sh exits 0.
7. Do NOT launch opencode. Report the summary and stop.

Rules:
- Do not skip steps. Do not improvise. Do not launch opencode.
- If validation fails, follow the recovery table in Step 9 of SKILL.md.
- After upgrade: I will rotate my MaaS keys if they were shared with you.
```

## Documentation

| File | Description |
|------|-------------|
| [SKILL.md](./SKILL.md) | Deterministic install procedure (for agents and humans) |
| [REFERENCE.md](./REFERENCE.md) | Architecture, tool integration, presets, models, repair guide |
| [CHANGELOG.md](./CHANGELOG.md) | Version history |
