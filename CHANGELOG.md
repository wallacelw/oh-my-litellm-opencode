# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

- `set -e` traps in `3_install.sh` and `5_validate.sh` — command
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
