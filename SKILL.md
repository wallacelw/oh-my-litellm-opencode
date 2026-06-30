---
name: oh-my-coding-maas-gateway
description: Deploy LiteLLM proxy (litellm + postgres + prometheus + grafana) routing through Huawei MaaS with multi-key load balancing, then bootstrap opencode + Codex CLI + Claude Code CLI with virtual keys and 4 presets.
---

# oh-my-coding-maas-gateway — Deterministic Install Procedure

Deploy LiteLLM proxy → bootstrap opencode + Codex CLI + Claude Code CLI → mint virtual keys → configure. **Idempotent.**

For reference documentation (architecture, env vars, presets, models, repair),
see **[REFERENCE.md](./REFERENCE.md)**.

---

## Bootstrap Flags

| Flag | Effect |
|------|--------|
| `--maas-key=KEY` | Non-interactive MaaS key (skips prompt) |
| `--agent` | Agent mode: fail-fast, no prompts, auto-install prereqs |
| `--tool=VAL` | `all` (default), `litellm`, `opencode`, `codex`, `claude`, or comma combo (e.g. `opencode,codex`) |
| `--virtual-key=sk-...` | Use existing virtual key, skip minting |
| `--dry-run` | Preview actions without modifying anything |

Legacy aliases: `--litellm-only`, `--opencode-only`, `--codex-only`,
`--claude-code-only` (map to `--tool=litellm|opencode|codex|claude`).

---

## Idempotency & Re-run Contract

- If any step's precondition is already met, skip and verify postcondition.
- Safe to re-run from any step. Never destroys data or regenerates immutable
  secrets (`LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`).
- Only `1_init_env.sh --auto --force` regenerates secrets (for key rotation).

---

## Installation Procedure

8 steps in 4 phases. For each step: check **precondition** → run **action** →
verify **postcondition**. If a step fails, run the documented recovery. If
recovery also fails, escalate.

### Phase 1: Pre-flight

#### Step 1: Verify Environment

**Precondition:** Agent has filesystem and shell access on a Linux machine.

**Action:**

```bash
uname -s   # must print "Linux"
```

Set `PROJECT_DIR` (default: `/home/oh-my-coding-maas-gateway`). If the
directory doesn't exist and creation fails with permission denied:

```bash
sudo mkdir -p "$PROJECT_DIR" && sudo chown "$USER" "$PROJECT_DIR"
```

**Postcondition:** `uname -s` prints `Linux` AND `$PROJECT_DIR` is writable.

**On failure:** Non-Linux: stop. Dir creation fails even with sudo: escalate.

---

#### Step 2: Ensure Prerequisites

**Precondition:** Step 1 passed.

**Action:**

Bootstrap ensures its own prerequisites via `scripts/lib/prereqs.sh`:

```bash
prereq_ensure_apt "git"     git     git
prereq_ensure_apt "python3" python3 python3
prereq_ensure_apt "curl"    curl    curl
prereq_ensure_apt "jq"      jq      jq
```

If any are missing, they are installed automatically (`apt-get install -y`).
Interactive mode prompts before installing; agent mode (`--agent`) installs
without prompting.

**Distributed prerequisites** — each script ensures only what it needs:

| Script | Ensures |
|--------|---------|
| `0_bootstrap.sh` | git, python3, curl, jq |
| `1_init_env.sh` | python3 |
| `2_deploy_litellm.sh` | curl, docker + compose + daemon |
| `3_mint_key.sh` | curl, jq |
| `4a_install_opencode.sh` | curl, jq, bun |
| `4b_install_codex.sh` | curl, npm/node, jq, bubblewrap |
| `4c_install_claude_code.sh` | curl, npm/node, jq |
| `5_validate.sh` | curl, jq |

