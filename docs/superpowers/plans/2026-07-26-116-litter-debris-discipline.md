# Implementation plan — #116 Litter and debris discipline

- **ADR:** `docs/architecture/ADR-0062-116-litter-debris-discipline.md`
- **SPEC:** `SPEC.md` / `docs/specs/116-litter-debris-discipline.spec.md`
- **Branch:** `feat/116-litter-debris-discipline` (stacked on `feat/115-human-gate-coverage`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**Do not add a stray-file detector** (ADR-0062 §D2). `commit`'s untracked-file list is already
mechanical and already in front of a human; a second one adds false-positive surface for nothing.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/litter-discipline.test.sh`.
  `L`-prefixed labels — grep the existing 38 files to confirm the prefix is unused. Hermetic, bash
  3.2. Sections: **LA** the cleanup clause is in the **Output Format** section of `coder.md`,
  `debugger.md` and `refactorer.md` (§D1 — assert the section, not merely the file, since Output
  Format is what an agent fills in); **LB** the clause names all four classes: temporary files,
  scratch scripts, debug log statements, temp branches; **LC** the disposition list is documented as
  a **record, not evidence**, and `commit`'s untracked list is named as authoritative (§D2);
  **LD** **no new stray-file detector exists** — assert the absence, since that absence is the
  decision; **LE** the temp-branch registry records and reconciliation **reports without deleting**
  (§D3), with the spec's case-3 reasoning stated where a future reader will see it before "fixing"
  it into an auto-delete; **LF** no debug-log detector exists (§D4) and the instruction says the
  class is unenforced; **LG** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — the cleanup clause.** Add to the Output Format of `staging/plugin/agents/coder.md`,
  `debugger.md` and `refactorer.md`. Additive; do not restructure those files. → LA/LB green.

- [ ] **Task 3 — name the authoritative check.** State in the clause, and wherever the disposition
  list is consumed, that it is a record and that `commit`'s untracked-file list is the mechanical
  signal. → LC/LD green.

- [ ] **Task 4 — temp-branch registry + reconciliation.** Agents register a temp branch they create;
  reconciliation lists branches that exist and were never reconciled. **Reports only — never
  deletes**, and the reason (the spec's case 3: a repository lost to a branch cleanup) is written
  next to the code, not only in the ADR. Decide where reconciliation runs and say why. → LE green.

- [ ] **Task 5 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `human-gate-coverage`). `PAIRS` entries for any new script **and** note that `agents/*.md` are
  covered by `pairs-completeness.test.sh`'s `check_complete` — three agent files change here, so
  verify they are all already in `PAIRS` rather than assuming (ADR-0043 added them, but check).
  Then run every `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`. → LG green.

## Risk flags

1. **Adding a detector anyway.** The instinct is to make this mechanical. §D2 and §D4 explain why
   both candidate detectors are worse than nothing here; LD and LF assert their absence.
2. **Auto-deleting stale branches.** Reproduces the exact incident the spec documents. LE pins
   report-only, and the reasoning must live beside the code.
3. **This feature is mostly instruction.** Do not let its text imply the debris problem is solved —
   the ADR says plainly that it is not.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
