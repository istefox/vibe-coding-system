# SPEC — Generator/verifier separation: dispatch the tester, deny coder test writes

Source: GitHub issue #103

Depends on issue #102: the tester is briefed from the SPEC's requirement IDs, so those must exist first.

## Objectives
1. Have a different agent write the tests than the one that writes the implementation.
2. Brief that agent from the specification, never from the implementation.
3. Enforce the separation mechanically, not by prompt.

## Scope
In: a `tester` dispatch per task group in c2c Step 5 on BOTH dispatch paths; a `PreToolUse` hook denying `coder` writes under test paths; an additive `tests_written_by` field in `step5-report.json`; a new test file in both CI registries.
Out: changing `refactorer` or `debugger` behaviour; retrofitting chains already completed.

## Stack
Markdown skill instructions plus a bash 3.2 `PreToolUse` hook, modelled on `write-scope-enforce.sh`, which already resolves the calling subagent's transcript via `.agent_id` and reads a scope marker from the dispatch prompt.

## Architecture
- Modified: `concept-to-code/SKILL.md` Step 5 — the Workflow path and the Agent-tool batch fallback each gain a tester stage stated independently, so behaviour does not depend on whether `hook_verified` flipped.
- New: `staging/plugin/scripts/tester-scope-enforce.sh` (name TBD by the architect) — `PreToolUse` on `Edit|Write|MultiEdit`, denies `agent_type: coder` a write whose path matches a test directory or test-file pattern.
- Modified: the `step5-report.json` schema block.
- Unchanged: `staging/plugin/agents/tester.md` — the agent already exists and is correctly specified; only the dispatch graph is wrong.

## Data model
`step5-report.json` gains `tests_written_by: "tester" | "coder" | "none"` per task. Additive.

## API / Interfaces
The hook follows the established contract: reads the hook payload JSON on stdin, emits a deny decision with a reason, exits 0 always, allows on every failure mode, and is inert when no test-scope marker is present in the dispatch.

## UI flows
None. A denied write returns a reason to the coder naming the tester as the owner of test files.

## Edge cases
- The hook must be inert outside Step 5 — an orchestrator turn or another skill writing a test file must not be blocked.
- A `tester` writing a test file must be allowed.
- A `coder` writing a non-test file must be allowed.
- A test-path pattern must cover the conventions already used here: `tests/`, `*_test.*`, `*.test.*`, `*.spec.*`, `test_*`, `*Tests.*`.
- Pin `model` and `effort` explicitly on the tester dispatch (`sonnet` / `medium`), per the existing Step 5 rule that an omitted value inherits the session rather than the frontmatter.

## Success criteria
- [ ] A Step 5 run dispatches tester before coder per task group, on both dispatch paths.
- [ ] A simulated `coder` Edit to a test path is denied with a reason naming the tester.
- [ ] A simulated `tester` Edit to the same path is allowed.
- [ ] A `coder` Edit to a source path is allowed.
- [ ] The hook is inert when the dispatch carries no test-scope marker.
- [ ] `tests_written_by` appears per task and a report lacking it is still read.
- [ ] The new test file is registered in BOTH CI registries.
