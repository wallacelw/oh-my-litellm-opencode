# agents.md — Development Rules for Coding Agents

## Workflow

1. Make changes.
2. Validate end-to-end from multiple perspectives (see below).
3. Commit with a clear message (see below).
4. Push: `git push origin main`.
5. Repeat.

**Always commit and push after completing a unit of work.** Do not accumulate
multiple unrelated changes in one commit. Do not leave uncommitted changes.

## End-to-End Validation

Before committing, validate the change from **all** relevant perspectives:

1. **Script validation:** Run `./scripts/5_validate.sh` (or
   `--litellm-only` / `--opencode-only` as appropriate). Must pass (or
   fail only on expected checks like placeholder MaaS key).

2. **Cross-file consistency:** If you changed one file, check every file
   that references it:
   - Changed a script? Check SKILL.md steps, REFERENCE.md script table.
   - Changed a config template? Check the generated config, validation
     checks, and CHANGELOG.
   - Changed presets? Check REFERENCE.md agent→model table, CHANGELOG.
   - Changed ports/services? Check docker-compose.yml, SKILL.md Steps 6-7,
     REFERENCE.md endpoints, .githooks/pre-commit.
   - Changed env vars? Check .env.template, 1_init_env.sh, 0_bootstrap.sh,
     docker-compose.yml, SKILL.md Key Contract table.

3. **Documentation accuracy:** Read the affected documentation sections
   and verify they match the actual code output. Summaries, tables, and
   examples should reflect current behavior — not stale descriptions.

4. **Edge cases:** Consider:
   - `--agent` mode vs interactive mode
   - `--litellm-only` vs full mode
   - `--dry-run` mode
   - Idempotent re-run (existing .env, running containers)
   - Upgrade path (existing installation, missing vars)

## Commit Messages

Use imperative mood, capitalized first word, no trailing period:

```
Add Prometheus retention validation
Fix duplicate key count message in agent mode
Update agent preset model assignments based on benchmarks
```

For conventional commit style (optional but encouraged):

```
feat: add Prometheus + Grafana observability stack
fix: resolve datasource UID mismatch in Grafana dashboard
docs: sync SKILL.md with observability stack changes
```

Multi-line messages: first line is the summary (≤72 chars), blank line,
then body with `-` bullets for details:

```
Fix bugs found in end-to-end review

- 0_bootstrap.sh: duplicate key count message in agent mode
- 5_validate.sh: --litellm-only --opencode-only silent no-op
- 4_mint-virtual-key.sh: empty duration display
```

## Never Commit

- `.env` — contains secrets (blocked by .gitignore + pre-commit hook)
- `configs/litellm_config.yaml` — auto-generated from `.env`
- API keys, passwords, tokens, or any secret material
- Backup files (`*.bak.*`)

## Before Committing

- Check `git status` — only stage intended files.
- Check `git diff --cached` — review what you're about to commit.
- Run the full End-to-End Validation section above — not just one perspective.
- All changes must be validated before pushing. No exceptions.

## Code Style

- Shell scripts: `set -euo pipefail`, 2-space indent, snake_case.
- YAML: 2-space indent, double quotes for strings with special chars.
- JSON: 2-space indent, no trailing commas.
- Markdown: 2-space indent for nested lists, sentences end with period.

## Project Structure

```
scripts/          — install + validate scripts (numbered 0-5)
configs/          — Prometheus, Grafana, LiteLLM configs
configs/templates/ — .env, litellm_config, opencode, slim plugin templates
docs              — SKILL.md (procedure), REFERENCE.md (reference), README.md (human)
```

## When Unsure

- Ask the user before making architectural decisions.
- Ask before changing Docker images, model definitions, or preset assignments.
- Ask before modifying the upgrade path or install procedure.
- Do not guess — clarify first.
