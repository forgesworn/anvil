<!--
Thanks for contributing. Keep the description short; link to relevant
THREAT-MODEL entries if this changes a gate.
-->

## What

<!-- One or two sentences on what this PR does. -->

## Why

<!-- The motivation. Link to an issue if one exists. -->

## Notes

<!-- Anything a reviewer should know. Delete the checklist lines that
     don't apply. -->

- [ ] Tests added / updated (`test/*.bats`)
- [ ] `bats test/*.bats` passes locally
- [ ] `shellcheck -x steps/*.sh` clean
- [ ] No new runtime dependencies outside the GitHub Actions runner image
- [ ] Audit-budget impact acceptable (line-count delta noted if > ~50 lines)
- [ ] THREAT-MODEL.md updated if this changes a gate boundary
