# Reproducible-build attestation (v0.4 design)

Status: **implemented in v0.4.0**.
Predecessor: v0.3.0 single-runner integrity anchor (`record-tarball.sh`).

## Why

v0.3.0 stamps a sha256 of the tarball into the GitHub Release body so
consumers can verify the **registry tarball** matches the **bytes CI
built**. That is a single-runner integrity anchor: the bytes are what
this one runner produced.

What v0.3 does **not** prove is that the build is deterministic. Two
runners building the same commit could produce two different sha256s
today, because tar headers carry timestamps and some build pipelines
leak absolute paths or other host-specific data into compiled output.

For any library where consumers need to trust the output, "did the
registry serve the bytes CI built" is the floor, not the ceiling. The
ceiling is "the bytes CI built are the only bytes a clean build of
this commit could have produced". That is reproducibility, and no
mainstream JS release tool offers it today.

This is the v0.4 flagship.

## What "reproducible" means here

A release is **reproducible** if two independent builds of the same
commit produce two byte-identical tarballs. "Byte-identical" means
sha256-equal. "Independent" means two separate GH Actions runners.

The check we implement is empirical, not formal: we run the build
twice and compare. If the hashes match, the release is published. If
they don't, the release fails and the maintainer is told what to
investigate.

This catches:

- Embedded `Date.now()` / `__BUILD_TIMESTAMP__`-style values in
  compiled output
- Non-deterministic minifier output ordering
- Sorted-by-filesystem-order globs that depend on inode order
- Build-tool tmp-dir paths leaking into source maps
- Random salt/UUID generation in build scripts

It does **not** catch:

- Non-determinism that needs more than two runs to surface (probabilistic)
- Non-determinism between operating systems we don't run on (we run
  ubuntu-24.04 only; cross-OS reproducibility is a stronger claim and
  out of scope for v0.4)
- Determinism violations that happen at install time (`npm ci` running
  postinstall scripts that fetch network resources non-deterministically)

The honest one-line claim for the README:

> "Two independent CI builds of this commit produced byte-identical
> output. Reproducibility across operating systems is not claimed."

## Architecture

The reusable workflow `release.yml` becomes a multi-job DAG:

```
            ┌──────────────┐
            │  build-A     │  ubuntu-24.04
            │  (record)    │  uploads tarball.meta + tarball.tgz as
            └──────┬───────┘  artifact "tarball-A"
                   │
            ┌──────▼───────┐
            │  build-B     │  ubuntu-24.04
            │  (record)    │  uploads tarball.meta + tarball.tgz as
            └──────┬───────┘  artifact "tarball-B"
                   │
            ┌──────▼───────┐
            │  reproduce   │  downloads both, compares sha256
            │  (gate)      │  fails if they diverge
            └──────┬───────┘
                   │
            ┌──────▼───────┐
            │  publish     │  needs id-token: write
            │              │  downloads tarball-A (canonical),
            │              │  publishes that exact file,
            │              │  updates GH Release with the integrity
            │              │  block plus a "reproducible" badge line
            └──────────────┘
```

Decisions:

- **Two parallel jobs, not sequential.** Saves wall-clock time and
  exercises true runner diversity. Sequential same-runner builds would
  miss host-pinned non-determinism.
- **Same image type (`ubuntu-24.04`) for both.** Cross-OS adds a much
  bigger correctness burden on consumers and is the wrong default.
  v0.5 could add an opt-in `cross-os` mode.
- **`build-A` is canonical.** The publish job uploads the tarball
  produced by `build-A`. We could pick either; consistency matters
  more than which one.
- **All gates run inside `build-A`** (verify-tag, run-tests,
  verify-vectors, verify-audit, verify-exports, verify-secrets,
  verify-action-pins). `build-B` runs only the build itself plus
  `record-tarball`. Running gates twice would double their wall-clock
  for no information gain — gate output is deterministic by
  construction.

## SOURCE_DATE_EPOCH and mtime normalisation

For two builds to be byte-equal, every file mtime in the resulting
tarball must be identical between runs. Two layers of defence:

