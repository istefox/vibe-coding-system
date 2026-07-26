# SPEC — SAST job and a security-audit skill

Source: GitHub issue #110

## Objectives
1. Run a real static analyser somewhere in the system, instead of relying only on LLM judgement.
2. Provide the ten-step security audit protocol as an on-demand skill.
3. Keep every security finding report-only.

## Scope
In: an opt-in `security-audit` CI job in the project template; a new `security-audit` skill implementing the ten-step protocol; a new test file in both CI registries.
Out: DAST; a commercial scanner; auto-fixing any security finding.

## Stack
GitHub Actions + Semgrep default rules for the CI job; Markdown skill instructions for the protocol.

## Architecture
- Modified: `staging/project-templates/ci/ci.yml` — opt-in job, absent by default in generated repos.
- New: `staging/plugin/skills/security-audit/SKILL.md`.
- New: test file in both CI registries asserting the skill's structural anchors and the template job.

## Data model
Findings are report-only. High-risk findings are tagged `ACTION REQUIRED — not auto-fixed`.

## API / Interfaces
The skill's ten steps, in the source order: automated scanners; separate-AI review; human checklist; penetration testing and fuzzing; security-focused unit tests; training-cutoff compensation (name the current OWASP Top 10 by year); logging hygiene; updated tooling; warnings in context; slow down.

## UI flows
On-demand invocation; output is a findings report, never a clearance. The skill must state explicitly that AI review is one input to a security assessment and never security clearance.

## Edge cases
- Semgrep absent must degrade gracefully, not fail the run.
- The report-only invariant from ADR-0018 must hold regardless of risk level.
- The opt-in job must be genuinely absent by default.

## Success criteria
- [ ] The skill's ten steps are present as named, testable anchors.
- [ ] The report-only invariant is asserted by a test.
- [ ] The CI job is opt-in and absent by default in generated repos.
- [ ] The skill states that AI review is never clearance.
- [ ] The new test file is registered in BOTH CI registries.
