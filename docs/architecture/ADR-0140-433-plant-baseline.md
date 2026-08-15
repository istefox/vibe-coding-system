# ADR-0140 — a plant is scored against a baseline, and the sandbox stops manufacturing reds (issue #433)

- **Date:** 2026-08-15
- **Issue:** #433 — "58 assertions are red in an unmutated plant-check sandbox, so a plant declared
  on any of them would fire unconditionally and pin nothing"
- **Supersedes:** nothing. **Amends:** ADR-0108 (the plant registry gains a baseline and a fifth
  refusal class).

## Status

Accepted.

## Context

### What the registry does, and the gap

`plant-check.sh` is the mechanism behind CLAUDE.md rule 2 — *an assertion is not evidence until a
defect has been planted and it has gone RED*. For each `# plant:` declaration it builds a fresh
sandbox, applies the substitution, runs the declaring harness, and credits the plant if the output
contains `^FAIL: <aid>`.

**There is exactly one harness invocation in the file, and it happens after the mutation is
written.** No baseline is ever taken. So the predicate answers *"does this id appear as a FAIL after
mutation"* — never *"did this mutation turn it red"*.

### Measured, 2026-08-15 at `b481923`

Building the sandbox exactly as the runner does and running all 80 harnesses with **no mutation
applied**:

| | count |
|---|---|
| harnesses with at least one FAIL | 26 |
| **(file, assertion-id) pairs RED with no mutation** | **58** |

The causes are uniform: every assertion whose subject lives outside `staging/` and `docs/` —
`.github/workflows/docs-ci.yml`, `.gitignore`, `PROJECT.md`, `CLAUDE.md`, `git ls-files` — cannot
evaluate in a sandbox that contains neither.

A plant declared on any of those 58 would be reported as fired, counted in `PC1`, and pin nothing.
That is rule 2's exact failure mode, reached through the **verification environment** rather than
through the assertion — the registry's own defect, one level up from the ones it exists to find.

### Live exposure was zero, and that was verified rather than assumed

Intersecting the 58 red ids with the 362 declared plant ids yields four hits — `CG1`, `CG2`, `D1`,
`G1` — and all four are id-only collisions across **different files**. The runner executes only the
declaring harness, so a red `CG1` in `project-ci-checks` cannot satisfy a plant declared in
`autopilot-run-scope`. No declared plant was false. Nothing prevented the next one from being.

## The measurement that decided the design

Two sandboxes, all 80 harnesses run in each:

| sandbox | harnesses failing | red (file, id) pairs |
|---|---|---|
| as the runner built it | 26 | **58** |
| plus `.github/`, `.gitignore`, `CLAUDE.md`, `PROJECT.md` | 2 | **2** |

**Four files, about 160 KB, remove 56 of the 58.** No new failure appeared. The residue is
`secret-dep-gate` (`git ls-files` returns nothing) and `triage-state-gitignore`
(`git check-ignore`), both needing a real git repository.

That residue is why removing the cause is not sufficient on its own, and the measurement is what
establishes it rather than an argument.

## Decision

### D1 — the sandbox carries the four repo-root inputs it was missing

`build_sandbox()` is now one function used by **both** the baseline pass and every mutation run.
ADR-0086's criterion applies exactly: the two must answer the same question about the same
environment, so two copies that could drift would be a defect — a baseline measured in a
differently-populated sandbox would recreate this very issue one level up.

**`.git` is deliberately not supplied.** The two residual reds need a real repository, and at least
one harness detects the absence of a checkout in order to *skip* an assertion it cannot evaluate.
Copying a `.git` in would change what isolation means here. Those two are covered by D2 instead.

### D2 — a baseline, computed once, and a fifth refusal class

Before the declaration loop, one unmutated sandbox is built and each **declaring** harness is run
once, recording the `FAIL:` lines it already emits. A declaration whose `aid` appears in its own
harness's baseline is refused as **`VACUOUS`**, and `PC5` fails on any.

`VACUOUS` is deliberately **not** folded into `BADPLANT`:

- `BADPLANT` — the registry **could not run** this plant: malformed fields, unattributable harness,
  unresolvable target, a needle matching zero or many sites.
- `VACUOUS` — the plant **would run and prove nothing**, because the assertion is red without it.

Two states with two different repairs, so two tokens, in the same spirit as
`manifest-entry-state.sh`'s refusal to collapse "no file" into "could not run".

Cost: one sandbox plus 39 harness runs, against the 362 sandbox builds and runs already performed.
That ratio is about 11%, and it is **derived from the run counts, not measured as a delta** — every
timed run on this machine already carried the baseline, so no like-for-like before/after exists.
What is measured is the absolute: 30m28s for 362 plants locally, 2026-08-15. Issue #350's cost
complaint is the 362, not the 39.

### D3 — the baseline is guarded against its own emptiness, by exit status and not by a success token

`PC5b` fails when the baseline could not be established for a declaring harness. An empty baseline
from a harness that did not run would make `PC5` pass for every plant in it, which is rule 7 applied
to the guard itself: **an unrun baseline is not a clean baseline.**

Emptiness is therefore corroborated before it is trusted, and the corroborating signal is the
harness's **exit status**:

| reds present | exit | verdict |
|---|---|---|
| yes | any | trusted — the baseline speaks for itself |
| no | 0, with output | trusted — the harness ran and had nothing to report |
| no | nonzero, or silent | refused — a failure no `FAIL:` line attributes |

