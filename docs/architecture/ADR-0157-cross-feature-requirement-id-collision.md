# ADR-0157 — a foreign feature's requirement id is not this feature's coverage

- **Topic slug:** `cross-feature-requirement-id-collision`
- **Issue:** #487
- **SPEC:** none — a bounded change to one checker, no requirement ids of its own
- **Extends:** ADR-0138 (the scope axis and the UNSCOPED verdict), ADR-0154 (the back-reference
  conjunction). Supersedes nothing.
- **Refuses:** per-feature requirement-id namespacing, on measured cost (A1)

## Status

Accepted — 2026-08-19.

## Context

`spec-coverage.sh` gates Step 5 → Step 6 on requirement coverage. Its test axis has three verdicts:

- `COVERED` — the id appears in a file that is **in scope**: the plan names it (half 1) and it names
  the feature back (half 2, ADR-0154).
- `UNSCOPED` — the id appears somewhere in the **discovered population** but not in scope. Remedy:
  name the file in your plan.
- `UNCOVERED` — the id appears nowhere. Remedy: write the test.

Requirement ids restart at `R-01` in every SPEC. The discovered population is the whole tests-root.
Those two facts do not compose: **the mention scan is satisfied by a stranger's `R-13`.**

Reported from a chain run on another project — 7 tasks, 5 batches, `agent_batch` dispatch. `R-13` and
`R-15` of the running feature matched the *previous* feature's already-committed tests, reported
`UNSCOPED`, and the gate exited 1. Both ids were genuinely untested. `UNSCOPED`'s remedy asks the
author to cite a stranger's harness from their plan; the alternatives left were renumbering a
released SPEC or writing a `(no-test:)` waiver for a requirement that was simply not tested.

This is CLAUDE.md **rule 18** in its second form. ADR-0138 named the first: a repo-wide scan against
a per-feature namespace. ADR-0154 then narrowed the *scoped* set with a back-reference. What nobody
narrowed is the population the other two questions are asked of.

### The second question, and the one nobody reported

`grep_boundary_test_all()` read the unfiltered population to tell `UNSCOPED` from `UNCOVERED`. The
`SCOPE-EMPTY` fallback — when the plan names no discovered test file at all — copied that same
unfiltered population **into scope**, so a stranger's `R-13` could report `COVERED`, exit 0.

A false green. Nobody reported it, because nothing looks at a green.

### Measured, 2026-08-19, on this repository's corpus

16 (spec, plan) pairs, 130 declared ids, 98 discovered test files.

**M1 — the class is here too, 12 times.** Of the 24 rows the frozen baseline carries as `UNSCOPED`,
**12 have their only mention in a file belonging to another feature**. Spot-checked on 404/R-04: the
harness that does claim issue #404 (`stop-gate-path-predicate.test.sh`) contains no `R-04` token at
all, while seven other features' harnesses do.

**M2 — ADR-0154's key set cannot answer this question.** Half 2 admits a file that names the plan's
basename *or any `ADR-NNNN` the plan cites*. Measured per pair, that admits **39 to 61 of the 98
files, a median of 47**: harnesses identify themselves by ADR id, and a plan cites its precedents'
ADRs alongside its own. Half the repository "names any feature back". Reusing it here moved **0 of
130** rows — the fix would have shipped green and inert.

**M3 — the plan basename alone is the opposite failure.** **6 hits across all 16 pairs.** A harness
essentially never cites its plan's filename.

**M4 — the issue number lands between them.** The feature's own number as a `#N` token: **1 to 11
files per pair**. It is also the token the house form already writes — `issue #404` — to say which
feature a harness belongs to.

**M5 — absence is not evidence, and two existing assertions said so.** The first implementation
dropped every file that failed to claim *this* feature. It produced the same 12 rows and turned
`RS1` and `RX6` red: their fixture is a file the plan does not name and that claims **nobody**, which
ADR-0138 defined as `UNSCOPED` and whose remedy — cite it — is right. Under the final rule all 12
flips rest on **positive** evidence: the file claims a *different* feature.

## Decision

### D1 — the mention scan reads a bounded population, and the bound has three states

Per discovered file, exactly one:

