#!/usr/bin/env sh
#
# Usage: verify_release_test.sh
#
# Tests for verify_release.sh. Uses a mock gh binary injected via PATH to
# simulate GitHub API responses without network access.
#
# Dependencies:
#   sh, jq, base64, mktemp
#
# Exit status:
#   0   All tests passed
#   1   One or more tests failed
#
###
# Name: verify_release_test
# Version: 0.1.0
# Date: 2026-03-31
# Author: tgulls
# License: MIT
###

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/verify_release.sh"

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

# Write a mock gh script into a temp bin dir and return the dir path.
# Env vars control behaviour:
#   GH_AUTH_FAIL=1      auth status exits 1
#   GH_TAG_FAIL=1       tag API exits 1
#   GH_PLUGIN_VERSION   version string returned in plugin.json content
make_mock_gh() {
  bin=$(mktemp -d "${TMPDIR:-/tmp}/mock_gh_bin.XXXXXX")
  cat > "$bin/gh" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  auth)
    [ "${GH_AUTH_FAIL:-0}" = "1" ] && exit 1
    exit 0
    ;;
  api)
    case "$2" in
      */git/ref/tags/*)
        [ "${GH_TAG_FAIL:-0}" = "1" ] && exit 1
        exit 0
        ;;
      */contents/.claude-plugin/plugin.json*)
        ver="${GH_PLUGIN_VERSION:-1.0.0}"
        # Output base64-encoded {"version":"<ver>"} — the --jq '.content' output
        printf '{"version":"%s"}' "$ver" | base64
        exit 0
        ;;
    esac
    ;;
esac
exit 1
EOF
  chmod +x "$bin/gh"
  printf '%s' "$bin"
}

make_marketplace() {
  file=$(mktemp "${TMPDIR:-/tmp}/marketplace.XXXXXX")
  cat > "$file" <<EOF
{
  "plugins": [
    {
      "name": "my-plugin",
      "version": "${1:-1.0.0}",
      "source": {
        "source": "github",
        "repo": "owner/my-plugin",
        "ref": "v${1:-1.0.0}"
      }
    }
  ]
}
EOF
  printf '%s' "$file"
}

# --- Argument validation (no gh needed) ---

assert_exit "missing marketplace exits 1" 1 \
  sh "$SCRIPT" --marketplace=/nonexistent.json

assert_exit "unknown option exits 2" 2 \
  sh "$SCRIPT" --bogus

# --- gh auth failure ---

BIN=$(make_mock_gh)
MKT=$(make_marketplace)
assert_exit "unauthenticated gh exits 1" 1 \
  env GH_AUTH_FAIL=1 PATH="$BIN:$PATH" sh "$SCRIPT" --marketplace="$MKT"
rm -rf "$BIN"; rm -f "$MKT"

# --- Non-github source is skipped ---

BIN=$(make_mock_gh)
FILE=$(mktemp "${TMPDIR:-/tmp}/marketplace.XXXXXX")
cat > "$FILE" <<'EOF'
{
  "plugins": [
    {
      "name": "local-plugin",
      "version": "1.0.0",
      "source": { "source": "local" }
    }
  ]
}
EOF
assert_exit "non-github source exits 0 (skipped)" 0 \
  env PATH="$BIN:$PATH" sh "$SCRIPT" --marketplace="$FILE"
rm -rf "$BIN"; rm -f "$FILE"

# --- Missing ref triggers warning, exits 0 ---

BIN=$(make_mock_gh)
FILE=$(mktemp "${TMPDIR:-/tmp}/marketplace.XXXXXX")
cat > "$FILE" <<'EOF'
{
  "plugins": [
    {
      "name": "no-ref-plugin",
      "version": "1.0.0",
      "source": { "source": "github", "repo": "owner/no-ref-plugin" }
    }
  ]
}
EOF
assert_exit "missing ref exits 0 (warning only)" 0 \
  env PATH="$BIN:$PATH" sh "$SCRIPT" --marketplace="$FILE"
rm -rf "$BIN"; rm -f "$FILE"

# --- Tag not found → exit 2 ---

BIN=$(make_mock_gh)
MKT=$(make_marketplace)
assert_exit "tag not found exits 2" 2 \
  env GH_TAG_FAIL=1 PATH="$BIN:$PATH" sh "$SCRIPT" --marketplace="$MKT"
rm -rf "$BIN"; rm -f "$MKT"

# --- Version mismatch → exit 2 ---

BIN=$(make_mock_gh)
MKT=$(make_marketplace "1.0.0")
assert_exit "version mismatch exits 2" 2 \
  env GH_PLUGIN_VERSION=9.9.9 PATH="$BIN:$PATH" sh "$SCRIPT" --marketplace="$MKT"
rm -rf "$BIN"; rm -f "$MKT"

# --- All valid → exit 0 ---

BIN=$(make_mock_gh)
MKT=$(make_marketplace "1.0.0")
assert_exit "valid plugin exits 0" 0 \
  env GH_PLUGIN_VERSION=1.0.0 PATH="$BIN:$PATH" sh "$SCRIPT" --marketplace="$MKT"
rm -rf "$BIN"; rm -f "$MKT"

# --- Results ---

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
