#!/usr/bin/env bash
# normalise-mtimes.sh — set every file/dir mtime in the working tree to
# $SOURCE_DATE_EPOCH so a subsequent `npm pack` produces tar headers
# that are byte-identical between runs.
#
# Why this is belt-and-braces:
#   We *also* set SOURCE_DATE_EPOCH in the environment so that any
#   build tool that honours it (most modern bundlers do) emits
#   deterministic embedded timestamps. But not every JS build tool
#   honours it cleanly, and `npm pack` itself uses file mtimes for
#   tar entry headers regardless. Touching every file to a fixed
#   epoch closes the file-stamp gap unconditionally — leaving only
#   embedded timestamps inside compiled output as the consumer's
#   determinism problem.
#
# Excluded paths: node_modules and .git. node_modules is huge and
# never ends up in the pack; .git is metadata. Both are skipped to
# keep the touch pass quick and to avoid touching files outside the
# pack set. Any nested node_modules or .git is also skipped.
#
# Cross-platform: GNU touch (Linux runners) and BSD touch (macOS dev
# machines) both accept `-t YYYYMMDDhhmm.SS`, so we precompute that
# string from $SOURCE_DATE_EPOCH and pass it once. GNU and BSD `date`
# differ on how they accept a unix timestamp on input, so we detect
# which is available.
#
# Env:
#   SOURCE_DATE_EPOCH   required, unix epoch seconds

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "normalise-mtimes"
require_cmds find touch date

epoch="${SOURCE_DATE_EPOCH:-}"
[[ -n "$epoch" ]] || die "SOURCE_DATE_EPOCH not set"
[[ "$epoch" =~ ^[0-9]+$ ]] || die "SOURCE_DATE_EPOCH must be a unix timestamp (got: $epoch)"

# Detect GNU vs BSD date and produce a YYYYMMDDhhmm.SS string that
# both GNU and BSD `touch -t` accept.
if date -u -d "@0" +%Y >/dev/null 2>&1; then
  touch_ts="$(date -u -d "@$epoch" +%Y%m%d%H%M.%S)"
elif date -u -r 0 +%Y >/dev/null 2>&1; then
  touch_ts="$(date -u -r "$epoch" +%Y%m%d%H%M.%S)"
else
  die "neither GNU nor BSD date understood — cannot format $epoch"
fi

log "normalising mtimes to $touch_ts (epoch $epoch)"

# Touch every file and directory under cwd, excluding node_modules
# and .git (and any nested copies). The `+` form batches paths up to
# ARG_MAX per touch invocation for efficiency. Find handles an empty
# match set gracefully — no error if there's nothing to touch.
find . \( -name node_modules -o -name .git \) -prune -o \
       \( -type f -o -type d \) -exec touch -t "$touch_ts" {} +

ok "mtimes normalised"
