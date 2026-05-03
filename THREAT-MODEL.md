# Threat model

This document captures what `forgesworn/anvil` defends against,
what it explicitly does not, and why. It is the security contract between
the action and its consumers. If a change to the action would break one
of the defences listed below, that change needs explicit justification.

## Design principles (relevant to threats)

1. **The release tool's own dep tree must be smaller than the libraries it
   ships.** Pure `bash` + `jq` + `gh` + `npm`. No Node tooling. No Docker.
   No compiled binaries the consumer cannot read.
2. **OIDC trusted publishing throughout.** No long-lived `NPM_TOKEN`
   stored in any consuming repo. SLSA provenance attached to every publish.
3. **Hard pre-publish gates over automated cleverness.** A failed gate
   refuses the publish. No "best effort" semantics. The release fails
   loudly or it succeeds completely.
4. **Explicit human intent, automated everything else.** Either a
   human commits the version bump and CHANGELOG entry manually
   (manual mode), or a human pushes conventional-commit messages
   that CI parses into a bump (auto mode). Either way, a traceable
   human commit is the trigger; CI handles tag verification, gates,
   publish, and GitHub Release body. No scheduled releases, no
   "publish on timer".
5. **The action source must be auditable in under thirty minutes total.**
   Currently ~1600 lines of bash across all step scripts.

## Threats addressed

| Threat | Defence |
|---|---|
| Compromised `NPM_TOKEN` leaked from a CI secret | OIDC trusted publishing. No long-lived token exists in any consumer repo. |
| Malicious code injected into a release-tooling devDependency at publish time | Zero release-tooling devDependencies in the consumer repo. The action is pure bash. |
| Accidental publish of a development version | `verify-tag` refuses the publish if git tag and `package.json` version disagree. |
| Accidental publish of secrets in packable artefacts | `verify-secrets` scans `dist/` and every path in `package.json` `files` for forbidden filenames and content patterns (private-key PEM blocks, Nostr nsecs, AWS/Slack/GitHub tokens). |
| Accidental break of a frozen protocol output | `verify-vectors` runs the consumer's configured frozen-vector command and refuses the publish if it exits non-zero. |
| Drift between declared `exports` and files on disk | `verify-exports` walks every exports subpath plus legacy `main`/`module`/`types`/`bin` entries and refuses the publish if any target is missing. |
| Runtime dependency with a known advisory shipping to production | `verify-audit` runs `npm audit --omit=dev` at `low` level by default. Dev-dep noise does not block; runtime issues do. |
| Maintainer accidentally pushing the wrong commit | In manual mode, the GitHub Release trigger forces an explicit, reviewable action — the maintainer creates the Release and the action runs only in response. In auto mode, a conventional commit on main is the explicit human action, and the chained workflow (see `docs/design/chained-workflows.md`) runs in one CI run. Either way, a real human commit is the trigger; there is no scheduled or background release path. |
| Consumer repo leaking a PAT used to bridge the auto-release → release.yml event chain | Replaced event coupling with `workflow_call` coupling in v0.6. The chained auto-release flow needs no PAT — one workflow run, one `GITHUB_TOKEN`, no long-lived credential in the consumer repo. Legacy `GH_TOKEN` secret is still accepted but silently unused; a stale PAT in a consumer repo no longer weakens anything. |
| Unreviewed npm publish after the release workflow starts | The reusable workflow attaches the publish job to the `npm-publish` GitHub Environment by default. Consumers can configure that environment with required reviewers, prevent self-review, and release-ref restrictions, then bind npm trusted publishing to the same environment. |
| Maintainer accidentally leaving legacy npm token publishing enabled in the release job | `publish-npm` fails if `NPM_TOKEN` or a real `NODE_AUTH_TOKEN` is set, or if npm auth material is present in `.npmrc`. The literal `actions/setup-node` placeholders (`NODE_AUTH_TOKEN=XXXXX-XXXXX-XXXXX-XXXXX` and `_authToken=${NODE_AUTH_TOKEN}`) are accepted because they carry no secret material; npm 11.5+ ignores them during OIDC exchange. npm publish must go through OIDC trusted publishing, and `publishConfig.provenance: true` is enforced before upload. |
| Supply-chain attack via the action's own transitive dependencies | The action has no Node dependencies. It invokes `bash`, `jq`, `gh`, `npm`, and `sed`/`awk`/`find`/`grep` from the GitHub-managed runner image. No fetched binaries. |
| Race between parallel releases publishing the same version twice | `publish-npm` is idempotent: if the exact version is already on the registry, it exits `0` without re-publishing. |
| Registry tarball substitution between publish and consumer fetch | `record-tarball` packs the artefact once and writes its sha512 (npm integrity format) plus sha256 to a meta file. `publish-npm` uploads that exact tarball — not a re-pack — and on a clean re-run compares the registry's `dist.integrity` to the recorded value: a mismatch fails the workflow loudly. The hashes are also stamped into the GitHub Release body so consumers can `curl | shasum` the registry tarball at any time. |
| Compromised third-party action re-pointed at malicious code via tag mutation (the `tj-actions/changed-files` 2025-03 vector) | `verify-action-pins` walks `.github/workflows/*.yml` in the consumer repo and warns on any `uses: owner/repo@ref` line whose ref is not a 40-char hex SHA. Warn-only by default; `strict-action-pins: true` promotes to fail. |
| Compromised publish credential used to ship a malicious `preinstall` / `install` / `postinstall` hook (the April 2026 `@bitwarden/cli@2026.4.0` / TeamPCP–Checkmarx vector) | `verify-lifecycle-scripts` reads the consumer's `package.json` and flags any install-time hook not matching an explicit `allowed-lifecycle-scripts` allowlist. Warn-only by default; `lifecycle-scripts-policy: strict` promotes to fail. Combined with OIDC trusted publishing (no long-lived `NPM_TOKEN` to exfiltrate), this closes the primary payload mechanism used by that campaign. |
| Non-deterministic build masking a regression in compiled output | The reusable workflow runs **two parallel builds on independent runners**, both packed with normalised mtimes and `SOURCE_DATE_EPOCH` derived from `git log`. The `reproduce` job compares the two sha256s and (under the default `reproducibility-mode: strict`) refuses to publish on mismatch. This catches embedded build timestamps, sorted-by-fs globs, random IDs, and host-path leakage — the common ways non-determinism slips into a JS bundle. Stronger than SLSA provenance: provenance attests one runner built these bytes once; reproduce attests two runners arrive at the same bytes. |

