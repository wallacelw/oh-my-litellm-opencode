---
name: oh-my-litellm-opencode
description: Deploy LiteLLM proxy (litellm + postgres + prometheus + grafana) routing through Huawei MaaS with multi-key load balancing, then bootstrap opencode + oh-my-opencode-slim with virtual key and 4 presets.
---

# oh-my-litellm-opencode — Deterministic Install Procedure

Deploy LiteLLM proxy → bootstrap opencode → mint virtual key → configure. **Idempotent.**

For reference documentation (architecture, presets, models, repair), see
**[REFERENCE.md](./REFERENCE.md)**.

---

## Section A: Idempotency & Re-run Contract

- If any step's precondition is already met, skip the action and verify the
  postcondition.
- The entire procedure is safe to re-run from any step.
- Re-running never destroys data or regenerates immutable secrets
  (`LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`).
- Only `1_init_env.sh --auto --force` regenerates secrets (for key rotation).
  Never do this unless explicitly rotating keys.

---

## Section B: Key Contract

| Env var | Set by | Read by | Format | Immutable? |
|---------|--------|---------|--------|------------|
| `HUAWEI_MAAS_API_KEY` | User (prompted, Step 5) | `1_init_env.sh`, `3a_install_opencode.sh` | Non-empty, no placeholders, validated via live API call | No |
| `HUAWEI_MAAS_API_KEY_COUNT` | Agent (Step 7) → recalculated by `0_bootstrap.sh` | `1_init_env.sh`, `2_generate_config.sh` | Integer ≥ 1 | No |
| `HUAWEI_MAAS_API_KEY_0` | `0_bootstrap.sh` (auto, = main key) | `1_init_env.sh`, `2_generate_config.sh` | Non-empty | No |
| `HUAWEI_MAAS_API_KEY_1..N` | User (prompted, Step 5) → agent exports (Step 7) | `0_bootstrap.sh` → `1_init_env.sh` | Non-empty | No |
| `LITELLM_MASTER_KEY` | `1_init_env.sh` (auto-generated) | `0_bootstrap.sh`, `3a_install_opencode.sh`, `3b_install_codex.sh` | Must start with `sk-` | **Yes** — changing invalidates all virtual keys |
| `LITELLM_SALT_KEY` | `1_init_env.sh` (auto-generated) | LiteLLM container | Random string | **Yes** — changing invalidates all virtual keys |
| `DB_PASSWORD` | `1_init_env.sh` (auto-generated) | docker-compose, postgres | Random string | **Yes** — changing breaks DB auth |
| `GRAFANA_ADMIN_PASSWORD` | `1_init_env.sh` (auto-generated) | docker-compose, `5_validate.sh` | Random string | No — rotating changes dashboard login only |
| `PROMETHEUS_RETENTION` | `1_init_env.sh` (default `30d`) | docker-compose | Prometheus duration (`Nd`/`Nh`/`Nw`), ≥ `7d` | No |
| `CODEX_VIRTUAL_KEY` | `3b_install_codex.sh` (minted) | `~/.codex/.env` as `LITELLM_CODEX_API_KEY` | Virtual key starting with `sk-` | No — tied to `LITELLM_MASTER_KEY` |
| `HUAWEI_MAAS_ANTHROPIC_API_BASE` | `1_init_env.sh` (default `https://api-ap-southeast-1.modelarts-maas.com/anthropic`) | `2_generate_config.sh` | URL | No |
| `CLAUDE_CODE_VIRTUAL_KEY` | `3c_install_claude_code.sh` (minted) | `~/.claude-code/.env` as `ANTHROPIC_API_KEY` | Virtual key starting with `sk-` | No — tied to `LITELLM_MASTER_KEY` |

**Rules:**

- Agent must NOT set `HUAWEI_MAAS_API_KEY_0` — bootstrap sets it from the main
  key automatically.
- Agent must export `HUAWEI_MAAS_API_KEY_COUNT` = 1 + number of extra keys.
- Agent must export `HUAWEI_MAAS_API_KEY_1` through `HUAWEI_MAAS_API_KEY_N` for
  extra keys only.

---

## Section C: Installation Procedure

