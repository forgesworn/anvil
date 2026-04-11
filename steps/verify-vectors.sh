#!/usr/bin/env bash
# verify-vectors.sh — run the frozen test vector gate.
#
# This is the crypto-library-specific gate. The consumer configures a
# command that exits non-zero if any canonical/frozen output has changed
# since the last release. For nsec-tree this is `npm run test:vectors`;
# for another lib it might be `cargo test --test frozen`.
#
# If no command is configured, we log and skip — it is the consumer's
# responsibility to opt in, and plenty of libraries have nothing to freeze.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-vectors"

cmd="${VECTOR_TEST_COMMAND:-}"

if [[ -z "$cmd" ]]; then
  warn "no vector-test-command configured — skipping frozen-vector gate"
  warn "crypto libraries should configure this; see forgesworn/release-action README"
  exit 0
fi

log "running: $cmd"

# Use bash -c so shell syntax in the configured command (pipes, env vars)
# works as the consumer expects.
if bash -c "$cmd"; then
  ok "frozen vectors unchanged"
else
  die "frozen vector gate failed — protocol output has drifted"
fi
