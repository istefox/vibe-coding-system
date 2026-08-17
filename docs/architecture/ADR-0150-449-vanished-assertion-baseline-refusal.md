# ADR-0150 — the per-file assertion baseline is refused on measured friction, and the practice that replaces it is written down (issue #449)

- **Date:** 2026-08-17
- **Issue:** #449 — "A vanished assertion is invisible in 49 of 82 harnesses, and a per-file floor is the wrong instrument"
- **Supersedes:** nothing. **Amends:** ADR-0146 §D3 (this is the successor it named).

## Status

Accepted.

## Context

ADR-0146 refused #310's R-02 — a per-file assertion-count floor — because a floor absorbs its own
plant (rule 10), and split the real question out as #449: **a frozen per-file baseline**, red on any
drop, bumped deliberately. #449 listed four things to measure before designing. All four were
measured, plus two the issue did not ask for, and the design does not survive them.

### R-01 — the derivation: static is the wrong number, and the runtime number is already free

83 harnesses, 2026-08-17. A static count of `ok`/`bad` call sites agrees with the runtime count in
**3 of 83 (4%)**. The disagreement is not a constant factor to correct for: it ranges from **−98**
(`worktree-isolation-contract`) to **+256** (`pairs-completeness`). Two causes, both structural —
most assertions are written as an `if/else` pair of which one branch executes, and some are emitted
inside a loop over a population, where no static reading can predict the count at all.

The issue's cost objection to the runtime count — that it needs a second full suite run, and the
suite already takes ~185s against a 300s ceiling — **dissolves on measurement**: 77 of 83 harnesses
already print their own `PASS=N` line, and in 74 of those it equals the emitted-assertion count
exactly. The authoritative number is a by-product of the run that already happens.

That removes the obstacle and does not save the design, because of the next number.

### The friction, counted: 95 of the last 100 commits

Of the 100 most recent non-merge commits touching a harness, **95 add or remove an `ok`/`bad` call
site.** A frozen baseline would demand a deliberate bump on 95% of the commits that touch these
files.

Issue #449 set this as the deciding question — "it decides whether this is a guard or a tax". It is
a tax.
A line bumped on nineteen commits out of twenty is a line people learn to bump without reading,
which is ADR-0048 §D7's failure applied to a baseline instead of a detector.

### The premise, checked: no assertion has vanished silently

Rule 13, and the issue does not ask for it. Over the same 100 commits, **3 net assertion drops
across 2 commits**:

| commit | harness | why |
|---|---|---|
| `fb20f4f` | `reward-hack-detectors` | `literal-assertion-added` retired on measurement (#314, ADR-0144) |
| `58e9486` | `external-dependency-gate` | `token-budget` halt removed (#365, ADR-0129 §D6) |
| `58e9486` | `phase1` | same removal, its two assertions |

**All three are deliberate, and every one leaves a comment where the assertion stood, naming the
issue and the ADR.** Zero silent. The fourth issue in a row whose stated defect has no live
instance, after #313, #314 and #300.

### R-03 — the population over `plant-check.sh`, and a token the issue names wrongly

2993 runtime assertions; 371 distinct `(harness, assertion-id)` pairs carry a plant. So **2622
(88%) are outside the registry** — the added population is genuinely large.

The issue states that a vanished planted assertion is already caught as `BADPLANT`. Verified on an
isolated fixture: it is caught, but the signal is **`NOFIRE`**, not `BADPLANT`. The needle lives in
the TARGET file and still resolves, so the declaration is usable; what fails is `PC1`, because
`FAIL: <aid>` never appears. Correct outcome, wrong name — and the distinction matters, because the
two tokens have different repairs (ADR-0140).

### Where a count can drop with no diff in the harness — and it is already guarded

A hand-written list cannot shrink silently: shortening it is a diff a reviewer sees. A **derived**
population can. Ten harnesses emit assertions inside a loop over a derived population (a glob, a
command substitution, a `while read`), and **10 of 10 already carry a denominator guard** — rule 7,
already applied.

Two heuristics said otherwise on the way to that number and both were wrong on inspection: the first
counted every loop, matching seven harnesses that iterate literal lists (`for name in coder debugger
refactorer`); the second missed `proportional-audit-depth`'s `PB4`, which is a denominator guard
worded differently from the grep looking for it. Recorded because it is rule 2's second clause
applied to a measurement: inspect what the scan actually matched before believing what it reports.

## Decision

### D1 — the frozen baseline is not built

Not on the 88% population figure, which favours it, but on the 95% friction figure and the zero
instances, which together mean it would fire constantly and never for the reason it exists.

### D2 — the practice that has actually worked becomes rule 19

Three drops, three in-place comments naming the issue and the ADR. Nobody wrote that down; it is now
CLAUDE.md rule 19.

**It is an instruction, not an enforcement, for 2622 of 2993 assertions, and rule 16 requires
saying so.** No diff-level rule can enforce it: this repository has measured twice, on this exact
question, that a rule over a test diff has zero precision (ADR-0073 at 0-of-2 over 354 commits,
ADR-0148 at 0-of-6 over 383). For the 371 planted assertions it *is* enforced — deleting one leaves
its declaration behind and `plant-check.sh` reports `NOFIRE`, red in CI.

### D3 — nothing is added to the 6 harnesses that print no total

`acceptance-contract`, `hook-probe`, `hook-verify-workflow`, `phase1`, `plan-task-count` and `prep`
emit no final `PASS=N`. With no baseline consuming it, adding one is a producer with no consumer,
which is rule 17 read backwards. Recorded here so the next reader knows it was seen and declined,
not missed.

## Consequences

- Nothing executable ships. Two files change: `CLAUDE.md` (rule 19) and this ADR.
- **The 88% figure is the honest argument against this decision** and is stated rather than buried:
  most assertions in this repository are pinned by nothing that would notice their disappearance.
  What the measurement says is that nothing has disappeared, and that the instrument proposed for it
  would cost more attention than it returns — not that the exposure is imaginary.
- If a silent deletion is ever found, this ADR is the record of what was measured and when, and the
  re-derivation starts from the 95% friction number, which is the one that would have to change.

## References

- ADR-0146 §D3 (the refusal that filed this), ADR-0124 (why a floor is only a vacuity guard),
  ADR-0073 and ADR-0148 (a rule over a test diff, measured twice at zero precision), ADR-0140
  (`NOFIRE` and `BADPLANT` are different states with different repairs), ADR-0048 §D7 (a signal
  always wrong is one its readers learn to dismiss), CLAUDE.md rules 2, 7, 10, 13, 16, 17, 19.
