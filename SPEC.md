# SPEC — Dynamic Workflows integration into concept-to-code Step 5

**Date:** 2026-05-29
**Topic slug:** dynamic-workflows-step5
**Manifest:** docs/manifests/2026-05-29-dynamic-workflows-step5.manifest.yml

---

## Objectives

Replace the manual `Agent`-tool-based parallel coder dispatch in **Step 5 only** of the
`concept-to-code` chain with Claude Code's **Dynamic Workflows** orchestration layer
(research preview, Opus 4.8). Goals:

1. Remove the ≥6-task batching workaround (truncation risk → Dynamic Workflows handles
   scale via script variables + resumability).
2. Enable reliable dispatch for large plans without silent mid-plan truncation.
3. Produce a structured results file (`step5-report.json`) that the orchestrator reads
   instead of trusting the coder's in-context report.
4. Verify that all existing hooks fire correctly inside workflow subagents before shipping.

---

## Scope

### In scope
- `~/.claude/skills/concept-to-code/SKILL.md` — Step 5 section rewrite:
  - Trigger mechanism (keyword in dispatch prompt)
  - Result handoff contract (`step5-report.json`)
  - Batch policy removal in workflow mode
  - Fallback path (Agent tool batch dispatch if workflow unavailable)
  - Smoke test procedure (prerequisite step, first time only)
- `step5-report.json` schema definition
- `~/.claude/skills/concept-to-code/scripts/` — no new scripts required (results via file)
- Manifest: minor extension (`step5_mode` and `hook_verified` fields) — additive, backward-compatible

### Out of scope
- Gates 1–5 (HITL): unchanged
- `~/.claude/agents/coder.md`: unchanged (coder still runs with the same instructions)
- `~/.claude/hooks/`: unchanged (pattern-enforce, stop-gate, db-backup-guardrail)
- `~/.claude/skills/review-triage-fix/SKILL.md`: unchanged
- `docs/vibe-coding-system.md` update: deferred to post-implementation doc pass
- Manifest schema version bump: not required (additive fields)

---

## Stack

- **Claude Code** 2.1.154, Max plan (Dynamic Workflows research preview)
- **Target files**: `~/.claude/skills/concept-to-code/SKILL.md` (primary),
  manifest YAML (additive fields only)
- **Runtime**: Dynamic Workflows triggered by "workflow" keyword in the Step 5 dispatch
  prompt; Claude Code writes the JS orchestration script dynamically
- **State handoff**: `<project_root>/.claude/step5-report.json` (written by the last
  workflow subagent, read by the orchestrator)
- **Bash 3.2**: no new shell scripts added; manifest updates use existing helpers

---

## Architecture

### Current Step 5 (pre-feature)

```
Orchestrator
  ├── git rev-parse (worktree check)
  ├── Agent(coder, tasks 1-3)   ← batch 1
  ├── [checkpoint: git status + verify.sh]
  ├── Agent(coder, tasks 4-6)   ← batch 2
  └── [controller verification]  → Gate 5
```

State lives in the orchestrator's context window. Truncation risk above 5 tasks.

### New Step 5 (post-feature)

```
Orchestrator
  ├── Smoke test (first run, if hook_verified=false in manifest)
  │     └── trigger trivial workflow in sandbox → user confirms hooks fire → hook_verified=true
  ├── Step 5 dispatch prompt (includes "workflow" keyword + coder instructions)
  │     └── CC generates JS script → dispatches coders as subagents (max 16 concurrent)
  │           ├── Subagent 1: coder tasks 1-N
  │           ├── Subagent 2: coder tasks N+1-M
  │           └── Final subagent: writes <project_root>/.claude/step5-report.json
  └── Orchestrator reads step5-report.json → Gate 5
```

State lives in workflow JS script variables (not context window).
Resumability: if a subagent fails, the workflow script can restart from checkpoint.

### Fallback path

If Dynamic Workflows is unavailable or the keyword does not trigger script generation:
the orchestrator falls back to the **current Agent tool batch dispatch** (unchanged).
The fallback retains the ≥6-task batching policy.

### Hook interaction (safety-critical)

**Unverified at spec time.** Whether `PreToolUse`/`PostToolUse` hooks fire inside
workflow subagents is unknown. The smoke test is a **hard prerequisite** before any
production use of the workflow path.

If hooks do NOT fire: Dynamic Workflows is blocked for this project. Not negotiable.

---

## Data model — `step5-report.json`

Written by the final workflow subagent to `<project_root>/.claude/step5-report.json`.
Read by the orchestrator after the workflow completes.

