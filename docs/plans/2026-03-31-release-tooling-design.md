# Release Tooling Design

**Date:** 2026-03-31
**Status:** Approved
**Author:** tgulls + Claude
**Source:** brainstorming → writing-plans
**Location:** `.claude/skills/release/`, `scripts/`, `RELEASE.md`

---

## Overview

A three-part release system for the `tgulls-grounded-plugins` marketplace: a deterministic verification script, a human-readable procedure document, and a project skill that orchestrates the full release flow via Claude. A GitHub Actions gate is planned separately (see backlog item) before the marketplace goes public.

## Components

### 1. `scripts/update-plugin.sh`

Updates a single plugin entry in `marketplace.json`. Accepts `--plugin`, `--version`, and `--ref` (defaults `--ref` to `v{version}` if omitted). Validates the plugin name exists before writing. This is the entry point for a release — run before verification.

**Dependencies:** `jq`

### 2. `scripts/verify-release.sh`

Deterministic pre-release checks. Iterates over every plugin entry in `.claude-plugin/marketplace.json` and:

1. **Tag existence** — for `github` sources with a `ref`, calls `gh api repos/{repo}/git/ref/tags/{ref}` to confirm the tag exists on the remote
2. **Version match** — fetches `.claude-plugin/plugin.json` at that ref via `gh api repos/{repo}/contents/.claude-plugin/plugin.json?ref={ref}`, base64-decodes it, and asserts the `version` field equals the `version` in `marketplace.json`

Exits `0` if all plugins pass. Exits `2` with a per-plugin error message on any failure. Designed to be callable from CI (GitHub Actions, Option B).

**Dependencies:** `jq`, `gh` (authenticated)

### 3. `RELEASE.md`

Human-readable release procedure at the repo root. Acts as the source of truth for the release process — both for the `/release` skill and for anyone running the process manually. Lists each step in order, specifies which scripts to run, and describes what requires human judgment.

Structure:
- Prerequisites (auth, branch state)
- Step 1: Update `marketplace.json` versions and refs
- Step 2: Run `scripts/verify-release.sh`
- Step 3: Run `scripts/update-readme.sh`
- Step 4: Commit, push, open PR (single commit, squash on merge)
- Step 5: Post-merge tag (optional, for marketplace versioning)

### 4. `.claude/skills/release/SKILL.md`

Project-scoped skill invoked as `/release`. On invocation:

1. Reads `RELEASE.md` to load the current procedure
2. Solicits intent if not provided (e.g. "which plugin are you releasing, or is this a full marketplace release?")
3. Runs `scripts/verify-release.sh` via Bash and reports results
4. If verification passes, runs `scripts/update-readme.sh`
5. Stages changes, creates a single commit, pushes, and opens a PR
6. If verification fails, surfaces the errors and guides the user to fix them before retrying

The skill defers to `RELEASE.md` for procedure — if the procedure changes, the skill picks it up automatically without needing to be edited.

## Data Flow

```
User: /release docile v1.0.0
  → skill reads RELEASE.md
  → skill solicits intent (if not provided)
  → Bash: scripts/update-plugin.sh --plugin=docile --version=1.0.0
      → validates plugin exists in marketplace.json
      → writes version + ref (v1.0.0) to marketplace.json
  → Bash: scripts/verify-release.sh
      → gh api: tag v1.0.0 exists on tgrnd/docile?
      → gh api: plugin.json version at ref matches 1.0.0?
  → [pass] Bash: scripts/update-readme.sh
  → git: single commit + push + PR
  → [fail] surface errors per plugin, revert marketplace.json
```

## Error Handling

- `verify-release.sh` exits 2 with a clear message per failing plugin — skill surfaces these verbatim
- If `gh` is unauthenticated, script exits 1 with an auth hint
- Skill does not open a PR if verification fails

## Implementation Notes

- All shell scripts must follow the `shebang-sh:script-sh` skill standard (POSIX, GNU docs, ShellCheck clean, metadata block)
- Invoke `shebang-sh:script-sh` before writing any shell script during implementation

## Out of Scope (Option B)

GitHub Actions workflow that runs `verify-release.sh` on PRs modifying `marketplace.json`. Tracked in `docs/work/backlog/2026-03-31-github-actions-pre-release-validation-item.md`. Required before the marketplace goes public.
