# Chained workflows (v0.8 design)

Status: **implemented in v0.8.0**.
Predecessors:
- v0.5.0 event-coupled auto-release + optional PAT (broken without PAT)
- v0.7.0 workflow_call chain (forced trusted-publisher reconfiguration)

## Why

`auto-release.yml` determines a bump from conventional commits and
tags a new release. `release.yml` runs the gates and publishes to
npm. The two need to be connected. Two bad connections, one good one:

### The event-coupling design (v0.5)

Auto-release ran `gh release create`. The release-published event
was supposed to fire `release.yml`. It didn't: GitHub's anti-
recursion rule suppresses workflow runs from events created by
the default `GITHUB_TOKEN`. The workaround was a PAT, which
contradicts the zero-secret design posture and added silent-failure
surprise ("nothing happened, why?") for anyone without one
configured.

### The workflow_call chain (v0.7)

Auto-release called `release.yml` directly via `uses:` — a
reusable-workflow chain, not an event. No PAT needed. But the OIDC
subject for npm trusted publishing comes from the **entry-point
caller's** `workflow_ref`, which in the chained flow is
`auto-release.yml`, not `release.yml`. Every consumer would have
had to reconfigure their trusted publisher on npmjs.com to point at
`auto-release.yml`. A 20-package migration ball-ache for no real
benefit.

### The workflow_dispatch bridge (v0.8)

Auto-release does bump + tag + push, then runs:

```sh
gh workflow run release.yml -f tag=v1.2.3
```

That fires the consumer's `release.yml` as a **separate workflow
run**. Crucially:

- `workflow_dispatch` is an **explicit exception** to the anti-
  recursion rule. The GitHub docs call this out: "events triggered
  by the `GITHUB_TOKEN`, with the exception of `workflow_dispatch`
  and `repository_dispatch`, will not create a new workflow run."
  So no PAT is needed.
- The OIDC subject is `release.yml` (the entry-point of the
  dispatched run). Existing trusted-publisher configuration keeps
  working with no change.

One human push to main → one auto-release run → one dispatched
release run. Two workflow runs visible in the Actions tab, but only
one of them requires human setup (trusted publisher on
`release.yml`, the same as manual mode).

## What the design actually is

```
  push to main
        │
        ▼
  auto-release.yml (run #1, fires on push)
        │
   ┌────┴─────────────────────────────────────┐
   │                                          │
   ▼                                          ▼
determine                                 commit-and-tag
(parse commits)                           (bump, commit, tag, push)
                                               │
                                               ▼
                                          dispatch-release
                                          (gh workflow run release.yml -f tag=vX.Y.Z)
                                               │
                                               ▼  (workflow_dispatch event,
                                                   not suppressed)
  release.yml (run #2, fires on workflow_dispatch)
        │
   ┌────┴─────────────────────────────────────┐
   │                                          │
   ▼                                          ▼
release (uses: forgesworn/anvil/.github/workflows/release.yml@v0)
        │
 ┌──────┴──────┬──────────┐
 │             │          │
 ▼             ▼          ▼
build-a    build-b    reproduce
                          │
                          ▼
                       publish (npm + GH Release create)
```

Two runs, clean separation. The manual flow is unchanged: a human
creates a GitHub Release, that event fires `release.yml` directly.
The auto flow just dispatches the same entry point.

## Consumer-side contract

The consumer writes two files:

```yaml
# .github/workflows/auto-release.yml
name: auto-release
on:
  push:
    branches: [main]
permissions:
  contents: write
  actions: write            # required to dispatch
jobs:
  auto-release:
    uses: forgesworn/anvil/.github/workflows/auto-release.yml@v0
```

```yaml
# .github/workflows/release.yml
name: release
on:
  release:
    types: [published]       # manual flow: human creates Release
  workflow_dispatch:         # auto flow: auto-release dispatches
    inputs:
      tag:
        description: Release tag to publish (e.g. v1.2.3)
        type: string
        required: true
permissions:
  contents: write
  id-token: write
jobs:
  release:
    uses: forgesworn/anvil/.github/workflows/release.yml@v0
    with:
      tag: ${{ inputs.tag || '' }}
      vector-test-command: npm run test:vectors  # optional
```

The `workflow_dispatch` trigger with a `tag` input is the new
requirement. `release.yml` was already trigger-agnostic as of v0.7
(accepts `tag` input, falls back to `github.event.release.tag_name`).

## What changed from v0.7 to v0.8

- `auto-release.yml` replaces its `publish` workflow_call job with
  a `dispatch-release` job that shells `gh workflow run`.
