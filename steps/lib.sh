#!/usr/bin/env bash
# lib.sh — shared helpers for forgesworn/anvil steps.
#
# Sourced by every step script. Keep tiny — the whole action must be
# auditable in under thirty minutes.
#
# Usage:
#   source "$(dirname "$0")/lib.sh"
#   header "verify-tag"
#   log "checking package.json"
#   die "tag mismatch"

set -euo pipefail

# Colours only when stdout is a TTY or GitHub Actions (which strips ANSI safely).
if [[ -t 1 || -n "${GITHUB_ACTIONS:-}" ]]; then
  _RED=$'\033[31m'
  _YELLOW=$'\033[33m'
  _GREEN=$'\033[32m'
  _BOLD=$'\033[1m'
  _RESET=$'\033[0m'
else
  _RED=""; _YELLOW=""; _GREEN=""; _BOLD=""; _RESET=""
fi

# Name of the currently running step, for prefixing log lines.
_STEP_NAME="${_STEP_NAME:-$(basename "${0:-step}" .sh)}"

header() {
  local title="${1:-$_STEP_NAME}"
  _STEP_NAME="$title"
  printf '%s\n' "${_BOLD}==> ${title}${_RESET}"
}

log() {
  printf '  %s\n' "$*"
}

warn() {
  printf '%s\n' "${_YELLOW}  warning: $*${_RESET}" >&2
}

ok() {
  printf '%s\n' "${_GREEN}  ok: $*${_RESET}"
}

die() {
  printf '%s\n' "${_RED}${_BOLD}  error: $*${_RESET}" >&2
  # Emit a GitHub Actions error annotation so the failure is visible on the PR.
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    printf '::error title=%s::%s\n' "$_STEP_NAME" "$*"
  fi
  exit 1
}

# Require that each named command is on PATH. Used at the top of every step.
require_cmds() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    die "missing required commands: ${missing[*]}"
  fi
}

# Strip a leading "v" from a version-like string, if present.
# Example: strip_v "v1.2.3" => "1.2.3"
strip_v() {
  printf '%s' "${1#v}"
}
