#!/usr/bin/env bash
# update-release.sh — create or update the GitHub Release body from CHANGELOG.md.
#
# Runs after publish succeeds and stamps the Release body with the
# CHANGELOG section for the published version plus the tarball integrity
# block. Two call paths:
#
#   Manual path (caller triggered on release: published): the maintainer
#     already created the Release; we edit the body.
#   Chained path (auto-release.yml -> release.yml via workflow_call):
#     auto-release pushed a tag but no Release object exists yet; we
#     create the Release and stamp it.
#
# The create-or-update decision is probed via `gh release view` — if it
# succeeds, edit; otherwise create.
#
# Env:
#   GIT_TAG          release tag to edit (default: $GITHUB_REF_NAME)
#   CHANGELOG_FILE   path to CHANGELOG.md (default: CHANGELOG.md)
#   GITHUB_TOKEN     auth for gh (GitHub provides this automatically)
#   GITHUB_SHA       commit SHA to target a new Release at (default:
#                    `git rev-parse HEAD`; only used on the create path)

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
meta_dir="${TARBALL_META_DIR:-${RUNNER_TEMP:-/tmp}/forgesworn-anvil}"
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

  if [[ -n "$filename" && ("$filename" == *..* || "$filename" == /*) ]]; then
    warn "suspicious filename in meta file: $filename — skipping integrity block"
  elif [[ -n "$filename" && -n "$sha256" && -n "$integrity" ]]; then
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

    # Validate the package name against npm's grammar before embedding it
    # in a copy-paste shell recipe. A malicious package.json name
    # containing shell metacharacters (backticks, $( ), ; etc.) would
    # render verbatim in the release body and could trick an unwary
    # human running the verify recipe. Only names matching the npm
    # grammar get a verify recipe; anything weirder is silently skipped.
    npm_name_re='^(@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*$'
    if [[ -n "$name" && "$name" =~ $npm_name_re ]]; then
      # Compute the registry-side tarball filename. For unscoped packages
      # the local `npm pack` filename matches the registry filename. For
      # scoped packages npm flattens the scope with a dash in the local
      # filename (e.g. @scope/pkg -> scope-pkg-1.0.0.tgz) but the registry
      # serves the tarball at the unscoped basename within the
      # scope-namespaced path:
      #
      #   local pack:   scope-pkg-1.0.0.tgz
      #   registry url: https://registry.npmjs.org/@scope/pkg/-/pkg-1.0.0.tgz
      #
      # Using the local filename in the URL would 404 on scoped packages.
      # Strip any scope/ prefix from the package name, then rebuild a
      # `${basename}-${version}.tgz` filename for the registry path.
      pkg_basename="${name##*/}"
      version="$(jq -r '.version // empty' "$pkg" 2>/dev/null || true)"
      if [[ -n "$version" ]]; then
        registry_filename="${pkg_basename}-${version}.tgz"
      else
        # Defensive fallback: for unscoped packages the registry filename
        # is the same as the local filename, so keep behaviour identical.
        registry_filename="$filename"
      fi
      verify_recipe="$(cat <<EOF

Verify against the registry tarball:

\`\`\`sh
curl -sLO https://registry.npmjs.org/${name}/-/${registry_filename}
shasum -a 256 ${registry_filename}
\`\`\`
EOF
)"
      integrity_block="${integrity_block}${verify_recipe}"
    elif [[ -n "$name" ]]; then
      warn "package name '$name' contains unexpected characters — skipping verify recipe"
    fi

    notes="${notes}${integrity_block}"
    log "appended artefact integrity block to release body"
  else
    warn "tarball meta file present but missing required fields — skipping integrity block"
  fi
else
  log "no tarball meta at $meta_file — skipping integrity block"
fi

# Create-or-update logic. The legacy flow (caller triggered on
# release: published) always has a pre-existing Release -- the event is
# the trigger, so `gh release view` succeeds and we edit. The chained
# flow (auto-release.yml calls release.yml via workflow_call) pushed a
# tag but no human created a Release, so `gh release view` returns
# non-zero and we create. `gh release view` distinguishes 404 (absent)
# from auth/network failure by exit code 1 vs other non-zero. We treat
# any non-zero as "missing" and let `gh release create` surface real
# auth failures itself -- simpler than parsing stderr for "not found".
if gh release view "$tag" >/dev/null 2>&1; then
  log "updating release $tag"
  if ! gh release edit "$tag" --notes "$notes"; then
    die "gh release edit failed"
  fi
else
  log "creating release $tag"
  # --target pins the Release to a specific SHA. In the chained flow the
  # publish job checks out the tag, so either $GITHUB_SHA (set by the
  # runner) or `git rev-parse HEAD` resolves to the tagged commit. When
  # neither is available (e.g. running outside a git checkout, as in
  # bats fixtures), we omit --target and let gh default.
  target_sha="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || true)}"
  create_args=(release create "$tag" --title "$tag" --notes "$notes")
  if [[ -n "$target_sha" ]]; then
    create_args+=(--target "$target_sha")
  fi
  if ! gh "${create_args[@]}"; then
    die "gh release create failed"
  fi
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
