# Migrating from changesets

If you are moving a single-package TypeScript library off `@changesets/cli`
and onto `forgesworn/release-action`, this is the diff. Monorepo users:
release-action does not support monorepos in v0.x. Stay on changesets
until it does, or split your packages into separate repos.

## Before you start

You need:

- A single-package library that already publishes to npm.
- Commit rights to the repo and publish rights to the package on npmjs.com.

Read [the README's "Trusted publisher caveat" section](../README.md#trusted-publisher-caveat-important)
first. npm's trusted publisher matches the **caller** workflow, not the
reusable workflow. Get this wrong and you will burn an hour.

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
    uses: forgesworn/release-action/.github/workflows/release.yml@v0
```

If you want automatic versioning from conventional commits (closest to
the changesets experience), also add `.github/workflows/auto-release.yml`:

```yaml
name: auto-release

on:
  push:
    branches: [main]

permissions:
  contents: write

jobs:
  auto-release:
    uses: forgesworn/release-action/.github/workflows/auto-release.yml@v0
```

### 2. Remove the changesets release workflow

If your CI currently runs `changeset publish` or uses the
`changesets/action` GitHub Action, remove that workflow entirely.

### 3. Delete changeset configuration

```sh
git rm -r .changeset/
```

This removes the config file and any pending changeset markdown files.

### 4. Clean up package.json

Remove changesets devDependencies:

```diff
  "devDependencies": {
-   "@changesets/cli": "^2.30.0",
-   "@changesets/changelog-github": "^0.5.0",
```

Remove any changeset-related scripts:

```diff
  "scripts": {
-   "changeset": "changeset",
-   "release": "changeset publish",
-   "version": "changeset version",
```

Make sure `publishConfig.provenance` is set:

```json
"publishConfig": {
  "provenance": true
}
```

### 5. Run `npm install`

Regenerates `package-lock.json` without the changesets tree.

### 6. Configure the npm trusted publisher

On `npmjs.com`, go to your package's Settings -> Trusted Publishers and
add GitHub Actions:

| Field | Value |
|---|---|
| Publisher | GitHub Actions |
| Organization or user | your org or user |
| Repository | **your package's repo** (not `forgesworn/release-action`) |
| Workflow filename | `release.yml` (your caller workflow) |
| Environment | *(empty)* |

## First release

1. Bump `package.json` version.
2. Add a CHANGELOG entry under a heading containing the version number.
3. Commit, push, tag (`git tag v1.2.0 && git push --tags`).
4. Create a GitHub Release pointing at the tag.
5. Watch the workflow turn green.

If you set up `auto-release.yml`, skip steps 1-4: just push conventional
commits to `main` and the workflow handles the rest.

## What changes

| Before (changesets) | After (release-action) |
|---|---|
| `npx changeset` to describe changes | Write CHANGELOG directly (or use auto mode) |
| `.changeset/*.md` files in PRs | No extra files |
| `changeset version` to bump | Manual bump (or auto mode) |
| `changeset publish` to release | GitHub Release triggers pipeline |
| ~300 transitive deps | Zero release-tool deps |
| No OIDC, no provenance | OIDC + SLSA provenance on every publish |
| No supply-chain gates | Secret scan, exports check, reproducible builds |

## What you give up

- Native monorepo support with dependency graph awareness.
- The changeset-per-PR workflow that decouples versioning from commits.
- If you relied on changesets for monorepo inter-package versioning,
  there is no replacement in release-action today.
