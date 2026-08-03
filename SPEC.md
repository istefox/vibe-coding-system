# SPEC — the transition-pair count is stated in three files and derived in one

Source: GitHub issue #289

## Objectives

1. Find every site that states the legal transition-pair total as a literal (SKILL.md prose, the
   `manifest-transition.sh` comment, the test) and every site that derives it at run time.
2. Derive the count wherever it is used, with a count guard on the derivation so a parse returning
   zero fails loudly instead of reading as agreement.
3. Where a literal is genuinely needed, assert it against the derivation rather than leaving it as
   an unverified claim.

## Scope

In: the transition-pair count literals and derivations across
`staging/plugin/skills/concept-to-code/SKILL.md`,
`staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh`, and the harness files that
state or derive it.

Out: the transition graph itself — no pair is added or removed by this issue. Out: ADR-0105's
already-completed removal of the four `gate_5_review_decision` pairs. Out: historical ADRs and plans
that record an older total accurately for their moment (ADR-0034 precedent).

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/scripts/manifest-transition.sh` — the state machine that
  builds the pair list, and the header comment stating the total.
- `staging/plugin/skills/concept-to-code/SKILL.md` — §3's prose statement of the total and its
  enumeration of the pairs. Anchor on the distinctive count string, not a line number (ADR-0082).
- `staging/plugin/scripts/tests/gate5-state-removal.test.sh` — `GR3`, which **derives** the count
  (measured at spec time: 45, down from 49) and is the one detector; `GR4`, which counts the stated
  literals across SKILL.md and `manifest-transition.sh`; `GR5`, which forbids the stale 49.
- `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` — ADR-0028's
  reconciliation of the earlier 48/213/229 counts, the precedent for this class of literal.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108).
- `docs/architecture/ADR-0105-265-gate5-state-removal.md` — the source, including the record that an
  assertion pinning the total was **changed in kind** because a total moves whenever any unrelated
  pair does. Anchor on that sentence, not on the `:90` line number.
- `PROJECT.md` §9.6 — the second source, restating "three chances to drift, one detector".

## Data model

The legal transition pairs are `<from_state> -> <to_state>` lines emitted by
`manifest-transition.sh` into its `$PAIRS` file, plus the producer exemptions declared in the same
script (issue #248, ADR-0095). Any derivation must decide whether exemptions are inside or outside
the count and say so.

## API / Interfaces

The derivation itself: a checker over `manifest-transition.sh`'s pair emission, branching on an exit
code, distinguishing "did not run" (exit 3) from "found zero pairs". A zero-pair parse must not be
allowed to satisfy a comparison against a literal that also failed to parse.

## UI flows

None.

## Edge cases

- **A total moves whenever any unrelated pair does.** ADR-0105 records changing `TBP1` in kind for
  exactly this reason: its message claimed a specific pair "is present" while its test was
  `ACTUAL_PAIRS >= 49`, which is never evidence about that pair. The remaining literals must be
  checked for the same weakness — R-01's "check whether" is the measurement, not a formality.
- **A parse returning zero reads as agreement** if both sides parse to zero. The count guard exists
  for this.
- **`grep -c … || echo 0` yields `0\n0` on no match** — the idiom issue #174 documented here and
  ADR-0105 hit again in `GR1`. `|| true` is the fix.
- **A needle that is the number itself will match unrelated numbers.** The literal `45` occurs in
  ordinary text; a scan must belong to the mechanism (rule 12).
- ADR-0105 already had to correct five assertions pinned to 49 across three files when four pairs
  were removed; the next graph change repeats it unless the literals are derived or asserted.

## Success criteria

- [ ] R-01 — the count is derived wherever it is used, with a count guard on the derivation so a
      parse returning zero fails loudly instead of reading as agreement.
- [ ] R-02 — a remaining literal, if any is genuinely needed, is asserted against the derivation.
- [ ] R-03 — seen RED against a planted extra pair.
