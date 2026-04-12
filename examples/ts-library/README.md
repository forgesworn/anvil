# TypeScript library example

A worked example of how to set up `forgesworn/anvil` for a TypeScript
library that publishes to npm.

## Caller workflows

You always need **`release.yml`** — it runs the gates and publishes.
Add **`auto-release.yml`** alongside if you want conventional-commit
driven releases from `main`.

### `release.yml` (required for both manual and auto modes)

```yaml
name: release
on:
  release:
    types: [published]       # manual flow
  workflow_dispatch:         # auto flow dispatches here
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
      vector-test-command: npm run test:vectors
```

Drop `vector-test-command` if your library has no frozen test vectors.

### `auto-release.yml` (optional — enables the auto mode)

```yaml
name: auto-release
on:
  push:
    branches: [main]

permissions:
  contents: write
  actions: write            # required to dispatch release.yml

jobs:
  auto-release:
    uses: forgesworn/anvil/.github/workflows/auto-release.yml@v0
```

No release-time inputs here — those live on `release.yml` because
`auto-release.yml` fires `release.yml` via `workflow_dispatch`, which
makes `release.yml` the OIDC entry-point for npm trusted publishing.

See [`../../docs/design/chained-workflows.md`](../../docs/design/chained-workflows.md)
for why this is a two-file setup rather than one.

## `package.json` essentials

```json
{
  "name": "my-library",
  "version": "1.0.0",
  "files": [
    "dist",
    "src",
    "README.md",
    "CHANGELOG.md",
    "LICENCE"
  ],
  "publishConfig": {
    "provenance": true
  },
  "scripts": {
    "build": "tsc",
    "test": "vitest run",
    "test:vectors": "vitest run test/vectors.test.ts"
  }
}
```

Three things are load-bearing:

1. **`files` is explicit.** The secret scan enumerates its scan roots
   from this array plus a hardcoded `dist/`. Declaring `files`
   explicitly gives the scan a predictable surface and is best practice
   for published npm packages anyway. See
   [`../../THREAT-MODEL.md`](../../THREAT-MODEL.md) "Known limitations"
   for the details of this gap.
2. **`publishConfig.provenance: true`** drives SLSA provenance signing
   implicitly. Do **not** pass `--provenance` on any `npm publish`
   command line and do **not** set `NPM_CONFIG_PROVENANCE=true` in
   your workflow env. npm 11.6+ can short-circuit to `ENEEDAUTH` when
   provenance is flagged explicitly.
3. **`test:vectors` is a separate script** so the frozen-vector gate
   can run independently of the full test suite. If your tests are
   already split by directory (`test/vectors.test.ts`,
   `test/unit/*.test.ts`, etc.) this is one line.

## Before your first release

One-off setup on `npmjs.com`:

1. Go to your package's Settings -> Trusted Publisher.
2. Add a GitHub Actions publisher with:
   - **Repository**: your package's repo (not `forgesworn/anvil`)
   - **Workflow filename**: `release.yml` — the same file for both
     manual and auto flows, because `auto-release.yml` dispatches
     `release.yml` as the OIDC entry-point. **Not** the reusable
     workflow inside `forgesworn/anvil`.
   - **Environment**: leave empty

npm matches against the OIDC token's `workflow_ref` claim (the caller),
not `job_workflow_ref` (the reusable workflow). This is the single most
non-obvious thing about the pattern and the most common failure mode
the first time through. See the root README's
[Trusted publisher caveat](../../README.md#trusted-publisher-caveat-important)
section for the full story.

## The release loop

### Manual pattern

1. Bump `package.json` version manually.
2. Add a CHANGELOG entry under a heading containing the new version.
3. Commit, tag (`git tag v1.5.0`), push (`git push && git push --tags`).
4. Create a GitHub Release pointing at the tag (placeholder body is fine,
   the action replaces it).
5. Watch the `release` workflow. Green = published with provenance.

### Auto pattern

1. Write commits with conventional prefixes on main:
   - `feat: ...` → minor bump
   - `fix: ...` → patch bump
   - `feat!: ...` or `BREAKING CHANGE:` in body → major bump
2. Push to `main`.
3. Watch the `auto-release` workflow: `determine → commit-and-tag →
   publish`. Green = version bumped, tagged, published, Release
   created with the integrity block.
4. That's it. No local commands, no manual tagging.

## Further reading

- [Root README](../../README.md) -- full input reference and trusted publisher caveat
- [THREAT-MODEL.md](../../THREAT-MODEL.md) -- security contract and known limitations
- [Migration guides](../../docs/README.md) -- recipes for semantic-release, changesets, release-please, release-it, np
