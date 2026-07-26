# SPEC — Licence and provenance scanning

Source: GitHub issue #119

## Objectives
1. Give publishing repos a licence-contamination check.
2. Add the suspicious-output procedure to the publication audit.
3. Preserve attribution rather than stripping it.

## Scope
In: an opt-in licence-scan CI job; new checklist steps in the `clean-public-repo` audit phase; a new test file in both CI registries.
Out: buying or integrating a commercial licence scanner; legal advice.

## Stack
GitHub Actions + Markdown skill instructions.

## Architecture
- Modified: `staging/project-templates/ci/ci.yml` — opt-in licence-scan job, absent by default.
- Modified: `staging/plugin/skills/clean-public-repo/SKILL.md` audit phase — the suspicious-output procedure: distinctive comments, author names, unusually large or unusually clean blocks; search a unique string before keeping it.
- New: test file in both CI registries.

## Data model
None.

## API / Interfaces
Report-only. The existing never-falsify-authorship invariant is preserved and must be asserted by a test: if generated output carries an author name or a known-algorithm reference, it is moved to a proper attribution section, never deleted.

## UI flows
Findings appear in the `clean-public-repo` audit report.

## Edge cases
- The CI job must be absent by default in generated repos.
- The audit must not regress the anonymisation behaviour already specified in ADR-0011 and ADR-0026.
- Attribution preservation and tool-trace removal must not conflict: removing a "generated with" trailer is not the same as removing an upstream author credit.

## Success criteria
- [ ] The CI job is absent by default and present when opted in.
- [ ] The `clean-public-repo` audit checklist contains the new anchors.
- [ ] The never-falsify-authorship invariant is asserted by a test.
- [ ] Existing anonymisation behaviour is unchanged.
- [ ] The new test file is registered in BOTH CI registries.
