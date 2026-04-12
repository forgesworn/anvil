# Pre-publish gates

Every gate runs automatically as part of the `build-a` job. No opt-in
is required unless noted. If any gate fails, the release is blocked and
nothing is published.

## Exports-map check (verify-exports.sh)

Catches the "I deleted src/foo.ts but forgot to update exports" class of
bug before it ships a broken import to downstream consumers. Neither
[`publint`](https://publint.dev/rules) (which explicitly skips this
check) nor `arethetypeswrong` (which does type resolution, not file
presence) perform this file-existence validation.

### What it validates

**Modern exports field:** Uses `jq` to walk the entire `.exports` tree
in `package.json`, including all conditional keys (`import`, `require`,
`types`, `node`, `browser`, `default`), nested conditionals, and string
shorthand. Every leaf string starting with `./` is treated as a file
path that must exist on disk.

**Legacy entry points:** Also checks top-level `main`, `module`,
`types`, `typings`, and `bin` (both string and object forms). These are
the pre-exports world but still shipped to consumers. Paths without a
`./` prefix are normalised automatically.

Duplicate paths (e.g. when a `default` conditional repeats an `import`
target) are deduplicated so each file is checked exactly once.

### Configuration

No configuration required. The check runs automatically as part of the
build-a job. The only relevant input is `package-json` (defaults to
`package.json`) which controls the path to the manifest file.

There is no way to skip or disable this gate -- it is always on. If your
`package.json` declares exports, every path must exist after `npm run
build`. If no exports or legacy entry points are declared, the check
warns and passes.

### How the gate enforces

- If any exported path does not exist on disk, the step exits with
  status 1 and the release is blocked.
- Output on failure: `warning: missing: ./dist/missing.js` for each
  missing path, then `error: N exports targets missing on disk --
  refusing to publish`.
- Output on success: `ok  ./dist/index.js` for each verified path,
  then `ok: all N export targets exist`.
- If no exports or legacy entry points are declared at all, the check
  warns `no exports or legacy entry points declared -- nothing to
  verify` and passes (exit 0).

### Example

Given this `package.json`:

```json
{
  "exports": {
    ".": {
      "import": "./dist/index.mjs",
      "require": "./dist/index.cjs",
      "types": "./dist/index.d.ts"
    },
    "./utils": {
      "import": "./dist/utils.mjs",
      "require": "./dist/utils.cjs"
    }
  },
  "main": "./dist/index.cjs",
  "types": "./dist/index.d.ts"
}
```

All six paths (four from exports, two from legacy `main`/`types`) must
exist after the build step. If `./dist/utils.mjs` is missing, the
release is blocked with:

```
  warning: missing: ./dist/utils.mjs
  error: 1 exports targets missing on disk -- refusing to publish
```

---

## Runtime-only npm audit (verify-audit.sh)

Runs `npm audit --omit=dev` so that devDependency advisories do not
block releases, but any advisory in the runtime dependency tree does.
This is the opposite of tools like `semantic-release`, which audit
everything and drown you in devDep noise that has zero impact on
consumers of your published package.

### How it works

The script runs a single command:

```sh
npm audit --omit=dev --audit-level=$level
```

The `--omit=dev` flag tells npm to evaluate only production dependencies
(those listed in `dependencies`, not `devDependencies`). If npm finds
any advisory at or above the configured severity level, it exits
non-zero and the release is blocked.

### Configuration

The `audit-level` input (default: `low`) controls the severity
threshold. Valid values: `low`, `moderate`, `high`, `critical`.

```yaml
uses: forgesworn/anvil/.github/workflows/release.yml@v0
with:
  audit-level: moderate   # only block on moderate or above
```

For security-sensitive libraries (cryptography, authentication,
payments), the default of `low` is intentional: even low-severity
runtime advisories are worth investigating before publishing.

### What it checks and what it ignores

- **Checked**: all packages in `dependencies` -- the runtime tree that
  ships to consumers when they `npm install` your package
- **Ignored**: all packages in `devDependencies` -- build tools, test
  frameworks, linters. These never reach consumers.

No additional `package.json` configuration is required. The gate runs
automatically in the build-a job.

### Output

- On success: `ok: no runtime advisories at or above $level`
- On failure: `error: runtime audit found advisories -- refusing to
  publish` plus the full `npm audit` advisory output

---

## Tarball hash stamping (record-tarball.sh + update-release.sh)

After all pre-publish gates pass and the package is published to npm,
anvil stamps the registry tarball's cryptographic hashes into the GitHub
Release body and uploads the tarball as a release asset. This gives
consumers two independent sources for the bytes (npm registry + GitHub
Releases) and a way to verify they match.

### How it works

