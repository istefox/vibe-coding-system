# Implementation plan — #111 Tracer-bullet probe step

- **ADR:** `docs/architecture/ADR-0057-111-tracer-bullet-probe.md`
- **SPEC:** `SPEC.md` / `docs/specs/111-tracer-bullet-probe.spec.md`
- **Branch:** `feat/111-tracer-bullet-probe` (stacked on `feat/110-sast-security-audit`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**The verdict is computed, not asked for** (ADR-0057 §D3). Asking the probe coder "could you do
this?" is the obvious implementation and it is the one that makes the feature decorative.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/tracer-bullet-probe.test.sh`.
  `T`-prefixed labels — note `test-write-scope.test.sh` already uses `T`; prefix these `TB` to keep
  them distinguishable in a combined log. Hermetic, bash 3.2. Sections: **TBA** Step 4.5 exists
  between Gate 4 and Step 5 and is **optional, defaulting to skipped** (§D1 / ADR-0055 §D2);
  **TBB** all three verdicts exist and `red` has its own gate with **hand-code / abort as a named
  first-class option** and a recorded reason (§D2); **TBC** the verdict is derived from mechanical
  facts — build/run, test pass, attempt count, out-of-scope files — and the text states the agent
  **cannot upgrade a mechanically failing slice to green** (§D3, the assertion that matters most);
  **TBD** the slice is end-to-end, not single-layer (§D1); **TBE** the cost cap exists and reuses
  ADR-0052's budget mechanism rather than a second one (§D4), and exceeding it is itself a signal;
  **TBF** on `green` the slice is kept and referenced as the pattern seed by the Step 5 briefs
  (§D5); **TBG** `amber` routes back to Gate 2; **TBH** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — Step 4.5 in `concept-to-code/SKILL.md`.** Between Gate 4 and Step 5. Optional,
  default off. One coder, thinnest end-to-end slice. Dispatch pins `model` and `effort` explicitly
  — the effort table is documentation, not a binding, and an omitted `effort` inherits the
  orchestrator's (ADR-0018 addendum, ADR-0049 §D6). → TBA/TBD green.

- [ ] **Task 3 — the verdict computation.** Mechanical derivation per §D3, with the agent's
  narrative as context only. State explicitly that a recommendation is recorded but cannot override
  a mechanical failure. → TBC green.

- [ ] **Task 4 — the three routes.** `green` → Step 5 with the slice as pattern seed; `amber` →
  back to Gate 2 for scope reduction; `red` → a new gate offering continue-anyway / reduce-scope /
  hand-code, the last aborting the chain with the reason recorded in the manifest.
  Check whether `manifest-transition.sh` already has the pairs this needs — ADR-0027 found Gates
  0c/0d were written but structurally unreachable because the pairs were missing, so verify rather
  than assume. If a new pair is needed, add it and update the documented pair count in **both**
  places it appears (`SKILL.md` and the `manifest-transition.sh` comment — ADR-0028 had to
  reconcile those two after they drifted). → TBB/TBG green.

- [ ] **Task 5 — pattern seed.** On `green`, the slice is committed and the Step 5 briefs reference
  it as the established pattern (§D5). → TBF green.

- [ ] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `sast-security-audit`). Then run every `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`, not before** — `secret-dep-gate.test.sh` D1 scans `git ls-files`,
  so an untracked file is invisible to it; this cost #108 a regression. → TBH green.

## Risk flags

1. **A self-assessed verdict.** The obvious implementation, and it reproduces the generator/verifier
   problem ADR-0049 exists to fix. TBC is the guard.
2. **`red` degrading into a slow `amber`.** Without hand-code written down as a first-class option,
   every incentive in a mid-run chain points at "continue". TBB asserts the option exists by name.
3. **A probe that costs what Step 5 costs** has no value. TBE pins the cap, and reuses ADR-0052's
   budget rather than inventing a second cost control.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