Scripts are independently runnable. Repeated installs are harmless (apt is
idempotent; the helper library tracks what's been ensured per process).

**Non-Debian systems:** The helper library uses `apt-get`. For other distros,
install the equivalent packages manually before running bootstrap:

| Package | Debian/Ubuntu | RHEL/Fedora | Alpine | Arch |
|---------|--------------|-------------|--------|------|
| git | `git` | `git` | `git` | `git` |
| python3 | `python3` | `python3` | `python3` | `python` |
| curl | `curl` | `curl` | `curl` | `curl` |
| jq | `jq` | `jq` | `jq` | `jq` |
| docker | `docker.io` | `docker` | `docker` | `docker` |
| node/npm | `nodejs npm` | `nodejs npm` | `nodejs npm` | `nodejs npm` |
| bubblewrap | `bubblewrap` | `bubblewrap` | `bubblewrap` | `bubblewrap` |

Docker daemon start uses `systemctl` (systemd required). On non-systemd
systems, start the Docker daemon manually before running bootstrap.

> **Note:** opencode is NOT a prerequisite — it's installed by Step 5.

**Postcondition:** `git`, `python3`, `curl`, `jq` are on PATH.

**On failure:** Report which tool failed to install. Escalate.

---

#### Step 3: Collect & Validate MaaS Keys

**Precondition:** Step 2 passed.

**Action:**

Prompt for Huawei ModelArts MaaS API key (region: ap-southeast-1). Validate
non-empty and not a placeholder:

```bash
[ -n "$MAAS_KEY" ] \
  && [[ "$MAAS_KEY" != *"change-me"* ]] \
  && [[ "$MAAS_KEY" != *"xxx"* ]]
```

If invalid: re-prompt.

Optionally collect N additional keys for load balancing. Validate each the
same way. Export:

```bash
export HUAWEI_MAAS_API_KEY="$MAAS_KEY"
export HUAWEI_MAAS_API_KEY_COUNT="$((1 + NUM_EXTRA_KEYS))"
export HUAWEI_MAAS_API_KEY_1="$EXTRA_KEY_1"   # if NUM_EXTRA_KEYS >= 1
# ... (do NOT export HUAWEI_MAAS_API_KEY_0 — bootstrap sets it automatically)
```

**Postcondition:** `MAAS_KEY` is non-empty and not a placeholder.
`NUM_EXTRA_KEYS` set.

**On failure:** If key is empty or placeholder after 3 re-prompts: escalate.

---

### Phase 2: Execute

#### Step 4: Select Install Scope

**Precondition:** Step 3 passed.

**Action:**

Interactive mode shows a numbered menu:

```
Select installation scope:
  1) Default — LiteLLM + opencode + Codex + Claude Code  [default]
  2) LiteLLM only
  3) LiteLLM + opencode
  4) LiteLLM + Codex
  5) LiteLLM + Claude Code
  6) Custom — toggle each component
```

Agent mode: pass `--tool=VAL` where VAL is `all` (default), `litellm`,
`opencode`, `codex`, `claude`, or a comma combo (e.g. `opencode,codex`).

**Postcondition:** `$INSTALL_TOOL` is set.

---

#### Step 5: Run Bootstrap

**Precondition:** Steps 1–4 passed.

**Action:**

```bash
cd "$PROJECT_DIR"
./scripts/0_bootstrap.sh --agent --tool="$INSTALL_TOOL" --maas-key="$MAAS_KEY"
```

Bootstrap is idempotent and handles internally:
- Docker engine + compose + daemon startup (via `prereq_ensure_docker`)
- Port conflict check (exits in agent mode if ports 4000/5432/9090/3000 in use)
- `.env` generation (preserving existing immutable secrets)
- `configs/litellm/config.yaml` generation
- Docker Compose stack start (LiteLLM + PostgreSQL + Prometheus + Grafana)
- Tool installs + virtual key minting + config writing (per selected scope)
- Internal validation (`5_validate.sh`)

**What bootstrap does by mode:**

| Mode | Actions |
|------|---------|
| `all` (default) | Deploy + install opencode + Codex + Claude Code + validate |
| `litellm` | Deploy + validate |
| `opencode` | Deploy + install opencode + validate |
| `codex` | Deploy + install Codex + validate |
| `claude` | Deploy + install Claude Code + validate |

**Notes:**
- Docker image pull: 4 images (~1 GB total). On slow connections, wait for
  `docker compose up -d` to complete — do not timeout.
- npm registry (tool installs): If unreachable, tool installs fail with
  network error.
- Git hooks: Bootstrap configures `.githooks/pre-commit` to block committing
  `.env` and secrets.

**Postcondition:** `0_bootstrap.sh` exits 0.

**On failure:** `docker compose logs litellm --tail 50`. Escalate with logs.

---

### Phase 3: Verify

#### Step 6: Verify LiteLLM Healthy

**Precondition:** Step 5 passed.

**Action:**

```bash
for i in $(seq 1 18); do
  curl -sf -m 15 "http://127.0.0.1:4000/health/liveliness" >/dev/null 2>&1 && break
  sleep 5
done
```

**Postcondition:** `curl -sf http://127.0.0.1:4000/health/liveliness` returns 200.

**On failure:** `docker compose logs litellm --tail 50`. Escalate with logs.

---

#### Step 7: Run Validation

**Precondition:** Step 6 passed.

**Action:**

```bash
cd "$PROJECT_DIR"
./scripts/5_validate.sh    # add --litellm-only / --opencode-only / etc. for scoped checks
```

**Postcondition:** `5_validate.sh` exits 0.

**On failure:** Parse FAIL lines, match on keywords, run recovery:

| FAIL pattern | Recovery |
|--------------|----------|
| `.env not found` / `placeholder value` | Re-run `1_init_env.sh --auto` then bootstrap |
| `services running` + `expected 4` | `docker compose up -d`, wait 30s, retry |
| `liveness probe returned` | `docker compose logs litellm --tail 50` |
| `Inference smoke test` + `did not respond` | Re-validate MaaS key; check logs |
| **opencode issues** (`opencode not found`, `opencode.json`, `oh-my-opencode-slim`, `No opencode config`, `No API key for model checks`, `Model catalog not reachable`) | Re-run `4a_install_opencode.sh` (or `curl -fsSL https://opencode.ai/install \| bash` if binary missing) |
| **Codex issues** (`codex not found`, `config.toml`, `No Codex config`, `base_url`, `env_key`, `wire_api`, `default model`) | Re-run `4b_install_codex.sh` (or `npm install -g @openai/codex` if binary missing) |
| **Claude Code issues** (`claude not found`, `settings.json`, `No Claude Code config`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `default model`) | Re-run `4c_install_claude_code.sh` (or `npm install -g @anthropic-ai/claude-code` if binary missing) |
| `Responses API smoke test` + `did not respond` | Check `~/.codex/.env` key; verify `/v1/responses` |
| `Messages API smoke test` + `did not respond` | Check `~/.claude/settings.json` key |
| `Prometheus not reachable` | `docker compose up -d prometheus`, wait 10s |
| `/metrics endpoint not responding` | `docker compose restart litellm`, wait 15s |
| `Prometheus scraping` + `target is down` | Check LiteLLM `/metrics` responds |
| `Grafana not reachable` | `docker compose up -d grafana`, wait 20s |

> **Note:** WARN messages (e.g. `litellm_config.yaml not found`, `dashboard
> not found`, `unhealthy_count > 0`, deployment drift) do NOT cause non-zero
> exit — they are advisory. Monitor but proceed.

After recovery, re-run `5_validate.sh` **once**. If it still fails: escalate
with full output. Do not loop recovery more than once.

---

### Phase 4: Confirm

#### Step 8: Confirm Summary

**Precondition:** Step 7 passed (validation exited 0).

**Action:**

Bootstrap prints a summary at the end of Step 5 containing:
- What was installed (conditional on mode)
- Service URLs: LiteLLM `:4000`, Grafana `:3000`, Prometheus `:9090`
- Coding agent activation commands + config paths + masked virtual keys
- Next steps

In agent mode (`--agent`), a security warning is appended:

```
⚠️  Security: API keys were shared with the agent via command line
   and environment variables. Rotate them to prevent unauthorized use.
```

Do NOT show this warning for interactive installs.

**Postcondition:** Summary printed. Installation is complete.

**On failure:** N/A — terminal step.

---

**The install is complete when Step 7 (`5_validate.sh`) exits 0.** Step 8 is
informational only. Do NOT launch `opencode` — that is the user's next action.

---

## Upgrade Procedure

When the project is already installed, follow the procedure above with these
modifications:

| Step | Fresh install | Upgrade |
|------|--------------|---------|
| 1 | Detect environment + prompt dir | Detect existing dir (look for `.git`) |
| 2 | Ensure prerequisites | Quick verify (prereqs already installed) |
| 3 | Prompt for MaaS key + validate | Read from `.env` — do NOT prompt |
| 4 | Select scope | Same |
| 5 | Run bootstrap | Same — idempotent, preserves all secrets |
| 6–8 | Same | Same |

**Key points:**

- Bootstrap preserves `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY`, `DB_PASSWORD`,
  `GRAFANA_ADMIN_PASSWORD`, `PROMETHEUS_RETENTION` from existing `.env`.
- Config regenerated from templates — new options picked up automatically.
- Docker Compose recreates containers; data volumes preserved.
- If `git pull` fails: ask user `"Reset to origin/main? (y/n)"`.
- **Grafana dashboard updates:** Hard-restart Grafana to pick up provisioning:
  `docker compose restart grafana` (Grafana won't overwrite UI-modified
  dashboards with provisioned ones on its own).

**Upgrade is complete when `5_validate.sh` exits 0.**

**Post-upgrade:** Restart opencode (exit with `/exit` or Ctrl+C, start fresh)
to pick up new config. Plugin/preset changes are not hot-reloaded.

**Grafana access:** `http://127.0.0.1:3000` (anonymous, no login).