```json
{
  "step5_mode": "workflow",
  "workflow_completed_at": "ISO8601",
  "tasks_completed": [1, 2, 3],
  "tasks_failed": [],
  "files_modified": [
    { "path": "absolute/path", "operation": "edit|create|delete" }
  ],
  "test_result": "green | red | n/a",
  "test_output_tail": "last 20 lines of test output",
  "harness_deltas": "PASS=N FAIL=0 (delta from baseline)",
  "errors": []
}
```

The orchestrator treats `tasks_failed` non-empty or `test_result: red` as a failure
signal and does not proceed to Gate 5 without user acknowledgment.

---

## Trigger mechanism

The orchestrator's Step 5 dispatch prompt must include the word "**workflow**" to trigger
CC to generate a JS orchestration script instead of doing turn-by-turn work.

Trigger phrase (embedded in the dispatch):
> "Use a **workflow** to dispatch the following coders in parallel…"

The trigger is implicit — CC behavior when seeing "workflow" is not deterministically
documented. If the keyword does not trigger script generation, the orchestrator detects
it (still in turn-by-turn mode) and falls back to the Agent tool path.

---

## Smoke test procedure

Run ONCE per project before using the workflow path in production.
Result recorded as `hook_verified: true|false` in the manifest (additive field).

Steps:
1. Create a throwaway sandbox repo (`/tmp/wf-smoke-test/`), init git, add a minimal file.
2. Invoke a workflow that triggers a single `Edit` tool call on that file.
3. Observe the terminal: confirm the pattern-enforce hook fires (emits a `PATTERN:` check
   message to stderr / visible in the terminal).
4. If hook fires → `hook_verified: true`; proceed with workflow mode.
5. If hook does NOT fire → `hook_verified: false`; stay on Agent tool path. Report finding.

User must observe the terminal during the smoke test. The chain records the result but
cannot auto-verify hook firing.

---

## UI flows

### Happy path (workflow mode)
1. Orchestrator checks `manifest.hook_verified`. If `false`: presents smoke test
   instructions. User runs smoke test, reports result.
2. If `hook_verified: true`: orchestrator dispatches Step 5 prompt (workflow keyword +
   coder instructions + step5-report.json write contract).
3. CC generates JS script, dispatches subagent coders (up to 16 concurrent).
4. Workflow writes `.claude/step5-report.json`.
5. Orchestrator reads report: verifies `tasks_failed` empty, `test_result` not red.
6. Transitions to `step_6_review`. Presents Gate 5.

### Fallback path (Agent tool)
Identical to current Step 5 (batching, per-batch checkpoint, controller-side verify).

### Failure path
- `step5-report.json` absent → orchestrator falls back to `git diff + test run` directly.
- `tasks_failed` non-empty → failure report; user decides how to proceed.
- `test_result: red` → same failure signal as current behavior.

---

## Edge cases

| Scenario | Behavior |
|---|---|
| Plan ≤5 tasks | Workflow mode still preferred; fallback available if latency too high |
| Smoke test not yet run | Step 5 blocks; orchestrator presents smoke test before dispatch |
| Workflow crashes mid-run | CC resumability handles it; if step5-report.json absent → git diff fallback |
| Cross-repo (impl in ~/.claude, manifest in doc repo) | Coder uses absolute paths; `isolation: none` (files outside git repo) |
| step5-report.json stale from a prior run | Orchestrator checks `workflow_completed_at` vs manifest `last_updated_at`; stale → ignore, use git diff |
| Dynamic Workflows removed/gated after research preview | Fallback path activates; no chain breakage |

---

## Success criteria (Definition of Done)

1. **Smoke test passed**: `PreToolUse`/`PostToolUse` hooks confirmed firing inside
   workflow subagents. `hook_verified: true` recorded in manifest.
2. **SKILL.md updated**: Step 5 section in `~/.claude/skills/concept-to-code/SKILL.md`
   contains workflow dispatch instructions, fallback path, and `step5-report.json`
   read contract. Batch-dispatch template demoted to fallback only.
3. **Existing harness green**: `bash ~/.claude/skills/concept-to-code/tests/run-tests.sh`
   passes at ≥ PASS=32 FAIL=0 (pre-feature baseline).
4. **End-to-end chain run**: a ≥6-task plan completes via workflow mode; PATTERN: hooks
   observed firing; `step5-report.json` written with correct schema; harness green.
5. **ADR-0016 written**: decision recorded in
   `docs/architecture/ADR-0016-dynamic-workflows-step5.md`.

---

## Constraints

- No changes to hooks (pattern-enforce, stop-gate, db-backup-guardrail).
- No changes to `coder.md`.
- No HITL gate changes (Gates 1–5 unchanged).
- Bash 3.2-clean for any new helper scripts.
- Manifest writes via helper scripts only (no direct Edit-tool writes to manifest).
- Hook safety is a hard blocker: if hooks do not fire in the smoke test, the workflow
  path is not shipped.
