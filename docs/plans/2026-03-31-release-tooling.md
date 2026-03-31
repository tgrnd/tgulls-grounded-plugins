# Release Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a script-backed release system for the tgulls-grounded-plugins marketplace with a `/release` project skill that orchestrates deterministic verification and PR creation.

**Architecture:** Three shell scripts handle deterministic steps (update, verify, readme); `RELEASE.md` documents the full procedure; a project skill reads `RELEASE.md` and drives the flow via Claude. All scripts must pass ShellCheck and follow the `shebang-sh:script-sh` standard — invoke that skill before writing any shell script.

**Tech Stack:** POSIX sh, jq, gh CLI, Claude Code project skill

---

### Task 1: `scripts/update-plugin.sh`

**Files:**
- Create: `scripts/update-plugin.sh`

**Before writing the script, invoke:** `shebang-sh:script-sh`

- [ ] **Step 1: Write `scripts/update-plugin.sh`**

```sh
#!/usr/bin/env sh
#
# Usage: update-plugin --plugin=NAME --version=VERSION [--ref=REF]
#        update-plugin --plugin=NAME --version=VERSION [--ref=REF] [--marketplace=FILE]
#        update-plugin -h | --help
#        update-plugin --version-info
#
# Updates a plugin entry in marketplace.json with a new version and ref.
# Defaults --ref to v{VERSION} if omitted.
#
# Options:
#   --plugin=NAME       Plugin name to update (required)
#   --version=VERSION   New version string, without v prefix (required)
#   --ref=REF           Git ref to pin (default: v{VERSION})
#   --marketplace=FILE  Path to marketplace.json
#                       (default: .claude-plugin/marketplace.json)
#   -h, --help          Display this help and exit
#       --version-info  Output version information and exit
#
# Dependencies:
#   jq
#
# Exit status:
#   0   Success
#   1   General error
#   2   Invalid arguments or plugin not found
#
###
# Name: update-plugin
# Version: 0.1.0
# Date: 2026-03-31
# Author: tgulls
# License: MIT
###

set -eu

MARKETPLACE=".claude-plugin/marketplace.json"
PLUGIN=""
VERSION=""
REF=""

for arg in "$@"; do
  case "$arg" in
    --plugin=*)       PLUGIN="${arg#*=}" ;;
    --version=*)      VERSION="${arg#*=}" ;;
    --ref=*)          REF="${arg#*=}" ;;
    --marketplace=*)  MARKETPLACE="${arg#*=}" ;;
    -h|--help)
      sed -n 's/^# //p' "$0" | sed '/^Name:/q' | head -n -1
      exit 0
      ;;
    --version-info)
      sed -n 's/^# Version: //p' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PLUGIN" ] || [ -z "$VERSION" ]; then
  printf 'error: --plugin and --version are required\n' >&2
  exit 2
fi

if [ -z "$REF" ]; then
  REF="v${VERSION}"
fi

if [ ! -f "$MARKETPLACE" ]; then
  printf 'error: marketplace file not found: %s\n' "$MARKETPLACE" >&2
  exit 1
fi

count=$(jq --arg name "$PLUGIN" '[.plugins[] | select(.name == $name)] | length' "$MARKETPLACE")
if [ "$count" -eq 0 ]; then
  printf 'error: plugin "%s" not found in %s\n' "$PLUGIN" "$MARKETPLACE" >&2
  exit 2
fi

TMPFILE=$(mktemp "${TMPDIR:-/tmp}/update-plugin.XXXXXX")

jq --arg name "$PLUGIN" --arg version "$VERSION" --arg ref "$REF" '
  .plugins = [
    .plugins[] |
    if .name == $name
    then .version = $version | .source.ref = $ref
    else .
    end
  ]
' "$MARKETPLACE" > "$TMPFILE"

mv "$TMPFILE" "$MARKETPLACE"

printf 'Updated %s to %s (ref: %s)\n' "$PLUGIN" "$VERSION" "$REF"
```

- [ ] **Step 2: Make executable and lint**

```bash
chmod +x scripts/update-plugin.sh
shellcheck -s sh scripts/update-plugin.sh
sh -n scripts/update-plugin.sh
```

Expected: no output (clean)

- [ ] **Step 3: Functional test**

