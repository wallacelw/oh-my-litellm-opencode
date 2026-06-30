# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **Distributed prerequisite installation** — each script now installs its own
  prerequisites via shared `scripts/lib/prereqs.sh` library instead of
  centralized check in `0_bootstrap.sh`. Scripts are independently runnable.
  `PREREQ_MODE=auto` (agent) installs without prompting; `prompt` asks first.
- `2_deploy_litellm.sh` now ensures Docker engine + compose plugin + daemon
  are running via `prereq_ensure_docker` (previously assumed pre-installed).
- Port check in `0_bootstrap.sh` now exits with error in `--agent` mode
  (previously only warned).
- **SKILL.md restructured** — 825 → 372 lines. 10 steps → 8 steps in 4 phases
  (Pre-flight, Execute, Verify, Confirm). Step 10 summary spec replaced with
  brief description. Recovery table grouped by script. Key Contract table
  moved to REFERENCE.md. Non-Debian package mapping table added.
- **README.md rewritten** — human-first comprehensive page. Architecture
  diagram, Quick Start, What You Get (service URLs + tool activation),
  install modes, prerequisites (auto-install), after-install usage guide,
  upgrade, troubleshooting, agent install prompts. 148 → 215 lines.
- REFERENCE.md: dashboard description updated (25→34 panels, 5m→15m),
  stale Prometheus rules repair entry removed, intro updated.

### Added

- `scripts/lib/prereqs.sh` — shared prerequisite installation helper library.
  Provides `prereq_ensure_apt`, `prereq_ensure_bun`, `prereq_ensure_npm`,
  `prereq_ensure_docker`. Idempotent, with sudo wrapper and apt-update-once.

### Removed

- Prometheus alerting rules (`alerts.yml`) — removed, no Alertmanager configured.
- Prometheus recording rules (`rules.yml`) — removed, no 7-day baselines needed.
- 7-day baseline lines from Grafana dashboard panels (TTFT, TPOT, RPM, TPM).
- `PROMETHEUS_RETENTION` minimum 7d requirement — any valid duration now accepted.
- "Annotations & Alerts" annotation from Grafana dashboard.

### Added

- Tool selection menu in `0_bootstrap.sh` — interactive 6-option menu
  (default all, litellm-only, litellm+opencode, litellm+codex, litellm+claude,
  custom toggle). Use `--tool=all|litellm|opencode|codex|claude` for
  non-interactive selection (comma-separated for custom combos).
  Legacy `--litellm-only`/`--opencode-only`/`--codex-only`/`--claude-code-only`
  flags still work as aliases.
- Just-in-time prerequisite checking in `0_bootstrap.sh` — core prereqs
  checked first, then tool-specific prereqs checked after selection.
- `--skip-opencode`/`--skip-codex`/`--skip-claude-code` flags for
  `5_validate.sh` (additive, combinable with existing --xxx-only flags).
- Claude Code CLI integration via `4c_install_claude_code.sh` — installs
  Claude Code CLI, mints virtual key (alias "claude-code", unlimited budget),
  writes `~/.claude/settings.json`, disables VSCode extension auto-install
  (`~/.claude.json` + `CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1`), uninstalls
  existing VSCode extension if present.
- `configs/claude-code/.env.template` — reference template documenting
  `~/.claude/settings.json` format (`env` block with `ANTHROPIC_BASE_URL`,
  `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`).
- Huawei MaaS Anthropic-compatible endpoint support
  (`HUAWEI_MAAS_ANTHROPIC_API_BASE`).
- `2_deploy_litellm.sh` now generates dual-format deployments: OpenAI
  (`openai/` prefix, `/openai/v1/chat/completions`) + Anthropic
  (`anthropic/` prefix, `/anthropic/v1/messages`) for all 6 models.
- `--claude-code-only` flag for `0_bootstrap.sh` and `5_validate.sh`.
- `CLAUDE_CODE_VIRTUAL_KEY` placeholder in `.env.template`.
- Validation Section E: Claude Code CLI checks (binary, config, provider,
  Messages API smoke test).
- Claude Code config written to `~/.claude/settings.json` (native settings
  file with `env` block, read automatically on startup — no
  `source`/`export` needed).
- `REFERENCE.md`: added Claude Code CLI section, Anthropic endpoint to
  architecture diagram and endpoints table, dual-format architecture
  documentation.

### Changed

- Total deployment count doubled: 6 OpenAI + 6 Anthropic per API key
  (12 × N total, was 6 × N).
- Anthropic deployments use `claude-` prefixed model names (e.g.,
  `claude-glm-5.2`) to avoid LiteLLM routing conflicts. OpenAI deployments
  keep base names (e.g., `glm-5.2`). Claude Code uses `claude-glm-5.2`
  as `ANTHROPIC_MODEL`.
- Script renumbering for modularity: `2_generate_config.sh` →
  `2_deploy_litellm.sh` (now also deploys Docker Compose),
  `4_mint-virtual-key.sh` → `3_mint_key.sh` (now precedes tool installs),
  `3a/3b/3c_install_*.sh` → `4a/4b/4c_install_*.sh`.

