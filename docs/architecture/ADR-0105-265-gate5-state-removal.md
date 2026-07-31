# ADR-0105 — Gate 5 had a state nothing entered, and four siblings that never needed one

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #265 (found by the derived producer guard shipped with #248, on its first run)
- **Related:** ADR-0095 (#248, the guard that found it), ADR-0027 (a pair can be written and
  structurally unreachable), ADR-0057 (Step 4.5, the fourth inline sub-gate)

## Context

`gate_5_review_decision` was entered by nothing. Step 5 transitions to `step_6_review` and presents
Gate 5 from there, while Gate 5's own block asserted `Trigger: … current_step =
gate_5_review_decision`, the advisory roll-up spoke of *"the transition to"* it, and Step 7 listed
it as a valid source state. Four legal pairs, structurally unreachable.

Nothing aborted: Step 7's `step_6_review → step_7_commit` is legal, so the chain worked. **A state
the graph declared, the prose relied on, and no run had ever occupied.**

## The deciding argument, which neither of the issue's options named

Issue #265 offered *move the gate before the state* or *delete the state*, and weighed them by
size. §3
already documents a pattern for gates that do **not** get their own `current_step`:

> Gate 2b and Gate 5.05/5.06 are already inline sub-gates with no dedicated state, and Step 4.5
> follows the same shape.

**Gate 5 is the fifth instance of that pattern.** So the state is the anomaly, not the missing
producer, and deleting it makes Gate 5 consistent with four siblings rather than merely making the
graph smaller. The alternative would have added a fifth shape to a system that already had one.

Measured before deciding: **zero** manifests have ever carried `current_step:
"gate_5_review_decision"`. No record is invalidated.

## Decision

Delete the state: four pairs out of `manifest-transition.sh` (49 → 45), the entry out of
`manifest-validate.sh`'s valid steps, the arrow out of §3's graph, and the three prose sites
corrected to name `step_6_review`. The `smoke-e2e.sh` walk is re-routed through the transitions that
actually exist.

**The reason is written at Gate 5**, with `Do not reintroduce one` — because the next reader meeting
a gate without a state will otherwise fix what looks like an omission. `GR6` asserts that sentence.

The `# transition-producer-exempt:` entry ADR-0095 added is removed with the state: an exemption for
a target that no longer exists is a ghost, and `transition-producer.test.sh` `TP3` would flag it.

## Verification

15 assertions in `gate5-state-removal.test.sh`, plus a `Z1` floor. Harness 66/66. `GR10` and `GR11`
execute the transition script against a real manifest: the removed pair is refused, the surviving
one still works.

Seen RED: **10 of 15** — `GR1`, `GR2`, `GR3`, `GR3b`, `GR3c`, `GR4`, `GR5`, `GR6`, `GR7`, `GR10`.
`GR0`, `GR8`, `GR9`, `GR11` are the premise and the forward guards.

Five planted defects, all fired: one pair restored (`GR1`, `GR3`, `GR10`), the state restored to
`VALID_STEPS` (`GR2`), Gate 5's Trigger reverted (`GR4`, `GR5`), the inline-sub-gate reason removed
(`GR6`), a stale 49 left in the script comment (`GR3b`, `GR3c`).

### Five assertions pinned 49 and were updated, not relaxed

`E1`, `E2`, `E3`, `E7` in `concept-to-code-manifest-helpers-guards.test.sh` and `TBP1` in
`tracer-bullet-probe.test.sh`. `E7` is an exact live recount and stays exact; its comment now
carries both moves (48 → 49 by #111, 49 → 45 here).

**`TBP1` was changed in kind, not in number.** Its message claimed *"the one new amber/reduce-scope
pair was actually needed and is present"* while its test was `ACTUAL_PAIRS >= 49` — a total that
moves whenever any unrelated pair is added or removed, and never evidence about that pair. It now
asserts `ready_for_implementation,gate_2_architecture_review` directly, with a count guard to keep
the derivation from going vacuous.

### Two assertions of my own counted their own explanation

`GR1`'s first form was `grep -q "$GONE" "$TR"`, and the script legitimately names the state while
explaining why it no longer has one. Same for `GR5` against `SKILL.md`. Both now target the
**mechanism** — a pair line, an exemption line, a graph arrow, an asserted `current_step` — never
the name. **Rule 12, third and fourth instance today**, after `spec-archive.test.sh` `SA10` and
`gate0-recommendation.test.sh` `N9`.

And `GR1`'s count used `grep -c … || echo 0`, which produces `0\n0` on no match — **the exact idiom
issue #174 documented in this repository.** `|| true` is the fix.

## Consequences

- **The state machine is smaller by four pairs**, and `manifest-validate.sh` now rejects a manifest
  hand-edited to that state. Zero existing manifests are affected, measured.
- **`GR6` is the only thing stopping the state being re-added** as an apparent omission. It asserts a
  sentence, not a behaviour.
- The pair count is stated in three files and derived in one (`GR3`). Three chances to drift, one
  detector.
- Inert until sync.
