# SPEC — literal-assertion-added shipped disabled at 25 percent precision and nothing has re-measured it

Source: GitHub issue #314

## Objectives

1. Re-run the `literal-assertion-added` detector over the commit corpus as it stands today and
   compute precision against a hand-classified sample, stating the sample size and the method. The
   25% figure is from an older and smaller sample and may now be better or worse.
2. Enable it or retire it on that number rather than on taste — a detector kept disabled "for now"
   is the outcome this issue exists to end.
3. If it is enabled, re-examine ADR-0061 §H16's inherited trigger in the same change.

## Scope

In: the `literal-assertion-added` SUSPECT detector inside `weakening-scan.sh`, its
`WEAKENING_SCAN_LITERAL_ASSERTION=1` opt-in, the precision measurement, the enable-or-retire
decision, and ADR-0061 §H16's trigger if the answer is enable.

Out: the other detectors that shipped in the same batch (`zero-assertion-test`,
`deleted-public-symbol`, `swallowed-error`) except where the decision touches the shared `SUSPECT`
sentinel; the `WEAKENED` rules and the `^WEAKENED` caller idiom; the in-place assertion blind spot,
which is issue #311's subject.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh` — the detector's home. Its
  header records that `SUSPECT` is a separate sentinel from `WEAKENED` and deliberately does not
  match `^WEAKENED`, and that the awk interval-syntax probe (`AWKGUARD`) runs only when the opt-in is
  set, because `literal-assertion-added` is the only detector needing `{2,}`.
- `staging/plugin/scripts/tests/reward-hack-detectors.test.sh` — the existing harness. Section HA
  pins that the detector does NOT fire without `WEAKENING_SCAN_LITERAL_ASSERTION=1` (HA4a) and DOES
  fire with it (HA4b); HB4 pins that it requires both halves of an impl+test co-change; HD4/HD5 pin
  that its output never matches `^WEAKENED`; HC5 covers the awk-guard path. Any enable-or-retire
  decision changes HA4a's expectation and must be reconciled with it deliberately, not relaxed.
- `docs/architecture/ADR-0051-105-reward-hacking-detectors.md` — the source. The issue cites a line
  number for "shipped disabled at 25% precision" and "cannot distinguish legit from cardboard"; that
  line number will have moved, so those phrases are the anchors. §D1 (both halves required) and §D5
  (the measurement that led to shipping disabled) are the decisions in scope.
- `docs/architecture/ADR-0061-115-human-gate-coverage.md` — §H16, which records that its trigger
  inherits every upstream false-positive rate including this one; in scope only if the detector is
  enabled.
- The four `^WEAKENED` call sites wired by ADR-0047 (`concept-to-code`, `autopilot-build`,
  `nightly-autopilot`, `commit` SKILL.md) — unaffected by a `SUSPECT`-only change, which is the
  property HD4 exists to keep.
- The corpus: this repository's own `git log`, sampled to the commits touching a test file, which is
  substantially larger than at ADR-0051 time.
- `staging/plugin/scripts/tests/plant-check.sh` and the plant registry (ADR-0108).

## Data model

None persistent. The measurement's working data is a hand-classified sample of detector hits over
the commit corpus: per hit, the commit, the file, and a true/false-positive judgement. The sample
size and classification method are themselves a required output (R-01).

## API / Interfaces

- `weakening-scan.sh` — reads a unified diff on stdin, writes `CLEAN`, `WEAKENED<TAB>…`,
  `SUSPECT<TAB><file><TAB><detector>` or `AWKGUARD` lines to stdout, always exits 0.
- `WEAKENING_SCAN_LITERAL_ASSERTION=1` — the opt-in environment variable that today gates the
  detector. Whether it survives, becomes the default, or disappears is the R-02 decision.
- `WEAKENING_SCAN_AWK` — the existing override used by the harness to simulate an awk without
  interval support.

## UI flows

None. Output is scan text consumed by an orchestrator at a gate and by a human reading a Step 5 or
`commit` Step 1 report.

## Edge cases

- A retire outcome must remove the detector rather than leave it disabled with a note, or the issue
  reproduces itself: "a disabled detector is a feature nobody can rely on and nobody remembers to
  delete."
- An enable outcome changes what a `SUSPECT` line means downstream, and ADR-0061 §H16's trigger
  inherits the rate directly (R-03).
- The awk interval-syntax probe currently runs only under the opt-in; enabling the detector by
  default makes that probe run on every invocation, so its `AWKGUARD` path becomes a live outcome
  rather than an opt-in one.
- Precision is measured against a hand-classified sample, so the classification rule must be stated
  — ADR-0073 measured two hits and found both were prose, which is the same class of judgement.
- A detector that fires more often is not automatically better: adding noise makes the `CLEAN` line
  mean less rather than more (the argument already in the script header for ADR-0048 §D7).
- `SUSPECT` must keep not matching `^WEAKENED` whatever the outcome, or all four ADR-0047 call sites
  change behaviour silently.
- Rule 12: a needle containing `literal-assertion-added` matches the harness comments and the script
  header that explain the detector, including this feature's own files.

## Success criteria

- [ ] R-01 — precision re-measured on the current corpus, with the sample size and method stated.
- [ ] R-02 — enabled or retired on that number, not on taste. A detector kept disabled "for now" is
      the outcome this issue exists to end.
- [ ] R-03 — if it is enabled, ADR-0061 §H16's inherited trigger is re-examined in the same change.
