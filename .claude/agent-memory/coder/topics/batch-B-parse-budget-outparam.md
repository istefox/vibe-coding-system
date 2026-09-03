---
name: batch-b-parse-budget-outparam
description: awk out-parameter idiom used to widen plan-budget-parse.awk's parse_budget for R-02 (ADR-0189, issue #296) without touching its return value or existing 1-arg callers
metadata:
  type: project
---

Task 2 of the 2026-09-02 per-file-budget-ceiling plan (VCS-057/ADR-0189, issue #296, R-02) widened
`parse_budget(rest)` in `staging/plugin/skills/concept-to-code/scripts/plan-budget-parse.awk` to
`parse_budget(rest, groups, ...)`. `groups` is a genuinely array-typed second formal parameter
placed BEFORE the local-variable list, so a pre-existing one-argument call still works (awk binds
the missing argument to a fresh local array). `groups[0]` holds the count and is set to the final
`ng` only immediately before the successful `return`, never via `delete groups` (whole-array
`delete` is a gawk extension, not POSIX, and this codebase is POSIX/bash-3.2 clean).

Why: the two existing consumers (`diff-budget-check.sh`, `step5-brief.sh`) and a frozen
corpus-comparison test (`BK9` in `diff-budget-scope.test.sh`, which `sed`-extracts the function body
between `^function parse_budget` and a column-0 `^}$`) all call `parse_budget(rest)` with one
argument and read only the string return. Widening the signature in place (rule 6: one producer of
"what does a Budget: line mean", not a fork) meant the return value had to stay byte-identical, so
those three call sites needed zero edits — verified live: `step5-brief.test.sh` 39/39 green and
`diff-budget-scope.test.sh`'s BK9a/b/c stayed green after the change.

How to apply: if a later task in this same plan (Task 4: diff-budget-check.sh FILEBUDGET emission,
or Task 6: Step 5 doc) needs to read `groups`, the contract is `groups[1..groups[0]]`, each entry a
`"<pre>\t<num>"` string — iterate `for (i = 1; i <= groups[0]; i++)`, never assume indices beyond
`groups[0]` are unset (they are unreachable by construction, not deleted). This out-parameter shape
(array-typed 2nd formal, before locals, `[0]` as count) is the pattern to reuse for any future awk
function in this repo that needs to widen its output without forking or breaking existing callers.
