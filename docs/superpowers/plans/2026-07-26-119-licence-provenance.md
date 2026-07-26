# Implementation plan — #119 Licence and provenance scanning

- **ADR:** `docs/architecture/ADR-0065-119-licence-provenance.md`
- **SPEC:** `SPEC.md` / `docs/specs/119-licence-provenance.spec.md`
- **Branch:** `feat/119-licence-provenance` (stacked on `feat/118-agent-instrumentation`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none.

**Nothing here is legal advice, and the text must not imply it is** (ADR-0065 §D4). A green licence
scan reads as "we are clear", and that reading is wrong in a way that could actually harm someone.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/licence-provenance.test.sh`.
  `P`-prefixed labels — note `proportional-audit-depth.test.sh` already uses `PA`–`PG`, so grep the
  existing 41 files and pick a non-colliding form; say which. Hermetic, bash 3.2. Sections:
  the licence-scan job exists in the CI template, is **separate and opt-in** via a repo marker, and
  its tool version is **pinned** — assert no `:latest` (§D1, ADR-0056 §D2's rule applies unchanged);
  findings **report, never block** (§D3); the **suspicious-output procedure** is in
  `clean-public-repo`'s audit phase as a documented human check (§D2); **no verbatim-reproduction
  detector exists** — assert the absence, which is the decision; **no text overclaims** (§D4) —
  assert the not-legal-advice statement is present and that nothing says the tree is "clean" or
  "compliant"; `clean-public-repo`'s **refusal to falsify authorship is untouched** (§D5) — a
  regression guard on ADR-0011/ADR-0026; registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — the CI job.** Opt-in licence-scan job in `staging/project-templates/ci/ci.yml`,
  following the `security-audit` job's shape from ADR-0056 exactly — separate job, marker-based
  opt-in, pinned version. Do not invent a second pattern. Reports; does not fail the build.

- [ ] **Task 3 — the suspicious-output procedure.** Add to `clean-public-repo`'s audit phase: if
  output looks verbatim (distinctive comments, author names, unusual identifiers), search a unique
  string before keeping it. **A documented human check, not a script** — it needs a judgement about
  distinctiveness and a network search, neither reproducible in CI.

- [ ] **Task 4 — the not-legal-advice statement.** In the skill text and the CI job. Say what the
  check does and does not establish: it reports declared metadata, and it cannot see verbatim
  reproduction of an unattributed snippet, which is the risk the spec actually names.

- [ ] **Task 5 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `agent-metrics`). `clean-public-repo/SKILL.md` is covered by `pairs-completeness.test.sh` —
  verify rather than assume. Then run every `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`.

## Risk flags

1. **Overclaiming.** A green scan is not a clean tree. The not-legal-advice assertion is the guard,
   and this is the same class of overclaim ADR-0059 §D1 refused for prompt injection.
2. **Building a verbatim detector.** Needs distinctiveness judgement plus a network search. Assert
   its absence.
3. **Weakening the authorship refusal.** ADR-0011/ADR-0026 settled it; provenance scanning must
   notice contamination, never provide a route to hiding it. Regression-guard it.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
