# Changelog

## 0.8.2 (2026-04-12)

### Bug Fixes

- strip lifecycle-script stdout before parsing npm pack --json



## 0.8.1 (2026-04-12)

### Bug Fixes

- remove invalid runner.temp from publish job-level env



## 0.8.0 (2026-04-12)

### Features

- bridge auto-release to release.yml via workflow_dispatch



## 0.7.0 (2026-04-12)

### Features

- chain auto-release publish into release.yml via workflow_call
- release workflow accepts explicit tag input



## 0.6.0 (2026-04-12)

### Features

- create or update Release to support chained auto-release flow

## 0.5.1 (2026-04-12)

### Bug Fixes

- include repo root in context7 indexed folders



## 0.5.0 (2026-04-12)

### Features

- conventional commit versioning (`version-strategy: verify`)
- `auto-release.yml` companion workflow for push-to-main automation
- wider ecosystem positioning (migration guides, comparison doc)

### Bug Fixes

- add .env, key material, and IDE patterns to .gitignore
- harden CI/CD workflows against expression injection and credential leaks
- harden scripts against injection, path traversal, and fragile patterns

## 0.4.1 (2026-04-11)

### Bug Fixes

- fix scoped-package registry URL in artefact integrity verify recipe
  (`@scope/pkg` tarballs got a 404; hashes were always correct)
- add 4 regression tests for scoped/unscoped URL construction

## 0.4.0 (2026-04-11)

### Features

- **multi-runner reproducible-build attestation** (flagship): two parallel
  CI builds on independent runners must produce byte-identical tarballs
  or the release is blocked
- four-job DAG: build-a, build-b, reproduce, publish
- `normalise-mtimes.sh`: touch all files to SOURCE_DATE_EPOCH for
  deterministic tar headers
- `compare-tarball-meta.sh`: reproducibility gate (strict/warn/off)
- canonical tarball uploaded as GitHub Release asset
- `reproducibility-mode` input (default: strict)

### Stats

- 2 new step scripts, 16 new bats tests (59 total)
- ~1250 lines of bash (inside 30-minute audit budget)

## 0.3.0 (2026-04-11)

### Features

- **artefact integrity bundle**: sha256 + sha512 integrity block appended
  to every GitHub Release body with a one-line verify recipe
- `record-tarball.sh`: pack once, hash, write tarball.meta for the pipeline
- `publish-npm.sh`: upload the exact recorded tarball (no re-pack)
- `verify-action-pins.sh`: warn/fail on unpinned `uses:` refs in consumer
  workflows (warn-only by default, `strict-action-pins: true` to fail)

### Stats

- 2 new step scripts, 13 new bats tests (43 total)
- ~1000 lines of bash