## Threats explicitly NOT addressed

| Threat | Why not |
|---|---|
| Malicious commit by the maintainer themselves | Out of scope. This is a publish hygiene tool, not a code review tool. |
| Compromise of GitHub itself | Out of scope. If GitHub is compromised, the entire ecosystem is. |
| Compromise of the npm registry itself | Out of scope. SLSA provenance helps consumers verify upstream, but the action cannot prevent registry compromise. |
| A bug in the action's own bash that allows command injection | Mitigated by code review and small surface area, not eliminated. Report bugs through issues. |
| Supply-chain attack on `gh`, `jq`, `npm`, `awk`, `sed`, `find`, `grep` themselves | Mitigated by using the GitHub-managed runner image, which is SHA-pinned to a runner release, not eliminated. |
| Leaked GitHub Actions OIDC claims reused by a third party | Mitigated by the short OIDC token lifetime (~10 minutes) and the npm registry's trusted-publisher repo/workflow matching, not eliminated. |
| Supply-chain substitution of the `jsr` CLI package at publish time | JSR publish is opt-in (requires `jsr.json` in the consumer repo). `publish-jsr.sh` pins `jsr@${JSR_CLI_VERSION}` by semver, not integrity: a maintainer-account compromise of the `jsr` npm package within npm's 72-hour republish-after-unpublish window could substitute bytes while keeping the version string. Mitigated by the version pin and opt-in posture; not eliminated. Bump `JSR_CLI_VERSION` only after manually verifying the tarball SHA against a known-good release. |
| Compromised third-party action running in a sibling job that can see publish credentials | Out of anvil's enforcement reach. anvil controls the jobs it defines in `release.yml`; a consumer workflow that runs a third-party action (Trivy, KICS, linters, custom scanners) in a separate job of the same run must either not expose `secrets.*` to that job, or not have an `NPM_TOKEN` secret to expose at all. OIDC trusted publishing already removes the primary long-lived target; see the "isolating third-party actions" note under Known limitations. |
| `@v0` (major) floating tag auto-adoption after a compromised release | `self-release.yml` force-advances the `v0` tag on every release so consumers pinned `@v0` get new versions without pin bumps. A single compromised commit that passes anvil's own self-release gates would auto-propagate to every consumer pinned `@v0`. This is the same trust property as `actions/checkout@v4`, `actions/setup-node@v6`, and every other action that offers a floating major tag. Consumers who want a stronger guarantee should pin anvil to a 40-char SHA and set `strict-action-pins: true` in their caller workflow. |

## Trust boundaries

