# Stale References Report

## Summary of Findings

### 1. References to `custom_openai`, `auth.json`, `openai_api_key`, `openai_base_url`
- **CHANGELOG.md:26** - Mentions `auth.json` in changelog (acceptable as historical reference)
- **CHANGELOG.md:31** - Mentions `custom_openai` prefix change (acceptable as historical reference)
- **No other stale references found** - Good!

### 2. References to `3_install.sh` (should be `3a_install_opencode.sh`)
- **CHANGELOG.md:29** - Mentions rename from `3_install.sh` to `3a_install_opencode.sh` (acceptable as historical reference)
- **No other stale references found** - Good!

### 3. References to "shell profile" or "bashrc" or "zshrc" in context of Codex API key
- **CHANGELOG.md:26** - Mentions "shell profile or `auth.json`" (acceptable as historical reference)
- **No other stale references found** - Good!

### 4. REFERENCE.md script table
- **✅ CORRECT**: Script table lists `3a_install_opencode.sh` and `3b_install_codex.sh` correctly
- **✅ CORRECT**: Descriptions are accurate

### 5. REFERENCE.md "Core Rules" section mentions openai/ + use_chat_completions_api
- **✅ CORRECT**: Line 55 mentions `openai/` provider prefix with `use_chat_completions_api: true`

### 6. REFERENCE.md Codex CLI endpoints/ports
- **❌ MISSING**: REFERENCE.md endpoints table doesn't mention Codex CLI endpoints
- **SHOULD ADD**: Codex CLI endpoint information

### 7. SKILL.md bootstrap steps accuracy
- **✅ CORRECT**: SKILL.md mentions `--codex-only` flag (line 345-346)
- **✅ CORRECT**: All bootstrap steps appear accurate

### 8. SKILL.md Key Contract table mentions CODEX_VIRTUAL_KEY
- **❌ MISSING**: Key Contract table doesn't include `CODEX_VIRTUAL_KEY`
- **SHOULD ADD**: `CODEX_VIRTUAL_KEY` env var to Key Contract table

### 9. SKILL.md references to old install flow
- **✅ CORRECT**: No references to old install flow found

### 10. README.md mentions Codex CLI
- **❌ MISSING**: README.md doesn't mention Codex CLI at all
- **SHOULD UPDATE**: Feature list and description should mention Codex CLI support

### 11. CHANGELOG.md [Unreleased] section completeness
- **✅ CORRECT**: [Unreleased] section covers Codex CLI integration
- **⚠️ PARTIAL**: Some recent changes from git log not in changelog:
  - Refactor configs/ into per-component directories
  - Set Grafana anonymous role to Viewer (read-only)
  - Enable anonymous admin access to Grafana
  - Fix model health panel and patch health check probe for Huawei MaaS
  - Rework Deployment & Health section and remove Budget remaining by key
  - Recognize content-moderation health check failures in validator
  - Disable companion installation by default in oh-my-opencode-slim
  - Rename agents.md to AGENTS.md
  - Rename AGENT.md to agents.md, fix Models Deployed count, add panel descriptions
  - Convert Total cost per model to timeseries curve and add RPM by model x API key line chart
  - Add end-to-end validation from multiple perspectives to AGENT.md
  - Add AGENT.md with standardized development rules for coding agents
  - Fill documentation gaps found in review

### 12. .env.template has CODEX_VIRTUAL_KEY
- **✅ CORRECT**: Line 25 has `CODEX_VIRTUAL_KEY` placeholder (commented out)

### 13. docker-compose.yml LiteLLM config volume mount
- **✅ CORRECT**: Lines 18-19 mount `./configs/litellm/config.yaml:/app/config.yaml:ro` and `./configs/litellm/entrypoint.sh:/app/entrypoint.sh:ro` correctly

### 14. AGENTS.md project structure mentions all codex files
- **✅ CORRECT**: Line 103 mentions `configs/codex/` directory

### 15. .githooks/pre-commit references correct script names
- **✅ CORRECT**: .githooks/pre-commit doesn't reference any script names (only blocks `.env` and `configs/litellm/config.yaml`)

## Detailed Findings

### Critical Issues (Need Fixing)

1. **REFERENCE.md endpoints table missing Codex CLI endpoints** (Line 27-35)
   - Should add Codex CLI endpoint information
   - Codex CLI uses LiteLLM proxy at `http://127.0.0.1:4000` with virtual key

2. **SKILL.md Key Contract table missing CODEX_VIRTUAL_KEY** (Lines 29-39)
   - Should add `CODEX_VIRTUAL_KEY` env var to the table
   - Set by: `3b_install_codex.sh` (minted, not set manually)
   - Read by: Codex CLI via `~/.codex/.env`
   - Format: Virtual key starting with `sk-`
   - Immutable: No (can be re-minted)

3. **README.md doesn't mention Codex CLI** (Line 3)
   - Feature list says "LiteLLM proxy → Huawei MaaS → opencode"
   - Should be "LiteLLM proxy → Huawei MaaS → opencode + Codex CLI"
   - Should mention `--codex-only` flag in Quick Start

### Minor Issues (Historical References - OK)

1. **CHANGELOG.md references old terms** (Lines 26, 29, 31)
   - Line 26: "shell profile or `auth.json`" - historical reference to old Codex CLI key storage
   - Line 29: "`3_install.sh` renamed to `3a_install_opencode.sh`" - historical reference to rename
   - Line 31: "opencode model keys use LiteLLM `model_name` directly (no `custom_openai` prefix)" - historical reference to prefix change
   - These are acceptable as they document historical changes

### Incomplete CHANGELOG

The [Unreleased] section in CHANGELOG.md only covers Codex CLI integration changes, but there are many other recent changes that should be documented. The changelog should be updated to include all changes since v0.2.0.

## Recommendations

1. **Update REFERENCE.md endpoints table** to include Codex CLI endpoint
2. **Update SKILL.md Key Contract table** to include `CODEX_VIRTUAL_KEY`
3. **Update README.md** to mention Codex CLI support in feature list and Quick Start
4. **Update CHANGELOG.md [Unreleased] section** to include all recent changes
5. **Consider adding a "Codex CLI" section to REFERENCE.md** documenting how Codex CLI integrates with LiteLLM