**Step 1 -- record-tarball.sh** (runs in the build job, before publish):

1. Derives `SOURCE_DATE_EPOCH` from the git commit timestamp of HEAD
2. Normalises all file mtimes to that epoch (for reproducibility)
3. Runs `npm pack --json` to produce the canonical `.tgz` tarball
4. Computes sha256 via `shasum -a 256`
5. Extracts the npm integrity value (sha512) from `npm pack --json`
6. Writes all metadata to `tarball.meta` as key=value lines:
   `filename`, `path`, `size`, `unpacked_size`, `sha256`, `integrity`

**Step 2 -- update-release.sh** (runs in the publish job, after npm
publish succeeds):

1. Extracts the CHANGELOG section for the released version
2. Reads `tarball.meta` and appends an "Artefact integrity" block to
   the GitHub Release body:

```
---

## Artefact integrity

file:      my-package-1.2.0.tgz
size:      12345 bytes
sha256:    abc123...
sha512-base64...

Verify against the registry tarball:

curl -sLO https://registry.npmjs.org/my-package/-/my-package-1.2.0.tgz
shasum -a 256 my-package-1.2.0.tgz
```

3. If the reproducible-build gate confirmed two independent builds
   matched, a **Reproducible build** badge is prepended above the block
4. Uploads the `.tgz` tarball as a GitHub Release asset via
   `gh release upload`

### Configuration

No configuration required. The stamping runs automatically whenever the
publish job succeeds.

### What consumers can verify

Download the tarball from the npm registry and compare its sha256
against the value stamped in the GitHub Release body. If the hashes
match, the bytes on npm are the same bytes CI built. If the
"Reproducible build" badge is present, those bytes were also confirmed
identical across two independent CI runners.

On a clean re-run of an already-published release, `publish-npm`
fetches the registry's `dist.integrity` and compares it to the recorded
value. Match: silent skip. Mismatch: loud failure (registry tarball
substitution alarm).

---

## Action-pin auditing (verify-action-pins.sh)

Walks `.github/workflows/*.yml` in the consumer's repository and flags
every `uses: owner/repo@ref` reference whose ref is not a 40-character
hex SHA. This catches the supply-chain risk where a tag-pinned action
(`@v4`) can be silently re-pointed at malicious code -- the same vector
that hit [`tj-actions/changed-files` in March 2025](https://github.com/tj-actions/changed-files/issues/2464).

### How it works

For each workflow YAML file, the script extracts every `uses:` line and
checks whether the `@ref` portion is a full 40-character commit SHA.
References that use tags (`@v4`), branches (`@main`), or short SHAs are
flagged as unpinned.

Special cases:

- **Local actions** (`./` paths): skipped (resolved from the same repo
  checkout, no external fetch)
- **forgesworn/anvil**: self-exempt by name. Without this carve-out,
  every consumer's release would fail on the line that loads the gate
  (`uses: forgesworn/anvil@v0`). Consumers who want SHA-pinning of
  anvil itself should pin with a 40-char SHA in their caller workflow.
- **Docker references** (`docker://`): checks for `sha256:` digest
  pinning instead of commit SHA

### Configuration

The `strict-action-pins` input (default: `true`) controls whether
unpinned references block the release or only warn:

```yaml
uses: forgesworn/anvil/.github/workflows/release.yml@v0
with:
  strict-action-pins: true    # fail on unpinned refs (default)
```

```yaml
with:
  strict-action-pins: false   # warn only, do not block release
```

Set to `false` during initial adoption, then promote to `true` once
all your workflow references are SHA-pinned.

### Output

- Per unpinned ref: `warning: unpinned action: .github/workflows/ci.yml:12  actions/setup-node@v4`
- In strict mode (default): `error: N unpinned action reference(s) found
  (strict-action-pins enabled)` and exit 1 -- release blocked
- In warn mode: logs the count and suggests SHA pins, exits 0

---

## Secret scan (verify-secrets.sh)

Scans the npm pack set (the files that would be included in the
published tarball) for accidentally committed secrets. Checks both
filenames (`.env`, `credentials.json`, `id_rsa`, etc.) and content
patterns (AWS keys, npm tokens, private keys).

This gate runs automatically. No configuration required.

---

## Frozen-vector gate (verify-vectors.sh)

An optional gate for libraries with deterministic test vectors
(cryptographic libraries, hash implementations, codec libraries). Runs
a separate test command that exercises known-answer tests against frozen
reference values.

### Configuration

Pass the `vector-test-command` input:

```yaml
uses: forgesworn/anvil/.github/workflows/release.yml@v0
with:
  vector-test-command: npm run test:vectors
```

If `vector-test-command` is empty (the default), this gate is skipped.
If set, the command must exit 0 or the release is blocked.
