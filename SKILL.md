---
name: oh-my-coding-maas-gateway
description: Deploy LiteLLM proxy (litellm + postgres + prometheus + grafana) routing through Huawei MaaS with multi-key load balancing, then bootstrap opencode + Codex CLI + Claude Code CLI with virtual keys and 4 presets.
---

# oh-my-coding-maas-gateway — Agent Procedure

You are both a supervisor and a wrapper around the bootstrap script.
You understand the project, guide the user, relay every bootstrap prompt
with context, and deliver a final summary with next steps.

Do NOT launch opencode or any coding tool. Your job ends at verification.

## 1. Read the project

Fetch and read these docs from GitHub (works before cloning):

- `https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/INSTALLATION.md`
- `https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/REFERENCE.md`

## 2. Present summary, ask intent

Output a structured summary to the user:

- **What it does** — LiteLLM proxy routing to Huawei MaaS, multi-key load
  balancing, observability stack (Prometheus + Grafana).
- **What gets installed** — Docker stack (LiteLLM + Postgres + Prometheus +
  Grafana), then selected coding tools (opencode, Codex CLI, Claude Code CLI).
- **Prerequisites** — Docker, git, curl, jq, bun/npm (installed automatically).
- **What you'll be asked for** — MaaS API key, install mode, extra keys.
- **Estimated time** — ~5 min fresh, ~2 min upgrade.

Then ask: **"Install or upgrade?"** If `/home/oh-my-coding-maas-gateway/.env`
exists, suggest upgrade. Otherwise suggest install.

## 3. Run bootstrap, relay prompts

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Bootstrap will emit prompts one at a time. For **each** prompt:

1. Read what bootstrap is asking.
2. Elaborate — explain what's being asked and why, add context from the
   docs you read (e.g., "Bootstrap is asking for your Huawei MaaS API key.
   This is from the Huawei cloud console, region ap-southeast-1. It will
   be stored in .env and never committed.").
3. Relay to the user and get their answer.
4. Feed the answer back to bootstrap on stdin.

This applies to **all** prompts — including auto-generated secrets (inform
the user what was generated and why) and the install directory. Maximum
transparency, no silent auto-answering.

For **upgrade**: bootstrap preserves the MaaS key from `.env` automatically
— do not ask the user. Relay all other prompts normally.

If sudo prompts for a password, ask the user.

## 4. Verify

Bootstrap runs `06_validate.sh` automatically. Check its exit code:

- **Exit 0** — proceed to final summary.
- **Exit non-zero** — match the FAIL pattern in the recovery table below,
  run the recovery, re-validate **once**. If it still fails, stop and
  report the full output to the user.

## 5. Final summary

Take bootstrap's output and complement it with:

- **Service URLs** — LiteLLM `http://127.0.0.1:4000`, Admin UI
  `http://127.0.0.1:4000/ui`, Grafana `http://127.0.0.1:3000`,
  Prometheus `http://127.0.0.1:9090`.
- **How to launch tools** — `opencode`, `codex`, `claude --bare`.
- **Health check** — `./scripts/06_validate.sh` (re-run anytime).
- **Key rotation** — remind the user to rotate their MaaS keys if shared
  with you during the process.
- **Upgrade note** — if this was an upgrade, remind them to restart
  opencode if it's running (plugin changes are not hot-reloaded).

## Recovery

| FAIL pattern | Recovery |
|--------------|----------|
| `.env not found` / `placeholder value` | Re-run `01_env.sh` |
| `services running` + `expected 4` | `docker compose up -d`, wait 30s, retry |
| `liveness probe returned` | `docker compose logs litellm --tail 50` |
| `Inference smoke test` + `did not respond` | Re-validate MaaS key; check logs |
| opencode issues (`opencode not found`, config) | Re-run `03_opencode.sh` |
| Codex issues (`codex not found`, config) | Re-run `04_codex.sh` |
| Claude Code issues (`claude not found`, config) | Re-run `05_claude_code.sh` |
| `Prometheus not reachable` | `docker compose up -d prometheus`, wait 10s |
| `/metrics endpoint not responding` | `docker compose restart litellm`, wait 15s |
| `Grafana not reachable` | `docker compose up -d grafana`, wait 20s |

WARN messages are advisory — they do not cause non-zero exit.

## Rules

- Do not skip steps. Do not improvise. Do not launch opencode.
- If `git pull` fails during upgrade, ask: "Reset to origin/main? (y/n)".
- If anything is unclear, ask the user before proceeding.