1. **Set `SOURCE_DATE_EPOCH` from the git commit time of HEAD.** This
   is the standard reproducible-builds convention. Any build tool that
   honours it (most modern ones do) uses this as the timestamp source
   for embedded dates and tar headers.

   ```sh
   export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
   ```

   Set in the `env:` block of the build jobs so every step inherits
   it.

2. **Explicitly normalise mtimes before packing.** Belt-and-braces:
   not all of `npm ci`, `npm run build`, and `npm pack` honour
   `SOURCE_DATE_EPOCH` cleanly. Before `record-tarball` runs, walk the
   pack set and `touch -d @$SOURCE_DATE_EPOCH` every file. This makes
   the tar headers byte-identical regardless of whether the build
   tools cooperated.

   Implementation: a small helper, `steps/normalise-mtimes.sh`, that
   reads the `files` array from `package.json` and touches each path.
   ~25 lines.

A consumer whose build script writes `Date.now()` into the bundle is
still going to fail reproducibility — mtime normalisation only fixes
file timestamps, not embedded build-time strings. That is correctly
the consumer's bug to fix, and the failure message will tell them so.

## New script: `compare-tarball-meta.sh`

Runs in the `reproduce` job after both `tarball-A` and `tarball-B`
artifacts have been downloaded. Compares the `sha256=` and
`integrity=` lines from both meta files. If both match, exits 0. If
either differs, prints both hashes, prints the diff between the two
tar listings (`tar -tvf A.tgz` vs `tar -tvf B.tgz`) so the maintainer
can see which file's mtime or content drifted, and exits 1.

~60 lines of bash.

## New input: `reproducibility-mode`

Three values:

| Value | Behaviour |
|---|---|
| `strict` (default from v0.4) | Two builds must match. Mismatch fails the release. |
| `warn` | Two builds run, hashes are recorded, but a mismatch only emits a GH Actions warning annotation. The publish proceeds with the `build-A` tarball. |
| `off` | Skip `build-B` and `reproduce` jobs entirely. Behaves like v0.3 single-runner mode. |

`warn` is the migration mode for libraries that want to start tracking
reproducibility without blocking releases on it. `off` is the escape
hatch for libraries that genuinely cannot be made reproducible (rare;
should be treated as a code smell).

## The composite action stays single-job

The composite action (`action.yml`) cannot define a multi-job
structure — composite actions are a flat list of steps inside one job.
The reproducibility flow is **reusable-workflow only**.

The composite action continues to behave like v0.3: single runner,
single build, single integrity anchor. Documented in README as the
"power-user escape hatch". Consumers who want the reproducibility
guarantee must use the reusable workflow (which we already document
as the primary path).

This is also a forcing function: if a consumer adopts the composite
action, they get strictly weaker guarantees, and the README should
say so.

## Migration for consumers

### Already on v0.3 reusable workflow

Bumping the pin to `@v0.4.0` enables `reproducibility-mode: strict` by
default. Most well-behaved JS builds are accidentally reproducible —
the common failure modes are timestamps and sorted-by-fs paths, both
of which v0.4's mtime normalisation handles for free. Libraries with
`Date.now()` / `__VERSION__`-style build-time injection need to fix
their build before the upgrade lands.

A safer migration path:

```yaml
with:
  vector-test-command: npm run test:vectors
  reproducibility-mode: warn   # log mismatches without blocking
```

After a couple of green releases under `warn`, flip to `strict` (or
remove the input to take the default).

### Already on v0.3 composite action

No change. Composite action stays at v0.3 semantics.

## Failure UX

When `compare-tarball-meta.sh` finds a mismatch, the GH Actions
annotation should look like:

```
::error title=reproduce::tarball hashes diverged between two independent builds
build-A sha256: 9a5e...e7c1
build-B sha256: 4f12...a8d3

Common causes:
  - Date.now() or build timestamp embedded in compiled output
  - Sorted-by-filesystem-order globs
  - Random IDs in build scripts (UUIDs, salts)

To investigate, download both tarball artifacts and run:
  diff <(tar -tvf tarball-A.tgz) <(tar -tvf tarball-B.tgz)

To temporarily allow non-reproducible releases, set
reproducibility-mode: warn in your caller workflow's `with:` block.
```

The message itself is the diagnostic. Consumers should not have to
read source code to understand why their release failed.

## Known limitations

