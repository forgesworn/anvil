# Chained workflows (v0.6 design)

Status: **implemented in v0.6.0**.
Predecessor: v0.5.0 event-coupled auto-release + optional PAT.

## Why

`auto-release.yml` drops a tag and a GitHub Release on push to main.
`release.yml` runs the gates and publishes to npm. In v0.5 the two
were coupled by an event: auto-release's `gh release create` fired a
`release: published` event that was supposed to trigger release.yml.

That coupling only closes for consumers who provide a PAT.

GitHub Actions has an anti-recursion rule: **events created by the
default `GITHUB_TOKEN` do not trigger workflow runs**. A tag push
authored by `github-actions[bot]`, a release created by the workflow,
an issue comment posted by the workflow — all silent. The rule exists
because without it a single workflow could loop itself infinitely on
commit. But it also breaks the perfectly legitimate case of
"workflow A's output should trigger workflow B".

The workaround was to provide a PAT (or GitHub App token) via the
`GH_TOKEN` secret. Acts on behalf of a real user, so GitHub considers
the events "human-authored" and lets them trigger workflows. Two
problems:

1. **Secret sprawl.** Every consumer repo needs a PAT configured,
   stored, rotated, audited. `anvil`'s entire design posture is
   zero-secret (OIDC trusted publishing, `GITHUB_TOKEN` for git). A
   required PAT contradicts that posture.
2. **Opaque failure.** A consumer without a PAT sees auto-release
   succeed (tag pushed, Release created) and nothing else happen.
   The npm publish silently fails to fire. The maintainer has to
   dig through docs to understand why.

## What "chained workflows" means here

Replace the event coupling with a `workflow_call` coupling. Inside
a single workflow run, `auto-release.yml` invokes `release.yml`
directly via `uses:`, passing the newly-pushed tag as an explicit
input. No event is created; the anti-recursion rule does not apply.

The DAG:

```
  push to main
        │
        ▼
  auto-release.yml (one workflow run)
        │
   ┌────┴─────────────────────────────────────────┐
   │                                              │
   ▼                                              ▼
determine                                    commit-and-tag
(parse commits)                              (bump, commit, tag, push)
                                                   │
                                                   ▼
                                              publish
                                              (uses: release.yml@v0)
                                                   │
                                            ┌──────┴──────┬─────────┐
                                            │             │         │
                                            ▼             ▼         ▼
                                          build-a      build-b   reproduce
                                                                     │
                                                                     ▼
                                                                  publish
                                                                (npm + GH Release)
```

One run. No tokens beyond the default `GITHUB_TOKEN` and the OIDC
subject npm issues to the caller workflow. The Release body is
created by `update-release.sh` after a successful publish, not by
`auto-release.yml` up-front — moved for a good reason, see §
"Release ownership" below.

## What changed

### `release.yml` gains a `tag` input

Optional string, defaults to `''`. When set, `release.yml`:

- Uses it as the `ref:` for `actions/checkout` in `build-a`,
  `build-b`, and `publish`.
- Passes it as `GIT_TAG` env to step scripts.

When empty, falls back to `github.event.release.tag_name` —
preserving the legacy release-event trigger path unchanged.

The input is the single most important piece of the refactor.
Without it, `release.yml` cannot be called from a context that
doesn't have a release-event payload, and the chain breaks. With
it, `release.yml` is trigger-agnostic: anything that can name a
tag can drive it.

### `auto-release.yml` gains a `publish` job

Replaces the single monolithic `release` job with three:

- `determine` — parse conventional commits (unchanged).
- `commit-and-tag` — bump `package.json`, update CHANGELOG, commit,
  tag, push. **No longer creates a GitHub Release.**
- `publish` — `uses: forgesworn/anvil/.github/workflows/release.yml@v0`
  with the freshly-created tag passed in explicitly.

The self-reference `@v0` is a literal — GitHub Actions does not
allow expressions in reusable-workflow `uses:`. A consumer who
pins `auto-release.yml@v0` implicitly commits to `release.yml@v0`.
They travel as a pair. SHA-pinning one pins the other.

### `update-release.sh` gains create-or-update

Today's script runs `gh release edit` after publish, updating the
Release body with the CHANGELOG section and integrity block. The
script assumes a Release already exists — reasonable for the
manual flow where the release-event is the trigger.

In the chained flow no Release exists when `update-release.sh`
runs; `auto-release.yml` pushed a tag, then `release.yml` took
over. The script now probes with `gh release view` and branches:

- `view` succeeds → `gh release edit` (legacy path, unchanged).
- `view` fails → `gh release create` with `--target $GITHUB_SHA`.

The create branch stamps the same body — CHANGELOG section +
integrity block + verify recipe + tarball asset upload.

### `auto-release.yml` grows release-time inputs

