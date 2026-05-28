# ADR-0007 — End-to-end smoke test for the concept-to-code chain

**Status:** Accepted — 2026-05-20 (implemented; concept-to-code harness PASS=12->13, +1 composite anchor; smoke-e2e.sh 3.78s wall; mutation test detection confirmed)
**Authors:** Adriano (architect agent) per Stefano Ferri
**Supersedes:** none
**Superseded by:** none
**Related:**
- `docs/architecture/ADR-0003-concept-to-code-chain.md` (Accepted 2026-05-20; introduces
  the state machine with 16 transitions)
- `docs/superpowers/specs/2026-05-20-concept-to-code-e2e-smoke-design.md`
- `docs/superpowers/plans/2026-05-20-concept-to-code-e2e-smoke.md`
- `~/.claude/skills/concept-to-code/SKILL.md` (state machine §3)
- `~/.claude/skills/concept-to-code/scripts/manifest-init.sh`
- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` (16 legal pairs)
- `~/.claude/skills/concept-to-code/scripts/manifest-validate.sh`
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` (current PASS=12 — anchors)
- Memory `feedback_bash32-constraint.md`
- Memory `feedback_micropiano-refactor-cleanup.md` (risk of blind refactor — composition test mitigates)

---

## 1. Context

The current self-test (`tests/run-tests.sh`, 12 PASS) of concept-to-code covers the
3 bash scripts **in isolation**:

- `manifest-init.sh` (assertions 1-2): creates manifest at expected path, rejects
  double-init.
- `manifest-validate.sh` (assertions 3-5, 9-12): schema version, current_step,
  status invariants, invariant-7 quote/null.
- `manifest-transition.sh` (assertions 6-8): legal 0->1, illegal 0->5,
  last_updated_at refresh.

**No test verifies the complete composition** init -> 16 sequential transitions
-> completed. The state machine has 16 legal pairs (`manifest-transition.sh`
lines 36-52); currently only 2-3 pairs are covered indirectly.

Three converging pieces of evidence motivate the intervention.

1. **Cycle 2 of pricing-markup-cli (memory `feedback_micropiano-refactor-cleanup.md`).**
   A refactor that substitutes a pattern without explicit Add+Remove left duplication.
   Same risk for the 3 concept-to-code scripts: a future refactor (e.g. adding a new step,
   renumbering, PAIRS normalization) can pass the 12 unit tests but break end-to-end
   composition. The guardrail is missing.

2. **State machine fragility.** The 16 transitions live in a heredoc (`PAIRS` temp file)
   inside `manifest-transition.sh` line 36+. A typo in the pair (e.g.
   `step_5_implemenntation`) would fail only when *a real user* attempts that transition
   — silent bug until production. A smoke test that exercises all 16 pairs in sequence
   catches the bug at deploy time.

3. **ADR-0003 mentions 16 transitions as a declared contract** but the self-test does
   not verify it. Discrepancy between documentation (public contract) and executable
   verification.

### Architectural problem

The concept-to-code chain is a *composition* of 3 scripts + 16 transitions + failure
handling. The composition is not testable by the existing unit tests (which test scripts
in isolation with fresh state). An **integration smoke** is needed that exercises the
entire state machine as a real orchestrator would.

### Direction

Add `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh` (bash 3.2-clean),
invoked as the final step of `tests/run-tests.sh` (composition, not substitution). Smoke
coverage:

1. Init a fresh manifest in an isolated tmpdir.
2. Execute all 16 legal transitions in sequence on the happy path
   (including the `gate_5_review_decision -> completed` branch).
3. Attempt 3 illegal transitions (must fail with exit 1).
4. Force a `step_5_implementation -> failed` transition (status forcing).
5. Verify file consistency (`current_step`, `status`, `last_updated_at`
   monotonic) after each representative step.
6. Cleanup tmpdir via `trap EXIT`.

Time budget: <8s (target <5s; soft fail >10s).

---

## 2. Decision

Add `~/.claude/skills/concept-to-code/tests/smoke-e2e.sh`, executed
**inside** `tests/run-tests.sh` as the 13th composite assertion (1 PASS = smoke
completely green; 1 FAIL = smoke failed at any internal step, with stderr
identifying the step).

### 2.1 Smoke architecture

