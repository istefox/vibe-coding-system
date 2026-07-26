# ADR-0057 — Tracer-bullet probe step (Step 4.5)

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #111 (twelfth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/111-tracer-bullet-probe.spec.md`
- **Builds on:** ADR-0049 (#103) for the generator/verifier separation whose logic §D3 reapplies,
  and ADR-0055 (#109) §D2 for the absent-means-what rule.
- **Closes:** gap **G-18** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (ABSENT, P2).

## Context

The word "tracer" does not occur anywhere under `staging/`. The chain runs Gate 2 (architecture) →
Gate 3 (project memory) → Gate 4 (session boundary) → Step 5 (full implementation).

There is no cheap thin-slice probe between "plan approved" and "implement everything". The
consequence is specific and expensive: the chain cannot produce the spec's most valuable outcome —
**Red, meaning the agent cannot do this class of work and a human should take manual control.**
Today that verdict arrives only after a full Step 5 has been paid for, if it arrives at all.

The spec (§4.4.3, §6.4) gives the probe four jobs: feasibility gate, acceptance evidence, capability
probe on the AI itself, and pattern seed for the slices that follow.

## Decision

### D1 — An optional Step 4.5 dispatching one coder on the thinnest end-to-end slice

"The simplest journey through this system that does something useful." One coder, one slice,
end-to-end rather than one layer — a slice that touches every layer shallowly probes integration
risk, which is where feasibility actually fails; a deep single-layer slice probes nothing the plan
did not already assume.

Optional, and **absent means skipped**, per ADR-0055 §D2's rule: this feature *adds* a step, so
inert equals the pre-feature behaviour and defaulting off preserves it. (Contrast ADR-0055 itself,
which removes constraints and therefore must default to strict.)

### D2 — Three verdicts, and `red` is the one the feature exists for

- `green` — the slice works; proceed to Step 5 with the slice as the pattern seed.
- `amber` — it works but awkwardly; route back to Gate 2 for a scope reduction.
- `red` — the agent cannot do this class of work; route to a new gate offering **continue anyway /
  reduce scope / hand-code (abort the chain, reason recorded)**.

`red` is the outcome with all the value and the one a system like this is structurally least likely
to emit. Every incentive in an agentic chain points at "continue": the chain is mid-run, the plan is
approved, and an agent asked whether it can do something will almost always say yes. So `red` gets
an explicit route, a named abort option, and a recorded reason. Without the hand-code option written
down as a first-class choice, `red` degrades into a slower `amber`.

### D3 — The verdict is derived from evidence, not from the coder's opinion

This is the decision that makes the rest worth anything.

Asking the probe coder "could you do this?" reproduces the generator/verifier problem ADR-0049
exists to fix, and the self-assessment problem ADR-0055 §D-negative already flagged for `risk`. An
agent's report on its own capability is the weakest evidence available, and it is biased toward
continuing.

So the verdict is computed from **mechanical facts about the slice**, with the agent's narrative as
context only:

- Did the slice build/run at all?
- Did its test pass?
- How many attempts did it take, and did it need to change the plan's stated approach?
- Did it touch files outside the slice's declared scope? (`diff-budget-check.sh` from ADR-0052
  already computes this.)

`red` is a mechanical outcome — did not build, or did not pass after N attempts — not a mood. The
agent may *recommend* `red`, and a recommendation is recorded, but it cannot upgrade a mechanically
failing slice to `green`.

### D4 — The probe must be cheap, and cheapness is enforced by scope, not by asking

A tracer that costs what Step 5 costs has no value: you could have run Step 5. So the slice carries
an explicit small budget (ADR-0052's mechanism, reused rather than reinvented) and a hard attempt
cap. Exceeding either is itself evidence — a slice that will not converge cheaply is an `amber` or
`red` signal, not a reason to keep spending.

### D5 — On `green`, the slice is the pattern seed and is kept

The spec's fourth job. The slice's code is not thrown away; it is committed and the Step 5 briefs
reference it as the established pattern. Otherwise the probe pays for itself once and the
consistency benefit is lost.

## Alternatives rejected

- **A1 — Ask the coder for a self-assessed verdict.** Rejected under §D3. This is the obvious
  implementation and it is the one that makes the feature decorative.
- **A2 — Make the probe mandatory.** Rejected under §D1: it adds cost to every chain including the
  ones whose feasibility is not in question, and a step that feels like a tax gets skipped.
- **A3 — Probe one layer deeply rather than end-to-end.** Rejected under §D1: integration is where
  feasibility fails, and a single-layer slice tests what the plan already assumed.
- **A4 — Fold `red` into `amber` and always continue with reduced scope.** Rejected under §D2:
  removes the only outcome that says "stop", which is the outcome the spec calls most valuable.
- **A5 — Throw the slice away after the verdict.** Rejected under §D5.

## Consequences

### Positive

- The chain gains the ability to conclude "do not use an agent for this", cheaply and before Step 5.
- `green` runs get a pattern seed, so Step 5 briefs start from working code rather than prose.
- Reuses ADR-0052's budget mechanism instead of inventing a second cost control.

### Negative, stated plainly

- **`red` will be rare, and rarity is not evidence of correctness.** A probe that never returns
  `red` is indistinguishable from a probe that cannot. Nothing here measures that, and it should be
  watched rather than assumed working — the same shape as ADR-0051's measured false-positive
  discipline, which this feature cannot apply because the corpus does not exist yet.
- **The thinnest useful slice is a judgement call**, made by the architect. A slice chosen too easy
  returns `green` for a plan that will fail later. §D3's mechanical verdict does not protect against
  a badly chosen slice, only against a dishonest report on a given one.
- **Off by default** (§D1), so like #106–#110 it ships inert.
- Instruction, not enforcement: the harness pins that Step 4.5, the three verdicts, the mechanical
  derivation and the hand-code option exist; nothing pins that a model computes the verdict honestly.
