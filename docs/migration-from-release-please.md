# Migrating from release-please

If you are moving a JavaScript/TypeScript library off `release-please`
and onto `forgesworn/anvil`, this is the diff. release-please
creates release PRs but does not publish to npm. anvil handles
the entire pipeline including publish. The migration is additive: you
are gaining a publish step, not losing one.

## Before you start

You need:

- A library that already publishes to npm (or is ready to).
- Commit rights to the repo and publish rights to the package on npmjs.com.

Read [the README's "Trusted publisher caveat" section](../README.md#trusted-publisher-caveat-important)
first.

## The diff

Four concrete changes.

### 1. Replace the release-please workflow

Your current workflow probably looks like this:

```yaml
name: release-please
on:
  push:
    branches: [main]
jobs:
  release-please:
    uses: googleapis/release-please-action@v4
    # ... followed by a conditional npm publish step
```

Replace it with two workflows.

**`.github/workflows/auto-release.yml`** — parses conventional
commits, bumps, tags, and dispatches release.yml:

```yaml
name: auto-release
on:
  push:
    branches: [main]
permissions:
  contents: write
  actions: write
jobs:
  auto-release:
    uses: forgesworn/anvil/.github/workflows/auto-release.yml@v0
```

**`.github/workflows/release.yml`** — runs gates and publishes.
Needs both `release: published` (for manual releases) and
`workflow_dispatch` (for auto-release to dispatch):

```yaml
name: release
on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      tag:
        description: Release tag to publish
        type: string
        required: true
permissions:
  contents: write
  id-token: write
jobs:
  release:
    uses: forgesworn/anvil/.github/workflows/release.yml@v0
    with:
      tag: ${{ inputs.tag || '' }}
```

### 2. Remove release-please configuration

```sh
git rm release-please-config.json .release-please-manifest.json
```

If you have a `.github/release-please.yml` or similar, remove that too.

### 3. Update package.json

Make sure `publishConfig.provenance` is set:

```json
"publishConfig": {
  "provenance": true
}
```

Remove any release-please-specific scripts if they exist.

### 4. Configure the npm trusted publisher

On `npmjs.com`, go to your package's Settings -> Trusted Publishers and
add GitHub Actions:

| Field | Value |
|---|---|
| Publisher | GitHub Actions |
| Organization or user | your org or user |
| Repository | **your package's repo** (not `forgesworn/anvil`) |
| Workflow filename | `release.yml` (your caller workflow) |
| Environment | `npm-publish` |

Create a matching GitHub Environment named `npm-publish` if you want
required reviewers, prevent self-review, or release-ref restrictions
before npm publish.

## What changes

| Before (release-please) | After (anvil) |
|---|---|
| Release PR with version bump + CHANGELOG | auto-release commits directly to main |
| Separate npm publish step you maintain | Publish built into the pipeline |
| No OIDC, no provenance (unless you added it) | OIDC + SLSA provenance on every publish |
| No supply-chain gates | Secret scan, exports check, reproducible builds |
| PR review gate before version bump | Version determined and applied automatically |

## What you give up

- The release PR review gate. release-please's main differentiator is
  that a human reviews and merges the version bump before it ships.
  anvil's `auto-release.yml` companion workflow commits the bump
  directly. If you want human approval, use `manual` mode instead -- you
  bump and tag yourself, and the action handles the rest.
- Multi-language support. release-please handles Java, Python, Go, Rust,
  etc. anvil is JS/TS only.
- Monorepo manifest mode. anvil is single-package by design.

## What you gain

- Complete publish pipeline with OIDC, provenance, and supply-chain gates.
- Reproducible-build attestation.
- Zero new dependencies (release-please is also dependency-light, but
  anvil adds the publish step without adding any).
