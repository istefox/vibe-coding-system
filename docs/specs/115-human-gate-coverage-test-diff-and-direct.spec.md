# SPEC — Human-gate coverage: test diff and direction check

Source: GitHub issue #115

## Objectives
1. Put the test diff in front of the human before a commit (gate H4).
2. Add a periodic direction check to long chains (gate H16).

## Scope
In: a distinct test-diff section in the `commit` Step 4 gate; a direction-check emission at the c2c Step 5 mid-point for chains above a task threshold; a new test file in both CI registries.
Out: gates H18 and H19 — operator judgement with no artifact to gate on.

## Stack
Markdown skill instructions.

## Architecture
- Modified: `commit/SKILL.md` Step 4 — the gate currently shows message, included files and excluded untracked (`commit/SKILL.md:174-207`); add a separate test-diff section when the change set touches test files.
- Modified: `concept-to-code/SKILL.md` Step 5 — direction check at the mid-point above a task threshold.
- Modified: the `step5-report.json` schema — additive record of the direction check.
- New: test file in both CI registries.

## Data model
`direction_check: {asked: bool, at_task: N}` in `step5-report.json`. Additive.

## API / Interfaces
In autopilot the direction check is a recorded line, not a blocking question, so the morning report shows it was asked without stalling the run.

## UI flows
The commit gate gains one section. It must not become a second blocking gate.

## Edge cases
- A change set touching no tests renders the gate exactly as today — the regression to protect.
- A very large test diff must be truncated the same way the file list already is.
- A short chain must not emit a direction check.
- The existing commit invariant guardrails must not change.

## Success criteria
- [ ] A change set touching tests renders a distinct test-diff section.
- [ ] A change set touching no tests renders the gate exactly as today.
- [ ] The direction check appears in `step5-report.json` for a long chain and is absent for a short one.
- [ ] No new blocking gate is added to an unattended path.
- [ ] The new test file is registered in BOTH CI registries.
