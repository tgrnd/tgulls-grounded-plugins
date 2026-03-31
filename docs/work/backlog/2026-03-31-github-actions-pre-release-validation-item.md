---
title: GitHub Actions pre-release validation
status: backlog
created: 2026-03-31
priority: high
tags: [ci, release, safety]
---

# GitHub Actions Pre-Release Validation

## Summary

Add a GitHub Actions workflow that blocks merges to main when plugin refs or versions are invalid. Must be in place before the marketplace goes public.

## Acceptance Criteria

- [ ] Workflow triggers on PRs to `main` that modify `marketplace.json`
- [ ] Runs the same checks as `scripts/verify-release.sh` (tag exists, plugin.json version matches ref)
- [ ] Validates `marketplace.json` schema
- [ ] PR is blocked if any check fails
- [ ] Passes cleanly on valid marketplace state

## Why

`scripts/verify-release.sh` catches issues locally, but doesn't prevent a bad `marketplace.json` from being merged directly. Once the marketplace is public, a broken ref means users can't install plugins. The Actions gate is the last line of defense.

## Notes

- Reuse logic from `scripts/verify-release.sh` — keep script as source of truth, call it from CI
- See `RELEASE.md` for the full release process this fits into