Execute every step in order. For each step: check **precondition** → run
**action** → verify **postcondition**. If a step fails, run the documented
**on failure** recovery. If recovery also fails, stop and report to the user.

### Step 1: Detect Environment

**Precondition:** Agent has filesystem and shell access on a Linux machine.

**Action:**

```bash
uname -s   # must print "Linux"
```

Prompt user: `"Enter install directory (default: /home/oh-my-litellm-opencode):"`

If user presses Enter or provides no input, set
`PROJECT_DIR="/home/oh-my-litellm-opencode"`. Otherwise set `PROJECT_DIR` to
the user's input.

If creating `$PROJECT_DIR` fails with permission denied:

```bash
sudo mkdir -p "$PROJECT_DIR" && sudo chown "$USER" "$PROJECT_DIR"
```

Prompt user: `"Full install (LiteLLM + opencode) or LiteLLM-only? (default: full)"`

If user presses Enter or chooses full: `INSTALL_MODE="full"`.
If user chooses LiteLLM-only: `INSTALL_MODE="litellm-only"`.

**Postcondition:** `uname -s` prints `Linux` AND `$PROJECT_DIR` is set and
writable (`touch "$PROJECT_DIR/.test" && rm "$PROJECT_DIR/.test"` succeeds)
AND `$INSTALL_MODE` is set to `full` or `litellm-only`.

**On failure:** If OS is not Linux: stop and report "This procedure supports
Linux only." If dir creation fails even with sudo: escalate.

---

### Step 2: Verify & Install Prerequisites

**Precondition:** Step 1 passed.

**Action:**

Check each tool:

```bash
command -v bun     && bun --version          # only if INSTALL_MODE=full
command -v jq      && jq --version           # only if INSTALL_MODE=full
command -v git     && git --version
command -v python3 && python3 --version
command -v curl    && curl --version
command -v docker  && docker --version
docker compose version              # V2 plugin
command -v sudo                     # sudo available
```

> **Note:** `bun` and `jq` are NOT required when `INSTALL_MODE=litellm-only`.
> They are only used by `3a_install_opencode.sh` (opencode plugin install) and
> `5_validate.sh` Section B (opencode config checks), both skipped in
> LiteLLM-only mode.

Collect all missing tools. If any are missing:

1. List all missing tools to the user.
2. Ask: `"OK to install all missing prerequisites? (y/n)"`
3. If user declines: stop and report "Prerequisites are required. Install them
   manually and re-run from Step 1."
4. If user approves, install each missing tool:

   First, refresh the package index (required on fresh systems):
   ```bash
   sudo apt-get update
   ```

   Then install each:
   - `bun`:            `curl -fsSL https://bun.sh/install | bash`
   - `jq`:             `sudo apt-get install -y jq`
   - `git`:            `sudo apt-get install -y git`
   - `python3`:        `sudo apt-get install -y python3`
   - `curl`:           `sudo apt-get install -y curl`
   - `docker`:         `curl -fsSL https://get.docker.com | sudo sh`
   - `docker compose`: If `docker` exists but `docker compose version` fails:
                         `sudo apt-get install -y docker-compose-v2`
   - `sudo`:           If missing and running as root (`id -u` = 0), run
                         commands directly without sudo. If missing and not root:
                         escalate "sudo is required but not installed."

After installing bun, source the bun env so it's on PATH:

```bash
export PATH="$HOME/.bun/bin:$PATH"
```

> **Note:** opencode is NOT a prerequisite. It is installed automatically during
> Step 7 (bootstrap → `3a_install_opencode.sh`). Do not install it separately.

**Postcondition:** All of the following succeed:

```bash
command -v bun && command -v jq && command -v git \
  && command -v python3 && command -v curl \
  && command -v docker && docker compose version
```

**On failure:** Report which tool failed to install. Escalate.

---

### Step 3: Ensure Docker Daemon

**Precondition:** Step 2 passed (`docker` and `docker compose` are installed).

**Action:**

```bash
docker info >/dev/null 2>&1
```

If that fails:

```bash
sudo systemctl start docker
```

Wait 5 seconds, retry `docker info`.

**Postcondition:** `docker info` exits 0.

**On failure:** Escalate: `"Docker daemon won't start. Check: sudo journalctl -u docker --tail 20"`

