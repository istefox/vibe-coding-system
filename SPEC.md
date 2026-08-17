# SPEC — shard the plant registry across jobs

**Topic slug:** 447-shard-the-plant-registry-across-jobs

Source: GitHub issue #447

## Objectives

1. Cut the wall-clock cost of the plant registry in CI by running it as several jobs on separate
   machines, since two cores per machine is the ceiling and more workers inside one job cannot pass
   it.
2. Keep the registry's population-level guarantees intact under a split that, by construction, gives
   each job only a slice of the population to look at.
3. Change nothing about which verdict any plant receives.

## What is already measured

Every number below was re-derived on 2026-08-17 against the current corpus (`main` at `6ff5dc2`,
399 plants, 45 declaring harnesses). Where a figure in the issue body had moved, it moved.

**The imbalance.** Two files are 47.5% of the modelled sequential cost (the issue quotes 45%);
eleven are 88% (quotes 87%). `spec-coverage.test.sh` alone is 29.5% — 19 plants × 29.55s = 561.5s
of a 1906s total.

**The unit of the split follows from that, and the issue does not pose it in these terms.** Slicing
by *harness* is bounded at **3.39x** by that one file no matter how many shards exist. Slicing by
*plant* has no such floor: each plant already costs one isolated sandbox plus one full harness run,
so the atomic unit is a plant and the most expensive single one is 29.55s.

**The baseline multiplies and it does not matter.** 164.7s against 1905.8s of mutation: **8.6%**.
Even the worst case where every shard re-runs all 45 baselines is priced into the projections.

**A shard is as I/O-bound as the whole corpus, and no new A/B was needed to know it.**
`build_sandbox` copies the whole `staging/` + `docs/` + `.github/` per plant, unconditionally — the
per-plant cost does not depend on how many plants are in the run. So the **1.38–1.46x at 2 workers**
already measured on the runner holds unchanged inside a shard. Runner cores: **2**, printed today on
`ubuntu-24.04` image `20260810.271.1`.

**A matrix leg has no producer.** `required-checks-audit.sh` derives producers from check-runs
observed on `main` HEAD and from job ids / `name:` / workflow `name:` in the yaml. Fed a 4-shard
matrix plus a union job with `gh` stubbed, it reports every leg as `missing-producer` and the
statically-named union job as satisfied. Leg contexts are `<display name> (<value>)` — confirmed
empirically as `probe-all-green (1)`.

**A union job written the obvious way reports green while its shards are red.** Probe run
`32023759765`: four dependencies, two of them `failure`, and inside the job the step guarded by
`if: failure()` was **skipped** while `if: success()` **ran**; the job concluded `success`. Status
check functions in a step `if` read the previous steps of the same job, not `needs`.

**A matrix job contributes one aggregated result.** `probe-fail-fast` produced leg 1 `cancelled`,
leg 2 `cancelled`, leg 3 `failure`, and downstream reads `failure`: the two legs that never ran are
invisible in the aggregate.

Two limits of that measurement, stated rather than smoothed. The probe exercised **step-level**
status functions only; `failure()` in a **job-level** `if` was not exercised and nothing here rests
on it. And whether a single matrix leg can be skipped by a job-level condition on `matrix` remains
unmeasured — two probe runs were rejected at validation, the first rejection was wrongly blamed on
that condition, and the real cause was `${{ failure() }}` inside a `run:` body.

## Scope

In: `staging/plugin/scripts/tests/plant-check.sh` (a shard-selection mode and the deferral of its
population assertions), `.github/workflows/docs-ci.yml` (the shard matrix and the union job),
`staging/plugin/scripts/tests/plant-registry-parallel.test.sh` (the new assertions and their
plants), one ADR, one narrative block, one `CLAUDE.md` index line, and the `PROJECT.md` checkbox.

Out: branch protection and `set-branch-protection.sh` — the chosen topology creates no new required
context, so #336 stays where it is. Out: `ci.yml`, which globs the harness directory but does not
run the registry. Out: any change to what a plant declaration means, to the fired predicate, or to
the sandbox.

## Architecture

**The registry becomes four shard jobs, and `shell-tests` becomes the union job.**

`shell-tests` is today one of four required contexts on `main` and the registry is its last step.
The topology is chosen so that **no new required context is created**: `shell-tests` keeps its name
and its place in the required set, gains `needs: [plant-shard]`, keeps its harness loop, and gains
the union evaluation as its final step. Nothing on GitHub has to change for this to land, and the
window in which the registry is either ungated or blocking every PR does not exist.

The price is stated: the harness loop (~2.5 min) serialises after the shards instead of running
alongside them. Projected total ~8.4 min against ~18 min today — a projection from the local cost
model scaled to the CI-measured 15m16s registry step, to be re-derived on the runner, not trusted.

```
plant-shard (1..4)   ── matrix, fail-fast: false, no needs
        │
        └──> shell-tests   needs: [plant-shard], if: always()
                             1. require success from every leg
                             2. harness loop (unchanged)
                             3. download the four artifacts, evaluate the union
```

**`if: always()` on the union is not a stylistic choice.** Without it a failed shard skips
`shell-tests`, and a required context that never reports leaves the pull request pending forever.
With it, the union must assert `needs.plant-shard.result == 'success'` explicitly: the three
non-success states measured — `failure`, `cancelled`, `skipped` — are distinct, and only
`!= 'success'` catches all three.

**`fail-fast: false`**, so one broken plant does not cancel the other three shards and hide the rest
of the picture. This is ADR-0101's precedent applied again: evidence quality beats checkpoint
tidiness.

