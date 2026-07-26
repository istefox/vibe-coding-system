# SPEC — Wire the anti-test-weakening detector into every unattended path

Source: GitHub issue #101

## Objectives
1. Make the existing anti-test-weakening detector run on every path that can produce a commit, not only inside the human-invoked review cycle.
2. Make a weakening finding **blocking** on unattended paths rather than a silent note.
3. Record findings in the machine-readable reports the orchestrator already reads.

## Scope
In: new call sites for `weakening-scan.sh` in `concept-to-code` Step 5, `autopilot-build`, `nightly-autopilot`, and `commit` Step 1; an additive `weakening_findings` array in `step5-report.json`; a new test file in both CI registries.
Out: changing the detector's heuristics — new detectors are a separate feature (issue #105). `review-triage-fix` behaviour and its existing harness must not change.

## Stack
Bash 3.2 + Markdown skill instructions. `weakening-scan.sh` already exists at `staging/plugin/skills/review-triage-fix/scripts/weakening-scan.sh` and takes a unified diff on stdin, emitting `CLEAN` or `WEAKENED<TAB><file><TAB><reason>`.

## Architecture
- Unchanged: `weakening-scan.sh` itself.
- Modified: `concept-to-code/SKILL.md` Step 5 — run the scan over the cumulative diff before the transition to `step_6_review`.
- Modified: `autopilot-build/SKILL.md` and `nightly-autopilot/SKILL.md` — run it at each checkpoint / per-feature loop.
- Modified: `commit/SKILL.md` Step 1 — run it over the computed file scope, beside the secrets check.
- Modified: the `step5-report.json` schema block in `concept-to-code/SKILL.md`.
- New: a test file registered in both CI registries.

## Data model
`step5-report.json` gains `weakening_findings: [{file, reason}]`. Additive: absent means none, and every report written before this change stays valid.

## API / Interfaces
The scan is invoked as today: a unified diff on stdin, `CLEAN` or `WEAKENED` lines on stdout, exit 0 always. The **caller** supplies the blocking semantics.

## UI flows
On an unattended path a `WEAKENED` line refuses the step transition and surfaces in the morning report. On the `commit` path it renders in the Step 4 approval gate.

## Edge cases
- A diff with no test files must produce `CLEAN` and cost nothing.
- A legitimate test deletion (a removed feature) is still reported — it surfaces for a human, it is not auto-resolved.
- `review-triage-fix` already calls the scan; it must not be called twice in one cycle.
- A non-git or empty diff must not error.

## Success criteria
- [ ] A diff deleting a test file blocks the c2c Step 5 → Step 6 transition.
- [ ] A diff adding `@pytest.mark.skip` blocks.
- [ ] A clean diff advances exactly as today.
- [ ] `weakening_findings` appears in `step5-report.json` and a report lacking it is still read without error.
- [ ] The existing `review-triage-fix` harness stays green and that skill is unmodified.
- [ ] The new test file is registered in BOTH CI registries.
