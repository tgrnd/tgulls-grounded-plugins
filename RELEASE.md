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
