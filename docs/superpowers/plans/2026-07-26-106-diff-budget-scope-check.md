# Implementation plan — #106 Per-task diff budget and scope check

- **ADR:** `docs/architecture/ADR-0052-106-diff-budget-scope-check.md`
- **SPEC:** `SPEC.md` / `docs/specs/106-diff-budget-scope-check.spec.md`
- **Branch:** `feat/106-diff-budget-scope-check` (stacked on `feat/105-reward-hacking-detectors`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`, a Step 5 → Step 6 gate.

**Read ADR-0052 §D5 before writing any Gate 5 text.** This is the third advisory feature in a row.
The Gate 5 summary must get *shorter* in the all-clear case, not longer.

## Task checklist

- [x] **Task 1 — RED harness.** `staging/plugin/scripts/tests/diff-budget-scope.test.sh`.
  `B`-prefixed labels, hermetic (`mktemp -d`, throwaway git repos), bash 3.2 (no assoc arrays,
  `mapfile`, `${v^^}`, `<<<`, process substitution). Sections: **BA** a budget on a task line is
  parsed, and the over/under verdict is correct at the boundary; **BB** **absent budget is fully
  inert** — no finding, no output, verified against several real plans in
  `docs/superpowers/plans/` (this is the backward-compatibility hard gate, and it must run against
  the real corpus with a `>= 5` count guard against a vacuous loop, the `pairs-completeness.test.sh`
  self-test-2 lesson); **BC** an unparseable budget is treated as absent, never as zero; **BD**
  out-of-scope files are reported as their own finding type, distinct from an overshoot; **BE** the
  §D4 exclusions (manifest, `step5-report.json`, `SPEC.md`, an explicit plan-level `scope:`);
  **BF** `budget_findings` in the `step5-report.json` schema block; **BG** the §D5 roll-up — a
  single line when all six advisory arrays are empty, and a top-N cap with a remainder count on
  `budget_findings`; **BH** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key`.

- [x] **Task 2 — the budget parser + checker.**
  `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh`. **It is a reporter**: always
  exits 0, signals through stdout, prints a `CLEAN` sentinel when there is nothing — matching
  `weakening-scan.sh`, not `spec-coverage.sh`. State the caller idiom in the script header and at
  the call site, and restate the trap: never `[ -n "$out" ]` (true even on `CLEAN`), never
  `grep -c … || echo 0` (two-line `0\n0`; `|| true` is the fix). Lenient parse per §D6.
  → BA/BB/BC green.

- [x] **Task 3 — out-of-scope detection + exclusions.** Per §D4: a file in no declared task scope is
  its own finding type, not folded into the overshoot. → BD/BE green.

- [x] **Task 4 — plan template.** The architect's plan template gains the optional per-task budget
  in the form §D6 describes. Update `staging/plugin/agents/architect.md` so the agent knows to emit
  it. Do **not** retrofit existing plans.

- [x] **Task 5 — wiring + the §D5 roll-up.** Call the checker at the existing Step 5 checkpoints
  (ADR-0039 §D5's `pipeline()` stage, never a barrier). Add `budget_findings` to the
  `step5-report.json` schema and read contract. **Then do the §D5 work on the Gate 5 summary**:
  collapse all six advisory arrays to one line when every one is empty, and cap `budget_findings`
  at the top N by margin with a remainder count. → BF/BG green.

- [x] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `reward-hack-detectors`). Add the new script to `sync-to-claude.sh` `PAIRS` if the skill's
  `scripts/` are vendored per-file — check how `spec-coverage.sh` was registered and follow it
  exactly. Then run every `staging/plugin/scripts/tests/*.test.sh`; report anything already failing
  separately from anything newly caused. → BH green.

## Risk flags

1. **§D5 is the point of this feature's design.** Adding a seventh advisory array the way the last
   three were added is the default path and the wrong one. BG makes the roll-up a CI-pinned contract.
2. **Backward compatibility is the hard gate.** 30+ existing plans carry no budget and must stay
   silent — not "0 findings OK", genuinely silent. BB runs against the real corpus with a count guard.
3. **Reporter vs checker.** `spec-coverage.sh` sits in the same directory and is a *checker* (branch
   on exit code); this one is a *reporter* (branch on stdout). Do not copy one's caller idiom into
   the other — ADR-0048 §D7 already had to write that sentence once.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