---

### Step 4: Clone or Update Repository

**Precondition:** Steps 1–3 passed. `$PROJECT_DIR` is set.

**Action:**

If `$PROJECT_DIR` does not exist:

```bash
git clone https://github.com/wallacelw/oh-my-litellm-opencode "$PROJECT_DIR"
```

If `$PROJECT_DIR` exists with a `.git` dir:

Ask user: `"Existing installation found at $PROJECT_DIR. Update in-place or fresh install?"`

- **Update:**

  ```bash
  git -C "$PROJECT_DIR" pull --ff-only
  ```

  If pull fails (local changes or diverged history):

  Ask user: `"Pull failed. Reset to origin/main? (y/n)"`

  If yes: `git -C "$PROJECT_DIR" reset --hard origin/main`

- **Fresh:**

  ```bash
  cd "$PROJECT_DIR" && docker compose down -v
  cd /
  rm -rf "$PROJECT_DIR"
  git clone https://github.com/wallacelw/oh-my-litellm-opencode "$PROJECT_DIR"
  ```

**Postcondition:** `$PROJECT_DIR/scripts/0_bootstrap.sh` exists and is
executable (`test -x "$PROJECT_DIR/scripts/0_bootstrap.sh"`).

**On failure:** Escalate: `"Failed to clone repository. Check network connectivity and GitHub access."`

---

### Step 5: Collect & Validate MaaS Keys

**Precondition:** Step 4 passed.

**Action:**

Prompt user: `"What is your Huawei ModelArts MaaS API key? (region: ap-southeast-1, get from https://console.huaweicloud.com/modelarts/)"`

Set `MAAS_KEY` to the user's input.

Validate the key is non-empty and not a placeholder:

```bash
[ -n "$MAAS_KEY" ] \
  && [[ "$MAAS_KEY" != *"change-me"* ]] \
  && [[ "$MAAS_KEY" != *"xxx"* ]]
```

If invalid: re-prompt.

Validate the key works via a live API call against the same OpenAI-compatible
endpoint that LiteLLM will use:

```bash
curl -sf --max-time 30 -X POST \
  "https://api-ap-southeast-1.modelarts-maas.com/openai/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MAAS_KEY" \
  -d '{"model":"glm-5.2","messages":[{"role":"system","content":"You are a helpful assistant."},{"role":"user","content":"Ping! Answer with only Pong!"}]}'
```

If the API call fails: report `"The MaaS API key was rejected by the endpoint.
Verify the key at https://console.huaweicloud.com/modelarts/ and that the
region is ap-southeast-1."` Re-prompt for the key.

Prompt user: `"How many additional MaaS keys for load balancing? (default: 0)"`

If user enters 0 or presses Enter: `NUM_EXTRA_KEYS=0`, no extra keys.

If user enters N > 0: prompt for each key one-by-one:

```
"Enter extra MaaS API key #1 (1/N):"
"Enter extra MaaS API key #2 (2/N):"
...
```

Validate each extra key the same way as the main key (non-empty + live API
call). Store as `EXTRA_KEY_1` through `EXTRA_KEY_N`.

**Postcondition:** `MAAS_KEY` is set and validated via live API call.
`NUM_EXTRA_KEYS` is set (0 or positive integer).

**On failure:** If the live API call fails after 3 retries with the same key:
escalate `"MaaS API key validation failed. The key may be invalid, expired, or
the region is wrong."`

---

### Step 6: Check Ports Free

**Precondition:** Step 5 passed.

**Action:**

Check ports for all 4 services:

```bash
sudo ss -tlnp | grep -E ':(4000|5432|9090|3000) '
```

- **4000** — LiteLLM proxy
- **5432** — PostgreSQL
- **9090** — Prometheus
- **3000** — Grafana

If any port is in use: report to user `"Port X is in use by PID Y (process
name). Stop it or choose a different approach."` Wait for user to resolve. Do
NOT auto-kill.

**Postcondition:** `sudo ss -tlnp | grep -E ':(4000|5432|9090|3000) '` returns no output.

**On failure:** If user cannot free the ports: escalate `"Ports 4000, 5432,
9090, 3000 must be free for the stack."`

---

### Step 7: Run Bootstrap

