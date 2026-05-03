#!/usr/bin/env bash
# publish-npm.sh — idempotent npm publish via OIDC trusted publishing.
#
# Flow: read the recorded tarball, enforce OIDC/provenance invariants,
# check registry idempotency, dry-run, then publish that exact tarball.
# Re-packing here would break the integrity story. Install-hook defence
# lives in verify-lifecycle-scripts, which runs earlier.
#
# OIDC requirements: `id-token: write`, setup-node registry config, and
# an npm trusted publisher for the caller repo/workflow.
#
# Env:
#   PACKAGE_JSON       (default: package.json)
#   TARBALL_META_DIR   (default: $RUNNER_TEMP/forgesworn-anvil)
#   DRY_RUN=1          skip the real publish (for smoke-testing)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

header "publish-npm"
require_cmds grep jq npm

pkg="${PACKAGE_JSON:-package.json}"
[[ -f "$pkg" ]] || die "$pkg not found"

name="$(jq -r '.name // empty' "$pkg")"
version="$(jq -r '.version // empty' "$pkg")"
[[ -n "$name" ]]    || die "$pkg has no .name"
[[ -n "$version" ]] || die "$pkg has no .version"

log "package: $name@$version"

if ! jq -e '.publishConfig.provenance == true' "$pkg" >/dev/null; then
  die "$pkg must set publishConfig.provenance to true"
fi

[[ -z "${NPM_TOKEN:-}" ]] || die "NPM_TOKEN is set; use OIDC trusted publishing, not long-lived npm tokens"
# actions/setup-node writes literal placeholders when registry-url is set
# without a real token: NODE_AUTH_TOKEN=XXXXX-XXXXX-XXXXX-XXXXX in env, and
# `_authToken=${NODE_AUTH_TOKEN}` in the generated .npmrc. npm 11.5+ ignores
# both during OIDC exchange, but a strict null/auth-material check would
# trip on them. We accept the exact placeholder forms and reject anything
# else. See actions/setup-node src/authutil.ts.
SETUP_NODE_TOKEN_PLACEHOLDER='XXXXX-XXXXX-XXXXX-XXXXX'
if [[ -n "${NODE_AUTH_TOKEN:-}" && "${NODE_AUTH_TOKEN}" != "$SETUP_NODE_TOKEN_PLACEHOLDER" ]]; then
  die "NODE_AUTH_TOKEN is set; use OIDC trusted publishing, not long-lived npm tokens"
fi
[[ -z "${NPM_CONFIG_PROVENANCE:-}" ]] || die "NPM_CONFIG_PROVENANCE is set; use publishConfig.provenance instead"

for npmrc in .npmrc "${NPM_CONFIG_USERCONFIG:-}"; do
  [[ -n "$npmrc" && -f "$npmrc" ]] || continue
  # Allow the literal `${NODE_AUTH_TOKEN}` template form written by
  # setup-node; reject any line whose auth value is anything else.
  if grep -E '(^|[/:])(_authToken|_auth|_password)[[:space:]]*=' "$npmrc" \
       | grep -vqE '=[[:space:]]*\$\{NODE_AUTH_TOKEN\}[[:space:]]*$'; then
    die "npm auth material found in $npmrc; remove token auth before publishing"
  fi
done

meta_dir="${TARBALL_META_DIR:-${RUNNER_TEMP:-/tmp}/forgesworn-anvil}"
meta_file="$meta_dir/tarball.meta"
[[ -f "$meta_file" ]] || die "tarball meta not found at $meta_file (record-tarball must run before publish-npm)"

filename=""
recorded_integrity=""
while IFS='=' read -r key value; do
  case "$key" in
    filename)  filename="$value" ;;
    integrity) recorded_integrity="$value" ;;
  esac
done < "$meta_file"

[[ -n "$filename"            ]] || die "meta file missing filename"
[[ -n "$recorded_integrity"  ]] || die "meta file missing integrity"
[[ "$filename" != *..* && "$filename" != /* ]] || die "suspicious filename in meta file: $filename"

# Reconstruct the path from our meta dir; `path=` may come from another job.
tarball_path="$meta_dir/$filename"
[[ -f "$tarball_path" ]] || die "tarball not found at $tarball_path"

# Idempotency and substitution alarm. E404 means clean first publish;
# any other `npm view` failure is ambiguous, so fail closed.
view_err="$(mktemp)"
trap 'rm -f "$view_err"' EXIT
if registry_integrity="$(npm view "${name}@${version}" dist.integrity 2>"$view_err")"; then
  if [[ -n "$registry_integrity" ]]; then
    if [[ "$registry_integrity" == "$recorded_integrity" ]]; then
      ok "${name}@${version} already on registry with matching integrity — nothing to publish"
      exit 0
    fi
    warn "registry integrity: $registry_integrity"
    warn "local integrity:    $recorded_integrity"
    die "${name}@${version} on registry does not match locally built tarball — possible registry substitution or non-deterministic build; investigate before re-running"
  fi
  # `npm view` succeeded but returned empty — the version is unpublished
  # (npm keeps the name but erases the dist block). Proceed to publish.
else
  if ! grep -qE 'E404|is not in this registry|code E404' "$view_err"; then
    warn "npm view failed with a non-404 error:"
    cat "$view_err" >&2 || true
    die "cannot confirm registry state for ${name}@${version}; refusing to publish until the registry is reachable"
  fi
  log "${name}@${version} not on registry (E404) — proceeding to publish"
fi

# Do not pass --provenance; package.json publishConfig drives it.
log "running dry-run first"
if ! npm publish --dry-run --access public "$tarball_path"; then
  die "npm publish --dry-run failed"
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  warn "DRY_RUN=1 set — skipping real publish"
  exit 0
fi

log "publishing $tarball_path"
if ! npm publish --access public "$tarball_path"; then
  die "npm publish failed"
fi

ok "${name}@${version} published"
