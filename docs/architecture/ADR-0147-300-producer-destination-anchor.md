# ADR-0147 — a producer names the target as a destination, not as a mention (issue #300)

- **Date:** 2026-08-16
- **Issue:** #300 — "a producer is any line that mentions the target so a target only talked about looks produced"
- **Supersedes:** nothing. **Amends:** ADR-0095 (its `has_producer` predicate is replaced).

## Status

Accepted.

## Context

ADR-0095 shipped `transition-producer.test.sh` to catch a transition target that nothing enters —
the #248 shape, where `step_5_implementation` had producers only behind a default-off flag, and
the #238 shape, where `gate_5_review_decision` was entered by nothing at all. Its predicate was:

```sh
grep -- "$1" "$PROD" | grep -qE "manifest-transition\.sh|[Tt]ransition|(→|->)[[:space:]]*\`?$1"
```

A line counts as a producer if it names the target and carries the word "transition" anywhere. The
word "transition" is not a transition.

### R-01, measured before designing: the premise is real, the instances are zero

28 targets, 45 legal pairs, 2026-08-16. **Every target has a genuine producer today**, so the
predicate is not currently passing anything it should fail. Third issue in a row whose stated defect
has no live instance (#313, #314, now this), and the measurement is the reason none of them shipped
the detector its issue asked for.

What the measurement did find is that the looseness is large and mechanically decidable. On
`step_6_review`, **eleven lines counted as producers and exactly one was an instruction**:

| lines | shape |
|---|---|
| 3 | negation — `do NOT transition to step_6_review` |
| 1 | negation wrapped onto a second line |
| 4 | narration — `before transitioning to`, `it never blocks the transition to` |
| 1 | narrative arrow — `block the Step 5 → step_6_review` |
| 1 | the target is the SOURCE — `Transition step_6_review → step_7_commit` |
| **1** | **the producer** — `… exit code is 0 → transition to step_6_review.` |

### What that costs, and it is not precision

TP1, the class guard, **could not be planted**. The file's only declaration was TP6's, an instance
pin for #248. Delete the one real producer of `step_6_review` and TP1 stays green, because ten
prose lines hold it up. An assertion nobody can plant pins nothing — rule 2, inside the guard built
to catch things that pin nothing.

That is measured, not argued. The same mutation, run against both predicates on 2026-08-16:

- old predicate: `PASS=14 FAIL=0`, TP1 green with the producer deleted.
- new predicate: `FAIL: TP1 … undeclared: step_6_review`.

## Decision

### D1 — classify the line, do not grep it

`has_producer` becomes a classifier over a flattened copy of the population. First match wins:

| class | rule | producer |
|---|---|---|
| `CALL` | a `manifest-transition.sh` invocation naming the target as an argument | yes |
| `NEG` | the line negates the transition, or continues a negation that wrapped | no |
| `PROSE` | the verb is preceded by a determiner or preposition, or the clause is quoted | no |
| `IMP` | `transition[s\|ing\|ed] [back] to\|into <target>` at a clause boundary | yes |
| `ARROW` | `<id> -> <target>` where `<id>,<target>` is a legal pair in the derived table | yes |

`PROSE` is ADR-0117's rule applied to a second predicate: **the preceding word separates an
instruction from prose, and form cannot.** `ARROW` is #355's right anchor in a second place — an
arrow whose left operand is the target is the target's *source*, and `block the Step 5 →
step_6_review` has no source at all. The legal-source set is derived from the same pair table the
targets come from; nothing is listed by hand.

Measured effect over the corpus: 63 producer lines, 14 rejected, **28 of 28 targets keep a
producer**, `step_6_review` goes from 11 to 1.

### D2 — line-wise, and the one thing wrapping breaks is handled by a lookback

Joining wrapped lines into paragraphs was implemented and **rejected on measurement**. A paragraph
carrying both a `manifest-transition.sh` call and an unrelated mention of a second state credits the
second state with the first one's call, and it destroyed the arrow attribution on `step_e1_plan` —
the exact form ADR-0095 had to add, and the regression R-03 names.

The one case wrapping genuinely breaks is a negation split across two lines
(`… and do NOT` / `transition to step_6_review without user acknowledgment.`), which reads as an
imperative from the second line alone. A one-line lookback handles it. Rule 3 is satisfied by
flattening decoration — backticks, bold, `→` to `->`, case, blank runs — not by dissolving the line
structure the classifier depends on.

### D3 — the floors are vacuity guards and say so at the site

`TP1c` and `TP1c2` are `>= N` on the producer and rejected populations. Rule 10 applies: a floor
absorbs its own plant, so neither is evidence about any individual verdict. They exist because a
rejected count of zero reads exactly like a corpus with no prose in it, which is what this corpus
looked like before anyone measured (rule 7). `TP1b` is what pins the verdicts, against a fixture of
the seven measured shapes, both directions.

## Consequences

- One file changed: `staging/plugin/scripts/tests/transition-producer.test.sh`. 14 assertions → 19.
- One new plant, `TP1`, seen RED. The file now has 2.
- **The residue is stated rather than closed.** A line phrased `transitioning to <target>` with no
  determiner in front is an imperative to this classifier whether or not it is one. That is a
  judgement about English word order, not a parse, and no rule over prose does better. What changed
  is that the classes it *can* decide — negation, source side, quoted, determiner-led — are decided.
- `is_exempt`, `TP2`, `TP3`, `TP4` are untouched; the exemption mechanism reads the same predicate,
  so a stale waiver is still caught by the tightened one.

## References

- ADR-0095 (the guard and its predicate), ADR-0117 (the preceding word separates instruction from
  prose), ADR-0145 (#355, the right anchor), ADR-0085 (guard the denominator), ADR-0124 (why a floor
  is only a vacuity guard), CLAUDE.md rules 2, 3, 7, 10, 12.
