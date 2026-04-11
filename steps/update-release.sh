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
require_cmds gh jq

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

# Append the artefact integrity block if record-tarball wrote a meta
# file. The block stamps the tarball filename, size, sha256, and npm
# integrity (sha512) into the release body so consumers can hash-compare
# the registry tarball against what CI built. Missing meta is logged
# and skipped, never fatal — the changelog body still gets posted.
#
# When REPRODUCIBLE=1 (set by the publish job after the reproduce job
# confirmed two independent builds matched), a "Reproducible build"
# header line is added above the integrity block. When unset or 0, the
# block ships as a single-runner integrity anchor only.
meta_dir="${TARBALL_META_DIR:-${RUNNER_TEMP:-/tmp}/forgesworn-release}"
meta_file="$meta_dir/tarball.meta"
tarball_path=""
if [[ -f "$meta_file" ]]; then
  filename=""; size=""; sha256=""; integrity=""
  while IFS='=' read -r key value; do
    case "$key" in
      filename)  filename="$value" ;;
      size)      size="$value" ;;
      sha256)    sha256="$value" ;;
      integrity) integrity="$value" ;;
    esac
  done < "$meta_file"

  if [[ -n "$filename" && -n "$sha256" && -n "$integrity" ]]; then
    pkg="${PACKAGE_JSON:-package.json}"
    name=""
    if [[ -f "$pkg" ]]; then
      name="$(jq -r '.name // empty' "$pkg" 2>/dev/null || true)"
    fi

    # Reconstruct the tarball path from the meta dir + filename so we
    # do not depend on the absolute path written by a different job.
    tarball_path="$meta_dir/$filename"

    # Reproducibility badge — only if the publish job confirmed it.
    badge=""
    if [[ "${REPRODUCIBLE:-0}" == "1" ]]; then
      badge=$'\n\n**Reproducible build**: byte-identical output verified across two independent CI runners.'
    fi

    # Heredoc with EOF unquoted so ${var} interpolates; backticks are
    # escaped so the markdown fences come through literally.
    integrity_block="$(cat <<EOF

---
${badge}

## Artefact integrity

\`\`\`
file:      ${filename}
size:      ${size} bytes
sha256:    ${sha256}
${integrity}
\`\`\`
EOF
)"

    if [[ -n "$name" ]]; then
      verify_recipe="$(cat <<EOF

Verify against the registry tarball:

\`\`\`sh
curl -sLO https://registry.npmjs.org/${name}/-/${filename}
shasum -a 256 ${filename}
\`\`\`
EOF
)"
      integrity_block="${integrity_block}${verify_recipe}"
    fi

    notes="${notes}${integrity_block}"
    log "appended artefact integrity block to release body"
  else
    warn "tarball meta file present but missing required fields — skipping integrity block"
  fi
else
  log "no tarball meta at $meta_file — skipping integrity block"
fi

log "updating release $tag"
if ! gh release edit "$tag" --notes "$notes"; then
  die "gh release edit failed"
fi

# Upload the canonical tarball as a release asset so consumers have a
# second independent source for the bytes (registry + GH Releases) and
# can cross-verify against both. --clobber makes this idempotent on
# re-runs of an already-published release.
if [[ -n "$tarball_path" && -f "$tarball_path" ]]; then
  log "uploading $tarball_path as release asset"
  if ! gh release upload "$tag" "$tarball_path" --clobber; then
    warn "gh release upload failed — release body updated but asset not attached"
  else
    log "asset uploaded"
  fi
fi

ok "release $tag body updated from CHANGELOG"
