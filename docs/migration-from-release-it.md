# Migrating from release-it

If you are moving a JavaScript/TypeScript library off `release-it` and
onto `forgesworn/anvil`, this is the diff. release-it is a
pragmatic tool that works both locally and in CI. anvil is
CI-only by design. If you prefer publishing from your laptop, this
migration is not for you.

## Before you start

You need:

- A library that already publishes to npm via CI (not locally).
- Commit rights to the repo and publish rights to the package on npmjs.com.

Read [the README's "Trusted publisher caveat" section](../README.md#trusted-publisher-caveat-important)
first.

## The diff

Five concrete changes.

### 1. Add the caller workflow

Create `.github/workflows/release.yml`:

```yaml
name: release

on:
  release:
    types: [published]

permissions:
  contents: write
  id-token: write

jobs:
  release:
    uses: forgesworn/anvil/.github/workflows/release.yml@v0
```

If you used release-it's conventional changelog plugin and want to keep
automatic versioning, add `.github/workflows/auto-release.yml`
alongside the `release.yml` above, and add a `workflow_dispatch`
trigger + `tag` input to `release.yml` so auto-release can fire it:

```yaml
# .github/workflows/auto-release.yml
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

See the README's "Version strategy → Auto" section for the
workflow_dispatch additions to `release.yml`.

### 2. Remove the release-it workflow

If your CI currently runs `release-it` in a workflow, remove that job.

### 3. Delete release-it configuration

```sh
git rm .release-it.json   # or .release-it.yaml, .release-it.toml
```

Also remove any release-it config from `package.json` if it was inline:

```diff
- "release-it": {
-   "git": { "commitMessage": "chore: release v${version}" },
-   "npm": { "publish": true }
- },
```

### 4. Clean up package.json

Remove release-it devDependencies:

```diff
  "devDependencies": {
-   "release-it": "^19.2.4",
-   "@release-it/conventional-changelog": "^10.0.0",
```

Make sure `publishConfig.provenance` is set:

```json
"publishConfig": {
  "provenance": true
}
```

### 5. Run `npm install`

Regenerates `package-lock.json` without the release-it tree.

### 6. Configure the npm trusted publisher

On `npmjs.com`, go to your package's Settings -> Trusted Publishers and
add GitHub Actions:

| Field | Value |
|---|---|
| Publisher | GitHub Actions |
| Organization or user | your org or user |
| Repository | **your package's repo** (not `forgesworn/anvil`) |
| Workflow filename | `release.yml` (your caller workflow) |
| Environment | *(empty)* |

## First release

1. Bump `package.json` version.
2. Add a CHANGELOG entry.
3. Commit, push, tag, create a GitHub Release.

Or with the `auto-release.yml` companion workflow: push conventional commits to main.

## What changes

| Before (release-it) | After (anvil) |
|---|---|
| Interactive or CI mode | CI-only |
| Plugin-based (Git, GitHub, npm) | All-in-one reusable workflow |
| ~200 transitive deps | Zero release-tool deps |
| Optional OIDC | OIDC required + SLSA provenance |
| No supply-chain gates | Secret scan, exports check, reproducible builds |

## What you give up

- Interactive local publishing mode.
- GitLab support (anvil is GitHub Actions only).
- Plugin architecture for custom release steps.
- If you publish from your laptop regularly, anvil is not the
  right replacement. Consider `np` or stay on release-it.
