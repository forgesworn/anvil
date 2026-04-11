#!/usr/bin/env bats

# Tests for steps/verify-action-pins.sh — flags `uses:` lines in
# .github/workflows/*.yml that aren't 40-char SHA pinned. Warn-only by
# default, hard-fail under STRICT_ACTION_PINS=1.

load helpers

setup() {
  setup_fixture
  export WORKFLOWS_DIR="$FIXTURE_DIR/.github/workflows"
  mkdir -p "$WORKFLOWS_DIR"
}

teardown() {
  teardown_fixture
  unset WORKFLOWS_DIR
  unset STRICT_ACTION_PINS
}

write_workflow() {
  local name="$1"
  local content="$2"
  printf '%s' "$content" > "$WORKFLOWS_DIR/$name"
}

@test "verify-action-pins: passes when no workflows directory exists" {
  rm -rf "$WORKFLOWS_DIR"
  run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}

@test "verify-action-pins: passes when workflows directory is empty" {
  run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}

@test "verify-action-pins: passes when every uses: line is SHA-pinned" {
  write_workflow ci.yml '
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: actions/setup-node@2028fbc5c25fe9cf00d9f06a71cc4710d4507903 # v6.0.0
'
  run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unpinned action"* ]]
}

@test "verify-action-pins: warns by default when an action is tag-pinned" {
  write_workflow ci.yml '
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
'
  run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unpinned action"* ]]
  [[ "$output" == *"actions/checkout@v4"* ]]
}

@test "verify-action-pins: strict mode fails on a tag-pinned action" {
  write_workflow ci.yml '
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
'
  STRICT_ACTION_PINS=1 run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unpinned action"* ]]
  [[ "$output" == *"strict-action-pins enabled"* ]]
}

@test "verify-action-pins: forgesworn/release-action is exempt by name" {
  write_workflow release.yml '
jobs:
  release:
    uses: forgesworn/release-action/.github/workflows/release.yml@v0
    with:
      vector-test-command: npm run test:vectors
'
  STRICT_ACTION_PINS=1 run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unpinned action"* ]]
}

@test "verify-action-pins: local ./action references are not flagged" {
  write_workflow ci.yml '
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: ./.github/actions/local-thing
'
  STRICT_ACTION_PINS=1 run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unpinned action"* ]]
}

@test "verify-action-pins: mixed pinned + unpinned warns only about the unpinned" {
  write_workflow ci.yml '
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
      - uses: actions/setup-node@v6
'
  run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"actions/setup-node@v6"* ]]
  [[ "$output" != *"actions/checkout@11bd71"* ]]
}

@test "verify-action-pins: ignores commented-out uses: lines" {
  write_workflow ci.yml '
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      # - uses: actions/checkout@v4
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
'
  STRICT_ACTION_PINS=1 run "$ACTION_ROOT/steps/verify-action-pins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unpinned action"* ]]
}
