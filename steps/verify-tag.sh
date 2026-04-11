#!/usr/bin/env bash
# verify-tag.sh — refuse to publish unless the triggering git tag matches
# the package.json version.
#
# This is the single most important gate: it prevents a maintainer from
# accidentally publishing a development version, or tagging the wrong commit.
#
# Inputs (environment):
#   PACKAGE_JSON   path to package.json (default: package.json)
#   GIT_TAG        tag to compare (default: github.event.release.tag_name,
#                  falling back to $GITHUB_REF_NAME)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-tag"
require_cmds jq node

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

pkg_version="$(jq -r '.version // empty' "$pkg")"
[[ -n "$pkg_version" ]] || die "$pkg has no .version field"

tag="${GIT_TAG:-${GITHUB_REF_NAME:-}}"
[[ -n "$tag" ]] || die "no tag provided (set GIT_TAG or GITHUB_REF_NAME)"

tag_stripped="$(strip_v "$tag")"

log "package version: $pkg_version"
log "git tag:         $tag (stripped: $tag_stripped)"

if [[ "$pkg_version" != "$tag_stripped" ]]; then
  die "tag/package.json mismatch — refusing to publish"
fi

ok "tag matches package.json version"
