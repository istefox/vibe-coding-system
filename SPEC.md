# SPEC — Requirement IDs in SPEC and a coverage check

Source: GitHub issue #102

## Objectives
1. Give every generated SPEC stable, enumerated requirement identifiers.
2. Make the plan cite the identifiers each task satisfies.
3. Assert mechanically that no requirement was silently dropped between SPEC, plan and tests.

## Scope
In: `R-01 … R-nn` IDs in the success-criteria section of both SPEC generators; plan tasks citing IDs; a new `spec-coverage.sh`; a call at the c2c Step 5 exit; a new test file in both CI registries.
Out: retrofitting IDs into the existing specs under `docs/specs/`.

## Stack
Bash 3.2 for the checker; Markdown skill instructions for the generators.

## Architecture
- Modified: `staging/plugin/skills/interview-driver/SKILL.md` (`:13` currently names the SPEC sections with no identifiers).
- Modified: `staging/plugin/skills/spec-from-issue/SKILL.md`, whose template must emit IDs in Success criteria.
- Modified: the architect's plan template so each task cites its IDs.
- New: `staging/plugin/skills/concept-to-code/scripts/spec-coverage.sh`.
- Modified: `concept-to-code/SKILL.md` Step 5 exit.
- New: test file in both CI registries.

## Data model
A requirement ID is `R-NN` (zero-padded, two digits, unique within one SPEC), appearing at the start of a success-criteria checklist item.

## API / Interfaces
`spec-coverage.sh --spec <file> --plan <file> [--tests-root <dir>]`
- exit 0: every ID is covered, or the SPEC declares no IDs (backward compatibility).
- exit non-zero: prints each uncovered ID and where the coverage was missing (plan or tests).

## UI flows
None. The check runs at the Step 5 exit and its output goes to the orchestrator and the report.

## Edge cases
- A SPEC with no `R-` IDs passes silently — this is the backward-compatibility path and must be tested explicitly.
- Duplicate IDs in one SPEC are an error, not a silent overwrite.
- An ID cited by a plan task that does not exist in the SPEC is an error.
- Test coverage matching is by name or docstring mention, so a test file that does not mention any ID must not fail a SPEC that has none.

## Success criteria
- [ ] A SPEC with `R-01`,`R-02` and a plan covering only `R-01` fails and names `R-02`.
- [ ] A SPEC with no `R-` IDs passes silently.
- [ ] Both generators emit IDs in their Success criteria section.
- [ ] A duplicate ID is reported as an error.
- [ ] The check is called at the c2c Step 5 exit.
- [ ] The new test file is registered in BOTH CI registries.
