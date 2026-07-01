---
name: oh-my-coding-maas-gateway
description: Deploy LiteLLM proxy (litellm + postgres + prometheus + grafana) routing through Huawei MaaS with multi-key load balancing, then bootstrap opencode + Codex CLI + Claude Code CLI with virtual keys and 4 presets.
---

# oh-my-coding-maas-gateway — Agent Install Procedure

**Idempotent.** For full details, see **[INSTALLATION.md](./INSTALLATION.md)**.
For architecture and config, see **[REFERENCE.md](./REFERENCE.md)**.

## Flags

| Flag | Effect |
|------|--------|
| `--tool=VAL` | `all` (default), `litellm`, `opencode`, `codex`, `claude`, or comma combo. Skips menu. |
| `--virtual-key=sk-...` | Reuse existing opencode virtual key, skip minting. |
| `--dry-run` | Preview without changes. |

Env var overrides: `HUAWEI_MAAS_API_KEY`, `HUAWEI_MAAS_API_KEY_COUNT`,
`HUAWEI_MAAS_API_KEY_1..N` — skip prompts when set.

## Install

```bash
# Standalone (no clone needed):
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash

# Or from a clone:
./scripts/bootstrap.sh --tool=all
```

Bootstrap handles everything: install directory prompt (default `/home`),
prereq→tools summary, `.env` generation (prompts for each secret: auto or
custom), Docker stack, tool installs, virtual key minting, validation.

**You will need to ask the user for:**
- Install mode (default: all) — or pass `--tool=`
- Huawei MaaS API key (region ap-southeast-1) — or set `HUAWEI_MAAS_API_KEY`
- Number of extra MaaS keys for load balancing (default: 0)
- Sudo password if prompted

**Complete when `06_validate.sh` exits 0.** Do NOT launch opencode.

## Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Same one-liner as install — bootstrap detects the existing repo, pulls
updates, and re-runs idempotently. Read the MaaS key from `.env` — do NOT
ask the user. If `git pull` fails, ask: "Reset to origin/main? (y/n)".
Complete when `06_validate.sh` exits 0.

Post-upgrade: restart opencode if running (`/exit`, start fresh — plugin
changes are not hot-reloaded).

## Recovery

If `06_validate.sh` fails, match the FAIL pattern and run the recovery:

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

WARN messages do NOT cause non-zero exit — they are advisory. After recovery,
re-run `06_validate.sh` **once**. If it still fails, escalate with full output.

## Rules

- Do not skip steps. Do not improvise. Do not launch opencode.
- If an existing installation is found, ask: update in-place or fresh install.
- After install: user will rotate MaaS keys (they were shared with you).
