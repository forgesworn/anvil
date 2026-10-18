#!/usr/bin/env bats

# Tests for the "Update CHANGELOG" step in .github/workflows/auto-release.yml.
# The step is inline shell, so each test pulls its run block out of the
# workflow and runs that, keeping the tested code and the shipped code
# the same.

load helpers

setup() {
  setup_fixture
  TODAY="$(date -u +%Y-%m-%d)"
}

teardown() {
  teardown_fixture
}

update_changelog() {
  local script
  script="$(awk '
    /^      - name: Update CHANGELOG$/ { found = 1; next }
    found && /^        run: \|$/ { inrun = 1; next }
    inrun && /^      - name:/ { exit }
    inrun { sub(/^          /, ""); print }
  ' "$ACTION_ROOT/.github/workflows/auto-release.yml")"
  [[ -n "$script" ]] || return 1
  NEXT_VERSION="$1" CHANGELOG="$2" CHANGELOG_FILE="" bash -c "$script"
}

write_changelog() {
  printf '%s' "$1" > "$FIXTURE_DIR/CHANGELOG.md"
}

@test "auto-release changelog: a major H1 heading is not treated as the title" {
  write_changelog '## [2.0.1](https://example.test/compare) (2026-04-07)

- fix

# [2.0.0](https://example.test/compare) (2026-03-30)

- breaking
'
  run update_changelog 2.0.2 '- new fix'
  [ "$status" -eq 0 ]
  expected="## 2.0.2 (${TODAY})

- new fix

## [2.0.1](https://example.test/compare) (2026-04-07)

- fix

# [2.0.0](https://example.test/compare) (2026-03-30)

- breaking"
  [ "$(cat CHANGELOG.md)" = "$expected" ]
}

@test "auto-release changelog: goes above a major H1 on the first line" {
  write_changelog '# [3.0.0](https://example.test/compare) (2026-09-05)

### Features

- feature
'
  run update_changelog 3.0.1 '- docs fix'
  [ "$status" -eq 0 ]
  [ "$(head -1 CHANGELOG.md)" = "## 3.0.1 (${TODAY})" ]
  [ "$(grep -n '^# \[3.0.0\]' CHANGELOG.md | cut -d: -f1)" -eq 5 ]
}

@test "auto-release changelog: goes after the title and above the first version" {
  write_changelog '# Changelog

All notable changes.

## 1.0.0 (2026-01-01)

- first
'
  run update_changelog 1.0.1 '- second'
  [ "$status" -eq 0 ]
  expected="# Changelog

All notable changes.

## 1.0.1 (${TODAY})

- second

## 1.0.0 (2026-01-01)

- first"
  [ "$(cat CHANGELOG.md)" = "$expected" ]
}

@test "auto-release changelog: notes above the version list stay on top" {
  write_changelog '## Migrating from v2 to v3

Notes.

## 3.0.3 (2026-07-19)

- fix
'
  run update_changelog 3.0.4 '- docs'
  [ "$status" -eq 0 ]
  [ "$(head -1 CHANGELOG.md)" = "## Migrating from v2 to v3" ]
  [ "$(grep -n '^## ' CHANGELOG.md | cut -d: -f2-)" = "## Migrating from v2 to v3
## 3.0.4 (${TODAY})
## 3.0.3 (2026-07-19)" ]
}

@test "auto-release changelog: title with no versions gets the section after it" {
  write_changelog '# Changelog
'
  run update_changelog 0.1.0 '- initial'
  [ "$status" -eq 0 ]
  [ "$(cat CHANGELOG.md)" = "# Changelog

## 0.1.0 (${TODAY})

- initial" ]
}

@test "auto-release changelog: no headings at all puts the section on top" {
  write_changelog 'Just some text.
'
  run update_changelog 0.1.0 '- initial'
  [ "$status" -eq 0 ]
  [ "$(cat CHANGELOG.md)" = "## 0.1.0 (${TODAY})

- initial

Just some text." ]
}

@test "auto-release changelog: missing file is created with a title" {
  run update_changelog 1.0.0 '- first'
  [ "$status" -eq 0 ]
  [ "$(cat CHANGELOG.md)" = "# Changelog

## 1.0.0 (${TODAY})

- first" ]
}

@test "auto-release changelog: keeps a last line with no trailing newline" {
  write_changelog '## 1.0.0 (2026-01-01)

- last line'
  run update_changelog 1.0.1 '- next'
  [ "$status" -eq 0 ]
  [ "$(tail -1 CHANGELOG.md)" = "- last line" ]
}
