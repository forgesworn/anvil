# CLAUDE.md -- forgesworn/anvil

## What this is

A GitHub Action (reusable workflow + composite fallback) that publishes
npm packages with hard pre-publish gates. Pure bash, no Node tooling in
the action itself. Target audience: cryptography and supply-chain-sensitive
JS/TS library maintainers.

## Architecture

```
action.yml          Composite action (no reproducible-build gate)
.github/workflows/
  release.yml       Reusable workflow (four-job DAG, full protection)
  auto-release.yml  Companion: push-to-main conventional-commit automation
  ci.yml            CI: shellcheck + bats
steps/              All step scripts, all bash, all sourcing lib.sh
test/               bats tests
docs/               Migration guides, comparison, design docs
examples/           Consumer setup guide
```

## Key constraints

- **Audit budget**: total bash must stay under ~1600 lines (thirty-minute
  audit target). Check before adding code.
- **Zero dependencies**: no npm packages in the action itself. Only tools
  already on the GitHub Actions runner image (bash, jq, gh, npm).
- **Threat model**: every change must fit within THREAT-MODEL.md boundaries.
  If it expands the attack surface, update the threat model first.

## Development

```sh
bats test/*.bats        # run all tests
shellcheck -x steps/*.sh  # lint step scripts
```

## Conventions

- British English throughout.
- Commit style: `type: description` (lowercase, imperative). No Co-Authored-By.
- All step scripts source `steps/lib.sh` for shared helpers.
- Inputs default to safe values (strict-action-pins defaults to true,
  reproducibility-mode defaults to strict).

## Non-goals

- Monorepo support (single-package by design).
- Node-based tooling inside the action.
- Automated semver from commits as a release-blocking step (verify mode
  warns; auto-release.yml is a separate companion workflow, not a
  version-strategy value).
- Dependencies not on the default runner image.
