# Implementation plan — #109 Proportional audit depth

- **ADR:** `docs/architecture/ADR-0055-109-proportional-audit-depth.md`
- **SPEC:** `SPEC.md` / `docs/specs/109-proportional-audit-depth.spec.md`
- **Branch:** `feat/109-proportional-audit-depth` (stacked on `feat/108-project-ci-deterministic-checks`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**Absent means STRICT here, not inert.** The three preceding features all defaulted to inert-when-
absent and this one must not (ADR-0055 §D2). They *add* constraints, so inert equals the status quo;
this one *removes* them, so inert would silently downgrade every existing manifest.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/proportional-audit-depth.test.sh`.
  `P`-prefixed labels, hermetic, bash 3.2. Sections: **PA** both fields validate as
  conditional-if-present, and every enum value is accepted; **PB** **the default-strict rule** — an
  unset `risk`, an unset `task_type`, and a manifest predating both resolve to the strict profile,
  asserted against **real manifests in `docs/manifests/`** with a `>= 5` count guard against a
  vacuous loop; **PC** `max()` resolution — `high` + `boilerplate` → high, and no averaging or
  numeric score exists anywhere (assert the *absence* of a weights table, which is what stops §D3
  being reopened); **PD** the §D4 floor — a light profile does **not** remove `spec-coverage.sh`,
  the weakening scan, `interface-check.sh`, or the recovery-readiness pre-flight; **PE** Gate 2
  proposes and a human confirms (§D5), and the architect proposes rather than writing silently;
  **PF** Grove's five factors map onto the two axes with no third field (§D6); **PG** registration
  in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key`.

- [ ] **Task 2 — manifest fields.** `risk` and `task_type` in `manifest-init.sh` (written as
  `null`), and conditional-if-present invariants in `manifest-validate.sh` following Invariant 15's
  shape from ADR-0050. No schema bump. → PA green.

- [ ] **Task 3 — the resolution rule.** A single documented place that maps
  (`risk`, `task_type`) → profile, defaulting unset to strict and taking `max()` across axes. One
  place, not one per call site — this is the mistake `autopilot-build`'s stale restatement of c2c's
  isolation check already made once (ADR-0049 §D5). → PB/PC green.

- [ ] **Task 4 — the §D4 floor.** Wire the profile into c2c so it governs review passes, optional
  reviewer lenses and checkpoint cadence, and **cannot** remove any blocking gate. State the floor
  explicitly next to the resolution rule so it is not inferred. → PD green.

- [ ] **Task 5 — Gate 2 + architect.** `staging/plugin/agents/architect.md` proposes both fields
  from the plan's content; Gate 2 is where the operator confirms. Propose, never write silently
  (§D5) — same contract as ADR-0053 §D6's protected-interface proposal. Fold Grove's five factors
  onto the two axes here, with no third field (§D6). → PE/PF green.

- [ ] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `project-ci-checks`). Then run every `staging/plugin/scripts/tests/*.test.sh` — this changes
  `manifest-validate.sh` and `manifest-init.sh`, so the manifest-helpers harness is the key
  regression reader. Report anything already failing separately from anything newly caused.
  → PG green.

## Risk flags

1. **Defaulting to inert by pattern-match.** Three consecutive precedents point that way and it is
   wrong here. PB is the guard, and it must run against real manifests, not fixtures.
2. **The profile becoming a bypass.** A `task_type: boilerplate` label on a payment change must not
   disable payment-grade checks. PD pins the floor.
3. **Two resolution sites drifting.** Task 3 says one place. A restatement elsewhere goes stale, as
   `autopilot-build`'s copy of the isolation check already did.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
