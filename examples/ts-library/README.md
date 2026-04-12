# TypeScript library example

The canonical worked example of this action is
[`forgesworn/nsec-tree`](https://github.com/forgesworn/nsec-tree), the
first validated consumer of `forgesworn/anvil`. It was
migrated from `semantic-release` in the nsec-tree@1.5.0 release and
has been publishing successfully through this action since.

If you are looking for "what does a real consumer repo look like",
read nsec-tree's `.github/workflows/release.yml`, its `package.json`,
and the 1.5.0 CHANGELOG entry. The pattern is boring on purpose.

## Caller workflow

`.github/workflows/release.yml`:

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
    with:
      vector-test-command: npm run test:vectors
```

Five lines of actual configuration. Drop `vector-test-command` if your
library has no frozen test vectors.

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

1. Go to your package's Settings → Trusted Publisher.
2. Add a GitHub Actions publisher with:
   - **Repository**: your package's repo (not `forgesworn/anvil`)
   - **Workflow filename**: `release.yml` (your caller workflow,
     not the reusable one)
   - **Environment**: leave empty

npm matches against the OIDC token's `workflow_ref` claim (the caller),
not `job_workflow_ref` (the reusable workflow). This is the single most
non-obvious thing about the pattern and the most common failure mode
the first time through. See the root README's
[Trusted publisher caveat](../../README.md#trusted-publisher-caveat-important)
section for the full story.

## The release loop

1. Bump `package.json` version manually.
2. Add a CHANGELOG entry under a heading containing the new version.
3. Commit, tag (`git tag v1.5.0`), push (`git push && git push --tags`).
4. Create a GitHub Release pointing at the tag (placeholder body is fine,
   the action replaces it).
5. Watch the `release` workflow. Green = published with provenance.

## Further reading

- [Root README](../../README.md) — full input reference and trusted publisher caveat
- [THREAT-MODEL.md](../../THREAT-MODEL.md) — security contract and known limitations
- [Migration guide from semantic-release](../../docs/migration-from-semantic-release.md) — six-step recipe distilled from the nsec-tree pilot
- [nsec-tree on GitHub](https://github.com/forgesworn/nsec-tree) — the worked example
- [nsec-tree on npm](https://www.npmjs.com/package/nsec-tree) — what a successful publish looks like, provenance attached