Previously the consumer's own `release.yml` carried `node-version`,
`vector-test-command`, `audit-level`, etc. In the chained flow the
consumer no longer writes `release.yml` — they only write
`auto-release.yml`. So `auto-release.yml` plumbs those inputs
through to its chained `release.yml` call.

Inputs added: `node-version`, `test-command`, `vector-test-command`,
`audit-level`, `strict-action-pins`, `reproducibility-mode`,
`debug`. All default to the same values as `release.yml` itself.

Inputs deliberately omitted: `version-strategy` (auto-release *is*
the strategy; `verify` makes no sense inside auto), `registry-url`
(left on defaults for the MVP).

## Release ownership

The old design split Release ownership awkwardly: `auto-release.yml`
created the Release (for the trigger), `release.yml` edited the body
(for the CHANGELOG and integrity data). Two workflows touching one
object, coupled by event.

The new design gives the Release entirely to `release.yml`:
`update-release.sh` creates it after a successful publish or edits
it in-place for the legacy flow. One workflow owns the object.

This also means a failed publish no longer leaves a confusing
empty Release behind — in the chained flow, if gates fail, no
Release is created. The tag is pushed, which is a loud signal that
a publish was attempted; a maintainer can re-run the failed
`publish` job and the second attempt creates the Release
idempotently.

## OIDC and trusted publishing

No change. The reusable-workflow OIDC subject contains the **entry-point caller's** `workflow_ref` — the consumer's
`auto-release.yml`, not `forgesworn/anvil`'s internal `release.yml`.
npm's trusted-publisher row continues to point at the consumer's
caller file. Migration: if a consumer had trusted-publishing set up
against `release.yml`, they need to point it at `auto-release.yml`
when they move to the single-file pattern.

This is the biggest operational footgun in the migration. Call it
out loudly in the migration docs.

## Backwards compatibility

- **Consumers on `release.yml` with a `release: published` trigger:**
  nothing changes. `inputs.tag` defaults to `''`; the fallback chain
  lands on `github.event.release.tag_name` exactly as before.
- **Consumers on `auto-release.yml` with `GH_TOKEN`:** the chained
  flow ignores `GH_TOKEN`. The secret declaration is kept but
  marked deprecated. A PAT in a consumer repo is no longer load-
  bearing and can be rotated out. No code change is required on
  their side beyond bumping the pin.
- **Consumers on `auto-release.yml` without `GH_TOKEN`:** publish
  never worked for them. Now it does. Strict improvement.

## Risk edges

- **Tag already exists.** `commit-and-tag`'s `git tag` fails loudly
  on a re-run if someone manually tagged in between. Acceptable —
  the maintainer is always the source of truth on tag collisions.
- **Publish mid-fails after push.** Tag is on the remote, no
  Release exists, no npm publish. Maintainer re-runs the failed
  job. `publish-npm` is already idempotent; `update-release.sh`
  creates the missing Release on the second attempt. Better than
  today's failure mode.
- **Consumer has both a stale `release.yml` file and the new
  `auto-release.yml` in the same repo.** The stale `release.yml`
  triggered on `release: published` now never fires, because
  `auto-release.yml` no longer creates the Release up-front —
  the chained `release.yml` does, and that create event is
  `GITHUB_TOKEN`-authored so it is suppressed. One workflow run
  publishes, not two. Consumers should delete the stale file on
  migration but leaving it costs nothing.

## Known limitations

- The chained `release.yml` run inherits the outer run's six-hour
  timeout and total-jobs budget. For normal releases this is
  inconsequential (<10 minutes).
- Re-running the outer `auto-release.yml` re-runs the chained
  `release.yml`. Every step must be idempotent. They already are
  (publish-npm integrity check, update-release.sh view-or-edit-or-create).
- The self-reference `@v0` in `auto-release.yml`'s `uses:` is a
  literal — a consumer who wants to pilot a branch of anvil has to
  edit their local fork. This is a GitHub Actions constraint, not
  a design choice.

## What was considered and rejected

- **Keep the PAT.** Contradicts the zero-secret design posture.
- **GitHub App for token issuance.** Heavier setup than the tool it
  replaces; breaks the "under thirty minutes to audit the whole
  thing" constraint for consumers.
- **`workflow_dispatch` triggered from `auto-release`.** Same
  anti-recursion rule applies: `gh workflow run` from the default
  `GITHUB_TOKEN` is suppressed.
- **Move everything into one workflow file.** Tempting for
  simplicity, but `release.yml` still needs to be callable
  standalone for the manual flow. Separation of concerns wins.

## References

- GitHub Actions docs: events from `GITHUB_TOKEN` do not trigger
  workflows, <https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication>
- GitHub Actions reusable workflows: `workflow_call` is not an
  event trigger, <https://docs.github.com/en/actions/sharing-automations/reusing-workflows>
- npm trusted publishing: the `workflow_ref` claim points at the
  entry-point caller, <https://docs.npmjs.com/trusted-publishers>
