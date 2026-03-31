#!/usr/bin/env sh
#
# Usage: update_readme_test.sh
#
# Tests for update_readme.sh.
#
# Dependencies:
#   sh, jq, awk, mktemp
#
# Exit status:
#   0   All tests passed
#   1   One or more tests failed
#
###
# Name: update_readme_test
# Version: 0.1.0
# Date: 2026-03-31
# Author: tgulls
# License: MIT
###

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/update_readme.sh"

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

make_fixtures() {
  dir=$(mktemp -d "${TMPDIR:-/tmp}/update_readme_test.XXXXXX")
  cat > "$dir/marketplace.json" <<'EOF'
{
  "plugins": [
    {
      "name": "my-plugin",
      "description": "Does something useful",
      "version": "1.2.3",
      "source": {
        "source": "github",
        "repo": "owner/my-plugin"
      }
    }
  ]
}
EOF
  cat > "$dir/README.md" <<'EOF'
# Title

Before section.

<!-- plugins-start -->
old table content
<!-- plugins-end -->

After section.
EOF
  printf '%s' "$dir"
}

# --- Argument validation ---

assert_exit "unknown option exits 2" 2 \
  sh "$SCRIPT" --bogus

# --- File validation ---

DIR=$(make_fixtures)
assert_exit "missing marketplace exits 1" 1 \
  sh "$SCRIPT" --marketplace=/nonexistent.json --readme="$DIR/README.md"
rm -rf "$DIR"

DIR=$(make_fixtures)
assert_exit "missing readme exits 1" 1 \
  sh "$SCRIPT" --marketplace="$DIR/marketplace.json" --readme=/nonexistent.md
rm -rf "$DIR"

# --- Table generation ---

DIR=$(make_fixtures)
sh "$SCRIPT" \
  --marketplace="$DIR/marketplace.json" \
  --readme="$DIR/README.md" > /dev/null

result=$(grep -c 'my-plugin' "$DIR/README.md")
assert_eq "plugin name appears in output" "1" "$result"

result=$(grep -c '1.2.3' "$DIR/README.md")
assert_eq "version appears in output" "1" "$result"

result=$(grep -c 'Before section.' "$DIR/README.md")
assert_eq "content before markers preserved" "1" "$result"

result=$(grep -c 'After section.' "$DIR/README.md")
assert_eq "content after markers preserved" "1" "$result"

old=0
grep -q 'old table content' "$DIR/README.md" || old=1
assert_eq "old table content replaced" "1" "$old"

rm -rf "$DIR"

# --- GitHub link generation ---

DIR=$(make_fixtures)
sh "$SCRIPT" \
  --marketplace="$DIR/marketplace.json" \
  --readme="$DIR/README.md" > /dev/null

result=$(grep -c 'github.com/owner/my-plugin' "$DIR/README.md")
assert_eq "github source generates repo link" "1" "$result"
rm -rf "$DIR"

# --- Plugin with no source repo (no link) ---

DIR=$(mktemp -d "${TMPDIR:-/tmp}/update_readme_test.XXXXXX")
cat > "$DIR/marketplace.json" <<'EOF'
{
  "plugins": [
    {
      "name": "local-plugin",
      "description": "A local plugin",
      "version": "0.1.0",
      "source": { "source": "local" }
    }
  ]
}
EOF
cat > "$DIR/README.md" <<'EOF'
<!-- plugins-start -->
<!-- plugins-end -->
EOF
sh "$SCRIPT" \
  --marketplace="$DIR/marketplace.json" \
  --readme="$DIR/README.md" > /dev/null

result=$(grep -c 'local-plugin' "$DIR/README.md")
assert_eq "local plugin name appears without link" "1" "$result"
rm -rf "$DIR"

# --- Results ---

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
