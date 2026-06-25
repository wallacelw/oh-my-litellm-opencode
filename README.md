# oh-my-litellm-opencode

LiteLLM proxy → Huawei MaaS → opencode. Virtual keys, 4 presets, 6 models, multi-key load balancing.

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
./scripts/0_bootstrap.sh      # prompts for MaaS key, starts Docker, installs opencode
./scripts/5_validate.sh       # verify
opencode
```

**LiteLLM-only?** Skip opencode and just deploy the proxy:

```bash
./scripts/0_bootstrap.sh --litellm-only    # LiteLLM proxy only, no opencode
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
- Install mode: full (LiteLLM + opencode) or LiteLLM-only (default: full)
- Install directory (default: /home/oh-my-litellm-opencode)
- My Huawei MaaS API key (region: ap-southeast-1)
- How many extra MaaS keys for load balancing (default: 0)
- Permission to install missing prerequisites (batch ask once)
- My sudo password if the system prompts for it

Rules:
- Do not skip steps. Do not improvise. Do not launch opencode.
- If anything is unclear, ask me before proceeding.
- If an existing installation is found, ask me: update in-place or fresh install.
```

## Documentation

- **[SKILL.md](./SKILL.md)** — Deterministic install procedure (for agents and humans)
- **[REFERENCE.md](./REFERENCE.md)** — Architecture, presets, models, repair guide
