#!/usr/bin/env bash
# compare-tarball-meta.sh — compare two tarball.meta files produced by
# record-tarball.sh on independent runners. The reproducibility gate.
#
# Usage:
#   compare-tarball-meta.sh META_A META_B
#
# Behaviour:
#   - sha256 lines equal -> exit 0 (reproducible)
#   - sha256 lines differ + STRICT=1 -> die (release blocked)
#   - sha256 lines differ + STRICT unset -> warn, exit 0 (warn mode)
#
# On a mismatch the script prints both hashes and (if the tarball
# files are still on disk and `tar` is available) a diff of the two
# tar listings, so the maintainer can see which file's mtime or
# content drifted. The diagnostic is the message — consumers should
# not have to read source to understand the failure.
#
# Env:
#   STRICT   "1" promotes a hash mismatch from warn to fail.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "compare-tarball-meta"

meta_a="${1:-}"
meta_b="${2:-}"
[[ -n "$meta_a" && -n "$meta_b" ]] || die "usage: compare-tarball-meta.sh META_A META_B"
[[ -f "$meta_a" ]] || die "meta file not found: $meta_a"
[[ -f "$meta_b" ]] || die "meta file not found: $meta_b"

extract_field() {
  local field="$1"
  local file="$2"
  # `|| true` swallows the pipefail when grep finds nothing — we want
  # an empty string in that case so the caller's `[[ -n ]]` check can
  # do the right thing.
  grep "^${field}=" "$file" 2>/dev/null | cut -d= -f2- || true
}

sha_a="$(extract_field sha256 "$meta_a")"
sha_b="$(extract_field sha256 "$meta_b")"
[[ -n "$sha_a" ]] || die "$meta_a missing sha256 line"
[[ -n "$sha_b" ]] || die "$meta_b missing sha256 line"

log "build-A sha256: $sha_a"
log "build-B sha256: $sha_b"

# emit_reproducible_output writes a step output the workflow can read
# to decide whether to flag the release as reproducible. Guarded so
# the script also runs cleanly in bats tests where GITHUB_OUTPUT is
# unset.
emit_reproducible_output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf 'reproducible=%s\n' "$1" >> "$GITHUB_OUTPUT"
  fi
}

if [[ "$sha_a" == "$sha_b" ]]; then
  emit_reproducible_output 1
  ok "tarballs are byte-identical between two independent builds"
  exit 0
fi

emit_reproducible_output 0

# Mismatch — print the diagnostic.
warn "tarball hashes diverged between two independent builds"

path_a="$(extract_field path "$meta_a")"
path_b="$(extract_field path "$meta_b")"
if [[ -f "$path_a" && -f "$path_b" ]] && command -v tar >/dev/null 2>&1; then
  log "tar listing diff (build-A vs build-B):"
  diff <(tar -tvf "$path_a" 2>/dev/null) <(tar -tvf "$path_b" 2>/dev/null) || true
fi

cat >&2 <<'GUIDE'

Common causes of non-reproducible JS builds:
  - Date.now() or build timestamp embedded in compiled output
  - Sorted-by-filesystem-order globs that depend on inode order
  - Random IDs (UUIDs, salts) generated at build time
  - Bundler config that injects host paths into source maps

To investigate locally:
  diff <(tar -tvf tarball-A.tgz) <(tar -tvf tarball-B.tgz)

To allow non-reproducible releases temporarily, set
`reproducibility-mode: warn` in your caller workflow's `with:` block.
GUIDE

if [[ "${STRICT:-0}" == "1" ]]; then
  die "reproducibility check failed under strict mode"
fi
warn "reproducibility check failed under non-strict mode — release will continue"
exit 0
