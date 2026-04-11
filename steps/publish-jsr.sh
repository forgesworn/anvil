#!/usr/bin/env bash
# publish-jsr.sh — JSR publish, opt-in via jsr.json presence.
#
# JSR does NOT currently support OIDC trusted publishing (as of 2026-04),
# so this step needs a JSR_TOKEN. For that reason it is gated on the
# presence of jsr.json: consumers that do not want JSR simply do not
# create the file and this script exits 0 quietly.
#
# If jsr.json is present we:
#   1. Require JSR_TOKEN in the env (fail loudly if absent).
#   2. Verify jsr.json version == package.json version (fail on mismatch).
#   3. Run `jsr publish`, honouring .allowSlowTypes if set.
#
# Env:
#   JSR_TOKEN     JSR access token (required when jsr.json exists)
#   DRY_RUN=1     skip the real publish

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "publish-jsr"

if [[ ! -f "jsr.json" ]]; then
  log "no jsr.json — skipping JSR publish"
  exit 0
fi

require_cmds jq npx node

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

pkg_version="$(jq -r '.version // empty' "$pkg")"
jsr_version="$(jq -r '.version // empty' jsr.json)"
[[ -n "$pkg_version" ]] || die "$pkg has no .version"
[[ -n "$jsr_version" ]] || die "jsr.json has no .version"

if [[ "$pkg_version" != "$jsr_version" ]]; then
  die "package.json version ($pkg_version) != jsr.json version ($jsr_version)"
fi

if [[ -z "${JSR_TOKEN:-}" ]]; then
  die "JSR_TOKEN not set — cannot publish to JSR (set it as a repo secret)"
fi

slow_types=""
if [[ "$(jq -r '.allowSlowTypes // false' jsr.json)" == "true" ]]; then
  slow_types="--allow-slow-types"
  log "allowSlowTypes=true"
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  warn "DRY_RUN=1 set — skipping JSR publish"
  exit 0
fi

log "publishing to JSR"
# npx jsr avoids a global install and keeps our footprint small.
if ! npx --yes jsr publish --token "$JSR_TOKEN" $slow_types; then
  die "jsr publish failed"
fi

ok "published to JSR"
