# ADR-0095 — Step 5 could be entered and never left, and the guard for it found a second one

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #248 (found by the Phase 7.1 shakedown run at the end of Step 5), #265 (filed by this
  work, found by its own guard on the first run)
- **Related:** ADR-0071 (#173, the same class), ADR-0057 (the flag the only producer sat behind),
  ADR-0027 (a pair can be written and structurally unreachable), ADR-0086 (the derived-guard
  pattern, instance 9), ADR-0085 (guard the denominator), ADR-0050 (the pre-flight this lands in)

## Context

At the end of Step 5 the orchestrator transitions to `step_6_review`. It failed:

```
manifest-transition: illegal transition ready_for_implementation → step_6_review
```

Correctly. The graph is `ready_for_implementation → step_5_implementation → step_6_review`, and the
manifest was still at `ready_for_implementation`. **Nothing on the default path performed the first
hop.** Every producer of `step_5_implementation` lives inside the Step 4.5 tracer-bullet block, and
Step 4.5 runs only when `tracer_bullet_mode = probe`, which `manifest-init.sh` never writes — the
default is `skip`.

So a default run entered Step 5 from `ready_for_implementation`, did all of Step 5, and could not
leave. Six separate places in Step 5's own text instruct "transition to `step_6_review`", every one
of them from a state the chain had never entered.

**The giveaway is ADR-0057's own wording**: *"`ready_for_implementation → step_5_implementation`
exactly as before this feature existed"*. The pair sat in the legal-pairs table with no caller at
all, and the tracer-bullet feature became its only caller — behind a flag that defaults off. The
feature that reads as if it inherited the transition is the only thing that ever performed it.

Third instance of one class when #248 was filed: a consumer and a producer specified in different
places, with nothing checking that the producer exists (#173 / ADR-0071, a pre-flight asserting a
state nothing produced; #238, `manifest-set-gate.sh` correct, deployed and called from nowhere).

## Decision

### D1 — Step 5.0.5 produces the state, unconditionally, after the pre-flight and before dispatch

One transition, at the end of the recovery-readiness pre-flight, which is where the state's name
says the chain is.

**Placement is load-bearing in both directions.** Later would leave the gap open for anything
between; earlier would strand a *refused* pre-flight in `step_5_implementation`, and every refusal
above prints "Do not proceed to dispatch-mode selection" precisely so the manifest stays at
`ready_for_implementation` — the state a Form B resume is defined for.

**Step 4.5's producer is not removed and needs no guard against the duplicate.**
`manifest-transition.sh` returns 0 on a same-to-same call, so running both is a no-op, not an error.
`TP9` pins that idempotence, because it is the property that lets two producers coexist and nothing
else in either block says so.

### D2 — The fix breaks Form B resume, so Form B gains the branch in the same change

Form B's branch list accepts `ready_for_implementation` and nothing else in that stretch. Before
this fix a chain sat at `ready_for_implementation` for the whole of Step 5, so an interrupted run
matched that branch. After it, an interrupted Step 5 matches **no branch at all**.

That is not a hypothetical: ADR-0050's own Step 5.0.3 says *"If `recovery_baseline_sha` is already
non-null (a resumed Step 5 run), skip the write"* — the design anticipates a resumed Step 5
explicitly. So the recovery path was specified and the state that reaches it was not.

The new branch re-enters Step 5 at the pre-flight: all four assertions re-run, 5.0.5 is a no-op,
5.0.3 preserves the baseline. **Closing a transition hole by opening a recovery one would not have
been a fix**, and the two are one edit for that reason.

### D3 — The class guard is target-level, and it does not catch #248. That boundary is the design.

`transition-producer.test.sh` derives the 49 legal pairs from `manifest-transition.sh`, reduces them
to 29 distinct targets, and asserts each is named by a transition instruction somewhere in a staged
`SKILL.md`.

- **It catches the #238 shape** — a target with no producer anywhere.
- **It does not catch the #248 shape** — a target whose only producers are behind a default-off
  flag. `step_5_implementation` *has* two producers. A mechanical check cannot read conditionality
  out of prose, and a guard that claimed to would be worse than an honest boundary.

So #248 is pinned **instance-level** by `TP6`/`TP7`, and the class guard is justified separately, by
what it found rather than by what was asked for.

### D4 — concept-to-code §3 is excluded from the producer population, and the exclusion fails closed

§3 is the state-machine summary: a routing table, a legal-pairs list and an ASCII diagram. By
construction it names every pair in the graph and performs none of them. Including it makes every
target trivially covered and the guard assert nothing.

The range is derived from the two headings at run time. **If it does not resolve, concept-to-code
contributes nothing at all** — 26 targets report producerless, loud, alongside `TP0c` naming the
cause. The tempting simplification (drop the guard, include the file whole) fails *open*. The test
says so at that line, because the safe direction is not the obvious one.

### D5 — Instance 9 of the derived-guard pattern, not extracted

ADR-0086's criterion: extract only when two copies giving different answers would be a defect. This
asks its own question about its own population, with its own thresholds and its own marker syntax.
It stays a copy, and the header says so.

## What running it found, that reading it would not have

**The first predicate reported `step_e1_plan` as producerless. It is not.** The Gate 0d routing
block writes

```
Transition: set `current_step` to `gate_0d_scaffolding` …, then immediately transition based on `chain_path`:
- `chain_path = express` → `gate_0d_scaffolding → step_e1_plan`
```

with the verb on the **preceding** line. A predicate keyed on the word "transition" appearing on the
same line as the target is blind to a bullet list under a transition header. The arrow form is in
the predicate because of this, not because it was anticipated.

**And the same run produced a real finding, which is issue #265.** `gate_5_review_decision` is
entered by nothing. Step 5 transitions to `step_6_review` and presents Gate 5 from there, while
Gate 5's own block asserts `Trigger: … current_step = gate_5_review_decision`, the advisory roll-up
speaks of "the transition to `gate_5_review_decision`", and Step 7 lists it as a valid source state.
Four legal pairs are unreachable. Nothing aborts — Step 7's `step_6_review → step_7_commit` is legal
— so it had no symptom, which is why it survived. Fourth instance of the class, and ADR-0027's
Gates-0c/0d lesson again.

It is **declared, not fixed here**: resolving it means choosing whether the gate moves before the
state or the state is deleted, and the state's position contradicts the gate's own semantics
(`gate_5_review_decision` sits after `step_6_review`, while Gate 5 decides *whether* to review).
That is a design question, not a line.

## Verification

14 assertions in `transition-producer.test.sh`, plus a `Z1` floor.

Seen RED against the unmodified tree: **`TP1`** (naming `gate_5_review_decision`), **`TP6`**,
**`TP7`**. `TP0`/`TP0b`/`TP0c`/`TP0d`/`TP2`/`TP3`/`TP4`/`TP5`/`TP8`/`TP9` pass before and after —
forward guards and derivation guards, labelled as such, not fix evidence.

Five planted defects, all fired:

| plant | fires |
|---|---|
| exemption target renamed to a ghost state | `TP3` (and `TP1`, the real target uncovered again) |
| exemption reason shortened below 40 chars | `TP4` |
| waiver added on a target that HAS a producer | `TP2` — the reverse direction |
| §3 heading reworded | `TP0c` **and** `TP1` naming 26 targets — loud, not silent |
| pair-table `echo` rewritten as `printf` | `TP0` (27 pairs), `TP0b` (18 targets) |

**The exemption lives in `manifest-transition.sh`**, the file that declares the pair (ADR-0077's
rule), on one line, ending *"Do not read this line as audited and fine"* — the same wording
ADR-0077 gave `pre-flight-pattern-enforce.sh`'s waiver, for the same reason: a waiver that reads as
a clean bill of health is worse than none.

## Consequences

- **A chain interrupted in `step_6_review` still matches no Form B branch.** Pre-existing — that
  state was reachable before this change — and deliberately not fixed here: a half-considered resume
  branch for a step with its own preconditions is worse than a named gap.
- **The guard's population stops at staged `SKILL.md` files.** A producer written into a skill
  `scripts/` helper, or into a file outside `staging/`, is invisible to it. `TP0d` guards that the
  glob still resolves; nothing guards that the right files are in it.
- **A producer is a line that *mentions* the target in a transition context.** The guard cannot tell
  a real transition from prose that discusses one, so its false-negative direction is "a target that
  is only ever talked about looks produced" — which is precisely the residue #248 leaves and D3
  states.
- The `# transition-producer-exempt:` marker is now a third waiver syntax in this repository, after
  `transcript-scan-exempt` and `xref-exempt`. ADR-0086 already decided that is deliberate.
- Inert until sync, like every skill fix here. The paused #222 run executes the deployed copy.
