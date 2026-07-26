# Implementation plan — #104 Recovery-readiness pre-flight for c2c Step 5

- **ADR:** `docs/architecture/ADR-0050-104-recovery-readiness-preflight.md`
- **SPEC:** `SPEC.md` / `docs/specs/104-recovery-readiness-preflight.spec.md`
- **Branch:** `feat/104-recovery-readiness-preflight` (stacked on `feat/103-generator-verifier-separation`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none, and an undeclared citation is an
`ORPHAN`, exit 3 from `spec-coverage.sh`, which is a Step 5 → Step 6 gate.

**Read ADR-0050 §D4 before touching anything.** ADR-0049 just shipped a dirty-tree condition that
*tolerates* a dirty tree; this one *refuses* on one. They are sequential, not contradictory, and
collapsing them is the single most likely way to get this wrong.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/recovery-preflight.test.sh`.
  `R`-prefixed labels, hermetic (fixtures under `mktemp -d`, real throwaway git repos), bash 3.2
  (no assoc arrays, `mapfile`, `${v^^}`, `<<<`, process substitution). Follow the structure and
  counting of a sibling such as `spec-coverage.test.sh`. Sections: **RA** the three assertions
  exist in c2c Step 5 as prose anchors; **RB** the refusal names a literal remediation command for
  each failure; **RC** the default-branch check resolves the remote default rather than hardcoding
  `main`; **RD** `recovery_baseline_sha` is written once and is conditional-if-present in
  `manifest-validate.sh`; **RE** the ADR-0050 §D4 sequencing note is present in SKILL.md and names
  both conditions, so a future reader cannot collapse them silently; **RF** the autopilot path
  refuses identically (no leniency branch); **RG** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` (`protect-files.sh` denies them; `secret-dep-gate.test.sh` D scans `git ls-files`).

- [ ] **Task 2 — c2c Step 5 pre-flight block.** Add at the **top** of Step 5, before any dispatch
  and before the tester stage ADR-0049 introduced. Reuse `deep-refactor` Step 0.3/0.7 verbatim in
  idiom and variable naming (`git rev-parse HEAD` → `BASELINE_COMMIT`; `git status --porcelain` →
  `DIRTY_TREE`) — do not invent a second idiom (§D5). Three assertions per §D1; refusal per §D2
  printing the literal remediation command. Include the §D4 sequencing note next to the block, in
  prose, naming ADR-0049's condition explicitly. → RA/RB/RC/RE green.

- [ ] **Task 3 — manifest field.** `recovery_baseline_sha` written once at pre-flight via
  `manifest-set-flag.sh`; add the conditional-if-present invariant to
  `concept-to-code/scripts/manifest-validate.sh` so pre-ADR-0050 manifests stay valid with no
  migration and no schema bump. → RD green.

- [ ] **Task 4 — autopilot parity.** Confirm and pin that `autopilot: true` takes the same refusal
  with no leniency branch, recorded in the report rather than prompted (§D6). Check whether
  `autopilot-build/SKILL.md` restates Step 5's entry conditions; if it does, update it in the same
  edit — a stale restatement there is a false green on an unattended path, the exact defect
  ADR-0049 §D5 fixed. → RF green.

- [ ] **Task 5 — registration.** New test file added to **both** CI registries: `ci.yml`'s glob
  picks it up automatically, but `.github/workflows/docs-ci.yml`'s **explicit named list** requires
  a manual append (after `test-write-scope`). → RG green.

- [ ] **Task 6 — full suite.** Run every `staging/plugin/scripts/tests/*.test.sh`, not just the new
  file: this touches `concept-to-code/SKILL.md` Step 5 (readers: `test-write-scope.test.sh`,
  `weakening-wiring.test.sh`, `spec-coverage.test.sh`, `step5-checkpoint-review.test.sh`) and
  `manifest-validate.sh` (readers: the manifest-helpers harness). Report anything already failing
  separately from anything newly caused.

## Risk flags

1. **§D4 collapse.** The two dirty-tree conditions read as a contradiction out of context. RE exists
   to make silent reconciliation fail CI.
2. **Refusing a legitimate resume.** A resume into a deliberately dirty tree now needs an explicit
   stash. Accepted in the ADR; make sure the refusal message says so rather than looking like a bug.
3. **Instruction, not enforcement.** The harness pins that the block exists, never that a model obeys
   it. Do not overstate the guarantee in the SKILL.md text.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
