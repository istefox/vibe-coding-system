# SPEC — Tracer-bullet probe step

Source: GitHub issue #111

## Objectives
1. Prove a thin end-to-end path before paying for a full implementation step.
2. Make "the agent cannot do this class of work" a first-class, early outcome.
3. Seed the implementation patterns the later slices follow.

## Scope
In: an optional Step 4.5 in c2c; a gate on a `red` outcome; an additive manifest field; a new test file in both CI registries.
Out: automatic slice-selection heuristics beyond "the first task in the plan that crosses all layers".

## Stack
Markdown skill instructions + manifest field.

## Architecture
- Modified: `concept-to-code/SKILL.md` — new Step 4.5 and a new gate, placed between the session boundary and Step 5.
- Modified: manifest schema — additive `tracer_outcome` and the established patterns.
- New: test file in both CI registries.

## Data model
`tracer_outcome: green|amber|red|null`. Additive, nullable.

## API / Interfaces
Outcome semantics: `green` proceed to Step 5 at full scope; `amber` (works but slow or awkward) route back to Gate 2 for scope reduction; `red` halt before Step 5 and offer continue / reduce scope / hand-code, recording the reason.

## UI flows
A new gate fires only on `red`. Skipped by default on `express`, offered on `standard`. In autopilot the default is to run the probe and continue on `amber`.

## Edge cases
- The step must be genuinely optional and absent from `express` runs.
- A `red` outcome must halt before any Step 5 dispatch is paid for.
- A pre-existing manifest without the field must still validate.
- The probe must not commit.

## Success criteria
- [ ] The step is absent from `express` runs.
- [ ] A `red` outcome halts before Step 5 and records why.
- [ ] The manifest field is additive and old manifests still validate.
- [ ] The established patterns are passed into the Step 5 coder brief.
- [ ] The new test file is registered in BOTH CI registries.
