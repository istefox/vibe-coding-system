# Memory index

One line per topic. The durable facts live in the linked file, not here — this index stays under
the 200-line/25KB injection cap; the topic files do not.

- [Stub-CLI test pattern and ADR-0154 back-reference gotcha](topics/task1-codex-audit-mode-slug.md)
  — reusable stub-`codex`-on-isolated-PATH harness pattern, and how a correct test file can still
  report every requirement id UNSCOPED with zero in-file error signal if it doesn't back-reference
  the plan/ADR, learned writing codex-audit-mode.test.sh spec-first (ADR-0193)
- [Ordinal-to-enumeration harness repair](topics/task5-schema-test-allblocks-slug.md) — the
  Z*-floor-vs-SC*-exact-equality distinction, re-derive-by-running procedure, bash 3.2 `grep -c`
  population-count pattern, learned repairing codex-reviewer-schema.test.sh (ADR-0193 §D7)
- [Plant sandbox git semantics and guard absorption](topics/plant-sandbox-git-and-guard-absorption.md)
  — why a git-driven end-to-end assertion still works in plant-check's `.git`-less sandbox, the
  unborn-repo fixture, the two absorption shapes (`os.path.join`; a second exit-3 path — assert the
  message, not just `rc -eq 3`), and the known pre-existing RS7 red
- [Caller-identifying utility shim](topics/selective-mktemp-shim-fixture.md) — isolating a guard on
  the Nth `mktemp`/`git`/`grep` call when an earlier helper uses it too: shim by `ps -o args= -p
  $PPID` or by flag signature, the succeeding shim that fails the NEXT step, control-pass
  denominator guards, prompt-log-as-evidence, and 2-3 plants under one assertion id
- [Audit file-scope fixtures and scratch plant verification](topics/audit-file-scope-fixtures-and-scratch-plant-verify.md)
  — whole-tree audit FILE_LIST is every git-tracked file (fabricated fixture paths get REJECTED),
  hyphen-free-basename + realpath fixture fix, content-selective python3 shim for an otherwise
  unreachable denominator guard, a manual scratch-copy plant-verify procedure, and a worktree-git-
  guardrail trigger fixed by using literal (non-`$VAR`) absolute paths
- [Plant infeasible for a not-yet-existing mechanism](topics/plant-infeasible-for-not-yet-existing-mechanism.md)
  — Batch-A tester-first RED assertions: when a plant IS still constructible (inject via a stable
  existing anchor + `\n`-escaped insertion) vs. when it genuinely is not (small fixed-population
  floors, whole-block insertions needing the future coder's free text) — follow the file's own
  no-plant-for-RED-until-future-task precedent instead of faking one, learned on pairs-completeness
  XR1/XR3/XR5 and sync-manual-steps section J (ADR-0197 migration)
- [Plan contract-scan blind spot: shared extractor](topics/plan-contract-scan-blind-spot-shared-extractor.md)
  — a plan's "every call-site is listed" grep can miss a consumer reached through a shared
  helper/variable rather than a direct literal match; resolution pattern (keep the variable, remove
  only in-scope consumers, flag the gap) and the CX10-shaped "retire a cross-check, don't freeze a
  baseline" rule-6 default, learned retiring codex-audit-mode.test.sh's SKILL.md reads (ADR-0197 Task 4)
