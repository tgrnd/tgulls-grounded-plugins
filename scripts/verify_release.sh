#!/usr/bin/env sh
#
# Usage: verify-release [--marketplace=FILE]
#        verify-release -h | --help
#        verify-release --version
#
# Verifies that each plugin in marketplace.json has a matching git tag and
# consistent version in its plugin.json at the tagged ref.
#
# For each plugin where source.source is "github" and source.ref is set,
# the script checks that the tag exists on GitHub and that the plugin.json
# version at that ref matches the version declared in marketplace.json.
#
# Options:
#   --marketplace=FILE  Path to marketplace.json
#                       (default: .claude-plugin/marketplace.json)
#   -h, --help          Display this help and exit
#       --version       Output version information and exit
#
# Dependencies:
#   gh, jq, base64, tr
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
    --marketplace=*) MARKETPLACE="${arg#*=}" ;;
    -h|--help)
      sed -n 's/^# //p' "$0" | sed -n '/^Name:/q;p'
      exit 0
      ;;
    --version)
      sed -n 's/^# Version: //p' "$0" | head -1
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$MARKETPLACE" ]; then
  printf 'error: marketplace file not found: %s\n' "$MARKETPLACE" >&2
  exit 1
fi

# Check gh authentication before making any API calls
if ! gh auth status > /dev/null 2>&1; then
  printf 'error: gh is not authenticated — run "gh auth login" first\n' >&2
  exit 1
fi

ERRORS=0
count=$(jq '.plugins | length' "$MARKETPLACE")
i=0

while [ "$i" -lt "$count" ]; do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  version=$(jq -r ".plugins[$i].version" "$MARKETPLACE")
  source_type=$(jq -r ".plugins[$i].source.source" "$MARKETPLACE")
  ref=$(jq -r ".plugins[$i].source.ref // empty" "$MARKETPLACE")
  repo=$(jq -r ".plugins[$i].source.repo // empty" "$MARKETPLACE")

  if [ "$source_type" != "github" ]; then
    printf 'skip: %s (source type "%s" not verified)\n' "$name" "$source_type"
    i=$((i + 1))
    continue
  fi

  if [ -z "$ref" ]; then
    printf 'warning: %s has no ref — skipping tag verification\n' "$name" >&2
    i=$((i + 1))
    continue
  fi

  # Check that the tag exists on GitHub
  if ! gh api "repos/${repo}/git/ref/tags/${ref}" > /dev/null 2>&1; then
    printf 'error: %s — tag "%s" not found on %s\n' "$name" "$ref" "$repo" >&2
    ERRORS=$((ERRORS + 1))
    i=$((i + 1))
    continue
  fi

  # Fetch plugin.json at the tagged ref and decode its content
  plugin_version=$(
    gh api "repos/${repo}/contents/.claude-plugin/plugin.json?ref=${ref}" \
      --jq '.content' 2>/dev/null \
    | tr -d '\n' \
    | base64 -d 2>/dev/null \
    | jq -r '.version' 2>/dev/null
  ) || plugin_version=""

  if [ -z "$plugin_version" ]; then
    printf 'error: %s — could not fetch or decode plugin.json at ref "%s"\n' "$name" "$ref" >&2
    ERRORS=$((ERRORS + 1))
    i=$((i + 1))
    continue
  fi

  if [ "$plugin_version" != "$version" ]; then
    printf 'error: %s — plugin.json version "%s" does not match marketplace version "%s"\n' \
      "$name" "$plugin_version" "$version" >&2
    ERRORS=$((ERRORS + 1))
    i=$((i + 1))
    continue
  fi

  printf 'ok: %s %s\n' "$name" "$version"
  i=$((i + 1))
done

if [ "$ERRORS" -eq 0 ]; then
  printf '\nAll plugins verified\n'
  exit 0
else
  printf '\n%d verification error(s)\n' "$ERRORS"
  exit 2
fi
