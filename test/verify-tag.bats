#!/usr/bin/env bats

# Tests for steps/verify-tag.sh — the single most important gate.

load helpers

setup() {
  setup_fixture
}

teardown() {
  teardown_fixture
}

@test "verify-tag: passes when tag matches package.json version" {
  write_package_json '{"name":"pkg","version":"1.2.3"}'
  GIT_TAG="v1.2.3" run "$ACTION_ROOT/steps/verify-tag.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok: tag matches package.json version"* ]]
}

@test "verify-tag: passes when tag lacks v prefix" {
  write_package_json '{"name":"pkg","version":"1.2.3"}'
  GIT_TAG="1.2.3" run "$ACTION_ROOT/steps/verify-tag.sh"
  [ "$status" -eq 0 ]
}

@test "verify-tag: fails when tag does not match package.json" {
  write_package_json '{"name":"pkg","version":"1.2.3"}'
  GIT_TAG="v1.2.4" run "$ACTION_ROOT/steps/verify-tag.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tag/package.json mismatch"* ]]
}

@test "verify-tag: fails with no tag set" {
  write_package_json '{"name":"pkg","version":"1.2.3"}'
  unset GIT_TAG GITHUB_REF_NAME
  run "$ACTION_ROOT/steps/verify-tag.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no tag provided"* ]]
}

@test "verify-tag: fails when package.json has no version" {
  write_package_json '{"name":"pkg"}'
  GIT_TAG="v1.2.3" run "$ACTION_ROOT/steps/verify-tag.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no .version field"* ]]
}

@test "verify-tag: fails when package.json missing" {
  GIT_TAG="v1.2.3" run "$ACTION_ROOT/steps/verify-tag.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "verify-tag: honours GITHUB_REF_NAME fallback" {
  write_package_json '{"name":"pkg","version":"2.0.0"}'
  unset GIT_TAG
  GITHUB_REF_NAME="v2.0.0" run "$ACTION_ROOT/steps/verify-tag.sh"
  [ "$status" -eq 0 ]
}
