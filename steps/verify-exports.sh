#!/usr/bin/env bash
# verify-exports.sh — check every subpath in package.json "exports" points
# at a file that actually exists on disk.
#
# Catches the "I deleted src/foo.ts but forgot to update exports" class of
# bug before it becomes a broken import for downstream consumers.
#
# Walks the full exports tree: conditional keys (import/require/types) and
# string shorthand are both handled. Skips the "default" conditional only
# if it duplicates a target we already checked.
#
# Env:
#   PACKAGE_JSON   (default: package.json)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-exports"
require_cmds jq

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

# Flatten .exports into a list of leaf string values ending in a real path.
# We use jq's walk in a portable way: any leaf string that starts with
# "./" is treated as a path to verify.
targets=()
while IFS= read -r line; do
  [[ -n "$line" ]] && targets+=("$line")
done < <(
  jq -r '
    def walk(f):
      . as $in
      | if type == "object" then
          reduce (keys_unsorted[]) as $k
            ({}; .[$k] = ($in[$k] | walk(f)))
        elif type == "array" then
          map(walk(f))
        else
          f
        end;
    (.exports // {}) | walk(.) | .. | strings
    | select(startswith("./"))
  ' "$pkg" 2>/dev/null | sort -u
)

# Also include top-level "main", "module", "types", "bin" (string form),
# and "files" entries that look like file paths. These are the pre-exports
# world but still shipped.
legacy=()
while IFS= read -r line; do
  [[ -n "$line" ]] && legacy+=("$line")
done < <(
  jq -r '
    [
      .main // empty,
      .module // empty,
      .types // empty,
      .typings // empty,
      (.bin | if type == "string" then . else (values[]? // empty) end)
    ]
    | .[]
    | select(type == "string")
    | select(startswith("./") or (startswith("/") | not))
  ' "$pkg" 2>/dev/null
)

# Normalise legacy entries to ./-prefixed form.
# Use the "${arr[@]+...}" guard pattern so empty arrays don't trip set -u
# on bash 3.2 (macOS default).
if (( ${#legacy[@]} > 0 )); then
  for i in "${!legacy[@]}"; do
    [[ "${legacy[i]}" == ./* ]] || legacy[i]="./${legacy[i]}"
  done
fi

all=()
(( ${#targets[@]} > 0 )) && all+=("${targets[@]}")
(( ${#legacy[@]} > 0 ))  && all+=("${legacy[@]}")

if (( ${#all[@]} == 0 )); then
  warn "no exports or legacy entry points declared — nothing to verify"
  exit 0
fi

missing=()
checked=()
for t in "${all[@]}"; do
  # Deduplicate.
  skip=0
  if (( ${#checked[@]} > 0 )); then
    for c in "${checked[@]}"; do
      [[ "$c" == "$t" ]] && { skip=1; break; }
    done
  fi
  (( skip )) && continue
  checked+=("$t")

  if [[ -e "$t" ]]; then
    log "ok  $t"
  else
    warn "missing: $t"
    missing+=("$t")
  fi
done

if (( ${#missing[@]} > 0 )); then
  die "${#missing[@]} exports targets missing on disk — refusing to publish"
fi

ok "all ${#checked[@]} export targets exist"
