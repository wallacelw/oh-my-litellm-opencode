---
name: oh-my-coding-maas-gateway
description: Deploy LiteLLM proxy (litellm + postgres + prometheus + grafana) routing through Huawei MaaS with multi-key load balancing, then bootstrap opencode + Codex CLI + Claude Code CLI with virtual keys and 4 presets.
---

# oh-my-coding-maas-gateway — Agent Procedure

You are the intermediary between the user and bootstrap. Run bootstrap,
answer its prompts on stdin, handle failures, stop when validation passes.
Do NOT launch opencode.

Full details: **[INSTALLATION.md](./INSTALLATION.md)** ·
**[REFERENCE.md](./REFERENCE.md)**

## 1. Determine install or upgrade

Check if `/home/oh-my-coding-maas-gateway/.env` exists:

- **Missing → fresh install.** Ask the user for:
  - Huawei MaaS API key (region ap-southeast-1)
  - Install mode — all (default), litellm, opencode, codex, claude
  - Extra MaaS keys for load balancing (default: 0)
- **Exists → upgrade.** Read the MaaS key from `.env`. Do not ask the user.

## 2. Run bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Answer each prompt as bootstrap presents it. Pass `--tool=<mode>` to skip
the menu. If sudo prompts, ask the user for their password.

## 3. Verify

Done when `06_validate.sh` exits 0. If it fails, run the matching recovery
below, then re-validate **once**. If it still fails, stop and report.

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
- After completion: remind the user to rotate MaaS keys if shared.
