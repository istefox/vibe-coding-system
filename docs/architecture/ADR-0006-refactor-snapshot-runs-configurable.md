# ADR-0006 — `RFS_RUNS=N` configurable determinism check for refactor-snapshot

**Status:** Accepted  
**Date:** 2026-05-20  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:**
- `docs/architecture/ADR-0002-refactor-snapshot-harness.md` (Accepted 2026-05-20, established the 3 hardcoded PRE runs)
- `docs/superpowers/specs/2026-05-20-refactor-snapshot-runs-configurable-design.md`
- `docs/superpowers/plans/2026-05-20-refactor-snapshot-runs-configurable.md`
- `~/.claude/agents/refactorer.md` (Step 3 hardcoded "re-run pre-snapshot 2 more times (3 total)")
- `~/.claude/skills/refactor-snapshot/SKILL.md` (already cites `RFS_DETERMINISM_RUNS` but not implemented)
- `~/.claude/skills/refactor-snapshot/scripts/capture.sh` (single-shot, does not iterate)
- Memory `feedback_bash32-constraint.md`

---

## 1. Context

The refactor-snapshot harness (ADR-0002, deployed 2026-05-20) requires the refactorer
to perform 3 executions of the PRE snapshot (Step 3 of `refactorer.md`: "Re-run pre-snapshot 2
more times (3 total). If SHA256 differs across runs -> STOP"). The number **3** is
hardcoded in the prompt; `capture.sh` knows nothing about the concept of a "run set" — it is
single-shot.

Three converging pieces of evidence motivate the intervention.

1. **Discrepancy already present in the code.** `SKILL.md` cites the env var
   `RFS_DETERMINISM_RUNS` (default 3) as *part of the public contract*, but neither
   `capture.sh` nor `refactorer.md` honors it. It is a declared but unimplemented contract
   — a latent documentation bug.

2. **Slow test suites.** On real projects (pricing-markup-cli has a test-cmd of
   ~90s; the vibe-coding-system blueprint has aggregated harnesses >120s) a PRE with 3
   executions costs 4.5-6 minutes *before* the refactor + 1 POST = 6-8 minutes for
   every *pass* of refactor (<=200 lines), typically 3-5 passes per feature -> 30-40
   minutes of friction. When the test is notoriously deterministic, the user wants to
   lower to `RFS_RUNS=1` (skip determinism, accept the risk).

3. **Flaky tests.** Tests that fail 1/10 times have only
   `1 - (0.9)^3 ~= 27%` chance of being caught at 3 runs. For projects with
   known-flaky suites (integration tests, async I/O) 5-10 runs are needed to reduce
   the false-negative rate to <5%. Hardcoded 3 gives a *false sense of security*.

### Architectural problem

The value "3" is a *policy* (cost/coverage trade-off) hardcoded in a *prompt*
(`refactorer.md`) and ignored by the executable layer (`capture.sh`). Both configurability
and a single source of truth are missing: the number of runs lives in two places
(prompt + SKILL.md cites but does not honor) and is authoritative at runtime in neither.

### Direction

Implement `RFS_RUNS=N` as a *true* env var:

- Read by a **new wrapper script** `pre-runs.sh` (sibling of `capture.sh`, `diff.sh`).
- Default 3, valid range [1, 10], explicit validation (fail loud).
- The refactorer calls the wrapper *once* instead of 3 invocations of `capture.sh PRE`.
- Audit trail: the wrapper output includes `RUNS=N` explicitly; the refactorer report
  cites the effective value used.

Renamed `RFS_DETERMINISM_RUNS` -> `RFS_RUNS` (short, aligned with
`RFS_TIMEOUT`/`RFS_FILTER`/`RFS_FULL`). The var `RFS_DETERMINISM_RUNS` was never honored
by the executable code, so this is a change to SKILL.md but not a runtime breaking change.

---

## 2. Decision

Introduce a new executable script
`~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh` (bash 3.2-clean) with
contract:

```
bash pre-runs.sh
# Reads env: RFS_RUNS (default 3, range [1,10])
# Calls capture.sh PRE N times.
# Compares SHA256 (STDOUT + STDERR + EXIT) of every snapshot vs first.
# Emits to stdout: RUNS=<N>\nSTATUS=<PASS|UNVERIFIED>\n[FIRST_RUN_SHA=...]
# Exit: 0 PASS, 2 UNVERIFIED, 1 invalid RFS_RUNS, 3 capture.sh failure
```

Detailed behavior:

- `RFS_RUNS=N` validated as integer in [1, 10]. Out-of-range or non-numeric ->
  exit 1, stderr `ERROR: RFS_RUNS=<val> invalid, must be integer in [1,10]`.
  **Fail loud, NO silent clamp.**
- `N=1` executes 1 capture, emits `STATUS=PASS` automatically (no determinism
  check possible at N=1, but it is an explicit user choice — audit trail in report
  will say `RUNS=1 (determinism check skipped)`).
- `N>=2` executes N captures; after each capture saves the file in tmp with SHA256
  computed; compares all against the first. If even one differs ->
  `STATUS=UNVERIFIED`, exit 2. All equal -> `STATUS=PASS`, exit 0. The final PRE
  file (`.claude/.refactor-snapshot.txt`) is that of the LAST run (most recent = most
  up-to-date baseline).
- If a single internal `capture.sh` fails (exit!=0, e.g. missing test-cmd,
  timeout) -> propagated as exit 3, stderr includes the run number that failed.

Wording of `refactorer.md` Step 3 changes from:

```
3. Determinism check. Re-run pre-snapshot 2 more times (3 total). If SHA256
   differs across runs -> STOP, output `UNVERIFIED non-deterministic test output`...
```

to:

```
3. PRE capture + determinism check. Invoke
   `bash ~/.claude/skills/refactor-snapshot/scripts/pre-runs.sh`.
   Default 3 runs; override via `RFS_RUNS=<1..10>` env var. Exit 0 = PASS, exit 2
   = UNVERIFIED (non-deterministic across runs). Cite the RUNS=N value from
   stdout in the final report.
```

The previous `capture.sh PRE` invocations (Steps 2 and 3) collapse into
*a single invocation* of `pre-runs.sh`. The refactor lifecycle becomes:

```
pre-runs.sh                         # PRE + determinism (Steps 2+3 merged)
# ... refactor edits ...
capture.sh POST
diff.sh
```

### 2.1 Coexistence with other env vars

`RFS_RUNS` coexists orthogonally with `RFS_TIMEOUT`, `RFS_FILTER`, `RFS_FULL`:

- `RFS_TIMEOUT` is **per-run** (no change — every invocation of `capture.sh`
  inside `pre-runs.sh` respects its own timeout). Worst-case total wallclock
  ~= `N * RFS_TIMEOUT`.
- `RFS_FILTER` / `RFS_FULL` are **per-capture**, identical for all N runs
  (no random selection — all runs use the same scope, otherwise the determinism
  check is impossible).
- Audit trail in the refactorer report: explicitly cites `RUNS=N`,
  `TIMEOUT=...`, `FILTER=...`/`FULL=...` when non-default.

### 2.2 Answers to the 4 architectural questions

1. **Control granularity:** global env var `RFS_RUNS` *session-only*.
   No per-project config file in this iteration (YAGNI: the refactorer
   is invoked in an interactive session, the user knows which project it is working on
   and can prefix `RFS_RUNS=5` to the dispatch). Config file adds
   parsing logic + precedence cases (env > file > default) for zero
   demonstrated benefit.

2. **Validation of N:** **fail loud, no clamp.** `RFS_RUNS=0` and `RFS_RUNS=11`
   are explicit errors (exit 1). Rationale: silent clamp hides bugs in the
   call site; "0 = skip determinism" is an ambiguity (is it skip or is it error?).
   The "skip determinism" case is explicit as `RFS_RUNS=1` (see above).

3. **Step 3 wording + audit trail:** refactorer report cites
   `RUNS=N` literally from wrapper stdout. Default 3 = cites "RUNS=3
   (default)"; override = cites "RUNS=5 (env override)". The file
   `.claude/.refactor-snapshot.txt` does NOT contain the N value (remains byte-for-byte
   compatible with ADR-0002 format: EXIT/SHA/SHA/---/---/). Audit trail lives
   in the refactorer markdown report, not in the snapshot file (separation of
   concerns: snapshot = byte-faithful behavior; report = process metadata).

4. **Cohesion with other flags:** see §2.1. They coexist by design; no
   cross-effect. `RFS_RUNS=10 + RFS_TIMEOUT=120` = worst-case 20 minutes on
   PRE — it is a conscious choice, the user can see it.

---

## 3. Alternatives considered

### Alt-A — Mutate `capture.sh` with internal loop (REJECTED)

Add the loop inside `capture.sh PRE` when `RFS_RUNS>=2`.

**Rejection:**
- Violates single-responsibility: `capture.sh` today captures *one* snapshot.
  Changing it to "1 or N depending on env var" makes it stateful.
- Breaks the declared contract in `SKILL.md` invocation contract (3 explicit calls). Must
  rewrite both SKILL.md and the agent anyway — less isolated than the wrapper.
- The 10 existing self-tests of `capture.sh` would need to be revised one by one;
  isolated wrapper preserves the existing anchor self-test intact.

### Alt-B — Loop in the refactorer prompt, read `RFS_RUNS` as text (REJECTED)

The `refactorer.md` Step 3 prompt says "execute `capture.sh PRE` $RFS_RUNS times,
compare SHA256 by reading the files". The Claude agent interprets the loop.

**Rejection:**
- Non-deterministic: the agent might get the count wrong, forget the comparison, etc.
  Shifting deterministic logic into a probabilistic agent is an anti-pattern (lesson of
  ADR-0002: the added value of the harness is the *determinism* of the check).
- Not testable via bash harness: the loop does not physically exist in an executable file.
  ZERO coverage possible from the self-test.

### Alt-C — Config file `.claude/refactor-snapshot.config` (REJECTED for now)

Per-project override via YAML file with `runs: 5`.

**Rejection:**
- YAGNI: no evidence of demand. Adding YAML parser in bash 3.2 (costly). The env var
  covers 100% of the identified use case (interactive session).
- Precedence rules (file > env > default? env > file? per-cwd or per-user?) introduce
  complexity without demonstrated benefit. Reopenable in a subsequent ADR if the use case
  emerges.

---

## 4. Consequences

### Positive

- Refactor on slow suites becomes practical (`RFS_RUNS=1`).
- Refactor on flaky suites becomes rigorous (`RFS_RUNS=8`).
- SKILL.md is consistent with the code again (single source of truth: `pre-runs.sh`).
- A single invocation (`pre-runs.sh`) replaces 3 (`capture.sh PRE` x3) ->
  simpler refactorer prompt, less scope for interpretive errors.
- Explicit audit trail (`RUNS=N` in the refactorer report).

### Negative

- New executable file to maintain (`pre-runs.sh`). +1 test surface
  (target: +6 PASS to the refactor-snapshot self-test, 11 -> 17).
- Refactorer.md changes -> another Edit to the critical prompt (but minimal: 2 lines).

### Neutral

- `RFS_DETERMINISM_RUNS` (cited in SKILL.md but never honored) is renamed
  to `RFS_RUNS`. Not a runtime breaking change (the old var did nothing);
  it is a documentation change.
- The final `.claude/.refactor-snapshot.txt` file is that of the last run
  (not the first). Equivalent when determinism PASS; more informative
  when UNVERIFIED (last observed state).

---

## 5. References

- `~/.claude/skills/refactor-snapshot/scripts/capture.sh` (single-shot, not to
  be modified)
- `~/.claude/skills/refactor-snapshot/scripts/diff.sh` (orthogonal)
- `~/.claude/skills/refactor-snapshot/tests/run-tests.sh` (anchor; tests added,
  no existing tests touched)
- ADR-0002 §2 (3 PRE runs hardcoded — soft-superseded by the default 3 of
  `RFS_RUNS`)
