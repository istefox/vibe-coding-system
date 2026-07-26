# Implementation plan — #108 Deterministic checks in the target project CI

- **ADR:** `docs/architecture/ADR-0054-108-project-ci-deterministic-checks.md`
- **SPEC:** `SPEC.md` / `docs/specs/108-project-ci-deterministic-checks.spec.md`
- **Branch:** `feat/108-project-ci-deterministic-checks` (stacked on `feat/107-interface-immutability-gate`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**No existing script may be modified.** The whole design rests on the reporters staying reporters
(ADR-0054 §D1). If you find yourself editing `secret-scan.sh` to exit non-zero, stop — that breaks
every hook call site to serve this one.

## Task checklist

- [x] **Task 1 — RED harness.** `staging/plugin/scripts/tests/project-ci-checks.test.sh`.
  `C`-prefixed labels, hermetic, bash 3.2. Sections: **CA** the `checks` job exists in
  `staging/project-templates/ci/ci.yml`, is a **separate job** from `ci` (§D2), and each gate step
  is present; **CB** the fail-closed/print-only split of §D5 is exactly as specified — `SECRET`,
  `WEAKENED` and `interface-check.sh` exit 3 fail the build; `SUSPECT` and dependency notes print
  only; **CC** every step is `[ -x … ]`-guarded and prints a **skip notice** when the script is
  absent (§D4) — assert the notice text, not just the guard, because a silent skip and a pass look
  identical; **CD** `vendor-checks.sh` copies the expected script set and is idempotent; **CE** no
  existing script was modified — assert `secret-scan.sh`, `dependency-scan.sh`, `weakening-scan.sh`
  and `interface-check.sh` still exit 0 / keep their contracts (this is the guard for the plan's
  headline constraint); **CF** the reporter trap is restated at each reporter call site and the
  checker branches on exit code (§D6); **CG** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — note `protect-files.sh` denies any path containing `secrets` (ADR-0046).

- [x] **Task 2 — the `checks` job.** Extend `staging/project-templates/ci/ci.yml` with a `checks`
  job, separate from `ci` (§D2), running the diff-scoped gates against the PR diff. Needs a base ref
  and therefore a `fetch-depth` adjustment on the checkout — `dependency-scan.sh`'s existing
  base-ref/merge-base pattern in that file is the one to follow. `interface-check.sh` already has a
  step there from #107; move or reconcile it into the new job rather than duplicating it, and pass
  `--no-renames` (ADR-0053 requires it). → CA/CB/CF green.

- [x] **Task 3 — skip notices.** Every gate step `[ -x … ]`-guarded, printing a visible skip notice
  naming `vendor-checks.sh` as the remedy when the script is absent (§D4). → CC green.

- [x] **Task 4 — `vendor-checks.sh`.** Copies the current check scripts into a target repo's
  `.claude/scripts/`. Idempotent, shows what it will overwrite before overwriting (the house rule:
  never overwrite an existing file without showing the diff first), and records the source revision
  so a stale copy is identifiable. Decide where it lives and register it in `PAIRS` following the
  nearest sibling. → CD green.

- [x] **Task 5 — documentation.** Say in the template header and in the RUNBOOK that vendoring is a
  deliberate manual step, that the copies drift, and how to refresh them. This feature does nothing
  on merge day; the docs are what make that a known state rather than a surprise.

- [x] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `interface-immutability`). Then run every `staging/plugin/scripts/tests/*.test.sh`. **CE is the
  regression that matters** — `secret-dep-gate.test.sh`, `weakening-wiring.test.sh`,
  `reward-hack-detectors.test.sh` and `interface-immutability.test.sh` all cover scripts this
  feature must not touch. Report anything already failing separately from anything newly caused.
  → CG green.

## Risk flags

1. **Editing a script to make CI fail-closed.** The single most likely wrong turn, and it would
   break every hook. CE pins the constraint.
2. **A skip that looks like a pass.** ADR-0043, ADR-0044 and ADR-0046 each hit a variant of this.
   CC asserts the notice text, not just the guard.
3. **Vendored drift** is real and unfixed by design (§D3). Do not paper over it with an
   auto-updater; say it in the docs.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
