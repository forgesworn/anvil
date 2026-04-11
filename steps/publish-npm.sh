#!/usr/bin/env bash
# publish-npm.sh — idempotent npm publish via OIDC trusted publishing.
#
# Flow:
#   1. Read name + version from package.json.
#   2. Check npm registry: is this exact version already published?
#      If yes, exit 0. Publishing a release twice must be safe.
#   3. Dry-run first (surfaces issues like missing files).
#   4. Real publish with --provenance --access public.
#
# OIDC requirements:
#   - Caller workflow must have `permissions: id-token: write`.
#   - `actions/setup-node` must have been run with a registry-url, or
#     --registry passed via NPM_CONFIG_REGISTRY, so npm knows where to
#     request the OIDC token.
#   - The npm package must have a trusted publisher configured on
#     registry.npmjs.org for this repo. The first publish still needs a
#     manual bootstrap — see README.
#
# Env:
#   DRY_RUN=1    skip the real publish (for smoke-testing locally)

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

# Idempotency: if the registry already has this exact version, nothing to do.
# `npm view` returns non-zero for unknown versions, which we treat as "not
# yet published".
if published="$(npm view "${name}@${version}" version 2>/dev/null)" && [[ -n "$published" ]]; then
  ok "${name}@${version} already on registry — nothing to publish"
  exit 0
fi

# Note: --provenance is NOT passed on the CLI. Instead we rely on
# package.json's "publishConfig.provenance": true to drive provenance
# signing. npm 11.6+ short-circuits to "ENEEDAUTH" when --provenance is
# passed explicitly, never initiating OIDC trusted publishing exchange.
# paulmillr/jsbt uses the same implicit pattern; it works.
log "running dry-run first"
if ! npm publish --dry-run --access public; then
  die "npm publish --dry-run failed"
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  warn "DRY_RUN=1 set — skipping real publish"
  exit 0
fi

log "publishing"
if ! npm publish --access public; then
  die "npm publish failed"
fi

ok "${name}@${version} published"