```bash
# Create a test copy of marketplace.json
cp .claude-plugin/marketplace.json /tmp/test-marketplace.json

# Update docile to a test version
sh scripts/update-plugin.sh \
  --plugin=docile \
  --version=9.9.9 \
  --marketplace=/tmp/test-marketplace.json

# Verify version was updated
result=$(jq -r '.plugins[0].version' /tmp/test-marketplace.json)
[ "$result" = "9.9.9" ] && printf 'PASS: version\n' || printf 'FAIL: version got %s\n' "$result"

# Verify ref defaulted to v9.9.9
result=$(jq -r '.plugins[0].source.ref' /tmp/test-marketplace.json)
[ "$result" = "v9.9.9" ] && printf 'PASS: ref\n' || printf 'FAIL: ref got %s\n' "$result"

# Test unknown plugin exits 2
sh scripts/update-plugin.sh \
  --plugin=nonexistent \
  --version=1.0.0 \
  --marketplace=/tmp/test-marketplace.json
echo "Exit code: $?"
```

Expected:
```
Updated docile to 9.9.9 (ref: v9.9.9)
PASS: version
PASS: ref
error: plugin "nonexistent" not found in /tmp/test-marketplace.json
Exit code: 2
```

- [ ] **Step 4: Commit**

```bash
git add scripts/update-plugin.sh
git commit -m "feat: add update-plugin script"
```

---

### Task 2: `scripts/verify-release.sh`

**Files:**
- Create: `scripts/verify-release.sh`

**Before writing the script, invoke:** `shebang-sh:script-sh`

- [ ] **Step 1: Write `scripts/verify-release.sh`**

```sh
#!/usr/bin/env sh
#
# Usage: verify-release [--marketplace=FILE]
#        verify-release -h | --help
#        verify-release --version
#
# Verifies all plugin entries in marketplace.json against their sources.
# For github sources with a ref:
#   1. Confirms the tag exists on the remote repository
#   2. Fetches .claude-plugin/plugin.json at that ref and asserts
#      its version field matches the version in marketplace.json
#
# Options:
#   --marketplace=FILE  Path to marketplace.json
#                       (default: .claude-plugin/marketplace.json)
#   -h, --help          Display this help and exit
#       --version       Output version information and exit
#
# Dependencies:
#   jq, gh (authenticated)
#
# Exit status:
#   0   All plugins verified
#   1   General error (missing file, unauthenticated)
#   2   One or more verification failures
#
###
# Name: verify-release
# Version: 0.1.0
# Date: 2026-03-31
# Author: tgulls
# License: MIT
###

set -eu

MARKETPLACE=".claude-plugin/marketplace.json"

for arg in "$@"; do
  case "$arg" in
    --marketplace=*)  MARKETPLACE="${arg#*=}" ;;
    -h|--help)
      sed -n 's/^# //p' "$0" | sed '/^Name:/q' | head -n -1
      exit 0
      ;;
    --version)
      sed -n 's/^# Version: //p' "$0"
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$MARKETPLACE" ]; then
  printf 'error: marketplace file not found: %s\n' "$MARKETPLACE" >&2
  exit 1
fi

if ! gh auth status > /dev/null 2>&1; then
  printf 'error: gh CLI is not authenticated — run: gh auth login\n' >&2
  exit 1
fi

ERRORS=0
plugin_count=$(jq '.plugins | length' "$MARKETPLACE")
i=0

while [ "$i" -lt "$plugin_count" ]; do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  version=$(jq -r ".plugins[$i].version" "$MARKETPLACE")
  source_type=$(jq -r ".plugins[$i].source | if type == \"object\" then .source else \"local\" end" "$MARKETPLACE")

  if [ "$source_type" = "github" ]; then
    repo=$(jq -r ".plugins[$i].source.repo" "$MARKETPLACE")
    ref=$(jq -r ".plugins[$i].source.ref // \"\"" "$MARKETPLACE")

    if [ -z "$ref" ]; then
      printf 'warning: %s has no ref — skipping tag verification\n' "$name"
      i=$((i + 1))
      continue
    fi

    # Check tag exists
    if ! gh api "repos/$repo/git/ref/tags/$ref" > /dev/null 2>&1; then
      printf 'error: %s — tag "%s" not found on %s\n' "$name" "$ref" "$repo" >&2
      ERRORS=$((ERRORS + 1))
      i=$((i + 1))
      continue
    fi

    # Fetch plugin.json at ref and verify version
    plugin_version=$(
      gh api "repos/$repo/contents/.claude-plugin/plugin.json?ref=$ref" \
        --jq '.content' 2>/dev/null \
      | tr -d '\n' \
      | base64 -d 2>/dev/null \
      | jq -r '.version' 2>/dev/null \
      || true
    )

    if [ -z "$plugin_version" ]; then
      printf 'error: %s — could not fetch plugin.json at ref "%s"\n' "$name" "$ref" >&2
      ERRORS=$((ERRORS + 1))
      i=$((i + 1))
      continue
    fi

    if [ "$plugin_version" != "$version" ]; then
      printf 'error: %s — marketplace version "%s" does not match plugin.json version "%s" at ref "%s"\n' \
        "$name" "$version" "$plugin_version" "$ref" >&2
      ERRORS=$((ERRORS + 1))
    else
      printf 'ok: %s %s\n' "$name" "$version"
    fi
  else
    printf 'skip: %s (source type "%s" not verified)\n' "$name" "$source_type"
  fi

  i=$((i + 1))
done

if [ "$ERRORS" -gt 0 ]; then
  printf '\n%d verification error(s)\n' "$ERRORS" >&2
  exit 2
fi

printf '\nAll plugins verified\n'
```

