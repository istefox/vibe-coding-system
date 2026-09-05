---
name: task234-codex-reviewer-audit-mode
description: codex-reviewer.sh audit mode (Tasks 2-4, ADR-0193) implementation notes — SCHEMA_EOF block ordering, guard-embedding mechanism, python plant strings
metadata:
  type: project
---

Implemented `--mode audit` in `staging/plugin/scripts/codex-reviewer.sh` (Tasks 2-4 of
`docs/superpowers/plans/2026-09-05-codex-review-gate-deep-refactor.md`, ADR-0193). Tasks 5-10
(schema-test ordinal repair, SKILL.md dispatch-model/Gate-0-CDX/Gate-1 prose, chain-decision-index)
are separate tasks not covered here.

**Why the audit SCHEMA_EOF block goes last, not between review and diagnose:** ADR-0193 §D7 warns
that `codex-reviewer-schema.test.sh` (pre-Task-5) extracts schemas by ORDINAL position (block 1 =
review, block 2 = diagnose). Inserting a third block between them would silently repoint block 2 at
the audit schema and stop diagnose from being checked at all — no visible failure, just silent loss
of coverage (rule 18 shape). Placing the new block after diagnose (as the final `else` in the
`if review / elif diagnose / else audit` chain) keeps the existing ordinal test green until Task 5
converts it to all-blocks extraction. Verified by re-running
`staging/plugin/scripts/tests/codex-reviewer-schema.test.sh` after the change: still 3/3 pass,
S1=review, S2=diagnose, unaffected.

**Guard embedding mechanism, not a case statement:** the test's plant comment
(`staging/plugin/scripts/tests/codex-audit-mode.test.sh` CX17) names the literal string
`"$DIMENSION" = "perf"` as the expected pattern, which drove using two independent
`if [ "$DIMENSION" = "dead-code" ]; then ... fi` / `if [ "$DIMENSION" = "perf" ]; then ... fi`
blocks to build `GUARD_BLOCK`, rather than a `case` statement. Functionally equivalent, but a
`case` would not match that plant's literal-text needle. Worth checking a test file's `# plant:`
comments for the exact surface form expected before choosing an equivalent-but-differently-shaped
implementation — [[coder-plant-comments-shape-implementation]] if that pattern recurs elsewhere.

**File-list intersection avoids process substitution (bash 3.2 constraint):** to intersect
`enumerate-sources.sh`'s whole-tree output with a diff's changed-paths list, wrote both to temp
files and used `grep -Fxf changed_file all_file` (fixed-string, whole-line match, patterns from
file) rather than `grep -Fx -f <(...)`. `-Fxf` is POSIX-portable and bash-3.2-safe.

**id synthesis:** `<dimension>-<basename(file)>-<hash3>` where hash3 is
`hashlib.sha256(file + str(line) + description).hexdigest()[:3]` — sha256 chosen only because it's
stdlib and deterministic; the plan did not pin an algorithm, any stable digest satisfies R-02/R-04.

**Full test result at hand-off (Tasks 2-4 only, before Tasks 5-10):**
`codex-audit-mode.test.sh` → PASS=24 FAIL=4 (CX01-CX19, CX21, CX25-CX27 green; CX20/CX22/CX23/CX24
red — those four assert SKILL.md's dispatch-model/Gate-0-CDX/Gate-1 prose, which Tasks 6-8 add, not
Tasks 2-4). `codex-reviewer-schema.test.sh` → PASS=3 FAIL=0 (still ordinal, Task 5 not yet run).
