# SPEC — Canonical-mechanism conformance

Source: GitHub issue #117

## Objectives
1. Let a project declare its one true HTTP client, logger, config accessor, DB access layer and error type.
2. Have the reviewer flag a hand-rolled equivalent.

## Scope
In: a `.claude/rules/canonical-mechanisms.md` convention; a first-draft generator in `project-init`; a reviewer checklist item; a new test file in both CI registries.
Out: per-language lint rules enforcing conformance mechanically — a reviewer-level check is the proportionate first step.

## Stack
Markdown rules file with `paths:` frontmatter (the established `.claude/rules/` convention) + bash detection in `project-init`.

## Architecture
- New convention: `.claude/rules/canonical-mechanisms.md`, one line per mechanism, `name → import path or symbol`, with `paths:` frontmatter so it loads only for the relevant stack.
- Modified: `staging/plugin/skills/project-init/SKILL.md` — generate a first draft by detecting the dominant mechanism in existing code (most-imported HTTP client, logger, config module).
- Modified: `staging/plugin/agents/reviewer.md` — add the conformance question to the Consistency checklist, severity MINOR.
- New: test file in both CI registries.

## Data model
One `name → symbol` line per mechanism; `#` comments allowed.

## API / Interfaces
None beyond the file convention. Absent file means the check is inert.

## UI flows
None.

## Edge cases
- A repo with no dominant mechanism (a tie, or a single usage) must produce no draft rather than a wrong one.
- A repo with no canonical-mechanisms file must behave exactly as today.
- The reviewer must not flag the canonical mechanism itself as a violation.

## Success criteria
- [ ] `project-init` on a repo with a dominant HTTP client emits a draft naming it.
- [ ] A repo with no dominant mechanism produces no draft.
- [ ] The reviewer checklist contains the anchor.
- [ ] A repo with no canonical-mechanisms file behaves exactly as today.
- [ ] The new test file is registered in BOTH CI registries.
