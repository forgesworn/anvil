# Migrating from np

If you are moving from `np` (Sindre Sorhus's interactive publish tool)
to `forgesworn/anvil`, you are making a philosophical shift:
publishing moves from your laptop to CI. The safety checks np provides
(clean working tree, correct branch, tests pass) are replaced by harder
gates that run in a controlled environment with OIDC credentials.

## Before you start

You need:

- A library that publishes to npm.
- Willingness to stop running `npm publish` (or `np`) locally.
- Commit rights to the repo and publish rights to the package on npmjs.com.

Read [the README's "Trusted publisher caveat" section](../README.md#trusted-publisher-caveat-important)
first.

## The diff

Four concrete changes.

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

### 2. Remove np

```diff
  "devDependencies": {
-   "np": "^11.0.3",
```

Remove any np config from `package.json`:

```diff
- "np": {
-   "yarn": false,
-   "anyBranch": false
- },
```

### 3. Update package.json

Make sure `publishConfig.provenance` is set:

```json
"publishConfig": {
  "provenance": true
}
```

### 4. Run `npm install`

Regenerates `package-lock.json` without the np tree (~36 direct deps).

### 5. Configure the npm trusted publisher

On `npmjs.com`, go to your package's Settings -> Trusted Publishers and
add GitHub Actions:

| Field | Value |
|---|---|
| Publisher | GitHub Actions |
| Organization or user | your org or user |
| Repository | **your package's repo** (not `forgesworn/anvil`) |
| Workflow filename | `release.yml` (your caller workflow) |
| Environment | *(empty)* |

## New workflow

Your old workflow:

```sh
# locally, on your machine
np
# np asks: version bump? run tests? publish? tag? create release?
```

Your new workflow:

```sh
# locally
vim package.json          # bump version
vim CHANGELOG.md          # write entry
git add -A && git commit -m "chore(release): 1.2.0"
git tag v1.2.0 && git push --tags
# on GitHub: create Release for v1.2.0
# CI takes over: gates, reproducible build, OIDC publish, provenance
```

Or if you want automatic versioning, use the `auto-release.yml`
workflow instead (single file, no separate `release.yml` needed —
it chains internally via `workflow_call`) and just push
conventional commits. See the README's "Version strategy → Auto"
section.

## What changes

| Before (np) | After (anvil) |
|---|---|
| Interactive local CLI | CI-only pipeline |
| Publishes from your machine | Publishes from GitHub Actions with OIDC |
| np's safety checks (clean tree, tests) | Harder gates (secret scan, exports, reproducible builds) |
| Long-lived npm token on your machine | No stored tokens anywhere |
| ~36 direct deps installed locally | Zero release-tool deps |

## What you give up

- The interactive local workflow. No more `np` in your terminal.
- The ability to publish without pushing to GitHub first.
- 2FA prompts at publish time (OIDC replaces this entirely).

## What you gain

- No long-lived npm tokens on any machine (OIDC trusted publishing).
- SLSA provenance on every publish.
- Reproducible-build attestation.
- Secret scanning, exports verification, action-pin auditing.
- Your laptop is no longer a supply-chain attack surface for your
  package's consumers.
