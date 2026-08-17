# ADR-0144 — two issues whose premise did not survive measurement: a detector retired, a heading guarded (issues #313, #314)

- **Date:** 2026-08-16
- **Issues:** #314 — "literal-assertion-added shipped disabled at 25 percent precision and nothing
  has re-measured it"; #313 — "spec-coverage is wholly inert for a SPEC whose criteria sit under an
  unrecognised heading".
- **Supersedes:** nothing. **Amends:** ADR-0051 (`literal-assertion-added` and its AWKGUARD probe
  are removed), ADR-0048 (the recognised-heading set gains a reverse guard).

## Status

Accepted.

## Context

Both issues were triaged rather than implemented, because both carry the same instruction in their
own footer — *measure this issue's own claim before designing* — and in both cases the measurement
decided the outcome. Neither ends in the change its title implies.

### #314 — the detector, re-measured on the corpus as it stands

`literal-assertion-added` shipped **disabled by default** under ADR-0051 §D5 at a measured 25%
precision on a synthetic five-diff sample. A disabled detector is a feature nobody can rely on and
nobody remembers to delete, which is what R-02 exists to end.

Re-measured 2026-08-16 by enabling it (`WEAKENING_SCAN_LITERAL_ASSERTION=1`) and scanning
`git show --no-renames` for **every** non-merge commit reachable from `main` — no sampling:

| | count |
|---|---|
| non-merge commits scanned | **383** |
| commits producing at least one finding | 5 |
| findings total | 8 |
| findings that are the behaviour the detector exists to catch | **0** |

Classified by reading each line in its own commit: **four are comments** narrating an assertion in
prose, **two are `printf` calls** writing JSON fixtures, **two are this detector's own test
fixture**. Three of the eight are comments written the day before the measurement, in files added by
ADR-0143 — the needle matching the prose that explains the thing, which is rule 12 in a new place.

The earlier measurement (2026-08-14, 375 commits, 5 findings, 0 true positives) is confirmed rather
than replaced: the corpus grew by 8 commits and the precision did not move off zero.

### #313 — the heading, measured on both branches

`spec-coverage.sh:225` reports ids found outside every recognised section **only when
`DECL_N == 0`**. The asymmetry is deliberate (ADR-0072 §D5). Its consequence is that a **mixed**
SPEC — some ids under `## Success criteria`, others under an unrecognised heading — loses the second
group in silence, and nobody had counted that group. The 2026-08-14 comment measured the other
branch.

Measured by **instrumenting the checker itself** — a lookalike parser would have measured the
lookalike — and running it over all 78 `docs/specs/*.spec.md`:

| | count |
|---|---|
| SPECs | 78 |
| instrumentation produced nothing on | 0 |
| declaring ids, gate active | 44 |
| **MIXED: `DECL_N > 0` with ids outside every recognised section** | **0** |
| `DECL_N == 0` with outside ids | **0** |

The `$OUTSIDE` population is empty across the corpus in **both** branches. The described defect has
no instances, and the corpus does not come close to producing one.

## Decision

### D1 — `literal-assertion-added` is retired, and the AWKGUARD probe with it

Removed: the rule, the `WEAKENING_SCAN_LITERAL_ASSERTION` gate, the `LIT_ENABLED` variable, the
buffer, and the interval probe. The probe guarded **only** this detector — every other rule uses
`+`/`*`/`?`/alternation and needs no interval support — so once the detector is gone the probe has no
subject, which is the shape rule 9 warns about.

**The retirement is bounded and the ADR says by what.** This corpus is documentation and Bash; the
detector was written for `assert <expr> == <literal>` in application code, of which this repository
has almost none. The decision is **about this repository** and says nothing about the detector in a
Python or TypeScript codebase. Presenting the number as a general verdict would overreach.

### D2 — the assertions that covered it are removed, not left green

`HA4a`, `HA4b`, `HC5`, `HG1`–`HG5` and `HD4` are gone. **Five of them kept PASSING after the
removal**, and that is precisely why they could not stay: each asserted an ABSENCE that had become
trivially true. An assertion satisfied by the deletion of its own subject reads as coverage and pins
nothing.

`RET1`/`RET2` replace them as a reverse guard: the retired execution surface must STAY retired, so a
re-added copy is caught rather than silently re-enabled by someone reading ADR-0051 without this
ADR. The needle is the **execution surface**, not the name — comment lines are stripped before the
grep, because the header must be free to say what was retired and why (rule 12).

### D3 — #313 closes with a reverse guard, not with "no instances"

`RH1` asserts that both SPEC generators still emit a heading the checker recognises. The recognised
set is **derived by running the predicate itself** (`plan-task-predicate.awk` +
`spec-id-predicate.awk`, the two files and the order the checker loads at `spec-coverage.sh:229`),
never restated in the test — a copy of the heading list would pass while the checker's own rule
drifted away from it, which is the failure the assertion exists to prevent, one level up.

Widening the recognised heading set is **not** done: it has no instance to justify it. What has an
instance is the mechanism that keeps the population at zero — two templates, `interview-driver`
`:23` and `spec-from-issue` `:143`, feeding 75 of 78 SPECs — and one template edit would end it
silently.

### D4 — what these two do NOT change

- `spec-coverage.sh`'s `DECL_N == 0` asymmetry stays exactly as ADR-0072 §D5 set it. Nothing
  measured argues against it; the measurement says the branch is never reached.
- The `SUSPECT` sentinel, its advisory contract and the three surviving detectors are untouched.
  `HD5`'s alternation drops the retired name, because a guard listing a detector that no longer
  exists would match the retirement note explaining its absence.

## Consequences

- **Three plants, and two of them corrected the assertion they were declared on.** `RET1`'s first
  form re-added `LIT_ENABLED` and the assertion stayed green: the token list did not include the
  variable, so the guard's needle did not reach the mechanism it named. `PP0` in ADR-0143 failed the
  same way two days earlier. The registry is earning its cost.
- **A `set -u` failure inside a pipeline subshell fires the inherited `EXIT` trap.** Removing `HA4`
  left one reference to `$ha4_optin` in `HD4`; under `set -u` the expansion killed the `printf`
  subshell, whose inherited `trap 'rm -rf "$TMP"' EXIT` then deleted the shared fixture directory
  **mid-run**. Fourteen later assertions failed for reasons that looked unrelated to the edit. One
  unbound variable, in a harness that had passed `bash -n`.
- The registry grows by 3 plants: 2 in a 0.38s harness and 1 in `spec-coverage.test.sh`, which at
  28s is the most expensive file in the corpus (ADR-0143). That one plant costs ~28s of every CI
  registry run, and it is placed there because that is where the checker's contract is asserted.
- #355 was the third item in this triage and is **not** resolved here: measured the same day, 33 of
  387 plants sit on a prefix collision and **0 are mis-credited**, which turns its fix from "its own
  cycle" into a small change. The measurement is on the issue.

## References

- Issue #314's own R-01/R-02, R-03 (ADR-0061 §H16's inherited trigger loses one upstream
  false-positive source in this change).
- Issue #313's R-01 (no subject), R-02 (already held, asserted by `RE3`/`RE4` over 33 files).
- ADR-0051 (the four detectors), ADR-0048 (`R-NN` coverage), ADR-0072 §D5 (the asymmetry),
  ADR-0143 (the registry that verified these plants), CLAUDE.md rules 1, 4, 7, 9, 12, 13, 16.
