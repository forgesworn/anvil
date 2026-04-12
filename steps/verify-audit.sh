#!/usr/bin/env bash
# verify-audit.sh — runtime dependency audit.
#
# Runs `npm audit --omit=dev` so that devDependency noise does not block
# a release, but any advisory in the *runtime* dep tree does. This is the
# opposite of semantic-release's behaviour, which audits everything and
# drowns you in devDep drama.
#
# Fail level: low. Crypto libraries should treat even low-severity runtime
# advisories as worth investigating before publishing a new version.
#
# Env:
#   AUDIT_LEVEL   (default: low) — one of low, moderate, high, critical

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-audit"
require_cmds npm

level="${AUDIT_LEVEL:-low}"
log "npm audit --omit=dev --audit-level=$level"

# npm audit exits non-zero if advisories exist at or above --audit-level.
if npm audit --omit=dev --audit-level="$level"; then
  ok "no runtime advisories at or above $level"
else
  die "runtime audit found advisories — refusing to publish"
fi
