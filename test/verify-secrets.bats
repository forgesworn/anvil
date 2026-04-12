#!/usr/bin/env bats

# Tests for steps/verify-secrets.sh -- the pre-publish secret scan.
#
# verify-secrets uses `npm pack --dry-run --json` to derive the exact
# set of files npm would publish, then scans those for forbidden
# filenames and content patterns.

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
  # 58 chars of bech32 alphabet after nsec1 -- regex uses a real pattern.
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

@test "verify-secrets: scans files listed in package.json files" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist","PROTOCOL.md"]}'
  write_file "dist/index.js" "export {};"
  write_file "PROTOCOL.md" "some protocol doc"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 0 ]
}

@test "verify-secrets: allows nsec1 test vectors in PROTOCOL.md" {
  # Regression: crypto libraries publish documentation containing example
  # derived secrets (test vectors). Those are intentional. Secret-marker
  # content scans must skip common documentation extensions while
  # filename checks stay universal.
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist","PROTOCOL.md"]}'
  write_file "dist/index.js" "export {};"
  write_file "PROTOCOL.md" "
child_nsec = nsec1nr5ck3mw4v7zhj6syrj2v7dyrd6wa0anpgregnzrv8ysv5qjvhnsafv7mx
child_nsec = nsec1l3329mrljxtscjzln469xf5drf4qwfe7aq5u73xgw6zl0p6c7p8sd6vumk
"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 0 ]
}

@test "verify-secrets: still catches nsec1 in source code (not just docs)" {
  write_package_json '{"name":"pkg","version":"1.0.0","files":["dist"]}'
  write_file "dist/bad.js" "const leaked = 'nsec1nr5ck3mw4v7zhj6syrj2v7dyrd6wa0anpgregnzrv8ysv5qjvhnsafv7mx';"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden content"* ]]
}

@test "verify-secrets: catches secrets in glob-matched files" {
  # Regression: files field supports globs. The old implementation treated
  # glob entries as literal paths, silently dropping them from the scan.
  # npm pack correctly expands globs, so the new implementation catches
  # secrets in glob-matched files.
  write_package_json '{"name":"pkg","version":"1.0.0","files":["src/**/*.js"]}'
  write_file "src/index.js" "export {};"
  write_file "src/keys/leak.js" "const key = 'AKIAIOSFODNN7EXAMPLE';"
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden content"* ]]
  [[ "$output" == *"src/keys/leak.js"* ]]
}

@test "verify-secrets: fails when package.json is missing" {
  run "$ACTION_ROOT/steps/verify-secrets.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}
