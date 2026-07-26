# SPEC — Agent-level instrumentation metrics

Source: GitHub issue #118

## Objectives
1. Record the cheap control metrics the system currently cannot see.
2. Surface them where the operator already looks.
3. Avoid building a productivity dashboard.

## Scope
In: four metrics per task in `step5-report.json` and `nightly-report.json`; a `vibe-status` section; a new test file in both CI registries.
Out: per-subagent token cost, which is not locally observable (`usage-report.py:11-14`); any ROI or productivity claim.

## Stack
Markdown skill instructions + the existing JSON report writers + `vibe-status`.

## Architecture
- Modified: `concept-to-code/SKILL.md` Step 5 — emit the metrics.
- Modified: `nightly-autopilot/SKILL.md` — carry them into the morning report.
- Modified: `staging/plugin/skills/vibe-status/SKILL.md` — render them for the most recent chain.
- New: test file in both CI registries.

## Data model
Per task: `test_count_delta`, `deleted_lines`, `iteration_count`, `elapsed_seconds`. All additive; absent means "not recorded".

## API / Interfaces
JSON fields only.

## UI flows
`vibe-status` renders a metrics section when present and omits it entirely when absent.

## Edge cases
- A report missing the fields must still be read without error — the backward-compatibility path.
- A chain with no tests has a `test_count_delta` of 0, not null.
- The ADR must state that the spec declares productivity measurement an open gap and that this instruments for control, not for proving ROI.

## Success criteria
- [ ] A completed Step 5 writes the four fields.
- [ ] A report missing them is still read without error.
- [ ] `vibe-status` renders them when present and omits the section when absent.
- [ ] No ROI or productivity claim is made anywhere in the output.
- [ ] The new test file is registered in BOTH CI registries.
