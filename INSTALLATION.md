# Installation

Complete reference for the installation process: the pipeline, what every
script does, ordering, flags, environment variables, prerequisites, the
loose-coupling contract, recovery, and upgrade procedure.

For a human-friendly overview, see [README.md](./README.md). For the
agent-facing install procedure, see [SKILL.md](./SKILL.md). For architecture
and config reference, see [REFERENCE.md](./REFERENCE.md).

---

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

That's it. Bootstrap clones itself into `/home/oh-my-coding-maas-gateway`
(or a directory you choose), shows a colored menu to select what to install,
and prompts for your Huawei MaaS API key. For each secret, it offers an
auto-generated value or custom entry. Prerequisites are installed
automatically as needed.

**Prefer to clone first?** Equivalent:

```bash
git clone https://github.com/wallacelw/oh-my-coding-maas-gateway /home/oh-my-coding-maas-gateway
cd /home/oh-my-coding-maas-gateway
./scripts/bootstrap.sh
```

Non-interactive (CI or agent driving stdin):

```bash
HUAWEI_MAAS_API_KEY=$KEY ./scripts/bootstrap.sh --tool=opencode
```

---

## Pipeline

Bootstrap is a thin sequencer. It resolves the tool selection, ensures core
prerequisites, then runs the numbered steps in order. Each step owns one
domain and is independently runnable.

| Order | Script | Domain | Optional | Description |
|-------|--------|--------|----------|-------------|
| — | `bootstrap.sh` | Orchestration | — | Entry point. Selection → core prereqs → dispatch steps → summary. |
| 01 | `01_env.sh` | Environment & secrets | no | Generate/update `.env` (immutable secrets, MaaS keys, endpoints); configure git hooks. |
| 02 | `02_litellm.sh` | LiteLLM proxy + observability | no | Generate `config.yaml`; port check; Docker Compose up (LiteLLM + PostgreSQL + Prometheus + Grafana); wait for health. |
| 03 | `03_opencode.sh` | opencode | yes | Install opencode + oh-my-opencode-slim plugin; mint virtual key; write config. |
| 04 | `04_codex.sh` | Codex CLI | yes | Install Codex CLI; mint virtual key; write config + model catalog. |
| 05 | `05_claude_code.sh` | Claude Code CLI | yes | Install Claude Code CLI; mint virtual key; write settings; disable VSCode extension. |
| 06 | `06_validate.sh` | Validation | no | End-to-end validation of all installed components. |

### Ordering

`01 env` (everything needs `.env`) → `02 litellm` (tools need the proxy live)
→ `03/04/05` tools (independent, optional, any relative order) → `06 validate`
(last, checks everything).

### Helpers (`scripts/helpers/`)

Shared libraries sourced by the pipeline steps. Not run directly.

| File | Used by | Provides |
|------|---------|----------|
| `prereqs.sh` | all steps | `prereq_ensure_apt`, `prereq_ensure_bun`, `prereq_ensure_npm`, `prereq_ensure_docker`. Each install labeled with `[LOG_TAG]`. |
| `keys.sh` | 03/04/05 | `resolve_master_key` (env → `.env` → prompt), `mint_or_reuse_key` (alias lookup + mint). |
| `common.sh` | all scripts | `source_env`, `retry_curl`, `strip_jsonc`, `mask_key`, logging (`log_step`, `log_ok`, `log_info`, `log_warn`, `log_error`, `log_dim`, `log_action`), prompts (`prompt_yesno`, `prompt_input`, `prompt_password`), `run_filtered` (subprocess output filtering). |

---

## Per-script details

### `bootstrap.sh`

The only script a human runs. Prompts for an install directory (default:
current parent, or `/home` if standalone). If running standalone (no repo
detected), clones the repo to the target location and re-execs. Parses
`--tool=`, `--virtual-key=`, `--dry-run`. Ensures core prerequisites (git,
python3, curl, jq). Shows a colored tool-selection menu if `--tool=` is not
given. Prints a prerequisite→tools mapping for customer validation. Dispatches
steps 01–06. Prints a colored summary with service URLs, config file paths,
masked virtual keys, a security warning, and advice to restart the shell.

### `01_env.sh`

Owns `.env`. For each secret (`LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`,
`DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`, `PROMETHEUS_RETENTION`), prompts to
use an auto-generated value or enter a custom one (non-interactive defaults to
auto-generated). On re-run, preserves existing secrets (idempotent).
Collects the Huawei MaaS API key from the `HUAWEI_MAAS_API_KEY` environment
variable or an interactive prompt. Collects extra keys for load balancing from
`HUAWEI_MAAS_API_KEY_1..N` / `HUAWEI_MAAS_API_KEY_COUNT` env vars or a prompt.
Configures git hooks to block committing secrets. `--force` regenerates all
secrets (for key rotation).

