#!/usr/bin/env sh
#
# Usage: update_plugin_test.sh
#
# Tests for update_plugin.sh.
#
# Dependencies:
#   sh, jq, mktemp
#
# Exit status:
#   0   All tests passed
#   1   One or more tests failed
#
###
# Name: update_plugin_test
# Version: 0.1.0
# Date: 2026-03-31
# Author: tgulls
# License: MIT
###

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/update_plugin.sh"

PASS=0
FAIL=0

assert_eq() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf 'PASS: %s\n' "$desc"
    PASS=$((PASS + 1))
  else
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$desc" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_exit() {
  desc="$1"; expected="$2"; shift 2
  actual=0
  "$@" > /dev/null 2>&1 || actual=$?
  assert_eq "$desc" "$expected" "$actual"
}

make_marketplace() {
  dir=$(mktemp -d "${TMPDIR:-/tmp}/update_plugin_test.XXXXXX")
  cat > "$dir/marketplace.json" <<'EOF'
{
  "plugins": [
    {
      "name": "my-plugin",
      "version": "1.0.0",
      "source": {
        "source": "github",
        "repo": "owner/my-plugin",
        "ref": "v1.0.0"
      }
    }
  ]
}
EOF
  printf '%s' "$dir"
}

# --- Argument validation ---

assert_exit "missing --plugin exits 2" 2 \
  sh "$SCRIPT" --version=1.0.0

assert_exit "missing --version exits 2" 2 \
  sh "$SCRIPT" --plugin=my-plugin

assert_exit "unknown option exits 2" 2 \
  sh "$SCRIPT" --plugin=my-plugin --version=1.0.0 --bogus

# --- File validation ---

assert_exit "missing marketplace file exits 1" 1 \
  sh "$SCRIPT" --plugin=my-plugin --version=1.0.0 \
    --marketplace=/nonexistent/path.json

# --- Plugin lookup ---

DIR=$(make_marketplace)
assert_exit "plugin not found exits 2" 2 \
  sh "$SCRIPT" --plugin=no-such-plugin --version=1.0.0 \
    --marketplace="$DIR/marketplace.json"
rm -rf "$DIR"

# --- Successful update ---

DIR=$(make_marketplace)
sh "$SCRIPT" --plugin=my-plugin --version=2.0.0 \
  --marketplace="$DIR/marketplace.json" > /dev/null

result=$(jq -r '.plugins[0].version' "$DIR/marketplace.json")
assert_eq "updates version" "2.0.0" "$result"

ref=$(jq -r '.plugins[0].source.ref' "$DIR/marketplace.json")
assert_eq "default ref is v{VERSION}" "v2.0.0" "$ref"
rm -rf "$DIR"

# --- Custom ref ---

DIR=$(make_marketplace)
sh "$SCRIPT" --plugin=my-plugin --version=2.0.0 --ref=custom-ref \
  --marketplace="$DIR/marketplace.json" > /dev/null

ref=$(jq -r '.plugins[0].source.ref' "$DIR/marketplace.json")
assert_eq "custom --ref overrides default" "custom-ref" "$ref"
rm -rf "$DIR"

# --- Untouched plugins ---

DIR=$(mktemp -d "${TMPDIR:-/tmp}/update_plugin_test.XXXXXX")
cat > "$DIR/marketplace.json" <<'EOF'
{
  "plugins": [
    { "name": "plugin-a", "version": "1.0.0", "source": { "source": "github", "repo": "o/a", "ref": "v1.0.0" } },
    { "name": "plugin-b", "version": "3.0.0", "source": { "source": "github", "repo": "o/b", "ref": "v3.0.0" } }
  ]
}
EOF
sh "$SCRIPT" --plugin=plugin-a --version=1.1.0 \
  --marketplace="$DIR/marketplace.json" > /dev/null

unchanged=$(jq -r '.plugins[1].version' "$DIR/marketplace.json")
assert_eq "other plugins unchanged" "3.0.0" "$unchanged"
rm -rf "$DIR"

# --- Results ---

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
