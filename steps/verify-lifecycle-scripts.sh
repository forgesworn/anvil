#!/usr/bin/env bash
# verify-lifecycle-scripts.sh — refuse to publish packages whose install
# lifecycle scripts would run arbitrary code on every consumer.
#
# npm runs `preinstall`, `install`, and `postinstall` scripts
# automatically when a consumer runs `npm install <pkg>`. A malicious
# script set in one of these hooks lets a compromised publish execute
# code on every consumer machine with no user interaction. This is the
# payload mechanism used in the April 2026 Bitwarden CLI compromise,
# where @bitwarden/cli@2026.4.0 shipped a preinstall hook pointing at
# a credential-stealer loader (bw1.js / bw_setup.js).
#
# The gate reads `scripts` from the consumer's package.json — the same
# object that ships in the published tarball — and compares each of the
# three install-time hooks against an explicit allowlist. Anything not
# on the allowlist warns (default) or fails (strict).
#
# Why not block all three unconditionally: native-module packages
# legitimately use `postinstall` for `node-gyp rebuild` or similar
# build-on-install behaviour. The allowlist lets those packages declare
# intent without disabling the gate.
#
# Policy:
#   warn   (default) -- log a warning for each unpermitted hook; publish continues
#   strict          -- fail the release if any unpermitted hook is present
#   off             -- skip the gate entirely
#
# Allowlist format: JSON object mapping hook name to the exact command
# string permitted. An exact string match is required; a different
# command in the same hook is treated as "not allowlisted". Empty map
# (the default) means "no install hooks allowed".
#
# Example caller configuration:
#   lifecycle-scripts-policy: strict
#   allowed-lifecycle-scripts: '{"postinstall": "node-gyp rebuild"}'
#
# Env:
#   PACKAGE_JSON                (default: package.json)
#   LIFECYCLE_POLICY            (warn|strict|off, default warn)
#   ALLOWED_LIFECYCLE_SCRIPTS   (JSON object, default "{}")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-lifecycle-scripts"

policy="${LIFECYCLE_POLICY:-warn}"
case "$policy" in
  warn|strict) ;;
  off) log "lifecycle-scripts-policy=off — skipping"; ok "skipped"; exit 0 ;;
  *) die "lifecycle-scripts-policy must be one of: warn, strict, off (got: '$policy')" ;;
esac

require_cmds jq

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

allowed_raw="${ALLOWED_LIFECYCLE_SCRIPTS:-}"
[[ -z "$allowed_raw" ]] && allowed_raw='{}'
if ! printf '%s' "$allowed_raw" | jq -e 'type == "object"' >/dev/null 2>&1; then
  die "allowed-lifecycle-scripts must be a JSON object (got: $allowed_raw)"
fi

# Hooks npm runs on `npm install <pkg>` for every consumer of the
# published package. Build-time hooks (prepack, prepare, prepublishOnly)
# are deliberately not in this list: those run on the publisher's
# machine at pack/publish time, not on the consumer.
hooks=(preinstall install postinstall)

fail=0
found_any=0

for hook in "${hooks[@]}"; do
  cmd="$(jq -r --arg h "$hook" '.scripts[$h] // empty' "$pkg")"
  [[ -z "$cmd" ]] && continue
  found_any=1

  allowed_cmd="$(printf '%s' "$allowed_raw" | jq -r --arg h "$hook" '.[$h] // empty')"

  if [[ -n "$allowed_cmd" && "$allowed_cmd" == "$cmd" ]]; then
    ok "$hook allowed by allowlist: $cmd"
    continue
  fi

  if [[ -n "$allowed_cmd" ]]; then
    warn "$hook mismatch: package.json has '$cmd' but allowlist expects '$allowed_cmd'"
  else
    warn "$hook hook set in package.json: $cmd"
  fi
  fail=1
done

if (( found_any == 0 )); then
  ok "no preinstall/install/postinstall hooks declared"
  exit 0
fi

if (( fail )); then
  if [[ "$policy" == "strict" ]]; then
    die "lifecycle-scripts-policy=strict: refusing to publish package with unpermitted install hooks"
  fi
  warn "lifecycle-scripts-policy=warn — publish will proceed; set to 'strict' to fail on unpermitted hooks"
  exit 0
fi

ok "all install hooks present are on the allowlist"
