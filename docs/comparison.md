# How anvil compares

An honest comparison with the five tools most JS/TS library authors
consider for release automation. Updated 2026-04.

The supply-chain landscape has shifted: as of mid-2025, release-it and
np both ship npm OIDC trusted publishing and/or `--provenance`
support. anvil's differentiation is no longer "the only tool with
OIDC and provenance" -- it is reproducible-build attestation,
pack-set secret scanning, and the audit budget itself.

## At a glance

| | anvil | semantic-release | changesets | release-please | release-it | np |
|---|---|---|---|---|---|---|
| Weekly npm downloads | -- (GH Action) | 2.4M | 2.6M | -- (GH Action) | 760K | 140K |
| GitHub stars | -- | 23.5K | 11.7K | 6.7K | 8.9K | 7.7K |
| Direct dependencies | **0** | 28 | 26 | n/a | 23 | 36 |
| Version decision | manual or auto | auto (commits) | manual (changeset files) | auto (commits) | interactive or auto | interactive |
| CHANGELOG generation | auto (via auto-release.yml) | auto | auto (from changesets) | auto | auto | no |
| OIDC trusted publishing | yes (required) | optional | no | no | yes (since 2025-07) | via npm CLI |
| SLSA provenance | yes (every publish) | optional | no | no | yes (with OIDC) | yes (`--provenance`) |
| Reproducible builds | **yes (two-runner)** | no | no | no | no | no |
| Secret scan | yes | no | no | no | no | no |
| Exports map verification | yes | no | no | no | no | no |
| Action-pin auditing | yes | no | no | no | no | no |
| Monorepo support | no (single-package by design) | via plugins | **native** | yes | via plugins | no |
| Runtime | bash (CI only) | Node.js | Node.js | TypeScript (CI) | Node.js | Node.js (local) |
| Auditable in 30 minutes | yes (~1700 lines) | no (~28 deps) | no (~26 deps) | no | no (~23 deps) | no (~36 deps) |

## Tool-by-tool

### vs semantic-release (2.4M weekly downloads)

semantic-release is the market leader. It parses conventional commit
messages, determines the version bump, generates a changelog, tags,
and publishes. Fully automatic. 28 direct dependencies, hundreds
transitive.

**What semantic-release does better:**
- Huge community: answers on StackOverflow, tutorials everywhere

