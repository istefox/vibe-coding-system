# SPEC — a per-file budget ceiling is parsed and then summed so one file can exceed its own

Source: GitHub issue #296

## Objectives

1. Report a file that exceeds its own declared ceiling, even when the task's total stays under the
   summed budget.
2. Leave the single-ceiling declaration form behaving exactly as it does today, proven by comparing
   the whole corpus under both parsers.
3. Keep the reporter contract unchanged: always exit 0, signal on stdout.

## Scope

In: what `diff-budget-check.sh` does with per-file ceilings after parsing them — currently summed
into a task total and discarded — and the finding it reports when one file overruns its own
declaration. A whole-corpus both-parsers comparison in the style of ADR-0091 §BK9.

Out: the parsing of the per-file syntax itself, which ADR-0091 already fixed (the parser reads
`a/x.md (~165 lines, new), b/y.sh (~1 line)`). The `MALFORMED` token's consumers (#295), the
identifier model (#293), and the mode-selection question (#294).

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` — the whole change. The
  relevant stages, in order: the awk parser that walks paren groups left to right and writes each
  parsed declaration to `BUDGET_FILE`; the `MASTER_SCOPE` union built from `BUDGET_FILE`; and the
  `--tasks` expansion that sums declared budgets across the selected task set. It is the last stage
  that discards per-file granularity. Line numbers quoted by ADR-0091 will have moved; resolve them
  by reading the file.
- `docs/superpowers/plans/` — the corpus. ADR-0091 measured 16 budget declarations, of which the
  per-file ones are the population R-01 acts on and R-02 must show unchanged elsewhere.
- `staging/plugin/skills/concept-to-code/SKILL.md` — the Step 5 checkpoint block consuming the
  reporter's stdout and recording findings into `step5-report.json`; a new per-file finding shape
  has to land there.
- `staging/plugin/scripts/tests/diff-budget-scope.test.sh` — the harness file, already carrying
  ADR-0091 §BK9's both-parsers corpus comparison, which R-02 asks to repeat.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0091-246-per-file-budget-half-parse.md` and
  `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md` — the source and its predecessor.

## Data model

A budget declaration, per task, is currently reduced to a line in `BUDGET_FILE` keyed by task
identifier. The per-file form carries, per file: a path and a line ceiling (and, in the corpus, an
optional marker such as `new`). The change is that the per-file ceiling must survive to the
comparison stage instead of being collapsed into one total per task.

A finding shape must be decided for "file X exceeded its own ceiling", distinct from the existing
task-total `BUDGET` finding, and recorded in `step5-report.json` alongside the existing
`budget_findings` entries.

## API / Interfaces

`diff-budget-check.sh --plan <file> --tasks <task-spec> < git-diff---stat-output`. Reporter
contract: always exit 0, signal on stdout, `CLEAN` when there is nothing to report. Token grammar
today: `BUDGET`, `SCOPE`, `MALFORMED`, `CLEAN`. Whether the per-file overrun is a new token or a
variant of `BUDGET` is a design decision — either way it becomes part of the grammar every consumer
enumerated by #295 reads.

## UI flows

None.

## Edge cases

- A task whose total passes while one file overruns — the case R-01 names, and the only one the
  current check misses.
- A single-ceiling declaration, which must behave byte-identically (R-02).
- A mixed declaration: ADR-0091 records that mixed forms work as a consequence of the one-grammar
  left-to-right walk, not as a special case.
- A file in the declared set with zero changed lines in the diff.
- A changed file not named in any declaration — the existing `SCOPE` finding, which must not change
  meaning.
- `git diff --stat` path elision and right-aligned counts: ADR-0070 defects 3 and 4, both of which
  corrupt per-file attribution and are the reason `--stat=999` is used at both call sites.
- A malformed declaration coexisting with a well-formed one in the same task.
- Per the standing rules in the issue footer, both directions per contract, and a reporter never
  branches on an exit code.

## Success criteria

- [ ] R-01 — a file exceeding its own ceiling is reported even when the task total passes.
- [ ] R-02 — the single-ceiling form keeps its current behaviour exactly; prove it by comparing the
      whole corpus under both parsers, as ADR-0091 §BK9 did.
- [ ] R-03 — the reporter contract is unchanged: always exit 0, signal on stdout.
