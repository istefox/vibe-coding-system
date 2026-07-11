---
name: refactor-snapshot
description: Behavior-preservation snapshot harness for the refactorer agent. Captures stdout/stderr/exit-code of project test command pre-refactor, re-runs post-refactor, diffs SHA256. Fails loud on non-zero diff. Stack-agnostic via .claude/test-cmd contract.
---

# Refactor snapshot harness

Captures observable behavior of the project test suite (stdout + stderr + exit-code)
before a refactor, re-runs after the refactor, and diffs SHA256. Non-zero diff means
the refactor changed observable behavior and must be reconsidered.

## When to invoke

Exclusively from the `refactorer` sub-agent during its Process. Not auto-invoked, not
chained from other agents or skills. The `refactorer.md` system prompt step-2-3 / step-4
/ step-5 are the only callers.

## Invocation contract

The refactorer invokes three commands in sequence per refactor cycle:

    bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh       # PRE + determinism
    # ... refactor edits ...
    bash ~/.claude/skills/refactor-snapshot/scripts/capture.sh POST   # after edit
    bash ~/.claude/skills/refactor-snapshot/scripts/diff.sh           # gate

`pre-runs.sh` runs `capture.sh PRE` N times (RFS_RUNS, default 3) and verifies
SHA256 identity across runs. STATUS=UNVERIFIED if not deterministic.

## Outputs

- `$PWD/.claude/.refactor-snapshot.txt` — PRE snapshot (kept across cycles as
  baseline).
- `$PWD/.claude/.refactor-snapshot.txt.post` — POST snapshot (cleaned on PASS, kept on
  FAIL for inspection).

File format (both):

    EXIT=<integer>
    STDOUT-SHA256=<64 hex>
    STDERR-SHA256=<64 hex>
    ---STDOUT---
    <full stdout, byte-faithful>
    ---STDERR---
    <full stderr, byte-faithful>

Exit codes (`diff.sh`): 0 = PASS, 1 = FAIL, 2 = UNVERIFIED.

## Stack-agnostic

Reads `$PWD/.claude/test-cmd` (TOFU + 3-tier contract, deploy 2026-05-19 swarm-testcmd).
No language parsing. Project target declares its own test command (`pytest`, `npm
test`, `swift test`, etc).

If `.claude/test-cmd` is missing, `capture.sh` returns exit 1 → refactorer reports
UNVERIFIED and aborts the cycle.

## Override

Optional file `$PWD/.claude/refactor-snapshot-override`, user-created (HITL gate; the
refactorer NEVER creates this):

    REASON: <one-line justification>
    SCOPE: <stdout|stderr|exit|all>
    EXPIRES: <YYYY-MM-DD>

If present and valid, `diff.sh` ignores divergence in the declared SCOPE channels and
outputs `OVERRIDE=yes:<REASON>`. Audit trail: refactorer cites the file path + reason
in its final report.

## Failure modes

| State | Meaning | Refactorer action |
|---|---|---|
| `PASS` | All SHA256 + EXIT identical, or all diverging channels covered by override | Report success |
| `FAIL` | At least one diverging channel not covered by override | STOP, report drift (HITL) |
| `UNVERIFIED` | PRE non-deterministic (3 runs differ), or PRE/POST malformed, or test-cmd missing | STOP, report flakiness or precondition failure |

## Env vars

- `RFS_RUNS` (default 3, range [1,10]) — number of PRE runs for determinism check.
  Set `RFS_RUNS=1` to skip determinism check (single capture).
- `RFS_TIMEOUT` (default 120) — per-run test-cmd timeout in seconds.
- `RFS_FILTER` (default empty) — pattern passed to test-cmd (e.g. `pytest -k <pat>`).
- `RFS_FULL` (default 0) — when 1, ignore RFS_FILTER and use full test scope.

## Constraints

- Bash 3.2.57 portable (no assoc array, no `mapfile`, no `${v^^}`, no `<()`).
- SHA256 via `shasum -a 256` (BSD/macOS) with `sha256sum` fallback (Linux).
- Self-test: `bash tests/run-tests.sh` — target PASS=18 FAIL=0.
