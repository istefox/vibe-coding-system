# ADR-0073 — What the Step 5 → Step 6 gates do not see: one disclosure, one recorded blind spot

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issues #178 and #177
- **Extends:** ADR-0047 (`weakening-scan.sh` wiring), ADR-0051 (the SUSPECT sentinel and its
  measurement precedent), ADR-0052 §D5 (the six-array roll-up and its bound)
- **Reported as:** two observations from reviewing the first end-to-end chain run, neither of which
  was a failure anyone hit.

## Context

Two issues from the same review, at the same boundary, with opposite answers. They are decided
together because deciding either alone would have got the other wrong.

**#178 — nothing compares the implementation against the approved plan.** The plan specified three
Pydantic bounds. The coder declared none of them, for a defensible reason accepted at Gate 5: with
no `RequestValidationError` handler registered, a Pydantic bound makes FastAPI return `detail` as a
list of error objects, so the SPEC's `R-03` substring assertion fails and the operator loses the
engine's Italian message. The deviation was probably correct. The problem is *how it was found* —
the orchestrator read the diff. Every existing gate measures something adjacent and passes it:
`spec-coverage` (the id was cited and tested), `weakening-scan` (tests were added),
`interface-check` (a validator is not a signature change), `diff-budget` (smaller, if anything).

**#177 — `weakening-scan.sh` cannot see an assertion relaxed in place.** `assert-removed` is a count
comparison, `asrt_rm > asrt_add`. Editing an assertion in place removes one assert-bearing line and
adds one, so the counts are equal and the rule cannot fire. Flipping `is True` to `is False` to match
whatever the implementation produces is the textbook weakening move and is invisible to every
detector in the file.

## Decision

### D1 — #178: disclose the deviation; do not gate it

`step5-report.json` gains an additive `plan_deviations` array — the fifth extension on the same
terms as `step5_mode`, `checkpoint_reviews`, `weakening_findings` and `requirement_coverage`. No
schema version bump. The coder's brief asks for a terminal `PLAN DEVIATIONS:` block, with an
explicit `none` form so an omitted block is distinguishable from an unasked question.

**It is never a failure signal, in any mode.** Deviating is legitimate and frequently correct — a
plan is written before the code is read. What is not legitimate is deviating silently, because the
human approving Gate 5 then has to find it by reading a diff.

The trap in a self-report is real and stated at the call site: this system's own rule is not to
trust an agent's self-report *as the gate* (ADR-0047 §A3, RTF Step 3). That rule is about gates. A
disclosure feeding a human decision is the opposite case — **a coder that hides a deviation leaves
the reviewer exactly where it was before the field existed, so the field can only add information,
never remove a check.** Nothing verifies it, and nothing may be built on it as if something did.

### D2 — #178: the Step 6 reviewer is briefed with the plan (the issue's option 2, decided yes)

Phase 1's reviewer prompt now names the plan path and asks for plan conformance as an explicit lens.
Cost: nothing structural.

The prompt also states that **a departure is not automatically a defect**, and that the reviewer
should judge it on the code at whatever severity the departure itself warrants. Without that
sentence the lens becomes the conformance gate §D3 rejects, implemented by prompt rather than by
code — and its most likely first act would be to block a correct deviation like the one that
prompted the issue.

`plan_deviations` is given to the reviewer as a starting point, explicitly never as the complete set.

### D3 — #178: no conformance gate, and the reason is structural

A mechanical plan-conformance check would have to parse prose. A plan is prose; "the coder chose a
better approach" is a legitimate and frequent outcome the chain must not block. `deep-refactor` and
`review-triage-fix` both treat judgment calls as report-only for exactly this reason.

Recorded so it is not rediscovered as a gap: **plan conformance is deliberately unchecked
mechanically.** Before this ADR nobody had decided that; it simply never came up.

### D4 — #177: no detector, and the reason is measured

The acceptance criteria required a false-positive rate measured against this repository's own
history before shipping any detector. Measured over the last 354 commits, 89 of which touch a test
file, a rule on `asrt_rm == asrt_add > 0` fires **twice**. Both hits are **prose**: a comment
containing the word "assertion", and an `ok "…"` message containing "asserts". Precision on the
observed sample: **0 of 2**.

That number is secondary to the structural argument, which is that the diff shape is ambiguous by
construction — correcting a wrong test and relaxing a right one produce byte-identical diffs. No
rule over a diff separates them. A detector would report "an assertion changed", which is ordinary
test maintenance, and a signal that is always wrong is one its readers learn to dismiss. That makes
the `CLEAN` line mean *less*, not more (ADR-0048 §D7).

