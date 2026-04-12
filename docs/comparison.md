# How release-action compares

An honest comparison with the five tools most JS/TS library authors
consider for release automation. Updated 2026-04.

## At a glance

| | release-action | semantic-release | changesets | release-please | release-it | np |
|---|---|---|---|---|---|---|
| Weekly npm downloads | -- (GH Action) | 2.4M | 2.6M | -- (GH Action) | 760K | 140K |
| GitHub stars | -- | 23.5K | 11.7K | 6.7K | 8.9K | 7.7K |
| Direct dependencies | **0** | 28 | 26 | n/a | 23 | 36 |
| Version decision | manual or auto | auto (commits) | manual (changeset files) | auto (commits) | interactive or auto | interactive |
| CHANGELOG generation | auto (in auto mode) | auto | auto (from changesets) | auto | auto | no |
| OIDC trusted publishing | yes (required) | optional | no | no | optional | no |
| SLSA provenance | yes (every publish) | optional | no | no | no | no |
| Reproducible builds | **yes (two-runner)** | no | no | no | no | no |
| Secret scan | yes | no | no | no | no | no |
| Exports map verification | yes | no | no | no | no | no |
| Action-pin auditing | yes | no | no | no | no | no |
| Monorepo support | no (single-package by design) | via plugins | **native** | yes | via plugins | no |
| Runtime | bash (CI only) | Node.js | Node.js | TypeScript (CI) | Node.js | Node.js (local) |
| Auditable in 30 minutes | yes (~1400 lines) | no (~28 deps) | no (~26 deps) | no | no (~23 deps) | no (~36 deps) |

## Tool-by-tool

### vs semantic-release (2.4M weekly downloads)

semantic-release is the market leader. It parses conventional commit
messages, determines the version bump, generates a changelog, tags,
and publishes. Fully automatic. 28 direct dependencies, hundreds
transitive.

**What semantic-release does better:**
- Huge community: answers on StackOverflow, tutorials everywhere

**What release-action does better:**
- Same push-to-main automation via `auto` mode, zero dependencies
  (vs ~500 transitive in semantic-release)
- Reproducible-build attestation (no other tool offers this)
- Secret scanning, exports verification, action-pin auditing
- OIDC trusted publishing required by default (not optional)
- SLSA provenance on every publish (not opt-in)
- Auditable: ~1400 lines of bash vs opaque dependency tree
- `verify` mode: you pick the version, the tool catches mistakes.
  No equivalent in semantic-release.

**The version-from-commits problem:**
semantic-release derives your public API contract from commit message
prefixes. One contributor writes `feat:` instead of `fix:` and you
ship a minor instead of a patch. The tool provides no way to override
this without editing commit history. release-action gives you three
options: `manual` (you decide everything), `verify` (you decide but
the tool catches undersized bumps), or `auto` (same commit-driven
automation, zero dependencies).

**Who should switch:**
Anyone who wants the same push-to-main automation without adding ~500
transitive dependencies to their repo. `auto` mode gives you the
same workflow. `verify` mode gives you something semantic-release
can't: manual version control with automated consistency checking.
If your consumers audit your dependency tree, release-action removes
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

**What release-action does better:**
- Zero dependencies (vs ~300 transitive)
- Reproducible builds, secret scanning, OIDC, provenance
- No extra files to manage (changesets require `.changeset/*.md`)
- No CLI tool needed locally
- Supply-chain gates that changesets doesn't offer

**The monorepo gap:**
This is the main reason to choose changesets today. release-action is
single-package by design. If you have a monorepo with inter-package
dependencies, changesets handles that natively. release-action
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

**What release-action does better:**
- Complete pipeline: gates + publish + provenance (release-please
  stops at tagging)
- Reproducible builds, secret scanning, exports verification
- OIDC trusted publishing and SLSA provenance built in
- `auto` mode provides the same commit-to-release automation
- `verify` mode offers something release-please can't: manual
  version control with automated consistency checking

**The publish gap:**
release-please intentionally does not publish. You need a separate
workflow step for `npm publish`. release-action handles the entire
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
- GitLab support (release-action is GitHub-only)
- Plugin architecture (more extensible)
- Conventional changelog plugin for auto-changelogs
- Simpler config for simple projects

**What release-action does better:**
- Zero dependencies (vs ~200 transitive)
- Reproducible builds, secret scanning, exports verification
- OIDC trusted publishing and SLSA provenance
- No local tool installation needed
- Harder security guarantees (gates fail the release, not just warn)

**Who should switch:**
GitHub-only library authors who want stronger supply-chain guarantees
than release-it provides. GitLab users should stay on release-it.

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

**What release-action does better:**
- CI-native: no local tooling, no developer machine dependency
- OIDC trusted publishing (no long-lived tokens)
- Reproducible builds, secret scanning, exports verification
- SLSA provenance on every publish
- No npm install needed (pure bash in CI)

**The philosophy gap:**
np is "better npm publish from your laptop". release-action is
"npm publish should never happen from a laptop". These are
fundamentally different philosophies. np trusts the developer's
machine. release-action trusts only CI with OIDC credentials.

**Who should switch:**
Anyone who's decided publishing should happen in CI, not locally.
If you prefer the interactive local workflow, np is the right tool.

**Migration effort:** Minimal. See
[`docs/migration-from-np.md`](migration-from-np.md).

---

## Feature matrix: supply-chain hardening

This is where release-action's differentiation is clearest.

| Gate | release-action | semantic-release | changesets | release-please | release-it | np |
|---|---|---|---|---|---|---|
| OIDC (no stored tokens) | required | opt-in | no | no | opt-in | no |
| SLSA provenance | every publish | opt-in | no | no | no | no |
| Reproducible builds | two-runner | no | no | no | no | no |
| Secret scan (pack set) | yes | no | no | no | no | no |
| Exports map check | yes | no | no | no | no | no |
| Runtime-only audit | yes | no | no | no | no | no |
| Action-pin audit | yes | no | no | no | no | no |
| Frozen-vector gate | yes | no | no | no | no | no |
| Tarball integrity in release | yes | no | no | no | no | no |
| Zero release-tool deps | yes | no | no | yes (GH Action) | no | no |

## When NOT to use release-action

Be honest about the gaps:

- **You have a monorepo.** Use changesets.
- **You need a large plugin ecosystem** (Slack, backmerge, custom
  analysers). Use semantic-release.
- **You publish from your laptop and prefer it that way.** Use np.
- **You use GitLab, not GitHub.** Use release-it.
- **You need the PR-review gate before version bumps.** Use
  release-please. (release-action's `verify` mode checks after the
  fact, not before.)

## The pitch

release-action is for library authors who:

1. Already bump versions and write changelogs manually (or want the
   `auto` mode to do it with zero dependencies)
2. Want a publish pipeline that does not make them nervous
3. Care about supply-chain surface area
4. Want the only JS release tool that offers reproducible-build
   attestation

If that's you, the migration from any of the above tools is a
single-session job. See the migration guides in this directory.
