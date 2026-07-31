# SPEC — an undefined assertion helper is indistinguishable from a passing assertion

Source: GitHub issue #310

## Objectives

1. Sweep every harness file for the helpers it defines and the helpers it calls, and report every
   call to a helper the file does not define — deriving the population rather than assuming the two
   files ADR-0081 touched are the only ones.
2. Make a call to an undefined helper fail the suite loudly in every harness file, instead of
   printing "command not found" while the suite reports a clean pass and exits 0.
3. Give each harness file an assertion-count floor, so a vanished assertion is visible rather than
   silently reducing the reported total.

## Scope

In: the `*.test.sh` harness files under `staging/plugin/scripts/tests/`; the `ok()`/`bad()` (and any
sibling) assertion-helper convention; the failure behaviour when such a helper is called but not
defined; per-file assertion-count floors.

Out: changing what any individual assertion checks; introducing a shared helper library across the
harness files (ADR-0086 decided the derived-guard pattern stays as deliberate per-file copies and
gave correlated failure as the reason); the skill-private, `$HOME`-coupled harnesses that are
CI-dark by construction, except insofar as the sweep must decide whether they are in the population.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/scripts/tests/*.test.sh` — the harness population. `staging/plugin/scripts/tests/`
  also holds non-`*.test.sh` members (`plant-check.sh`, `run-hook-tests.sh`, and the two legacy
  `$HOME`-coupled hook tests vendored out of the glob by ADR-0024); the sweep must decide explicitly
  which of these are in the population rather than inheriting the glob by accident.
- `staging/plugin/scripts/tests/pairs-completeness.test.sh` — the file ADR-0081 found without
  `ok()`/`bad()` helpers, where six assertions printed "command not found" and the suite still
  reported `PASS=244 FAIL=0`. Both helpers are now defined there with that history written above
  them.
- `docs/architecture/ADR-0081-213-212-false-green-and-zone-anomalies.md` — the source, and the same
  false-green class it fixed in `docs/RUNBOOK.md`'s agent-validation loop one level out.
- `.claude/test-cmd` — the command that runs the harness; and `.github/workflows/` for the `ci` job
  that invokes the files one by one.
- `staging/plugin/scripts/tests/plant-check.sh` and the plant registry (ADR-0108) — R-03's planted
  call to an undefined helper is declared there beside its assertion.
- Existing per-file assertion-count floors named `Z1` exist in at least
  `plan-task-count.test.sh`, `scope-guards.test.sh` and `fence-contract-coverage.test.sh` (ADR-0083
  §D3); those are the precedent for R-02's floor, including its shape as a floor rather than an
  exact count.

## Data model

None. The sweep's working data is, per harness file, the set of helper names defined and the set
called; no persistent record is implied by the issue.

## API / Interfaces

- A sweep over the harness population reporting each call to a helper the calling file does not
  define. Contract per the repository's standing rule: a checker branches on an exit code and
  distinguishes "did not run" (exit 3) from "found nothing"; a reporter always exits 0 and signals
  on stdout.
- The harness-file convention itself: `ok()` / `bad()` and any siblings the sweep discovers, plus
  whatever mechanism makes an undefined-helper call fail loudly (nothing in these files runs under
  `set -e` today, which is the enabling condition).
- Per-file assertion-count floor assertions, in the `Z1` shape already used in three files.

## UI flows

None. Output is harness text read in a terminal or in the CI log.

## Edge cases

- A helper defined conditionally, or defined after its first call, so a static "defines" set
  disagrees with runtime availability.
- A helper name that is also a real command on `PATH`: the call succeeds, silently, doing something
  entirely different — a false green with no "command not found" line at all.
- A helper legitimately provided by a sourced file rather than defined inline, if any harness file
  does this.
- A file with genuinely zero assertions, versus a file whose assertions all vanished: R-02 exists
  because a suite reporting fewer assertions does not read as broken and nobody watches the count.
- The sweep's own denominator: a glob that stops resolving reports zero offending calls, which is
  indistinguishable from full compliance — the derivation needs its own count guard (ADR-0085's
  rule: guard the denominator, not the matches).
- Rule 12 applies to the sweep's needles: a needle that is the NAME of a helper will match the prose
  and comments in files that legitimately discuss `ok()`/`bad()`, including this feature's own.

## Success criteria

- [ ] R-01 — a call to an undefined helper fails the suite loudly in every harness file.
- [ ] R-02 — an assertion-count floor exists per file so a vanished assertion is visible; a suite
      reporting fewer assertions does not read as broken and nobody watches the count.
- [ ] R-03 — seen RED against a planted call to an undefined helper.
