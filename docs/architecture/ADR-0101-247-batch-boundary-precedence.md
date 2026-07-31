# ADR-0101 — Two batch-boundary rules that cannot both be satisfied, and a red checkpoint nobody had defined

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #247 (found by the Phase 7.1 shakedown run at the Step 5 batch-1 checkpoint),
  #273 (split out of it — the mechanism, deferred here)
- **Related:** ADR-0088 §D5 (the rules this corrects, shipped four hours earlier), ADR-0049 (the
  tester-then-coder-per-batch assumption), ADR-0020 (autopilot-build's circuit breaker), ADR-0091
  (#246, the live warning about plan-side declaration syntax), ADR-0034 (bodies not edited in place)

## Context

The batch-1 checkpoint for #222 ran the real test command and one file failed:

```text
FAIL: S1: skill(s) neither covered nor declared: ui-layout-audit
PASS=14 FAIL=1
```

Nothing was broken. Task 2 vendors `ui-layout-audit/SKILL.md`, which puts it into
`skill-coverage-perimeter.test.sh`'s population; **Task 3's `C7` is what covers it**. So `S1` is red
between task 2 and task 3 by design, and #222's SPEC predicted it in those words.

**This corrects a rule I shipped four hours earlier, not a defect someone else left.**

### The two rules conflict on the plan the ADR uses as its worked example

ADR-0088 §D5 states both as if they were jointly satisfiable:

1. do not put an assertion in the same batch as the task it depends on;
2. do not split a red assertion from the task that turns it green.

Rule 1 forces task 3 into a **later** batch than task 2: `C7`'s RED must be *"the vendored file
exists but does not name gate 5.05"*, which the tester cannot observe before task 2 vendors it.
Rule 2 wants tasks 2 and 3 **together**, because `S1` reddens at task 2 and greens at task 3.

No batching satisfies both, and §D5 gave a reader applying it in good faith no way to choose.

### The measurement that shrank the issue

Issue #247 says an unattended run "would stop, write a `partial` report, and present a correctly-working
TDD sequence as a failure". Measured: `autopilot-build`'s circuit breaker reads
`.claude/step5-report.json` **after dispatch** — once, at the end of Step 5, not per checkpoint.
`S1` greens at task 3, inside Step 5, so that run would not have halted.

The claim holds only for an expected red that survives to the **end** of Step 5 — which is a plan
already violating rule 2 with no task to green it. **So the urgent half evaporates and the
documentation defect is what is left.** `BP6` pins the cadence the argument rests on, so a future
change to it fails loudly rather than invalidating this reasoning in silence.

## Decision

### D1 — Rule 1 outranks rule 2, and the reason is what carries forward

**Evidence quality beats checkpoint tidiness.** Violating rule 1 makes an assertion fail for the
*wrong reason*, so the recorded RED proves nothing and writing the test first bought nothing.
Violating rule 2 leaves an intermediate checkpoint red — visible, explainable, and resolved by a
later batch inside the same Step 5.

The verdict alone would be a coin toss written down. `BP2b` asserts the reason separately from the
verdict for that reason.

### D2 — A red intermediate checkpoint is defined, in three cases

ADR-0049's flow assumes the tester reddens and the coder greens **within the same batch**, so a
checkpoint should be clean. `S1` is neither half of that: it is a **pre-existing guard in a file
nobody in the batch touched**, whose premise the implementation changes and which a later task
restores. The chain had no concept of that.

- A red in a file this batch did not touch, which a later task restores → **expected**: name it,
  name the task that will green it, record it, continue.
- A red in this batch's own tests → **not expected**, and the case the checkpoint exists for.
- Neither description fits → **stop.** An unclassifiable red is the one that most needs a human.

The third case is the one that keeps this from being a licence. `BP4` asserts the negative half,
because a rule that only says what is excused excuses everything.

### D3 — This is a reading rule; the mechanism is deferred to #273, with the reason

Two mechanisms were considered. An **expected-red declaration** in the plan needs a new plan-side
syntax, and ADR-0091 is the live warning about what a half-parsed one costs. Comparing against the
**previous checkpoint's failing set** needs no syntax — but it distinguishes a *new* failure from a
*carried-over* one, not an *intended* one from an *unintended* one, and on #222's own plan `S1` is
new at checkpoint 1, so it would still be reported. Neither is the cheap win it looks like.

**`autopilot-build`'s breaker is deliberately not relaxed in the meantime.** Halting on red is
correct in the absence of a way to tell an expected red from a real one; `BP7` pins it as a forward
guard.

## Verification

11 assertions in `batch-boundary-precedence.test.sh`, plus a `Z1` floor. Harness 62/62.

Seen RED against the unmodified tree: **6 of 11** — `BP2`, `BP2b`, `BP3`, `BP4`, `BP5`, `BP8`.
`BP0`, `BP1`, `BP6`, `BP7` pass before and after: `BP1` and `BP7` are forward guards, `BP6` is the
measured premise.

Six planted defects, all fired:

| plant | fires |
|---|---|
| precedence sentence removed | `BP2` |
| precedence kept, **reason** removed | `BP2b` |
| one of the two rules deleted | `BP1` |
| the negative half of the expected-red rule removed | `BP4` |
| autopilot breaker relaxed to note-and-continue | `BP7` |
| the ADR-0088 correction removed | `BP5` |

**One plant needed its needle read out of the file rather than guessed.** `test_result = RED → halt`
is written with backticks around the code span, so a pattern joining the words with `\s+` cannot
span `` RED` → halt ``. Same family as ADR-0099's wrap lesson, one decoration over.

**And `BP3` failed against correct text on capitalisation alone** — the clause opens a sentence and
the needle was lower-case. Prose assertions in this file now match case-insensitively as well as
flat and undecorated: **a clause is the same clause whether it opens a sentence or sits inside one.**
Seventh member of that family here.

## Consequences

- **Nothing executable changes.** This ships a precedence rule and a reading rule — prose an
  orchestrator is asked to follow, the same instruction-not-enforcement boundary ADR-0047 and
  ADR-0048 record for their own gates. What changes is that a reader facing the conflict now has an
  answer and a reason.
- **The classification is a model's judgement with no verification.** #273 exists for that, and the
  breaker stays strict until it lands.
- **`BP6` couples this ADR's reasoning to `autopilot-build`'s breaker cadence.** If the breaker ever
  moves to per-checkpoint, the assertion fails and the argument here must be re-measured rather than
  quietly inherited.
- #222's plan text says `ui-layout-audit` "becomes part of `POP` for the first time this task" at
  task 3. Off by one — it enters at task 2. The plan is otherwise accurate and is left unchanged, as
  a historical record (ADR-0034 precedent).
- Inert until sync.
