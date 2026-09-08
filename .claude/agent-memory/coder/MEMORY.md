# Coder memory index

One line per topic. The durable facts live in the linked file, not here — this index stays under
the 200-line/25KB injection cap; the topic files do not.

- [awk out-parameter idiom for parse_budget](topics/batch-B-parse-budget-outparam.md) — widening
  plan-budget-parse.awk for R-02 (ADR-0189, issue #296) without touching its return value or
  existing 1-arg callers
- [diff-budget-check.sh FILEBUDGET emission](topics/batch-C-filebudget-emission.md) — per-file
  ceiling attribution (ADR-0189 §D2-D6, issue #296, R-01/R-03) without touching the pre-existing
  BUDGET/SCOPE machinery
- [Batch C step5-ask premise gap](topics/batch-C-step5-ask-and-effort.md) — Task 1's harness never
  landed before Batch C ran, causing a predictable TG1 regression (ADR-0194)
- [codex-tester.sh bash 3.2 gotchas](topics/codex-tester-cx12-argv-token-and-empty-array-nounset.md)
  — CX12's single-token argv expectation and the empty-array set -u idiom (ADR-0194)
- [codex-reviewer.sh audit mode](topics/task234-codex-reviewer-audit-mode-slug.md) — Tasks 2-4 of
  ADR-0193: SCHEMA_EOF block ordering, guard-embedding mechanism, python plant strings
- [deep-refactor/SKILL.md Gate 0-CDX and dispatch IF/ELSE](topics/task678-deep-refactor-skill-gate-cdx-slug.md)
  — Tasks 6-8 of ADR-0193: exact-count string traps in plant needles, this file's bold-heading and
  ```sh-fence conventions
- [codex-coder.sh scope-check gotchas](topics/batch-B-codex-coder-scope-check.md) — ADR-0196 tasks
  2-3: plant markers stay in the test file only, CK ids span two tasks, `-c key=value` as one argv
  element
- [codex coder backend gate in step5-implementation.md](topics/batch-C-codex-coder-step5-gate.md)
  — ADR-0196 tasks 4-6: a dispatch-site-marker quoting trap, and where `slice_heading` actually
  draws section boundaries versus where the plan's prose implies they are
