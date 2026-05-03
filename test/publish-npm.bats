#!/usr/bin/env bats

# Tests for steps/publish-npm.sh — uses a fake `npm` on PATH so we can
# exercise the registry-integrity comparator, idempotency path, and
# substitution alarm without needing a real npm registry or OIDC token.
#
# The fake npm logs every invocation to $NPM_LOG and dispatches on the
# first arg:
#
#   npm view <name>@<version> dist.integrity
#     - prints $NPM_VIEW_INTEGRITY and exits 0 if set
#     - exits 1 (not found) otherwise
#
#   npm publish [--dry-run] [--access public] <tarball-path>
#     - exits 0
#
# All other npm subcommands also exit 0 — the script only invokes view
# and publish.

load helpers

setup() {
  setup_fixture
  unset NPM_TOKEN NODE_AUTH_TOKEN NPM_CONFIG_PROVENANCE NPM_CONFIG_USERCONFIG

  meta_dir="$FIXTURE_DIR/meta"
  mkdir -p "$meta_dir"
  export TARBALL_META_DIR="$meta_dir"

  bin_dir="$FIXTURE_DIR/bin"
  mkdir -p "$bin_dir"
  cat > "$bin_dir/npm" <<'NPM'
#!/usr/bin/env bash
# Fake npm: log every invocation, dispatch on the first arg.
{
  printf 'NPM_CALL:'
  for arg in "$@"; do printf ' %s' "$arg"; done
  printf '\n'
} >> "$NPM_LOG"

case "${1:-}" in
  view)
    if [[ -n "${NPM_VIEW_INTEGRITY:-}" ]]; then
      printf '%s\n' "$NPM_VIEW_INTEGRITY"
      exit 0
    fi
    if [[ -n "${NPM_VIEW_ERROR:-}" ]]; then
      printf '%s\n' "$NPM_VIEW_ERROR" >&2
      exit 1
    fi
    # Default: mimic real npm view on a missing version with E404.
    printf 'npm ERR! code E404\n' >&2
    printf 'npm ERR! 404 Not Found - GET https://registry.npmjs.org/x\n' >&2
    exit 1
    ;;
  publish)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
NPM
  chmod +x "$bin_dir/npm"

  export NPM_LOG="$FIXTURE_DIR/npm.log"
  : > "$NPM_LOG"
  export PATH="$bin_dir:$PATH"
}

teardown() {
  teardown_fixture
  unset TARBALL_META_DIR
  unset NPM_LOG
  unset NPM_VIEW_INTEGRITY
  unset NPM_VIEW_ERROR
  unset NPM_TOKEN
  unset NODE_AUTH_TOKEN
  unset NPM_CONFIG_PROVENANCE
  unset NPM_CONFIG_USERCONFIG
}

# Build a complete fixture: package.json + tarball.meta + tarball file.
setup_release_fixture() {
  local name="${1:-test-pkg}"
  local version="${2:-1.0.0}"
  local integrity="${3:-sha512-LOCAL}"

  local filename
  # Match how npm pack flattens scoped names into the local filename:
  # `@scope/name` -> `scope-name-1.0.0.tgz`. Tests for unscoped just
  # produce `name-1.0.0.tgz`.
  filename="${name#@}"
  filename="${filename//\//-}-${version}.tgz"

  write_package_json "{\"name\":\"$name\",\"version\":\"$version\",\"publishConfig\":{\"provenance\":true}}"

  cat > "$meta_dir/tarball.meta" <<EOF
filename=$filename
path=$meta_dir/$filename
size=1234
unpacked_size=5678
sha256=abc123
integrity=$integrity
EOF
  : > "$meta_dir/$filename"
}

@test "publish-npm: requires publishConfig.provenance true" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  write_package_json '{"name":"test-pkg","version":"1.0.0"}'

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"publishConfig.provenance"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: refuses long-lived npm token env vars" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  export NPM_TOKEN="npm_secret"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NPM_TOKEN is set"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: refuses npmrc auth material" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  printf '//registry.npmjs.org/:_authToken=secret\n' > "$FIXTURE_DIR/.npmrc"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"npm auth material"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: refuses real NODE_AUTH_TOKEN" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  export NODE_AUTH_TOKEN="npm_realToken123"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NODE_AUTH_TOKEN is set"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: allows setup-node placeholder NODE_AUTH_TOKEN" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  export NODE_AUTH_TOKEN="XXXXX-XXXXX-XXXXX-XXXXX"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 0 ]
  grep -q "^NPM_CALL: publish --access public $meta_dir/test-pkg-1.0.0.tgz$" "$NPM_LOG"
}

@test "publish-npm: allows setup-node template _authToken in npmrc" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  printf '//registry.npmjs.org/:_authToken=${NODE_AUTH_TOKEN}\nregistry=https://registry.npmjs.org/\n' > "$FIXTURE_DIR/.npmrc"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 0 ]
  grep -q "^NPM_CALL: publish --access public $meta_dir/test-pkg-1.0.0.tgz$" "$NPM_LOG"
}

