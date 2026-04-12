# Security policy

## Reporting a vulnerability

Security issues in the action itself should be reported via
[GitHub Security Advisories](https://github.com/forgesworn/anvil/security/advisories/new)
at this repo. Do not use the public issue tracker for security reports.

You should receive an initial response within 72 hours. If the issue
is confirmed, a fix will be prioritised over feature work and released
as a patch version (e.g. v0.4.1 for a fix against v0.4.0).

## Scope

The action's security contract is documented in
[THREAT-MODEL.md](THREAT-MODEL.md), which lists what the action
defends against, what it explicitly does not, and the trust boundaries.
A report is in scope if it describes a way to bypass one of the
documented defences or exploit a trust boundary.

## Supported versions

Only the latest minor release on the v0.x series receives security
fixes. Pin to `@v0` (the floating major tag) to receive them
automatically.
