# ADR-0098 — Gate 0 showed two recommendations and declared neither, and its size vote is a constant

- **Status:** Accepted
- **Date:** 2026-07-31
- **Issues:** #227 (found by the Phase 7 shakedown run at the first gate of the first invocation)
- **Related:** ADR-0097 (#237, the same family one gate later — the shared principle is recorded
  there), ADR-0017 (the three-path routing this gate performs), ADR-0032 / ADR-0044 (the
  `$HOME`-coupled skill-private harness this rename had to reach)

## Context

Gate 0 displayed two "recommended" markers that can point at different options, with nothing saying
which wins:

1. the question string hardcoded `Recommended: [<path>] — <auto_detect_reason>`;
2. the global `AskUserQuestion` convention has the orchestrator put **its** choice first and append
   `(Recommended)` to the label.

On the shakedown run the user saw `Recommended: [h] hybrid` in the question text and
`[s] Standard … (Recommended)` in the option list, in the same box, and asked which to believe.

**Neither was wrong.** The auto-detect is a mechanical vote on repository size and title keywords.
The orchestrator knew the invocation existed to exercise Steps 5 and 6, which `hybrid` never
reaches. The gate simply presented both as "the recommendation".

## The second finding is stronger than the issue states

Issue #227 says `file_vote` pins to `standard` "on any repository past a few hundred files". Measured,
the threshold is **20**:

```text
< 10 → express      10–19 → hybrid      >= 20 → standard
```

So on any repository with 20 files or more the vote is permanently `standard`. Feed that into the
documented majority rule — *file_vote + keyword_vote, tie-break: both express → express, else
hybrid* — and exactly two outcomes remain reachable: `standard` when the title carries an
architecture keyword, `hybrid` otherwise. **`express` can never be auto-recommended.**

Corroborated by the corpus rather than by argument: three manifests ever recorded a `file_vote`, and
all three are `standard`, on repositories of 255, 541 and 595 files.

## Decision

### D1 — The orchestrator's recommendation wins, and the vote is labelled advisory

The question says `Auto-detect suggests:`. The orchestrator marks its own option per the global
convention. Precedence is stated in the block rather than left to be inferred.

The choice between the two is not close: the vote sees a file count and a title, the orchestrator
sees the conversation that produced the invocation. What made this a defect was not which signal is
better but that **neither was declared to win**.

### D2 — A divergence is shown, never silently resolved

When the orchestrator's choice differs from the vote, one line is prepended naming both and the
reason for overriding. When they agree, nothing is prepended.

This is the part that answers the user's actual question. Picking a winner and hiding the loser
would remove the contradiction from the screen without removing it from the system — the operator
would simply stop being told that two signals disagreed.

### D3 — Rename `file_estimate` → `repo_file_count`; do not re-tune the thresholds

**At Gate 0 there is no feature-size signal to be had.** There is no SPEC and no plan — they are
what the chain is about to produce — so a repository-size proxy is not a lazy choice, it is the only
thing measurable at that moment. What was wrong was the **name**, which claimed to estimate
something the number does not describe.

Inventing better thresholds without a better signal would be the same error with fresher numbers.
Dropping the vote entirely would change routing on a gate a human answers anyway. So: rename, say
what it measures, and state the degenerate consequence at the gate so the reader can weigh it.

`express` remains available as a click. It is only unreachable as a *suggestion*.

## Verification

15 assertions in `gate0-recommendation.test.sh`, plus a `Z1` floor. Harness 59/59.

Seen RED against the unmodified tree: **10 of 15** — `N1`, `N2`, `N3`, `N4`, `N5`, `N5b`, `N7`,
`N7b`, `N8`, `N9`. `N0`/`N0b`/`Z1` are anchors; `N6`/`N6b` are the measured premise, executed in
both directions (a 25-file repo votes `standard`, a 5-file repo still votes `express` — the vote is
degenerate on real repositories, not broken).

Five planted defects. **Four fired; the fifth did not, and that is the useful one.**

| plant | fires |
|---|---|
| `Recommended:` restored in the question string | `N1` |
| precedence sentence removed | `N3` |
| divergence-disclosure clause removed | `N4` |
| field renamed back in the script | `N5`, `N5b` |
| legacy harness anchor left on the old name | **nothing — see below** |

### The plant that did not fire

`N9`'s first draft grepped for `repo_file_count` **anywhere** in the skill-private harness. The
plant changed only the `grep -q` pattern; the surrounding `ok()`/`bad()` message strings still
carried the new name, so the assertion passed a file that would have gone red against the renamed
script.

**The needle must belong to the mechanism, not to the prose describing it.** It now matches the
literal `grep -q '^repo_file_count='`, and the re-planted defect fires. Rule 12's cousin, and the
second instance the same day — `spec-archive.test.sh`'s `SA10` had the identical shape a few hours
earlier.

### A sixth instance of the decoration family

`N7b` failed against correct text because its clause contains a backticked word and the needle did
not. Rather than reword the needle, the flattened copy now strips backticks and asterisks as well as
line breaks: **a clause is the same clause whether it wraps, whether a word inside it is code-quoted,
and whether it is bolded.** Structural markers are still matched line-wise against the undecorated
block, because there the decoration *is* the structure.

Met while writing an ADR that cites the five earlier instances.

## Consequences

- **`repo_file_count` is a renamed output field with three consumers**, all updated: `gate0-detect.sh`,
  `concept-to-code/SKILL.md`'s field list, and the skill-private `concept-to-code/tests/run-tests.sh`.
  That last one resolves `$HOME/.claude/skills/…`, so it tests the **deployed** copy and reads red
  until sync — the documented behaviour of that file (ADR-0032 flagged it, ADR-0044 recorded it
  actively misleading a verification step).
- **Historical `auto_detect_reason` strings keep the old name.** They are accurate records of what
  the script printed at the time; rewriting them would falsify the record (ADR-0075's principle).
- **The routing vote is unchanged.** This ADR renames and discloses; it does not make `express`
  reachable. A gate that can only ever suggest two of its four options is a real limitation, now
  stated at the gate instead of discovered at the 595th file.
- **The divergence line is prose an orchestrator is asked to emit.** Nothing enforces that it
  appears, which is the same instruction-not-enforcement boundary ADR-0047 and ADR-0048 record for
  their own gates.
- Inert until sync.
