#!/usr/bin/env bash
# publish-npm.sh — idempotent npm publish via OIDC trusted publishing.
#
# Flow:
#   1. Read tarball path + integrity from $TARBALL_META_DIR/tarball.meta
#      (written by record-tarball.sh).
#   2. Read name + version from package.json for the idempotency check.
#   3. If the registry already has this exact version, compare its
#      dist.integrity to our locally recorded integrity:
#        - match  -> exit 0 (true idempotency, clean re-run)
#        - differ -> die (registry tarball substitution alarm)
#   4. Dry-run publish using the recorded tarball, then real publish.
#
# Why publish a path rather than re-pack:
#   record-tarball.sh produced the bytes we hashed. Re-packing here
#   would risk a second pack with drifted tar headers, breaking the
#   integrity story (the registry tarball would not match the SHA we
#   stamped into the GitHub Release). We upload exactly what we hashed.
#
# OIDC requirements:
#   - Caller workflow must have `permissions: id-token: write`.
#   - actions/setup-node must have been run with a registry-url, so npm
#     knows where to request the OIDC token.
#   - The npm package must have a trusted publisher configured at
#     registry.npmjs.org for the caller's repo. The first publish still
#     needs a manual bootstrap — see README.
#
# Env:
#   PACKAGE_JSON       (default: package.json)
#   TARBALL_META_DIR   (default: $RUNNER_TEMP/forgesworn-release, then /tmp)
#   DRY_RUN=1          skip the real publish (for smoke-testing)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "publish-npm"
require_cmds jq npm

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

name="$(jq -r '.name // empty' "$pkg")"
version="$(jq -r '.version // empty' "$pkg")"
[[ -n "$name" ]]    || die "$pkg has no .name"
[[ -n "$version" ]] || die "$pkg has no .version"

log "package: $name@$version"

meta_dir="${TARBALL_META_DIR:-${RUNNER_TEMP:-/tmp}/forgesworn-release}"
meta_file="$meta_dir/tarball.meta"
[[ -f "$meta_file" ]] || die "tarball meta not found at $meta_file (record-tarball must run before publish-npm)"

filename=""
recorded_integrity=""
while IFS='=' read -r key value; do
  case "$key" in
    filename)  filename="$value" ;;
    integrity) recorded_integrity="$value" ;;
  esac
done < "$meta_file"

[[ -n "$filename"            ]] || die "meta file missing filename"
[[ -n "$recorded_integrity"  ]] || die "meta file missing integrity"
[[ "$filename" != *..* && "$filename" != /* ]] || die "suspicious filename in meta file: $filename"

# Reconstruct the tarball path from $TARBALL_META_DIR + filename rather
# than trusting the `path=` field. The meta file may have been written
# in a different job (with a different RUNNER_TEMP) and downloaded as
# an artifact into our own meta dir, so the recorded absolute path is
# unreliable. The filename is stable.
tarball_path="$meta_dir/$filename"
[[ -f "$tarball_path" ]] || die "tarball not found at $tarball_path"

# Idempotency: if the registry already has this version, compare
# integrity. A match means a clean re-run of an already-successful
# release; a mismatch means the bytes on the registry are not the bytes
# CI built. That is exactly the registry tarball substitution scenario,
# and we surface it loudly rather than silently re-using the registry
# copy.
if registry_integrity="$(npm view "${name}@${version}" dist.integrity 2>/dev/null)" \
   && [[ -n "$registry_integrity" ]]; then
  if [[ "$registry_integrity" == "$recorded_integrity" ]]; then
    ok "${name}@${version} already on registry with matching integrity — nothing to publish"
    exit 0
  fi
  warn "registry integrity: $registry_integrity"
  warn "local integrity:    $recorded_integrity"
  die "${name}@${version} on registry does not match locally built tarball — possible registry substitution or non-deterministic build; investigate before re-running"
fi

# Note: --provenance is NOT passed on the CLI. Instead we rely on
# package.json's "publishConfig.provenance": true to drive provenance
# signing. npm 11.6+ short-circuits to ENEEDAUTH when --provenance is
# passed explicitly, never initiating the OIDC trusted-publishing
# token exchange. paulmillr/jsbt uses the same implicit pattern.
log "running dry-run first"
if ! npm publish --dry-run --access public "$tarball_path"; then
  die "npm publish --dry-run failed"
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  warn "DRY_RUN=1 set — skipping real publish"
  exit 0
fi

log "publishing $tarball_path"
if ! npm publish --access public "$tarball_path"; then
  die "npm publish failed"
fi

ok "${name}@${version} published"