1. **Single OS only.** Two ubuntu-24.04 runners catch a meaningful
   chunk of host-pinned non-determinism but not OS-pinned drift.
   Cross-OS reproducibility is a stronger claim that adds a
   correctness burden on consumers (their build must work on multiple
   OSes); v0.5 territory.
2. **Two-run sample size.** A non-determinism source that fires
   probabilistically (e.g. one-in-a-thousand) won't reliably show up
   in two runs. We accept this as the cost of CI minutes; the
   alternative is N runs and the marginal value drops fast.
3. **`SOURCE_DATE_EPOCH` is opt-in for build tools.** We can't force
   `esbuild`/`rollup`/`webpack`/`tsc` to honour it. Belt-and-braces
   mtime normalisation closes the file-stamp gap, but embedded
   timestamps inside compiled output are still the consumer's problem.
4. **Doubles CI minutes.** Two parallel build jobs use 2× the
   compute. For OSS GitHub repos this is free; for private repos on
   the GH free tier it consumes more of the monthly budget.

## Implementation plan

In sequence (no point parallelising — each step depends on the
previous having a stable shape):

1. **`steps/normalise-mtimes.sh`** — read `files` from package.json,
   touch every file to `@$SOURCE_DATE_EPOCH`. Bats tests: empty pack
   set, missing package.json, scoped paths.
2. **`steps/compare-tarball-meta.sh`** — diff two `tarball.meta`
   files, fail with the rich error message above. Bats tests: equal
   metas pass, diverged sha256 fails, missing meta files fail
   gracefully.
3. **Modify `record-tarball.sh`** to set/honour `SOURCE_DATE_EPOCH`
   from git when not already set, and to call `normalise-mtimes.sh`
   before packing. Update the existing bats tests; add a new test
   that two consecutive packs of the same fixture produce identical
   sha256s.
4. **Restructure `.github/workflows/release.yml`** into the four-job
   DAG above. Plumb the `reproducibility-mode` input. Wire up
   artifact upload/download. SHA-pin `actions/upload-artifact` and
   `actions/download-artifact`.
5. **`action.yml`** unchanged in shape, but add a paragraph in its
   `description:` noting that the composite action does not include
   the reproducibility check.
6. **README.md** gets a new top-level section on reproducibility
   replacing the v0.3 "Artefact integrity" section as the headline
   feature, with the v0.3 single-runner anchor demoted to a sub-bullet.
7. **THREAT-MODEL.md** gains a new defended threat row
   ("non-deterministic build masking a regression in compiled
   output") and removes the "single-runner SHA is not a
   reproducibility proof" limitation paragraph (replaced with the
   new, stronger claim and its narrower limitations).
8. **`docs/migration-from-v0.3.md`** for the upgrade story, including
   the `reproducibility-mode: warn` middle path.

Estimated bash growth: 200-300 lines across the new scripts and
modifications. Total step-script lines after v0.4: ~1300, still well
inside the thirty-minute audit budget.

## Open questions

1. **Do we keep the composite action at all?** Once the reusable
   workflow has the flagship feature, the composite action becomes a
   strictly inferior option. Removing it would simplify the README
   and the threat model. Counter-argument: some consumers want
   custom job structure (extra pre-flight steps, matrix testing
   before release) and the composite is the only escape hatch.
   **Tentative answer**: keep, but add a prominent note in
   `action.yml` description and README explaining the trade-off.

2. **Should `reproducibility-mode: strict` be the default from v0.4
   or only from v1.0?** Strict-by-default in v0.x is the v0-series
   design philosophy ("the gate set may shift in response to pilot
   feedback"). But it would break any existing v0.3 consumer whose
   build is non-reproducible. **Tentative answer**: ship with default
   `strict` because there's only one consumer (forgesworn libraries)
   and we control them. If we ever onboard external consumers on
   v0.3, revisit before v0.4 cuts.

3. **Should the publish job upload the tarball as a release asset?**
   Currently we just stamp hashes into the body. Uploading the
   tarball itself to the GH Release as a downloadable asset would
   give consumers a second source for the bytes (registry +
   GH Releases) and let them cross-verify against both. Probably
   yes, very small additional cost, ~10 lines in `update-release.sh`.
   **Tentative answer**: yes, ship in v0.4.