**Precondition:** Steps 1–6 passed.

**Action:**

Export the key environment variables:

```bash
export HUAWEI_MAAS_API_KEY="$MAAS_KEY"
export HUAWEI_MAAS_API_KEY_COUNT="$((1 + NUM_EXTRA_KEYS))"
# Export extra keys (if any). Do NOT export HUAWEI_MAAS_API_KEY_0 —
# bootstrap sets it automatically from the main key.
export HUAWEI_MAAS_API_KEY_1="$EXTRA_KEY_1"   # if NUM_EXTRA_KEYS >= 1
export HUAWEI_MAAS_API_KEY_2="$EXTRA_KEY_2"   # if NUM_EXTRA_KEYS >= 2
# ... and so on for each extra key
```

Run the bootstrap:

```bash
cd "$PROJECT_DIR"
if [ "$INSTALL_MODE" = "litellm-only" ]; then
  ./scripts/0_bootstrap.sh --agent --litellm-only --maas-key="$MAAS_KEY"
elif [ "$INSTALL_MODE" = "opencode-only" ]; then
  ./scripts/0_bootstrap.sh --agent --opencode-only --maas-key="$MAAS_KEY"
elif [ "$INSTALL_MODE" = "codex-only" ]; then
  ./scripts/0_bootstrap.sh --agent --codex-only --maas-key="$MAAS_KEY"
elif [ "$INSTALL_MODE" = "claude-code-only" ]; then
  ./scripts/0_bootstrap.sh --agent --claude-code-only --maas-key="$MAAS_KEY"
else
  ./scripts/0_bootstrap.sh --agent --maas-key="$MAAS_KEY"
fi
```

This is idempotent — safe to re-run. In **full** mode it will:

1. Generate `.env` (preserving existing immutable secrets)
2. Generate `configs/litellm/config.yaml`
3. Start Docker Compose (LiteLLM + PostgreSQL + Prometheus + Grafana)
4. Install opencode + oh-my-opencode-slim plugin
5. Mint a virtual key (alias "opencode")
6. Write opencode config
7. Install Codex CLI + mint virtual key (alias "codex")
8. Write Codex CLI config (`~/.codex/config.toml` + `model_catalog.json` + `.env`)
9. Install Claude Code CLI + mint virtual key (alias "claude-code")
10. Write Claude Code CLI config (`~/.claude-code/.env`)
11. Run validation

In **LiteLLM-only** mode it will:

1. Generate `.env` (preserving existing immutable secrets)
2. Generate `configs/litellm/config.yaml`
3. Start Docker Compose (LiteLLM + PostgreSQL + Prometheus + Grafana)
4. Run validation (`--litellm-only`)

> **Notes:**
> - **Docker image pull:** Step 3 pulls 4 images: LiteLLM (~500 MB),
>   PostgreSQL (~50 MB), Prometheus (~200 MB), Grafana (~300 MB). On a slow
>   connection this can take several minutes. Do not timeout or report failure
>   during the pull — wait for `docker compose up -d` to complete.
> - **npm registry** (full mode only): Step 4 runs `bunx oh-my-opencode-slim
>   install` which downloads from the npm registry. If the registry is
>   unreachable, this fails with a network error.
> - **Git hooks:** Bootstrap configures `.githooks/pre-commit` to block
>   committing `.env` and secrets. This is a side effect — no action needed.
> - **Internal validation:** Bootstrap runs `5_validate.sh` internally as its
>   last step. Steps 8 and 9 below are postcondition confirmations of that
>   internal work, not new operations.

**Postcondition:** `0_bootstrap.sh` exits 0.

**On failure:** Run
`docker compose -f "$PROJECT_DIR/docker-compose.yml" logs litellm --tail 50`.
Escalate with the log output.

---

### Step 8: Wait for LiteLLM Healthy

**Precondition:** Step 7 passed.

**Action:**

```bash
# Poll every 5 seconds, up to 90 seconds
for i in $(seq 1 18); do
  if curl -sf -m 15 "http://127.0.0.1:4000/health/liveliness" >/dev/null 2>&1; then
    echo "LiteLLM healthy"
    break
  fi
  sleep 5
done
```

**Postcondition:** `curl -sf http://127.0.0.1:4000/health/liveliness` returns
HTTP 200.

