#!/usr/bin/env bats

# Tests for steps/verify-exports.sh — the exports map sanity check.

load helpers

setup() {
  setup_fixture
}

teardown() {
  teardown_fixture
}

@test "verify-exports: passes when all exports targets exist" {
  write_package_json '{
    "name": "pkg",
    "version": "1.0.0",
    "exports": {
      ".": {
        "types": "./dist/index.d.ts",
        "import": "./dist/index.js"
      },
      "./core": {
        "types": "./dist/core.d.ts",
        "import": "./dist/core.js"
      }
    }
  }'
  write_file "dist/index.js" "export {};"
  write_file "dist/index.d.ts" "export {};"
  write_file "dist/core.js" "export {};"
  write_file "dist/core.d.ts" "export {};"
  run "$ACTION_ROOT/steps/verify-exports.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 4 export targets exist"* ]]
}

@test "verify-exports: fails when an exports target is missing" {
  write_package_json '{
    "name": "pkg",
    "version": "1.0.0",
    "exports": {
      ".": {
        "import": "./dist/index.js"
      },
      "./missing": {
        "import": "./dist/missing.js"
      }
    }
  }'
  write_file "dist/index.js" "export {};"
  run "$ACTION_ROOT/steps/verify-exports.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing: ./dist/missing.js"* ]]
  [[ "$output" == *"1 exports targets missing on disk"* ]]
}

@test "verify-exports: passes for legacy main-only package" {
  write_package_json '{
    "name": "pkg",
    "version": "1.0.0",
    "main": "./dist/index.js",
    "types": "./dist/index.d.ts"
  }'
  write_file "dist/index.js" "module.exports = {};"
  write_file "dist/index.d.ts" "export {};"
  run "$ACTION_ROOT/steps/verify-exports.sh"
  [ "$status" -eq 0 ]
}

@test "verify-exports: fails for legacy main that is missing" {
  write_package_json '{
    "name": "pkg",
    "version": "1.0.0",
    "main": "./dist/missing.js"
  }'
  write_file "dist/something-else.js" "export {};"
  run "$ACTION_ROOT/steps/verify-exports.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing: ./dist/missing.js"* ]]
}

@test "verify-exports: warns and exits zero when no exports declared" {
  write_package_json '{"name":"pkg","version":"1.0.0"}'
  run "$ACTION_ROOT/steps/verify-exports.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no exports or legacy entry points"* ]]
}

@test "verify-exports: handles deeply nested conditional exports" {
  write_package_json '{
    "name": "pkg",
    "version": "1.0.0",
    "exports": {
      ".": {
        "node": {
          "import": "./dist/node.js",
          "require": "./dist/node.cjs"
        },
        "default": "./dist/default.js"
      }
    }
  }'
  write_file "dist/node.js" "export {};"
  write_file "dist/node.cjs" "module.exports = {};"
  write_file "dist/default.js" "export {};"
  run "$ACTION_ROOT/steps/verify-exports.sh"
  [ "$status" -eq 0 ]
}
