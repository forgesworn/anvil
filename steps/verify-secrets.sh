#!/usr/bin/env bash
# verify-secrets.sh — pre-publish secret scan.
#
# Refuses to publish if a file matching a forbidden name or any file
# containing a known secret-marker pattern is found anywhere inside the
# packable artefacts (dist/ and any other files/directories listed in
# package.json "files").
#
# Pattern list is inline and deliberately small — every addition is a
# trade-off between false positives blocking real releases and true
# positives leaking real secrets. Keep conservative; a consuming repo can
# add its own pre-step if it needs stricter rules.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-secrets"
require_cmds jq grep find

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

# Files/directories to scan = everything listed in package.json "files",
# plus dist/ as a hard default (covers the common case).
roots=()
while IFS= read -r line; do
  [[ -n "$line" ]] && roots+=("$line")
done < <(
  {
    jq -r '.files[]? // empty' "$pkg"
    echo "dist"
  } | awk 'NF' | sort -u
)

# Keep only those that exist on disk; error if none.
existing_roots=()
for r in "${roots[@]}"; do
  [[ -e "$r" ]] && existing_roots+=("$r")
done
if (( ${#existing_roots[@]} == 0 )); then
  die "no packable artefacts found on disk (checked: ${roots[*]})"
fi

log "scanning: ${existing_roots[*]}"

# Forbidden filenames (basename match). Expand carefully — every entry is
# a decision we've made about what should never ship.
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

# Filename checks.
for root in "${existing_roots[@]}"; do
  if [[ -f "$root" ]]; then
    # Single file — only the basename check applies.
    base="$(basename "$root")"
    for name in "${forbidden_names[@]}"; do
      if [[ "$base" == "$name" ]]; then
        warn "forbidden filename in packable artefacts: $root"
        fail=1
      fi
    done
    for glob in "${forbidden_globs[@]}"; do
      # shellcheck disable=SC2053
      if [[ "$base" == $glob ]]; then
        warn "forbidden filename pattern ($glob): $root"
        fail=1
      fi
    done
    continue
  fi
  # Directory — recursive find.
  for name in "${forbidden_names[@]}"; do
    while IFS= read -r hit; do
      warn "forbidden filename: $hit"
      fail=1
    done < <(find "$root" -type f -name "$name" 2>/dev/null)
  done
  for glob in "${forbidden_globs[@]}"; do
    while IFS= read -r hit; do
      warn "forbidden filename pattern ($glob): $hit"
      fail=1
    done < <(find "$root" -type f -name "$glob" 2>/dev/null)
  done
done

# Content checks. We grep each pattern across all files under the roots.
# -I skips binary files; -r recurses; -E enables extended regex.
#
# Documentation file extensions are excluded because libraries legitimately
# publish protocol docs and test vectors containing example secrets (e.g.
# an nsec1 derived-key example in PROTOCOL.md). Filename-based checks above
# still cover those (.env in dist/docs would still fail), so the leak-in-
# source case is preserved.
content_exclude_globs=(
  '*.md'
  '*.markdown'
  '*.txt'
  '*.rst'
  '*.adoc'
)
grep_excludes=()
for glob in "${content_exclude_globs[@]}"; do
  grep_excludes+=(--exclude="$glob")
done

for pattern in "${forbidden_patterns[@]}"; do
  while IFS= read -r hit; do
    warn "forbidden content ($pattern): $hit"
    fail=1
  done < <(
    grep -rEIl --binary-files=without-match "${grep_excludes[@]}" -- "$pattern" "${existing_roots[@]}" 2>/dev/null || true
  )
done

if (( fail )); then
  die "secret scan found issues — refusing to publish"
fi

ok "no forbidden filenames or content patterns found"
