# oh-my-litellm-opencode

LiteLLM proxy → Huawei MaaS → opencode + Codex CLI + Claude Code CLI. Virtual keys, 4 presets, 6 models, dual-format endpoints (OpenAI + Anthropic), multi-key load balancing, Prometheus + Grafana observability.

## Quick Start

**Prerequisites:** Linux, Docker, bun, jq.

**1. Install prerequisites** (skip any you already have):

```bash
curl -fsSL https://bun.sh/install | bash          # bun
sudo apt-get install -y jq                         # jq
# Docker: https://docs.docker.com/get-docker/     # then start the daemon
```

**2. Deploy:**

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode
cd oh-my-litellm-opencode
./scripts/0_bootstrap.sh      # prompts for MaaS key, starts Docker, installs opencode + Codex CLI
./scripts/5_validate.sh       # verify
opencode                      # or: codex  or:  claude --bare
```

After install, open the Grafana dashboard at `http://127.0.0.1:3000`
(username: `admin`, password: `grep GRAFANA_ADMIN_PASSWORD .env`).

If opencode was already running, exit it (`/exit` or Ctrl+C) and start fresh
to pick up the new configuration.

**LiteLLM-only?** Skip opencode and Codex CLI, just deploy the proxy:

```bash
./scripts/0_bootstrap.sh --litellm-only    # LiteLLM proxy only
```

**Codex CLI only?** Skip opencode:

```bash
./scripts/0_bootstrap.sh --codex-only      # LiteLLM proxy + Codex CLI
```

**Claude Code CLI only?** Skip opencode and Codex:

```bash
./scripts/0_bootstrap.sh --claude-code-only   # LiteLLM proxy + Claude Code CLI
```

## One-Click Agent Install

Copy and paste this prompt into any coding agent to install automatically:

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

Already installed and want to update to the latest version? Copy and paste:

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
   (add --litellm-only if the existing install is LiteLLM-only)
   Bootstrap is idempotent — it preserves all existing secrets and data.
6. The upgrade is complete when scripts/5_validate.sh exits 0.
7. Do NOT launch opencode. Report the summary and stop.

Rules:
- Do not skip steps. Do not improvise. Do not launch opencode.
- If validation fails, follow the recovery table in Step 9 of SKILL.md.
- After upgrade: I will rotate my MaaS keys if they were shared with you.
```

## Documentation

- **[SKILL.md](./SKILL.md)** — Deterministic install procedure (for agents and humans)
- **[REFERENCE.md](./REFERENCE.md)** — Architecture, presets, models, repair guide
