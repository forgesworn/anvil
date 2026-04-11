#!/usr/bin/env bats

# Tests for steps/verify-secrets.sh — the pre-publish secret scan.

load helpers

setup() {
  setup_fixture
}

teardown() {
  teardown_fixture
}

@test "verify-secrets: passes for clean dist" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  write_file "dist/index.js" "export const answer = 42;"
  write_file "dist/index.d.ts" "export declare const answer: number;"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no forbidden filenames"* ]]
}

@test "verify-secrets: fails on .env file in dist" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  write_file "dist/index.js" "export {};"
  write_file "dist/.env" "SECRET=hunter2"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden filename"* ]]
}

@test "verify-secrets: fails on .pem file" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  write_file "dist/index.js" "export {};"
  write_file "dist/keys/server.pem" "dummy"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"*.pem"* ]]
}

@test "verify-secrets: fails on PRIVATE KEY marker in content" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  write_file "dist/index.js" "// -----BEGIN RSA PRIVATE KEY-----"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden content"* ]]
}

@test "verify-secrets: fails on nsec1 in content" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  # 58 chars of bech32 alphabet after nsec1 — regex uses a real pattern.
  write_file "dist/index.js" "const leaked = 'nsec1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqxkxkhpw';"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden content"* ]]
}

@test "verify-secrets: fails on AWS access key prefix" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  write_file "dist/index.js" "const key = 'AKIAIOSFODNN7EXAMPLE';"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden content"* ]]
}

@test "verify-secrets: fails when no packable artefacts exist" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no packable artefacts"* ]]
}

@test "verify-secrets: scans files listed in package.json files" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist","PROTOCOL.md"]}'
  write_file "dist/index.js" "export {};"
  write_file "PROTOCOL.md" "some protocol doc"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 0 ]
}
