#!/usr/bin/env bash
# record-tarball.sh — pack the release artefact and record its hashes.
#
# Runs after all gates and before publish-npm. Produces the canonical
# tarball that publish-npm will upload, and writes a meta file that the
# rest of the pipeline reads:
#
#   $TARBALL_META_DIR/tarball.meta   (key=value lines)
#
# Why pack here, not in publish-npm:
#   - publish-npm uploads the tarball at $path verbatim, so the bytes we
#     hash are byte-identical to the bytes the registry receives.
#   - update-release reads the same meta file and stamps the hashes into
#     the GitHub Release body, so consumers can hash-compare the
#     registry tarball against what CI built.
#   - npm pack --json already returns the SLSA-aligned sha512 integrity
#     value, so we do not have to roll our own.
#
# Determinism note: a single sha256 here is a single-runner integrity
# anchor, not a reproducible-build proof. Two runners may produce two
# different sha256s today due to embedded timestamps and path leakage.
# Reproducibility across runners is a v0.4 theme. THREAT-MODEL.md spells
# this out.
#
# Env:
#   PACKAGE_JSON       (default: package.json)
#   TARBALL_META_DIR   (default: $RUNNER_TEMP/forgesworn-release, then /tmp)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "record-tarball"
require_cmds jq npm shasum

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

meta_dir="${TARBALL_META_DIR:-${RUNNER_TEMP:-/tmp}/forgesworn-release}"
mkdir -p "$meta_dir"

log "packing into $meta_dir"
if ! pack_json="$(npm pack --pack-destination "$meta_dir" --json 2>/dev/null)"; then
  die "npm pack failed"
fi

filename="$(printf '%s' "$pack_json" | jq -r '.[0].filename // empty')"
integrity="$(printf '%s' "$pack_json" | jq -r '.[0].integrity // empty')"
size="$(printf '%s' "$pack_json" | jq -r '.[0].size // 0')"
unpacked="$(printf '%s' "$pack_json" | jq -r '.[0].unpackedSize // 0')"

[[ -n "$filename"  ]] || die "could not parse filename from npm pack --json"
[[ -n "$integrity" ]] || die "could not parse integrity from npm pack --json"

# `npm pack --json` returns the on-disk basename in .filename, which is
# what --pack-destination wrote. Scoped packages are flattened (e.g.
# @scope/name -> scope-name-1.0.0.tgz).
tarball_path="$meta_dir/$filename"
[[ -f "$tarball_path" ]] || die "expected tarball at $tarball_path but it is missing"

sha256="$(shasum -a 256 "$tarball_path" | awk '{print $1}')"
[[ -n "$sha256" ]] || die "sha256 computation failed"

meta_file="$meta_dir/tarball.meta"
{
  printf 'filename=%s\n'      "$filename"
  printf 'path=%s\n'          "$tarball_path"
  printf 'size=%s\n'          "$size"
  printf 'unpacked_size=%s\n' "$unpacked"
  printf 'sha256=%s\n'        "$sha256"
  printf 'integrity=%s\n'     "$integrity"
} > "$meta_file"

log "filename:  $filename"
log "size:      $size bytes (unpacked $unpacked)"
log "sha256:    $sha256"
log "integrity: $integrity"
ok "tarball recorded at $tarball_path"
