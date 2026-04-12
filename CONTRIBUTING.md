# Contributing

This action is deliberately small. The total bash surface area must
stay under the thirty-minute audit budget (~1600 lines today). Before
adding a feature, ask whether it fits within the trust boundaries in
[THREAT-MODEL.md](THREAT-MODEL.md) and whether the audit budget still
holds after the addition.

## Development

Prerequisites: `bash`, `jq`, `npm`, `gh`, `shellcheck`, `bats`.

```sh
# Run the full test suite
bats test/*.bats

# Lint all step scripts
shellcheck -x steps/*.sh
```

## Pull requests

1. Branch from `main`. Name the branch `type/short-description`
   (e.g. `fix/verify-exports-windows`, `feat/gate-for-banned-licences`).
2. Write a bats test first when adding or changing gate behaviour.
   Every step script has a matching `test/<name>.bats` fixture.
3. Commit style: `type: description` (lowercase, imperative). No
   `Co-Authored-By`. Examples: `fix: handle empty exports map`,
   `docs: clarify JSR_TOKEN scope`.
4. Run `bats test/*.bats` and `shellcheck -x steps/*.sh` locally
   before pushing. CI runs the same checks.
5. Open the PR against `main`. Keep the description short -- link to
   the relevant THREAT-MODEL entry if the change affects a gate, and
   mention the line-count delta if the change is non-trivial (the
   thirty-minute audit budget is a hard constraint).
6. A solo maintainer reviews and merges. Expect feedback within a day
   or two; longer for design-impacting changes.

## Proposing larger changes

For anything that adds a new gate, changes a trust boundary, or grows
the line count by more than ~50 lines, open an issue first with the
proposed design. The audit budget means every addition has to earn
its place; discussing the shape before writing the code saves everyone
time.

## Non-goals

- Automated commit analysis or semver determination from commit messages
  as a release-blocking step (the `auto-release.yml` companion workflow
  handles this outside the gate pipeline)
- Changelog generation as a release-blocking step
- Node-based tooling inside the action itself
- Dependencies that are not already on the default GitHub Actions runner image

## Reporting vulnerabilities

Security issues should be reported via GitHub Security Advisories at
this repo, not the public issue tracker. See [SECURITY.md](SECURITY.md).
Non-security bugs go to the regular issue tracker.
