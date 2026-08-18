# SPEC — spec-coverage's test-axis scope requires a test file to name the feature back

**Topic slug:** spec-coverage-scope-back-reference

## Objective

Close the path by which a foreign `R-NN` satisfies this feature's requirement-coverage gate.

ADR-0138 narrowed `spec-coverage.sh`'s test axis to the test files a plan names, so an unrelated
harness could no longer supply a match. Measured against a real plan, the narrowing does not hold: a
plan names other harnesses for ordinary reasons — a precedent it copies, an idiom it reuses, a
verification step it prescribes — and each enters the scope carrying its own ids.

## Context — what was measured before this was designed

All figures derived 2026-08-18 from the corpus, not from an issue (rule 13).

**The exposure.** On the `ADR-0153` plan, `spec-coverage.sh` reports 6 files in scope. Three are
cited as precedents and carry seven ids of their own — `pairs-completeness.test.sh` has `R-05`,
`R-09`; `plant-check.sh` has `R-01`, `R-05`, `R-12`; `recovery-preflight.test.sh` has `R-02`,
`R-03` — every one inside that feature's declared `R-01 … R-24` range. Before its Task 6 landed,
four of them reported `COVERED` while being cited nowhere in the feature's own harness.

**Two designs refused on measurement.** Scoping to the files a plan's `Budget:` lines name: only 11
of 53 plans name a test file there, so 42 would collapse to an empty scope. Requiring the id
mention to sit in an id-mapping comment header: 87 of 893 mentions have that form and 22 of 31
files carrying ids have none, so most genuine coverage would flip to uncovered — the same wall
ADR-0138 hit with its own candidate, which measured 49 of 93 ids as comment-only.

**The design that survived.** A scoped file must also name the feature back:

```
plans naming >= 1 discovered harness                 : 52
  of which >= 1 named harness names the plan back    : 52
scoped files under today's filter                    : 263
scoped files naming the plan or one of its ADRs      : 169
dropped from scope                                   : 94   (36%)
ids flipping COVERED -> UNCOVERED under the new rule : 0
```

The 94 dropped are the precedent citations. Zero genuine coverage is lost on any of 52 plans.

**The proxy in that zero, and how this feature closes it.** The flip measurement approximated each
feature's declared id set by the ids its **plan** cites, not by parsing its SPEC. Regenerating
`spec-coverage-scope-baseline.tsv` — one row per (SPEC, declared id) pair — *is* the re-derivation
against the SPEC corpus, so the proxy is retired by this feature's own deliverable rather than
carried forward as a caveat.

## Scope

**In:** the test axis of `spec-coverage.sh`, its scope filter, the frozen corpus baseline that
proves the filter's behaviour, the harness that reads it, and one line in the architect's plan
output contract.

**Out:** the plan axis, the discovery predicate for "what is a test file", the exit-code contract,
the `(no-test: …)` waiver mechanism, `UNCOVERED`'s own semantics, and every other consumer of the
script. This feature narrows one population; it changes no verdict's meaning.

## Stack

Bash 3.2 and POSIX `awk`/`sed`/`grep`, matching the file being changed. No new dependency, no new
helper script unless the extraction criterion (ADR-0086) is met — one consumer means one file.

## Architecture

The filter becomes a conjunction. A discovered test file enters the test axis when **both** hold:

1. its basename appears in the plan as a whole token — today's condition, unchanged;
2. its own text names the plan's basename, or one of the `ADR-NNNN` ids the plan cites.

Half 2 is an OR by measurement, not by preference: harnesses in this corpus name the ADR more often
than the plan, and requiring the plan alone was not measured and risks flips the OR does not have.

The derivation is itself a population, so it carries a denominator guard (rule 7): a bug that made
every file fail half 2 would collapse the scope everywhere, and the baseline would report that as
187 changed rows rather than as a collapse.

## Data model

`spec-coverage-scope-baseline.tsv` keeps its shape — one row per (SPEC, declared id) pair with its
scoped verdict. Its rows are regenerated under the new rule and the delta is recorded.

No manifest field is added. No new file format is introduced.

## API — the script's stdout and exit codes

