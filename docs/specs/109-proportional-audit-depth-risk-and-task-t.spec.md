# SPEC — Proportional audit depth: risk and task_type axes

Source: GitHub issue #109

## Objectives
1. Make audit depth a function of risk and task type, not only of change size.
2. Default to the strictest profile when unset.
3. Fold Grove's five delegation factors into the same fields so two scoring schemes cannot drift.

## Scope
In: additive `risk` and `task_type` manifest fields; Gate 2 sets them; Step 5 and Step 6 select depth from `max()` of the axes; a conditional validator invariant; a new test file in both CI registries.
Out: a full gate matrix per quadrant; per-file risk tagging.

## Stack
YAML manifest fields + bash 3.2 validation + Markdown skill instructions.

## Architecture
- Modified: `manifest-init.sh` (additive fields), `manifest-validate.sh` (conditional invariant).
- Modified: `concept-to-code/SKILL.md` Gate 2, Step 5, Step 6.
- Must be reconciled with ADR-0017, which owns chain routing: this extends that decision, it does not replace it.
- New: test file in both CI registries.

## Data model
- `risk: low|high` (default: high when unset, per the spec's instruction to default strict).
- `task_type: boilerplate|glue|novel-algorithm|regulated|legacy-integration|perf-critical`.

## API / Interfaces
Effective profile = strictest of (size axis from `chain_path`, risk, task_type). The strict profile forces the Step 6 review cycle and disables review shortcuts.

## UI flows
Gate 2 shows the architect's proposal and the human confirms; in autopilot the strict default stands with no prompt.

## Edge cases
- A manifest without the fields must behave exactly as today and must validate.
- An out-of-enum value must fail validation with a named reason.
- `risk: high` must force the Step 6 cycle even when Gate 5 would have offered to skip it.
- The default-strict rule must not silently make every existing chain stricter — it applies to the new fields only when they are present or when the chain opts in.

## Success criteria
- [ ] A manifest without the fields behaves as today and validates.
- [ ] `risk: high` forces the Step 6 review cycle.
- [ ] An out-of-enum value fails validation with a named reason.
- [ ] The ADR reconciles this with ADR-0017.
- [ ] The new test file is registered in BOTH CI registries.