### `02_litellm.sh`

Generates `configs/litellm/config.yaml` from `.env` — N deployments per model
per format (dual OpenAI + Anthropic), 12N total. Checks ports 4000/5432/9090/
3000 are free. Runs `docker compose up -d` (LiteLLM + PostgreSQL + Prometheus
+ Grafana). Waits up to 90s for LiteLLM to become healthy. Supports
`--routing-strategy=` and `--dry-run`.

### `03_opencode.sh`

Installs the opencode binary (via curl, output filtered with `run_filtered`),
the oh-my-opencode-slim plugin (v2.0.5, via bunx — 4 presets, 7 agents, output
filtered to suppress GitHub star prompts), mints a virtual key (alias
"opencode"), and writes `~/.config/opencode/opencode.json` +
`oh-my-opencode-slim.json`. Supports `--virtual-key=` and `--dry-run`.

### `04_codex.sh`

Installs the OpenAI Codex CLI (via npm), mints a virtual key (alias "codex"),
and writes `~/.codex/config.toml` (custom `litellm_proxy` provider,
`wire_api=responses`), `model_catalog.json`, and `.env` with the API key.
Supports `--virtual-key=` and `--dry-run`.

### `05_claude_code.sh`

Installs the Claude Code CLI (via npm), mints a virtual key (alias
"claude-code"), writes `~/.claude/settings.json` (env block pointing to the
LiteLLM proxy via the Anthropic Messages API), and disables the VSCode
extension auto-install. Supports `--virtual-key=` and `--dry-run`.

### `06_validate.sh`

Validates all installed components in sections A–E + observability:
`.env` completeness, Docker services, LiteLLM health + config, Prometheus +
Grafana, and each tool's config + API smoke test. Supports `--dry-run`,
`--litellm-only`/`--opencode-only`/`--codex-only`/`--claude-code-only`
(scoped), and `--skip-opencode`/`--skip-codex`/`--skip-claude-code` (additive).

---

## Flags

### `bootstrap.sh`

| Flag | Effect |
|------|--------|
| `--tool=VAL` | `all` (default), `litellm`, `opencode`, `codex`, `claude`, or comma combo (e.g. `opencode,codex`). Skips the menu. |
| `--virtual-key=sk-...` | Reuse an existing opencode virtual key, skip minting. |
| `--dry-run` | Preview actions without modifying anything. |

### `01_env.sh`

| Flag | Effect |
|------|--------|
| `--force` | Regenerate all immutable secrets (for key rotation). Invalidates existing virtual keys. |

### `06_validate.sh`

| Flag | Effect |
|------|--------|
| `--dry-run` | Structure checks only, no network calls. |
| `--litellm-only` | Only LiteLLM proxy checks. |
| `--opencode-only` | Only opencode config checks. |
| `--codex-only` | Only Codex CLI config checks. |
| `--claude-code-only` | Only Claude Code CLI config checks. |
| `--skip-opencode` | Skip opencode checks (additive). |
| `--skip-codex` | Skip Codex checks (additive). |
| `--skip-claude-code` | Skip Claude Code checks (additive). |

The `--xxx-only` flags are mutually exclusive. The `--skip-*` flags combine
with anything.

---

## Environment Variables

These control the install when set before running `bootstrap.sh`. When
absent, the scripts prompt interactively (or error in non-interactive mode).

| Variable | Purpose | Read by |
|----------|---------|---------|
| `HUAWEI_MAAS_API_KEY` | Main Huawei MaaS API key (region ap-southeast-1). | `01_env.sh`, `03_opencode.sh` |
| `HUAWEI_MAAS_API_KEY_COUNT` | Total number of MaaS keys (1 + extras). | `01_env.sh`, `02_litellm.sh` |
| `HUAWEI_MAAS_API_KEY_1..N` | Extra MaaS keys for load balancing. | `01_env.sh`, `02_litellm.sh` |
| `LITELLM_MASTER_KEY` | LiteLLM master key (resolved from env or `.env`). | `03/04/05` via `helpers/keys.sh` |

All other secrets (`LITELLM_SALT_KEY`, `DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`,
`PROMETHEUS_RETENTION`) are auto-generated by `01_env.sh` and stored in `.env`.

---

## Colored Output & Action Labels

All scripts use a shared logging system from `helpers/common.sh`:

