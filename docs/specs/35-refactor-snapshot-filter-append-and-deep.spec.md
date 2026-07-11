# SPEC — refactor-snapshot filter append and deep-refactor scope glob

Source: GitHub issue #35

## Objectives
1. Make refactor-snapshot's RFS_FILTER actually apply to the test command instead of running as a separate failing command (audit finding 2.6, P2).
2. Make deep-refactor's documented glob path-override work (finding 3.8).
3. Stop the circuit-breaker text from recommending a command that destroys pre-existing user edits on a dirty tree (finding 3.9).

## Scope
In (under `staging/plugin/skills/`, vendored by issue #28):
- `refactor-snapshot/scripts/capture.sh:56`: the read loop (lines 33–41) leaves a trailing newline on CMD_CONTENT, so `EXEC_CMD="$CMD_CONTENT $RFS_FILTER"` puts the filter on a new line and `bash -c` runs it as a separate failing command (reproduced: suite runs unfiltered, EXIT 127 in both PRE and POST, diff.sh exit-code channel always matches even when the refactor turned the suite red). Strip the trailing newline before appending (bash 3.2 safe), keeping all three timeout branches on the same EXEC_CMD.
- `deep-refactor/scripts/enumerate-sources.sh:49`: the glob path-override is interpolated raw into `grep -E` (reproduced: override `*.swift` returns zero files and Step 0.6 aborts with no-source-files; the fallback at line 53 reuses the broken pattern). Escape the override for ERE and match as a literal prefix, or implement real glob support with case matching; update the usage text to match what is actually supported.
- `deep-refactor/SKILL.md:585`: circuit-breaker text suggests `git checkout -- .`, which on a dirty-tree run (explicitly allowed by Gate 0, lines 187–191) also destroys the user's pre-existing uncommitted edits. When DIRTY_TREE is true, replace with a selective-revert note or a stash suggestion.

Out:
- Any file under `~/.claude`.
- Other deep-refactor pipeline behavior.

## Stack
Bash 3.2-compatible, BSD-safe scripts; Markdown SKILL.md; harness tests in docs-ci.

## Architecture
`refactor-snapshot/scripts/capture.sh`, `deep-refactor/scripts/enumerate-sources.sh`, `deep-refactor/SKILL.md` Gate 2 text.

## Data model
None.

## API / Interfaces
capture.sh contract: snapshot EXIT equals the real (filtered) suite exit. enumerate-sources contract: override patterns behave as the usage text documents.

## UI flows
None.

## Edge cases
- RFS_FILTER set: filter must land on the same command line as the test command, in all three timeout branches.
- Override `*.swift` on a fixture with swift files: must return them, in both the primary path and the line-53 fallback.
- Circuit breaker firing on a run started with a dirty tree: no advice that reverts user edits wholesale.

## Success criteria
- [x] Harness test: with RFS_FILTER set, the snapshot EXIT equals the real suite exit and stdout shows the filter took effect on the same command line
- [x] Harness test: enumerate-sources with override `*.swift` returns the fixture's swift files
- [x] Gate 2 text no longer recommends a command that deletes pre-existing user edits on a dirty tree
- [x] No file under `~/.claude` modified