- [ ] **Step 2: Make executable and lint**

```bash
chmod +x scripts/verify-release.sh
shellcheck -s sh scripts/verify-release.sh
sh -n scripts/verify-release.sh
```

Expected: no output (clean)

- [ ] **Step 3: Manual verification test**

Requires `gh` authenticated and `tgrnd/docile` tag `v0.2.0-dev` to exist.

```bash
sh scripts/verify-release.sh
```

Expected output:
```
ok: docile 0.2.0-dev

All plugins verified
```

Test failure path — temporarily set a bad ref:
```bash
cp .claude-plugin/marketplace.json /tmp/marketplace-backup.json
# Edit .claude-plugin/marketplace.json and change ref to "v99.0.0"
jq '.plugins[0].source.ref = "v99.0.0"' .claude-plugin/marketplace.json > /tmp/bad.json
cp /tmp/bad.json .claude-plugin/marketplace.json

sh scripts/verify-release.sh
echo "Exit: $?"

# Restore
cp /tmp/marketplace-backup.json .claude-plugin/marketplace.json
```

Expected:
```
error: docile — tag "v99.0.0" not found on tgrnd/docile

1 verification error(s)
Exit: 2
```

- [ ] **Step 4: Commit**

```bash
git add scripts/verify-release.sh
git commit -m "feat: add verify-release script"
```

---

### Task 3: `RELEASE.md`

**Files:**
- Create: `RELEASE.md`

- [ ] **Step 1: Write `RELEASE.md`**

```markdown
# Release Process

This document describes how to release a new plugin version or add a new plugin to the marketplace. It is used directly by humans and referenced by the `/release` skill.

## Prerequisites

- `gh` CLI authenticated (`gh auth status`)
- `jq` installed
- On `main` branch, up to date with remote (`git pull`)
- No uncommitted changes

## Steps

### 1. Update marketplace.json

For an existing plugin version bump:

```sh
sh scripts/update-plugin.sh --plugin=<name> --version=<version>
```

This sets `version` and defaults `source.ref` to `v<version>`. To use a different ref:

```sh
sh scripts/update-plugin.sh --plugin=<name> --version=<version> --ref=<ref>
```

For a new plugin, add the entry manually to `.claude-plugin/marketplace.json` following the existing pattern.

### 2. Verify the release

```sh
sh scripts/verify-release.sh
```

This confirms for every GitHub-sourced plugin:
- The `source.ref` tag exists on the remote repository
- The `version` in `plugin.json` at that ref matches `marketplace.json`

Fix any errors before proceeding. Do not merge until this passes.

### 3. Update README

```sh
sh scripts/update-readme.sh
```

Regenerates the plugin table from `marketplace.json`.

### 4. Commit and open PR

Stage all changes as a single commit:

```sh
git add .claude-plugin/marketplace.json README.md
git commit -m "release: <plugin> v<version>"
```

Push and open PR:

```sh
git push -u origin <branch>
gh pr create --title "release: <plugin> v<version>"
```

Merge using **squash** to keep a clean single commit on `main`.

### 5. Post-merge (optional)

After merging, tag the marketplace repo if tracking releases:

```sh
git tag v<version>
git push --tags
```

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/update-plugin.sh` | Update plugin version + ref in marketplace.json |
| `scripts/verify-release.sh` | Verify plugin versions are available at their sources |
| `scripts/update-readme.sh` | Regenerate README plugin table |
```

- [ ] **Step 2: Verify RELEASE.md renders correctly**

```bash
# Quick sanity check — confirm all referenced scripts exist
for script in scripts/update-plugin.sh scripts/verify-release.sh scripts/update-readme.sh; do
  [ -f "$script" ] && printf 'ok: %s\n' "$script" || printf 'MISSING: %s\n' "$script"
