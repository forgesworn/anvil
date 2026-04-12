#!/usr/bin/env bats

# Tests for steps/verify-bump.sh -- the "verify" mode safety net.

load helpers

setup() {
  setup_fixture

  # Initialise a git repo with a tagged base version
  git init -q "$FIXTURE_DIR"
  cd "$FIXTURE_DIR" || return 1
  git config user.name "test"
  git config user.email "test@test"

  write_package_json '{"name":"pkg","version":"1.0.0"}'
  git add package.json
  git commit -q -m "initial"
  git tag v1.0.0
}

teardown() {
  teardown_fixture
}

commit_msg() {
  echo "$RANDOM" > "$FIXTURE_DIR/f_${RANDOM}"
  git add -A
  git commit -q -m "$1"
}

commit_with_body() {
  echo "$RANDOM" > "$FIXTURE_DIR/f_${RANDOM}"
  git add -A
  git commit -q -m "$1" -m "$2"
}

# ---------------------------------------------------------------------------
# Consistent bumps (pass)
# ---------------------------------------------------------------------------

@test "verify-bump: patch bump with fix commits passes" {
  commit_msg "fix: resolve null pointer"
  git tag v1.0.1

  GIT_TAG="v1.0.1" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bump is consistent"* ]]
}

@test "verify-bump: minor bump with feat commits passes" {
  commit_msg "feat: add widget"
  git tag v1.1.0

  GIT_TAG="v1.1.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bump is consistent"* ]]
}

@test "verify-bump: major bump with breaking change passes" {
  commit_msg "feat!: rewrite API"
  git tag v2.0.0

  GIT_TAG="v2.0.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Under-bumps (fail)
# ---------------------------------------------------------------------------

@test "verify-bump: patch bump with feat commits fails" {
  commit_msg "feat: add widget"
  git tag v1.0.1

  GIT_TAG="v1.0.1" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"under-bump"* ]]
}

@test "verify-bump: minor bump with breaking change fails" {
  commit_msg "feat!: rewrite API"
  git tag v1.1.0

  GIT_TAG="v1.1.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"under-bump"* ]]
}

@test "verify-bump: patch bump with BREAKING CHANGE footer fails" {
  commit_with_body "feat: new thing" "BREAKING CHANGE: old thing removed"
  git tag v1.0.1

  GIT_TAG="v1.0.1" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"under-bump"* ]]
}

# ---------------------------------------------------------------------------
# Over-bumps (warn, not fail)
# ---------------------------------------------------------------------------

@test "verify-bump: major bump with only fix commits warns but passes" {
  commit_msg "fix: small fix"
  git tag v2.0.0

  GIT_TAG="v2.0.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"over-bump"* ]]
}

@test "verify-bump: minor bump with only fix commits warns but passes" {
  commit_msg "fix: small fix"
  git tag v1.1.0

  GIT_TAG="v1.1.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"over-bump"* ]]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "verify-bump: first release with no prior tag passes" {
  # Remove the v1.0.0 tag so there's no prior version
  git tag -d v1.0.0
  git tag v1.0.0  # re-add as the "current" release tag

  # No prior tag to compare against
  GIT_TAG="v1.0.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"first release"* ]]
}

@test "verify-bump: no conventional commits skips verification" {
  commit_msg "just a regular commit"
  commit_msg "updated readme"
  git tag v1.0.1

  GIT_TAG="v1.0.1" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no releasable conventional commits"* ]]
}

@test "verify-bump: fails with no tag provided" {
  unset GIT_TAG GITHUB_REF_NAME
  run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no tag provided"* ]]
}

@test "verify-bump: fails when version is not greater than previous" {
  # v1.0.0 already exists. Tag a "regression" version after it.
  commit_msg "fix: something"
  git tag v0.9.0

  # prev_tag will be v1.0.0 (highest reachable excluding v0.9.0)
  # current is 0.9.0 which is less than 1.0.0
  GIT_TAG="v0.9.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not greater than"* ]]
}

@test "verify-bump: multi-digit version comparison works" {
  git tag -d v1.0.0
  write_package_json '{"name":"pkg","version":"10.0.0"}'
  git add package.json
  git commit -q -m "set v10"
  git tag v10.0.0

  commit_msg "feat: big feature"
  git tag v10.1.0

  GIT_TAG="v10.1.0" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bump is consistent"* ]]
}

@test "verify-bump: exact match bump passes without warning" {
  commit_msg "fix: exact patch fix"
  git tag v1.0.1

  GIT_TAG="v1.0.1" run "$ACTION_ROOT/steps/verify-bump.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bump is consistent"* ]]
  [[ "$output" != *"over-bump"* ]]
}
