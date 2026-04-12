#!/usr/bin/env bats

# Tests for steps/parse-commits.sh -- conventional commit parser.

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

# Helper: commit with a message
commit_msg() {
  # Touch a file to ensure there's something to commit
  echo "$RANDOM" > "$FIXTURE_DIR/f_${RANDOM}"
  git add -A
  git commit -q -m "$1" ${2:+--trailer "$2"}
}

# Helper: commit with a body (for BREAKING CHANGE footer)
commit_with_body() {
  local subject="$1"
  local body="$2"
  echo "$RANDOM" > "$FIXTURE_DIR/f_${RANDOM}"
  git add -A
  git commit -q -m "$subject" -m "$body"
}

# ---------------------------------------------------------------------------
# Bump detection
# ---------------------------------------------------------------------------

@test "parse-commits: fix commit produces patch bump" {
  commit_msg "fix: resolve null pointer"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "patch" ]
  [ "$next_version" = "1.0.1" ]
}

@test "parse-commits: feat commit produces minor bump" {
  commit_msg "feat: add widget support"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "minor" ]
  [ "$next_version" = "1.1.0" ]
}

@test "parse-commits: bang syntax produces major bump" {
  commit_msg "feat!: rewrite public API"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "major" ]
  [ "$next_version" = "2.0.0" ]
}

@test "parse-commits: BREAKING CHANGE footer produces major bump" {
  commit_with_body "feat: add new parser" "BREAKING CHANGE: removes legacy API"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "major" ]
  [ "$next_version" = "2.0.0" ]
}

@test "parse-commits: scoped commit is parsed correctly" {
  commit_msg "feat(parser): support nested arrays"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "minor" ]
  [[ "$(cat "$FIXTURE_DIR/out.changelog")" == *"(parser)"* ]]
}

@test "parse-commits: scoped bang produces major bump" {
  commit_msg "fix(auth)!: require token on all endpoints"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "major" ]
  [ "$next_version" = "2.0.0" ]
}

# ---------------------------------------------------------------------------
# Bump precedence
# ---------------------------------------------------------------------------

@test "parse-commits: feat wins over fix" {
  commit_msg "fix: patch something"
  commit_msg "feat: add something"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "minor" ]
  [ "$next_version" = "1.1.0" ]
}

@test "parse-commits: breaking wins over feat" {
  commit_msg "feat: add something"
  commit_msg "fix!: this breaks things"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "major" ]
}

# ---------------------------------------------------------------------------
# Non-releasable commits
# ---------------------------------------------------------------------------

@test "parse-commits: chore/docs/test produce no bump" {
  commit_msg "chore: update deps"
  commit_msg "docs: fix typo"
  commit_msg "test: add coverage"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "none" ]
  [ "$next_version" = "1.0.0" ]
}

@test "parse-commits: non-conventional commits produce no bump" {
  commit_msg "just a regular commit message"
  commit_msg "Updated the readme"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "none" ]
}

# ---------------------------------------------------------------------------
# Changelog output
# ---------------------------------------------------------------------------

@test "parse-commits: changelog groups by type" {
  commit_msg "feat: add widget"
  commit_msg "fix: resolve crash"
  commit_msg "feat!: rewrite engine"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  changelog="$(cat "$FIXTURE_DIR/out.changelog")"
  [[ "$changelog" == *"### Breaking Changes"* ]]
  [[ "$changelog" == *"### Features"* ]]
  [[ "$changelog" == *"### Bug Fixes"* ]]
  [[ "$changelog" == *"rewrite engine"* ]]
  [[ "$changelog" == *"add widget"* ]]
  [[ "$changelog" == *"resolve crash"* ]]
}

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

@test "parse-commits: no commits since tag produces no bump" {
  # v1.0.0 tag is on HEAD, no new commits
  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "none" ]
}

@test "parse-commits: works with no prior tag (first release)" {
  # Remove the tag
  git tag -d v1.0.0

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    CURRENT_VERSION="0.0.0" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]
}

@test "parse-commits: respects BASE_TAG override" {
  commit_msg "feat: first feature"
  git tag v1.1.0
  commit_msg "fix: a fix after 1.1.0"

  # Parse only commits since v1.1.0, not v1.0.0
  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    BASE_TAG="v1.1.0" \
    CURRENT_VERSION="1.1.0" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "patch" ]
  [ "$next_version" = "1.1.1" ]
}

@test "parse-commits: BREAKING-CHANGE hyphenated footer works" {
  commit_with_body "feat: new thing" "BREAKING-CHANGE: old thing removed"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "major" ]
}

@test "parse-commits: multi-digit versions are handled correctly" {
  git tag -d v1.0.0
  write_package_json '{"name":"pkg","version":"10.20.30"}'
  git add package.json
  git commit -q -m "set multi-digit version"
  git tag v10.20.30

  commit_msg "fix: a fix"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "patch" ]
  [ "$next_version" = "10.20.31" ]
}

@test "parse-commits: merge commit messages are ignored" {
  commit_msg "feat: real feature"
  commit_msg "Merge pull request #42 from feature-branch"
  commit_msg "Merge branch 'main' into develop"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  # Only the feat commit should count
  [ "$bump" = "minor" ]
}

@test "parse-commits: refactor/perf/style/ci/build produce no bump" {
  commit_msg "refactor: restructure modules"
  commit_msg "perf: optimise hot loop"
  commit_msg "style: fix whitespace"
  commit_msg "ci: update workflow"
  commit_msg "build: update esbuild"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "none" ]
}

@test "parse-commits: tags on other branches are ignored" {
  # Create a branch with a higher tag that is NOT merged into main
  git checkout -b other-branch
  commit_msg "feat: other branch feature"
  git tag v9.0.0
  git checkout -

  # Back on main, add a fix
  commit_msg "fix: main branch fix"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  # Should use v1.0.0 as base (on main), not v9.0.0 (on other branch)
  [ "$bump" = "patch" ]
  [ "$next_version" = "1.0.1" ]
}

@test "parse-commits: 0.x version bumps work correctly" {
  git tag -d v1.0.0
  write_package_json '{"name":"pkg","version":"0.3.7"}'
  git add package.json
  git commit -q -m "set 0.x version"
  git tag v0.3.7

  commit_msg "feat: new feature in 0.x"

  PARSE_COMMITS_OUT="$FIXTURE_DIR/out" \
    run "$ACTION_ROOT/steps/parse-commits.sh"
  [ "$status" -eq 0 ]

  source "$FIXTURE_DIR/out"
  [ "$bump" = "minor" ]
  [ "$next_version" = "0.4.0" ]
}
