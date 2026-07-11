# SPEC — concept-to-code: BSD-safe slug stamp and autopilot gate fixes

Source: GitHub issue #31

## Objectives
1. Make the Step-1 slug stamp BSD-safe so greenfield runs no longer error on macOS (audit finding 1.1, P1).
2. Close two autopilot policy violations: unattended `approve-test-cmd.sh` (Gate 2b) and unattended push (Gate 0d + Step 7), both forbidden by ADR-0014/ADR-0020 (findings 2.2, 2.3).
3. Define one canonical Gate 0 ordering and make express/hybrid manifests validate (findings 2.4, and the invariant-7 defect).

## Scope
In (`staging/plugin/skills/concept-to-code/SKILL.md`, vendored by issue #28; line numbers from the deployed copy of 2026-07-10):
- Line 273: `sed -i.bak '/^# /a\n**Topic slug:** ...'` is GNU-only; BSD sed exits 1, the Topic-slug marker is never written, gate0-detect.sh spec_topic_match stays unknown. Replace with a BSD-safe form (awk to temp file plus mv, or printf-based) working on macOS bash 3.2 and ubuntu CI.
- Line 1501: Gate 2b autopilot must never call approve-test-cmd.sh unattended. Require pre-existing trust; otherwise leave the NONE placeholder and record the halt reason.
- Lines 1187 + 819–846: Gate 0d autopilot must always set `initial_commit_push: "commit"`; guard the Step-7 push block on autopilot false (or the ADR-0022 nightly opt-in).
- Line 1185 + section 2 Form A: define one canonical Gate order (Gate 0 choice only, then 0b, 0c, 0d, then a single routing transition); align the click handlers and manifest-transition.sh pairs (today the documented `step_0_init` transition is illegal or Gates 0c/0d are unreachable; Form A never mentions 0c/0d).
- Line 945: express and hybrid paths end `status: completed` with null spec/adr/plan artifacts, violating manifest-validate.sh invariant 7. Make invariant 7 conditional on chain_path; record Gate E3 Abort as `aborted`, not completed.

Out:
- Any file under `~/.claude`.
- Manifest helper defects beyond invariant 7 (issue #32).

## Stack
Markdown SKILL.md + bash 3.2 / BSD-safe scripts (`manifest-validate.sh`, `manifest-transition.sh`); harness tests in docs-ci.

## Architecture
`staging/plugin/skills/concept-to-code/SKILL.md` (slug stamp, Gate 2b, Gate 0d, Form A, Step 7 push block) and `staging/plugin/skills/concept-to-code/scripts/{manifest-validate.sh,manifest-transition.sh}`.

## Data model
Manifest YAML: `initial_commit_push` field semantics (autopilot always "commit"); `status: aborted` for Gate E3 Abort; invariant 7 conditional on `chain_path`.

## API / Interfaces
manifest-transition.sh legal-pair table must match the SKILL section 3 text exactly.

## UI flows
Form A (interactive Gate 0 flow): one canonical order — Gate 0 choice, 0b, 0c, 0d, single routing transition.

## Edge cases
- Greenfield run on macOS (BSD sed): slug stamp must exit 0 and write the marker.
- Autopilot with no pre-existing TOFU trust: halt with recorded reason, NONE placeholder kept, no unattended approval.
- Autopilot with a remote configured: still no push unless ADR-0022 nightly opt-in.
- Express fixture manifest, status completed, null adr/plan: must pass validation; a standard-path manifest with null artifacts must still fail.

## Success criteria
- [ ] The slug-stamp command exits 0 and writes the marker on BSD sed (add a harness test that runs the exact command against a fixture SPEC.md)
- [ ] No code path in autopilot mode invokes approve-test-cmd.sh or `git push` (grep-level assertion in a harness test)
- [ ] An express fixture manifest with status completed and null adr/plan passes manifest-validate.sh; a standard one with null artifacts still fails
- [ ] Transition-pair count in the SKILL section 3 text matches the script exactly
- [ ] No file under `~/.claude` modified
