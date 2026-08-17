# ADR-0151 — the registry is sharded across jobs, and the population no shard can see is asserted once by a union (issue #447)

- **Date:** 2026-08-17
- **Issue:** #447 — "The plant registry's ceiling is 2 cores, and the only lever left is sharding it across jobs"
- **Amends:** ADR-0143 §D7, which named this lever and left its rejection to be re-read rather than
  treated as settled. **Extends:** ADR-0108 (the registry), ADR-0140 (the baseline).
- **Supersedes:** nothing.

## Status

Accepted.

## Context

ADR-0143 spent the registry's isolation concurrently and measured what that bought: **1.38x–1.46x**
on the runner, because the runner has **2 cores** and the mutation phase copies ~8.4 GB per run. Its
own §D7 recorded the consequence — more workers inside one job cannot pass two cores, and the only
remaining lever on GitHub is that **jobs run on separate machines**. It also recorded that the
"separate CI job" alternative had been rejected at a cost of "~3 minutes", a figure computed on an
assumption the later measurement falsified.

Every number below was re-derived on 2026-08-17 against the current corpus (`main` at `6ff5dc2`,
**399 plants over 45 declaring harnesses**), not carried over from the issue body. Where a figure had
moved, it moved.

### What the measurement changed about the design

**The unit of the split is a plant, not a harness — and the issue does not pose it in these terms.**
Two files are **47.5%** of the modelled sequential cost (the issue quotes 45%), eleven are **88%**
(quotes 87%), and `spec-coverage.test.sh` alone is **29.5%** — 19 plants x 29.55s = 561.5s of a
1906s total. Slicing by *harness* is therefore bounded at **3.39x** by that one file no matter how
many shards exist. Slicing by *plant* has no such floor: each plant already costs one isolated
sandbox plus one full harness run, so the atomic unit is a plant and the most expensive single one
is 29.55s.

**The baseline pass multiplies across shards and it does not matter.** 164.7s against 1905.8s of
mutation: **8.6%**. The worst case, where every shard re-runs all 45 baselines, is priced into the
projections below rather than optimised away.

**A shard is as I/O-bound as the whole corpus, and no new A/B was needed to establish it.**
`build_sandbox` copies the whole `staging/` + `docs/` + the four repo-root inputs per plant,
unconditionally: the per-plant cost does not depend on how many plants are in the run. So ADR-0143's
**1.38x–1.46x at 2 workers** holds unchanged inside a shard. Runner cores: **2**, printed today on
`ubuntu-24.04` image `20260810.271.1`.

**A matrix leg has no producer.** `required-checks-audit.sh` derives producers from check-runs
observed on `main` HEAD and from job ids, 4-space `name:` keys and the workflow `name:` in the yaml.
Fed a 4-shard matrix plus a union job with `gh` stubbed, it reports **every leg as
`missing-producer`** and the statically-named union job as satisfied. Leg contexts are
`<display name> (<value>)` — confirmed empirically as `probe-all-green (1)`.

**A union job written the obvious way reports green while its shards are red.** Probe run
`32023759765`: four dependencies, two of them `failure`, and inside the job the step guarded by
`if: failure()` was **skipped** while `if: success()` **ran**; the job concluded `success`. Status
check functions in a step `if` read the previous steps of the same job, not `needs`.

**A matrix job contributes one aggregated result.** `probe-fail-fast` produced leg 1 `cancelled`,
leg 2 `cancelled`, leg 3 `failure`, and downstream reads `failure`: the two legs that never ran are
invisible in the aggregate.

**Two limits of that measurement, stated rather than smoothed.** The probe exercised **step-level**
status functions only; `failure()` in a **job-level** `if` was not exercised and nothing in this
decision rests on it. And whether a single matrix leg can be skipped by a job-level condition on
`matrix` remains **unmeasured** — two probe runs were rejected at validation, the first rejection was
wrongly blamed on that condition, and the real cause was `${{ failure() }}` inside a `run:` body.

### The part that is not arithmetic

