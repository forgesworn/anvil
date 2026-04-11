# forgesworn/release-action

In 2026, most Nostr and Bitcoin JavaScript libraries still publish
with long-lived `NPM_TOKEN` secrets off a maintainer's workstation.
The few that use OIDC use it with no release-time gates beyond
"does the git tag match the `package.json` version". That is
pre-2020 supply-chain hygiene for a category whose entire value
proposition is trust.

This is a release tool for cryptography libraries that fixes that.
It bundles OIDC trusted publishing, SLSA provenance on every publish,
a secret scan scoped to the actual publish pack set, an exports-map
check that verifies every subpath exists on disk
([`publint`](https://publint.dev/rules) explicitly skips this check;
`arethetypeswrong` does type resolution, not file presence), a
consumer-supplied frozen-vector gate, a runtime-only `npm audit` so
devDep noise does not block releases, a warn-by-default audit of
unpinned `uses:` references in the consumer's own workflows, **and a
multi-runner reproducible-build attestation that publishes only when
two independent CI builds produce byte-identical tarballs**.

That last one is the v0.4 flagship. None of `semantic-release`,
`@changesets/cli`, `release-it`, `release-please`, or `np` offers it
today. The hash of the registry tarball is also stamped into the GitHub
Release body and uploaded as a release asset, so consumers have two
independent sources for the bytes (npm registry + GitHub Releases) and
can hash-compare against either.

Pure `bash` + `jq` + `gh` + `npm`. No Node tooling in the action
itself. ~1250 lines of bash across every step script. Auditable in
under thirty minutes — a hard design constraint, not a slogan.

## Why this exists

Two things are true about the JS/TS release tooling landscape in 2026.

**One**: the dominant release tools — `semantic-release`, `changesets` —
bring hundreds of transitive devDependencies with them. For a CRUD app
that is background noise. For a cryptography library whose entire value
proposition is byte-identical output across implementations and time,
it is a supply-chain surface area no crypto library author should
accept.

**Two**: most crypto JS libraries already know this and have responded
by not using release tooling at all. A quick survey of major Nostr
and Bitcoin JS libraries as of 2026-04:

- [`nbd-wtf/nostr-tools`](https://github.com/nbd-wtf/nostr-tools) —
  no release workflow. Manual `npm publish` off a workstation.
- [`bitcoinjs/bitcoinjs-lib`](https://github.com/bitcoinjs/bitcoinjs-lib) —
  CI is test-only. Manual publish.
- [`getAlby/js-sdk`](https://github.com/getAlby/js-sdk) — custom yarn
  workflow with classic `NODE_AUTH_TOKEN`. No OIDC, no provenance.
- `bitcoinerlab/secp256k1` — likely manual; workflows not public.
- [`paulmillr/noble-hashes`](https://github.com/paulmillr/noble-hashes) —
  the only one in the group using OIDC + SLSA provenance, via
  paulmillr's personal [`jsbt`](https://github.com/paulmillr/jsbt)
  reusable workflow. Tag/version match only. No secret scan, no
  exports-sanity check, no frozen-vector gate, no audit.

One of those six uses OIDC trusted publishing. None use a secret
scan. None use an exports-sanity check. None use a frozen-vector
gate. This is what supply-chain hygiene looks like for a category
whose customers are trusting the output to be byte-identical and
the source to be sin-free.

This action takes the `jsbt` pure-bash pattern and adds the gates
crypto libraries actually care about, packaged as one reusable
workflow any JS/TS library can adopt in five lines of caller
workflow. It is deliberately positioned as community infrastructure,
not as personal infra retroactively opened up.

## Quick start (reusable workflow)

Create `.github/workflows/release.yml` in your library:

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

That is the whole caller workflow. Five useful lines of `with:`.

Then:

1. Configure [npm trusted publishing](https://docs.npmjs.com/trusted-publishers)
   on `registry.npmjs.org` for your package. **Point it at YOUR repo and
   YOUR `release.yml`**, not at `forgesworn/release-action`. See the
   "Trusted publisher caveat" section below for why.
2. Bump `package.json` version and add a `CHANGELOG.md` entry.
3. Commit, tag (`v1.2.3`), push, and create a GitHub Release for the
   tag. The workflow takes over from there.

Already using `semantic-release`? See
[`docs/migration-from-semantic-release.md`](docs/migration-from-semantic-release.md)
for the recipe distilled from the first pilot.

## What the action does

The reusable workflow runs as a four-job DAG:

```
   build-a ──────┐
   (full gates +  │
    record)       ├──> reproduce ──> publish
   build-b ──────┘    (compare      (publish-npm,
   (build +           sha256s)       publish-jsr,
    record)                          update-release)
```

In order:

**`build-a`** runs every gate on the consumer-supplied artefact:

1. **Checkout** your repo and this action at the pinned SHA
2. **Setup Node** with OIDC registry configured
3. **verify-action-pins** — scan `.github/workflows/*.yml` for `uses:`
   lines that aren't 40-char SHA pinned. Warn-only by default; promote
   to hard-fail with `strict-action-pins: true`
4. **`npm ci`**
5. **`npm run build --if-present`**
6. **verify-tag** — git tag matches `package.json` version
7. **run-tests** — full test suite (`npm test` by default)
8. **verify-vectors** — your configured frozen-vector command (skipped
   if not set; crypto libraries should set this)
9. **verify-audit** — `npm audit --omit=dev` — runtime deps only
10. **verify-exports** — every subpath in `package.json` `"exports"` exists
    on disk
11. **verify-secrets** — grep `dist/` (and any paths in `"files"`) for
    forbidden filenames and secret markers
12. **record-tarball** — derive `SOURCE_DATE_EPOCH` from `git log`,
    normalise mtimes across the working tree, `npm pack` into a known
    location, parse the `--json` output for filename and sha512
    integrity, hash with sha256, write `tarball.meta` and upload it
    along with the `.tgz` as an artifact

**`build-b`** runs in parallel on a separate runner: checkout, setup,
`npm ci`, build, `record-tarball`, upload. Same `SOURCE_DATE_EPOCH`,
same normalised mtimes, same pack — the resulting tarball must be
byte-identical.

**`reproduce`** downloads both artifacts and runs **compare-tarball-meta**,
which exits 0 if the sha256s match. Under the default
`reproducibility-mode: strict` a mismatch is a hard failure and the
release is blocked. Under `reproducibility-mode: warn` the mismatch
is logged and the publish proceeds. Under `reproducibility-mode: off`
the second build and the comparison are skipped entirely (v0.3
single-runner behaviour).

**`publish`** downloads the canonical tarball from `build-a` and runs:

13. **publish-npm** — idempotent `npm publish --access public` via OIDC,
    publishing the **exact** tarball downloaded above (so the bytes on
    the registry are the bytes the reproduce gate signed off on).
    Provenance is driven by `package.json` `publishConfig.provenance: true`
    rather than a CLI flag (npm 11.6+ short-circuits to `ENEEDAUTH`
    when `--provenance` is passed explicitly). On a clean re-run the
    registry's `dist.integrity` is compared to the recorded integrity:
    match → silent skip, mismatch → loud failure (registry tarball
    substitution alarm).
14. **publish-jsr** — only if `jsr.json` exists in your repo
15. **update-release** — updates the GitHub Release body from the
    matching `CHANGELOG.md` section, appends an *Artefact integrity*
    block containing tarball filename, size, sha256, sha512, and a
    `curl | shasum` recipe consumers can run to verify the registry
    tarball matches; uploads the canonical `.tgz` as a GitHub Release
    asset so consumers have two independent sources for the bytes; and
    if the reproduce job ran and matched, prepends a *"Reproducible
    build"* line above the integrity block.

If any gate fails, the workflow fails and nothing is published.

The composite action (`action.yml`) does **not** include the
reproduce job — composite actions are flat lists of steps inside one
job and cannot define a multi-job DAG. The composite remains as an
escape hatch for power users who need custom job structure; it ships
with a strictly weaker guarantee (single-runner integrity anchor only,
no reproducibility check). Use the reusable workflow as the default.

## Inputs

| Input | Default | Description |
|---|---|---|
| `node-version` | `24.11.0` | Node version used for npm operations (must ship with npm >= 11.5.1 for OIDC trusted publishing) |
| `registry-url` | `https://registry.npmjs.org` | npm registry |
| `test-command` | `npm test` | Full test suite command |
| `vector-test-command` | *(empty)* | Frozen-vector gate command |
| `changelog-file` | `CHANGELOG.md` | Path to CHANGELOG |
| `package-json` | `package.json` | Path to package.json |
| `audit-level` | `low` | `npm audit` severity floor |
| `strict-action-pins` | `false` | If `true`, **verify-action-pins** fails the release on any unpinned `uses:` reference in `.github/workflows`. Default warn-only. `forgesworn/release-action` is exempt by name. |
| `reproducibility-mode` | `strict` | One of `strict`, `warn`, `off`. `strict` blocks the release if the two parallel builds produce different sha256s. `warn` logs the mismatch but publishes. `off` skips the second build entirely (v0.3 single-runner behaviour). |
| `dry-run` | `false` | Skip real publish (for smoke-testing) |
| `debug` | `false` | If `true`, run a diagnostic step before publish that dumps npm version, redacted `.npmrc`, OIDC env vars, and `npm config list`. Flip this on when debugging trusted-publisher errors — see "Trusted publisher caveat". Does not print token values. |

### Secrets

| Secret | When needed |
|---|---|
| `JSR_TOKEN` | Only if `jsr.json` exists. JSR does not yet support OIDC. |

## CHANGELOG format

The extractor is intentionally loose. Your CHANGELOG section is found by
matching the first Markdown heading (H1, H2, or H3) that contains:

- The version string (e.g. `1.4.4`), **and**
- A dotted numeric pattern the extractor recognises as a version heading

Capture continues until the next version heading. Non-version headings
like `### Features` or `### Bug Fixes` are passed through as content.
This means you can freely mix heading levels — `semantic-release`'s
"H1 for minors, H2 for patches" quirk works fine.

If you use [Keep a Changelog](https://keepachangelog.com) format, that
works too. No strict format is enforced.

## Reproducible builds (v0.4 flagship)

The reusable workflow runs **two independent builds in parallel** on
two GitHub Actions runners. Both pack the artefact with normalised
mtimes and `SOURCE_DATE_EPOCH` derived from `git log`. The
`reproduce` job downloads both meta files and compares the sha256s.

Under the default `reproducibility-mode: strict`, a mismatch is a
hard failure: the release is blocked, both hashes are printed, and
the diff between the two tar listings is dumped so the maintainer can
see which file's mtime or content drifted. Common causes are listed
in the failure message — `Date.now()` in build output, sorted-by-fs
globs, random IDs in build scripts, host paths in source maps.

Under `reproducibility-mode: warn` the mismatch is logged and the
release proceeds with `build-A`. Under `off` the second build is
skipped entirely and you fall back to v0.3 single-runner behaviour.

When two builds match, the GitHub Release body gains a top line:

> **Reproducible build**: byte-identical output verified across two
> independent CI runners.

This is a stronger claim than SLSA provenance. Provenance attests
that *some* runner built these bytes *once*. The reproduce gate
attests that **two** independent runners building the same commit
arrive at the *same* bytes — the actual byte-identical-output property
that crypto-library customers care about.

### Single-runner integrity anchor (sub-feature)

Whether reproducibility is on or off, every release body still ends
with an *Artefact integrity* block stamping the canonical tarball's
filename, size, sha256, and npm-format sha512 plus a `curl | shasum`
verify recipe:

> **Artefact integrity**
>
> ```
> file:      noble-hashes-1.4.2.tgz
> size:      87234 bytes
> sha256:    9a5ec1...e7c1
> sha512-...
> ```
>
> Verify against the registry tarball:
>
> ```sh
> curl -sLO https://registry.npmjs.org/noble-hashes/-/noble-hashes-1.4.2.tgz
> shasum -a 256 noble-hashes-1.4.2.tgz
> ```

The same `.tgz` is also uploaded as a GitHub Release asset, so a
consumer can fetch from either npm or GitHub Releases and hash-compare
both against the same recorded sha256. Two independent sources for
the bytes is strictly more valuable than one for a crypto library.

On a clean re-run of an already-published release, `publish-npm`
fetches the registry's `dist.integrity` and compares it to the local
recorded value. A match exits silently. A mismatch fails the workflow
loudly: that scenario is registry tarball substitution, and you want
to know about it on the next CI run rather than discover it later.

### Limitations of the reproduce gate

- **Single OS only.** Both builds run on `ubuntu-24.04`. Cross-OS
  reproducibility is a stronger claim that adds a correctness burden
  on consumers (their build must work on multiple OSes); it is not
  in scope for v0.4.
- **Two-run sample size.** A non-determinism source that fires
  probabilistically (one in a thousand) won't reliably show up in
  two runs. Accept this as the cost of CI minutes.
- **`SOURCE_DATE_EPOCH` is opt-in for build tools.** We can't force
  `esbuild`/`rollup`/`webpack`/`tsc` to honour it. Belt-and-braces
  mtime normalisation closes the file-stamp gap, but embedded
  timestamps inside compiled output are still the consumer's bug to
  fix.

See [`docs/migration-from-v0.3.md`](docs/migration-from-v0.3.md) if
you're upgrading from v0.3 and want the safer `warn` middle path
during the migration.

## Workflow pin auditing

`verify-action-pins` walks `.github/workflows/*.yml` in **your** repo
and emits a warning for every `uses: owner/repo@ref` line whose ref
isn't a 40-character hex SHA. By default this is warn-only — adopting
the action does not start failing your existing release on day one.
Set `strict-action-pins: true` in your caller workflow to promote the
warnings to a hard failure.

The reason is the [`tj-actions/changed-files` incident in March 2025](https://github.com/tj-actions/changed-files/issues/2464):
a tag-pinned action can be silently re-pointed at malicious code by
an attacker who compromises the action's repo or tag namespace. SHA
pinning binds the action to a specific commit so re-pointing has no
effect on existing consumers.

`forgesworn/release-action` itself is **exempt by name** from this
gate. Without the carve-out, every consumer's release would fail on
the line that loads the gate (`uses: forgesworn/release-action@v0`).
Consumers who want SHA-pinning of release-action itself should still
do so in their caller workflow with a 40-char SHA pin; the exemption
is by name, not by ref, so the rest of your workflow's SHA-pin
enforcement works exactly as you'd expect. See
[`THREAT-MODEL.md`](THREAT-MODEL.md) for the rationale.

## Trusted publisher caveat (important)

npm's trusted publisher matches against the OIDC token's **`workflow_ref`**
claim — the **caller** workflow, not the reusable workflow.

That means: when you use `forgesworn/release-action` via the reusable
workflow pattern, your package's trusted publisher must be configured
for **your own repo** and **your own caller workflow file**, not for
`forgesworn/release-action/release.yml`.

Configure on npmjs.com → your package → Settings → Trusted Publisher:

| Field | Value |
|---|---|
| Publisher | GitHub Actions |
| Organization or user | your GitHub org/user |
| Repository | **your package's repo** |
| Workflow filename | **your caller workflow file** (e.g. `release.yml`) |
| Environment | (leave empty) |

The reusable workflow still gets you centralised gate logic — one place
to update tag-match, secret scan, exports sanity, frozen-vector check,
runtime audit, etc., across every consumer. That's the real benefit.

What it does **not** give you is a single trusted-publisher record in
`forgesworn/release-action` that every consumer points at. That pattern
would require npm to match on `job_workflow_ref` (the reusable), which
it doesn't today. Jordan Harband (npm contributor) has recommended
against trusted publishing with reusable workflows for this reason — see
[`npm/documentation#1755`](https://github.com/npm/documentation/issues/1755).
It still works fine; you just configure the trust at the consumer
boundary rather than the reusable-workflow boundary.

If you see `npm publish` fail with:

```
OIDC token exchange error - package not found
```

at `/-/npm/v1/oidc/token/exchange/package/<name>`, the most likely
cause is the trusted publisher is configured for the wrong repo.
Change the Repository field to your package's own repo.

If that does not fix it, add `debug: true` to your caller workflow's
`with:` block and re-run. The diagnostic step dumps npm version, the
redacted effective `.npmrc`, OIDC env var presence, and `npm config
list` — enough ground-truth to tell whether npm is missing the OIDC
context entirely or has it but cannot match the trusted publisher.

## Advanced: composite action directly

If you need custom job structure or extra pre-flight steps, you can
bypass the reusable workflow and use the composite action in your own
job:

```yaml
jobs:
  release:
    runs-on: ubuntu-24.04
    permissions:
      contents: write
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: forgesworn/release-action@v0
        with:
          vector-test-command: npm run test:vectors
```

The composite action runs the same step scripts the reusable workflow
does. The reusable workflow remains the documented default because it
bakes the correct `permissions:` block in.

## Pinning

Pin by tag (`@v0` while MVP, `@v1` when stable) for stable pins, or by
commit SHA for maximum reproducibility. Dependabot can bump pins
automatically. Major version bumps indicate a change in gate semantics
— always review before upgrading the pin.

`v0.x` is the MVP series: the gate set may still shift in response to
real-world pilot feedback. A `v1.0.0` release will be cut once the
action has been in production use across several forgesworn libraries.

## Supported registries

| Registry | MVP | Notes |
|---|---|---|
| npm | yes | OIDC trusted publishing, provenance on every publish |
| JSR | yes | Opt-in via `jsr.json`, uses `JSR_TOKEN` (no OIDC yet) |
| crates.io | phase 2 | Pending Rust counterpart library |

## Threat model

See [THREAT-MODEL.md](THREAT-MODEL.md) for the full security contract:
what the action defends against, what it explicitly does not, the trust
boundaries, and the known limitations of the secret scan. Summary: the
action defends against accidentally publishing the wrong version,
secrets in artefacts, stolen long-lived tokens (via OIDC), and broken
frozen vectors. It does not defend against a malicious maintainer, a
compromised GitHub, or a compromised registry.

## Contributing

This action is deliberately small. Before adding a feature, ask whether
it fits within the trust boundaries in [THREAT-MODEL.md](THREAT-MODEL.md)
and whether the total bash surface area stays under the thirty-minute
audit budget.

Non-goals:

- Automated commit analysis or semver determination from commit messages
- Changelog generation as a release-blocking step
- Node-based tooling inside the action itself
- Dependencies that are not already on the default GitHub Actions runner image

## Licence

MIT. See [LICENCE](LICENCE).
