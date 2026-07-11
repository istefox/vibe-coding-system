# CLAUDE.md

## Project

{{PROJECT_NAME}} - {{ONE_LINE_DESCRIPTION}}

See PROJECT_BRIEF.md for full context on what to build and why.

## Stack

- Language/runtime: {{STACK}}
- Project type: {{PROJECT_TYPE}}
- Tooling: {{TOOLING}} <!-- e.g. ruff + pytest, eslint + prettier + vitest -->

## Architecture

{{ARCHITECTURE_SUMMARY}}
<!-- If an ADR exists: see docs/adr/0001-initial-architecture.md -->

## Git conventions

- Workflow: {{WORKFLOW}} <!-- GitHub Flow / trunk-based / Git Flow -->
- Commits: {{COMMIT_CONVENTION}} <!-- Conventional Commits v1.0.0: tipo(scope): descrizione -->
- Branches: {{BRANCH_CONVENTION}} <!-- Conventional Branch: feature/, fix/, chore/... -->
- Default branch: main. Never force-push.

## Commands

```bash
{{INSTALL_COMMAND}}
{{TEST_COMMAND}}
{{LINT_COMMAND}}
```

## Working agreements

- Run lint and tests before committing.
- Keep commits small and atomic, one logical change each.
- Update PROJECT_BRIEF.md "Status" section when a milestone is reached.
{{EXTRA_AGREEMENTS}}
