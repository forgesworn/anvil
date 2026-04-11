#!/usr/bin/env bash
# changelog-extract.sh — print the CHANGELOG.md section for a version.
#
# Loose heuristic, not strict Keep-A-Changelog. Accepts any Markdown
# heading at level 1-3 whose text contains the version string. Extraction
# starts on the line after the matching heading and stops at the next
# heading of the same-or-higher level.
#
# Why loose? Because nsec-tree's existing CHANGELOG has a mix of H1 and H2
# headings (a quirk of semantic-release's generator) and we want the
# pilot migration to Just Work without re-formatting historical entries.
#
# Stdout-only. Exits non-zero with a clear error if no section matches.
#
# Env:
#   CHANGELOG_FILE   path to CHANGELOG.md (default: CHANGELOG.md)
#   VERSION          version to extract (default: from package.json)
#   PACKAGE_JSON     path to package.json (default: package.json)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

# Don't print a header — this script's stdout is captured.
_STEP_NAME="changelog-extract"

cl="${CHANGELOG_FILE:-CHANGELOG.md}"
[[ -f "$cl" ]] || die "$cl not found"

version="${VERSION:-}"
if [[ -z "$version" ]]; then
  require_cmds jq
  pkg="${PACKAGE_JSON:-package.json}"
  [[ -f "$pkg" ]] || die "$pkg not found and no VERSION provided"
  version="$(jq -r '.version // empty' "$pkg")"
fi
[[ -n "$version" ]] || die "no version to extract"

# Find the start heading (any H1-H3 containing the version string) and
# capture until the next heading that looks like it starts a new version
# section.
#
# A heading "looks like a new version section" if it is H1-H3 AND its
# text contains a dotted numeric version (e.g. "1.2.3", "v2.0.0-rc.1").
# Non-version headings like "### Features" or "### Bug Fixes" are passed
# through as content. This is needed because semantic-release mixes H1
# and H2 for version headings depending on bump type, so level-based
# stopping is unreliable.
set +e
awk -v ver="$version" '
  function is_version_heading(line) {
    # Heading line starts with 1-3 # followed by whitespace.
    if (line !~ /^#{1,3}[[:space:]]/) return 0
    # Contains a dotted numeric version marker.
    if (line ~ /v?[0-9]+\.[0-9]+\.[0-9]+/) return 1
    return 0
  }
  BEGIN { capturing = 0 }
  {
    if (!capturing) {
      if (is_version_heading($0) && index($0, ver) > 0) {
        capturing = 1
        next
      }
    } else {
      if (is_version_heading($0)) {
        exit 0
      }
      print
    }
  }
  END {
    if (!capturing) exit 2
  }
' "$cl"
status=$?
set -e

if (( status == 2 )); then
  die "no CHANGELOG section found for version $version in $cl"
elif (( status != 0 )); then
  die "awk failed extracting $version from $cl (status $status)"
fi