Unchanged, with one addition. `COVERED`, `UNCOVERED`, `UNSCOPED`, `DUPLICATE`, `MALFORMED`,
`ORPHAN`, `STALE-WAIVER` keep their meanings and their exit codes.

An id whose only mention now sits in a descoped file reports `UNSCOPED`, which already exists and
already carries the right remedy — cite the id in the test file this feature actually wrote. No new
token is needed for the common case.

One state is genuinely new: the plan names one or more discovered harnesses and **none** names the
feature back. That is neither "the plan names no test file" nor a clean scope, and it gets its own
token and its own remedy line.

## UI flows

None. The script is invoked by `concept-to-code` Step 5 and by its harness.

## Edge cases

- **A plan names harnesses, none names back** — the new token above. Does not occur in today's
  corpus (52 of 52 resolve), and is exactly what a feature extending a shared harness would produce.
- **A plan names no test file at all** — unchanged: today's denominator guard already answers it,
  and the new state must not be confused with it.
- **A harness covering two features** — names both plans or both ADRs; the OR admits it.
- **A plan citing an ADR that no harness names** — the harness that names the plan still scopes in.
- **An ADR id appearing in a harness for an unrelated reason** — possible, and narrower than
  today's exposure rather than a new one: it requires the stranger to cite this feature's own ADR.
- **The corpus grows** — the denominator guard is a floor, and a floor absorbs its own plant
  (rule 10), so it is a vacuity guard and says so at its site; the baseline is the real evidence.
- **`--tests-root` omitted** (placeholder or provisional test-cmd) — the whole test axis is already
  skipped; this feature adds nothing there.

## Success criteria

`R-10`, `R-11` and `R-12` are documentation obligations and carried a `(no-test: …)`
exemption when this SPEC was written. The clauses were deleted at Gate 2, on 2026-08-18,
because the exemption reported `STALE-WAIVER` and blocked the gate before any code existed:
`spec-coverage.test.sh` already contains those three tokens as `RC3`/`RC4` heredoc fixtures,
so the ids are "mentioned in a scoped test file" by a fixture that has nothing to do with
this feature. The deletion alone would turn that block into a false `COVERED`, so it is
paired with the existence-level assertions the plan's Task 1 adds — both halves, never one.

- [ ] R-01 — a discovered test file enters the test axis only when the plan names it **and** its own text names the feature back; either half alone is not enough.
- [ ] R-02 — "names the feature back" is the plan's basename or one of the `ADR-NNNN` ids the plan cites, matched as a whole token the same way the basename already is.
- [ ] R-03 — an id whose only mention sits in a descoped file reports `UNSCOPED`, never `COVERED`.
- [ ] R-04 — the plan axis, the discovery predicate, the exit codes and the documentation-exemption waiver behave exactly as before; no verdict changes meaning. The clause naming that waiver is written without its literal marker form on purpose: the extractor reads the marker line-wise, so a requirement mentioning the mechanism would exempt itself from the axis it belongs to.
- [ ] R-05 — "the plan names harnesses but none names the feature back" is a distinct reported state, told apart from "the plan names no test file", and its remedy names the one-line fix.
- [ ] R-06 — the back-reference derivation carries a denominator guard that fails when it stops resolving across the corpus, declared at its site as a vacuity guard rather than as the primary evidence.
- [ ] R-07 — `spec-coverage-scope-baseline.tsv` is regenerated under the new rule and every row whose verdict changes is accounted for; a `COVERED` → `UNSCOPED` flip that is not a precedent citation blocks the feature.
- [ ] R-08 — the architect's plan output contract states that a plan names the harness it creates and that the harness names the plan or its ADR back.
- [ ] R-09 — every new assertion is seen RED against a declared plant, and the plant registry reports it `FIRED`, never `NOFIRE`, `BADPLANT` or `VACUOUS`.
- [ ] R-10 — the record is written: an ADR, a `docs/chain-decisions.md` block, one `CLAUDE.md` index line and a `PROJECT.md` row.
- [ ] R-11 — the ADR records both refused designs with the measurements that refused them.
- [ ] R-12 — the ADR states which parts of this feature are instructions rather than enforcements, naming the architect's contract line specifically.