**On failure:** Run
`docker compose -f "$PROJECT_DIR/docker-compose.yml" logs litellm --tail 50`.
Escalate with log output.

---

### Step 9: Run Validation

**Precondition:** Step 8 passed.

**Action:**

```bash
cd "$PROJECT_DIR"
if [ "$INSTALL_MODE" = "litellm-only" ]; then
  ./scripts/5_validate.sh --litellm-only
else
  ./scripts/5_validate.sh
fi
```

**Postcondition:** `5_validate.sh` exits 0 (all checks pass).

**On failure:** Parse the FAIL lines from the output. Match on **keywords**
(not exact strings) to find the recovery action:

| FAIL line contains | Recovery |
|--------------------|----------|
| `.env not found` | Re-run from Step 7 |
| `services running` and count `< 4` | `docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d`, wait 30s, retry Step 9 |
| `liveness probe` and not `200` | Re-run from Step 8 |
| `opencode not found` | `curl -fsSL https://opencode.ai/install \| bash`, retry Step 9 |
| `Model catalog not reachable` | Check virtual key in `~/.config/opencode/opencode.jsonc`, re-run from Step 7 |
| `smoke test` and `did not respond` | Re-validate MaaS key via Step 5's API call. If key is valid, escalate. |
| `Prometheus not reachable` | `docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d prometheus`, wait 10s, retry Step 9 |
| `rules not loaded` | Check `configs/prometheus/rules.yml` and `configs/prometheus/alerts.yml` syntax: `docker compose logs prometheus --tail 20` |
| `Grafana not reachable` | `docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d grafana`, wait 20s, retry Step 9 |
| `dashboard not found` | Check provisioning: `docker compose logs grafana --tail 20` |
| `claude not found` | `npm install -g @anthropic-ai/claude-code`, retry Step 9 |
| `Messages API smoke test` and `did not respond` | Check virtual key in `~/.claude-code/.env`, verify Anthropic endpoint in config.yaml |

> **Note:** `unhealthy_count > 0` is a **warning** in `5_validate.sh`, not a
> failure — it does not cause a non-zero exit. If you see this warning, monitor
> it but proceed. If inference fails later (smoke test), then investigate MaaS
> key/model/region validity.

After running the recovery command, re-run `5_validate.sh` **once**. If it
still fails: escalate with the full validation output. Do not loop recovery
more than once.

---

### Step 10: Print Summary

**Precondition:** Step 9 passed (validation exited 0).

**Action:** Report to the user:

If `INSTALL_MODE=full`:

```
=== Bootstrap complete ===

Project dir:       $PROJECT_DIR
LiteLLM proxy:     http://127.0.0.1:4000
LiteLLM Admin UI:  http://127.0.0.1:4000/ui
Grafana:           http://127.0.0.1:3000
Prometheus:        http://127.0.0.1:9090

Grafana login:
  Username:        admin
  Password:        grep GRAFANA_ADMIN_PASSWORD .env

opencode config:   ~/.config/opencode/opencode.jsonc
plugin config:     ~/.config/opencode/oh-my-opencode-slim.json
Codex CLI config:  ~/.codex/config.toml
Codex catalog:     ~/.codex/model_catalog.json
Codex API key:     ~/.codex/.env
Claude Code config: ~/.claude-code/.env

Next steps:
  1. Restart opencode to apply the new configuration:
       - Exit any running opencode session (Ctrl+C or /exit)
       - Start fresh: opencode
  2. Switch preset: /preset LiteLLM-Huawei-MaaS-Core
  3. Or use Codex CLI: codex
  4. Or use Claude Code CLI: source ~/.claude-code/.env && claude
```

If `INSTALL_MODE=litellm-only`:

```
=== Bootstrap complete ===

Project dir:       $PROJECT_DIR
LiteLLM proxy:     http://127.0.0.1:4000
LiteLLM Admin UI:  http://127.0.0.1:4000/ui
Grafana:           http://127.0.0.1:3000
Prometheus:        http://127.0.0.1:9090

Grafana login:
  Username:        admin
  Password:        grep GRAFANA_ADMIN_PASSWORD .env

Mode:              LiteLLM-only (no opencode)

Next steps:
  1. LiteLLM Admin UI: http://127.0.0.1:4000/ui
  2. To add opencode later:
     ./scripts/0_bootstrap.sh --maas-key="$MAAS_KEY"
  3. Or mint a virtual key only:
     ./scripts/4_mint-virtual-key.sh
```

