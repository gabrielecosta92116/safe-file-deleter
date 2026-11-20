#!/usr/bin/env bash
# Tests for safe_file_deleter.sh. Run with: bash test_safe_file_deleter.sh

set -euo pipefail

tests_run=0
tests_failed=0

assert_eq() {
  local expected=$1 actual=$2 name=$3
  tests_run=$((tests_run + 1))
  if [[ $expected == "$actual" ]]; then
    printf 'ok %d - %s\n' "$tests_run" "$name"
  else
    tests_failed=$((tests_failed + 1))
    printf 'not ok %d - %s\n' "$tests_run" "$name"
    printf '  expected: %q\n' "$expected"
    printf '  actual:   %q\n' "$actual"
  fi
}

assert_true() {
  local name=$1
  shift
  tests_run=$((tests_run + 1))
  if "$@"; then
    printf 'ok %d - %s\n' "$tests_run" "$name"
  else
    tests_failed=$((tests_failed + 1))
    printf 'not ok %d - %s\n' "$tests_run" "$name"
  fi
}

assert_false() {
  local name=$1
  shift
  tests_run=$((tests_run + 1))
  if "$@"; then
    tests_failed=$((tests_failed + 1))
    printf 'not ok %d - %s\n' "$tests_run" "$name"
  else
    printf 'ok %d - %s\n' "$tests_run" "$name"
  fi
}

# Locate the library relative to this test script so the tests work from any cwd.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=safe_file_deleter.sh
source "$here/safe_file_deleter.sh"

workdir=$(mktemp -d)
trap 'rm -rf -- "$workdir"' EXIT

# --- happy path: trash then restore ---
root=$workdir/trash1
mkdir -p "$root"
file=$workdir/notes.txt
printf 'hello\n' > "$file"

entry=$(sfd_trash "$file" "$root")
assert_true "trash removes original" test ! -e "$file"
assert_true "trash creates payload" test -f "$root/$entry/payload"
assert_eq "hello" "$(cat "$root/$entry/payload")" "payload content preserved"
assert_eq "$file" "$(sfd_read_meta "$root/$entry/meta" original)" "metadata records original path"

restored=$(sfd_restore "$entry" "$root")
assert_eq "$file" "$restored" "restore reports original path"
assert_eq "hello" "$(cat "$file")" "restored content matches"
assert_true "entry directory cleaned up" test ! -e "$root/$entry"

# --- missing file is an error ---
assert_false "trash missing file fails" sfd_trash "$workdir/does-not-exist" "$root"

# --- directories are refused ---
mkdir -p "$workdir/adir"
assert_false "trash directory fails" sfd_trash "$workdir/adir" "$root"
assert_true "directory still present" test -d "$workdir/adir"

# --- restore refuses to overwrite ---
file2=$workdir/second.txt
printf 'second\n' > "$file2"
entry2=$(sfd_trash "$file2" "$root")
printf 'newer\n' > "$file2"
assert_false "restore refuses overwrite" sfd_restore "$entry2" "$root"
assert_eq "newer" "$(cat "$file2")" "existing file untouched"
assert_true "payload still in trash" test -f "$root/$entry2/payload"

# --- restore of unknown entry fails ---
assert_false "restore unknown entry fails" sfd_restore "no-such-entry" "$root"

# --- list shows restorable entries only ---
listing=$(sfd_list "$root" | sort)
assert_eq "$entry2" "$listing" "list shows the pending entry"

# --- two files with the same basename get distinct entries ---
mkdir -p "$workdir/a" "$workdir/b"
printf 'a\n' > "$workdir/a/same.txt"
printf 'b\n' > "$workdir/b/same.txt"
e1=$(sfd_trash "$workdir/a/same.txt" "$root")
e2=$(sfd_trash "$workdir/b/same.txt" "$root")
assert_true "distinct entries for same basename" test "$e1" != "$e2"
assert_eq "a" "$(cat "$root/$e1/payload")" "first same-name payload"
assert_eq "b" "$(cat "$root/$e2/payload")" "second same-name payload"

# --- restore recreates a missing parent directory ---
deep=$workdir/deep/nested/file.txt
mkdir -p "$workdir/deep/nested"
printf 'deep\n' > "$deep"
entry3=$(sfd_trash "$deep" "$root")
rm -rf -- "$workdir/deep"
sfd_restore "$entry3" "$root" >/dev/null
assert_true "restore recreates parent" test -f "$deep"
assert_eq "deep" "$(cat "$deep")" "deep content restored"

# --- list on a missing root is empty, not an error ---
assert_eq "" "$(sfd_list "$workdir/no-such-root")" "list of missing root is empty"

printf '\n%d tests, %d failures\n' "$tests_run" "$tests_failed"
if (( tests_failed > 0 )); then
  exit 1
fi
exit 0
