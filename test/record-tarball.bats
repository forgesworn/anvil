#!/usr/bin/env bats

# Tests for steps/record-tarball.sh — packs the release artefact and
# writes a meta file containing filename, size, sha256, sha512 integrity.

load helpers

setup() {
  setup_fixture
  export TARBALL_META_DIR="$FIXTURE_DIR/meta"
  # Keep RUNNER_TEMP unset so the script honours our explicit override
  # rather than the runner default.
  unset RUNNER_TEMP
  # Tests run in a temp dir that has no git checkout, so the script
  # cannot derive SOURCE_DATE_EPOCH from git. Pin a fixed value so
  # mtime normalisation has something deterministic to use.
  export SOURCE_DATE_EPOCH=1700000000
}

teardown() {
  teardown_fixture
  unset TARBALL_META_DIR
  unset SOURCE_DATE_EPOCH
}

@test "record-tarball: writes meta file with hashes for a minimal package" {
  command -v npm >/dev/null 2>&1 || skip "npm not available"

  write_package_json '{"name":"test-pkg","version":"1.0.0","files":["index.js"]}'
  write_file "index.js" "module.exports = 42;"

  run "$ACTION_ROOT/steps/record-tarball.sh"
  [ "$status" -eq 0 ]

  meta="$TARBALL_META_DIR/tarball.meta"
  [ -f "$meta" ]

  # All required keys must be present, with sane formats.
  grep -q '^filename=' "$meta"
  grep -q '^path=' "$meta"
  grep -q '^size=' "$meta"
  grep -qE '^sha256=[0-9a-f]{64}$' "$meta"
  grep -q '^integrity=sha512-' "$meta"

  # The recorded tarball must actually exist on disk.
  recorded_path="$(grep '^path=' "$meta" | cut -d= -f2-)"
  [ -f "$recorded_path" ]
}

@test "record-tarball: fails when package.json is missing" {
  command -v npm >/dev/null 2>&1 || skip "npm not available"

  run "$ACTION_ROOT/steps/record-tarball.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"package.json not found"* ]]
}

@test "record-tarball: honours an alternative TARBALL_META_DIR" {
  command -v npm >/dev/null 2>&1 || skip "npm not available"

  write_package_json '{"name":"test-pkg","version":"1.2.3","files":["index.js"]}'
  write_file "index.js" "module.exports = 1;"

  export TARBALL_META_DIR="$FIXTURE_DIR/custom-meta"
  run "$ACTION_ROOT/steps/record-tarball.sh"
  [ "$status" -eq 0 ]
  [ -f "$FIXTURE_DIR/custom-meta/tarball.meta" ]
}

@test "record-tarball: filename matches the package name and version" {
  command -v npm >/dev/null 2>&1 || skip "npm not available"

  write_package_json '{"name":"test-pkg","version":"1.4.2","files":["index.js"]}'
  write_file "index.js" "module.exports = {};"

  run "$ACTION_ROOT/steps/record-tarball.sh"
  [ "$status" -eq 0 ]

  meta="$TARBALL_META_DIR/tarball.meta"
  filename="$(grep '^filename=' "$meta" | cut -d= -f2-)"
  [[ "$filename" == "test-pkg-1.4.2.tgz" ]]
}

@test "record-tarball: two consecutive packs of the same fixture produce the same sha256" {
  command -v npm >/dev/null 2>&1 || skip "npm not available"

  write_package_json '{"name":"repro-pkg","version":"1.0.0","files":["index.js"]}'
  write_file "index.js" "module.exports = 'reproducible';"

  # First pack into meta-a
  export TARBALL_META_DIR="$FIXTURE_DIR/meta-a"
  run "$ACTION_ROOT/steps/record-tarball.sh"
  [ "$status" -eq 0 ]
  sha_a="$(grep '^sha256=' "$FIXTURE_DIR/meta-a/tarball.meta" | cut -d= -f2-)"

  # Second pack into meta-b, same SOURCE_DATE_EPOCH
  export TARBALL_META_DIR="$FIXTURE_DIR/meta-b"
  run "$ACTION_ROOT/steps/record-tarball.sh"
  [ "$status" -eq 0 ]
  sha_b="$(grep '^sha256=' "$FIXTURE_DIR/meta-b/tarball.meta" | cut -d= -f2-)"

  # Both packs of identical content with identical mtimes must hash equal.
  [ -n "$sha_a" ]
  [ -n "$sha_b" ]
  [ "$sha_a" = "$sha_b" ]
}

@test "record-tarball: fails when SOURCE_DATE_EPOCH is unset and no git is available" {
  command -v npm >/dev/null 2>&1 || skip "npm not available"

  write_package_json '{"name":"test-pkg","version":"1.0.0","files":["index.js"]}'
  write_file "index.js" "module.exports = 1;"

  unset SOURCE_DATE_EPOCH
  run "$ACTION_ROOT/steps/record-tarball.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SOURCE_DATE_EPOCH"* ]]
}