- **Colors** auto-enable on TTY, disable on piped/CI output.
- `log_step` — bold cyan section headers (`━━━ Step 01 — ... ━━━`)
- `log_ok` / `log_info` / `log_warn` / `log_error` — green ✓ / blue → / yellow ⚠ / red ✗
- `log_dim` — dim secondary text
- `log_action "who" "msg"` — dim `[tag]` prefix showing who's acting

Each script sets a `LOG_TAG` (e.g. `bootstrap`, `env`, `litellm`, `opencode`,
`codex`, `claude`, `validate`). Prerequisite installs are labeled:
`→ [opencode] Installing curl (curl)...`.

Third-party subprocess output is filtered via `run_filtered` — suppresses
GitHub star prompts, npm warnings, and deprecation notices, showing remaining
lines with a dim `[tag]` prefix.

### Interactive Prompts

- `prompt_yesno "question" [y|n]` — colored `? Question [Y/n]`, auto-defaults on non-TTY
- `prompt_input "question" [default]` — colored input with default hint
- `prompt_password "label" "auto_value"` — shows masked auto-generated preview, offers custom entry

In `01_env.sh`, each secret prompts: "Use auto-generated value? [Y/n]" or
enter custom. Non-interactive defaults to auto-generated.

---

## Prerequisites

**OS:** Linux (Debian/Ubuntu with systemd recommended).

Prerequisites are installed **just-in-time, driven by selection**. Each step
ensures only its own prerequisites; skipped steps install nothing. A
`--tool=litellm` install never installs bun, npm, or bubblewrap.

| Step | Ensures |
|------|---------|
| `bootstrap.sh` | git, python3, curl, jq |
| `01_env.sh` | python3, git |
| `02_litellm.sh` | curl, docker + compose + daemon |
| `03_opencode.sh` | curl, jq, bun |
| `04_codex.sh` | curl, npm/node, jq, bubblewrap |
| `05_claude_code.sh` | curl, npm/node, jq |
| `06_validate.sh` | curl, jq |

Interactive mode prompts before each installation. Non-interactive shells
(piped stdin, CI) auto-confirm. Each install is labeled with `[LOG_TAG]`
showing which script triggered it. Bootstrap prints a **prereq→tools mapping**
at the start for customer validation (e.g. `curl — bootstrap, litellm,
validate, opencode, codex, claude`). **Non-Debian systems** (RHEL, Alpine,
Arch): install equivalent packages manually — Docker daemon start requires
systemd.

---

## Loose-Coupling Contract

- Every step **self-sources `.env`** via `helpers/common.sh:source_env`. No
  script depends on another script's exports.
- Every step is **independently runnable** — e.g. `./scripts/03_opencode.sh`
  works standalone (sources `.env`, resolves the master key, mints, writes
  config).
- **Optional steps (03/04/05)** are skipped per `--tool=`; skipping never
  breaks later steps. `06_validate.sh` receives `--skip-*` for skipped tools.
- Idempotent — safe to re-run. Immutable secrets are preserved; existing
  containers, configs, and valid virtual keys are reused.

---

## Idempotency & Re-run

- If any step's precondition is already met, it skips and verifies the
  postcondition.
- Safe to re-run from any step. Never destroys data or regenerates immutable
  secrets (`LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`).
- Only `01_env.sh --force` regenerates secrets (for key rotation).

---

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

WARN messages (e.g. `litellm_config.yaml not found`, `unhealthy_count > 0`,
deployment drift) do NOT cause non-zero exit — they are advisory.

After recovery, re-run `06_validate.sh` **once**. If it still fails, escalate
with full output.

---

## Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash
```

Same one-liner as install — bootstrap detects the existing repo, pulls
updates, and re-runs idempotently. Equivalent manual form:

```bash
cd /home/oh-my-coding-maas-gateway
git pull
./scripts/bootstrap.sh
```

- Bootstrap preserves `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`,
  `GRAFANA_ADMIN_PASSWORD`, `PROMETHEUS_RETENTION` from existing `.env`.
- Config is regenerated from templates — new options picked up automatically.
- Docker Compose recreates containers; data volumes preserved.
- If `git pull` fails: ask "Reset to origin/main? (y/n)".
- **Grafana dashboard updates:** hard-restart to pick up provisioning:
  `docker compose restart grafana`.

After upgrade, restart opencode if it's running (exit with `/exit` or Ctrl+C,
start fresh — plugin/preset changes are not hot-reloaded).

**Upgrade is complete when `06_validate.sh` exits 0.**

---

## After Install

Restart your shell (or open a new terminal) to clear exported environment
variables and apply all changes:

```bash
exec "$SHELL"
```

Then run your coding tool:

```bash
opencode          # or: codex  or:  claude --bare
```
