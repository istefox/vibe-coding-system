---
name: batch-c-step5-ask-and-effort
description: Step 5 batch C (Tasks 4-6, ADR-0194) landed the tester backend ask, exit-code branch and effort-pin lowering into step5-implementation.md WITHOUT the CX19-30/TG1 harness that was supposed to gate it — Task 1 (tester-owned test authoring) never landed in this feature's history
metadata:
  type: project
---

**Task 1 of the 2026-09-06 codex-claude-choice-for-tester plan never landed anywhere in this
repo's git history** (`feat/codex-claude-choice-for-tester` local branch = same commit as the
Batch B snapshot, `e4cb2b1`). Confirmed by direct search, not assumed:
`staging/plugin/scripts/tests/codex-tester-dispatch-gate.test.sh` does not exist on any branch,
and `test-write-scope.test.sh`'s `TG1(workflow)` needle still reads the literal string
`effort: "xhigh"` (Task 1c was supposed to flip that needle to `"high"` BEFORE Batch C's Task 6
edit landed the corresponding file change).

Consequence: doing Task 6's effort-pin edit (`xhigh` → `high` in
`step5-implementation.md`'s Workflow Stage 1 pin and the effort table) as instructed makes
`test-write-scope.test.sh` regress from 55/55 to 54/55 — `TG1` flips PASS→FAIL, because its own
needle was never updated. This is the DIRECT, predictable side effect of Task 1c's absence, not a
defect in the Task 6 edit itself. Batch C's own brief explicitly forbids editing any file under
`staging/plugin/scripts/tests/` (test-authoring is the tester agent's scope), so this needle
cannot be fixed from within a coder dispatch — it requires Task 1 (or at minimum 1c) to actually
land.

Why: the plan's own dispatch table (lines ~159-161 of the plan) assumes Batch A (Task 1) already
ran and left every `CX*` RED plus `TG1` RED-with-updated-needle before Batches B/C start. The
premise that "tests already exist, RED by design" was false when Batch C was dispatched — no
orchestration failure on Batch C's part, a missing upstream batch.

How to apply: before trusting any Batch-brief's "the tests already exist" claim on a
multi-batch dispatch (A/B/C sequencing), verify Task 1's harness file and any needle it was
supposed to update actually exist in the current worktree/branch — `git log --oneline --all --
<path>` is the fast check. If Task 1 shows no commits touching the new harness path, the
downstream batch's premise is false regardless of what the brief asserts, and the coder should
still implement the content changes (the plan's own wording is unaffected by the missing tests)
but must report the verification gap rather than silently declaring the harness green.