**Assignment is by modulo on the declaration index**, not by a stored cost table. The i-th declared
plant goes to shard `i mod 4`. It carries no state to maintain and none to go stale (rule 13), and
it balances precisely *because* it breaks files apart: `spec-coverage.test.sh`'s 19 plants land on
all four shards rather than pinning one. The achieved imbalance is measured and printed by the union
rather than assumed by the design.

**The union works on artifacts, not on inference.** Each shard uploads its per-plant verdict lines.
The union downloads all four, concatenates them, evaluates `PC0`, `PC3`, `PC5b` and `Z1` over the
concatenation exactly once, and then re-derives the declared set from the repository and requires
that the union of reported plant ids equals it. The re-derivation is the denominator guard (rule 7):
without it a matrix that silently lost a slice would present a smaller population that reads as
clean.

## Interface

`plant-check.sh` gains two environment knobs, following the idiom `PLANT_JOBS` and `PLANT_WORKROOT`
already set:

| variable | meaning | default |
|---|---|---|
| `PLANT_SHARDS` | how many shards the population is split across | `1` |
| `PLANT_SHARD` | which shard this process is, 1-based | `1` |

At the defaults the local invocation is unchanged, byte for byte. That is the compatibility contract
and it is asserted, not assumed.

**In shard mode the population assertions do not run, and the script says so.** It prints an
explicit token naming the deferral rather than skipping them quietly — a check that did not run must
report a state distinct from a clean result (rule 4). A shard's own exit code reflects only the
plants in its slice.

## Data model

Each shard's artifact is the verdict stream the registry already produces, one line per plant,
carrying the plant's assertion id, its target file and its verdict token (`FIRED`, `NOFIRE`,
`BADPLANT`, `VACUOUS`). No new token is introduced. The union's inputs are therefore four files of
the same shape the sequential run produces in one, which is what makes the equivalence proof below a
plain diff.

## How this change is verified, given that it changes the thing that verifies

A change to how the registry runs is a change to the mechanism that validates every plant, so the
recursion is answered explicitly. Both devices from #350, because that ADR recorded that neither was
sufficient alone:

1. **A byte-identical verdict diff over the whole corpus**, sequential against sharded, run outside
   CI because the two configurations cannot coexist there. It proves today's 399 plants receive
   identical verdicts.
2. **A fixture inside CI.** The existing fixture harness gains a sharded arm, so a future change
   that loses a slice, mis-assigns a plant, or lets the union pass on a partial population turns
   something red. The corpus diff proves parity once; only the fixture keeps proving it.

The new assertions live in `plant-registry-parallel.test.sh` rather than a new file. `docs-ci.yml`
names harnesses one by one, so a new file needs a registration that, if forgotten, leaves it green
and never executed where it counts — and the subject is the same one that file already answers: how
the registry runs.

## Edge cases

- **A shard is cancelled or skipped.** Measured as distinct from `failure`; the union requires
  `success` from each leg by name, so all three states halt it.
- **A shard runs and covers zero plants.** Caught by the re-derivation: the union of reported ids
  would not equal the declared set. This is the case the artifact-based design exists for, and the
  cheaper `needs`-only design cannot see it.
- **An artifact is missing entirely.** Reported as "did not run" (exit 3), never as a clean union.
- **`PLANT_SHARD` out of range, or `PLANT_SHARDS` zero or non-numeric.** A malformed slice
  specification must refuse rather than silently select everything or nothing.
- **The corpus grows.** Modulo assignment needs no update; `PC0`'s floor is evaluated on the union,
  not per shard, so a slice legitimately below it is not a failure.
- **Someone later requires a shard leg as a context.** Measured to be unsatisfiable by
  `required-checks-audit.sh`, and recorded in the ADR so the next person does not rediscover it by
  blocking every pull request.

## UI flows

None. This is CI configuration and a shell script.

## Success criteria

- [ ] R-01 — the split is derived from the measured per-file cost, and the achieved imbalance across
      shards is reported by the run rather than assumed by the design.
- [ ] R-02 — `PC0`, `PC3`, `PC5b` and `Z1` are evaluated over the union of the shards exactly once,
      and a shard that did not run reports a state distinct from a shard that ran and found nothing.
- [ ] R-03 — the required-check set on `main` is unchanged: `shell-tests` remains the single context
      covering the registry, and no matrix leg becomes a required context.
- [ ] R-04 — the before/after is measured under conditions that hold everything else equal, never one
      run against another, since the sequential step alone spread 20m07s–25m51s.
- [ ] R-05 — with `PLANT_SHARD` and `PLANT_SHARDS` unset, `plant-check.sh` behaves exactly as it does
      today, and the equivalence is asserted rather than assumed.
- [ ] R-06 — in shard mode the script prints an explicit token stating that the population assertions
      were deferred to the union, rather than omitting them silently.
- [ ] R-07 — the union job fails when any shard leg is not `success`, covering `failure`, `cancelled`
      and `skipped` alike.
- [ ] R-08 — a malformed slice specification refuses rather than selecting the whole population or
      none of it.
- [ ] R-09 — the union re-derives the declared plant set from the repository and requires that the
      shards' reported ids cover it exactly.
- [ ] R-10 — a sharded arm is added to the fixture harness, and it goes red when a slice is lost, a
      plant is mis-assigned, or the union accepts a partial population.
- [ ] R-11 — every new assertion is seen RED against a declared plant, with the declaration beside it
      in the registry.
- [ ] R-12 — the whole-corpus verdict diff between the sequential and sharded configurations is
      byte-identical (no-test: a one-off equivalence measurement run outside CI, because the two
      configurations cannot coexist in one workflow).
- [ ] R-13 — the ADR records that a matrix leg cannot be a required context, with the measurement
      that established it (no-test: a documentation obligation about a decision, not behaviour a
      harness can assert).