- **Trusted**: the GitHub Actions runner (ephemeral, isolated), the
  `gh`/`jq`/`npm`/`bash`/`awk`/`sed`/`find`/`grep` binaries on the
  runner image, and the action's own bash scripts.
- **Trusted on the consumer's behalf**: per-repo configuration inputs
  (`vector-test-command`, `test-command`, `audit-level`, etc.) because
  they are committed to the consuming repo and reviewable there.
- **Untrusted**: everything the consumer's test and build commands
  bring in. If a devDependency has a vulnerability that executes at
  `npm ci` or `npm run build` time, the action has no defence. This
  is why the design principle says "the release tool's own dep tree
  must be smaller than the libraries it ships".

## Known limitations

The following are deliberate trade-offs that a consumer should know
about. They are not bugs, but they are gaps a well-informed consumer
might choose to plug with an additional pre-step.

### Content secret scan skips `.md` / `.markdown` / `.txt` / `.rst` / `.adoc`

Content pattern scans (PEM blocks, Nostr nsecs, AWS/GitHub/Slack
tokens) do not run against documentation files. The reason: crypto
libraries legitimately publish protocol docs and test vectors
containing *example* secret-shaped strings (e.g. an `nsec1...`
derivation example in `PROTOCOL.md`). Scanning the docs would force
those libraries to either sanitise examples or suppress the scan per
file, and both paths have been worse in practice than the current
default.

The filename-based portion of the scan (`.env`, `id_rsa`, `*.pem`,
etc.) still runs against every file including docs, so an actual
`id_ed25519` in a README directory would be caught.

A real leaked `nsec1...` in a README.md **would not** be caught by
this scan. If your repo has this risk profile, add a pre-step that
greps your docs tree with stricter rules before calling the action.

### Secret scan roots come from `package.json` `files` plus `dist/`

`verify-secrets` enumerates the paths it scans from the `files` array
in `package.json`, plus `dist/` as a hardcoded default. Libraries
without an explicit `files` field publish whatever npm packs by
default (essentially the whole repo minus `node_modules` and
`.gitignore` entries), which means there is a scan gap on `src/` and
similar directories.

**Recommendation**: declare an explicit `files` array in
`package.json` for any library using this action. This is a general
best practice for published packages — it makes the publish surface
area predictable and greppable — and it closes this gap as a side
effect. A good reference:
`["dist", "src", "README.md", "CHANGELOG.md", "LICENCE"]`.

### The reproduce gate is single-OS and two-run

The v0.4 reproduce gate runs both builds on `ubuntu-24.04`. That
catches non-determinism that varies between runner instances —
timestamps, random tmp paths, build-tool ordering — but it does not
catch determinism violations that vary across operating systems.
Cross-OS reproducibility is a stronger claim that adds a real
correctness burden on consumers (their build must work on multiple
OSes); v0.5 territory at the earliest, and only if pilot feedback
shows demand.

Two runs is also the minimum sample size for empirical reproducibility
testing. A non-determinism source that fires probabilistically (one
in a thousand) won't reliably show up in two runs. We accept this as
the cost of CI minutes; the alternative is N runs and the marginal
value drops fast.

`SOURCE_DATE_EPOCH` is opt-in for build tools. We can't force
`esbuild`/`rollup`/`webpack`/`tsc` to honour it, so
`normalise-mtimes.sh` does belt-and-braces mtime fixing across the
working tree to close the file-stamp gap unconditionally. Embedded
timestamps inside compiled output (e.g. a `__BUILD_TIMESTAMP__` macro)
are still the consumer's bug to fix and will reliably fail the
reproduce gate.

### The composite action does NOT include the reproduce gate

`action.yml` (the composite action) is a flat list of steps inside
one job. It cannot define the multi-job DAG that the reproduce gate
requires. Consumers who use the composite action get the v0.3
single-runner integrity anchor only — strictly weaker than the
reusable workflow's reproducibility claim. The composite stays as a
power-user escape hatch for custom job structure; the reusable
workflow is the documented default and the only path to the v0.4
flagship guarantee.

### `verify-action-pins` exempts `forgesworn/anvil` and skips dynamic uses

The `verify-action-pins` gate has three known false negatives:

1. **Self-exemption.** Lines whose action name is `forgesworn/anvil`
   or starts with `forgesworn/anvil/` are not flagged, even in
   `strict-action-pins: true` mode. Without this carve-out, every
   consumer's release would fail on the line that loads the gate
   itself (`uses: forgesworn/anvil@v0`). The exemption is by
   **name**, not by ref — a consumer who SHA-pins us in their caller
   workflow gets the same SHA-pin enforcement on every other action.
   This is a pragmatic trade-off: it sidesteps a chicken-and-egg
   adoption problem at the cost of moving the trust decision for
   anvil itself one level up, into the consumer's choice of
   pin in the caller workflow.