## [0.3.0] - 2026-06-28

### Added

- Codex CLI integration via `3b_install_codex.sh` — installs Codex CLI, mints
  virtual key, writes config + model catalog.
- `configs/codex/model_catalog.json` — metadata for all 6 Huawei MaaS models
  (context window, max output tokens, reasoning effort levels).
- `configs/codex/config.toml.template` — Codex CLI config with custom
  `litellm_proxy` model provider (`wire_api = "responses"`, HTTP SSE).
- `--codex-only` flag for `0_bootstrap.sh` and `5_validate.sh`.
- `CODEX_VIRTUAL_KEY` placeholder in `.env.template`.

### Changed

- LiteLLM models use `openai/` prefix with `use_chat_completions_api: true`
  (documented LiteLLM feature for bridging Responses API → Chat Completions).
- Codex CLI API key stored in `~/.codex/.env` (auto-loaded by Codex CLI via
  dotenvy) instead of shell profile or `auth.json`.
- `multi_agent` feature disabled in Codex CLI config (sends `type: "namespace"`
  tools that Huawei MaaS rejects).
- `3_install.sh` renamed to `3a_install_opencode.sh` for consistency with
  `3b_install_codex.sh`.
- opencode model keys use LiteLLM `model_name` directly (no `openai/` prefix).

### Fixed

- Codex CLI WebSocket transport avoided — LiteLLM v1.89.3 has a bug in the
  WebSocket Responses API bridge (`litellm_params` passed to
  `AsyncCompletions.create()`). Custom provider with `wire_api = "responses"`
  forces HTTP SSE.

## [0.2.0] - 2026-06-27

### Added

- Prometheus + Grafana observability stack with pre-provisioned 12-panel
  dashboard, 4 recording rules (7-day rolling baselines), and 3 alerting
  rules (TTFT anomaly, budget low, deployment outage).
- `PROMETHEUS_RETENTION` env var (default `30d`, min `7d`) — configurable
  Prometheus TSDB retention via `.env`.
- `GRAFANA_ADMIN_PASSWORD` auto-generated by `1_init_env.sh`, stored in
  `.env`, idempotent on re-run.
- Dashboard variables `$model` and `$api_key` with per-metric label mapping
  (`model` vs `requested_model` vs `litellm_model_name`).
- Validation Section C: 6 observability checks (Prometheus reachable, rules
  loaded, /metrics active, scraping LiteLLM, Grafana dashboard, datasource).
- One-click agent upgrade prompt in `README.md` — copy-paste for updating
  an existing installation to the latest version.
- Section D (Upgrade Procedure) in `SKILL.md` — concise upgrade path with
  delta table showing differences from fresh install.
- Port conflict check now covers all 4 services (4000, 5432, 9090, 3000).
- Grafana credentials and restart opencode warning in bootstrap summary
  and SKILL.md Step 10.

### Changed

- All ports bound to `127.0.0.1` (was `0.0.0.0`) — Prometheus, Grafana,
  and LiteLLM /metrics no longer exposed to network.
- Service count validation updated from 2 to 4 services.
- LiteLLM config: `callbacks: ["prometheus"]`,
  `prometheus_initialize_budget_metrics: true`,
  `require_auth_for_metrics_endpoint: false`.
- Docker Compose: added `prometheus` (prom/prometheus:v3.2.1) and `grafana`
  (grafana/grafana:11.5.2) services with health checks and resource limits.
- `SKILL.md` Step 6: "Check Port 4000 Free" → "Check Ports Free" (all 4).
- `SKILL.md` Step 7: Docker Compose service lists updated to 4 services.
- `SKILL.md` Step 9: recovery table expanded with Prometheus/Grafana entries.
- `REFERENCE.md`: added Observability section, updated architecture diagram,
  endpoints table, and repair guide.
- `SKILL.md` Step 10: summary synced with actual bootstrap output (header,
  Grafana credentials, restart warning).
- `SKILL.md` Section D: added Grafana hard restart instruction for upgrades.
- Agent preset model assignments updated based on benchmark research:
  - **oracle**: `glm-5.2` primary (was `deepseek-v4-pro`) — best deep
    reasoning with tools (HLE +6.5, MCP +3.4, SWE-bench Pro +6.7).
  - **designer**: `glm-5.1` primary (was `glm-5`) with `deepseek-v3.2`
    fallback — +28% coding over glm-5, sustained long-horizon productivity.
  - **fixer**: `glm-5` primary (was `deepseek-v4-flash`) with
    `deepseek-v3.2` fallback — 30 RPM vs 3 RPM, 10× more throughput.
  - **explorer**: `deepseek-v3.2` primary (was `deepseek-v4-flash`) —
    700 RPM, eliminates fallback latency.

### Fixed

- Grafana datasource UID mismatch — dashboard referenced `uid: "prometheus"`
  but datasource didn't set `uid`. Added `uid: prometheus` to provisioning.
