# ADR-0155 — the tester's batch must leave the target building

- **Topic slug:** `compiled-language-tester-batch`
- **Issue:** #486
- **SPEC:** none — instruction-layer only, no requirement ids, no coverage gate
- **Extends:** ADR-0049 §D1 (tester before coder), ADR-0088 §D5 and ADR-0101 (the batch-boundary
  rules), ADR-0137 §D5 (the stop gate's shared budget). Supersedes nothing.

## Status

Accepted — 2026-08-18.

## Context

ADR-0049 §D1 dispatches the tester before the coder so it is *"briefed from the specification, never
from the implementation"*. Ordering, not an instruction, is what makes the separation real: a tester
briefed after the coder could read the implementation at no cost and with no trace.

That ordering carries an assumption nobody wrote down: **a failing assertion still compiles.** In
bash it does. The harness runs, prints `FAIL: RY1`, and the orchestrator compares the observed
failing set against the expected-red table the plan declares (ADR-0101).

In a compiled or type-checked language it does not. The tester writes a test referencing a type the
coder has not written, and the whole test target fails to build. Observed on a live chain run against
an external Swift/SwiftUI project on 2026-08-18:

```text
error: cannot find type 'GoogleBooksAPIKeyStoring' in scope
Testing failed:
      Cannot find type 'GoogleBooksAPIKeyStoring' in scope
      Testing cancelled because the build failed.
** TEST FAILED **
```

There are no red tests. There is no test run at all.

### What that costs, measured

**M1 — the chain has no concept of compilation.** `grep -ci 'compil'` over
`staging/plugin/skills/concept-to-code/SKILL.md`, ~4200 lines specifying the tester brief, the
batching rules and the checkpoint classification, returns **0**. This is not an omission in one
sentence; the machine was designed on an interpreted language and nothing states what happens
elsewhere.

**M2 — three downstream mechanisms lose their input at once.** The expected-red table cannot be
checked, because "the three declared reds" and "any regression" are the same string. The
controller-side checkpoint reads real counts rather than trusting the agent's report — correct, and
in this window there are no counts to read. A regression the coder introduces in an already-green
area produces the identical `** TEST FAILED **`.

**M3 — the stop gate dies twice over on this path, independently.** By budget: `stop-gate.sh` blocks
at most `STOP_GATE_MAX_REENTRY` times (default 3), then stands down for the session, and the counter
at `~/.claude/state/stop-gate/<session>.count` is written only in `emit_block` and the timeout branch
and cleared nowhere — measured on this machine, several sit at exactly `3`. Because this red window
is structural and recurs at every batch boundary, the budget is spent on declared reds almost
immediately, after which a genuine regression is unguarded. And by timeout: `TMO` defaults to 120s
and ADR-0137 §D5 charges a timeout to the same budget, so `xcodebuild test` can disarm the gate
having verified nothing at all.

**M4 — the mechanism already permits the fix.** `staging/plugin/scripts/test-write-scope.sh` line 69
is `[ "$AGENT_TYPE" = "coder" ] || { log_audit …; exit 0; }`. Everything that is not the coder passes
unconditionally. The tester is already free to write an interface declaration on a production path.
Nothing was blocking the correct behaviour; nothing instructed it.

## Decision

### D1 — a third batch-boundary rule, for compiled and type-checked languages

The tester's batch must leave the target **building**. The interface or type declaration its tests
reference lands with the tests, not with the implementation: **the tester owns the signature, the
coder owns the body.**

### D2 — it does not weaken ADR-0049, and the reason is what makes it safe

The guarantee ADR-0049 buys is that tests are written without seeing the implementation. A protocol
or type declaration is not an implementation — it is the interface, which is already this
repository's vocabulary in ADR-0053's protected-interfaces. A tester that declares
`protocol GoogleBooksAPIKeyStoring { … }` has read the specification, not the code that will satisfy
it.

The failure this prevents is not aesthetic. Without it the window produces a state no downstream
mechanism has a name for; with it the window produces red tests that compile, which is what every
downstream mechanism already assumes.

### D3 — precedence against the two existing rules

ADR-0088 §D5 and ADR-0101 state two rules and one tie-break: do not put an assertion in the same
batch as the task it depends on; do not split a red assertion from the task that turns it green;
when they conflict the first wins, because **evidence quality beats checkpoint tidiness**.

D1 outranks both. Violating rule 1 makes an assertion fail for the wrong reason and the recorded RED
proves nothing. Violating D1 means there is no recorded RED at all, and no checkpoint state that
describes what happened — a strictly larger loss, and the reason it is stated as a precondition
rather than as a third peer.

### D4 — a fourth checkpoint state: the target did not build

The classification block offers three: green, expected red, and unclassifiable red. "The target did
not build" is none of them, and collapsing it into the third is what makes an operator stop reading
the section. It is named, it is distinct, and it carries its own meaning: **D1 was violated** — the
declaration the tests reference did not land in the tester's batch. The remedy is a batching
correction, not a fix to the code under test.

### D5 — instruction, not enforcement (rule 16)

Every change this ADR makes is prose a model is asked to follow: three blocks in
`concept-to-code/SKILL.md`, one clause in `architect.md`'s Output Format. Nothing blocks a dispatch,
and no hook checks that a plan placed the declaration correctly.

What is **enforced** is that the clauses exist: assertions in
`staging/plugin/scripts/tests/batch-boundary-precedence.test.sh`, ADR-0101's own harness, each seen
RED against a declared plant. That is a changed failure *shape*, not a guarantee — a green harness
here pins that the instruction is written, never that it is obeyed.

### D6 — no hook change, on M4

`test-write-scope.sh` is untouched. Widening it was never needed and narrowing it would have been
wrong: the tester's freedom to write a production path is what D1 depends on.

## Consequences

**Positive.** The tester-to-coder window becomes a red suite instead of a broken build in every
compiled language, restoring the input the expected-red table, the checkpoint counts and the stop
gate all assume. It costs nothing on interpreted languages, where D1 is vacuously satisfied.

**Negative, and stated rather than discovered later.** D1 asks a plan author to know which of a
feature's files are interface and which are implementation, at planning time, before the code is
read. That judgement will sometimes be wrong, and when it is, the window breaks exactly as it does
today — D4's state is what makes that legible instead of silent.

D1 is also unenforced (D5). A plan that ignores it produces the pre-ADR-0155 behaviour with no
warning, and the only signal is the fourth checkpoint state appearing.

**Not addressed.** The stop gate's per-session budget survives this (#477): D1 removes the largest
recurring source of declared reds on compiled projects, it does not give the gate a concept of an
expected one. `.claude/test-timeout` — a per-project file, bounded at 900s — is the correct lever for
M3's timeout half and is unrelated to this decision.

## Alternatives considered

**A1 — reorder to coder-before-tester on compiled languages.** Rejected: it discards the one
guarantee ADR-0049 exists to provide, and it does so precisely where the code is most typed and the
temptation to write tests against the implementation is highest.

**A2 — teach the stop gate to recognise a declared intermediate red.** Not rejected — it is #477, and
it is the right fix for a different problem. It would make the window quieter without making it
meaningful: there would still be no red tests to classify, no counts to read, and no way to see a
regression. D1 addresses the cause; #477 addresses the noise.

**A3 — have the tester stub the implementation as well as the signature.** Rejected: a stub body is
an implementation, and a tester that writes one has answered the question the coder was dispatched
to answer. The interface is the boundary precisely because it is the part that is specified rather
than decided.

## References

- Issue #486
- ADR-0049 §D1 — generator/verifier separation by dispatch ordering
- ADR-0088 §D5, ADR-0101 — the two existing batch-boundary rules and their tie-break
- ADR-0053 — protected interfaces, the vocabulary D2 borrows
- ADR-0137 §D5 — a timeout spends from the stop gate's per-session budget
- ADR-0154 — the back-reference rule this ADR's own harness section satisfies by naming `ADR-0155`