@test "publish-npm: happy path runs dry-run then real publish on the recorded tarball" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  # NPM_VIEW_INTEGRITY unset → registry has no copy → publish proceeds.

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 0 ]

  # The view check fired against name@version.
  grep -q '^NPM_CALL: view test-pkg@1.0.0 dist.integrity$' "$NPM_LOG"

  # Both publish calls fired with the recorded tarball path.
  grep -q "^NPM_CALL: publish --dry-run --access public $meta_dir/test-pkg-1.0.0.tgz$" "$NPM_LOG"
  grep -q "^NPM_CALL: publish --access public $meta_dir/test-pkg-1.0.0.tgz$" "$NPM_LOG"
}

@test "publish-npm: idempotent skip when registry integrity matches" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-MATCH"
  export NPM_VIEW_INTEGRITY="sha512-MATCH"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already on registry with matching integrity"* ]]

  # The view fired but no publish call should have.
  grep -q 'view test-pkg@1.0.0 dist.integrity' "$NPM_LOG"
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: registry substitution alarm fires when integrity differs" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  export NPM_VIEW_INTEGRITY="sha512-DIFFERENT"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match locally built tarball"* ]]
  [[ "$output" == *"sha512-LOCAL"* ]]
  [[ "$output" == *"sha512-DIFFERENT"* ]]

  # The view fired but no publish call should have.
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: DRY_RUN=1 runs the dry-run pass but skips the real publish" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  export DRY_RUN=1

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN=1"* ]]

  # Dry-run publish fired; real publish (without --dry-run) did not.
  grep -q 'publish --dry-run --access public' "$NPM_LOG"
  ! grep -qE 'NPM_CALL: publish --access public [^-]' "$NPM_LOG"
}

@test "publish-npm: fails when the meta file is missing" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"test-pkg","version":"1.0.0","publishConfig":{"provenance":true}}'
  # No tarball.meta written.

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tarball meta not found"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: fails when the recorded tarball file is missing on disk" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  rm "$meta_dir/test-pkg-1.0.0.tgz"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tarball not found"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: fails when meta lacks the integrity field" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"test-pkg","version":"1.0.0","publishConfig":{"provenance":true}}'
  cat > "$meta_dir/tarball.meta" <<'EOF'
filename=test-pkg-1.0.0.tgz
path=/tmp/test-pkg-1.0.0.tgz
size=1234
sha256=abc
EOF
  : > "$meta_dir/test-pkg-1.0.0.tgz"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing integrity"* ]]
}

@test "publish-npm: rejects path traversal in meta filename" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  write_package_json '{"name":"test-pkg","version":"1.0.0","publishConfig":{"provenance":true}}'
  cat > "$meta_dir/tarball.meta" <<'EOF'
filename=../../etc/passwd
path=/tmp/test-pkg-1.0.0.tgz
size=1234
sha256=abc
integrity=sha512-LOCAL
EOF
  : > "$meta_dir/../../etc/passwd" 2>/dev/null || true

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"suspicious filename"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: refuses to publish when npm view fails with a non-404 error" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  # Simulate a transient registry failure that is NOT E404. If we
  # treated this as "not on registry; publish", a concurrent substitution
  # attack during a flaky view would escape the integrity alarm.
  export NPM_VIEW_ERROR="npm ERR! network request failed: ETIMEDOUT"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot confirm registry state"* ]]
  ! grep -q 'NPM_CALL: publish' "$NPM_LOG"
}

@test "publish-npm: proceeds when npm view returns E404 (version absent)" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "test-pkg" "1.0.0" "sha512-LOCAL"
  # Default fake-npm behaviour (no NPM_VIEW_INTEGRITY, no NPM_VIEW_ERROR)
  # already emits E404 to stderr; the test makes the expectation explicit.

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not on registry (E404)"* ]]
  grep -q "publish --access public $meta_dir/test-pkg-1.0.0.tgz" "$NPM_LOG"
}

@test "publish-npm: scoped package publishes the unscoped-prefixed local pack" {
  command -v jq >/dev/null 2>&1 || skip "jq not available"

  setup_release_fixture "@forgesworn/shamir-words" "1.1.0" "sha512-LOCAL"

  run "$ACTION_ROOT/steps/publish-npm.sh"
  [ "$status" -eq 0 ]

  # The local pack filename for a scoped package flattens the scope.
  grep -q "publish --access public $meta_dir/forgesworn-shamir-words-1.1.0.tgz" "$NPM_LOG"
  # And the view check uses the scoped name verbatim.
  grep -q '^NPM_CALL: view @forgesworn/shamir-words@1.1.0 dist.integrity$' "$NPM_LOG"
}
