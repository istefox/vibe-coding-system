# ADR-0107 — The fence guard checked the subset that could abort, not the set that declared itself

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #281 (found by sweeping Phase 8's ADRs for a disclosure repeated four times)
- **Related:** ADR-0083 (the fence-contract rule), ADR-0096 / ADR-0102 / ADR-0103 / ADR-0104 (the
  four that disclosed this by hand), ADR-0095 (#248, the same producer/consumer shape), ADR-0085
  (guard the denominator)

## Context

`fence-contract-coverage.test.sh` derived `CONTRACT_IDS` from `ABORT_LIST` — the **abort-capable**
subset, built by `fence_is_abort_capable`, which looks for a literal `exit 1`/`exit 2` or the word
"abort".

A fence that declares itself and then ends `exit 3` or `exit "$_rc"` is outside that predicate, and
therefore outside `F4` (must be executed), `F6` (ids unique) and `F7` (must parse).

**Measured: 18 declarations, 13 in the population, 5 invisible.**

| id | disclosed in |
|---|---|
| `c2c-step1-spec-archive` | ADR-0096 |
| `c2c-gate2b-trust-probe` | ADR-0102 |
| `c2c-step5-baseline-ancestry` | ADR-0103 |
| `c2c-step7-snapshot-collapse` | ADR-0104 |
| `concept-to-code-step5-plan-structure` | **nobody — it predates all four** |

### The defect was never coverage

All five are executed by a test and all five parse — checked before proposing anything. Nothing was
broken.

**What was missing is that nothing checked it.** Four ADRs assert coverage by hand, in prose, and
each was telling the truth. **A hand assertion that is true reads exactly like one that is
verified** — which is the producer/consumer shape ADR-0095 records, one level up: the claim and the
check in different places with nothing tying them together.

**The fifth entry is why it matters.** `concept-to-code-step5-plan-structure` had been outside its
own guard since before this session, and no ADR noticed. Four disclosures were written about a
population none of them had counted.

## Decision

### D1 — Derive the population from every declaration

`CONTRACT_IDS` and `F6`'s raw count now read `ALL_FENCES`. `F4`, `F6` and `F7` widen from 13 to 18.

### D2 — `F3`, `F5` and `F8` deliberately keep the narrow population

`F3` asks "must an abort-capable fence declare itself", so the abort-capable subset **is** its
question. `F8` measures the escape hatch from `F3` and would change meaning if widened. `F5` rides
on `F8`'s population, and there is exactly one illustration in the corpus, inside that subset —
**measured, not assumed**, and the test says so, with what would have to change if a second
illustration ever appeared outside it.

### D3 — Two new assertions, one property and one count

`F9` states the property rather than a number, so it cannot rot: every `fence-contract:` marker that
exists must be in the set `F4`/`F6`/`F7` check. `F10` guards the denominator (ADR-0085) — an
enumeration that quietly stops matching would empty `F4`, `F6`, `F7` and `F9` at once, and four
silent passes read as coverage.

## Verification

45 assertions in `fence-contract-coverage.test.sh` (was 43). Harness 67/67.

Seen RED by reverting the derivation to `ABORT_LIST`: **`F9` fails naming all five**, and `F10`
reports 13 against a floor of 15.

**One honest note about that plant.** `F6` also failed, with the message "18 contract markers but
only 13 distinct ids — an id is reused", which is nonsense. The plant reverted `CONTRACT_IDS` and
not `RAW`, so `F6` compared two populations that never coexisted; the real pre-fix state had both on
`ABORT_LIST` and `F6` passed at 13. **`F9` is the evidence; `F6`'s failure there is an artifact of
an incomplete plant** — the "inspect what the plant actually produced" rule (ADR-0090) applied to my
own plant rather than to someone else's code.

## Consequences

- **Four ADRs now say something false about their own fences.** ADR-0096, ADR-0102, ADR-0103 and
  ADR-0104 each state that `F3`/`F4` do not reach the fence. Each gains a dated `## Correction`
  rather than being edited in place (ADR-0034 precedent).
- **`F4`'s two accepted needles are unchanged**, so the five needed no new execution — they already
  named their id in an extractor, which is what made them verifiable at all.
- **A declared fence that is genuinely not executed will now fail** where before it was invisible.
  That is the point, and it is a new way for the harness to go red on a file nobody touched.
- The narrow population survives in three assertions for three stated reasons. A future reader
  widening them "for consistency" would break `F8`'s meaning; the test says so at that site.
