# ⏚ TGulls Grounded Plugins

Personal Claude Code marketplace for externally-hosted plugins.

## Plugins

<!-- plugins-start -->
| Plugin | Description | Version |
|--------|-------------|---------|
| [docile](https://github.com/tgrnd/docile) | Default filesystem conventions for docs/ | `0.2.0-dev` |
<!-- plugins-end -->

## Install

Add the marketplace via CLI command:

```sh
claude plugin marketplace add https://github.com/tgrnd/tgulls-grounded-plugins
```

Or via Claude Code slash command:

```
/plugin marketplace add https://github.com/tgrnd/tgulls-grounded-plugins
```

Then install a plugin via CLI command:

```sh
claude plugin install <plugin-name>@tgulls-grounded-plugins
```

Or via Claude Code slash command:

```
/plugin install <plugin-name>@tgulls-grounded-plugins
```

## Development

**Dependencies:** `jq`, `gh` (authenticated), `base64`, `awk`, `shellcheck`, `shfmt`

Lint and format scripts:

```sh
shellcheck scripts/*.sh
shfmt -d scripts/*.sh
```

Run the release script tests:

```sh
sh scripts/update_plugin_test.sh
sh scripts/update_readme_test.sh
sh scripts/verify_release_test.sh
```

Tests are colocated with each script as `*_test.sh`. `verify_release_test.sh` uses a mock `gh` binary and requires no network access.

See [RELEASE.md](RELEASE.md) for the release process.
