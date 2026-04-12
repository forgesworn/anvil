#!/usr/bin/env bash
# verify-vectors.sh — run the frozen test vector gate.
#
# Frozen test vector gate. The consumer configures a command that exits
# non-zero if any canonical/frozen output has changed since the last
# release. Useful for any library with deterministic outputs: crypto,
# codecs, parsers, serialisation.
#
# If no command is configured, we log and skip — it is the consumer's
# responsibility to opt in, and plenty of libraries have nothing to freeze.
#
# Env:
#   VECTOR_TEST_COMMAND   (default: empty — skip the gate)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "verify-vectors"

cmd="${VECTOR_TEST_COMMAND:-}"

if [[ -z "$cmd" ]]; then
  warn "no vector-test-command configured — skipping frozen-vector gate"
  warn "libraries with deterministic outputs should configure this; see forgesworn/anvil README"
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
