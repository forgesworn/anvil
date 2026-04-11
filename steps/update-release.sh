#!/usr/bin/env bash
# update-release.sh — update the GitHub Release body from CHANGELOG.md.
#
# We do NOT create the release — the maintainer does that manually as the
# trigger. This step runs after publish succeeds and replaces the release
# body with the section from CHANGELOG.md, so the release notes on GitHub
# match exactly what was published.
#
# Env:
#   GIT_TAG          release tag to edit (default: $GITHUB_REF_NAME)
#   CHANGELOG_FILE   path to CHANGELOG.md (default: CHANGELOG.md)
#   GITHUB_TOKEN     auth for gh (GitHub provides this automatically)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "update-release"
require_cmds gh

tag="${GIT_TAG:-${GITHUB_REF_NAME:-}}"
[[ -n "$tag" ]] || die "no tag provided (set GIT_TAG or GITHUB_REF_NAME)"

# changelog-extract.sh picks version from package.json by default, which
# is correct after verify-tag has already asserted tag == package.json
# version.
notes=""
if notes="$("${SCRIPT_DIR}/changelog-extract.sh")"; then
  log "extracted changelog section ($(wc -l <<<"$notes") lines)"
else
  warn "could not extract CHANGELOG section — leaving release body unchanged"
  exit 0
fi

# Strip leading/trailing blank lines so the release body looks clean.
notes="$(printf '%s\n' "$notes" | awk '
  NF { body = 1 }
  body { buf = buf $0 "\n" }
  END { sub(/\n+$/, "", buf); print buf }
')"

if [[ -z "$notes" ]]; then
  warn "changelog section was empty — leaving release body unchanged"
  exit 0
fi

log "updating release $tag"
if ! gh release edit "$tag" --notes "$notes"; then
  die "gh release edit failed"
fi

ok "release $tag body updated from CHANGELOG"
