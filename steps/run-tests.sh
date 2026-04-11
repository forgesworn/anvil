#!/usr/bin/env bash
# run-tests.sh — run the full test suite before publish.
#
# Thin wrapper over a configurable command (defaults to `npm test`).
# The main reason this exists as a separate step rather than inlined in
# action.yml is so that bats can smoke-test it against a fixture.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "run-tests"

cmd="${TEST_COMMAND:-npm test}"
log "running: $cmd"

if bash -c "$cmd"; then
  ok "tests passed"
else
  die "tests failed — refusing to publish"
fi