**Security warning (agent mode only):**

If the install was run via `--agent` (keys passed via command line / environment
variables), append this warning to the summary:

```
⚠️  Security: API keys were shared with the agent via command line
   and environment variables. Rotate them to prevent unauthorized use.

  1. Get new MaaS key(s) from https://console.huaweicloud.com/modelarts/
  2. Edit .env: replace HUAWEI_MAAS_API_KEY and HUAWEI_MAAS_API_KEY_1..N
  3. Regenerate config: ./scripts/2_generate_config.sh
  4. Restart LiteLLM:  docker compose restart litellm
  5. Re-validate:      ./scripts/5_validate.sh [--litellm-only if applicable]
```

For `INSTALL_MODE=full`, also add:

```
  Note: Virtual key is still valid — it's tied to LITELLM_MASTER_KEY,
  not MaaS keys. No need to re-mint unless you also rotate the master key.
```

Do NOT show this warning for interactive (non-agent) installs — the human
typed the keys directly, they were not shared with an agent.

**Restart opencode (full mode only):** If opencode was already running,
the user must exit it (`/exit` or Ctrl+C) and start fresh (`opencode`) to
pick up the new configuration. The slim plugin and preset changes are not
hot-reloaded.

**Postcondition:** Summary printed. Installation is complete.

**On failure:** N/A — this is the terminal step.

---

**The install is complete when Step 9 (`5_validate.sh`) exits 0.** Step 10 is
informational only. Do NOT launch `opencode` — that is the user's next action.

---

## Section D: Upgrade Procedure

When the project is already installed and needs updating to a newer version,
follow Section C but with these modifications:

| Step | Fresh install | Upgrade |
|------|--------------|---------|
| 1 | Detect environment + prompt install dir | Detect existing install dir (look for `$PROJECT_DIR/.git`) |
| 2 | Verify & install prerequisites | Quick verify only (prereqs already installed) |
| 3 | Ensure Docker daemon | Quick verify only |
| 4 | Clone | `git -C "$PROJECT_DIR" pull --ff-only` (update in-place) |
| 5 | Prompt for MaaS key + validate | Read `HUAWEI_MAAS_API_KEY` from `$PROJECT_DIR/.env` — do NOT prompt |
| 6 | Check ports free | Skip — ports are in use by existing containers (expected) |
| 7 | Run bootstrap | Same — `0_bootstrap.sh` is idempotent, preserves all secrets |
| 8–10 | Same | Same |

**Key points:**

- Bootstrap is idempotent — it preserves `LITELLM_MASTER_KEY`,
  `LITELLM_SALT_KEY`, `DB_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`, and
  `PROMETHEUS_RETENTION` from the existing `.env`.
- Config is regenerated from templates — any new config options (e.g.
  observability settings) are picked up automatically.
- Docker Compose recreates containers as needed — existing data volumes
  (`postgres_data`, `prometheus_data`, `grafana_data`) are preserved.
- If `git pull` fails due to local changes: ask user
  `"Pull failed. Reset to origin/main? (y/n)"`. If yes:
  `git -C "$PROJECT_DIR" reset --hard origin/main`.
- **Grafana dashboard updates:** If the dashboard JSON changed in the
  update, hard-restart the Grafana container to pick up provisioning:
  `docker compose -f "$PROJECT_DIR/docker-compose.yml" restart grafana`
  (Grafana with `allowUiUpdates: true` won't overwrite UI-modified
  dashboards with provisioned ones on its own).

**Upgrade is complete when `5_validate.sh` exits 0.**

**Post-upgrade: restart opencode.** If opencode is running, exit it
(`/exit` or Ctrl+C) and start fresh (`opencode`) to pick up the new
configuration. The slim plugin and preset changes are not hot-reloaded.

**Grafana access:** `http://127.0.0.1:3000` — username `admin`,
password `grep GRAFANA_ADMIN_PASSWORD .env`.