```
smoke-e2e.sh
  setup:    TMP=$(mktemp -d); trap cleanup EXIT; PROJ=$TMP/proj
  init:     manifest-init.sh demo "Demo Feature" $PROJ -> M=$PROJ/docs/manifests/...
  happy:    16 legal transitions in sequence, each followed by manifest-validate
  illegal:  3 illegal attempts (each must return exit 1)
  failure:  manifest-transition $M failed -> must succeed, status=failed
  consistency: parse final manifest, assert current_step + status + timestamp
  emit:     SMOKE=PASS or SMOKE=FAIL:<phase>:<detail>
  exit:     0 PASS, 1 FAIL
```

Each "phase" emits a sub-line `OK` or `FAIL` to stderr for debugging:

```
[smoke] setup OK
[smoke] init OK (path=/tmp/.../docs/manifests/...)
[smoke] happy 1/16 step_0->step_1 OK
[smoke] happy 2/16 step_1->gate_1 OK
...
[smoke] illegal 1/3 step_X->step_Y rejected OK
[smoke] failure-force OK status=failed
[smoke] consistency OK
SMOKE=PASS
```

### 2.2 Coverage of 16 transitions (happy path)

Sequence that exercises all 16 pairs (including the
`step_5_implementation -> gate_5_review_decision` direct branch, and the "reject"
branches of Gate 1/2/3 — backward transitions):

```
1.  step_0_init               -> step_1_interview
2.  step_1_interview          -> gate_1_spec_review
3.  gate_1_spec_review        -> step_1_interview          (reject branch)
4.  step_1_interview          -> gate_1_spec_review        (re-attempt)
5.  gate_1_spec_review        -> step_2_architecture       (approve)
6.  step_2_architecture       -> gate_2_architecture_review
7.  gate_2_architecture_review-> step_2_architecture        (reject branch)
8.  step_2_architecture       -> gate_2_architecture_review (re-attempt)
9.  gate_2_architecture_review-> step_3_project_memory      (approve)
10. step_3_project_memory     -> gate_3_project_memory_review
11. gate_3_project_memory_review -> step_3_project_memory   (reject branch)
12. step_3_project_memory     -> gate_3_project_memory_review (re-attempt)
13. gate_3_project_memory_review -> step_4_session_boundary (approve)
14. step_4_session_boundary   -> ready_for_implementation
15. ready_for_implementation  -> step_5_implementation
16. step_5_implementation     -> step_6_review
17. step_6_review             -> gate_5_review_decision
18. gate_5_review_decision    -> completed
```

These are 18 transitions; **all 16 distinct pairs are touched**. The 3 backward pairs
(3, 7, 11) are "reject" branches, already in the PAIRS list. The extra pair
`step_5_implementation -> gate_5_review_decision` (line 52 of `manifest-transition.sh`)
is NOT in the happy path here — it is verified in a second mini-flow:

**Second flow (alternative path, fresh manifest):**

```
1'. step_0 -> step_1 -> gate_1 -> step_2 -> gate_2 -> step_3 -> gate_3 ->
    step_4 -> ready -> step_5 -> gate_5 (via shortcut step_5_implementation -> gate_5_review_decision)
    -> completed
```

This flow touches the 16th pair "shortcut" (skip step_6_review).

Total coverage: 16/16 legal pairs verified.

### 2.3 Illegal transitions (3)

Attempted from `step_0_init` on a fresh manifest (replicates assertion 7 logic):

```
illegal 1: step_0_init -> step_5_implementation    (skip ahead)
illegal 2: step_0_init -> completed                 (jump-to-terminal)
illegal 3: step_0_init -> gate_2_architecture_review (skip gates)
```

All 3 must return exit 1.

### 2.4 Failure-force test

On a third fresh manifest (post-init), direct transition `step_0_init ->
failed` (allowed unconditionally per `manifest-transition.sh` lines 31-32).
Verifies:
- exit 0,
- `grep '^status: "failed"' manifest` -> match.

### 2.5 Answers to the 4 architectural questions

1. **Integration with existing harness:** smoke-e2e.sh **accompanies** and is
   **invoked by** `run-tests.sh` as the 13th composite assertion. Does NOT replace
   the unit tests (which remain as 12 individual PASSes). run-tests.sh executes
   `bash tests/smoke-e2e.sh && PASS=PASS+1 || FAIL=FAIL+1`. Rationale:
   single-entry-point for the system (vibe-status reads a single harness).
   Negative rationale for "separate": dilutes the signal — users see a single
   "PASS=N FAIL=0" number.