`plant-check.sh` ends in assertions **about the whole population**, and a shard can evaluate none of
them: `PC0` guards the denominator, `PC3` asserts the plants span >= 4 test files, `PC5b` asserts the
baseline ran for **all** declaring harnesses, and `Z1` is an assertion-count floor over the run.
Sharded naively each becomes either a false red or, worse, a guard that passes on a slice and is
never evaluated on the union — a check that reads as coverage while asking a smaller question than
the one it names. That is rule 7 with the denominator too small, and it is the shape this repository
keeps recording.

## Decision

### D1 — the split is by plant, assigned by modulo on the declaration index

The i-th declared plant goes to shard `i mod S`. Assignment carries no state to maintain and none to
go stale (rule 13), and it balances **precisely because it breaks files apart**: measured over
today's corpus at S=4, `spec-coverage.test.sh`'s 19 plants land on all four shards rather than
pinning one, and the slices come out **100 / 100 / 100 / 99 plants** spanning **36 / 34 / 35 / 36**
of the 45 declaring harnesses.

A stored per-file cost table would balance better on paper and is refused: it is exactly the
hand-maintained number that goes stale between the run that measured it and the run that reads it.
The achieved imbalance is **printed by the union** instead of assumed by the design (R-01).

### D2 — four shards

Fixed cost per leg — checkout, the `zsh` install, and the unrestricted baseline pass — is ~180s.
Projected: 4 legs at ~520s each against 8 legs at ~350s each. Eight shards buy roughly three more
minutes for double the fan-out and double the artifact plumbing, against a fixed cost that has never
been measured **in this topology**. Four ships; the re-test condition is pre-registered in D12 rather
than left to taste (ADR-0080's precedent).

### D3 — one code path: the sequential run is the 1-of-1 shard

`PLANT_SHARDS` defaults to 1 and `PLANT_SHARD` to 1, and the dispatch and aggregation loops both
walk `seq "$SHARD" "$SHARDS" "$DECL_N"`. At the defaults that is `seq 1 1 N`, which is `seq 1 N`:
**the local invocation is unchanged byte for byte, and that equivalence is asserted rather than
assumed** (R-05, assertion `PS1`).

There is no `if shard_mode` branch around the loop, deliberately. ADR-0086's criterion applies as it
did to the worker path: a sharded implementation kept beside a sequential one is two copies answering
one question, and the day they disagree nobody can say which verdict is the registry's.

**Shard mode is `PLANT_SHARDS > 1`.** At S=1 the slice *is* the population, so the population
assertions are valid and run. That is what makes the equivalence proof of D11 a plain diff: a
`PLANT_SHARDS=1` run and an unset run produce the same stream.

### D4 — a malformed slice specification REFUSES, where a malformed `PLANT_JOBS` resolves downwards

`PLANT_JOBS=abc` resolves to one worker (ADR-0143 §D2, assertion `PP5`): every failure in that chain
lands on the behaviour the file had before it was parallel. **The slice knobs take the opposite
direction and the asymmetry is the point.** `PLANT_JOBS` is a performance knob and a wrong value
costs time; `PLANT_SHARD` is a correctness knob and a wrong value silently runs one slice twice and
loses another. Non-numeric, zero, negative, or `PLANT_SHARD` outside `1..PLANT_SHARDS` is refused
with **exit 2** and no plant runs (R-08, assertion `PS4`).

Two env knobs in one file with opposite failure directions is the shape ADR-0131 recorded for
`plan-tasks.sh`; the reason each one points where it does is stated at both sites, so the next reader
does not "fix" the asymmetry.

### D5 — in shard mode the four population assertions are deferred, and the script says so

`PC0`, `PC3`, `PC5b` and `Z1` do not run in a shard. The shard prints an explicit token naming the
deferral — `PC-DEFERRED shard k/S — PC0 PC3 PC5b Z1 …` — rather than omitting them quietly: a check
that did not run must report a state distinct from a clean result (rule 4). A shard's own exit code
covers only the plants in its slice, and the token says that too (R-06, assertions `PS3`, `PS3b`).

**A consequence that must be read with D6, because on its own it is a fail-open.** With `PC0`
deferred, a shard whose collector broke discovers zero declarations, runs zero plants and exits 0.
It reads as clean. What makes that safe is not the shard: it is that the union always runs, always
re-derives the declared set from the repository, and requires the shards' reported ids to cover it
exactly. The safety argument therefore depends on the union being **unconditional and required**,
which is D7 and D8. No per-shard slice floor is added; a floor absorbs its own plant (rule 10,
ADR-0124, ADR-0150) and the union's exact coverage check is the stronger instrument.

### D6 — the union works on artifacts, and re-derives its own denominator

Each shard writes its verdict stream to `PLANT_ARTIFACT` and uploads it. The union downloads all of
them and evaluates, exactly once over the concatenation: `PC0`, `PC3`, `PC5b`, `Z1`, plus two new
assertions — `PC6`, the coverage check, and `PC7`, the imbalance report (R-01, R-02).

The artifact is one record per line, tab-separated, with a leading record-type field. No new verdict
token is introduced; `FIRED`, `NOFIRE`, `BADPLANT` and `VACUOUS` are the same four:

| record | fields | meaning |
|---|---|---|
| `M` | key, value | `shard`, `shards`, `decls`, `slice`, `asserts` |
| `B` | harness, state | the baseline outcome, one per declaring harness |
| `V` | index, harness, assertion id, token | one per declaration in this shard's slice |

Records are emitted in a fixed order — `M`, then `B` sorted by harness, then `V` in declaration
index order — because an output that reshuffles per run cannot be diffed against anything, which is
ADR-0143 §D3 applied to the artifact instead of to stdout.

**`PC6` is the denominator guard (rule 7), and it is why this design is artifacts rather than
`needs`.** The union re-derives the declarations from the repository with the *same* collector the
shards used — extracted to one `collect_decls` function, because two collectors giving different
answers would be the defect (ADR-0086) — and requires that every declaration index appears **exactly
once** across the artifacts, with a matching harness and assertion id, and that each shard's own
`decls` count agrees with the re-derivation. A missing index is a lost or empty slice; a duplicated
one is a mis-assignment. Without the re-derivation a matrix that silently dropped a slice would
present a smaller population that reads as clean — the cheaper `needs`-only design cannot see it.

**The union's exit codes are a checker's, not a reporter's** (rule 5): 0 clean, 1 a defect found,
2 bad invocation, **3 could not evaluate**. Exit 3 covers zero artifacts, an unreadable one, and the
case where the artifacts agree that `shards=S` but fewer than S are present — "did not run" is never
reported as a clean union (R-02).

**The expected shard count comes from the artifacts themselves,** not from a third copy of the
number. The yaml carries `4` in exactly one place, the matrix list; the shard job derives
`PLANT_SHARDS` from `${{ strategy.job-total }}`; the union derives it from the `M shards` records
and refuses with exit 3 if they disagree.

### D7 — the leg-result gate is a mode of `plant-check.sh`, not an `if:` in the yaml

The union must assert that every leg succeeded, and the three non-success states measured —
`failure`, `cancelled`, `skipped` — are distinct, so only `!= 'success'` catches all three. Written
the obvious way that is a step `if:`, which is **unplantable**: a plant targets `staging/` or
`../docs/`, and `.github/` is copied into the sandbox for tests to read but is not a legal plant
target. Logic that lives in yaml can be asserted to *exist* and never to *work* (rule 16).

So the decision lives in `plant-check.sh --require-legs <result>`: exit 0 on exactly `success`, exit
1 on anything else, naming the observed state. The comparison is against the ONE allowed value and
never against a list of rejects — a list is blind to what it omits (rule 8), including whatever
state GitHub adds next. The yaml's whole contribution is passing `${{ needs.plant-shard.result }}`
in through `env:`. This is R-07's mechanism and it is planted (`PS8`).

The same measurement decides where `if: always()` is correct and where it is not. On the **upload**
step it is correct — status functions read the previous steps of the same job, which is exactly what
a "upload the artifact even though the shard went red" condition needs. On a **union** step it would
have been wrong, and that is the trap probe run `32023759765` walked into.

### D8 — `shell-tests` becomes the union job and keeps its name: no new required context

`shell-tests` is today one of four required contexts on `main` (`markdownlint`, `links`, `ci`,
`shell-tests` — read from the branch-protection API on 2026-08-17) and the registry is its last step.
The topology is chosen so that **nothing on GitHub has to change for this to land**: `shell-tests`
keeps its name and its place in the required set, gains `needs: [plant-shard]`, keeps its harness
loop, and gains the union evaluation as its final steps. The window in which the registry is either
ungated or blocking every pull request does not exist.

```text
plant-shard (1..4)   -- matrix, fail-fast: false, no needs
        |
        +--> shell-tests   needs: [plant-shard], if: always()
                             1. harness loop (unchanged)
                             2. download the four artifacts
                             3. --require-legs
                             4. --union
```

**`if: always()` is not a stylistic choice.** Without it a failed shard *skips* `shell-tests`, and a
required context that never reports leaves the pull request pending forever.

**`fail-fast: false`,** so one broken plant does not cancel the other three shards and hide the rest
of the picture. ADR-0101's precedent applied again: evidence quality beats checkpoint tidiness. The
harness loop runs **before** the leg-result gate for the same reason — it is independent evidence and
a shard failure should not cost it.

**The price is stated:** the harness loop (~2.5 min) now serialises after the shards instead of
running alongside them. Projected total ~8.4 min against ~18 min today — a projection from the local
cost model scaled to the CI-measured 15m16s registry step, **to be re-derived on the runner, not
trusted**.

### D9 — a matrix leg cannot be a required context, and this is where the next person reads it (R-13)

Measured above: fed a 4-shard matrix with `gh` stubbed, `required-checks-audit.sh` reports every leg
as `missing-producer`, because it derives producers from job ids and `name:` keys while a leg's
context is `<display name> (<value>)`. ADR-0114's rule is that a required context must be made
satisfiable or the change aborts. **Requiring `plant-shard (1)` would therefore block every pull
request in this repository**, and the audit would call it unsatisfiable rather than explain why.

Nothing in this change touches branch protection or `set-branch-protection.sh`, so #336 stays where
it is — the chosen topology creates no new required context to reconcile (R-03).

### D10 — the baseline pass is NOT restricted to the slice

A shard could run baselines only for the harnesses its own slice declares. Measured: each slice
spans 34–36 of the 45 declaring harnesses, so the saving is ~22% of a 164.7s pass — about 26s of a
~520s leg, **5%**. The cost is a second population derivation that can drift from the slice
derivation, and a `PC5b` whose subject changes per shard. Rejected on that trade: every shard runs
every baseline, `PC5b`'s population stays the whole corpus in every artifact, and the union's job is
a consistency check rather than a reassembly.

### D11 — how a change to the thing that validates plants is itself verified

The recursion is the same one #350 hit and it is answered the same way, with **both** devices,
because ADR-0143 §D6 recorded that neither is sufficient alone.

**Outside CI — a byte-identical verdict diff over the whole corpus.** The sequential configuration
against the sharded one, over today's 399 plants, run outside CI because the two configurations
cannot coexist in one workflow. `PLANT_SHARDS=1` writes one artifact; four `PLANT_SHARDS=4` runs
write four; the four `V` streams ordered by declaration index must equal the one, byte for byte, and
the `B` streams must agree. It proves parity **once** (R-12).

**Inside CI — a sharded arm on the existing fixture.** The corpus diff proves parity on the day it
runs; only the fixture keeps proving it. `plant-registry-parallel.test.sh` already builds a miniature
staging tree of 13 plants over 5 harnesses that sleep for descending intervals, and points the real
`plant-check.sh` at it. It gains a sharded arm: four shard runs plus the existing one-worker run
re-used as the sequential arm, then the negative cases derived by editing copies of the artifacts —
which cost nothing, because the union builds no sandboxes (R-10).

Twelve of the thirteen new assertions are planted. The thirteenth is not, and the reason is declared
at the assertion rather than left as an omission — the precedent `pairs-completeness.test.sh` set for
its own `CI1`:

| id | what it pins | plant mutates |
|---|---|---|
| `PS0` | the shard arm ran at all: four artifacts, 13 `V` records across them | the artifact writer |
| `PS1` | knobs unset == `PLANT_SHARDS=1 PLANT_SHARD=1`, byte for byte | the `:-1` default |
| `PS2` | the four shards' `V` records, ordered by index, equal the sequential run's | the dispatch stride |
| `PS3` | the deferral token is printed and names all four assertions | the token `printf` |
| `PS3b` | in shard mode those four do NOT run, and at S=1 they do | the shard-mode guard |
| `PS4` | five malformed slice specs each refuse with exit 2 and run no plant | the validation refusal |
| `PS5` | a partial population is refused, naming the missing index | the coverage comparison |
| `PS6` | a missing artifact is exit 3; an empty slice is exit 1; neither is clean | the exit-3 branch |
| `PS7` | `PC0`, `PC3`, `PC5b`, `Z1` appear exactly once, in the union and in no shard | one union evaluation |
| `PS8` | `--require-legs` accepts only `success` | the equality test |
| `PS9` | the imbalance is printed per shard and the sizes sum to the declared total | the imbalance print |
| `PS10` | a duplicated declaration index across two artifacts is refused | the duplicate detection |
| `PS11` | the `docs-ci.yml` topology | **no plant — declared at the site** |

`PS11`'s subject is `.github/workflows/docs-ci.yml`, which the sandbox copies for tests to read but
which no plant may target. Widening the target grammar is explicitly out of scope for this change,
so `PS11` carries a one-line reason beside it instead of a declaration, and its live evidence is that
it is RED until the workflow lands.

`PP3`'s needle names the aggregation loop and that loop changes here, so its declaration is updated
in the same task. A rotted needle fails loud (`BADPLANT`, "needle matched 0 times"), which is the
safe direction, but it is called out rather than discovered.

### D12 — what this does NOT fix, and the pre-registered re-test

- **The per-file cost is untouched.** Each plant still runs the whole declaring file. This buys a
  constant factor across machines, not a change of shape.
- **`plant-registry-parallel.test.sh` becomes more expensive, and it is measured rather than waved
  at.** The file costs 9.47s today and carries 10 plants, so ~95s of registry time. The sharded arm
  adds four fixture registry runs — the sequential arm re-uses the existing one-worker run, and the
  negative cases are file edits plus a sandbox-free union — for an estimated ~13.5s, and 12 new
  plants take it to 22. Estimated ~270s from ~95s: **+175s on a 1906s corpus, ~9%**, spread by modulo
  across the four shards at ~44s each, against a saving of roughly 1400s of critical path.
  Re-measure after Task 6; if the file lands materially above ~15s, the negative cases are the place
  to cut, never the plants.
- **Eight shards were not tried.** The pre-registered condition: once the first sharded run reports
  its own fixed cost, if checkout + `zsh` + baseline is **under 25% of a leg's wall clock**, re-test
  at 8. Above that, four is where the fan-out stops paying.
- **R-04's device is weaker than #350's, by construction, and this is not smoothed.** #350 compared
  both arms in one job on one machine. Sharding cannot: the whole point is separate machines. The
  best available device is a temporary sequential job in the **same workflow run**, from the same
  commit, on the same image, started at the same time — everything equal except the machine draw,
  which is exactly what is not controlled. Take three runs and report the spread, never one number
  against one number: the sequential step alone spread 20m07s–25m51s.

## Alternatives considered

**Slice by declaring harness rather than by plant.** Rejected on the measurement: bounded at 3.39x by
`spec-coverage.test.sh`, which is 29.5% of the total on its own and cannot be split by a
harness-level assignment no matter how many shards exist. It would also make the baseline genuinely
non-duplicating, which is the one thing it has going for it and is worth 8.6%.

**A stored per-shard cost table, binned from the ranked per-file measurement.** Rejected: it balances
better on paper and it is a hand-maintained number that goes stale between the run that measured it
and the run that reads it (rule 13). Modulo needs no update when the corpus grows, and it happens to
balance to 100/100/100/99 today.

**`needs` only: let the union infer health from the legs' results.** Rejected because it cannot see
the case this design exists for — a shard that ran, succeeded, and covered zero plants. `needs`
reports `success` and the population is silently smaller. This is rule 7 exactly: zero matches can be
correct, zero candidates is a broken derivation, and from outside they are identical.

**Matrix job outputs instead of artifacts.** Rejected: outputs from a matrix's legs overwrite one
another, so four legs leave one value and nothing says which leg wrote it. Artifacts are per-leg by
construction.

**Restrict each shard's baseline pass to the harnesses its slice declares.** Rejected on the measured
saving: 34–36 of 45 harnesses per slice, ~26s of a ~520s leg, against a second population derivation
and a `PC5b` whose subject differs per shard. D10.

**Evaluate `PC0`/`PC3`/`PC5b`/`Z1` in every shard instead of deferring them.** Rejected: `PC3` fails
on a slice that legitimately spans three files, `PC0`'s floor is meaningless on a slice, and `Z1`
counts a smaller run. Every one of them becomes a false red or a guard that passes on a slice and is
never asked about the union.

**Add a per-shard slice floor (`>= 1` plants in this slice) as a cheap denominator guard.** Rejected:
a floor absorbs its own plant (rule 10), it duplicates a question `PC6` already answers exactly, and
a new unplanted assertion would need its own declared exemption for no added guarantee. ADR-0150
refused the same instrument for the same reason.

**`if: !cancelled()` on the union job instead of `if: always()`.** It satisfies the stated
requirement — a failed shard must not skip the union — and it avoids `always()`'s known hazard, where
a superseded pull-request run keeps a runner busy for ~10 minutes after the concurrency group has
cancelled it. Rejected for now because the job-level behaviour of status functions is **unmeasured
here** (see the two stated limits above), and choosing an unmeasured behaviour for a required context
that can leave a pull request pending forever is the wrong direction to be wrong in. The re-test
condition is pre-registered in the Consequences below.

**A new required context for the shards, `plant-registry`.** Rejected on the measurement: a matrix
leg has no producer that `required-checks-audit.sh` can derive, so requiring one blocks every pull
request (D9), and a statically-named aggregate job would be a *new* context to add to branch
protection while #336 is open on `set-branch-protection.sh`. The chosen topology needs neither.

**A new harness file for the shard assertions.** Rejected: `docs-ci.yml` names harnesses one by one,
so a new file needs a manual registration that, if forgotten, leaves it green and never executed
where it counts (ADR-0024). The subject is the same one `plant-registry-parallel.test.sh` already
answers — how the registry runs.

## Consequences

**Positive.**

- The registry's critical path is projected to fall from ~18 min to ~8.4 min per merge, with the
  measurement device and its limit stated rather than the projection trusted.
- No new required context, no branch-protection change, no window in which the registry is ungated.
  #336 is unaffected.
- The union's `PC6` is a *stronger* guard than anything the sequential run had: today nothing checks
  that the run covered every declaration, because the run was the derivation. Sharding forces the
  question to be asked out loud.
- The registry gains a machine-readable verdict stream. The `V` records are the shape ADR-0143's
  corpus diff produced by hand, so the equivalence proof becomes a `diff` of two files rather than a
  stdout comparison with timestamps stripped.
- `--require-legs` moves a decision out of yaml, where it could only be asserted to exist, into a
  file where it is planted.

**Negative.**

- **The harness loop no longer runs in parallel with the registry.** ~2.5 min moves onto the critical
  path behind the shards. This is the price of keeping `shell-tests` as the required context and it
  is paid knowingly.
- **`if: always()` and a superseded run.** The concurrency group cancels superseded pull-request runs;
  a job with `if: always()` is documented to be able to keep running through that. If a superseded run
  is observed holding a runner after cancellation, revisit with `!cancelled()` — pre-registered here
  so the observation has somewhere to land.
- **`plant-registry-parallel.test.sh` gets slower and carries more plants**, and it is the file whose
  cost model this whole ADR is about. Estimated ~9% added to the corpus, re-measured at Task 6.
- **A shard on its own can read as clean when it did nothing.** D5. The safety rests entirely on the
  union running unconditionally and being the required context; if a future change makes the union
  conditional, that property is gone and nothing in the shard will say so.
- **Four legs of queueing risk.** A run now waits for the slowest of four machine draws rather than
  one, so the *variance* of the critical path grows even as its mean falls.

**Neutral.**

- `required-checks-audit.sh`'s advisory gains a `not-required: plant-shard` line. Advisory, never a
  gate; `required-checks-audit.test.sh`'s section `R` reads recorded 2026-08-01 responses against the
  live workflows, and its `R3` greps for the `shell-tests` line specifically, so it is unaffected.
- The `COST:` comment block in `docs-ci.yml` is rewritten again, and again with the line telling the
  reader to re-derive the pair from a run rather than trust the comment. ADR-0143 predicted this
  would go stale; it did.
- Every `docs-ci.yml` harness-list assertion across ~25 harnesses greps the `for t in …` line, which
  this change does not touch. Verified at design time, not assumed.
- **No new numbered rule is warranted.** This is rules 4 and 7 applied to a new topology — "did not
  run" is not "found nothing", and guard the denominator — plus rule 5's checker/reporter split on
  the union's exit codes. Nothing here is an invariant the nineteen do not already state.

## References

- Issue #447, and its 2026-08-17 measurement comment.
- `SPEC.md` — "shard the plant registry across jobs", R-01 to R-13.
- `docs/superpowers/plans/2026-08-17-447-shard-the-plant-registry.md` — the implementation plan.
- ADR-0143 §D6 (the two verification devices), §D7 (the lever this ADR takes up), §D2 (the
  resolve-downwards direction D4 deliberately inverts).
- ADR-0108 (the plant registry), ADR-0140 (the baseline), ADR-0086 (the extraction criterion),
  ADR-0101 (evidence quality beats checkpoint tidiness), ADR-0114 (required contexts must be
  satisfiable), ADR-0124 and ADR-0150 (why a floor is refused), ADR-0131 (two knobs, opposite failure
  directions), ADR-0080 (a pre-registered re-test condition).
- CLAUDE.md rules 2, 4, 5, 6, 7, 10, 13, 16, 17, 19.

## Correction — 2026-08-17, the fixture cost

The risk flag under Consequences → Negative and D12 estimated `plant-registry-parallel.test.sh` at
~13.5s per run and ~+175s (~9%) added to the corpus, with 22 plants. Measured after Task 6 landed:
**27.8s**, roughly **+334s (~17.5%)** on the 1906s corpus — about double the estimate.

The operator decided not to cut fixture invocations. The overshoot sits inside a change that
removes ~1400s of critical path, and cutting would mean reworking assertions that were just
validated against their own plants, trading a measured verification for an unmeasured one.

The original estimate above is left as written (rule 14): a number inside a completed ADR is a
correct snapshot of its day.

## Correction — 2026-08-17, what Task 9's measurement found, and the four requirements it settled

**R-12's measurement found a defect this feature introduced, and no test could have.** Every harness
was green — 26 of 26 — while the whole-corpus verdict diff disagreed on **10 of 411 `V` records**,
all of them self-referential plants declared in `plant-registry-parallel.test.sh`.

The cause: `plant-check.sh` handed its own environment to the harness it was running under mutation,
including the three knobs **this feature introduces**. Two consequences, both real:

- With `PLANT_ARTIFACT` set — which the shipped `plant-shard` job always does — a nested fixture
  registry wrote its 13-line fixture stream to the outer, real artifact path. 23 of that file's 24
  nested calls inherit the variable.
- Sharper: `PS1` and `PS3b` have as their subject the fact that `PLANT_SHARD`/`PLANT_SHARDS` are
  *unset*. Under the shard job those are set, so that harness was mutation-tested in a different
  world in every shard — which is why each shard failed a different subset.

**A second instance of the same defect sat in `--baseline`**, found while fixing the first. Each
shard computes the full 45-harness baseline independently, so without that second fix the `B` stream
would have disagreed even with the worker-mode call repaired.

Fixed at both sites by clearing the three knobs for that one invocation. `PLANT_JOBS` and
`PLANT_WORKROOT` are deliberately *not* cleared, with the reason recorded at the site: neither can
change what a mutation run reports or which declarations it evaluates. `PS12` pins the fix and
carries its own plant.

**This is the reason R-12 exists as a requirement separate from any assertion.** D11 said the corpus
diff proves parity once and only the fixture keeps proving it. That was right about the fixture and
wrong about the ordering: the corpus diff did not confirm what the fixture had established, it found
what the fixture could not see.

### The four requirements, as measured

| | result | how |
|---|---|---|
| **R-12** | **satisfied** | 412 `V` records byte-identical between the sequential arm and the four-shard union; `B` streams identical on all four shards. Verified twice, independently. |
| **R-03** | **satisfied** | `required-checks-audit.sh` exit 0 against live branch protection: the four required contexts (`markdownlint`, `links`, `ci`, `shell-tests`) all have a producer, no `missing-producer`. The set is unchanged, which is what D8 bought. |
| **R-05** | **satisfied** | `PC0`, `PC3`, `PC4` and `PC5b`'s emitted lines are byte-identical between the pre-restructure file and the current one. |
| **R-04** | **measured, with its limit stated** | See below. |

**R-04.** Both arms in one workflow run, one commit, one image, started together — the closest
substitute available, since separate machines are the point of the change and cannot be held
constant. Two runs with all shards green, the second a rerun of the same commit so only the machine
draw varies:

| | sequential | sharded | ratio | slowest shard | imbalance |
|---|---|---|---|---|---|
| run 2 | 25.3 min | 12.0 min | 2.11x | 9.2 min | 1.52x |
| run 3 | 25.7 min | 11.0 min | 2.33x | 8.4 min | 1.43x |

The estimate in Context was ~2.1x (8.4 against 18 min). **The ratio holds; the absolute minutes are
higher on both arms**, so today's runner is slower rather than the split less effective. The achieved
imbalance of 1.43–1.52x is produced by modulo assignment with no stored cost table, which is what
R-01 asked to be demonstrated rather than assumed.

**Two runs, not the three the plan required — a deviation, declared rather than left to be noticed.**
The plan asked for three and gave its reason: the sequential step alone had measured 20m07s, 23m32s
and 25m51s, a spread wider than the effect. **That spread did not reappear**: these two sequential
arms are 25.3 and 25.7 min, 0.4 min apart. The operator judged a third sample's marginal value low
against ~26 min of wall clock. Two samples cannot establish a variance, so this is a weaker result
than the plan specified, and the honest reading is: the ratio is somewhere near 2.1–2.3x on this
runner, on a day when the machine draw happened to be stable.

**The sharded figure is short by the union steps**, which did not execute in either run (below). The
earlier run of the same day measured 11.0 against 25.7 min but its shards were red and aborted early,
so that pair is a timing of a failure, not a comparison, and is not counted here.

Two limits, stated rather than smoothed. The sharded figure is short by the union steps, which did
not execute (below). And an earlier run measured 11.0 vs 25.7 min, but its shards were red and
aborted early, so that pair is not a comparison and is not counted.

### What is NOT yet verified, and must not be read as verified

**The three union steps have never executed on a runner.** `shell-tests` fails in its harness loop —
for a reason unrelated to this feature, an in-flight manifest — and GitHub skips every step behind a
failed one. Read from the API rather than inferred: steps 5, 6 and 7 report `skipped`.

So `--require-legs` and `--union` are verified locally and in the fixture, and **not** in CI. Filed
as issues #457 (the red window) and #458 (the skipped steps). The first CI run that exercises them
is the one following Step 7's terminal-manifest commit; that run is the evidence, and until it exists
this ADR does not claim it.
