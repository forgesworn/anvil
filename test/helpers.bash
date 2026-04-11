#!/usr/bin/env bash
# Shared bats helpers for release-action tests.
#
# Each test creates its own fixture directory under a temp dir and runs
# the step scripts with that as CWD. Scripts themselves are sourced from
# $ACTION_ROOT/steps/, which is set from BATS_TEST_DIRNAME.

# ACTION_ROOT is the top of the release-action repo, resolved relative to
# this helper file.
ACTION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ACTION_ROOT

setup_fixture() {
  FIXTURE_DIR="$(mktemp -d -t release-action-bats.XXXXXX)"
  export FIXTURE_DIR
  cd "$FIXTURE_DIR" || return 1
}

teardown_fixture() {
  if [[ -n "${FIXTURE_DIR:-}" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

write_package_json() {
  printf '%s\n' "$1" > "$FIXTURE_DIR/package.json"
}

write_file() {
  local path="$1"
  local content="$2"
  mkdir -p "$(dirname "$FIXTURE_DIR/$path")"
  printf '%s' "$content" > "$FIXTURE_DIR/$path"
}
