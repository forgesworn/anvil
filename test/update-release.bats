#!/usr/bin/env bats

# Tests for steps/update-release.sh — focused on the registry-side
# tarball filename construction in the verify recipe. This is a
# regression guard for the scoped-package URL bug surfaced during the
# Phase 3 pilot on @forgesworn/shamir-words@1.1.0 and fixed in
# 21687101.
#
# The bug: the verify recipe used the local `npm pack` filename in
# the URL path. For unscoped packages this works because the local
# pack name equals the registry-side name. For scoped packages npm
# flattens the scope with a dash in the local filename but the
# registry serves the tarball at the unscoped basename within the
# scope-namespaced path:
#
#   local pack:    scope-pkg-1.0.0.tgz
#   registry url:  https://registry.npmjs.org/@scope/pkg/-/pkg-1.0.0.tgz
#
# These tests use a fake `gh` on PATH that logs every invocation to a
# file. After running update-release.sh we grep that log for the URL
# we expect.

load helpers

setup() {
  setup_fixture

  meta_dir="$FIXTURE_DIR/meta"
  mkdir -p "$meta_dir"

  bin_dir="$FIXTURE_DIR/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/gh" <<'GH'
#!/usr/bin/env bash
# Fake gh: log all args (including the multi-line --notes value) to
# a file the test can grep against. Exit behaviour for `release view`
# is driven by $GH_RELEASE_MODE so tests can exercise both the
# create-or-update branches in update-release.sh:
#   (unset|existing) - all commands succeed (legacy / pre-existing Release)
#   missing          - `release view` exits 1 (chained flow / 404 case)
#   error            - `release view` exits 2 (non-404 error)
# All other subcommands always exit 0 so tests can inspect the call log.
{
  printf 'GH_CALL: '
  printf '%s ' "$@"
  printf '\n'
} >> "$GH_LOG"

if [[ "${1:-}" == "release" && "${2:-}" == "view" ]]; then
  case "${GH_RELEASE_MODE:-existing}" in
    missing) exit 1 ;;
    error)   exit 2 ;;
    *)       exit 0 ;;
  esac
fi

exit 0
GH
  chmod +x "$bin_dir/gh"

  export GH_LOG="$FIXTURE_DIR/gh.log"
  : > "$GH_LOG"
  export PATH="$bin_dir:$PATH"
  export TARBALL_META_DIR="$meta_dir"
}

teardown() {
  teardown_fixture
  unset TARBALL_META_DIR
  unset GH_LOG
  unset GIT_TAG
  unset GH_RELEASE_MODE
  unset GITHUB_SHA
}

write_meta_for() {
  # $1: local pack filename
  local filename="$1"
  cat > "$meta_dir/tarball.meta" <<EOF
filename=${filename}
path=${meta_dir}/${filename}
size=1234
unpacked_size=5678
sha256=abc123
integrity=sha512-AAAA
EOF
  # The script will try to upload the tarball as a release asset, so
  # the file needs to exist on disk (an empty file is fine for the
  # fake gh).
  : > "$meta_dir/${filename}"
}

@test "update-release: scoped package URL uses unscoped basename" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"@forgesworn/shamir-words","version":"1.1.0","files":["dist"]}'
  write_file "CHANGELOG.md" '## 1.1.0

- changes
'
  write_meta_for "forgesworn-shamir-words-1.1.0.tgz"
  export GIT_TAG="v1.1.0"

  run "$ACTION_ROOT/steps/update-release.sh"
  [ "$status" -eq 0 ]

  # Positive: the registry URL must use the unscoped basename inside
  # the scope-namespaced path.
  grep -q 'https://registry.npmjs.org/@forgesworn/shamir-words/-/shamir-words-1.1.0.tgz' "$GH_LOG"

  # Negative: the local pack filename (with the flattened scope dash)
  # must NOT appear inside any registry URL. Allowing it elsewhere in
  # the body (the integrity-block `file:` line) is fine.
  ! grep -qE 'registry\.npmjs\.org/[^[:space:]]*forgesworn-shamir-words' "$GH_LOG"
}

@test "update-release: unscoped package URL uses the local pack filename verbatim" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"nsec-tree","version":"1.5.0","files":["dist"]}'
  write_file "CHANGELOG.md" '## 1.5.0

- changes
'
  write_meta_for "nsec-tree-1.5.0.tgz"
  export GIT_TAG="v1.5.0"

  run "$ACTION_ROOT/steps/update-release.sh"
  [ "$status" -eq 0 ]

  # For unscoped packages the local filename equals the registry-side
  # filename, so the URL stays the same.
  grep -q 'https://registry.npmjs.org/nsec-tree/-/nsec-tree-1.5.0.tgz' "$GH_LOG"
}

