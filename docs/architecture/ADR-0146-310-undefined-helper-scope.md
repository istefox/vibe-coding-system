# ADR-0146 — a call to a helper the file does not define, and the floor that was asked for instead (issue #310)

- **Date:** 2026-08-16
- **Issue:** #310 — "an undefined assertion helper is indistinguishable from a passing assertion"
- **Supersedes:** nothing. **Amends:** ADR-0081 (its instance now has a standing guard).

## Status

Accepted.

## Context

ADR-0081 found it on the way to something else: `pairs-completeness.test.sh` had no `ok()`/`bad()`
helpers, a draft called them anyway, and **six assertions printed "command not found" while the
suite reported `PASS=244 FAIL=0` and exited 0**. Nothing in these harnesses runs under `set -e`, so
a call to a helper the file does not define is indistinguishable from an assertion that passed. It
is the false-green class living inside the files where every other assertion lives.

### R-01, measured before designing: the population is zero

All 82 harnesses, 2026-08-16: **zero** calls to a helper the file does not define. ADR-0081's
instance was repaired and no new one exists.

Getting to that zero took three attempts, and the failures are the useful part:

- **47 findings, none real.** The scan matched the English word "no" inside message strings — and
  `no` *is* a helper here, defined by `phase1.test.sh`. The vocabulary was right; the POSITION
  detection was wrong.
- **3 findings, none real.** Two were `case` labels (`no)`) and one an assignment (`mk="$2"`). Both
  sit in command position, and position alone cannot tell them from a call.
- **0 findings**, once the scan tracked quote state ACROSS LINES — the messages in this corpus wrap
  — masked heredoc bodies, and excluded `name=` and `name)`.

A detector that reports zero is a claim about the detector until something is planted in front of
it. One `verdict` call was planted into a copy of the corpus: the scan found exactly it, and `bash`
confirmed the live behaviour — `command not found` on stderr, execution continues, exit unaffected.

### R-02, measured: 49 of 82 harnesses have no assertion-count floor

The issue asks for "an assertion-count floor per file so a vanished assertion is visible".

## Decision

### D1 — the guard is a derived scan, not 82 copies of a runtime hook

`harness-helper-scope.test.sh`. The alternative was a `command_not_found_handle` in every harness,
which is 82 copies of the same three lines; ADR-0086 already refused a shared helper across these
hermetic files, and 82 copies of a runtime hook is the same problem with more surface.

**The vocabulary is DERIVED, never listed**: a helper is any function defined by two or more
harnesses, which is what makes it a convention a draft would copy in rather than one file's private
function. A hand-written list would be blind to precisely the file that invents a new helper name
(rule 8).

### D2 — `HS2` is a self-test, because `HS1` ships against a population of zero

`HS1` is green today and would be green with a broken scanner. `HS2` plants a call into a copy of
the corpus and requires exactly one finding, so the two outcomes are distinguishable. Without it,
this ADR would be shipping a green line and calling it a guard (rule 16's distinction: the
enforcement half has to be identifiable).

### D3 — R-02 is REFUSED IN THE FORM IT IS WRITTEN, and the reason is a rule this repo already has

A per-file assertion-count floor is the instrument ADR-0124 retired, for the reason stated as
CLAUDE.md rule 10: **a floor absorbs its own plant.** An assertion of the form `total >= N` against
a file with slack still passes when one assertion is deleted, so a floor added to 49 files would be
49 assertions that mostly cannot fail — precisely the false-green shape #310 exists to remove, added
in bulk, in the name of removing it.

What would actually make a vanished assertion visible is ADR-0124's instrument: a **frozen per-file
baseline**, red on any DROP, with a deliberate bump when a file legitimately gains assertions. That
carries real friction on every PR that adds an assertion, and it needs its own design — including
whether the count is derived statically from call sites or by running the suite twice, which the
300s local test ceiling (ADR-0143) already rules out.

So R-02 is not silently dropped and not quietly satisfied: it is answered with a refusal, a reason,
and a successor — **#449**, which carries the measurement and the four things to derive before
designing it. R-01 and R-03 ship here.

## Consequences

- One new harness, ~1s, registered in `docs-ci.yml`'s list (`CI1` fails on any staged harness the
  list omits) and carrying 2 plants, both seen RED.
- **The scan is a heuristic over bash source and says so.** It tracks quotes and heredocs but does
  not parse bash: a call built by `eval`, or a helper name assembled at run time, is outside it.
  What it covers is the shape that has actually occurred — a draft calling `ok`/`bad` in a file that
  never defined them.
- The vocabulary threshold (defined by ≥ 2 harnesses) is a judgement, and a helper defined by
  exactly one file is invisible to it. That is the safe direction: a private function called only in
  its own file cannot produce this defect.

## References

- ADR-0081 (the instance), ADR-0086 (why not a shared helper), ADR-0124 (why not a floor),
  ADR-0143 (the 300s ceiling that rules out running the suite twice), CLAUDE.md rules 4, 7, 8, 10.
