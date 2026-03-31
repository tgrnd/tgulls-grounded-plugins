# tgulls-grounded-plugins

Personal Claude Code plugin marketplace.

## Commands

```sh
# Run release script tests
sh scripts/update_plugin_test.sh
sh scripts/update_readme_test.sh
sh scripts/verify_release_test.sh
```

## Conventions

- Shell scripts: POSIX sh, `shebang-sh:script-sh` standard, test files colocated as `*_test.sh`
- Release: use `/release` skill (see `RELEASE.md` for the full procedure)