@test "update-release: noble-style nested scope URL also strips the scope" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"@noble/hashes","version":"1.4.2","files":["dist"]}'
  write_file "CHANGELOG.md" '## 1.4.2

- changes
'
  write_meta_for "noble-hashes-1.4.2.tgz"
  export GIT_TAG="v1.4.2"

  run "$ACTION_ROOT/steps/update-release.sh"
  [ "$status" -eq 0 ]

  grep -q 'https://registry.npmjs.org/@noble/hashes/-/hashes-1.4.2.tgz' "$GH_LOG"
  ! grep -qE 'registry\.npmjs\.org/[^[:space:]]*noble-hashes' "$GH_LOG"
}

@test "update-release: gh release upload is invoked with the canonical tarball" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"nsec-tree","version":"1.5.0","files":["dist"]}'
  write_file "CHANGELOG.md" '## 1.5.0

- changes
'
  write_meta_for "nsec-tree-1.5.0.tgz"
  export GIT_TAG="v1.5.0"

  run "$ACTION_ROOT/steps/update-release.sh"
  [ "$status" -eq 0 ]

  # The fake gh log should contain a `release upload` call referencing
  # the canonical tarball path under the meta dir, with --clobber for
  # idempotency.
  grep -q "release upload v1.5.0 ${meta_dir}/nsec-tree-1.5.0.tgz --clobber" "$GH_LOG"
}

# ---------------------------------------------------------------------
# Create-or-update branch coverage (see update-release.sh header).
# The legacy tests above all run under the default $GH_RELEASE_MODE
# (= existing), exercising the edit branch. The tests below force the
# missing and error modes.
# ---------------------------------------------------------------------

@test "update-release: creates a Release when none exists (chained flow)" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"nsec-tree","version":"1.5.0","files":["dist"]}'
  write_file "CHANGELOG.md" '## 1.5.0

- changes
'
  write_meta_for "nsec-tree-1.5.0.tgz"
  export GIT_TAG="v1.5.0"
  export GH_RELEASE_MODE="missing"
  export GITHUB_SHA="deadbeefcafef00d1234567890abcdef12345678"

  run "$ACTION_ROOT/steps/update-release.sh"
  [ "$status" -eq 0 ]

  # On the missing branch we must call `release create`, not `release edit`.
  grep -q "GH_CALL: release create v1.5.0" "$GH_LOG"
  ! grep -q "GH_CALL: release edit" "$GH_LOG"

  # --target must be passed and equal $GITHUB_SHA. --notes contains
  # multi-line content so the whole call may span several log lines;
  # check for --target and the SHA individually rather than on one line.
  grep -q -- "--target" "$GH_LOG"
  grep -q "$GITHUB_SHA" "$GH_LOG"

  # Asset upload still runs after create.
  grep -q "release upload v1.5.0" "$GH_LOG"
}

@test "update-release: edits existing Release (legacy flow)" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"nsec-tree","version":"1.5.0","files":["dist"]}'
  write_file "CHANGELOG.md" '## 1.5.0

- changes
'
  write_meta_for "nsec-tree-1.5.0.tgz"
  export GIT_TAG="v1.5.0"
  export GH_RELEASE_MODE="existing"

  run "$ACTION_ROOT/steps/update-release.sh"
  [ "$status" -eq 0 ]

  # On the existing branch we must call `release edit`, not `release create`.
  grep -q "GH_CALL: release edit v1.5.0" "$GH_LOG"
  ! grep -q "GH_CALL: release create" "$GH_LOG"
}

@test "update-release: create omits --target when no SHA resolvable" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"nsec-tree","version":"1.5.0","files":["dist"]}'
  write_file "CHANGELOG.md" '## 1.5.0

- changes
'
  write_meta_for "nsec-tree-1.5.0.tgz"
  export GIT_TAG="v1.5.0"
  export GH_RELEASE_MODE="missing"
  # GITHUB_SHA deliberately unset; fixture has no git repo so git
  # rev-parse HEAD also fails. Script should omit --target rather
  # than pass an empty string.
  unset GITHUB_SHA

  run "$ACTION_ROOT/steps/update-release.sh"
  [ "$status" -eq 0 ]

  grep -q "GH_CALL: release create v1.5.0" "$GH_LOG"
  # --target must NOT appear in any create call when no SHA is available.
  ! grep -qE "release create v1\.5\.0[^\n]*--target" "$GH_LOG"
}
