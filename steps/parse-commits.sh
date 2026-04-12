#!/usr/bin/env bash
# Parse conventional commits since the last semver tag and determine
# the version bump type.
#
# Env:
#   BASE_TAG      - tag to diff from (default: most recent semver tag)
#   HEAD_REF      - ref to diff to (default: HEAD)
#   CURRENT_VERSION - current version string (default: read from package.json)
#   PACKAGE_JSON  - path to package.json (default: package.json)
#
# Outputs (written to stdout as key=value, and to $GITHUB_OUTPUT if set):
#   bump          - "major", "minor", "patch", or "none"
#   next_version  - calculated next version (unchanged if bump=none)
#   changelog     - markdown changelog snippet
#
# Exit: always 0. Consumers decide what to do with bump=none.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "parse-commits"
require_cmds git jq

# ---------------------------------------------------------------------------
# Resolve base tag
# ---------------------------------------------------------------------------

if [[ -n "${BASE_TAG:-}" ]]; then
  last_tag="$BASE_TAG"
else
  # Only tags reachable from HEAD -- avoids picking up tags on other branches
  last_tag="$(git tag --merged HEAD --sort=-v:refname | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
fi

if [[ -z "$last_tag" ]]; then
  # No prior tag -- diff from root
  log "no prior semver tag found; analysing all commits"
  range="HEAD"
else
  log "analysing commits since $last_tag"
  range="${last_tag}..${HEAD_REF:-HEAD}"
fi

# ---------------------------------------------------------------------------
# Resolve current version
# ---------------------------------------------------------------------------

pkg="${PACKAGE_JSON:-package.json}"
if [[ -n "${CURRENT_VERSION:-}" ]]; then
  current="$CURRENT_VERSION"
elif [[ -f "$pkg" ]]; then
  current="$(jq -r '.version // empty' "$pkg")"
  [[ -n "$current" ]] || die "$pkg has no .version field"
else
  die "no CURRENT_VERSION set and $pkg not found"
fi

# ---------------------------------------------------------------------------
# Parse commit subjects
# ---------------------------------------------------------------------------

has_breaking=false
has_feat=false
has_fix=false

changelog_breaking=""
changelog_feat=""
changelog_fix=""

# Conventional Commits regex:
#   type(scope)!: description   -- with optional scope and optional !
#   type!: description          -- without scope, with !
#   type: description           -- plain
cc_re='^([a-z]+)(\(([^)]+)\))?(!)?: (.+)$'

while IFS= read -r subject; do
  [[ -z "$subject" ]] && continue

  if [[ "$subject" =~ $cc_re ]]; then
    type="${BASH_REMATCH[1]}"
    scope="${BASH_REMATCH[3]:-}"
    bang="${BASH_REMATCH[4]:-}"
    desc="${BASH_REMATCH[5]}"

    scope_suffix=""
    [[ -n "$scope" ]] && scope_suffix=" ($scope)"

    if [[ "$bang" == "!" ]]; then
      has_breaking=true
      changelog_breaking+="- ${desc}${scope_suffix}"$'\n'
    elif [[ "$type" == "feat" ]]; then
      has_feat=true
      changelog_feat+="- ${desc}${scope_suffix}"$'\n'
    elif [[ "$type" == "fix" ]]; then
      has_fix=true
      changelog_fix+="- ${desc}${scope_suffix}"$'\n'
    fi
    # Other types (docs, chore, ci, test, refactor, style, perf, build)
    # are intentionally ignored for version bump purposes.
  fi
done < <(git log --format="%s" "$range")

# ---------------------------------------------------------------------------
# Check commit bodies for BREAKING CHANGE footer
# ---------------------------------------------------------------------------

while IFS= read -r -d '' body; do
  if [[ "$body" == *"BREAKING CHANGE:"* ]] || [[ "$body" == *"BREAKING-CHANGE:"* ]]; then
    has_breaking=true
    # Extract the breaking change description from the footer
    while IFS= read -r line; do
      if [[ "$line" =~ ^BREAKING[\ -]CHANGE:\ (.+)$ ]]; then
        changelog_breaking+="- ${BASH_REMATCH[1]}"$'\n'
      fi
    done <<< "$body"
  fi
done < <(git log --format="%b%x00" "$range")

# ---------------------------------------------------------------------------
# Determine bump
# ---------------------------------------------------------------------------

if $has_breaking; then
  bump="major"
elif $has_feat; then
  bump="minor"
elif $has_fix; then
  bump="patch"
else
  bump="none"
fi

# ---------------------------------------------------------------------------
# Calculate next version
# ---------------------------------------------------------------------------

IFS='.' read -r v_major v_minor v_patch <<< "$current"

case "$bump" in
  major) next_version="$((v_major + 1)).0.0" ;;
  minor) next_version="${v_major}.$((v_minor + 1)).0" ;;
  patch) next_version="${v_major}.${v_minor}.$((v_patch + 1))" ;;
  none)  next_version="$current" ;;
esac

# ---------------------------------------------------------------------------
# Build changelog snippet
# ---------------------------------------------------------------------------

changelog=""
if [[ -n "$changelog_breaking" ]]; then
  changelog+="### Breaking Changes"$'\n\n'"${changelog_breaking}"$'\n'
fi
if [[ -n "$changelog_feat" ]]; then
  changelog+="### Features"$'\n\n'"${changelog_feat}"$'\n'
fi
if [[ -n "$changelog_fix" ]]; then
  changelog+="### Bug Fixes"$'\n\n'"${changelog_fix}"$'\n'
fi

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

log "bump: $bump"
log "current: $current"
log "next: $next_version"

if [[ -n "$changelog" ]]; then
  log "changelog:"
  while IFS= read -r line; do
    [[ -n "$line" ]] && log "  $line"
  done <<< "$changelog"
fi

# Write to GITHUB_OUTPUT if available (for workflow consumption)
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "bump=$bump"
    echo "next_version=$next_version"
    # Multiline output uses a randomised heredoc delimiter to prevent
    # injection via crafted commit messages containing the delimiter string.
    _delim="CHANGELOG_EOF_$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    echo "changelog<<${_delim}"
    echo "$changelog"
    echo "${_delim}"
  } >> "$GITHUB_OUTPUT"
fi

# Also write to a file for local/test consumption
if [[ -n "${PARSE_COMMITS_OUT:-}" ]]; then
  {
    echo "bump=$bump"
    echo "next_version=$next_version"
  } > "$PARSE_COMMITS_OUT"
  # Changelog in a separate file to avoid quoting issues
  echo -n "$changelog" > "${PARSE_COMMITS_OUT}.changelog"
fi

ok "$bump bump: $current -> $next_version"
