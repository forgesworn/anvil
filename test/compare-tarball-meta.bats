#!/usr/bin/env bats

# Tests for steps/compare-tarball-meta.sh — the v0.4 reproducibility
# gate. Compares two tarball.meta files for byte-equivalent sha256.

load helpers

setup() {
  setup_fixture
}

teardown() {
  teardown_fixture
  unset STRICT
  unset GITHUB_OUTPUT
}

write_meta() {
  local name="$1"
  local sha="$2"
  cat > "$FIXTURE_DIR/$name" <<EOF
filename=test-pkg-1.0.0.tgz
path=/tmp/forgesworn-anvil/test-pkg-1.0.0.tgz
size=1234
unpacked_size=5678
sha256=$sha
integrity=sha512-AAAA
EOF
}

@test "compare-tarball-meta: passes when sha256 matches" {
  write_meta "a.meta" "abc123"
  write_meta "b.meta" "abc123"

  run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta" "$FIXTURE_DIR/b.meta"
  [ "$status" -eq 0 ]
  [[ "$output" == *"byte-identical"* ]]
}

@test "compare-tarball-meta: fails under STRICT when sha256 differs" {
  write_meta "a.meta" "aaa111"
  write_meta "b.meta" "bbb222"

  STRICT=1 run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta" "$FIXTURE_DIR/b.meta"
  [ "$status" -eq 1 ]
  [[ "$output" == *"diverged"* ]]
  [[ "$output" == *"strict mode"* ]]
}

@test "compare-tarball-meta: warns and exits 0 in non-strict when sha256 differs" {
  write_meta "a.meta" "aaa111"
  write_meta "b.meta" "bbb222"

  run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta" "$FIXTURE_DIR/b.meta"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diverged"* ]]
  [[ "$output" == *"non-strict mode"* ]]
}

@test "compare-tarball-meta: writes reproducible=1 to GITHUB_OUTPUT on match" {
  write_meta "a.meta" "abc123"
  write_meta "b.meta" "abc123"

  export GITHUB_OUTPUT="$FIXTURE_DIR/gh_output"
  : > "$GITHUB_OUTPUT"

  run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta" "$FIXTURE_DIR/b.meta"
  [ "$status" -eq 0 ]
  grep -q '^reproducible=1$' "$GITHUB_OUTPUT"
}

@test "compare-tarball-meta: writes reproducible=0 to GITHUB_OUTPUT on mismatch (warn mode)" {
  write_meta "a.meta" "aaa"
  write_meta "b.meta" "bbb"

  export GITHUB_OUTPUT="$FIXTURE_DIR/gh_output"
  : > "$GITHUB_OUTPUT"

  run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta" "$FIXTURE_DIR/b.meta"
  [ "$status" -eq 0 ]
  grep -q '^reproducible=0$' "$GITHUB_OUTPUT"
}

@test "compare-tarball-meta: fails when called with too few args" {
  run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage"* ]]
}

@test "compare-tarball-meta: fails when a meta file is missing" {
  write_meta "a.meta" "abc"
  run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta" "$FIXTURE_DIR/missing.meta"
  [ "$status" -eq 1 ]
  [[ "$output" == *"meta file not found"* ]]
}

@test "compare-tarball-meta: fails when a meta file lacks sha256" {
  cat > "$FIXTURE_DIR/a.meta" <<EOF
filename=test-pkg-1.0.0.tgz
EOF
  cat > "$FIXTURE_DIR/b.meta" <<EOF
filename=test-pkg-1.0.0.tgz
sha256=abc123
EOF
  run "$ACTION_ROOT/steps/compare-tarball-meta.sh" "$FIXTURE_DIR/a.meta" "$FIXTURE_DIR/b.meta"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing sha256"* ]]
}
