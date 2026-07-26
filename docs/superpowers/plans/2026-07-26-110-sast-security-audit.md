# Implementation plan — #110 SAST job and `security-audit` skill

- **ADR:** `docs/architecture/ADR-0056-110-sast-security-audit.md`
- **SPEC:** `SPEC.md` / `docs/specs/110-sast-security-audit.spec.md`
- **Branch:** `feat/110-sast-security-audit` (stacked on `feat/109-proportional-audit-depth`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**The version pin is load-bearing, not hygiene** (ADR-0056 §D2). An unpinned scanner reintroduces
exactly the machine-dependent verdict ADR-0039 §D4 removed.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/sast-security-audit.test.sh`.
  `S`-prefixed labels, hermetic, bash 3.2. Sections: **SA** the `security-audit` job exists in the
  CI template, is **separate** from `ci` and from `checks`, and is **opt-in** via a repo marker;
  **SB** **the Semgrep version/digest is pinned** — assert no `:latest`, and assert an explicit
  version or digest is present (this is §D2's guard and the single most important assertion in the
  file); **SC** the ERROR-blocks / WARNING-INFO-prints split of §D3; **SD** the skill exists with
  all ten protocol steps present and individually identifiable; **SE** the skill **reports and does
  not fix** (§D4) — assert it does not dispatch a fixing agent, consistent with
  `deep-refactor:272` and `review-triage-fix:104`; **SF** the OWASP Top 10 is named **with an
  explicit year** (§D5), and the skill's own text states the year is a maintenance obligation;
  **SG** the separate-AI review step pins a **different model** and states that same-model
  self-review does not satisfy it (§D6); **SH** registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — and note `protect-files.sh` denies any path containing `secrets`, so name files
  with the singular (ADR-0046).

- [ ] **Task 2 — the CI job.** Opt-in `security-audit` job in
  `staging/project-templates/ci/ci.yml`, separate from `ci` and `checks`. Pinned Semgrep version or
  digest; pinned ruleset. Opt-in marker follows the shape of ADR-0022's `publish: true` /
  ADR-0053's `.claude/protected-interfaces` — pick one and say which you followed.
  → SA/SB/SC green.

- [ ] **Task 3 — the `security-audit` skill.** `staging/plugin/skills/security-audit/SKILL.md`,
  implementing the ten-step protocol as an on-demand checklist run. Report-only (§D4). Follow the
  house SKILL.md structure of a sibling — `deep-refactor` is the closest analogue in shape.
  → SD/SE green.

- [ ] **Task 4 — training-cutoff compensation.** Name the OWASP Top 10 **by year** (§D5), and state
  in the skill's own text that the year is a fact with an expiry date and a stale year is worse than
  no year because it reads as current. → SF green.

- [ ] **Task 5 — the separate-AI review step.** Dispatch a subagent with a **different `model` pin**
  and a security-only brief; state plainly that a same-model self-review does not satisfy the step
  (§D6 — this is the generator/verifier problem of ADR-0049 reappearing in the security domain).
  → SG green.

- [ ] **Task 6 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `proportional-audit-depth`). `PAIRS` entry for the new skill's `SKILL.md` — note
  `pairs-completeness.test.sh`'s `check_complete` covers `plugin/skills/*/SKILL.md`, so a missing
  entry fails CI there; verify that is what happens rather than assuming. Then run every
  `staging/plugin/scripts/tests/*.test.sh`.
  **Run the full suite AFTER `git add`, not before** — `secret-dep-gate.test.sh` D1 scans
  `git ls-files`, so an untracked new file is invisible to it and a finding the commit introduces
  cannot be seen by a pre-commit run. This cost #108 a regression. → SH green.

## Risk flags

1. **An unpinned scanner.** Looks like convenience, is actually a reversal of ADR-0039 §D4. SB is
   the guard.
2. **A stale OWASP year** reads as current and is worse than none. SF can assert a year is named; it
   cannot assert it is right. Say so.
3. **Semgrep default rules are not a security programme.** They catch known patterns. Do not let the
   skill's language imply coverage of design-level vulnerabilities.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
