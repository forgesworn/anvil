# forgesworn/anvil

A GitHub Action (reusable workflow + composite fallback) that publishes npm
packages with hard pre-publish gates: reproducible-build attestation, OIDC
trusted publishing, secret scan, exports-map check, lifecycle-script check,
and action-pin auditing. Pure bash, no Node tooling in the action itself.

## Build & Test

| Command | Purpose |
|---------|---------|
| `bats test/*.bats` | Run the full test suite |
| `shellcheck -x steps/*.sh` | Lint step scripts (`-x` follows sourced `lib.sh`) |
| `wc -l steps/*.sh` | Check the audit budget before adding code |

CI (`.github/workflows/ci.yml`) runs both `shellcheck` and `bats` on push and
pull request to `main`.

## Structure

```
action.yml          Composite action (no reproducible-build gate)
.github/workflows/
  release.yml       Reusable workflow (four-job DAG, full protection)
  auto-release.yml  Companion: push-to-main conventional-commit automation
  ci.yml             CI: shellcheck + bats
steps/               All step scripts, all bash, all sourcing lib.sh
test/                bats tests
docs/                Migration guides, comparison, design docs
examples/            Consumer setup guide
```

## Conventions

- British English throughout (`LICENCE`, "normalise", "optimise").
- Commit style: `type: description` (lowercase, imperative). No
  `Co-Authored-By` trailers.
- All step scripts source `steps/lib.sh` for shared helpers.
- Inputs default to safe values (`strict-action-pins` defaults to `true`,
  `reproducibility-mode` defaults to `strict`).

## Key Files

| File | Purpose |
|------|---------|
| `THREAT-MODEL.md` | Defended and explicitly-undefended surfaces; load-bearing |
| `steps/lib.sh` | Shared helpers (`header`, `log`, `warn`, `die`, `require_cmds`) |
| `llms.txt` / `llms-full.txt` | Agent-facing API reference; keep in sync with the source |

## Common Pitfalls

- **Audit budget**: total bash across `steps/*.sh` must stay under ~1600
  lines so the whole action remains auditable in thirty minutes. Check
  `wc -l steps/*.sh` before adding code.
- **Zero dependencies**: no npm packages, no compiled binaries, no fetched
  tooling. Only tools already on the GitHub Actions runner image (bash, jq,
  gh, npm, shasum, awk, sed, find, grep).
- **Threat model is load-bearing**: any change that expands the attack
  surface must update `THREAT-MODEL.md` first.
- **Non-goals**: monorepo support (single-package by design), Node-based
  tooling inside the action, automated semver from commits as a
  release-blocking step (`verify` mode warns; `auto-release.yml` is a
  separate companion workflow, not a version-strategy value), dependencies
  not on the default runner image.
