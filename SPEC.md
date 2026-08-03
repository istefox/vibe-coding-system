# SPEC — one real plan shape is recognised by no task predicate

Source: GitHub issue #290

## Objectives

1. Re-derive the corpus: run both predicates (`is_task_line`, `is_task_opener`) over every plan in
   `docs/superpowers/plans/` and report which plans match neither, confirming today's number rather
   than trusting ADR-0069's "one" or ADR-0100 §PTG9's "two further".
2. Ensure each unrecognised plan is either recognised or exempted **by name**, with a companion
   assertion that the exempted file still exists.
3. Prove that widening a predicate does not change token extraction for the plans that already
   match, by comparing both predicates over the whole corpus before and after.

## Scope

In: `plan-task-predicate.awk`'s two predicates and any widening of them; the exemption list and its
companion existence assertions; the before/after corpus comparison.

Out: the `--tasks` expansion and the `BUDGET_FILE` key, and the identifier model generally —
ADR-0070 records that `task_num()` extracts digits only and that changing it is out of scope. Out:
rewriting any plan in `docs/superpowers/plans/`, which are historical records.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk` — the one place that
  decides, holding both `is_task_line()` (the `>= 1` guard predicate, over-counting is safe) and
  `is_task_opener()` (the block-boundary predicate, over-matching corrupts attribution).
- `staging/plugin/skills/concept-to-code/scripts/plan-tasks.sh` — the single entry point, with its
  `--count` and `--count-openers` modes and their **opposite failure directions**.
- `docs/superpowers/plans/` — the corpus, 58 plans measured at spec time.
  `2026-06-06-claude-md-slim.md` writes `### Step N — …`; ADR-0100 §PTG9 names two further plans
  using `### T1 —` and `### Step 0 —`.
- Consumers: `staging/plugin/skills/concept-to-code/SKILL.md` Step 5 pre-dispatch (plan-structure
  validation and batch arithmetic), `staging/plugin/skills/autopilot-build/SKILL.md` check 5,
  `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`,
  `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh`.
- Tests: `staging/plugin/scripts/tests/plan-task-count.test.sh` (`PTE1` count guard, `PTE2` the
  named exemption, `PTE3` the exemption's live subject);
  `staging/plugin/scripts/tests/diff-budget-scope.test.sh` (`PTG9`/`PTG10`);
  `staging/plugin/scripts/tests/batch-dispatch-openers.test.sh`.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- Sources: `docs/architecture/ADR-0069-172-plan-task-form.md`,
  `docs/architecture/ADR-0070-184-diff-budget-task-predicate.md`,
  `docs/architecture/ADR-0100-242-batch-dispatch-openers.md`.

## Data model

A plan task, as recognised by the two predicates: a checklist item (`- [ ] **Task N …`), or an
H2–H4 heading containing "Task". The unrecognised shapes are `### Step N —`, `### Step 0 —`, and
`### T1 —`.

## API / Interfaces

`plan-tasks.sh --count` (guard, `>= 1`, over-counts by design) and `plan-tasks.sh --count-openers`
(arithmetic, returns 0 on plans using a different word for a task). Both are checkers: exit 3 for
"did not run" is distinct from a zero result. Neither is a safe substitute for the other, and both
call sites say so.

## UI flows

None.

## Edge cases

- **A plan matching no predicate makes `--count` return 0**, and both Step 5 consumers abort blaming
  a malformed plan — issue #172 reproduced.
- **The batch arithmetic falls back to a single block, which is safe but silent** (ADR-0100). Safe
  and silent is the harder failure to notice.
- **Widening to `Task|Step` was already rejected once** by ADR-0069 §D6, on the ground that it
  changes token extraction for every plan to accommodate one completed plan. R-02 is the check that
  makes any widening prove otherwise.
- **An exemption must not outlive its subject.** `PTE3` is the existing pattern: assert the exempted
  file still exists, so the exemption cannot become a waiver covering nothing (the stale-waiver
  direction, ADR-0081 `ZA4`).
- **An identity waiver does not travel on rename** — ADR-0069 §PTD's objection to filename-keyed
  lists; naming a file by name is accepted here only because R-01 pairs it with the existence
  assertion.
- **The two predicates answer different questions**, and a widening that satisfies one may corrupt
  the other: a checkbox sub-step reading `- [ ] Re-run Task 2.` must satisfy `is_task_line` and must
  not satisfy `is_task_opener`.

## Success criteria

- [ ] R-01 — each unrecognised plan is either recognised or exempted **by name**, with a companion
      assertion that the exempted file still exists so the exemption cannot outlive its subject.
- [ ] R-02 — widening a predicate must not change token extraction for the plans that already match;
      prove it by comparing both predicates over the whole corpus before and after.
