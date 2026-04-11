#!/usr/bin/env bats

# Tests for steps/normalise-mtimes.sh — touches every file/dir under
# cwd to $SOURCE_DATE_EPOCH so a subsequent npm pack produces tar
# headers that are byte-identical between independent runs.

load helpers

setup() {
  setup_fixture
  export SOURCE_DATE_EPOCH=1700000000
}

teardown() {
  teardown_fixture
  unset SOURCE_DATE_EPOCH
}

# Cross-platform mtime read: BSD stat (macOS) and GNU stat (Linux).
file_mtime() {
  if stat -c %Y "$1" 2>/dev/null; then
    return 0
  fi
  stat -f %m "$1"
}

@test "normalise-mtimes: touches files in cwd to SOURCE_DATE_EPOCH" {
  write_file "index.js" "module.exports = 1;"
  write_file "README.md" "# hi"

  run "$ACTION_ROOT/steps/normalise-mtimes.sh"
  [ "$status" -eq 0 ]

  [ "$(file_mtime "$FIXTURE_DIR/index.js")" -eq 1700000000 ]
  [ "$(file_mtime "$FIXTURE_DIR/README.md")" -eq 1700000000 ]
}

@test "normalise-mtimes: touches files inside subdirectories" {
  write_file "src/lib/util.js" "export {};"
  write_file "dist/index.js" "exports.a = 1;"

  run "$ACTION_ROOT/steps/normalise-mtimes.sh"
  [ "$status" -eq 0 ]

  [ "$(file_mtime "$FIXTURE_DIR/src/lib/util.js")" -eq 1700000000 ]
  [ "$(file_mtime "$FIXTURE_DIR/dist/index.js")" -eq 1700000000 ]
}

@test "normalise-mtimes: skips node_modules" {
  write_file "node_modules/foo/index.js" "module.exports = {};"

  # Stamp the file with a known different mtime first.
  touch -t 200001010000.00 "$FIXTURE_DIR/node_modules/foo/index.js"
  before="$(file_mtime "$FIXTURE_DIR/node_modules/foo/index.js")"

  run "$ACTION_ROOT/steps/normalise-mtimes.sh"
  [ "$status" -eq 0 ]

  after="$(file_mtime "$FIXTURE_DIR/node_modules/foo/index.js")"
  # mtime must be unchanged — node_modules was pruned.
  [ "$before" -eq "$after" ]
  [ "$after" -ne 1700000000 ]
}

@test "normalise-mtimes: skips .git" {
  write_file ".git/HEAD" "ref: refs/heads/main"
  touch -t 200001010000.00 "$FIXTURE_DIR/.git/HEAD"
  before="$(file_mtime "$FIXTURE_DIR/.git/HEAD")"

  run "$ACTION_ROOT/steps/normalise-mtimes.sh"
  [ "$status" -eq 0 ]

  after="$(file_mtime "$FIXTURE_DIR/.git/HEAD")"
  [ "$before" -eq "$after" ]
  [ "$after" -ne 1700000000 ]
}

@test "normalise-mtimes: fails when SOURCE_DATE_EPOCH is unset" {
  write_file "index.js" "x"
  unset SOURCE_DATE_EPOCH
  run "$ACTION_ROOT/steps/normalise-mtimes.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SOURCE_DATE_EPOCH not set"* ]]
}

@test "normalise-mtimes: fails when SOURCE_DATE_EPOCH is non-numeric" {
  write_file "index.js" "x"
  export SOURCE_DATE_EPOCH="not-a-number"
  run "$ACTION_ROOT/steps/normalise-mtimes.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unix timestamp"* ]]
}
