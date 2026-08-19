# ADR-0156 — the stop gate's budget is spent by distinct failures, not by repeats

- **Topic slug:** `stop-gate-distinct-failure-budget`
- **Issue:** #477
- **SPEC:** none — a bounded change to one hook, no requirement ids, no coverage gate
- **Extends:** ADR-0137 §D4/§D5 (the ceiling and the shared budget). Supersedes nothing.
- **Deliberately does not close:** #273's half — a declared expected-red set both consumers can read

## Status

Accepted — 2026-08-18.

## Context

`stop-gate.sh` runs the project's `test-cmd` at the end of any turn that wrote a file, and blocks on
a non-zero exit. It has no notion of a declared or expected red, and it is not going to get one here
(D5). What it does have is an anti-loop counter, `$DIR/$SID.count`, capped at
`STOP_GATE_MAX_REENTRY` (default 3), after which it stands down for the rest of the session.

On any chain that produces a structurally red window — every tester-before-coder batch, by
construction (ADR-0049 §D1, ADR-0155) — the sequence is block, block, block, and then **the gate
stops looking**, at exactly the point where the first real regression can appear: the final batch,
where the coder is supposed to green what the tester left red.

The noise is the milder half. The mechanism disarming itself is the finding.

### Measured, 2026-08-18, on this machine

**M1 — the counter is written in two places and removed in none.** `$CF` is read and incremented
inside `emit_block` (lines 45, 51) and again on the timeout path (210, 213). The green path
(236-239) clears `$DIRTY` and `$OUT` and leaves the counter untouched. **A session that reaches the
cap is disarmed permanently**, and a subsequent green run does not restore it.

**M2 — 5 of 16 sessions that ever blocked ended disarmed.** Counter files under
`~/.claude/state/stop-gate/`: 16 total, distributed `10 × 1`, `1 × 2`, `5 × 3`. That distribution is
bimodal and the shape is the argument: a session that blocks **once** is a real red, seen and fixed;
the five at the cap are the structural windows, which spent the entire budget and then guarded
nothing for the remainder of their session. 31% is not an edge case.

**M3 — three blocks on one failure are one piece of information.** Every one of the five cap
sessions spent its budget on repeats of a failure the operator had already read. Nothing in the file
compares one failure to the previous one; the counter bounds *cost*, and it counts invocations
rather than findings.

**M4 — the timeout route is not the live one here, and that is a local fact, not a general one.**
This repository sets `.claude/test-timeout` to 300s against a measured 159s suite (ADR-0137 §D4).
The block route is what disarms sessions here. On a project without that file the 120s default and
`xcodebuild` compose into the same stand-down by the other door — which is why D4 leaves the timeout
path alone rather than assuming it is harmless.

*Rule 13 note, recorded because the `.claude/test-timeout` block asks for it explicitly: the suite is
**85** harnesses today against the **79** its 2026-08-14 measurement was taken on. The 300s ceiling
is not re-derived by this ADR and should be before it is trusted again.*

## Decision

### D1 — the budget is spent by DISTINCT failures

Before blocking, compare the failing output against the signature recorded for this session. The
counter increments only when the signature is **new**. A repeat of a failure already reported spends
nothing.

This is the whole fix. It follows from M3: the counter exists to bound cost, and a repeat costs the
operator nothing new because they have already read it.

### D2 — a repeat does not block either

A second, identical failure exits 0 without blocking. The operator was told once; telling them again
is the noise half of #477, and it is what made a correct Step 5 unclosable for six consecutive turns
on 2026-08-18.

**The pairing with D1 is what keeps this from being a bypass.** A *different* failure — which is
what a real regression is, by definition — has a different signature, so it blocks and it spends. The
gate is louder about new information and silent about old, which is the opposite of today.

### D3 — a green run clears the counter and the signature

A verified tree refreshes the budget. M1 shows the counter surviving a green run today, which is how
a session stays disarmed after the condition that disarmed it is gone.

### D4 — the timeout path is unchanged

ADR-0137 §D5 decided deliberately that a timeout spends the same counter, and signature-dedup cannot
apply there: a timeout produces no output to compare. Left exactly as it is, and the file says why,
so the asymmetry is a stated decision rather than something a later reader repairs by symmetry.

### D5 — the stand-down becomes visible, and the hook still learns nothing about the chain

At the cap the announcement moves into the `reason` `emit_block` emits, the channel an operator
actually reads. Today it is stderr only — and the file's own comment on the timeout path already
says why that is wrong: *a guard that stops guarding silently is this repository's signature
failure.* The block path stood down just as quietly.

`stop-gate.sh` continues to read only `$ROOT/.claude/`: `test-cmd`, `test-timeout`, the path list.
No manifest, no chain artifact. #477's fourth question — a declared expected-red set both this hook
and the Step 5 checkpoint could read — stays with **#273**, and building it here would trade away the
property that keeps this hook project-owned and chain-agnostic.

## Consequences

**Positive.** A structurally red window costs one block instead of the whole budget, and the budget
survives to catch the failure that matters. The disarm becomes visible. Nothing about the chain
leaks into a project-owned hook.

**Negative, stated rather than discovered later.** A persistent red is now reported once and then
tolerated silently for the rest of the session. That is a deliberate trade: today it is reported
three times and then tolerated silently anyway, having also destroyed the budget. The new behaviour
is strictly better on both axes, but it is still tolerance, and an operator who ignores the first
block gets no second reminder.

Signature equality is textual. A failure whose output varies run to run — a timestamp, a temp path,
a random seed — reads as new every time and spends the budget as it does today. That is the safe
direction (it degrades to current behaviour, never quieter), and it is a known limit rather than a
bug to discover.

**Not addressed.** The gate still cannot tell an expected red from a real one; it can only tell a
*repeated* red from a *new* one. That is a weaker property, and it is deliberately the one obtainable
without reading a chain artifact.

## Alternatives considered

**A1 — raise `STOP_GATE_MAX_REENTRY`.** Rejected: it moves the disarm threshold without changing
what spends it. A longer chain exhausts a larger budget just as reliably, and the operator gets more
noise on the way.

**A2 — never stand down.** Rejected: the anti-loop guard exists because a blocking Stop hook can trap
a session with no way out. Removing it trades a silent disarm for a hard lock.

**A3 — teach the hook to read the plan's expected-red table.** Rejected here and assigned to #273.
It is the better answer to the underlying question and the wrong thing to build in this file: it is
the one change that would make a project-owned hook depend on the chain's shape, and #273's consumer
is orchestrator-side, synchronous, and already reads the plan.

**A4 — key the signature on the exit code rather than the output.** Rejected on M3: a suite that
fails two different assertions exits `1` both times, so the two would dedupe into one and the second
finding would be silently dropped — a false negative in the direction the gate exists to prevent.

## References

- Issue #477, and its sibling #273 (the checkpoint consumer of the same missing concept)
- ADR-0137 §D4 (the ceiling), §D5 (one counter, one budget, spent by either failure mode)
- ADR-0049 §D1, ADR-0155 — why a structurally red window exists at every batch boundary
