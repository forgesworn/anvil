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

## SLSA provenance (publish-npm.sh)

Every package published through anvil carries SLSA provenance
attestations, proving the build originated from a specific GitHub
Actions workflow run on a specific commit. This is powered by npm's
built-in Sigstore integration and GitHub's OIDC identity provider.

### How provenance works

1. The caller workflow declares `permissions: id-token: write`, which
   allows GitHub Actions to mint an OIDC token for the run.
2. `actions/setup-node` configures the npm registry URL, enabling npm's
   OIDC-aware publish flow.
3. `publish-npm.sh` runs `npm publish --access public $tarball_path`.
   npm detects the OIDC environment, exchanges the GitHub OIDC token
   for a short-lived Sigstore signing certificate, signs the package,
   and attaches the provenance attestation to the registry entry.
4. The registry records the attestation, linking the published bytes
   to the GitHub Actions workflow run, commit SHA, and repository.

### Configuration

Two things are required in your library:

**1. package.json** -- set `publishConfig.provenance`:

```json
{
  "publishConfig": {
    "provenance": true
  }
}
```

**Important**: do NOT pass `--provenance` as a CLI flag. npm 11.6+
short-circuits to `ENEEDAUTH` when `--provenance` is passed explicitly,
breaking the OIDC token exchange entirely. Use `publishConfig` instead.

**2. Caller workflow** -- ensure OIDC permissions:

```yaml
permissions:
  contents: write   # update Release bodies + upload tarball asset
  id-token: write   # OIDC trusted publishing + provenance signing
```

The reusable workflow (`forgesworn/anvil/.github/workflows/release.yml`)
bakes these permissions in. If using the composite action directly, you
must set them yourself.

### Verifying provenance as a consumer

**On npmjs.com**: navigate to the package page. Packages with provenance
show a green "Provenance" badge linking to the source commit and
workflow run.

**Via the CLI**:

```sh
npm audit signatures
```

This checks that every package in your `node_modules` has a valid
registry signature and, where present, a valid provenance attestation.

**Via the npm registry API**:

```sh
# Fetch attestations for a specific version
curl -s https://registry.npmjs.org/-/npm/v1/attestations/my-package@1.2.0 | jq .
```

The response includes the Sigstore bundle with the signing certificate,
transparency log entry, and the SLSA predicate linking the package to
its source.

### Troubleshooting

**`OIDC token exchange error - package not found`**: the trusted
publisher on npmjs.com is configured for the wrong repository. It must
point at YOUR repo and YOUR caller workflow, not at forgesworn/anvil.

**`ENEEDAUTH` or `npm ERR! need auth`**: likely caused by passing
`--provenance` as a CLI flag with npm >= 11.6. Remove the flag and use
`publishConfig.provenance: true` in package.json instead.

**No provenance badge on npmjs.com**: check that `publishConfig.provenance`
is set to `true` in package.json (not just truthy). Also verify that
`id-token: write` is in the caller workflow's permissions.

**`npm audit signatures` reports unsigned packages**: provenance only
applies to packages published with OIDC. Older versions published with
a long-lived `NPM_TOKEN` will not have attestations. Only versions
published through anvil (or any OIDC-enabled flow) carry provenance.

Add `debug: true` to your caller workflow's `with:` block to dump npm
version, redacted `.npmrc`, OIDC environment variable presence, and
`npm config list`.

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

Core implementation:

```bash
# Derive SOURCE_DATE_EPOCH from git commit time
SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
export SOURCE_DATE_EPOCH

# Normalise all file mtimes for reproducibility
find . -exec touch -t "$(date -d "@$SOURCE_DATE_EPOCH" '+%Y%m%d%H%M.%S')" {} +

# Pack and extract metadata
pack_json="$(npm pack --pack-destination "$meta_dir" --json)"
filename="$(printf '%s' "$pack_json" | jq -r '.[0].filename')"
integrity="$(printf '%s' "$pack_json" | jq -r '.[0].integrity')"
size="$(printf '%s' "$pack_json" | jq -r '.[0].size')"

# Compute sha256
sha256="$(shasum -a 256 "$meta_dir/$filename" | awk '{print $1}')"

# Write tarball.meta (consumed by update-release.sh and compare-tarball-meta.sh)
printf 'filename=%s\nsize=%s\nsha256=%s\nintegrity=%s\n' \
  "$filename" "$size" "$sha256" "$integrity" > "$meta_dir/tarball.meta"
```

**Step 2 -- update-release.sh** (runs in the publish job, after npm
publish succeeds):

1. Extracts the CHANGELOG section for the released version via
   `changelog-extract.sh`
2. Reads `tarball.meta` and appends an "Artefact integrity" block to
   the GitHub Release body
3. If the reproducible-build gate confirmed two independent builds
   matched (`REPRODUCIBLE=1`), prepends a **Reproducible build** badge
4. Uploads the `.tgz` tarball as a GitHub Release asset

Core implementation:

```bash
# Read metadata from tarball.meta
while IFS='=' read -r key value; do
  case "$key" in
    filename)  filename="$value" ;;
    size)      size="$value" ;;
    sha256)    sha256="$value" ;;
    integrity) integrity="$value" ;;
  esac
done < "$meta_dir/tarball.meta"

# Build the integrity block appended to the release body
integrity_block="
---

## Artefact integrity

\`\`\`
file:      ${filename}
size:      ${size} bytes
sha256:    ${sha256}
${integrity}
\`\`\`

Verify against the registry tarball:

\`\`\`sh
curl -sLO https://registry.npmjs.org/${name}/-/${basename}-${version}.tgz
shasum -a 256 ${basename}-${version}.tgz
\`\`\`
"

# Update the GitHub Release body (changelog notes + integrity block)
gh release edit "$tag" --notes "${notes}${integrity_block}"

# Upload the canonical tarball as a release asset
gh release upload "$tag" "$tarball_path" --clobber
```

### Output in the GitHub Release body

The final release body contains three parts:

1. The CHANGELOG section for this version (extracted from CHANGELOG.md)
2. If reproducible: `**Reproducible build**: byte-identical output
   verified across two independent CI runners.`
3. The artefact integrity block with filename, size, sha256, sha512,
   and a curl + shasum verification recipe

### Configuration

No configuration required. The stamping runs automatically whenever the
publish job succeeds.

### What consumers can verify

Download the tarball from the npm registry and compare its sha256
against the value stamped in the GitHub Release body:

```sh
curl -sLO https://registry.npmjs.org/my-package/-/my-package-1.2.0.tgz
shasum -a 256 my-package-1.2.0.tgz
# Compare output with sha256 in the GitHub Release "Artefact integrity" block
```

If the hashes match, the bytes on npm are the same bytes CI built. If
the "Reproducible build" badge is present, those bytes were also
confirmed identical across two independent CI runners.

The tarball is also uploaded as a GitHub Release asset, giving consumers
a second independent source. Compare both:

```sh
# From npm registry
npm_sha=$(curl -sL https://registry.npmjs.org/my-package/-/my-package-1.2.0.tgz | shasum -a 256 | cut -d' ' -f1)
# From GitHub Releases
gh_sha=$(curl -sL https://github.com/owner/repo/releases/download/v1.2.0/my-package-1.2.0.tgz | shasum -a 256 | cut -d' ' -f1)
[[ "$npm_sha" == "$gh_sha" ]] && echo "Match" || echo "MISMATCH"
```

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
