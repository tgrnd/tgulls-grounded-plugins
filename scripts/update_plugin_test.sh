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

# --- Tag warning (mock gh) ---

make_mock_gh() {
  bin=$(mktemp -d "${TMPDIR:-/tmp}/mock_gh_bin.XXXXXX")
  cat > "$bin/gh" <<'GHEOF'
#!/usr/bin/env sh
case "$1" in
  api)
    case "$2" in
      */git/ref/tags/*) [ "${GH_TAG_FAIL:-0}" = "1" ] && exit 1; exit 0 ;;
    esac ;;
esac
exit 1
GHEOF
  chmod +x "$bin/gh"
  printf '%s' "$bin"
}

DIR=$(make_marketplace)
BIN=$(make_mock_gh)
stderr=$(env GH_TAG_FAIL=1 PATH="$BIN:$PATH" \
  sh "$SCRIPT" --plugin=my-plugin --version=9.9.9 \
    --marketplace="$DIR/marketplace.json" 2>&1 >/dev/null) || true
case "$stderr" in
  *'warning: tag "v9.9.9" not found'*) warn_found=1 ;;
  *) warn_found=0 ;;
esac
assert_eq "warns when tag not found" "1" "$warn_found"

# Still succeeds despite warning
result=$(jq -r '.plugins[0].version' "$DIR/marketplace.json")
assert_eq "updates despite missing tag" "9.9.9" "$result"
rm -rf "$DIR" "$BIN"

# No warning when gh is not available
DIR=$(make_marketplace)
no_gh_bin=$(mktemp -d "${TMPDIR:-/tmp}/no_gh_bin.XXXXXX")
stderr=$(PATH="$no_gh_bin" \
  sh "$SCRIPT" --plugin=my-plugin --version=8.8.8 \
    --marketplace="$DIR/marketplace.json" 2>&1 >/dev/null) || true
case "$stderr" in
  *warning*) warn_found=1 ;;
  *) warn_found=0 ;;
esac
assert_eq "no warning when gh unavailable" "0" "$warn_found"
rm -rf "$DIR" "$no_gh_bin"

# --- Results ---

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
