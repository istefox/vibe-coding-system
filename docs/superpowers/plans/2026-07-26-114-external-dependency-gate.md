# Implementation plan — #114 External-dependency feasibility gate (G13)

- **ADR:** `docs/architecture/ADR-0060-114-external-dependency-gate.md`
- **SPEC:** `SPEC.md` / `docs/specs/114-external-dependency-gate.spec.md`
- **Branch:** `feat/114-external-dependency-gate` (stacked on `feat/113-untrusted-input-hardening`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**Task 4 is a scope widening and is deliberate** (ADR-0060 §D3). Read that section before touching
`nightly-guard.sh`.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/external-dependency-gate.test.sh`.
  `E`-prefixed labels — grep the existing 36 files to confirm the prefix is unused. Hermetic, bash
  3.2. Sections: **EA** the plan template and `architect.md` carry the external-dependency
  declaration (§D1); **EB** the gate checks **present-tense provisioning state**, not
  provisionability, and refuses to dispatch unattended on an unmet declared dependency (§D2);
  **EC** **the per-feature skip does NOT halt the roadmap** — a skip note is distinct from the
  run-level `needs-human` marker, and `nightly-guard.sh` halts on the latter and not the former
  (§D3, the most important section in the file); **ED** the existing thin-issue writer in
  `spec-from-issue` and #113's injection-suspect writer are **moved onto the per-feature note**, and
  a regression assertion proves a thin issue no longer halts a multi-feature run; **EE** the
  run-level halts still fire unchanged for red build, RTF blocker and budget breach — a regression
  guard, since Task 4 edits the guard that owns them; **EF** absent declaration is inert (§D5) and
  the text states it means "nobody said", not "none exist"; **EG** the gate runs at **both** c2c
  Gate 2 and nightly Phase P from one implementation (§D4); **EH** registration in both CI
  registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural). Note this
  feature is *about* credentials, so name fixtures carefully.

- [ ] **Task 2 — the declaration.** Plan template + `staging/plugin/agents/architect.md`: declare
  third-party APIs, auth flows, cloud consoles, externally provisioned resources per feature.
  Propose-and-declare, consistent with ADR-0053 §D6 and ADR-0055 §D5's propose-never-write-silently
  contract. → EA green.

- [ ] **Task 3 — the gate.** One implementation, two call sites (c2c Gate 2, nightly Phase P).
  Checks present-tense provisioning state. Refusal names the human action required, never a retry.
  → EB/EG green.

- [ ] **Task 4 — split the markers (the scope widening, §D3).** Introduce a per-feature skip note
  distinct from the run-level `.claude/needs-human`. Move `spec-from-issue`'s thin-issue writer and
  #113's injection-suspect writer onto it. `nightly-guard.sh` halts on the run-level marker only.
  The morning report lists skipped features and the run continues.
  **Be careful here:** `nightly-guard.sh` also owns the red-build, RTF-blocker and budget halts, and
  those must keep firing exactly as before — EE is the regression guard. Also update
  `nightly-autopilot/SKILL.md`'s marker-contract prose (`:177`, `:182`) so the docs and the code
  agree; a stale restatement there is the ADR-0049 §D5 failure. → EC/ED/EE green.

- [ ] **Task 5 — report.** The morning report distinguishes skipped features from a halted run.
  Additive fields only, same terms as every prior schema extension. → EF green.

- [ ] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `untrusted-input`). Then run every `staging/plugin/scripts/tests/*.test.sh` — Task 4 touches
  `nightly-guard.sh`, `spec-from-issue` and #113's fresh code, so `untrusted-input.test.sh` and any
  nightly harness are the key regression readers.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`. → EH green.

## Risk flags

1. **Breaking the run-level halts while splitting them.** `nightly-guard.sh` is the single place
   that stops a bad overnight run. EE is the regression guard and it matters more than the new
   feature.
2. **Scope widening** (§D3). Real blast radius across three files including #113's just-merged
   code. The alternative was knowingly adding a third writer to a broken mechanism.
3. **Absent declaration is indistinguishable from no dependencies** (§D5). Say it; do not imply the
   gate proves anything about an undeclared feature.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
