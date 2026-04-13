#!/usr/bin/env bash
# changelog-extract.sh — print the CHANGELOG.md section for a version.
#
# Loose heuristic, not strict Keep-A-Changelog. Accepts any Markdown
# heading at level 1-3 whose text contains the version string. Extraction
# starts on the line after the matching heading and stops at the next
# heading of the same-or-higher level.
#
# Why loose? Real-world CHANGELOGs use mixed heading levels (a common
# quirk of semantic-release's generator) and we want migrations to Just
# Work without re-formatting historical entries.
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
#
# Version match is word-bounded: `1.2.3` in a heading like `## Pre-1.2.3`
# or `## 1.2.30` must NOT match the release for `1.2.3`. We require the
# version to be preceded by start-of-line or a non-version character
# (whitespace, `v`, punctuation) and followed by end-of-line or a
# non-version character. An optional leading `v` is allowed on either
# side so `## v1.2.3` matches when `version=1.2.3`.
set +e
awk -v ver="$version" '
  function is_version_heading(line) {
    # Heading line starts with 1-3 # followed by whitespace.
    if (line !~ /^#{1,3}[[:space:]]/) return 0
    # Contains a dotted numeric version marker.
    if (line ~ /v?[0-9]+\.[0-9]+\.[0-9]+/) return 1
    return 0
  }
  function version_matches(line, ver,   bare, re) {
    # Strip an optional leading `v` from the needle so `## 1.2.3`
    # matches when caller passes `v1.2.3` and vice versa.
    bare = ver
    sub(/^v/, "", bare)
    # Escape regex metacharacters in the version (dots especially).
    gsub(/[.+*?(){}|\\^$\[\]]/, "\\\\&", bare)
    # Word-bounded: preceded by start-of-line, whitespace, or
    # punctuation (brackets, parens, colon). Followed by end-of-line,
    # whitespace, or punctuation. A leading `v` on the heading is
    # consumed so "## v1.2.3" still matches.
    re = "(^|[^0-9A-Za-z._-])v?" bare "([^0-9A-Za-z._-]|$)"
    return (line ~ re)
  }
  BEGIN { capturing = 0 }
  {
    if (!capturing) {
      if (is_version_heading($0) && version_matches($0, ver)) {
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
