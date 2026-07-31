# SPEC — The Step 5 checkpoint has no mechanism to tell an expected red from a real one

Source: GitHub issue #273

## Objectives

1. Give the Step 5 checkpoint a **mechanism** that decides whether a red intermediate checkpoint is
   expected, replacing the reading rule ADR-0101 shipped — a rule that "asks a model to judge, and
   nothing verifies the judgement".
2. Choose between the two candidates the issue names, or a third: **A** an expected-red declaration
   in the plan (checkpoint compares the failing set against the declaration rather than against
   zero); **B** comparison against the previous checkpoint's failing set, reporting only *new*
   failures.
3. Keep `autopilot-build`'s circuit breaker strict until such a mechanism exists, and make it
   *precise* rather than merely strict once one does.

## Scope

In: the Step 5 per-checkpoint red classification in
`staging/plugin/skills/concept-to-code/SKILL.md`; whichever of candidate A (a plan-side
expected-red declaration syntax, its parser, and its `MALFORMED`-on-a-recognisable-attempt
discipline) or candidate B (previous-checkpoint failing-set comparison) is selected; the forward
guard `BP7` in `staging/plugin/scripts/tests/batch-boundary-precedence.test.sh`.

Out: relaxing `autopilot-build`'s circuit breaker before a mechanism exists — the issue states this
as a carried constraint. Out: the batch-boundary precedence rule itself (ADR-0101, #247, already
shipped). Out: any change to the cadence at which the breaker reads `.claude/step5-report.json` —
measured in ADR-0101 as **after dispatch, once, at the end of Step 5, not per checkpoint**.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/SKILL.md` — Step 5's checkpoint review block, where
  ADR-0101's three-case reading rule is written today.
- `staging/plugin/skills/autopilot-build/SKILL.md` — the circuit breaker that reads
  `.claude/step5-report.json` after dispatch and halts on `test_result = RED` (ADR-0020).
- `staging/plugin/scripts/tests/batch-boundary-precedence.test.sh` — `BP4` (the negative half of the
  classification), `BP6` (the breaker cadence), `BP7` (the forward guard that pins the breaker
  strict until a mechanism lands).
- `staging/plugin/scripts/tests/step5-checkpoint-review.test.sh` — the existing checkpoint-review
  assertions (ADR-0039 D5).
- If candidate A is selected: a new plan-side declaration parser, sibling to
  `staging/plugin/skills/concept-to-code/scripts/diff-budget-check.sh` and its
  `staging/plugin/skills/concept-to-code/scripts/plan-task-predicate.awk` predicate — the live
  warning the issue cites is `diff-budget-check.sh`'s per-file `Budget:` half-parse (#246,
  ADR-0091).
- `docs/architecture/ADR-0101-247-batch-boundary-precedence.md` — the reading rule and the deferral
  this issue is split out of. Related anchors: ADR-0088 §D5, ADR-0049, ADR-0020,
  `docs/architecture/ADR-0091-246-per-file-budget-half-parse.md`.

## Data model

If candidate A is selected, the plan gains a declaration of the shape "assertion X is red between
task N and task M" — exact syntax TBD, and the issue names its risk explicitly: the syntax must be
recognisable enough to be `MALFORMED`-on-attempt rather than half-parsed.

`.claude/step5-report.json` may need an additive field to carry the checkpoint verdict. Field name
and shape TBD; no schema version bump, per the additive convention.

## API / Interfaces

TBD, and dependent on the candidate chosen. If a checker is written it branches on an exit code and
must distinguish "did not run" (exit 3) from "found nothing"; if a reporter is written it always
exits 0 and signals on stdout. The issue's own footer restates that the two idioms must not be
copied into one another.

## UI flows

None. The visible surface is the Step 5 checkpoint output and, on an unattended run, the
`autopilot-build` halt message.

## Edge cases

- **Candidate B does not answer the question #247 asked.** Measured in the issue: on #222's own plan
  `S1` reddens *because of* task 2, so it is new at checkpoint 1 and would still be reported. B
  distinguishes a **new** failure from a **carried-over** one, not an **intended** one from an
  **unintended** one.
- **Candidate A's syntax risk.** #246 is the live warning — a per-file `Budget:` line close enough
  to be half-parsed produced a false `SCOPE`, a ceiling two orders of magnitude wrong, and an
  inflated file count, all while looking like it worked.
- **A red that greens inside Step 5 never reaches the breaker**, because the breaker reads the
  report after dispatch. The issue's own correction to #247: the claim that an unattended run
  "would stop and present a correctly-working TDD sequence as a failure" holds only for a red
  surviving to the *end* of Step 5, which is a plan already violating the batch-boundary rules with
  no task to green it.
- **An unclassifiable red must stop.** ADR-0101's third case is what keeps the classification from
  becoming a licence; any mechanism must preserve it.
- Nothing is broken today, so a change here can only be judged against precision, not against a
  live failure.

## Success criteria

The issue states no numbered acceptance criteria. `R-01` is assigned to the single requirement the
issue states in its own words; no further criteria are invented.

- [ ] R-01 — **`autopilot-build`'s circuit breaker must not be relaxed until one of these exists.**
      Halting on red is correct in the absence of a way to tell an expected red from a real one.
      `batch-boundary-precedence.test.sh` `BP7` pins that as a forward guard.
