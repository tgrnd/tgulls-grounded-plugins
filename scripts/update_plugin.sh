#!/usr/bin/env sh
#
# Usage: update-plugin --plugin=NAME --version=VERSION [--ref=REF]
#                      [--marketplace=FILE]
#        update-plugin -h | --help
#        update-plugin --version-info
#
# Updates a plugin entry in marketplace.json, setting its version and source ref.
#
# Options:
#   --plugin=NAME       Name of the plugin to update (required)
#   --version=VERSION   New version string (required)
#   --ref=REF           Git ref to set in source.ref
#                       (default: v{VERSION})
#   --marketplace=FILE  Path to marketplace.json
#                       (default: .claude-plugin/marketplace.json)
#   -h, --help          Display this help and exit
#       --version-info  Output version information and exit
#
# Exit status:
#   0   Success
#   1   General error
#   2   Invalid arguments or plugin not found
#
# Dependencies:
#   jq, mktemp
#   gh (optional, for tag existence warning)
#
###
# Name: update-plugin
# Version: 0.2.0
# Date: 2026-03-31
# Author: tgulls
# License: MIT
###

set -eu

PLUGIN=""
VERSION=""
REF=""
MARKETPLACE=".claude-plugin/marketplace.json"

for arg in "$@"; do
  case "$arg" in
    --plugin=*)      PLUGIN="${arg#*=}" ;;
    --version=*)     VERSION="${arg#*=}" ;;
    --ref=*)         REF="${arg#*=}" ;;
    --marketplace=*) MARKETPLACE="${arg#*=}" ;;
    -h|--help)
      sed -n 's/^# //p' "$0" | sed '/^Name:/q' | sed '$d'
      exit 0
      ;;
    --version-info)
      sed -n 's/^# Version: //p' "$0"
      exit 0
      ;;
    *)
      printf 'error: unknown option: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PLUGIN" ]; then
  printf 'error: --plugin=NAME is required\n' >&2
  exit 2
fi

if [ -z "$VERSION" ]; then
  printf 'error: --version=VERSION is required\n' >&2
  exit 2
fi

if [ -z "$REF" ]; then
  REF="v${VERSION}"
fi

if [ ! -f "$MARKETPLACE" ]; then
  printf 'error: marketplace file not found: %s\n' "$MARKETPLACE" >&2
  exit 1
fi

# Validate the plugin exists before writing
found=$(jq -r --arg name "$PLUGIN" '.plugins[] | select(.name == $name) | .name' "$MARKETPLACE")

if [ -z "$found" ]; then
  printf 'error: plugin "%s" not found in %s\n' "$PLUGIN" "$MARKETPLACE" >&2
  exit 2
fi

# Warn if the target ref does not exist on the source repo (non-blocking)
repo=$(jq -r --arg name "$PLUGIN" '.plugins[] | select(.name == $name) | .source.repo // empty' "$MARKETPLACE")
if [ -n "$repo" ] && command -v gh > /dev/null 2>&1; then
  if ! gh api "repos/${repo}/git/ref/tags/${REF}" > /dev/null 2>&1; then
    printf 'warning: tag "%s" not found on %s\n' "$REF" "$repo" >&2
  fi
fi

TMPFILE=$(mktemp "${TMPDIR:-/tmp}/update-plugin.XXXXXX")
trap 'rm -f "$TMPFILE"' EXIT INT TERM

jq --arg name "$PLUGIN" --arg version "$VERSION" --arg ref "$REF" '
  .plugins = [
    .plugins[] |
    if .name == $name then
      .version = $version | .source.ref = $ref
    else
      .
    end
  ]
' "$MARKETPLACE" > "$TMPFILE" || { printf 'error: failed to update %s\n' "$MARKETPLACE" >&2; exit 1; }

mv "$TMPFILE" "$MARKETPLACE"

printf 'Updated %s to %s (ref: %s)\n' "$PLUGIN" "$VERSION" "$REF"
