# SPEC — thirteen skill-private test runners exercise the deployed copy and are dark to CI

Source: GitHub issue #308

## Objectives
1. Enumerate and count the skill-private test runners that resolve `SKILL_DIR="$HOME/.claude/skills/…"`
   — "thirteen" is a figure carried across four separate dates and must be re-derived — and for each
   one report what it would take to point it at `staging/`: some resolve a single variable, some
   assume deployed-only fixtures. Report the split rather than assuming uniformity.
2. Point each runner at `staging/`, or declare with a reason the ones that genuinely cannot, and get
   each of them running in CI so a change to a skill is covered by that skill's own suite.
3. Add a derived guard that fails when a runner resolves `$HOME` for anything other than a
   deliberate deployed-state check, with a count guard on the derivation.

## Scope
In: the `staging/plugin/skills/*/tests/` runners and any sibling test scripts under those directories
that resolve `$HOME`; their root-resolution logic and fixtures; their invocation from CI; a derived
guard over the population with a denominator count guard; declared reasons for any runner that must
stay deployed-facing.

Out: changing what any skill does. The skills themselves (`SKILL.md`, `scripts/`) are not modified
by this feature except where a test's fixture assumption forces it. The main `*.test.sh` harness
under `staging/plugin/scripts/tests/` is not restructured — those files are already hermetic and
already run in CI. `~/.claude` is not modified; the deployed tree is only ever read.

## Stack
Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture
Runners matching `staging/plugin/skills/*/tests/run-tests.sh` today (eleven by that glob, against
the issue's figure of thirteen — the discrepancy is what R-01's enumeration must resolve):
`autopilot-build`, `claude-md-slim`, `clean-public-repo`, `concept-to-code`, `deep-refactor`,
`design-brainstorm`, `humanize-en`, `nightly-autopilot`, `refactor-snapshot`, `review-triage-fix`,
`vibe-status`.

Sibling test scripts under the same trees that also reference `$HOME/.claude/skills` and belong in
the enumeration: `staging/plugin/skills/concept-to-code/tests/agent-notes-roundtrip.sh`,
`staging/plugin/skills/concept-to-code/tests/smoke-e2e.sh`,
`staging/plugin/skills/deep-refactor/tests/enumerate-sources.test.sh`.

Supporting files:
- `.claude/test-cmd` — `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`;
  the glob that structurally excludes every skill-private runner.
- `.github/workflows/ci.yml` (runs the same glob) and `.github/workflows/docs-ci.yml` (names
  individual test files and runs `plant-check.sh` last and separately) — the two places a
  skill-private suite would have to be invoked to stop being CI-dark.
- `staging/plugin/scripts/tests/transcript-scan-rule.test.sh` and
  `staging/plugin/scripts/tests/skill-coverage-perimeter.test.sh` — the derived-guard precedents,
  for the population/waiver/count-guard shape the new guard should follow.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry.
- `docs/architecture/ADR-0032-36-claude-md-slim-union-check.md`,
  `docs/architecture/ADR-0044-57-global-duplicate-union-check.md`,
  `docs/architecture/ADR-0093-232-macos-detection-false-positives.md`,
  `docs/architecture/ADR-0098-227-gate0-recommendation.md` — the four prior disclosures; the line
  numbers in the issue's source list will have moved. ADR-0044 records the occasion one of these
  suites actively misled a verification step; ADR-0093 re-homed four `detect-macos` assertions out
  of `concept-to-code/tests/run-tests.sh` into a CI-runnable harness while leaving the original file
  byte-untouched, which is the precedent for a partial migration.
- `docs/architecture/ADR-0024-28-vendor-deployed-only-skills-and-hooks.md` — records the legacy
  `$HOME`-coupled hook tests kept deliberately outside the `*.test.sh` glob and CI, which is the
  precedent for a declared deployed-facing exception.
- `docs/architecture/ADR-0084-211-skill-coverage-perimeter.md` — the standing refusal to make the
  harness depend on deploy state, which bounds how far R-02 can go.

## Data model
None. The relevant artifacts are each runner's root-resolution expression (today
`SKILL_DIR="$HOME/.claude/skills/<name>"`, to become a `staging/`-relative resolution, typically
from `$(dirname "$0")`), and — for any runner that must stay deployed-facing — a one-line declared
reason in the runner's own source, following the repository's existing waiver conventions.

## API / Interfaces
- Each runner's entry point: `bash staging/plugin/skills/<name>/tests/run-tests.sh`, reporting
  `PASS`/`FAIL` lines and a non-zero exit on failure.
- `SKILL_DIR` (and equivalents) — the single variable that, in the simple cases, is the whole fix.
- The CI invocation surface: `.claude/test-cmd`, `.github/workflows/ci.yml`,
  `.github/workflows/docs-ci.yml`.
- The new derived guard: a `*.test.sh` under `staging/plugin/scripts/tests/` that derives the runner
  population, count-guards the derivation, and fails on an undeclared `$HOME` resolution.

## UI flows
None.

## Edge cases
- The count is a figure from four different dates and does not match today's glob; the enumeration
  must be re-derived, and the population must include sibling test scripts, not only files literally
  named `run-tests.sh`.
- The split is real: some runners resolve one variable, others assume fixtures that exist only in a
  deployed tree, and a design that assumes uniformity will silently half-migrate.
- A runner that is genuinely a deployed-state check has a legitimate reason to read `$HOME`; a
  declared exception must be distinguishable from an unmigrated file, or the guard excuses the wrong
  thing.
- Redirecting `HOME` in a fixture also hides per-user Python site-packages, so a Python dependency
  (PyYAML) can vanish and the test then reports a "did not run" condition as a defect — ADR-0090
  recorded exactly this.
- A runner brought into CI may go red immediately, because until now its green was evidence about
  the deployed tree rather than about `staging/`.
- A count guard is required on the derivation: a glob that stops resolving discovers nothing and
  reads exactly like full compliance.
- Adding runners to `.claude/test-cmd`'s glob is not possible without moving or renaming the files;
  the CI invocation therefore needs its own decision.
- Per the repository's standing rules: every new assertion must be seen RED against a declared
  plant, both directions per contract, and a checker must distinguish "did not run" from "found
  nothing".

## Success criteria
- [ ] R-01 — each runner exercises `staging/`, or is declared with a reason if it genuinely cannot.
- [ ] R-02 — each runs in CI, so a change to a skill is covered by the skill's own suite.
- [ ] R-03 — a runner that resolves `$HOME` for anything other than a deliberate deployed-state
      check fails a derived guard, with a count guard on the derivation.
