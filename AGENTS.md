# Agent instructions

This repo uses `CLAUDE.md` as the canonical agent-facing instruction
file. Any coding agent (Claude Code, Cursor, Copilot, Gemini, Codex)
should read it before making changes:

- [`CLAUDE.md`](CLAUDE.md) — architecture, constraints, audit budget,
  conventions, non-goals.

Key points that apply to any agent:

- **Audit budget.** Total bash across `steps/*.sh` must stay under
  ~1600 lines so the whole action remains auditable in thirty minutes.
  Check `wc -l steps/*.sh` before adding code.
- **Zero dependencies.** No npm packages, no compiled binaries, no
  fetched tooling. Only tools already on the GitHub Actions runner
  image (bash, jq, gh, npm, shasum, awk, sed, find, grep).
- **Threat model is load-bearing.** [`THREAT-MODEL.md`](THREAT-MODEL.md)
  documents the defended and explicitly-undefended surfaces. Any change
  that expands the attack surface must update the threat model first.
- **British English** throughout (`LICENCE`, "normalise", "optimise").
- **Commit style**: `type: description` (lowercase, imperative). No
  `Co-Authored-By` trailers.

For tests and linting:

```sh
bats test/*.bats           # full test suite
shellcheck -x steps/*.sh   # lint step scripts
```

Everything agent-specific lives in `CLAUDE.md`. This file exists so
non-Claude agents discover the same constraints without having to
infer them from the repo's conventions.
