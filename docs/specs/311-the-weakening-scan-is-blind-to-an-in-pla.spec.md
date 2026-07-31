# SPEC — the weakening scan is blind to an in-place assertion edit

Source: GitHub issue #311

## Objectives

1. Reproduce ADR-0073's measurement before proposing anything: a rule on
   `assertions removed == assertions added > 0` over the commit corpus (354 commits at the time, 89
   touching a test) fired twice, both hits prose, precision 0 of 2. Extend the corpus to its current
   size and re-derive.
2. Ship nothing whose precision does not beat that 0-of-2 already on record.
3. If the honest answer is again that no diff-level rule works, record that as a decision and make
   the limit visible where a reader would otherwise assume coverage — while leaving the reporter
   contract byte-compatible for its four call sites.

## Scope

In: `weakening-scan.sh`'s blindness to an assertion whose body is gutted in place without a line
being deleted; the measurement over the commit corpus; the decision and its visibility at the places
a reader forms an expectation of coverage.

Out: changing the reporter contract (always exit 0, `CLEAN` on no finding, caller idiom
`grep -q '^WEAKENED'`); moving or copying `weakening-scan.sh` out of
`staging/plugin/skills/review-triage-fix/scripts/` (ADR-0047 invokes it in place at all call sites);
verifying that an implementation is correct, which no diff-level rule can do.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh` — the detector. Its header
  already carries a "WHAT `CLEAN` DOES NOT MEAN" section written for ADR-0073 §D4 / issue #177; the
  `WEAKENED` rules live in the awk block (`deleted-test-file`, `skip/xfail-added`,
  `assert-removed (rm>add)`, `test-removed-or-commented`), and `SUSPECT` is a deliberately separate
  sentinel that does not match `^WEAKENED`.
- The four call sites wired by ADR-0047, each of which greps `^WEAKENED`:
  `staging/plugin/skills/concept-to-code/SKILL.md` (the Step 5 → Step 6 boundary),
  `staging/plugin/skills/autopilot-build/SKILL.md`,
  `staging/plugin/skills/nightly-autopilot/SKILL.md`, and
  `staging/plugin/skills/commit/SKILL.md` (Step 1, whose **Test diff** section is what actually
  covers this class today).
- `docs/architecture/ADR-0073-177-178-what-the-gates-do-not-see.md` — the source; the issue cites a
  line number for the "in-place assertion blind spot stays open" disclosure, and that line number
  will have moved, so the sentence itself is the anchor.
- `docs/architecture/ADR-0051-105-reward-hacking-detectors.md` — §D5 hit the same wall on the same
  script and is the precedent for declining to ship on a precision number.
- `docs/architecture/ADR-0047-101-weakening-scan-wiring.md` — the wiring, the reporter/checker
  distinction, and the `printf '%s\n' "$out" | grep -q '^WEAKENED'` idiom the call sites must keep.
- `staging/plugin/scripts/tests/weakening-wiring.test.sh` and
  `staging/plugin/scripts/tests/reward-hack-detectors.test.sh` — the existing harnesses over the
  wiring and the detectors.
- `staging/plugin/scripts/tests/plant-check.sh` and the plant registry (ADR-0108).

## Data model

None. The measurement's working data is the commit corpus reachable from `git log` in this
repository, sampled to the commits touching a test file; no persistent record is implied beyond
whatever the decision records in the ADR.

## API / Interfaces

- `weakening-scan.sh` — reads a unified diff on stdin, writes `CLEAN` or
  `WEAKENED<TAB><file><TAB><reason>` lines to stdout, always exits 0. This contract is frozen by
  R-03. `SUSPECT` and `AWKGUARD` are existing sentinels on the same stream.
- The four caller idioms in the SKILL.md files named above, which must stay
  `grep -q '^WEAKENED'`.
- Whatever the measurement is run by: a throwaway measurement is acceptable input to the decision,
  but any shipped artifact takes the reporter or checker contract, not a blend.

## UI flows

None. Output is scan text consumed by an orchestrator at a gate, and by a human reading a Step 5 or
`commit` Step 1 report.

## Edge cases

- The structural argument that bounds every candidate rule: correcting a wrong test and relaxing a
  right one produce byte-identical diffs, so no rule over a diff separates them.
- An assertion gutted in place with no line-count change at all — the subject of the issue; every
  downstream gate reports `CLEAN`.
- The two hits ADR-0073 measured were both prose (a comment containing "assertion", an `ok "…"`
  message containing "asserts"), which is rule 12 appearing inside a detector's own needle.
- A rule that fires more often is not automatically better: the gate is wired into four paths that
  can produce a commit with no human present, so a false `WEAKENED` halts an unattended run.
- Adding a detector that cannot distinguish legitimate from illegitimate makes the `CLEAN` line mean
  less rather than more — the argument already written into the script's header for ADR-0048 §D7.
- If the outcome is a decision plus visibility, the visibility text is prose and must be asserted
  against a flattened, undecorated, case-insensitive copy, and its needle must belong to the
  mechanism rather than to the name of the thing it describes.

## Success criteria

- [ ] R-01 — measure first. **Ship nothing whose precision does not beat the 0-of-2 already on
      record**; ADR-0051 §D5 hit the same wall on the same script and ADR-0073 declined to ship for
      that reason.
- [ ] R-02 — if the honest answer is again that no diff-level rule works, the outcome is a decision
      recording it, plus making the limit visible where a reader would otherwise assume coverage.
- [ ] R-03 — the reporter contract is untouched: always exit 0, `CLEAN` on no finding, and the
      caller idiom stays `grep -q '^WEAKENED'` at all four call sites.
