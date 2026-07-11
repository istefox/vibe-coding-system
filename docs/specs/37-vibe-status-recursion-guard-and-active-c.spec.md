# SPEC — vibe-status: recursion guard and active-chains wiring

Source: GitHub issue #37

## Objectives
1. Stop vibe-status test 10 from recursing through the real HOME and orphaning process generations (audit finding 2.9, P2).
2. Fix the `grep -c || echo 0` two-line-value bug in the Memory section (finding 3.13).
3. Land the ADR-0021 Active-chains wiring (staged 2026-06-22, never deployed) into the now-vendored aggregate.sh (finding 2.27, reverse drift).

## Scope
In (under `staging/plugin/skills/vibe-status/`, vendored by issue #28, except INTEGRATION.md which already exists in staging):
- `tests/run-tests.sh:117`: test 10 runs the full aggregate against the real HOME; aggregate.sh (line 36) rediscovers vibe-status's own harness → unbounded recursion; nested timeout invocations move into fresh process groups and survive the parent kill (orphans observed live). The TMP_AGG_HOME fixture built at lines 109–115 is never used. Fix: add a recursion guard (environment variable set by test 10 and honored by aggregate.sh harness discovery), or point test 10 at the already-built TMP_AGG_HOME. Kill the process group on timeout in harness-runner.sh.
- `scripts/aggregate.sh:180`: `grep -c ... || echo 0` produces `0\n0` when MEMORY.md has no index entries, breaking the Memory section rendering. Fix the count guard.
- `staging/plugin/skills/vibe-status/INTEGRATION.md`: execute its wiring (chain-memory-section.sh plus wiring into aggregate.sh and SKILL.md) against the vendored copies, and add chain-memory-section.sh to sync PAIRS, so the deployed side gains the Active-chains section at the next human sync.

Out:
- Any file under `~/.claude` (deployment happens at the next human sync).
- Deploying the wiring (sync is a separate human step).

## Stack
Bash 3.2-compatible shell; test harness in docs-ci; Markdown SKILL.md.

## Architecture
`tests/run-tests.sh` (test 10), `scripts/aggregate.sh` (harness discovery guard, Memory count, Active-chains section), `harness-runner.sh` (process-group kill), `chain-memory-section.sh` (new in PAIRS), `staging/sync-to-claude.sh` PAIRS.

## Data model
None.

## API / Interfaces
aggregate.sh gains an environment-variable recursion guard honored by harness discovery; report gains the Active-chains section per INTEGRATION.md.

## UI flows
None (report text: a MEMORY.md with no index entries renders `0 entries indexed` on one line).

## Edge cases
- Harness run from within an aggregate run (recursion): guarded, no re-entry.
- Timeout during harness run: whole process group killed, no orphaned aggregate/timeout processes.
- MEMORY.md with zero index entries: single-line `0 entries indexed`.

## Success criteria
- [x] Running the vibe-status harness leaves zero orphaned aggregate or timeout processes (assert with a ps check in the test)
- [x] A MEMORY.md with no index entries renders `0 entries indexed` on one line
- [x] aggregate.sh contains the Active-chains wiring and PAIRS covers chain-memory-section.sh
- [x] No file under `~/.claude` modified
