# SPEC — hook-verify-workflow: filter the audit window by session

Source: GitHub issue #33

## Objectives
1. Stop `hook-verify-workflow.sh --check` from reporting VERIFIED on evidence produced by other concurrent sessions (audit finding 3.2) — the exact false-positive risk ADR-0016 treats as a hard blocker.

## Scope
In (`staging/plugin/scripts/hook-verify-workflow.sh`, already versioned; byte-identical deployed copy at `~/.claude/skills/concept-to-code/scripts/`):
- Line 96 builds the AFTER window as `awk -F'\t' -v m="$MARK" '$1 > m' "$LOG"` with no filter on field 2 (session_id). The audit log `~/.claude/state/pattern-enforce/audit.log` is machine-global (4916 rows across 88 session IDs at audit time), so a coder dispatched by ANY concurrent session after the marker makes `--check` count ENFORCED > 0 and record `hook_verified=true` without evidence that hooks propagate into workflow subagents.
- When `CLAUDE_SESSION_ID` is available, filter the AFTER window on field 2 equal to it.
- When it is not available and rows from more than one session id appear after the marker, print `status=INCONCLUSIVE` and exit 3 instead of VERIFIED.
- Keep the exit-code contract documented in the header comment in sync.

Out:
- Any file under `~/.claude` (the deployed copy is updated at the next human sync).
- Changes to the audit-log format or to pattern-enforce itself.

## Stack
Bash 3.2-compatible, BSD-awk-safe shell; test harness `staging/plugin/scripts/tests/hook-verify-workflow.test.sh` run by docs-ci.

## Architecture
Single script plus its test file under `staging/plugin/scripts/`.

## Data model
Audit log rows: tab-separated, field 1 = timestamp/marker ordering key, field 2 = session_id.

## API / Interfaces
Exit-code contract: existing codes preserved; exit 3 = INCONCLUSIVE added (or kept in sync with the documented contract in the header).

## UI flows
None.

## Edge cases
- Same-session rows only: VERIFIED.
- Foreign-session rows only, `CLAUDE_SESSION_ID` set: NOT VERIFIED.
- Foreign-session rows only, no session id available: INCONCLUSIVE, exit 3.
- Mixed rows: count only the matching session.

## Success criteria
- [x] `staging/plugin/scripts/tests/hook-verify-workflow.test.sh` gains cases: same-session rows verify; foreign-session rows alone yield INCONCLUSIVE (no session id) or NOT VERIFIED (session id set); mixed rows count only the matching session
- [x] Existing test cases still pass
- [x] Script stays bash 3.2 clean and BSD awk safe
- [x] No file under `~/.claude` modified
