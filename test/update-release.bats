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
# a file the test can grep against. Always exits 0.
{
  printf 'GH_CALL: '
  printf '%s ' "$@"
  printf '\n'
} >> "$GH_LOG"
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
