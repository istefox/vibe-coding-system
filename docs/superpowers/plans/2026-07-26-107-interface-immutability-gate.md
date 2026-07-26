# Implementation plan — #107 Interface immutability gate

- **ADR:** `docs/architecture/ADR-0053-107-interface-immutability-gate.md`
- **SPEC:** `SPEC.md` / `docs/specs/107-interface-immutability-gate.spec.md`
- **Branch:** `feat/107-interface-immutability-gate` (stacked on `feat/106-diff-budget-scope-check`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`, a Step 5 → Step 6 gate.

**This check BLOCKS.** It is the first of the recent features to do so, deliberately (ADR-0053 §D2).
Do not soften it into an advisory to match its neighbours.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/interface-immutability.test.sh`.
  `I`-prefixed labels, hermetic (`mktemp -d`, throwaway git repos), bash 3.2 (no assoc arrays,
  `mapfile`, `${v^^}`, `<<<`, process substitution). Sections: **IA** a removed protected signature
  is detected and the script exits 3; **IB** a signature-changed protected entry is detected;
  **IC** **absent `.claude/protected-interfaces` is fully inert** — exit 0, no stdout, no stderr
  (the backward-compatibility hard gate; assert it against a fixture repo *and* against this
  repository, which has no such file); **ID** comments and blank lines are ignored, path globs and
  exact signatures both work; **IE** exit-code contract — 0 clean, 3 broken, 2 bad invocation,
  pinned explicitly so nobody converts it to a reporter; **IF** the §D4 known limits are asserted
  as *expected* behaviour (a continuation-line default-arg change may be missed; a reformat may
  fire) so closing one forces the ADR paragraph to move with the code, the ADR-0045 section-E
  pattern; **IG** the c2c Step 6 call site branches on the **exit code** and says so, and the
  §D3 contract table is present; **IH** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key`.

- [ ] **Task 2 — `interface-check.sh`.** New script; put it beside its siblings in
  `staging/plugin/skills/concept-to-code/scripts/` unless the standalone-CI requirement argues for
  `staging/plugin/scripts/` — decide, and say which and why in the report. Reads
  `.claude/protected-interfaces` and a diff. Exit 0 / 3 / 2 per §D3. Header comment states the
  contract **and** names the two reporter siblings it must not be confused with. Textual, shallow
  matching per §D4 — no language parsers, no AST, no tool dependence.
  → IA/IB/IC/ID/IE green.

- [ ] **Task 3 — the §D3 contract table.** Add it at the c2c call site: four scripts, two reporters,
  two checkers, with each caller idiom. This family has now had the reporter/checker confusion
  written down three times; make the table the thing a reader sees before copying an idiom.
  → IG green.

- [ ] **Task 4 — c2c Step 6 wiring + standalone CI exposure.** Call it in Step 6 before the review
  closes, branching on the exit code. Expose it standalone so a project CI can call it directly
  (§D5). Add it to the project CI template if that is where the other checks live — check how
  `secret-scan.sh` reached `staging/project-templates/ci/ci.yml` and follow it.

- [ ] **Task 5 — architect proposal at Gate 2.** `staging/plugin/agents/architect.md`: when the plan
  touches a public surface, propose `.claude/protected-interfaces` entries. **Propose, never write
  silently** (§D6) — a protection the operator did not knowingly declare is a block they will not
  understand, and opt-in consent is the whole defence for a blocking gate.

- [ ] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `diff-budget-scope`). `PAIRS` entry following whichever sibling matches the location chosen in
  Task 2. Then run every `staging/plugin/scripts/tests/*.test.sh`; report anything already failing
  separately from anything newly caused. → IH green.

## Risk flags

1. **Softening it to advisory.** The neighbouring three features are all advisory and the pull
   toward consistency is strong. IE pins the exit-code contract so a conversion fails CI.
2. **Over-firing on reformats** (§D4). Known and accepted at this depth; IF pins it as expected so
   the limitation cannot be quietly "fixed" without moving the ADR text.
3. **Fourth contract in a four-script family.** Task 3's table is the mitigation and it is
   documentation, not enforcement. Worth its own issue.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
