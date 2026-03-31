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

Read `RELEASE.md` first — it is the canonical procedure. This skill orchestrates it; the steps and scripts are defined there.

## Orchestration Rules

**Intent:** Extract plugin name and version from args. If either is missing, ask the user before proceeding.

**Branch:** Create `release/<plugin>-v<version>` before running any scripts.

**Scripts:** Run each script from `RELEASE.md` in order via Bash. After `update_plugin.sh`, show the diff and ask the user to confirm before continuing.

**`gh` CLI failures:** If a `gh` command fails due to sandbox restrictions, retry with `dangerouslyDisableSandbox: true` before asking the user to authenticate.

**Verification gate:** If `verify_release.sh` fails, surface the full per-plugin error and STOP. Do not auto-fix issues in the source plugin repo — that is the plugin maintainer's responsibility.

**Commit:** After a clean verify and readme update, create a single commit. Stage only the files changed by the scripts. Message format: `release: <plugin> v<version>`.

**PR body must include:**
- Plugin name and version
- Source ref being pinned
- Link to the plugin repo tag
- Reminder to merge using squash

**Report:** Share the PR URL and remind the user to squash-merge.

## Error Handling

Stop on any failure. Do not auto-retry. Surface the error and wait for the user to resolve it before proceeding.
