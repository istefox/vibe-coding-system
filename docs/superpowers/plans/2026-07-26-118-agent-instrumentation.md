# Implementation plan — #118 Agent-level instrumentation metrics

- **ADR:** `docs/architecture/ADR-0064-118-agent-instrumentation.md`
- **SPEC:** `SPEC.md` / `docs/specs/118-agent-instrumentation.spec.md`
- **Branch:** `feat/118-agent-instrumentation` (stacked on `feat/117-canonical-mechanism-conformance`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none.

**Absent means "not recorded", never zero** (ADR-0064 §D3). Defaulting an unmeasured metric to 0 is
the tempting simplification and it destroys the dataset the feature exists to build.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/agent-metrics.test.sh`.
  `G`-prefixed labels — grep the existing 40 files to confirm the prefix is unused. Hermetic, bash
  3.2. Sections: **GA** all four metrics appear in the `step5-report.json` and `nightly-report.json`
  schema blocks as **additive, conditional-if-present** fields; **GB** **absent is distinguishable
  from zero** (§D3) — assert the read contract says so explicitly and that no default-to-zero exists
  anywhere; **GC** every metric is **computed, not self-reported** (§D4) — assert none is sourced
  from an agent's narrative; **GD** the metrics are **not surfaced at Gate 5** and **not counted in
  the advisory roll-up** ADR-0052 §D5 added (§D2 — this is the assertion that keeps the feature from
  worsening the recorded advisory-load risk); **GE** no estimated sub-agent token cost is introduced
  (§D5), and `usage-report.py`'s existing not-locally-observable note is intact; **GF** no rut
  detector and no threshold exists (§A5) — assert the absence; **GG** registration in both CI
  registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — the four metrics.** Test-count delta and deleted lines from git; iteration count and
  elapsed wall time from the dispatch loop. Wire into c2c Step 5's report writing.
  Reuse the existing test-file predicate rather than adding a fourth — ADR-0048 records that the
  existing ones diverge on purpose, so pick the one whose error direction fits *counting tests* and
  say why. → GA/GC green.

- [ ] **Task 3 — the read contract.** State in both schema blocks that absent means not recorded and
  must not be read as zero (§D3). Note this is the same rule as ADR-0046's exit codes and ADR-0043's
  completeness check, applied to stored data. → GB green.

- [ ] **Task 4 — keep them out of Gate 5.** Metrics are not findings: no claim attached, no decision
  requested. Not in the advisory roll-up, not presented as actionable (§D2). → GD/GE/GF green.

- [ ] **Task 5 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `canonical-mechanism`). Then run every `staging/plugin/scripts/tests/*.test.sh` — this touches
  `step5-report.json`'s schema, so `weakening-wiring.test.sh`, `spec-coverage.test.sh`,
  `diff-budget-scope.test.sh` and `human-gate-coverage.test.sh` are the regression readers.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`. → GG green.

## Risk flags

1. **Defaulting absent to zero.** Makes every historical task look well-behaved and poisons the
   dataset. GB is the guard.
2. **Surfacing metrics at Gate 5.** Would add four lines to a gate whose advisory load ADR-0052 §D5
   already recorded as the live risk, degrading the findings that do need action. GD is the guard.
3. **This ships data collection with no consumer.** Say so; do not let the text imply rut detection
   exists. Building it now would mean inventing thresholds against an empty corpus, which ADR-0051
   established this system does not do.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