**Not a success token, and that was learned by measuring.** The first implementation asked for a
line matching the `PASS:`/`FAIL:` prefixes and `PC5b` fired on its first run against
`phase1.test.sh` — which
had run perfectly, 37 assertions green, printing `ok   <label>`. Measured 2026-08-15 across all 39
declaring harnesses, 38 print `PASS: <id>` and exactly one prints `ok`. The failure idiom *is*
uniform, because a declaring harness is already refused as `BADPLANT` unless it emits the
`FAIL: <id>` prefix; the success idiom has no such enforcement, so enumerating it is rule 8 —
a list blind to the harness that invents a third form.

The guard found a defect on its first execution. It was its author's, which is the outcome rule 2
predicts and the reason the probes below are not optional.

Re-measured against the corrected predicate, all 39 declaring harnesses in an unmutated sandbox:
38 exit 0 with no reds and are trusted with an empty baseline, `triage-state-gitignore` exits 1
carrying its one genuine red (`T16`), and **nothing is refused**. The predicate accepts every
harness that ran, including the one the first version rejected.

### D4 — what this does NOT fix

The fired predicate is `grep -q "^FAIL: $aid"`: a **prefix** match, unanchored and unescaped, so
`FAIL: SGP1` is satisfied by `FAIL: SGP10`. That is **issue #355** and it stays open. The baseline
comparison uses the **same** predicate on purpose so the two halves agree; the consequence is that
until #355 is fixed this guard inherits the looseness and may **over-refuse** a plant whose id is a
prefix of an already-red one. Over-refusal fails loud, which is the safe direction; under-refusal is
the defect being fixed. A reader should not have to discover that trade by hitting it.

### D5 — `PC5` passes on the day it ships, and that is not a repair

No declared plant is vacuous today, by the intersection above. `PC5` is a guard for the next
declaration. **What repaired something is D1**, and the ADR says so rather than letting a green
`PC5` be read as evidence that 58 defects were fixed.

## Alternatives considered

**Baseline only, leave the sandbox as it was.** Correct but wasteful: it would refuse plants on 58
assertions that a 160 KB copy makes evaluable. It would also have left the registry permanently
unable to cover whole harnesses, which is coverage lost for no reason.

**Fix the sandbox only, no baseline.** Tempting after seeing 58 drop to 2, and wrong: the residue is
non-empty, and nothing would notice the next repo-root input a harness starts depending on. That is
rule 8 — a list validated in one direction is blind to what it omits.

**Copy `.git` too, taking the residue to zero.** Rejected on D1's reasoning: at least one harness
uses the absence of a checkout as its skip condition, so supplying one changes assertion behaviour
rather than only assertion inputs, and the cost per sandbox is no longer negligible at 362 copies.

## Consequences

- Supplying `CLAUDE.md` makes assertions that were silently **not evaluating** in the sandbox
  evaluate: `claude-md-condensation` goes from 5 PASS to 13 PASS. The registry's effective coverage
  grows as a side effect, and the direction is safe — an assertion that was skipped and is now green
  would make a plant *not* fire, which `PC1` reports loudly.
- `plant-check.sh` grows two assertions and a derived ~11% of runtime, on a script #350 already
  considers too slow. Accepted deliberately. The workflow's own cost note was corrected in the same
  change: it claimed `~12s for 15 plants`, true when it was written, against a measured 23m32s for
  362 on the runner. A registry that grows linearly outgrows any absolute written beside it.
- **`PC5` and `PC5b` are outside their own registry, by construction.** `plant-check.sh` collects
  declarations from `*.test.sh` and is not itself a `*.test.sh`, so no `# plant:` line can target
  it and rule 2's normal evidence is unavailable to the two assertions that enforce rule 2. They
  were verified instead by two hand-run probes, armed together and measured 2026-08-15:

  ```text
  FAIL: PC5  vacuous plant(s) — triage-state-gitignore.test.sh [T16]
             already RED in the unmutated sandbox; firing here would prove nothing
  FAIL: PC5b the baseline DID NOT RUN for: step7-snapshot-collapse.test.sh(rc=7,unattributable)
  ```

  The first probe declared a plant on `T16` — red in every unmutated sandbox — with the target and
  needle of the file's real `T17` declaration, so it would genuinely have run. `PC0` rose from 362
  to 363, confirming it was collected, and `PC1` did **not** list it as failing to fire: it was
  refused before running rather than credited, which is precisely the outcome this ADR exists to
  produce. The second suppressed one harness's baseline with a nonzero exit carrying no `FAIL:`
  line. A reader who assumes a green `PC5` carries the usual planted evidence would be wrong, so
  the gap and its substitute are stated here rather than left to be inferred from the registry's
  own silence.
- This work is **attended only**. `plant-check.sh` is the verification substrate; a run that breaks
  it breaks the evidence for everything else in the same run, which is the Phase 12 criterion.

## References

- Issue #433; open and deliberately untouched: #355 (prefix match), #350 (registry cost).
- ADR-0108 (the plant registry), ADR-0085 (guard the denominator), ADR-0086 (when to extract),
  ADR-0046/ADR-0076 (did-not-run is a distinct state), CLAUDE.md rules 2, 7 and 8.
