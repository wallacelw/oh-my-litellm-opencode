# oh-my-litellm-opencode

LiteLLM proxy → Huawei MaaS → opencode. Virtual keys, 4 presets, multi-key load balancing.

## Quick Start

**1. Install prerequisites** (skip any you already have):

```bash
curl -fsSL https://bun.sh/install | bash          # bun
sudo apt-get install -y jq                         # jq (or: brew install jq)
# Docker: https://docs.docker.com/get-docker/     # then start the daemon
```

**2. Deploy:**

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode /home/oh-my-litellm-opencode
cd /home/oh-my-litellm-opencode
./scripts/0_bootstrap.sh      # prompts for MaaS key, starts Docker, installs opencode
./scripts/5_validate.sh       # verify
opencode
```

## Architecture

```
 opencode                LiteLLM (:4000)              Huawei MaaS
 ────────                ──────────────              ────────────
 orchestrator ─┐                              ┌───→ glm-5.1
 oracle ───────┤                              ├───→ glm-5
 council ──────┤  virtual key (sk-...)       ├───→ deepseek-v4-pro
 librarian ────┤──────────────→ LiteLLM ─────├───→ deepseek-v4-flash
 explorer ─────┤  (scoped, unlimited) │       └───→ deepseek-v3.2
 designer ─────┤                    │
 fixer ────────┘                    │    N API keys (load-balanced)
                                    │
                              PostgreSQL (:5432)
```

## Endpoints

| Service | URL | Auth |
|---------|-----|------|
| LiteLLM Proxy | `http://127.0.0.1:4000` | Virtual key (`sk-...`) |
| LiteLLM Admin UI | `http://127.0.0.1:4000/ui` | Master key |

## For AI Agents

Read **[SKILL.md](https://github.com/wallacelw/oh-my-litellm-opencode/blob/main/SKILL.md)** for the installation flow. Agent collects keys interactively, then calls `0_bootstrap.sh --agent --maas-key=KEY` for the non-interactive deploy.
