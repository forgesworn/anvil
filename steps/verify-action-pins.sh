#!/usr/bin/env bash
# verify-action-pins.sh — flag unpinned third-party action references.
#
# Walks .github/workflows/*.yml in the consumer repo and emits a warning
# for every `uses: owner/repo@ref` line whose ref is not a 40-char hex
# SHA. By default this is warn-only, so a consumer adopting the gate
# does not see their release start failing overnight. STRICT_ACTION_PINS=1
# promotes the warnings to a hard failure.
#
# Why this matters: a tag-pinned action (`@v4`) can be silently
# re-pointed at malicious code by an attacker who compromises the
# action's repo or tag namespace. SHA pinning binds the action to a
# specific commit, so re-pointing has no effect on existing consumers.
# This is the same vector that hit `tj-actions/changed-files` in
# March 2025.
#
# Self-exemption: forgesworn/anvil is exempt by name. Without
# this carve-out, every consumer's gate would fail on the very line
# that loads the gate (their `uses: forgesworn/anvil@v0`).
# Consumers who want SHA pinning of anvil itself should pin
# the version in their caller workflow with a 40-char SHA AND set
# strict-action-pins: true; the exemption is by name, not by ref, so
# a consumer who pins us with a SHA still gets the SHA enforcement
# they want from the rest of their workflow.
#
# Known false negative: dynamic uses (`uses: ${{ matrix.action }}`)
# are not statically resolvable and are not flagged. THREAT-MODEL.md
# notes this.
#
# Env:
#   WORKFLOWS_DIR        (default: .github/workflows)
#   STRICT_ACTION_PINS   ("1" promotes warn to fail)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-action-pins"
require_cmds grep find sed

workflows_dir="${WORKFLOWS_DIR:-.github/workflows}"
strict="${STRICT_ACTION_PINS:-0}"

if [[ ! -d "$workflows_dir" ]]; then
  log "no workflows directory at $workflows_dir — nothing to verify"
  ok "skipped"
  exit 0
fi

# Avoid bash 4+ `mapfile` so this works on macOS's stock bash 3.2 too.
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find "$workflows_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

if (( ${#files[@]} == 0 )); then
  log "no workflow files in $workflows_dir"
  ok "skipped"
  exit 0
fi

unpinned_count=0
total_count=0

for file in "${files[@]}"; do
  # Fast filter: only inspect lines that look like a `uses: x@y` ref.
  # Precise parse happens in the bash regex below.
  while IFS=: read -r lineno content; do
    [[ -z "$lineno" ]] && continue

    # Strip leading whitespace and an optional list-marker dash so the
    # downstream regex can anchor on `^uses:`. Comment lines remain
    # prefixed by `#` and the anchored regex below skips them.
    line="$(printf '%s' "$content" | sed -E 's/^[[:space:]]*-?[[:space:]]*//')"

    if [[ "$line" =~ ^uses:[[:space:]]*([^@[:space:]#]+)@([^[:space:]#]+) ]]; then
      action="${BASH_REMATCH[1]}"
      ref="${BASH_REMATCH[2]}"
      total_count=$((total_count + 1))

      # Self-exemption — see header comment. Matches both the
      # composite-action form (`forgesworn/anvil`) and the
      # reusable-workflow form (`forgesworn/anvil/.github/...`).
      # Still warn if the ref is not a SHA — callers using @v0 are
      # exposed to tag retargeting on the highest-privilege dependency
      # in the release job.
      if [[ "$action" == "forgesworn/anvil" || "$action" == forgesworn/anvil/* ]]; then
        if [[ ! "$ref" =~ ^[0-9a-f]{40}$ ]]; then
          warn "forgesworn/anvil is not SHA-pinned ($ref) — consider pinning to a commit SHA"
        fi
        continue
      fi

      # Local actions (./) are always resolved from the same repo checkout.
      if [[ "$action" == ./* ]]; then
        continue
      fi

      # Docker references use image digests for pinning, not commit SHAs.
      # Flag docker:// refs whose @ref is not a sha256 digest.
      # Note: docker://image:tag references (no @) are not caught by the
      # grep filter and are a known gap — they never reach this code path.
      if [[ "$action" == docker://* ]]; then
        if [[ "$ref" != sha256:* ]]; then
          warn "unpinned container action: $file:$lineno  $action@$ref (no digest)"
          unpinned_count=$((unpinned_count + 1))
        fi
        continue
      fi

      if [[ ! "$ref" =~ ^[0-9a-f]{40}$ ]]; then
        warn "unpinned action: $file:$lineno  $action@$ref"
        unpinned_count=$((unpinned_count + 1))
      fi
    fi
  done < <(grep -nE 'uses:[[:space:]]*[^[:space:]]+@' "$file" || true)
done

if (( unpinned_count > 0 )); then
  if [[ "$strict" == "1" ]]; then
    die "$unpinned_count unpinned action reference(s) found (strict-action-pins enabled)"
  fi
  warn "$unpinned_count unpinned action reference(s) — consider SHA pins"
  log "set strict-action-pins: true in your caller workflow to make this fatal"
  log "(forgesworn/anvil itself is exempt; see THREAT-MODEL.md)"
fi

ok "$total_count action ref(s) inspected, $unpinned_count unpinned"
