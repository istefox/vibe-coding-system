# Implementation plan — #103 Generator/verifier separation

- **ADR:** `docs/architecture/ADR-0049-103-generator-verifier-separation.md`
- **SPEC:** `SPEC.md` / `docs/specs/103-generator-verifier-separation-dispat.spec.md`
- **Branch:** `feat/103-generator-verifier-separation` (stacked on `feat/102-requirement-ids-coverage`)
- **Coder model:** sonnet

**Do NOT cite `R-NN` identifiers in this plan.** This SPEC declares none, and a citation the SPEC
does not declare is an `ORPHAN` — exit 3 from `spec-coverage.sh`, which is a Step 5 → Step 6 gate.

**Read first (risk 1 below is not hypothetical):** `write-scope-enforce.sh` and the new
`test-write-scope.sh` both self-arm on an agent that reads their own marker. Do not brief an agent to
Read a marker-driven hook by path; name the mechanism instead.

## Task checklist

- [ ] **Task 1 — RED harness.** Create `staging/plugin/scripts/tests/test-write-scope.test.sh`.
  `T`-prefixed labels, hermetic, bash 3.2, no `$HOME` coupling. Sections: **TA** the two decisions
  (§D1 ordering, §D3 marker); **TB** fail-open modes (no marker, no `agent_id`, no transcript,
  malformed JSON, `jq` missing, main-session non-fallback); **TC** agent-type discrimination
  (tester/refactorer/orchestrator allowed); **TD** the predicate table incl. the literal
  `docs/specs/103-….spec.md` case and a `testing-app/` component; **TE** expected-ALLOW bypasses
  (`Bash` heredoc, test content in a non-test filename); **TF** marker coupling hook↔SKILL.md and
  the deny reason's recovery path; **TG** both-paths pins; **TH** schema/read contract; **TI**
  registration; **TJ** `tester.md` contract; **TK** `####` heading uniqueness; **TL**
  `autopilot-build` isolation restatement. Every assertion must be seen RED.
  No fixture path may contain `secret`, `credential`, `.env`, `.pem`, `.key` — `protect-files.sh`
  denies them and `secret-dep-gate.test.sh` section D scans `git ls-files`.

- [ ] **Task 2 — the hook.** `staging/plugin/scripts/test-write-scope.sh`. Header states the threat
  model verbatim ("a guardrail against a shortcut, NOT a sandbox"). **Reads only the first `user`
  entry** of the subagent transcript (ADR-0049 §D9 — the scan-everything form is a live defect).
  `TEST_WRITE_SCOPE_DIR` state dir, audit log, `permissionDecision: "deny"` (never `block` — the
  ADR-0009 enum), exit 0 always. → TA/TB/TC/TD/TE green.

- [ ] **Task 3 — `staging/plugin/agents/tester.md`.** Four additive edits: spec-first `When to
  invoke` bullet; Process step-1 branch (brief from SPEC IDs, not from implementation); Output
  Format requirement-ID reporting; anti-fabrication edge case. → TJ green.

- [ ] **Task 4 — c2c Workflow path.** `pipeline()` stages tester → coder → optional reviewer; tester
  `agent()` pinned `model: "sonnet"`, `effort: "medium"`; the `--list` brief block with its two
  fallbacks; new heading `#### Generator/verifier separation — tester stage and coder test-write
  deny (ADR-0049)` placed after the Workflow dispatch block and **before** `#### step5-report.json
  schema…` (not between #101's and #102's gate headings); the dirty-tree isolation condition; GAP E
  strengthened to sequence conflicting groups. → TG(workflow)/TK green.

- [ ] **Task 5 — c2c Agent-tool fallback.** Tester dispatch per batch; the verbatim marker in the
  batch template; `SKILL.md:895` "Execute tasks … following TDD (red → green → checkpoint)" rewritten
  to "the red tests already exist — make them green; you may not create or edit test files"; the same
  isolation condition. → TG(fallback)/TF green.

- [ ] **Task 6 — report schema + read contract.** `tests_written_by` in the `step5-report.json`
  schema block; read contract states it is never a failure signal, absent is not malformed, and a
  `"coder"` entry is surfaced at Gate 5; extend the existing two-array contrast note to three. → TH green.

- [ ] **Task 7 — `sync-manual-steps.test.sh` contract update.** Its `build_home … yes` fixture
  enumerates the wired hooks and asserts the all-clear line; a fifth notice turns A3 red. Add the
  entry to the fixture, add a `TEST_MARK` and two assertions mirroring the E4/E5 pair. RED until Task 8.

- [ ] **Task 8 — registration.** `PAIRS` line
  `plugin/scripts/test-write-scope.sh|hooks/test-write-scope.sh`; the hook appended to
  `sync-to-claude.sh`'s `chmod +x` list; fifth conditional MANUAL-STEP notice; `staging/user/settings.json`
  reference entry; `docs-ci.yml` named list gains `test-write-scope` (after `spec-coverage`);
  `autopilot-build/SKILL.md:187–192` isolation restatement. → TI/TL and Task 7 green.
  `pairs-completeness.test.sh` is blind to `plugin/scripts/*`, so TI is the only thing preventing
  ADR-0043's defect here.

- [ ] **Task 9 — full suite.** Run the whole harness set, not just the new file: this changes
  `step5-report.json` (readers: `weakening-wiring.test.sh`, `step5-checkpoint-review.test.sh`,
  `spec-coverage.test.sh`, `autopilot-build/SKILL.md`, `concept-to-code/tests/run-tests.sh`) and
  `sync-to-claude.sh` (readers: `sync-manual-steps.test.sh`, `pairs-completeness.test.sh`). Confirm
  every previously-RED assertion is green and no pre-existing assertion regressed.

## Risk flags

1. **The hook that blocked the architect will block the coder implementing this.** Task 1 writes a
   path under `tests/`, and the coder reads marker-bearing sources as part of the job. Both hooks
   self-arm on a read of their own marker. The `write-scope-enforce.sh` first-entry fix is on this
   branch but is **staging-only** — the deployed copy still carries the defect until a human runs
   `sync-to-claude.sh --apply`. Dispatch accordingly.
2. **`isolation: "none"` returns for any group whose tester wrote something**, and Workflow-path task
   groups run in parallel — so parallel coders share the main tree for those groups. GAP E's conflict
   scan becomes load-bearing. Largest cost of the feature; not fully mitigated.
3. **The Workflow path's marker is model-generated text.** A paraphrase makes the guard silently
   inert on the default path. Compounding: manual `settings.json` wiring means the hook does nothing
   between merge and a human's edit.

TEST-CMD CANDIDATE: `for t in staging/plugin/scripts/tests/*.test.sh; do bash "$t" || exit 1; done`
TEST-CMD MODE: brownfield
CODER-MODEL CANDIDATE: sonnet
