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
  the Nth `mktemp`/`git`/`curl` call when an earlier helper uses it too: shim by `ps -o args= -p
  $PPID`, control-pass denominator guard, and two plants under one assertion id
