# ADR-0078 — A path on a finished chain is a record, not a precondition

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #197
- **Extends:** ADR-0076 §D4 (the boundary rule this applies), ADR-0075 (which chose `completed` for
  a narrower reason), ADR-0077 (the derive-the-premise instrument section A reuses)
- **Reported as:** a tracking issue derived from ADR-0075 §D5, filed to argue against the obvious fix.

## Context

`manifest-validate.sh` invariant 4 required `project_root` to be an existing directory in **every**
state. Five of this repository's own manifests carry
`project_root: /Users/stefanoferri/Developer/vibe-coding-system`, a path from a different machine,
and failed for that reason alone — 5 of 40, all `current_step: completed`.

The paths are not corrupt. They are accurate for the machine those chains ran on. What is wrong is
the invariant's unstated assumption: **that every manifest is validated on the machine that produced
it.**

## Decision

### D1 — The existence check is conditional on a terminal state; presence never is

`project_root` must still be present and non-empty in every state — a missing field is corruption at
any point. The **directory-exists** half applies only while the chain can still run.

This is ADR-0076 §D4's rule, which #197 was filed to receive: decide what a field means from the
manifest's `current_step`. It is also the first application of that rule to a *value* check rather
than to an absence.

### D2 — Terminal means ABSORBING, and that was verified against the state machine

`completed`, `failed`, `aborted`. Not asserted — checked: no transition pair in
`manifest-transition.sh` has any of the three as its **source**, and the unconditional
`any state -> failed|aborted` branch creates edges *into* two of them and none out. A manifest in
any of the three can never move again.

**Wider than ADR-0075's `completed`-only tolerance, deliberately.** That rule's argument is "a
finished chain cannot affect a future run", and it covers all three absorbing states identically.
ADR-0075 named one because one was all its two manifests had. Narrowing to `completed` here would
be following its letter past its reason.

### D3 — It cannot weaken a live path, and that is what makes it safe rather than merely convenient

Every consumer reads an in-flight manifest:

- `manifest-transition.sh` validates **pre-transition**, and a terminal manifest never transitions.
- `autopilot-build` check 2 runs the validator and then requires
  `current_step = ready_for_implementation` on the next line.
- `concept-to-code` Step parse reads the manifest of the chain it is running.

On every one of those the existence check is unchanged. `B4` pins it: an in-flight manifest with a
dead `project_root` still fails, and still fails *naming `project_root`*.

### D4 — Silent, not a note

The script's only output channel is `fail()`, and its main caller (`manifest-transition.sh`)
discards stderr. A note would reach nobody and would change the output of a script whose contract is
its exit code.

That is the opposite of ADR-0075's choice for nightly check 6, which prints a note — right *there*,
because a pre-flight is talking to an operator who is about to read the terminal.

### D5 — The five files stay byte-unchanged, which is the point of the issue

Rewriting five completed historical records to a path they were never created under falsifies the
record for no consumer. The issue exists to argue against that, and `C2` enforces it from the other
side: it asserts at least one manifest still carries a dead `project_root`, so `C1` cannot go green
the day someone "fixes" the five and leaves the exemption untested while looking covered.

### D6 — The premise is pinned, not the conclusion

Section A derives the absorbing set from `manifest-transition.sh` at run time and checks the
validator's exempt list — read out of the validator's own source — against it. Hardcoding
`completed, failed, aborted` in the test would pin today's answer rather than the reason for it, and
a future transition out of `failed` would silently make the exemption unsound with the test still
green.

`A0` count-guards the derivation (an empty pair table would make every state look absorbing) and
`A3` runs it in reverse (a live state must not be exempt, or an empty exempt list would satisfy
`A2`).

## Alternatives considered

### A — Backfill the five `project_root` values

Rejected per §D5. It is the option the issue was filed to argue against: it fixes this corpus and
nothing else, and it edits a record of where those chains actually ran.

### B — Drop invariant 4 entirely

Rejected. It is a real check on the path that matters. A live chain whose `project_root` does not
exist is a genuine defect and `B4` keeps catching it.

### C — Condition on `status` rather than `current_step`

Rejected. `status` is a separate enum (`in_progress|failed|completed|aborted`) that can legitimately
disagree with `current_step`, and the absorbing property is a fact about the **state machine**,
which is keyed on `current_step`. §D6's derivation would have nothing to check against.

## Consequences

### Positive

- All 40 manifests validate. Anything that iterates the corpus stops meeting five false failures.
- The invariant now says what it means: a path that must exist *while the chain can still use it*.
- The five records survive intact.

### Negative

- **A terminal manifest with a genuinely wrong `project_root` — a typo, not a machine difference —
  now passes.** Indistinguishable from the historical case by inspection, and the value of catching
  it on a chain that will never run again is close to zero. Accepted, not overlooked.
- The exemption is only as sound as the state machine. If a future transition makes `failed`
  resumable, §D6's `A2` fails — which is the design — but until someone reads that failure the
  window exists.
- `A0`, `A3`, `B5`, `B6`, `B7` and `C2` pass before and after. Forward guards, not fix evidence.
  `A1`, `B1`, `B2`, `B3` and `C1` are the five that were RED.

### Neutral

- No schema change, no manifest edited, no `PAIRS` change (`manifest-validate.sh` already has one).
- One new test file, registered in both registries.
- Inert until sync.

## Verification

Seen RED against the pre-fix validator: `B1`/`B2`/`B3` fail on the three terminal states, `C1` fails
naming **exactly the five manifests the issue names**, and `A1` correctly reports that it cannot read
an exempt list out of a validator that has none.

The fixtures are built by patching a **real** manifest. A hand-written minimal one trips five
unrelated invariants (artifacts on a completed status, `hitl_gates` count, `chain_path`), and a first
draft did exactly that — reporting "still invalid" with an empty `project_root` reason, a failure
about everything except the thing under test.

## References

- Issue #197, including the argument against backfilling that §D5 implements
- `docs/architecture/ADR-0076-195-additive-field-state.md` §D4 — the boundary rule
- `docs/architecture/ADR-0075-123-hook-verified-states.md` §D5 — where the five were first counted
- `staging/plugin/scripts/tests/manifest-project-root-terminal.test.sh`
