#!/usr/bin/env bash
# verify-secrets.sh -- pre-publish secret scan.
#
# Refuses to publish if a file matching a forbidden name or any file
# containing a known secret-marker pattern is found in the pack set.
#
# The pack set is derived from `npm pack --dry-run --json`, which is
# the authoritative source of what npm will actually publish. This
# avoids reimplementing npm's files/glob/ignore semantics and ensures
# we scan exactly the files that would end up in the tarball.
#
# Pattern list is inline and deliberately small -- every addition is a
# trade-off between false positives blocking real releases and true
# positives leaking real secrets. Keep conservative; a consuming repo
# can add its own pre-step if it needs stricter rules.
#
# Env:
#   PACKAGE_JSON   (default: package.json)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-secrets"
require_cmds jq grep npm

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

# ---------------------------------------------------------------------------
# Derive the pack set from npm itself
# ---------------------------------------------------------------------------

# npm pack --dry-run --json outputs the file list npm would actually
# publish. This is the single source of truth -- it respects "files",
# ".npmignore", and all of npm's inclusion/exclusion rules.
pack_json="$(npm pack --dry-run --json 2>/dev/null)" \
  || die "npm pack --dry-run --json failed"

# Extract file paths from the JSON output. npm pack --json returns an
# array of objects, each with a "files" array containing { "path": ... }.
pack_files=()
while IFS= read -r f; do
  [[ -n "$f" ]] && pack_files+=("$f")
done < <(echo "$pack_json" | jq -r '.[0].files[].path // empty')

if (( ${#pack_files[@]} == 0 )); then
  die "npm pack reported no files -- nothing to scan"
fi

log "scanning ${#pack_files[@]} files from npm pack set"

# Forbidden filenames (basename match). Expand carefully -- every entry
# is a decision we've made about what should never ship.
forbidden_names=(
  ".env"
  ".env.local"
  ".env.production"
  "id_rsa"
  "id_ed25519"
  "id_ecdsa"
  ".npmrc"
)

# Forbidden filename glob patterns (basename).
forbidden_globs=(
  "*.pem"
  "*.key"
  "*.p12"
  "*.pfx"
)

# Forbidden content patterns (grep -E regex). Case-sensitive.
# Each pattern is a hand-picked marker that should never appear in a
# published artefact.
forbidden_patterns=(
  '-----BEGIN (RSA |EC |OPENSSH |DSA |PRIVATE|ENCRYPTED) ?(PRIVATE )?KEY-----'
  '-----BEGIN PGP PRIVATE KEY BLOCK-----'
  'nsec1[ac-hj-np-z02-9]{58}'
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  'xox[baprs]-[0-9A-Za-z-]{10,}'
  'ghp_[0-9A-Za-z]{36}'
  'github_pat_[0-9A-Za-z_]{82}'
)

fail=0

# ---------------------------------------------------------------------------
# Filename checks against the actual pack set
# ---------------------------------------------------------------------------

for f in "${pack_files[@]}"; do
  base="$(basename "$f")"
  for name in "${forbidden_names[@]}"; do
    if [[ "$base" == "$name" ]]; then
      warn "forbidden filename in pack set: $f"
      fail=1
    fi
  done
  for glob in "${forbidden_globs[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$base" == $glob ]]; then
      warn "forbidden filename pattern ($glob): $f"
      fail=1
    fi
  done
done

# ---------------------------------------------------------------------------
# Content checks against files in the pack set
# ---------------------------------------------------------------------------

# Documentation file extensions are excluded because libraries legitimately
# publish protocol docs and test vectors containing example secrets (e.g.
# an nsec1 derived-key example in PROTOCOL.md). Filename-based checks above
# still cover those (.env in dist/docs would still fail), so the leak-in-
# source case is preserved.
content_exclude_exts=(
  md markdown txt rst adoc
)

# Build a filtered list of pack files to content-scan (excluding docs).
content_files=()
for f in "${pack_files[@]}"; do
  ext="${f##*.}"
  skip=false
  for exclude_ext in "${content_exclude_exts[@]}"; do
    if [[ "$ext" == "$exclude_ext" ]]; then
      skip=true
      break
    fi
  done
  [[ "$skip" == true ]] || content_files+=("$f")
done

for pattern in "${forbidden_patterns[@]}"; do
  for f in "${content_files[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -qEI --binary-files=without-match -- "$pattern" "$f" 2>/dev/null; then
      warn "forbidden content ($pattern): $f"
      fail=1
    fi
  done
done

if (( fail )); then
  die "secret scan found issues -- refusing to publish"
fi

ok "no forbidden filenames or content patterns found in ${#pack_files[@]} pack files"
