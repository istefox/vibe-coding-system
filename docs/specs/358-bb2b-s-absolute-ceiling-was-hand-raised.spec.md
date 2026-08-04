# SPEC — BB2b's absolute ceiling was hand-raised three times in one session on three healthy features

Source: GitHub issue #358

## Objectives

1. Replace `BB2b`'s absolute ceiling on the budget-declaring plan exclusion with a bound that does
   not turn red when a plan does the thing the diff-budget feature exists to encourage.
2. Preserve what the bound is actually for: catching an exclusion that has grown to cover **most**
   of the corpus, or shrunk to cover **none**.
3. Stop the "bump the number, move on" habit that a hand-edited literal trains — the same habit
   assertion floors and ceilings exist to prevent.

## Scope

In:

- `staging/plugin/scripts/tests/diff-budget-scope.test.sh`, assertion `BB2b` and the comment block
  recording its three raises.
- `BB3`'s existing `bb2_count >= 5` vacuity guard, which must stay or move with `BB2b`.

Out:

- The diff-budget checker itself (`diff-budget-check.sh`) and its parser. ADR-0052, ADR-0070 and
  ADR-0091 own that surface; this issue is about the assertion bounding the exclusion, not about
  what the exclusion contains.
- `BB2`'s own subject. Only `BB2b`'s bound is in scope.

## Stack

Documentation and blueprint repository: markdown plus bash 3.2 test harnesses. No build, lint, run
or package manager. Harnesses are hermetic `*.test.sh` files under
`staging/plugin/scripts/tests/`, run by `.claude/test-cmd` and by the `shell-tests` CI job.

## Architecture

- `staging/plugin/scripts/tests/diff-budget-scope.test.sh` — the only file the issue names.
  `BB2b` compares `bb2_skipped` (plans excluded from `BB2` because they declare a `Budget:`)
  against the literal bounds `1` and `8`. `BB3` guards the denominator with `bb2_count >= 5`.
- Whichever shape is chosen, the derivation runs over the plan corpus in
  `docs/superpowers/plans/`, which is what makes the count move per feature.

## Data model

None. The subject is two integers derived at run time (`bb2_skipped`, `bb2_count`) and the bound
applied to them.

## API / Interfaces

None. `BB2b` is an assertion inside a hermetic harness; it has no callers and exposes nothing.

## UI flows

None.

## Edge cases

- **An empty or unresolvable corpus must not read as a clean pass.** A proportion over an empty
  denominator is not a proportion. `BB3`'s `bb2_count >= 5` vacuity guard is what covers this today
  and must stay or move with `BB2b` (ADR-0085's denominator rule).
- **The exclusion covering none of the corpus** is a real failure of the derivation and must still
  fail, exactly as the absolute bound's lower end did.
- **The exclusion covering most of the corpus** is the other real failure and must still fail.
- **A committed-baseline shape can rot silently** — the issue names this cost explicitly, citing
  ADR-0121's consequences, alongside the regeneration step it adds.
- The figure at the last hand-raise was 8 of 62, about 13%. Any proportional band has to admit that
  observation without admitting the two failure modes above.

## Success criteria

- [ ] R-01 — `BB2b` no longer applies an absolute count as its bound, so a healthy feature that
  adds a budget-declaring plan does not turn the assertion red.
- [ ] R-02 — `BB2b` still fails when the exclusion covers most of the corpus.
- [ ] R-03 — `BB2b` still fails when the exclusion covers none of the corpus.
- [ ] R-04 — `BB3`'s `bb2_count >= 5` vacuity guard stays, or moves with `BB2b`, so the bound is
  never evaluated over an empty or under-resolved corpus.
- [ ] R-05 — The chosen shape is recorded with its cost, including silent-rot risk if a committed
  baseline is chosen, rather than left as an unexplained literal.
- [ ] R-06 — The three recorded hand-raises (5 → 6 → 7 → 8) are preserved as history rather than
  deleted, so the reason the shape changed remains legible.

Shape selection between a percentage band and a committed baseline file is **TBD**: the issue
presents both as candidates and states explicitly that it is not a decision.