- Panel 14 (RPM by model) used non-existent `model` label on
  `litellm_proxy_total_requests_metric` — changed to `requested_model`.
- Subquery syntax in dashboard panels 14/15: `avg_over_time(expr)[7d:5m]`
  → `avg_over_time((expr)[7d:5m])` — subquery must be inside the function.
- Dashboard variables `$model`/`$api_key` were defined but never used in
  queries — added label filters selectors to all applicable panels.
- Panel 12 (Budget gauge) threshold mode: `percentage` → `absolute`.
- Section C validation ran in `--opencode-only` mode without LiteLLM —
  now guarded by `if [ "$OPENCODE_ONLY" = false ]`.
- `5_validate.sh` C2 check indentation (extra leading spaces).
- Prometheus recording rules subquery syntax: `expr * 60 [7d:5m]` →
  `(expr * 60)[7d:5m]` — parentheses required before subquery operator.
- `curl -sf` without `-L` on LiteLLM /metrics (307 redirect to /metrics/).
- `curl` without `-g` on Prometheus query `up{job="litellm"}` (URL globbing).
- Duplicate "MAAS API keys total" message in agent mode bootstrap output.
- `5_validate.sh --litellm-only --opencode-only` was a silent no-op — now
  errors with mutual exclusion message.
- Empty duration display in `4_mint-virtual-key.sh` — now shows "unlimited".
- Removed `.master-key` cache file — all secrets now live in `.env` only.
  `0_bootstrap.sh` resolves `LITELLM_MASTER_KEY` from env var → `.env`
  (removed `.master-key` lookup and cache-write logic).

## [0.1.0] - 2026-06-26

Initial release.

### Added

- Deterministic 10-step install procedure (`SKILL.md`) — any agent can
  install by following steps 1–10 with preconditions, actions,
  postconditions, and recovery actions.
- One-click agent install prompt in `README.md` — copy-paste into any
  coding agent for fully automated installation.
- `--litellm-only` mode: deploy the LiteLLM proxy without opencode.
  Skips bun/jq prerequisites, opencode installation, and runs a
  standalone inference smoke test.
- `--agent` mode: non-interactive installation with mandatory key
  rotation security warning in the summary.
- `--dry-run` mode: preview all steps without making changes.
- 6 Huawei MaaS models: `glm-5.2`, `glm-5.1`, `glm-5`, `deepseek-v4-pro`,
  `deepseek-v4-flash`, `deepseek-v3.2`.
- 4 presets:
  - `LiteLLM-Huawei-MaaS-Full` — 6 models via LiteLLM proxy (default).
  - `LiteLLM-Huawei-MaaS-Core` — 4 models via LiteLLM (no v4-pro/v4-flash).
  - `Huawei-MaaS-Full` — 6 models direct (bypass proxy).
  - `Huawei-MaaS-Core` — 4 models direct.
- 3-councillor council system (alpha/beta/gamma) with distinct goals:
  deep reasoning, architecture, and practical implementation.
- Virtual key auto-minting with idempotent reuse — re-running bootstrap
  reuses the existing key if valid, mints a new one if expired.
- Multi-key load balancing (`HUAWEI_MAAS_API_KEY_0..N`) with
  simple-shuffle routing strategy.
- Comprehensive validation: 54 checks (full mode) / 14 checks
  (litellm-only mode) covering .env, Docker, LiteLLM health, config
  correctness, opencode configuration, presets, and inference.
- Idempotent installation — safe to re-run; existing containers, configs,
  and keys are detected and reused.
- `REFERENCE.md` with architecture, endpoint reference, script
  documentation, preset/model mapping table, and repair guide.

### Fixed

- `set -e` traps in `3a_install_opencode.sh` and `5_validate.sh` — command
  substitutions in assignments could trigger `set -e` before error
  handlers could print messages, causing silent script death on API
  failures (virtual key minting, model catalog fetch, liveness probe).
- Key rotation warning now shows even when validation fails — previously
  `set -e` exited before the summary could print.
- Agent-mode key rotation warning is definitive ("keys were shared with
  the agent") rather than conditional ("if any keys were visible").
- Warning covers all MaaS keys (`HUAWEI_MAAS_API_KEY` and
  `HUAWEI_MAAS_API_KEY_1..N`), not just the primary key.
- LiteLLM-only + agent mode now shows the key rotation warning (was
  missing entirely in v0.1.0-pre).

### Known Limitations

- **Linux only** — no macOS or Windows support.
- **Requires Docker + Docker Compose v2** — not bundled.
- **Requires a Huawei MaaS API key** (ap-southeast-1 region) — not
  included; obtain from the ModelArts MaaS console.
- **Inference smoke test requires a valid MaaS key** — placeholder or
  invalid keys will fail validation (all other checks still pass).
- **Pre-1.0 stability** — script flags, config schema, and preset
  definitions may change before v1.0. Pin to a tag for reproducibility.
