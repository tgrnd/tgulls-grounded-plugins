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

This skill drives the release process for the Claude Code plugin marketplace. It orchestrates plugin version updates, verification, and PR creation.

## Procedure Overview

The release process is documented in `RELEASE.md` at the project root — that is the source of truth for the complete procedure. This skill automates the workflow described there.

**Note:** Changes to `RELEASE.md` are picked up automatically by this skill on next invocation.

## How This Skill Works

### 1. Load Procedure

The skill reads `RELEASE.md` to understand the current release workflow. All steps defined there are considered authoritative.

### 2. Understand Intent

When invoked:

- **With arguments**: Use the provided plugin name and version directly
  - Example: `/release my-plugin 1.2.3`
- **Without arguments**: Ask the user clarifying questions:
  - "Which plugin are you releasing?"
  - "What version should it be bumped to?"
  - "Should the source ref be `v<version>` or a different ref?"

Store these values for use in subsequent steps.

### 3. Create Release Branch

Create a feature branch for the release:

```bash
git checkout -b release/<plugin>-v<version>
```

Example: `release/my-plugin-v1.2.3`

### 4. Update Plugin Version

Run the update script to modify `marketplace.json`:

```bash
sh scripts/update-plugin.sh --plugin=<plugin> --version=<version>
```

**Critical step:** After running this command:
- Show the diff of the changes
- Ask user to confirm before proceeding
- Do NOT auto-proceed

If using a non-standard source ref (not `v<version>`):

```bash
sh scripts/update-plugin.sh --plugin=<plugin> --version=<version> --ref=<custom-ref>
```

### 5. Verify Release

Run verification to ensure the plugin version is available at its source:

```bash
sh scripts/verify-release.sh
```

**Critical gates:**
- If verification FAILS, surface the error clearly and STOP
- Do not attempt auto-fix or skip this step
- Do not adjust versions in the source plugin repo — that's the plugin maintainer's responsibility
- Return the error to the user for manual investigation

If verification PASSES, proceed to the next step.

### 6. Update README

Regenerate the plugin table in the README:

```bash
sh scripts/update-readme.sh
```

This updates the plugin listing based on the modified `marketplace.json`.

### 7. Commit and Push

Create a single, focused commit:

```bash
git add .claude-plugin/marketplace.json README.md
git commit -m "release: <plugin> v<version>"
git push -u origin release/<plugin>-v<version>
```

Example commit message: `release: my-plugin v1.2.3`

### 8. Open Pull Request

Create a PR with comprehensive body:

```bash
gh pr create --title "release: <plugin> v<version>" --body "..."
```

**PR body must include:**
- Plugin name and version being released
- Source repository reference (the ref being pinned)
- Link to the plugin's repository release or tag page
- Reminder that the PR should be merged using **squash** to maintain a clean commit history

**Example PR body:**

```
## Release: my-plugin v1.2.3

Releases my-plugin version 1.2.3 to the Claude Code marketplace.

**Source:** https://github.com/owner/my-plugin/releases/tag/v1.2.3

Please merge this PR using **squash** to keep a clean single commit on main.
```

### 9. Report

After the PR is created successfully:

- Share the PR URL with the user
- Remind them that the PR should be merged using squash (not regular merge or rebase)
- Explain that post-merge, they can optionally tag the marketplace repo itself if tracking releases

## Prerequisites Check

Before starting, verify:

- `gh auth status` returns an authenticated session
- User is on or ready to switch to the main branch
- No uncommitted changes in the working directory
- Repository is up to date with remote

If prerequisites aren't met, STOP and ask the user to resolve them before proceeding.

## Error Handling

- **Authentication fails**: Stop and ask user to run `gh auth login`
- **Update script fails**: Show error, ask user to verify plugin name
- **Verification fails**: Stop immediately, show full error, do not proceed
- **Git operations fail**: Stop and ask user to resolve conflicts or git issues
- **PR creation fails**: Show error, confirm user wants to retry or investigate

## Next Steps After Release

After the PR is merged:

1. Optionally tag the marketplace repo: `git tag v<version>` (purely informational)
2. Merged PR removes the release branch automatically (GitHub automation)
3. Plugin is now available in the marketplace

---

**Source of Truth:** See `RELEASE.md` in the project root for the authoritative procedure.