2. **Dynamic uses.** A `uses: ${{ matrix.action }}` line cannot be
   resolved statically and is silently ignored. Consumers who template
   action references through matrix expressions should audit those
   templates separately.
3. **YAML anchors and aliases.** The gate is a line-oriented grep, not
   a YAML parser. An anchor definition like `_shared: &pin actions/checkout@v4`
   followed by `uses: *pin` is invisible to the scan: the anchor line
   has no `uses:` prefix, and the alias line has no `owner/repo@ref`
   to inspect. The bash-only audit budget rules out a full YAML parse.
   Consumers using anchors/aliases to deduplicate `uses:` references
   should SHA-pin the anchor target directly, since the alias cannot be
   audited by the gate.

### Secret-scan pack-set selection relies on npm output ordering

`verify-secrets` and `record-tarball` both run `npm pack --json` and
parse the last JSON value from its stdout. This correctly isolates
npm's own manifest from any prepack/prepare lifecycle script that also
prints JSON, because npm emits the manifest **after** prepack has run.
If npm ever reordered so that prepack output came after the manifest
(e.g. a future version that streams output differently), the last-value
selection would pick prepack output instead and the scan could become
bypassable. This is a stable contract today but worth re-checking on
major npm upgrades.

### `verify-lifecycle-scripts` only covers install-time hooks

The gate inspects `preinstall`, `install`, and `postinstall` — the three
hooks npm runs automatically on `npm install <pkg>` for every consumer.
It does **not** inspect `prepare`, `prepack`, `prepublish`, or
`prepublishOnly`: those fire on the publisher's machine at pack/publish
time, not on the consumer, and are already scoped to the trusted publish
job. A malicious `prepack` in a consumer repo would run on anvil's own
runner during `record-tarball.sh` — a separate concern that sits at the
trust boundary between consumer build tooling and the action itself,
covered by the "untrusted consumer build" boundary below.

The gate also does not detect malicious code loaded from the package's
main entry (`require`/`import` side effects that run on first use), nor
code loaded by a native-module binding, nor anything inside a bundled
runtime. Those attacker paths avoid the lifecycle-hook mechanism
entirely; the gate is a targeted block on the *specific* shape used in
the April 2026 Bitwarden compromise, not a general malicious-code
detector. Consumers who want that stronger guarantee need code review
and/or signed commits, which are out of scope.

### Isolating third-party actions from publish credentials

anvil's own `release.yml` jobs do not expose any long-lived secret to
step scripts — OIDC is minted inside the publish job with a ~10-minute
lifetime and `id-token: write` scoped to that job only. The consumer is
responsible for not leaking secrets into *sibling* jobs of the same
workflow run. If a consumer adds a Trivy/KICS/lint job to their release
workflow and sets `env: NPM_TOKEN: ${{ secrets.NPM_TOKEN }}` on it
(defeating the point of OIDC), a compromised third-party action in that
sibling job can still exfiltrate the token and publish out-of-band later.

Mitigations a consumer should apply:

1. **Delete any `NPM_TOKEN` secret.** With OIDC trusted publishing
   configured on npm, it is unused; keeping it is the whole attack
   surface.
2. **Run third-party scanners in a separate workflow**, not a sibling
   job of the release workflow. A scanner triggered on `pull_request`
   or `push` never sees the release context's secrets.
3. **Pin every third-party action by 40-char SHA** and enable
   `strict-action-pins: true` so `verify-action-pins` fails the release
   on any unpinned reference.

### Changelog extraction uses a word-bounded heading match

`changelog-extract` finds the CHANGELOG section by matching any H1/H2/H3
heading whose text contains both a dotted numeric version pattern and
the target version with word boundaries around it. The boundary is
"preceded by start-of-line or a non-version character, followed by
end-of-line or a non-version character", with an optional leading `v`
consumed. This correctly accepts `## 1.5.0`, `## v1.5.0`,
`## 1.5.0 (2026-04-11)`, and `### [1.5.0] - 2026-04-11`, and correctly
rejects `## Pre-1.5.0`, `## 1.5.0-rc.1`, `## 1.5.00`, and `## 11.5.0`.

## Reporting vulnerabilities

Security issues in the action itself should be reported via GitHub
Security Advisories at the `forgesworn/anvil` repo.
Non-security bugs go to the regular issue tracker.
