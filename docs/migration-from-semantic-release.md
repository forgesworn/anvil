# Migrating from semantic-release

This is the recipe distilled from `nsec-tree`, the first consumer. If you
are moving a TypeScript library off `semantic-release` and onto
`forgesworn/release-action`, this is roughly the diff to make. It is
deliberately short. The action is small and so is the migration.

## Before you start

You need:

- A library that already publishes to npm.
- A CHANGELOG that humans update (or willingness to start), **unless** you
  use `auto` mode which generates changelog entries from conventional commits.
  See the README's "Version strategy" section.
- Commit rights to the repo and publish rights to the package on npmjs.com.

Read [the README's "Trusted publisher caveat" section](../README.md#trusted-publisher-caveat-important)
first. If you skip that, you will burn an hour diagnosing an error message
that does not mean what it says. It is the single most non-obvious thing
about this pattern.

## The diff

Six concrete changes. In order.

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
    with:
      vector-test-command: npm run test:vectors
```

Drop the `vector-test-command` line if your library has no frozen test
vectors. Libraries with deterministic test suites (crypto, codecs,
serialisation) should almost always set it.

### 2. Remove the old release job from `ci.yml`

If your `ci.yml` currently runs `semantic-release` as a final job, strip
that job entirely. Keep the test matrix. CI runs tests; the release
workflow runs on GitHub Release publish and handles publishing.

### 3. Delete `.releaserc.json`

`git rm .releaserc.json`. Nothing replaces it. Configuration lives in the
caller workflow now.

### 4. Clean up `package.json`

Remove the `semantic-release` devDependencies:

```diff
   "devDependencies": {
-    "@semantic-release/changelog": "^6.0.3",
-    "@semantic-release/git": "^10.0.1",
-    "@semantic-release/github": "^12.0.6",
-    "@semantic-release/npm": "^13.1.5",
-    "semantic-release": "^25.0.3",
```

Remove any `overrides` you added to silence bundled-npm Dependabot noise.
They are no longer needed because there is no bundled `npm` CLI to make
noise:

```diff
-  "overrides": {
-    "brace-expansion": "^5.0.5",
-    "picomatch": "^4.0.4"
-  },
```

Make sure `publishConfig.provenance` is set:

```json
"publishConfig": {
  "provenance": true
}
```

Do **not** pass `--provenance` on any `npm publish` command line, and do
**not** set `NPM_CONFIG_PROVENANCE`. npm 11.6+ can short-circuit to
`ENEEDAUTH` when provenance is flagged explicitly, which breaks the OIDC
trusted-publishing exchange before it starts. The `publishConfig` field
drives provenance implicitly, which is what you want.

Add the frozen-vector test script if you have vectors:

```diff
   "scripts": {
     "test": "vitest run",
+    "test:vectors": "vitest run test/vectors.test.ts",
```

Point it at whatever subset of your test suite exercises the frozen
vectors. The action fails the publish if this command exits non-zero.

### 5. Run `npm install`

Regenerates `package-lock.json` without the `semantic-release` tree.
Expect the lockfile to shrink substantially. `nsec-tree`'s shrank from
7993 lines to 1795 lines (78%) on this step alone.

### 6. Configure the npm trusted publisher for your package

On `npmjs.com`, go to your package's Settings → Trusted Publishers and
add GitHub Actions:

| Field | Value |
|---|---|
| Publisher | GitHub Actions |
| Organization or user | your org or user |
| Repository | **your package's repo** (not `forgesworn/release-action`) |
| Workflow filename | `release.yml` (your caller workflow) |
| Environment | *(empty)* |

The Repository and Workflow filename fields must match the caller, not
the reusable workflow. npm matches against the OIDC token's
`workflow_ref` claim, not `job_workflow_ref`. This is counterintuitive
and it is in the README for a reason.

## First release

Once the diff is merged:

1. Manually bump `package.json` version (`1.4.4 → 1.5.0` or whatever
   fits). `release-action` refuses to publish if the git tag and
   `package.json` version disagree.
2. Add a CHANGELOG entry under a heading containing the new version
   number. Any of these headings works:
   - `## [1.5.0] - 2026-04-11`
   - `# 1.5.0`
   - `### 1.5.0 (2026-04-11)`
3. Commit, push, tag (`git tag v1.5.0 && git push --tags`).
4. Create a GitHub Release pointing at the tag. The Release body can be
   empty or a short placeholder. The action replaces it with the
   CHANGELOG section on publish.
5. Watch the `release` workflow run. It should turn green and your
   package should appear on npm with provenance attached.

That is the whole loop. Bump, CHANGELOG, tag, Release, done.

## If it fails

**`OIDC token exchange error - package not found`**: your trusted
publisher is configured for the wrong repo. See step 6. This is the most
common failure mode and the error message is actively misleading.

**`ENEEDAUTH`**: someone set `--provenance` or `NPM_CONFIG_PROVENANCE`
somewhere. Grep for it and remove it. Use `publishConfig.provenance: true`
in `package.json` instead.

**Still stuck**: add `debug: true` to your caller workflow's `with:`
block and re-run. A diagnostic step will dump npm version, the redacted
effective `.npmrc`, OIDC env var presence, and `npm config list` into
the log. That is usually enough to tell whether npm has the OIDC
context at all or has it but cannot match the trusted publisher.

## What you get

- Zero release-tooling devDependencies in the consumer repo.
- Dramatically smaller `package-lock.json`.
- No more bundled-npm Dependabot noise (handlebars, lodash, picomatch,
  brace-expansion, etc.).
- OIDC trusted publishing with SLSA provenance on every publish.
- Hard pre-publish gates: tag-match, secret scan, exports sanity,
  frozen-vector check, runtime-only `npm audit`.
- A five-line caller workflow and a CHANGELOG you control.

## What you give up

- The psychological reassurance of a release tool with 597 transitive
  dependencies.

That is genuinely it. If you liked the automatic versioning from
commit messages, use `auto` mode -- add the companion
`auto-release.yml` workflow alongside `release.yml` and you get the
same behaviour with zero dependencies. If you want manual control
with a safety net, use `version-strategy: verify` -- the action
parses your conventional commits and fails if your bump is smaller
than what the commits imply. See the README's "Version strategy"
section for setup.
