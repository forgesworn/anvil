#!/usr/bin/env bats

# Tests for steps/changelog-extract.sh — the CHANGELOG section extractor.

load helpers

setup() {
  setup_fixture
}

teardown() {
  teardown_fixture
}

write_changelog() {
  printf '%s\n' "$1" > "$FIXTURE_DIR/CHANGELOG.md"
}

@test "changelog-extract: extracts H2 section by version" {
  write_changelog '# Changelog

## [1.2.0] - 2026-04-01

- feature A
- feature B

## [1.1.0] - 2026-03-01

- old stuff'
  VERSION="1.2.0" run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature A"* ]]
  [[ "$output" == *"feature B"* ]]
  [[ "$output" != *"old stuff"* ]]
}

@test "changelog-extract: handles H1 headings (semantic-release style)" {
  write_changelog '# [1.4.0](https://example.com/compare/v1.3.0...v1.4.0) (2026-03-18)

### Features

* add a feature

## [1.3.2](https://example.com) (2026-03-18)

### Bug Fixes

* fix a bug'
  VERSION="1.4.0" run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"add a feature"* ]]
  [[ "$output" != *"fix a bug"* ]]
}

@test "changelog-extract: falls through to next H1 when starting on H1" {
  write_changelog '# [1.4.0] section one

content one

# [1.3.0] section two

content two'
  VERSION="1.4.0" run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"content one"* ]]
  [[ "$output" != *"content two"* ]]
}

@test "changelog-extract: fails when version section is absent" {
  write_changelog '## [1.0.0]

- only entry'
  VERSION="9.9.9" run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no CHANGELOG section found"* ]]
}

@test "changelog-extract: reads version from package.json when not overridden" {
  write_package_json '{"name":"pkg","version":"2.0.0"}'
  write_changelog '## [2.0.0]

- release notes'
  run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"release notes"* ]]
}

@test "changelog-extract: fails when CHANGELOG.md missing" {
  VERSION="1.0.0" run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "changelog-extract: handles nsec-tree real CHANGELOG format" {
  # Regression test: nsec-tree's semantic-release-generated CHANGELOG has
  # both H1 and H2 version headings on purpose (minors H1, patches H2).
  # Extracting 1.4.4 should stop at 1.4.3, and extracting 1.4.0 should
  # stop at 1.3.2 (skipping the Features/Bug Fixes sub-headings).
  write_changelog '## [1.4.4](https://github.com/forgesworn/nsec-tree/compare/v1.4.3...v1.4.4) (2026-04-10)


### Bug Fixes

* bound recovery purpose array length ([77d12ea])
* harden linkage proof and event parsing against injection ([fa4ff57])

## [1.4.3](https://github.com/forgesworn/nsec-tree/compare/v1.4.2...v1.4.3) (2026-03-31)


### Bug Fixes

* **protocol:** update attestation format to pipe delimiters in spec docs ([619eb19])

# [1.4.0](https://github.com/forgesworn/nsec-tree/compare/v1.3.2...v1.4.0) (2026-03-18)


### Features

* add deriveFromIdentity for arbitrary-depth key hierarchies ([a514968])

## [1.3.2](https://github.com/forgesworn/nsec-tree/compare/v1.3.1...v1.3.2) (2026-03-18)


### Bug Fixes

* earlier bug'
  VERSION="1.4.4" run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bound recovery purpose"* ]]
  [[ "$output" == *"harden linkage proof"* ]]
  [[ "$output" != *"pipe delimiters"* ]]

  VERSION="1.4.0" run "$ACTION_ROOT/steps/changelog-extract.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"deriveFromIdentity"* ]]
  [[ "$output" != *"earlier bug"* ]]
  [[ "$output" != *"pipe delimiters"* ]]
}