done
```

Expected:
```
ok: scripts/update-plugin.sh
ok: scripts/verify-release.sh
ok: scripts/update-readme.sh
```

- [ ] **Step 3: Commit**

```bash
git add RELEASE.md
git commit -m "docs: add RELEASE.md release procedure"
```

---

### Task 4: `.claude/skills/release/SKILL.md`

**Files:**
- Create: `.claude/skills/release/SKILL.md`

- [ ] **Step 1: Create directory and write skill**

```bash
mkdir -p .claude/skills/release
```

```markdown
---
name: release
description: >
  Use when the user wants to release a plugin, bump a version, open a release PR,
  or asks about the release process. Triggers on: "release", "ship", "bump version",
  "/release".
user-invocable: true
allowed-tools:
  - Read
  - Bash(sh scripts/*)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git push *)
  - Bash(git checkout -b *)
  - Bash(gh pr create *)
  - Bash(gh auth status)
argument-hint: "[plugin] [version]"
---

# Release Skill

You are driving a marketplace release for `tgulls-grounded-plugins`.

## Step 1: Load procedure

Read `RELEASE.md` at the project root. This is the source of truth for the release process.

## Step 2: Understand intent

If the user provided a plugin name and version (e.g. `/release docile 1.0.0`), proceed with those.

If intent is unclear, ask:
> "Which plugin are you releasing and what version? (e.g. `docile 1.0.0`)"

If the user says "new plugin", guide them to manually add the entry to `.claude-plugin/marketplace.json` following the existing pattern, then continue from Step 3.

## Step 3: Branch

Create a release branch:

```bash
git checkout -b release/<plugin>-v<version>
```

## Step 4: Update marketplace.json

```bash
sh scripts/update-plugin.sh --plugin=<plugin> --version=<version>
```

Show the diff to the user and confirm before proceeding.

## Step 5: Verify

```bash
sh scripts/verify-release.sh
```

If verification fails, surface each error clearly and stop. Do not proceed until the user resolves the issues and re-runs verification. Do not attempt to auto-fix version mismatches — the source plugin repo must be updated by the user.

## Step 6: Update README

```bash
sh scripts/update-readme.sh
```

## Step 7: Commit and PR

```bash
git add .claude-plugin/marketplace.json README.md
git commit -m "release: <plugin> v<version>"
git push -u origin release/<plugin>-v<version>
gh pr create --title "release: <plugin> v<version>" --body "..."
```

PR body should include:
- Plugin name and version
- Source ref being pinned
- Link to the plugin repo release/tag

## Step 8: Report

Share the PR URL and remind the user to merge with **squash**.
```

- [ ] **Step 2: Verify skill is discoverable**

```bash
ls -la .claude/skills/release/SKILL.md
```

Expected: file exists

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/release/SKILL.md
git commit -m "feat: add /release project skill"
```

---

### Task 5: Integration test and PR

**Files:**
- No new files

- [ ] **Step 1: Run full flow dry-run**

```bash
# Confirm current state is clean
git status
sh scripts/verify-release.sh
```

Expected: current marketplace verifies clean.

- [ ] **Step 2: Reload plugins to confirm skill loads**

In Claude Code:
```
/reload-plugins
```

Confirm `release` skill appears in the skill list.

- [ ] **Step 3: Smoke-test `/release` invocation**

In Claude Code, type:
```
/release
```

Expected: skill solicits plugin name and version.

- [ ] **Step 4: Open PR for all release tooling**

```bash
git log --oneline main..HEAD
```

Confirm commits are: `update-plugin`, `verify-release`, `RELEASE.md`, `release skill`.

```bash
git push -u origin <current-branch>
gh pr create \
  --title "feat: add release tooling (scripts + RELEASE.md + /release skill)" \
  --body "..."
```

PR body:
```
## Summary
- `scripts/update-plugin.sh` — updates plugin version + ref in marketplace.json
- `scripts/verify-release.sh` — verifies tag exists and plugin.json version matches
- `RELEASE.md` — human-readable release procedure
- `.claude/skills/release/SKILL.md` — project skill that orchestrates the full flow

## Test plan
- [ ] `shellcheck -s sh scripts/update-plugin.sh` passes
- [ ] `shellcheck -s sh scripts/verify-release.sh` passes
- [ ] `sh scripts/verify-release.sh` passes against current marketplace.json
- [ ] `/release` skill loads and solicits intent
- [ ] Full flow: update → verify → readme → commit → PR works end-to-end
```
