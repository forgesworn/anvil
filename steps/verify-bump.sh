#!/usr/bin/env bash
# Verify that the manual version bump is consistent with conventional
# commits since the last tag.
#
# Fails if the actual bump is SMALLER than what commits imply:
#   - Commits include feat but you only bumped patch -> fail
#   - Commits include BREAKING CHANGE but you bumped minor -> fail
#
# Warns (does not fail) if the actual bump is LARGER than implied:
#   - Only fix commits but you bumped minor -> warn (might be intentional)
#
# This is the "verify" mode safety net: you keep manual control, but
# the action catches under-bumps that would ship breaking changes in
# a patch release.
#
# Env:
#   PACKAGE_JSON  - path to package.json (default: package.json)
#   GIT_TAG       - current release tag (default: GITHUB_REF_NAME)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-bump"
require_cmds git jq

# ---------------------------------------------------------------------------
# Resolve current tag and previous tag
# ---------------------------------------------------------------------------

tag="${GIT_TAG:-${GITHUB_REF_NAME:-}}"
[[ -n "$tag" ]] || die "no tag provided (set GIT_TAG or push a tag)"

current_version="$(strip_v "$tag")"

# Only tags reachable from HEAD, excluding the current release tag
prev_tag="$(git tag --merged HEAD --sort=-v:refname \
  | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
  | grep -v "^v\?${current_version}$" \
  | head -1 || true)"

if [[ -z "$prev_tag" ]]; then
  log "no previous semver tag found; skipping bump verification"
  ok "first release -- nothing to verify against"
  exit 0
fi

# ---------------------------------------------------------------------------
# Determine what bump actually happened
# ---------------------------------------------------------------------------

prev_version="$(strip_v "$prev_tag")"

IFS='.' read -r cur_major cur_minor cur_patch <<< "$current_version"
IFS='.' read -r prev_major prev_minor prev_patch <<< "$prev_version"

if (( cur_major > prev_major )); then
  actual_bump="major"
elif (( cur_major == prev_major && cur_minor > prev_minor )); then
  actual_bump="minor"
elif (( cur_major == prev_major && cur_minor == prev_minor && cur_patch > prev_patch )); then
  actual_bump="patch"
else
  die "version $current_version is not greater than $prev_version"
fi

# ---------------------------------------------------------------------------
# Run parse-commits to determine what commits imply
# ---------------------------------------------------------------------------

parse_out="$(mktemp)"

# Run as a subprocess to avoid polluting our shell state.
# Suppress stdout/stderr -- we only need the output file.
BASE_TAG="$prev_tag" \
HEAD_REF="HEAD" \
CURRENT_VERSION="$prev_version" \
PARSE_COMMITS_OUT="$parse_out" \
  "${SCRIPT_DIR}/parse-commits.sh" > /dev/null 2>&1 || true

implied_bump="$(grep '^bump=' "$parse_out" 2>/dev/null | cut -d= -f2 || true)"
rm -f "$parse_out" "${parse_out}.changelog"

if [[ -z "$implied_bump" ]] || [[ "$implied_bump" == "none" ]]; then
  log "no conventional commits found; cannot verify bump"
  ok "no releasable conventional commits to verify against"
  exit 0
fi

# ---------------------------------------------------------------------------
# Compare: bump severity ordering
# ---------------------------------------------------------------------------

bump_rank() {
  case "$1" in
    major) echo 3 ;;
    minor) echo 2 ;;
    patch) echo 1 ;;
    *)     echo 0 ;;
  esac
}

actual_rank="$(bump_rank "$actual_bump")"
implied_rank="$(bump_rank "$implied_bump")"

log "actual bump: $actual_bump ($prev_version -> $current_version)"
log "commits imply: $implied_bump"

if (( actual_rank < implied_rank )); then
  die "under-bump: commits imply $implied_bump but you bumped $actual_bump ($prev_version -> $current_version)"
fi

if (( actual_rank > implied_rank )); then
  warn "over-bump: commits imply $implied_bump but you bumped $actual_bump -- this may be intentional"
fi

ok "bump is consistent: $actual_bump >= $implied_bump"
