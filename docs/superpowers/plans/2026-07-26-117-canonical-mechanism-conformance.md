# Implementation plan — #117 Canonical-mechanism conformance

- **ADR:** `docs/architecture/ADR-0063-117-canonical-mechanism-conformance.md`
- **SPEC:** `SPEC.md` / `docs/specs/117-canonical-mechanism-conformance.spec.md`
- **Branch:** `feat/117-canonical-mechanism-conformance` (stacked on `feat/116-litter-debris-discipline`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`.

**No detector script** (ADR-0063 §D4). Recognising a hand-rolled equivalent needs to know what the
declaration meant; a grep for the symbol flags every legitimate low-level use.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/canonical-mechanism.test.sh`.
  `M`-prefixed labels — grep the existing 39 files to confirm the prefix is unused. Hermetic, bash
  3.2. Sections: **MA** the `.claude/rules/canonical-mechanisms.md` convention is documented, with
  `paths:` frontmatter and the one-line-per-mechanism form (§D1); **MB** `project-init` drafts it by
  detecting the dominant mechanism, and **proposes rather than writing silently** (§D2);
  **MC** `reviewer.md`'s Consistency checklist carries the conformance question at **MINOR** severity
  (§D3) — assert the severity, since a later "promotion" to blocking is the likely wrong turn;
  **MD** **no detector script exists** — assert the absence, which is the decision (§D4);
  **ME** absent file is inert, and the text says absent means "nobody declared", not "none exist"
  (§D5); **MF** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — the convention.** Document `.claude/rules/canonical-mechanisms.md`: flat list, one
  line per mechanism (`name → import path or symbol`), `paths:` frontmatter. Where the other rules
  conventions are documented is where this belongs — find it and follow it rather than starting a
  new section. → MA green.

- [ ] **Task 3 — `project-init` drafting.** Detect the dominant mechanism (most-imported HTTP
  client, logger, config module) and draft the file. Propose, do not write silently.
  Note §D2's reasoning is worth preserving in a comment: auto-derivation is sound *here specifically*
  because the property detected and the property declared are the same one — the canonical mechanism
  is the one already used most. That does not generalise; ADR-0055 §A4 rejected path-based
  auto-derivation of `risk` for the opposite reason. → MB green.

- [ ] **Task 4 — reviewer checklist.** Add the conformance question to `reviewer.md`'s Consistency
  checklist at MINOR. Additive; do not restructure. → MC green.

- [ ] **Task 5 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `litter-discipline`). `reviewer.md` and any changed rules file are covered by
  `pairs-completeness.test.sh` — verify rather than assume. Then run every
  `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`. → MF green.

## Risk flags

1. **Building a detector anyway.** MD asserts its absence. §D4 and ADR-0062 §D4 both explain why.
2. **Promoting the finding above MINOR.** MC pins the severity; a legitimate bypass exists for every
   canonical mechanism and a gate would be argued with until disabled.
3. **A stale declaration is worse than none** and nothing detects staleness. Say it; do not imply
   the file stays true on its own.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