| state | test | in the population |
|---|---|---|
| **owned** | matches `$OWN_RE` — the plan's basename, or the feature's own `#N` | yes |
| **foreign-claimed** | carries some other `#<digits>` and not ours | **no** |
| **unclaimed** | carries no `#<digits>` at all | yes (ADR-0138's state, unchanged) |

Union that with **half 1** — the files the plan names — unconditionally. A file the plan points at
stays `UNSCOPED` even when half 2 drops it and even when it claims another feature: telling that
author to write a test that already exists, two lines from where their plan points, is the failure
mode M5 caught.

`$OWN_RE` is a **second key set for a second question**, not a copy of `$BACKREF_RE` (CLAUDE.md
rule 6 permits copies that answer different questions, and requires saying so). Half 2 is a
*conjunct*: half 1 does the discriminating, so half 2 can be generous. The question here has no
conjunct to lean on, so its key set carries the discrimination alone — which M2 and M3 measure.

The issue number is derived from filenames, never from a header line: the plan's `YYYY-MM-DD-<N>-`
prefix, then the SPEC's leading `<N>-`. Absent from both, the key set is the plan basename alone.

### D2 — the `SCOPE-EMPTY` fallback narrows, and gains a refusal

`SCOPE-EMPTY` keeps its name, its exit path and its fallback. What changes is the population it falls
back to: the files that could belong to this feature, instead of every test file in the tree. On a
project where no file claims anything the two sets are identical, which is why no existing assertion
moves.

When that population is empty **and** foreign-claimed files exist, the gate does **not** fall back:
`SCOPE-FOREIGN-ONLY` on stderr, scope stays empty, the ids report `UNCOVERED`. A finding, not a
vacuity — the same shape ADR-0154 §D2 gave `SCOPE-NO-BACKREF`.

**Its own token, not a `SCOPE-EMPTY` suffix.** A token that is a *prefix* of another is
indistinguishable to every `grep -q` already written against the shorter one; two assertions
(`RY6c`, `RY7`) branch on exactly that string. The first draft named it `SCOPE-EMPTY-OWNED` and
would have made both of them lie.

### D3 — the frozen baseline is regenerated, with per-row accounting

`spec-coverage-scope-baseline.tsv`: 12 rows move `UNSCOPED → UNCOVERED`, 0 row-count change, **0
`COVERED` row moves in either direction**. No id loses coverage and none gains it; what changes is
which remedy the 12 are told to apply. The 12 are listed by (spec, id) in the file's own dated block,
and each row carries the reason in its annotation column. Three rows already classed
`not-test-assertable` keep that class; the note is appended, not substituted.

A new class joins the column format: `foreign-mention-only`.

### D4 — what is enforcement and what is not (rule 16)

All of it is mechanical: three greps, one union, one exit code. Nothing here asks a model to behave.

## Consequences

- An id whose only mention belongs to another feature now reads `UNCOVERED`, whose remedy is the
  true one. The field case that produced this ADR is closed at the gate, not per project.
- The `SCOPE-EMPTY` false green is closed in the direction that matters: a stranger's id can no
  longer report `COVERED`.
- A project whose harnesses carry no `#N` tokens behaves exactly as before — every file is
  *unclaimed*, so the population is the whole discovered set.
- Stated bound: a six-digit colour literal (`#404040`) reads as a foreign claim and excludes that
  file. It makes a verdict stricter, never laxer, and a colour literal is not a requirement-id
  mention either way. Recorded here so its absence is not later read as coverage.
- `grep_boundary_test_all()` is **renamed** to `grep_boundary_test_claimed()` rather than quietly
  repointed. A helper called `_all` that reads a filtered set is the kind of half-true name a later
  reader trusts.

## Alternatives considered

**A1 — per-feature id namespacing (`R-<slug>-NN`), refused on cost.** It is the fix the field report
proposed. It touches `spec-id-predicate.awk`'s position-based declaration rule, `spec-normalize-ids.sh`,
ADR-0122's `strip_emphasis()` shared by reader and repairer, ADR-0072's near-miss healer, both SPEC
generators, the SPEC templates, and 199+ ids already declared across a closed corpus — which rule 14
forbids rewriting in place. It buys nothing the bounded population does not already close, and it
would have to be measured against exactly the 130 rows above to know that. Refused, recorded.

**A2 — scope the discovery to the current feature's tests.** The other half of the field report's
proposal. It is what ADR-0154 already does for the SCOPED set, and doing it to *discovery* deletes the
`UNSCOPED` verdict outright: a test that exists but is uncited becomes indistinguishable from one that
does not exist. The whole value of the two-verdict split is that their remedies differ.

**A3 — reuse `$BACKREF_RE` for the mention scan.** Measured, M2: 0 of 130 rows move. It would have
shipped as a green no-op with a convincing paragraph attached.

**A4 — drop any file that fails to claim this feature.** Measured, M5: same 12 rows, two ADR-0138
assertions red. Absence of a claim is not evidence of foreign ownership.

## References

- ADR-0138 — the scope axis, the `UNSCOPED` verdict, the frozen baseline
- ADR-0154 — the back-reference conjunction and its key set
- ADR-0122 — `strip_emphasis()`, shared by reader and repairer (A1's cost)
- CLAUDE.md rules 6, 8, 13, 14, 16, 18
- Issue #487
