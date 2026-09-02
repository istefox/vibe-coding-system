---
name: batch-c-filebudget-emission
description: how diff-budget-check.sh attributes per-file ceilings and emits FILEBUDGET (ADR-0189 §D2-D6, issue #296, R-01/R-03) without touching the pre-existing BUDGET/SCOPE machinery
metadata:
  type: project
---

Task 4 of the 2026-09-02 per-file-budget-ceiling plan added the `FILEBUDGET` emission to
`staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh`, on top of Task 2's
`parse_budget(rest, groups)` out-parameter ([[batch-b-parse-budget-outparam]]).

The mechanism is two parallel tables joined by a plain awk two-file `FNR==NR` pattern, not a
bash associative array (this script is bash-3.2 clean, no assoc arrays):

- `GROUPS_FILE` (`<task><TAB><files><TAB><ceiling><TAB><group-count>`) is populated in the
  `plan_parse.awk` heredoc's successful-parse branch only, by looping `groups[1..groups[0]]` right
  after the existing `BUDGET_FILE` print. Malformed/no-match branches are untouched by construction
  — `FILEBUDGET` can only ever originate from a declaration that already parses.
- `CEIL_RAW` (`<file><TAB><summed-ceiling><TAB><reportable>`) is derived from `GROUPS_FILE` AFTER
  task-set expansion, filtered to selected tasks with the same `grep -qxF "$_t" "$TASK_SET"` idiom
  the existing summing loop uses, and split on `IFS=','` in the same shape as the pre-existing
  `MASTER_SCOPE` loop. `reportable` is 1 iff that GROUP's own row has `_ng >= 2` (ADR-0189 §D3) —
  critically, reportability and the ceiling sum are computed from different populations on purpose:
  a file's ceiling sums every selected group naming it (single-ceiling groups included), but the
  file only becomes reportable if AT LEAST ONE of those groups came from a multi-group task. Once
  `rep[f]=1` is set from one row it is never unset by a later single-ceiling row for the same file.
- `ACTUAL_FILE` (`<file><TAB><actual-lines>`) is appended to only in the existing candidate loop's
  in-scope branch (the one incrementing `FILES_ACTUAL`), using `$_lookup` (the elision-resolved
  name, ADR-0189 §D6) not `$_path`. Out-of-scope files never reach it.
- The emission itself lives INSIDE the pre-existing `if [ "$BUDGET_LIVE" -eq 1 ]` block, after the
  `BUDGET` line and before `emit_malformed` — this is what makes BL11d (a task selection with no
  live budget of its own must stay CLEAN even when a sibling task's file is touched) pass without
  any special-casing: the same gate that silences `BUDGET` silences `FILEBUDGET`.
- `sort` on the awk output before `>>"$OUT"` is load-bearing, not cosmetic: `for (f in act)` has no
  defined iteration order in awk, and BL9b asserts sort-ordering on multi-line runs.

Why: false positives are the expensive failure for this REPORTER (ADR-0189 §Context point 1), so
every ambiguity resolves toward leniency — summing ceilings across ALL selected groups (not just
reportable ones) before gating on reportability is exactly that leniency, verified live via BL5
(cross-task ceiling sum 1+50=51) and BL10 (single-ceiling population stays byte-inert, BUDGET fires,
FILEBUDGET never does).

How to apply: verified live 2026-09-02 — `diff-budget-scope.test.sh` 75/76 (only BL12 red, which
depends on Task 6/step5-implementation.md, not this task) and `step5-brief.test.sh` 39/39 green,
confirming this change disturbs nothing in BK1-BK10 or the BA/BB/BD/BE/BJ sections. If a future task
needs another per-file derived signal from a `Budget:` declaration, reuse this same two-file
`FNR==NR` awk join pattern rather than inventing a bash associative-array workaround — it is the
established idiom in this exact script for exactly this reason.