- `auto-release.yml` drops the release-time input plumbing
  (`node-version`, `vector-test-command`, `audit-level`,
  `strict-action-pins`, `reproducibility-mode`, `debug`,
  `test-command`). Those live on the consumer's `release.yml`
  again — one source of truth for release config.
- `auto-release.yml` gains a `release-workflow` input (default
  `release.yml`) for consumers with a differently-named workflow.
- `auto-release.yml` caller needs `permissions: actions: write` to
  dispatch workflows.
- Consumer `release.yml` needs a `workflow_dispatch` trigger with
  a `tag` input. Pre-existing consumers who trigger only on
  `release: published` continue to work for manual releases but
  won't receive auto-dispatches until they add the trigger.

## Release ownership

`release.yml` still owns the GitHub Release object via
`update-release.sh` create-or-update (from v0.6). Auto-release
no longer touches the Release at all — it only pushes a tag and
kicks off the dispatch. When `release.yml` publishes
successfully, `update-release.sh` creates the Release with the
CHANGELOG body and integrity block. If `release.yml` fails,
no Release is created; a maintainer can re-run it manually, and
the second attempt creates the Release idempotently.

## OIDC and trusted publishing

Unchanged from pre-chain behaviour. The OIDC subject is
`release.yml`. `npm`'s trusted-publisher row continues to point at
the consumer's `release.yml`. No migration required.

This is the entire point of the workflow_dispatch design.

## Backwards compatibility

- **Consumers on v0.5 auto-release + PAT**: the `GH_TOKEN` secret
  is still accepted and silently ignored. PAT can be rotated out.
- **Consumers on v0.6 manual release**: no change.
- **Consumers on v0.7 chained auto-release**: the workflow_call
  chain is removed in v0.8. They must add the `workflow_dispatch`
  trigger + `tag` input to their `release.yml`. Trusted publisher
  can stay pointed at `release.yml` (they never needed to move it
  if they skipped v0.7).
- **New consumers**: two-file setup, no trusted-publisher quirks.

## Risk edges

- **Tag already exists.** `commit-and-tag`'s `git tag` fails loudly.
  Acceptable — maintainer collision on tagging.
- **Dispatch fires, release.yml fails gates.** Tag is on the remote,
  no GitHub Release, no npm publish. Maintainer re-runs the failed
  `release.yml` run via the Actions UI. `publish-npm` is
  idempotent; `update-release.sh` creates the Release on retry.
- **Consumer's `release.yml` doesn't have workflow_dispatch yet.**
  `gh workflow run` fails with a 422. Auto-release's
  dispatch-release job fails. Tag is already pushed, so the bump
  is real; the maintainer can create a GitHub Release manually
  via the web UI to fire `release.yml` via `release: published`.
  A graceful degradation rather than silent failure.
- **Two workflow runs for one release.** Visible in the Actions
  tab. Clearer than a single mega-run because failure boundaries
  are obvious: bump-and-tag is separate from gates-and-publish.

## Known limitations

- Dispatch is fire-and-forget. `auto-release.yml` completes once
  `gh workflow run` returns (usually within seconds); it does not
  wait for `release.yml` to finish. Monitor `release.yml` in the
  Actions UI. This is deliberate — coupling the two into one run
  is how we got the v0.7 design, and we don't want to go back.
- `gh workflow run` requires `actions: write` permission on the
  caller workflow. Documented in the consumer template above.
- The dispatched `release.yml` runs at the newly-pushed tag ref
  (via `--ref "$TAG"`). If the consumer's `release.yml` does
  anything tag-relative (e.g. checks out `github.ref` without
  falling back to the tag input), it may need adjustment. The
  standard anvil caller pattern already handles this.

## What was considered and rejected

- **Keep the PAT (v0.5).** Zero-secret design violated.
- **workflow_call chain (v0.7).** OIDC subject migration burden
  per consumer. Rejected in favour of preserving the existing
  trusted-publisher configuration.
- **Move everything into one workflow file.** `release.yml` must
  remain callable standalone for the manual flow. Separation of
  concerns is load-bearing.

## References

- GitHub Actions: events from `GITHUB_TOKEN` do not trigger
  workflows, <https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication>
  (note the workflow_dispatch / repository_dispatch exceptions)
- `gh workflow run` reference,
  <https://cli.github.com/manual/gh_workflow_run>
- npm trusted publishing: `workflow_ref` claim points at the
  entry-point caller, <https://docs.npmjs.com/trusted-publishers>
