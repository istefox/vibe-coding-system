# SPEC — the sixth bare manifest-set-flag.sh mention was left when the other five were fixed

Source: GitHub issue #286

## Objectives

1. Re-derive the population of manifest-helper mentions in
   `staging/plugin/skills/concept-to-code/SKILL.md` that are **not** written in the PATH-RULE form,
   rather than trusting ADR-0028's count of five plus one deferred.
2. Convert every remaining bare mention to the PATH-RULE form, so the convention is enforced rather
   than partially enforced.
3. Add a derived guard that fails when a new bare mention appears, count-guarded so an empty
   population cannot read as full coverage.

## Scope

In: every call site of a manifest helper script inside
`staging/plugin/skills/concept-to-code/SKILL.md`; the derived guard and its plant declaration; the
count guard on the derivation.

Out: the helper scripts themselves — they are correct and are not edited. Out: mentions in ADRs,
plans and other `docs/` records, which are historical and are not rewritten (ADR-0034 precedent).
Out: ADR-0028's own body, which records the deferral accurately for its moment.

## Stack

Bash 3.2 (macOS-portable) shell scripts under `staging/plugin/scripts/` and
`staging/plugin/skills/*/scripts/`; Markdown SKILL.md instruction files; awk predicates; a 68-file
`*.test.sh` harness under `staging/plugin/scripts/tests/` run by `.claude/test-cmd`; GitHub Actions
CI (`ci`, `markdownlint`, `links`). No application runtime.

## Architecture

- `staging/plugin/skills/concept-to-code/SKILL.md` — the file carrying the mentions. **The `:569`
  anchor from ADR-0028 has moved**; the issue says so explicitly and directs anchoring on a
  distinctive string (ADR-0082). Measured at spec time, bare (non-PATH-RULE) mentions of
  `manifest-set-flag.sh` are still present in at least the helper-inventory bullet, the Gate-4.0
  autopilot sentence, the `BASELINE_COMMIT` "NOT via `manifest-set-flag.sh`, which is boolean-only"
  clause, and the `step5_mode: "agent_batch"` fallback sentence — line numbers deliberately not
  recorded, and the population must be re-derived rather than taken from this list.
- The manifest helpers under `staging/plugin/skills/concept-to-code/scripts/`:
  `manifest-init.sh`, `manifest-transition.sh`, `manifest-validate.sh`, `manifest-set-flag.sh`,
  `manifest-set-artifact.sh`, `manifest-set-gate.sh`, `manifest-field-state.sh`.
- `staging/plugin/scripts/tests/concept-to-code-manifest-helpers-guards.test.sh` — the sibling
  harness ADR-0028 created for issue #32; the natural home for the derived guard, or a new
  hermetic file per the one-file-per-issue pattern.
- `staging/plugin/scripts/tests/plant-check.sh` — the plant registry runner (ADR-0108); each new
  assertion needs a declared plant beside it.
- `docs/architecture/ADR-0028-32-manifest-helpers-guards.md` — the source, which records the
  deferral and its reasoning (the sixth mention is grammatically distinct: a "via `X`" clause
  embedded in a longer conditional sentence, not a standalone bullet).
- `docs/architecture/ADR-0082-207-210-cross-reference-form.md` — the rule that a cross-reference
  must name a distinctive anchor rather than a line number.

## Data model

None.

## API / Interfaces

The PATH-RULE form itself: a helper invocation written with its fully-qualified deployed path
(`~/.claude/skills/concept-to-code/scripts/<helper>.sh …`) rather than as a bare script name. The
derived guard is a checker — it branches on an exit code and must distinguish "did not run"
(exit 3) from "found nothing".

## UI flows

None.

## Edge cases

- **A bare mention that is prose, not a call site.** The `BASELINE_COMMIT` sentence and the
  `step5_mode` fallback sentence both name `manifest-set-flag.sh` in order to say *not* to use it.
  A guard whose needle is the script's name counts the prose explaining it — rule 12, the class the
  repository has hit six times. The guard must distinguish a call site from a mention.
- **The count of five was correct at the time.** The population may have grown since; re-derivation
  is required, not confirmation of the old number.
- **An empty derivation reads as full coverage.** The count guard exists for exactly this.
- **The deployed and staged copies can differ**, which is why a bare mention resolves against the
  wrong tree — the mechanism by which this is a defect rather than a style preference.

## Success criteria

- [ ] R-01 — every call site of a manifest helper in the skill uses the PATH-RULE form.
- [ ] R-02 — a derived guard fails when a new bare mention is added, with a count guard on the
      derivation so an empty population cannot read as full coverage.
- [ ] R-03 — the guard is seen RED against a planted bare mention.
