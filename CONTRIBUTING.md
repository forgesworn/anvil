# Contributing

This action is deliberately small. The total bash surface area must
stay under the thirty-minute audit budget (~1600 lines today). Before
adding a feature, ask whether it fits within the trust boundaries in
[THREAT-MODEL.md](THREAT-MODEL.md) and whether the audit budget still
holds after the addition.

## Development

Prerequisites: `bash`, `jq`, `npm`, `gh`, `shellcheck`, `bats`.

```sh
# Run the full test suite (71 tests)
bats test/*.bats

# Lint all step scripts
shellcheck -x steps/*.sh
```

## Non-goals

- Automated commit analysis or semver determination from commit messages
- Changelog generation as a release-blocking step
- Node-based tooling inside the action itself
- Dependencies that are not already on the default GitHub Actions runner image

## Commit style

`type: description` (lowercase, imperative). No `Co-Authored-By`.

## Reporting vulnerabilities

Security issues should be reported via GitHub Security Advisories at
this repo, not the public issue tracker. See [SECURITY.md](SECURITY.md).
Non-security bugs go to the regular issue tracker.