ADR-0051 §D5 hit the same wall on this same script and shipped `literal-assertion-added` disabled by
default. This applies that precedent one step earlier: not shipped at all.

**What ships is the sentence.** `weakening-scan.sh`'s header now states what `CLEAN` does not cover,
names the mechanism, records the measurement, and records that no detector was added. Both callers —
`concept-to-code`'s Step 5 gate block and `commit`'s Step 1 block — say the same at their own call
sites, because the person reading a CLEAN line is reading it there, not in the script.

The `commit` block additionally points at its **Test diff** section (ADR-0061) as the thing that
actually covers this class: it is the only step in the flow that puts a changed assertion in front
of a human. That is a human step, and this ADR does not pretend otherwise.

### D5 — `plan_deviations` renders at Gate 5 outside the six-array roll-up

ADR-0052 §D5 bounded that roll-up deliberately: six arrays arrived in consecutive features, each
justified by "blocking would be too noisy, so we surface instead", and the failure mode is not one
unreadable array but six readable ones stacked into a summary that gets skimmed.

The exclusion here is **semantic**. The six are *findings* — each asserts something may be wrong and
asks whether to run a review cycle. A plan deviation asserts nothing is wrong; it asks a different
question ("is this departure acceptable"), and folding it into a summary about review-cycle volume
would bury the one thing that needs reading. Rendered on its own line, immediately before the
roll-up, only when non-empty, with the self-report clause inline.

## Alternatives considered

### A — Add the in-place detector anyway, on SUSPECT, disabled by default

Rejected. It is the shape ADR-0051 §D5 already produced once, and a second permanently-disabled
detector is code nobody runs plus a config knob nobody turns. The measurement does not support
enabling it, and the structural argument says no measurement ever will.

### B — Make `plan_deviations` a failure signal when non-empty

Rejected. It would halt the chain on the correct outcome — the deviation that prompted #178 was
sound — and it would make a self-report load-bearing, which is precisely the arrangement ADR-0047
§A3 refuses. An agent graded on its own disclosure learns not to disclose.

### C — Fold `plan_deviations` into the six-array roll-up

Rejected per §D5.

### D — Decide #177 and #178 separately

Rejected in practice. They are the same question asked twice — what does this boundary not see —
and the answers are opposite for reasons that only make sense side by side: #178's gap gets a
disclosure because a human can act on it; #177's gap gets a sentence because no mechanism can
separate the two cases and a human reading the test diff already can.

## Consequences

### Positive

- A declined plan constraint becomes a declared act rather than something the orchestrator has to
  notice while reading a diff.
- The Step 6 reviewer gains a lens it did not have, at no structural cost.
- `CLEAN` from `weakening-scan.sh` stops reading as "no weakening occurred" at all three places
  someone encounters it.
- Two absences that were implicit are now decisions on record.

### Negative

- **`plan_deviations` is unverified and always will be.** A coder that deviates without declaring is
  exactly as invisible as before. The field's value is entirely in the honest case, and its risk is
  that a future reader treats a short list as evidence of few deviations.
- **The in-place blind spot remains open.** Documented, measured, and unclosed. Anyone relying on
  the weakening gate for assertion integrity is relying on something that does not exist.
- The reviewer lens is prose in a prompt. Nothing enforces that the reviewer reads the plan, and a
  reviewer that ignores the instruction leaves conformance unchecked with no signal.

### Neutral

- No manifest field, no schema version bump, no state-machine change, no new stdout token.
- `weakening-scan.sh`'s behaviour is byte-unchanged: only its header moved.
- Inert until sync.

## References

- Issue #178, whose own fix-direction ranking (disclose > brief the reviewer > gate) this follows
- Issue #177, including the acceptance criterion that made the measurement mandatory
- `docs/architecture/ADR-0051-105-reward-hacking-detectors.md` §D2, §D5 — the SUSPECT sentinel and
  the disabled-by-default precedent this declines to repeat
- `docs/architecture/ADR-0052-106-diff-budget-scope-check.md` §D5 — the roll-up bound
- `docs/architecture/ADR-0061-115-human-gate-coverage.md` — the commit-gate test diff, the human
  step that covers what §D4 leaves uncovered
- `staging/plugin/scripts/tests/step5-checkpoint-review.test.sh` section E,
  `staging/plugin/scripts/tests/weakening-wiring.test.sh` section WJ