2. **Tmpdir cleanup:** `trap 'rm -rf "$TMP"' EXIT` for unconditional ALWAYS cleanup.
   On failure the tmpdir is cleaned regardless (no debug artifacts left).
   **Flag `--keep-tmp` not implemented in v1** (YAGNI: smoke-e2e is deterministic; for
   debugging the trap can be commented out in the script). Rationale: orphan artifacts
   in `/tmp` on CI = disk leak; a debug flag adds complexity for a rare use case.

3. **Execution time target:** **<5s soft, <8s hard** on macOS 14+ with
   bash 3.2.57. Measured with `time`. >8s = reported as WARN to stderr but not
   a failure. Rationale: the 3 scripts (`init`, `validate`, `transition`) each take
   ~50-100ms; 16 transitions x 100ms = 1.6s + 3 illegal x 100ms = 0.3s +
   failure force = 0.1s + setup/teardown = 0.5s ~= 2.5s wall. 2x margin for
   slow disks.

4. **Transition coverage:** **all 16 legal + 3 representative illegal + 1 failure-force.**
   Rationale: the added value is exactly *completeness* — a smoke that covers 12/16
   leaves 4 silent gaps (the same problem we want to solve). The 3 illegal are
   "representative" not "exhaustive" (15x14 combinatorics not practical; 3 examples
   cover patterns: skip-ahead, jump-terminal, skip-gates). Trade-off: completeness
   wins for restricted scope (16 is a small and fixed number).

---

## 3. Alternatives considered

### Alt-A — Separate smoke, NOT invoked by `run-tests.sh` (REJECTED)

Smoke lives in `tests/smoke-e2e.sh` but is invoked only on-demand
(`bash tests/smoke-e2e.sh`).

**Rejection:**
- Skill `vibe-status` (ADR-0005) reads a single harness per skill — seeing a PASS=12
  when a separate smoke also exists but is not run is misleading. Single-entry-point
  preserves the aggregator contract.
- A test that does not run by default = a test that rots. Cycle 2 lesson:
  "a check that requires human memory is already a non-functioning check".

### Alt-B — Smoke as Python script that parses the YAML manifest (REJECTED)

Use PyYAML for rigorous manifest parsing after each transition.

**Rejection:**
- Bash 3.2 hard constraint (sec. 0 of the system CLAUDE.md). Adding a Python dependency
  to a skill self-test that is 100% bash is a cross-stack smell.
- The 3 target scripts (`init`, `validate`, `transition`) are already bash; their contract
  is grep/sed-friendly. PyYAML adds surface without demonstrable benefit.

### Alt-C — Representative subset (8/16 transitions) (REJECTED)

Partial coverage (e.g. only 5-step happy path, no backward branches).

**Rejection:**
- Leaves 8 pairs unverified — same problem as today at 50%. The added value of the E2E
  smoke is exactly catching the "rogue" pairs (reject branches, shortcut step_5->gate_5).
- Sequence is 18 transitions ~= 2s wall — the time gain is marginal; the coverage risk is
  high. Clear cost/benefit decision for completeness.

---

## 4. Consequences

### Positive

- Future refactors of `manifest-transition.sh` (e.g. adding new step, gate renumbering)
  caught immediately by smoke failure.
- Declared contract (16 transitions) now verified as executable, not just documented.
- `vibe-status` reports PASS=13 (was 12) — single aggregated number of the
  concept-to-code skill state.
- State machine coverage: from 2-3/16 -> 16/16 + 3 illegal + 1 failure-force.

### Negative

- New file to maintain (`smoke-e2e.sh`, ~80-100 bash lines).
- run-tests.sh execution time grows by ~2-3s (was <1s). Acceptable.
- If the smoke FAILs, debugging requires reading stderr line `[smoke] phase X
  step_Y->step_Z FAIL <detail>` instead of individual assertion. Mitigation:
  verbose stderr with one line per transition.

### Neutral

- Smoke exercises the same 3 scripts as the unit tests; it does not add code coverage
  of new logic, only *composition*.
- Tmpdir cleanup unconditional on EXIT trap; no residue in `/tmp`.

---

## 5. References

- `~/.claude/skills/concept-to-code/scripts/manifest-transition.sh` (lines
  36-52: 16 PAIRS list — ground truth)
- `~/.claude/skills/concept-to-code/SKILL.md` §3 (state machine summary)
- `~/.claude/skills/concept-to-code/tests/run-tests.sh` (12 unit assertions —
  preserved intact)
- ADR-0003 §2 (transition table — declared contract)
