#!/usr/bin/env sh
#
# Usage: update-readme [--marketplace=FILE] [--readme=FILE]
#        update-readme -h | --help
#        update-readme --version
#
# Regenerates the plugin table in README.md from marketplace.json.
# Replaces content between <!-- plugins-start --> and <!-- plugins-end --> markers.
#
# Options:
#   --marketplace=FILE  Path to marketplace.json
#                       (default: .claude-plugin/marketplace.json)
#   --readme=FILE       Path to README.md (default: README.md)
#   -h, --help          Display this help and exit
#       --version       Output version information and exit
#
# Dependencies:
#   jq, awk, mktemp
#
# Exit status:
#   0   Success
#   1   General error
#   2   Invalid arguments
#
###
# Name: update-readme
# Version: 0.1.0
# Date: 2026-03-31
# Author: tgulls
# License: MIT
###

set -eu

MARKETPLACE=".claude-plugin/marketplace.json"
README="README.md"

for arg in "$@"; do
  case "$arg" in
    --marketplace=*) MARKETPLACE="${arg#*=}" ;;
    --readme=*)      README="${arg#*=}" ;;
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

if [ ! -f "$README" ]; then
  printf 'error: readme file not found: %s\n' "$README" >&2
  exit 1
fi

TABLE=$(jq -r '
  "| Plugin | Description | Version |",
  "|--------|-------------|---------|",
  (.plugins[] |
    "| " +
    (if (.source | type) == "object" and .source.repo != null
     then "[" + .name + "](https://github.com/" + .source.repo + ")"
     else .name
     end) +
    " | " + .description + " | `" + .version + "` |"
  )
' "$MARKETPLACE")

TMPFILE=$(mktemp "${TMPDIR:-/tmp}/update-readme.XXXXXX")
TABLE_FILE=$(mktemp "${TMPDIR:-/tmp}/update-readme-table.XXXXXX")

printf '%s\n' "$TABLE" > "$TABLE_FILE"

awk -v tablefile="$TABLE_FILE" '
  /<!-- plugins-start -->/ {
    print
    while ((getline line < tablefile) > 0) print line
    skip=1
    next
  }
  /<!-- plugins-end -->/ { skip=0 }
  !skip                  { print }
' "$README" > "$TMPFILE"

rm "$TABLE_FILE"
mv "$TMPFILE" "$README"

printf 'Updated %s\n' "$README"