**What anvil does better:**
- Same push-to-main automation via the [`auto-release.yml`](../README.md#auto-version-strategy)
  companion workflow, zero dependencies (vs ~500 transitive in semantic-release)
- Reproducible-build attestation (no other tool offers this)
- Secret scanning, exports verification, action-pin auditing
- OIDC trusted publishing required by default (not optional)
- SLSA provenance on every publish (not opt-in)
- Auditable: ~1700 lines of bash vs opaque dependency tree
- `verify` mode: you pick the version, the tool catches mistakes.
  No equivalent in semantic-release.

**The version-from-commits problem:**
semantic-release derives your public API contract from commit message
prefixes. One contributor writes `feat:` instead of `fix:` and you
ship a minor instead of a patch. The tool provides no way to override
this without editing commit history. anvil gives you three
options: `manual` (you decide everything), `verify` (you decide but
the tool catches undersized bumps), or the `auto-release.yml` companion
workflow (same commit-driven automation, zero dependencies).

**Who should switch:**
Anyone who wants the same push-to-main automation without adding ~500
transitive dependencies to their repo. The `auto-release.yml` companion
workflow gives you the same automation. `verify` mode gives you something semantic-release
can't: manual version control with automated consistency checking.
If your consumers audit your dependency tree, anvil removes
the entire release-tooling attack surface.

**Migration effort:** Low. See
[`docs/migration-from-semantic-release.md`](migration-from-semantic-release.md).

---

### vs changesets (2.6M weekly downloads)

changesets takes a fundamentally different approach: developers create
small markdown files ("changesets") describing their changes. At
release time, these are aggregated to determine the version bump and
changelog. 26 direct dependencies. Native monorepo support is its
killer feature.

**What changesets does better:**
- **Native monorepo support** with dependency graph awareness
- Changeset files decouple versioning from commit messages
- PR-level granularity (one changeset per PR, not per commit)
- Mature ecosystem (used by Vercel, Chakra UI, Radix)

**What anvil does better:**
- Zero dependencies (vs ~300 transitive)
- Reproducible builds, secret scanning, OIDC, provenance
- No extra files to manage (changesets require `.changeset/*.md`)
- No CLI tool needed locally
- Supply-chain gates that changesets doesn't offer

**The monorepo gap:**
This is the main reason to choose changesets today. anvil is
single-package by design. If you have a monorepo with inter-package
dependencies, changesets handles that natively. anvil
requires one workflow per package.

**Who should switch:**
Single-package library authors who use changesets but find the
changeset file ceremony excessive. Monorepo users should stay on
changesets.

**Migration effort:** Low-medium. Remove `.changeset/` config, delete
changeset files, add the caller workflow. See
[`docs/migration-from-changesets.md`](migration-from-changesets.md).

---

### vs release-please (6.7K stars)

Google's release-please scans conventional commits and opens a
"release PR" that bumps version files and updates CHANGELOG. When
the PR is merged, it creates a GitHub Release. It does not publish
to npm -- that's left to you.

**What release-please does better:**
- PR-based review gate (human approves the version before it ships)
- Multi-language support (Java, Python, Go, Rust, etc.)
- Monorepo support with manifest mode
- Lightweight: no npm package to install

**What anvil does better:**
- Complete pipeline: gates + publish + provenance (release-please
  stops at tagging)
- Reproducible builds, secret scanning, exports verification
- OIDC trusted publishing and SLSA provenance built in
- The `auto-release.yml` companion workflow provides the same commit-to-release automation
- `verify` mode offers something release-please can't: manual
  version control with automated consistency checking

**The publish gap:**
release-please intentionally does not publish. You need a separate
workflow step for `npm publish`. anvil handles the entire
pipeline including publish with OIDC and provenance.

**Who should switch:**
Anyone already using release-please who wants the publish step
handled too, with supply-chain gates included.

**Migration effort:** Low. See
[`docs/migration-from-release-please.md`](migration-from-release-please.md).

---

### vs release-it (760K weekly downloads)

release-it is a pragmatic release tool that works interactively or in
CI. It bumps version, tags, publishes, and creates a GitHub Release.
Plugin architecture for Git, GitHub, GitLab, npm. 23 direct
dependencies.

**What release-it does better:**
- Interactive mode for local releases
- GitLab support (anvil is GitHub-only)
- Plugin architecture (more extensible)
- Conventional changelog plugin for auto-changelogs
- Simpler config for simple projects
- OIDC trusted publishing with automatic provenance (since July 2025)
  closes the gap that anvil's earlier pitch leaned on

**What anvil does better:**
- Zero dependencies (vs ~200 transitive)
- Reproducible-build attestation across two runners (release-it does
  not offer this)
- Pack-set secret scanning against the exact files `npm pack` would
  upload (release-it has no equivalent gate)
- Exports map verification, runtime-only audit, action-pin audit,
  frozen-vector gate -- all release-blocking, none of them in
  release-it
- Pure bash in CI: ~1400 auditable lines vs Node runtime + plugin
  surface
- Harder security guarantees (gates fail the release, not just warn)

**Who should switch:**
GitHub-only library authors who want reproducibility gating and
pack-set scanning on top of OIDC. If trusted publishing alone is
the bar, release-it now meets it. GitLab users should stay on
release-it.

**Migration effort:** Low. See
[`docs/migration-from-release-it.md`](migration-from-release-it.md).

---

### vs np (140K weekly downloads)

Sindre Sorhus's np is an interactive CLI for local publishing. It
runs safety checks (clean working tree, correct branch, tests pass),
bumps version, tags, and publishes. 36 direct dependencies. Not
designed for CI.

**What np does better:**
- Interactive local workflow (pick version at publish time)
- Elegant CLI experience
- Built-in 2FA support
- No CI setup needed
- `--provenance` flag for CI publishing (closes the provenance gap
  that anvil's earlier pitch leaned on)

**What anvil does better:**
- CI-native by design: no local tooling, no developer machine in the
  trust chain
- OIDC trusted publishing as the default credential model, not a flag
  on top of an interactive CLI
- Reproducible-build attestation across two runners (np does not
  offer this)
- Pack-set secret scanning, exports verification, runtime-only audit,
  action-pin audit, frozen-vector gate -- all release-blocking
- ~1400 lines of auditable bash vs Node runtime + 36 direct deps

**The philosophy gap:**
np is "better npm publish from your laptop". anvil is
"npm publish should never happen from a laptop". These are
fundamentally different philosophies. np trusts the developer's
machine. anvil trusts only CI with OIDC credentials.

**Who should switch:**
Anyone who's decided publishing should happen in CI, not locally.
If you prefer the interactive local workflow, np is the right tool.

**Migration effort:** Minimal. See
[`docs/migration-from-np.md`](migration-from-np.md).

---

### vs JS-DevTools/npm-publish (666 stars, GitHub Action)

JS-DevTools/npm-publish is the dominant "just publish" action. It
detects version bumps in package.json, runs npm publish, and exits.
v4 supports OIDC trusted publishing. No gates beyond tag/version
detection. Node-based.

**What JS-DevTools/npm-publish does better:**
- Battle-tested (666 stars, widely used)
- Simpler mental model when all you want is publish
- Handles the version-detection heuristic well

**What anvil does better:**
- Pre-publish gates: secret scan, exports check, frozen vectors,
  runtime audit, action-pin audit (JS-DevTools offers none of these)
- Reproducible-build attestation (two-runner)
- SLSA provenance required by default, not opt-in
- Pure bash vs Node runtime (smaller attack surface)
- Tarball integrity stamped into Release body + uploaded as asset

**The philosophy gap:**
JS-DevTools/npm-publish publishes. anvil publishes safely.
If the only bar is "get bytes onto the registry with OIDC",
JS-DevTools/npm-publish is fine. If the bar includes "no accidental
secret leak, no broken exports, no silent non-determinism,
no compromised third-party action in your pipeline", anvil is
the deliberate upgrade.

**Who should switch:**
Authors who adopted JS-DevTools/npm-publish for its simplicity but
now want supply-chain guarantees on top of OIDC.

**Migration effort:** Minimal. Swap the caller workflow;
OIDC trusted publisher config carries over unchanged.

---

### vs pascalgn/npm-publish-action (227 stars, GitHub Action)

pascalgn/npm-publish-action is a simpler "auto-detect version,
publish" action. No OIDC support last time checked; relies on
long-lived NPM_TOKEN. No gates.

**What pascalgn does better:**
- Nothing relevant to the anvil user profile.

**What anvil does better:**
- OIDC vs stored NPM_TOKEN (the attack vector this tool predates)
- All pre-publish gates
- Reproducible builds, provenance, integrity stamping

**Who should switch:**
Anyone using pascalgn/npm-publish-action who hasn't yet migrated
off long-lived NPM_TOKEN. The security gap vs modern tooling is
significant.

**Migration effort:** Minimal on the action side; revoke NPM_TOKEN
and configure trusted publishing on npmjs.com.

---

## Feature matrix: supply-chain hardening

This is where anvil's differentiation is clearest.

| Gate | anvil | semantic-release | changesets | release-please | release-it | np |
|---|---|---|---|---|---|---|
| OIDC (no stored tokens) | required | opt-in | no | no | yes | via npm CLI |
| SLSA provenance | every publish | opt-in | no | no | yes | opt-in (`--provenance`) |
| Reproducible builds | two-runner | no | no | no | no | no |
| Secret scan (pack set) | yes | no | no | no | no | no |
| Exports map check | yes | no | no | no | no | no |
| Runtime-only audit | yes | no | no | no | no | no |
| Action-pin audit | yes | no | no | no | no | no |
| Frozen-vector gate | yes | no | no | no | no | no |
| Tarball integrity in release | yes | no | no | no | no | no |
| Zero release-tool deps | yes | no | no | yes (GH Action) | no | no |

## When NOT to use anvil

Be honest about the gaps:

- **You have a monorepo.** Use changesets.
- **You need a large plugin ecosystem** (Slack, backmerge, custom
  analysers). Use semantic-release.
- **You publish from your laptop and prefer it that way.** Use np.
- **You use GitLab, not GitHub.** Use release-it.
- **You need the PR-review gate before version bumps.** Use
  release-please. (anvil's `verify` mode checks after the
  fact, not before.)

## The pitch

anvil is for library authors who:

1. Already bump versions and write changelogs manually (or want the
   `auto-release.yml` companion workflow to do it with zero dependencies)
2. Want a publish pipeline that does not make them nervous
3. Care about supply-chain surface area enough to read what publishes
   their code
4. Want reproducible-build attestation (still no equivalent in
   semantic-release, changesets, release-please, release-it, or np)
5. Want pack-set secret scanning against the exact files `npm pack`
   would upload (no equivalent in any of the above)
6. Value an audit budget over a feature list: ~1700 lines of bash a
   reader can verify in a single sitting, vs hundreds of transitive
   dependencies they cannot

OIDC trusted publishing and SLSA provenance are no longer the wedge:
release-it and np have caught up. Reproducibility, pack-set scanning,
and the audit budget are the parts of anvil's posture that nothing
else in this list offers.

If that's you, the migration from any of the above tools is a
single-session job. See the migration guides in this directory.
