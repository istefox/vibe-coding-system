# SPEC — Per-task diff budget and scope check

Source: GitHub issue #106

## Objectives
1. Give each plan task an optional expected size.
2. Compare the actual diff against it at each Step 5 checkpoint.
3. Name files touched outside every declared task scope.

## Scope
In: an additive budget line in the architect's plan template; a checkpoint comparison in c2c Step 5; report output; a new test file in both CI registries.
Out: blocking on overage; reworking the plan format beyond the additive line.

## Stack
Markdown skill instructions plus bash 3.2 over `git diff --stat`.

## Architecture
- Modified: the architect's plan template (optional `Budget:` line per task: files touched, approximate +/- lines).
- Modified: `concept-to-code/SKILL.md` Step 5 checkpoint.
- Modified: the `step5-report.json` schema — additive `budget_overages`.
- New: test file in both CI registries.

## Data model
`budget_overages: [{task, declared_files, actual_files, declared_lines, actual_lines, out_of_scope_files[]}]`. Additive.

## API / Interfaces
A reporter: it never blocks. The rationale is stated in the issue — a budget that is wrong more often than the coder would be ignored, which is worse than not having one.

## UI flows
Overage surfaces in the orchestrator output and in the report; on unattended paths it reaches the morning report.

## Edge cases
- A plan with no budget lines produces no output and no error (inert).
- A task that legitimately touches many files (a rename sweep) will over-report — acceptable, because it does not block.
- Deleted files count toward files touched.
- The comparison must be per checkpoint batch, not cumulative across the whole chain.

## Success criteria
- [ ] A diff exceeding a declared budget produces a report entry naming the task and the overage.
- [ ] A plan with no budget produces no output and no error.
- [ ] A file touched outside all declared scopes is named.
- [ ] Nothing blocks.
- [ ] The new test file is registered in BOTH CI registries.
