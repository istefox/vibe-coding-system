# SPEC — task_num extracts digits only so a lettered task collides with its sibling

Source: GitHub issue #293

## Objectives

1. Give distinct plan tasks distinct identifiers, so `## Task 1b` and `## Task 1` no longer both
   resolve to `1` in `diff-budget-check.sh`'s `task_num()`.
2. Make `--tasks 1b` expressible, updating both the `--tasks` expansion and the `BUDGET_FILE` key
   that carry the identifier today.
3. Prove over the corpus in `docs/superpowers/plans/` that every plan currently parsed produces the
   same budget attribution after the change as before it.

## Scope

In: the identifier model used by `diff-budget-check.sh` — `task_num()` extraction, the `BUDGET_FILE`
key written per declaration, and the `--tasks` task-spec expansion; an assertion per call site; a
corpus-wide before/after attribution comparison. Measuring how many plans in
`docs/superpowers/plans/` actually use a lettered task identifier, before designing.

Out: the task predicate itself (`plan-task-predicate.awk`'s `is_task_line()` / `is_task_opener()`),
which recognises a task line and is not what assigns it a number. The reporter contract
(always exit 0, signal on stdout). The `MALFORMED` token and the per-file summation question,
which are issues #295 and #296.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` — carries all three affected
  mechanisms: the `task_num()` awk function that extracts the identifier, the `BUDGET_FILE`
  temp-file key each parsed declaration is written under (and re-read from at the summation and
  scope-union stages), and the `--tasks` argument parsing plus its expansion into an explicit task
  set. The line numbers ADR-0070 and ADR-0100 quote will have moved; resolve them by reading the
  file.
- `staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk` — supplies
  `is_task_opener()`, which delimits the task block whose identifier `task_num()` then extracts.
  Read to establish what a task opener may look like; not itself in scope.
- `staging/plugin/skills/concept-to-code/SKILL.md` — the Step 5 call site that passes `--tasks`.
- `docs/superpowers/plans/` — the plan corpus the before/after attribution comparison runs over.
- `staging/plugin/scripts/tests/diff-budget-scope.test.sh` — the harness file holding
  `diff-budget-check.sh`'s assertions, including ADR-0091 §BK9's both-parsers corpus comparison,
  which is the pattern R-03 asks to repeat.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108); each new
  assertion declares its plant beside it.
- `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md` and
  `docs/architecture/ADR-0100-242-batch-dispatch-openers.md` — where the limit was scoped out and
  then carried forward.

## Data model

The task identifier, currently an integer produced by `task_num()` and used as:

- the first field of each `BUDGET_FILE` line (`<identifier>\t<parsed declaration>`),
- the key the `--tasks` task-spec expands into and matches against,
- the value printed in `BUDGET`, `SCOPE` and `MALFORMED` output lines as `task <N>`.

Any widening of the identifier domain (digits plus an optional letter suffix) must hold across all
three uses.

## API / Interfaces

`diff-budget-check.sh --plan <file> --tasks <task-spec> < git-diff---stat-output` — a reporter:
always exits 0, signals on stdout, prints `CLEAN` when there is nothing to report. `--tasks` is the
interface that must accept `1b`. The stdout token grammar (`BUDGET`, `SCOPE`, `MALFORMED`, `CLEAN`)
is the other consumer-visible surface.

## UI flows

None.

## Edge cases

- A plan mixing `## Task 1` and `## Task 1b` — the collision the issue names.
- A plan using only plain numeric identifiers, which must attribute exactly as it does today
  (R-03).
- A `--tasks` range spanning a lettered identifier: ADR-0070 records that ranges are expanded
  numerically, so what `--tasks 1-3` means when `1b` exists must be decided, not assumed.
- The two corpus plans that use a different word for a task entirely (`### T1 —`, `### Step 0 —`),
  exempted by name in ADR-0070 §PTG9 and ADR-0069 §PTE2 — they match no predicate and must stay
  unaffected.
- A false `BUDGET` finding reaching an operator is the failure this exists to prevent; ADR-0091
  records what that looked like the last time it happened.
- Per the standing rules in the issue footer, both directions per contract: the plan that attributes
  correctly and the lettered plan the check exists to catch.

## Success criteria

- [ ] R-01 — distinct identifiers for distinct tasks, `--tasks 1b` expressible.
- [ ] R-02 — the `BUDGET_FILE` key and `--tasks` expansion both updated, with an assertion per call
      site.
- [ ] R-03 — every plan currently parsed produces the same attribution as before, proven over the
      corpus.
