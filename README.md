# forgesworn/release-action

A cryptography-grade release tool for JavaScript and TypeScript libraries.

Pure `bash` + `jq` + `gh` + `npm`. No Node tooling in the action itself.
OIDC trusted publishing. Provenance on every publish. Hard pre-publish
gates for tag/version match, secret scan, exports sanity, frozen test
vectors, and runtime audit.

The entire action is auditable in under thirty minutes. That is a hard
design constraint, not a slogan.

## Why this exists

The dominant JS/TS release tool chains — `semantic-release`, `changesets` —
bring hundreds of transitive devDependencies with them. For a CRUD app
that is background noise. For a deterministic cryptography library whose
whole value proposition is byte-identical output across implementations
and time, it is a supply-chain surface area no crypto library author
should accept.

None of `@noble/*`, `@scure/*`, `nostr-tools`, `bitcoinjs-lib`,
`bitcoinerlab`, or `nostrify` use heavy release tooling. paulmillr ships
[`jsbt`](https://github.com/paulmillr/jsbt) — a tiny reusable workflow —
for the same reason. This action generalises that pattern and adds the
gates crypto libraries actually care about.

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
   on `registry.npmjs.org` for your package, pointing at this repo and
   workflow.
2. Bump `package.json` version and add a `CHANGELOG.md` entry.
3. Commit, tag (`v1.2.3`), push, and create a GitHub Release for the
   tag. The workflow takes over from there.

## What the action does

In order:

1. **Checkout** your repo and this action at the pinned SHA
2. **Setup Node** with OIDC registry configured
3. **`npm ci`**
4. **`npm run build --if-present`**
5. **verify-tag** — git tag matches `package.json` version
6. **run-tests** — full test suite (`npm test` by default)
7. **verify-vectors** — your configured frozen-vector command (skipped
   if not set; crypto libraries should set this)
8. **verify-audit** — `npm audit --omit=dev` — runtime deps only
9. **verify-exports** — every subpath in `package.json` `"exports"` exists
   on disk
10. **verify-secrets** — grep `dist/` (and any paths in `"files"`) for
    forbidden filenames and secret markers
11. **publish-npm** — idempotent `npm publish --provenance --access public`
    via OIDC. Skipped if the exact version is already on the registry.
12. **publish-jsr** — only if `jsr.json` exists in your repo
13. **update-release** — updates the GitHub Release body from the
    matching `CHANGELOG.md` section

If any gate fails, the workflow fails and nothing is published.

## Inputs

| Input | Default | Description |
|---|---|---|
| `node-version` | `22` | Node version used for npm operations |
| `registry-url` | `https://registry.npmjs.org` | npm registry |
| `test-command` | `npm test` | Full test suite command |
| `vector-test-command` | *(empty)* | Frozen-vector gate command |
| `changelog-file` | `CHANGELOG.md` | Path to CHANGELOG |
| `package-json` | `package.json` | Path to package.json |
| `audit-level` | `low` | `npm audit` severity floor |
| `dry-run` | `false` | Skip real publish (for smoke-testing) |

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

See [THREAT-MODEL.md](THREAT-MODEL.md) *(coming)*. Summary: the action
defends against accidentally publishing the wrong version, secrets in
artefacts, stolen long-lived tokens (via OIDC), and broken frozen
vectors. It does not defend against a malicious maintainer, a
compromised GitHub, or a compromised registry.

## Contributing

This action is deliberately small. Before adding a feature, ask whether
it fits under the principles in the
[design doc](https://github.com/forgesworn/release-action/blob/main/docs/design.md)
*(coming)*. Non-goals: automated commit analysis, changelog generation
as a release-blocking step, Node-based tooling inside the action.

## Licence

MIT. See [LICENCE](LICENCE).
