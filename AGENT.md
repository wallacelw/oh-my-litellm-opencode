# AGENT.md — Development Rules for Coding Agents

## Workflow

1. Make changes.
2. Verify: run `./scripts/5_validate.sh` if scripts or configs changed.
3. Commit with a clear message (see below).
4. Push: `git push origin main`.
5. Repeat.

**Always commit and push after completing a unit of work.** Do not accumulate
multiple unrelated changes in one commit. Do not leave uncommitted changes.

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
- If scripts or configs changed: run `./scripts/5_validate.sh`.
- If docs changed: no validation needed, just commit and push.

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
