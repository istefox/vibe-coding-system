# Implementation plan — #115 Human-gate coverage (H4, H16)

- **ADR:** `docs/architecture/ADR-0061-115-human-gate-coverage.md`
- **SPEC:** `SPEC.md` / `docs/specs/115-human-gate-coverage.spec.md`
- **Branch:** `feat/115-human-gate-coverage` (stacked on `feat/114-external-dependency-gate`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers** — this SPEC declares none; an undeclared citation is an `ORPHAN`,
exit 3 from `spec-coverage.sh`.

**H16 triggers on evidence, never on a counter** (ADR-0061 §D2). A periodic prompt with no signal
behind it becomes furniture and trains the reflex click that makes it useless when it matters.

## Task checklist

- [ ] **Task 1 — RED harness.** `staging/plugin/scripts/tests/human-gate-coverage.test.sh`.
  `H`-prefixed labels — grep the existing 37 files to confirm the prefix is unused (note
  `reward-hack-detectors.test.sh` uses `HA`–`HH`, so pick a non-colliding form and say which).
  Hermetic, bash 3.2. Sections: **the test diff is its own labelled section** in `commit` Step 4,
  distinct from the file list; **it is omitted entirely when no test files changed**, not shown
  empty (§D1); **the diff is shown, not summarised** (§D4) — assert no LLM-summary step stands
  between the diff and the human; **truncation is labelled** with the command to see the rest, and
  assert silent truncation is impossible; **H16's trigger reads accumulated evidence** —
  `budget_findings`, out-of-scope findings, tracer `amber`/`red`, recurring `suspect_findings` —
  and assert **no fixed-cadence counter exists** (this is §D2's guard and the most important
  assertion in the file); **H16 asks and does not block** (§D3); registration in both CI registries.
  Every assertion seen RED first. No fixture path may contain `secret`, `credential`, `.env`,
  `.pem`, `.key` — `protect-files.sh` denies any path containing `secrets` (plural).

- [ ] **Task 2 — H4 in `commit` Step 4.** Test diff as its own section, omitted when empty, real
  diff not a summary, truncation labelled with the full command. Reuse the test-file predicate that
  already exists rather than writing a third one — `weakening-scan.sh` and ADR-0053 §D4 each have
  one, and ADR-0048 §D-predicate records that they diverge **on purpose** (discovery must not
  over-match, denial must not under-match). Pick the one whose error direction fits *showing* a diff
  and say why in a comment.

- [ ] **Task 3 — H16 trigger.** Reads signals four earlier features already collect. **No new
  measurement and no new advisory array** — ADR-0052 §D5 is explicit that the advisory load is the
  live risk. Surfaces the question with the evidence that raised it, records the answer, does not
  halt.

- [ ] **Task 4 — where H16 lives.** Decide and justify: `project-conductor` between features is the
  natural seam, since it is the only component that sees a roadmap rather than a feature. Check
  whether the evidence it needs is reachable there — `step5-report.json` is per-feature, so
  accumulating across features may need the conductor to read several. Say what you found; if the
  data is not reachable, say so rather than inventing a store.

- [ ] **Task 5 — registration + full suite.** New test file into **both** CI registries (`ci.yml`
  glob automatic; `.github/workflows/docs-ci.yml`'s explicit named list needs a manual append after
  `external-dependency-gate`). Then run every `staging/plugin/scripts/tests/*.test.sh`.
  **Run the suite AFTER `git add`** — `secret-dep-gate.test.sh` D1 scans `git ls-files`.
  Also: check whether any harness pins the repo-root `SPEC.md`, which the chain overwrites per
  feature — #114 had to fix exactly that in #113's file. A pin whose subject rotates is not a pin.

## Risk flags

1. **H16 on a timer.** The obvious implementation and the one that makes it furniture. The
   no-fixed-cadence assertion is the guard.
2. **Summarising the test diff.** Puts a generated artefact between the human and the thing they are
   verifying, defeating the gate — same objection ADR-0057 §D3 made to a self-assessed verdict.
3. **`commit/SKILL.md` has no test coverage of its own** (ADR-0046 recorded this). This change lands
   in a file pinned only indirectly, so the new harness is doing more work than usual.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
