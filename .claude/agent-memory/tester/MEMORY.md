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
