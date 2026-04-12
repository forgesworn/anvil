# Migrating from v0.3 to v0.4

v0.4 adds a multi-runner reproducible-build attestation as the
flagship feature. The reusable workflow now runs **two parallel
builds** on independent runners, packs them with normalised mtimes
and `SOURCE_DATE_EPOCH` derived from `git log`, and refuses to publish
if the two tarballs aren't byte-identical.

For libraries whose build is already deterministic this is a free
upgrade — bump the pin and you get a stronger release-time guarantee
without changing anything else. For libraries with subtly
non-deterministic builds it can fail the first release on v0.4 until
the build is fixed.

This document covers the safe upgrade path.

## TL;DR

Bump the pin in your caller workflow:

```yaml
jobs:
  release:
    uses: forgesworn/anvil/.github/workflows/release.yml@v0.4.0
```

If your library's build is already reproducible (most modern bundlers
are by default), nothing else changes — your release body just gains
a "Reproducible build" line and the comparison passes silently.

If you don't trust this without testing, use the warn middle path
below for a release or two.

## The safer middle path: `reproducibility-mode: warn`

Add the input to your caller workflow's `with:` block:

```yaml
jobs:
  release:
    uses: forgesworn/anvil/.github/workflows/release.yml@v0.4.0
    with:
      vector-test-command: npm run test:vectors
      reproducibility-mode: warn
```

Under `warn`, the reproduce job still runs, the diff still gets
printed on a mismatch, but the publish proceeds anyway. After a
release or two of green reproduce-job runs, remove the input to take
the default `strict`.

If you genuinely cannot make a library reproducible, set
`reproducibility-mode: off`. That falls back to v0.3 single-runner
behaviour and skips the second build entirely. **Use this as a last
resort** — non-reproducibility in a published library is a code smell,
not a configuration choice.

## Common causes of reproduce-job failures

The compare step prints a `diff` of the two tar listings on mismatch,
which usually points at the offending file. Common patterns:

### `Date.now()` or `__BUILD_TIMESTAMP__` in the bundle

Find:

```sh
grep -rn 'Date\.now\|__BUILD_TIMESTAMP__\|__BUILD_DATE__' src/
```

Replace runtime-evaluated timestamps with values derived from
`SOURCE_DATE_EPOCH` (read it in the build script via
`process.env.SOURCE_DATE_EPOCH`).

### Sorted-by-filesystem-order globs

If you have a build step that does `glob.sync('src/**/*.ts')` and
relies on the order, the order will differ between runners. Sort
explicitly:

```js
const files = glob.sync('src/**/*.ts').sort();
```

### Bundler config injecting host paths into source maps

`esbuild`, `rollup`, and `webpack` all default to absolute paths in
source maps unless you tell them otherwise. For `esbuild`:

```js
{
  sourcemap: true,
  sourceRoot: '.',
  // OR set `sources` to be relative
}
```

For `rollup`:

```js
output: {
  sourcemap: true,
  sourcemapPathTransform: (relativePath) => relativePath,
}
```

### Random IDs / UUIDs / salts in build scripts

Anything that calls `crypto.randomBytes()`, `Math.random()`, or
`crypto.randomUUID()` at build time produces a different bundle each
run. Either seed it deterministically (often from
`SOURCE_DATE_EPOCH`) or remove the call.

### Embedded git short-SHA

If your build embeds the git short SHA into the bundle for a build
banner, that's deterministic per commit and won't actually break
reproducibility — the *same* commit produces the *same* SHA. Confirm
you're embedding it from `git rev-parse HEAD`, not from a tool that
adds anything else (timestamp, dirty flag, etc.).

## Investigating a mismatch locally

The reproduce job uploads both tarball artifacts on failure. Download
them and run:

```sh
diff <(tar -tvf tarball-A.tgz) <(tar -tvf tarball-B.tgz)
```

This shows file-level differences (mtime, size, ownership). For
content differences inside a specific file:

```sh
mkdir A B
tar -xf tarball-A.tgz -C A
tar -xf tarball-B.tgz -C B
diff -r A B
```

If your build differs by minified output ordering, run an unminified
build of both and diff that — minifier output is often
non-deterministic where the source it's minifying is fine.

## What's new beyond reproducibility

v0.4 also:

- **Uploads the canonical tarball as a GitHub Release asset.** You
  now have two independent sources for the bytes (npm registry +
  GitHub Releases) and can hash-compare against either.
- **Adds a "Reproducible build" badge line** to the release body
  when the reproduce gate matches. Cosmetic, but makes the property
  visible without reading the integrity block.
- **Emits the reproducibility result as a job output** (`reproducible:
  '1'` or `'0'`) so consumers wiring this workflow into a larger
  pipeline can react programmatically.

## What's *not* changing

- **Composite action (`uses: forgesworn/anvil@v0.4.0`)
  remains v0.3-equivalent.** It still runs all gates, still records
  the tarball, still updates the release body with the integrity
  block — but it does **not** run the reproduce gate, because
  composite actions cannot define multi-job DAGs. The composite
  remains as a power-user escape hatch only. Its `description` field
  spells this out.
- **Inputs from v0.3 are unchanged.** Existing `with:` blocks
  continue to work without modification.
- **Trusted publisher configuration is unchanged.** The OIDC
  trusted-publisher record on npmjs.com still points at your repo
  and your caller workflow file, not at `forgesworn/anvil`.
- **The integrity block on the GitHub Release body is unchanged in
  shape.** It just gains the "Reproducible build" header line above
  it when the reproduce gate matched.
