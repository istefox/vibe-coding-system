# ADR-0016 — Dynamic Workflows: Replace Step 5 Batch Dispatch in concept-to-code

**Status:** Accepted  
**Date:** 2026-05-29  
**Amended:** 2026-06-09 — CC v2.1.160 renamed the dynamic-workflow trigger keyword from
`workflow` to `ultracode`; the bare word "workflow" no longer triggers a run (an explicit
request phrased in natural language still does). All trigger references updated below.  
**Author:** istefox  
**Supersedes:** none  
**Superseded by:** none  
**Related:** none  

---

## Context

### Current Step 5 — the problem

Step 5 of the `concept-to-code` chain dispatches the coder agent to implement the plan
produced by the architect in Step 2. The current design uses the `Agent` tool in batches
of 2-3 tasks to manage truncation risk:

```
Orchestrator
  ├── git rev-parse (worktree check)
  ├── Agent(coder, tasks 1-3)   ← batch 1
  ├── [checkpoint: git status + verify.sh]
  ├── Agent(coder, tasks 4-6)   ← batch 2
  └── [controller verification]  → Gate 5
```

Three structural problems with this design:

1. **Truncation risk.** State lives exclusively in the orchestrator's context window. For plans
   with 6+ tasks, a subagent dispatch can silently truncate mid-run without issuing a final
   report. The orchestrator cannot distinguish "task completed successfully" from "context
   overflowed before the task ran". The current workaround — batches of 2-3 tasks — bounds but
   does not eliminate this risk, and adds orchestrator overhead per batch.

2. **Scale ceiling.** The Agent-tool approach caps practical parallelism at the number of tasks
   the orchestrator can hold in mind simultaneously. There is no resumability: a mid-run failure
   restarts the entire batch.

3. **Structural coupling.** Intermediate results land in the orchestrator's context, making the
   orchestrator a stateful participant rather than a pure coordinator. This makes large plans
   sensitive to session health (compaction, length, memory).

### Dynamic Workflows — the feature

Claude Code v2.1.154 introduces **Dynamic Workflows** (research preview), available on all paid
plans including Pro, Max, Team, and Enterprise. The feature lets Claude write a JavaScript
orchestration script that the runtime executes outside the conversation:

- **Trigger:** include the keyword `ultracode` anywhere in the user-visible prompt (renamed
  from `workflow` in CC v2.1.160). Claude Code highlights the keyword in violet; Claude writes
  a JS script instead of working turn-by-turn. An explicit request phrased in natural language
  ("use a workflow to…") also triggers, but only the keyword is deterministic.
- **State model:** intermediate results live in script variables, not in Claude's context
  window. The orchestrator's context holds only the final answer.
- **Scale:** up to 16 concurrent agents, 1000 agents total per run.
- **Resumability:** agents that already completed cache their results; a paused run resumes
  within the same session. (Cross-session resumability is not supported: if Claude Code exits,
  the next session starts fresh.)
- **No mid-run user input** beyond tool-permission prompts. Sign-off between stages requires
  each stage to be its own workflow.
- **Subagent permissions:** workflow subagents always run in `acceptEdits` mode and inherit the
  session's tool allowlist, regardless of the session's permission mode.

### Hook behavior inside workflow subagents — unverified

Whether `PreToolUse`/`PostToolUse` hooks (pattern-enforce, stop-gate, db-backup-guardrail) fire
inside workflow subagents is **not documented** in the Dynamic Workflows reference. The docs
confirm that subagents inherit the tool allowlist; they say nothing about hook propagation.

This is safety-critical. The pattern-enforce hook (`PreToolUse` on `Edit`/`Write`) is the
primary contract-verification layer for the coder. If hooks do not fire inside workflow
subagents, the coder runs without the `PATTERN:` pre-flight check and without the stop-gate
(which prevents the orchestrator from bypassing HITL). These are non-negotiable guardrails.

**A smoke test is therefore a hard prerequisite before any production use of the workflow path.**

### Cross-repo isolation constraint

The concept-to-code skill lives in `~/.claude/skills/concept-to-code/` (not inside any git
repository). The manifest file for a given chain run lives in a target project's
`<project-root>/docs/manifests/`. When the skill runs against a project whose root is outside
a git repository (or when the session CWD is not inside a git repo), `isolation: worktree`
fails. The existing SKILL.md already handles this with `isolation: none` fallback.

Workflow subagents inherit the session's `acceptEdits` mode and tool allowlist. The cross-repo
scenario (implementing in `~/.claude/`, with manifest in a doc repo) requires `isolation: none`
and absolute paths in all read/write operations — already the convention in the skill.

### Assumptions (unvalidated at spec time)

1. The keyword trigger (`ultracode` in prompt; `workflow` before CC v2.1.160) reliably causes
   CC to generate a JS script rather than work turn-by-turn. If it does not, the orchestrator
   falls back to the current Agent-tool batch dispatch. The smoke test confirms the trigger works.
2. Dynamic Workflows remains available in its current form through the research preview period.
   If the feature is removed or gated differently, the fallback path activates with no chain
   breakage.
3. The `step5-report.json` file handoff survives session compaction (it is written to disk, not
   held in context, so compaction does not affect it).

---

## Decision

Replace the Step 5 batch dispatch instructions in SKILL.md with a **keyword-trigger +
step5-report.json file handoff** approach, with a fallback path to the current Agent-tool
batch dispatch when the workflow path is unavailable or unverified.

### Architecture

```
Orchestrator
  ├── Smoke test (once per environment, if hook_verified=false in manifest)
  │     └── trivial workflow in sandbox → user observes hooks → hook_verified=true|false
  │         If hook_verified=false: block. Workflow path is not used. Fallback activates.
  │
  ├── Step 5 dispatch prompt (includes "ultracode" keyword + coder instructions)
  │     └── CC generates JS script → dispatches coders as subagents (up to 16 concurrent)
  │           ├── Subagent 1: coder tasks 1-N
  │           ├── Subagent 2: coder tasks N+1-M
  │           └── Final subagent: writes <project_root>/.claude/step5-report.json
  │
  └── Orchestrator reads step5-report.json → verifies tasks_failed + test_result → Gate 5
```

### Trigger mechanism

The orchestrator's Step 5 dispatch prompt embeds the keyword "ultracode":

> "**ultracode** — use a workflow to dispatch the following coders in parallel…"

CC highlights the keyword and writes a JS orchestration script. If the keyword does not trigger
script generation (Claude Code version too old, feature disabled via `disableWorkflows: true`,
or the trigger is non-deterministic), the orchestrator detects it is still in turn-by-turn mode
and falls back to the Agent-tool batch path.

### Result handoff — step5-report.json

The final workflow subagent writes a structured JSON file to
`<project_root>/.claude/step5-report.json`. The orchestrator reads this file after the workflow
completes instead of relying on the coder's in-context report.

Schema:
```json
{
  "step5_mode": "workflow",
  "workflow_completed_at": "<ISO8601>",
  "tasks_completed": [1, 2, 3],
  "tasks_failed": [],
  "files_modified": [
    { "path": "absolute/path", "operation": "edit|create|delete" }
  ],
  "test_result": "green | red | n/a",
  "test_output_tail": "<last 20 lines of test output>",
  "harness_deltas": "PASS=N FAIL=0 (delta from baseline)",
  "errors": []
}
```

The orchestrator treats `tasks_failed` non-empty or `test_result: red` as a failure signal and
does not proceed to Gate 5 without user acknowledgment. A missing or stale file (stale = older
than `last_updated_at` in the manifest) triggers the `git diff + test run` fallback directly.

### Smoke test procedure (prerequisite, user-run)

Performed once per environment before first production use. Result recorded as `hook_verified:
true|false` in the manifest (additive field, schema 1.2-compatible, default `false`).

Steps:
1. Create a throwaway sandbox repo (`/tmp/wf-smoke-test/`), `git init`, add a minimal file.
2. Include the keyword "ultracode" in a prompt that triggers a single `Edit` tool call on that file.
3. Observe the terminal: confirm the pattern-enforce hook fires (emits a `PATTERN:` check
   message visible in the terminal output).
4. `hook_verified: true` → workflow path is available. `hook_verified: false` → fallback only.

User must observe the terminal during the smoke test. The chain records the outcome but cannot
auto-verify hook firing.

### Fallback path

If `hook_verified: false`, or if the keyword does not trigger script generation, or if
`step5-report.json` is absent after the workflow completes, the orchestrator falls back to the
current Agent-tool batch dispatch (2-3 tasks per batch, controller-side checkpoint between
batches). The fallback retains all existing behavior and does not change Gates 1-5.

### Manifest fields (additive, backward-compatible)

Two new fields added by `manifest-init.sh`:
```yaml
hook_verified: false   # true once smoke test passes in this environment
step5_mode: null       # "workflow" | "agent_batch" — set at Step 5 dispatch
```

These fields do not require a schema version bump (additive in schema 1.1; validator already
accepts 1.0|1.1|1.2; unknown fields are ignored by `manifest-validate.sh`).

---

## Alternatives considered

### Alternative A — Keep current Agent-tool batch dispatch unchanged

The current approach is known to work. It is the safe, zero-risk choice.

**Rejected because:**

The truncation risk on large plans is real and documented (MEMORY.md: `feedback_subagent-truncation-transport`). Batching is a workaround, not a solution: it reduces but does not eliminate the risk, and it adds per-batch orchestrator overhead (git status, verify.sh) that scales with plan size. For the 6+ task plans that the architect produces for non-trivial features, the current design is fragile at its stated scale.

Furthermore, the current design requires the orchestrator to hold intermediate results in context across multiple round-trips, coupling session health to implementation correctness. Dynamic Workflows removes this coupling cleanly. The fallback path preserves the current design in full when workflows are unavailable.

### Alternative B — /workflows dashboard manual trigger (user-initiated)

The user runs `/workflows` and selects a saved workflow script, or manually types `/deep-research`-style commands, instead of having the orchestrator embed a trigger in the dispatch prompt.

**Rejected because:**

This breaks the chain's deterministic dispatch contract. Step 5 is orchestrator-driven — the chain transitions from `ready_for_implementation` to `step_5_implementation` and dispatches the coder without user intervention. Requiring the user to navigate `/workflows` and select a run introduces a manual step that defeats the point of the chain's automation. It also requires a pre-saved workflow script per plan, which is impractical given that each plan is architect-generated and different.

The keyword-trigger approach (Alternative C, chosen) achieves the same runtime behavior without breaking the orchestrator's dispatch model.

### Alternative C — Keyword-in-prompt trigger with file handoff (chosen)

Embed the trigger keyword (`ultracode` since CC v2.1.160; originally `workflow`) in the
orchestrator's dispatch prompt; have the final workflow subagent write `step5-report.json`;
have the orchestrator read that file after the workflow completes.

**Chosen because:**

The trigger is zero-ceremony from the orchestrator's perspective: one keyword addition to the existing dispatch prompt template. The file handoff decouples the coder's results from context-window state. The fallback path (Alternative A behavior) activates automatically when the trigger fails or hooks are unverified. The smoke test provides a hard prerequisite gate that makes the safety risk explicit and user-controlled.

The primary weakness of this approach — that the keyword trigger is implicit and not
deterministically documented — is explicitly mitigated by the smoke test gate and the fallback
path. If the trigger fails, the chain is not broken: it degrades to current behavior.

---

## Consequences

### Positive

- **Truncation risk eliminated on the workflow path.** Intermediate results live in JS script
  variables, not in the orchestrator's context. Large plans (6+ tasks) complete without the
  current batch-overhead workaround.
- **Scale to 1000 agents per run.** The workflow runtime supports up to 16 concurrent subagents
  and 1000 total, far beyond the current practical limit of ~3 concurrent coder dispatches.
- **Resumability.** A failed or paused workflow run resumes within the same session, restoring
  completed-agent results from cache. The current Agent-tool path restarts the entire batch on
  failure.
- **Structured result handoff.** `step5-report.json` gives the orchestrator a machine-readable
  summary: which tasks completed, which failed, test results, files modified. Currently the
  orchestrator reads a free-text in-context report that requires parsing and is sensitive to
  truncation.
- **Fallback-safe deployment.** The existing Agent-tool batch dispatch is preserved as the
  fallback. The workflow path is additive: it activates only when `hook_verified=true` and the
  keyword trigger works.

### Negative / risks

- **Keyword trigger is implicit and fragile.** The trigger keyword is a CC behavior, not a
  stable documented API contract. If Anthropic changes the trigger condition, keyword
  sensitivity, or the behavior of the feature during or after the research preview, the
  orchestrator's dispatch prompt will silently fall through to turn-by-turn mode. The fallback
  path handles this, but the operator may not notice the degradation without monitoring
  `step5_mode` in the manifest. *This risk materialized on 2026-06-09: CC v2.1.160 renamed the
  keyword from `workflow` to `ultracode` (see Amended note above). Mitigation held — explicit
  natural-language requests still trigger, and the fallback path was never broken.*
- **Hook behavior inside workflow subagents is unverified.** This is the highest-risk unknown.
  The smoke test is the only mechanism to verify hook propagation before production use. If
  hooks do not fire, the entire workflow path is blocked — not as a degradation but as a hard
  block. The chain cannot proceed on the workflow path if the pattern-enforce and stop-gate
  hooks are absent.
- **Research preview — feature may be gated or removed.** Dynamic Workflows is documented as
  "research preview". Research previews can be restricted, changed, or discontinued without
  stable API guarantees. The design is resilient to removal (fallback path) but not to silent
  behavioral changes in the JS runtime environment that break the step5-report.json write
  contract.
- **No mid-run user input.** The workflow runtime does not support mid-run HITL. If the plan
  requires a user decision mid-implementation (unusual but possible), the workflow path cannot
  accommodate it. For such plans, the orchestrator must use the fallback Agent-tool path.
- **Cross-repo isolation: none required.** Workflow subagents must use absolute paths and
  `isolation: none` for the cross-repo scenario (implementing in `~/.claude/`, manifest in a
  target project). This is already the convention but must be preserved in the dispatch prompt
  template.
- **step5-report.json write contract relies on the final subagent completing.** If the last
  subagent in the workflow fails before writing the report, the orchestrator falls back to `git
  diff + test run` directly. This is correct behavior but means the structured result is not
  always available.
- **Session-bound resumability.** Workflow resumability works within the same Claude Code
  session. If the session exits mid-workflow, the next session starts the workflow fresh. For
  very long plans, the user must keep the session alive through completion.

### Neutral

- `step5_mode` and `hook_verified` are additive manifest fields. Existing manifests (schema
  1.0, 1.1) remain valid. The manifest validator does not reject unknown fields.
- No changes to `coder.md`, hooks (pattern-enforce, stop-gate, db-backup-guardrail), or Gates
  1-5. The workflow path changes only the Step 5 dispatch mechanism in SKILL.md.
- The smoke test is a one-time user action per environment. After `hook_verified=true` is
  recorded, the gate is silent for all subsequent runs.

---

## Smoke Test Result (2026-05-29, v2.1.156)

**Environment:** CLI v2.1.156, macOS 26, zsh. Workflow ran in session
`2fc99ad3-0770-4b0a-8e90-b0a8d14608c1`.

**Run 1 — baseline (hook v1.2):** `hook_verified=false`. The hook fired and correctly
identified `agent_type=coder`, but reported PATTERN missing. Root cause: workflow subagent
transcript stored at `subagents/workflows/<wf_id>/agent-<id>.jsonl`; hook searched only
`subagents/agent-<id>.jsonl`. PATTERN: was present in the transcript but the hook read
the main session jsonl (fallback), which contains no subagent text.

**Fix — hook v1.3:** Added `find`-based fallback in `pre-flight-pattern-enforce.sh`:
when the direct path is missing, search `$PROJ_DIR/$SID/subagents/workflows/` for
`agent-$AGENT_ID.jsonl`. Bash 3.2 compatible.

**Run 2 — post-fix (hook v1.3):** `hook_verified=true`. Audit log entry:
`allow — PATTERN found in window`. File appended correctly.

**Conclusions:**
1. Hooks propagate into workflow subagents: `PreToolUse` fires and `agent_type` is
   correctly set to the `agentType` passed in the workflow script.
2. The transcript path for workflow subagents differs from regular subagents — a
   previously undocumented path change introduced with Dynamic Workflows.
3. With hook v1.3, `pattern-enforce` correctly enforces the ADR-0001 contract inside
   workflow subagents.
4. The workflow path in Step 5 is unblocked. `hook_verified=true` can be set in manifests
   running on v2.1.154+ environments with hook v1.3 installed.

---

## CC 2.1.186 alignment (2026-06-23)

Assumed from the changelog text, not yet verified live in this environment.

Schema-validation abort (assumed, changelog 2.1.186). The release fixed Workflow `agent({schema})` subagents that used to loop forever on repeated schema validation failures; they now abort after 5 attempts. For Step 5 this removes a hang risk but changes the failure shape: a subagent whose output never satisfies the schema now returns null instead of spinning. The existing fallback already covers it, because a missing or incomplete `step5-report.json` routes Step 5 back to the Agent-tool batch dispatch. The Step-5 workflow script should filter aborted results with `.filter(Boolean)` before reading them, so one schema-failed agent does not poison the batch.

---

## CC 2.1.187 alignment (2026-06-24)

Structured-output success path (assumed, changelog 2.1.187). The release fixed Workflow `agent({schema})` and `--json-schema` output on the success side: the model can no longer re-call `StructuredOutput` after a valid result, and follow-up turns now reliably return structured output. This completes the 2.1.186 fix, which only bounded the failure side (abort after 5 validation failures). For Step 5 the net effect is a more dependable `step5-report.json`: a subagent that produces a valid report no longer risks looping or dropping the result on a later turn. The existing fallback and the `.filter(Boolean)` guidance from the 2.1.186 note still hold unchanged; this release narrows the failure surface rather than altering the contract.

---

## CC 2.1.193 alignment (2026-06-26)

Two items in this release touch Step-5 Workflow dispatch. Both are assumed from the changelog text and are not yet verified live here.

Idle background-shell reaping (assumed, changelog 2.1.193). The release added automatic memory-pressure reaping of idle background shell commands, disabled with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`. A long Workflow run can leave a background shell idle between stages long enough to be reaped, which would surface as a missing or truncated `step5-report.json`. The existing fallback already covers an incomplete report (it routes Step 5 back to the Agent-tool batch dispatch), so this does not break the chain; for long or memory-heavy runs the disable variable is the mitigation, set in the session env, not pinned in `staging/user/settings.json`.

Background-agent dispatch fix (assumed, changelog 2.1.193). The release stopped the background-agent launch result from instructing Claude to "end your response", so the orchestrator now keeps working while a dispatched agent runs. This is a positive for the orchestrator-during-dispatch behavior the Step-5 design depends on: the orchestrator can fan out and then proceed instead of ending its turn prematurely. Companion fixes (phantom `general-purpose (resumed)` subagent, pinned-agent re-prompt) reduce noise in parallel dispatch without changing the contract.

---

## CC 2.1.195 alignment (2026-06-27)

Background-agent reliability fixes (assumed, changelog 2.1.195). The release fixed background jobs disappearing from `claude agents`, a crashed background task reopening to a blank screen, and background-agent daemons running unreachable when the control socket fails. All three harden the background-dispatch path Step 5 relies on for `agent()` fan-out, and they continue the 2.1.193 background-agent thread. The effect is additive: nothing changes in the `step5-report.json` contract or the Agent-tool fallback, the failure surface just narrows. Assumed-not-verified-live, same discipline as the prior addenda.

## CC 2.1.196 alignment (2026-06-30)

Background-job conversation-deletion fix (assumed, changelog 2.1.196). The release fixed waking a background job permanently deleting its conversation and re-running the original prompt when the transcript probe misread a real transcript; the file is now set aside, never deleted. Step 5 fans `agent()` work out across background jobs and reads the result back, so a transcript that was deleted and re-run from the top would have surfaced as a lost or duplicated unit of work. This is a data-loss fix directly on the fan-out path, additive to the contract.

Duplicate-recap / StructuredOutput fix (assumed, changelog 2.1.196). The release stopped a schema-rejected StructuredOutput attempt rendering alongside its retry after a background turn. The `step5-report.json` handoff is StructuredOutput-backed (`tasks_completed`, `tasks_failed`, `test_result`, `files_modified`, `harness_deltas`), so a cleaner retry path reduces the chance of a malformed or doubled report reaching the orchestrator. No schema change.

These continue the 2.1.193/2.1.195 background-agent thread and are additive: the failure surface narrows, the contract and the Agent-tool fallback are unchanged. Assumed-not-verified-live.

Still open, not resolved by this release: the `hook_verified` blocker. No 2.1.196/2.1.197 changelog item addresses `PreToolUse`/`PostToolUse` hook propagation inside Workflow subagents, so the smoke test gating the workflow path (and the Agent-tool fallback when `hook_verified=false`) remains required exactly as before.

## CC 2.1.198 alignment (2026-07-02)

Workflow worktree edit-block fixed (changelog 2.1.198). The release fixed Workflow agents spawned with `isolation: 'worktree'` in background sessions being blocked from editing files inside their own worktree. Step 5 dispatches `coder` work this way, so before the fix a worktree coder could have returned with no edits applied, surfacing as a silent no-op in `step5-report.json` rather than an error. The fix removes that latent failure mode; the report contract and the Agent-tool fallback are unchanged. Assumed-not-verified-live, same discipline as the prior addenda. Source: `~/.claude/cache/changelog.md` (bundled 2.1.198).

The `hook_verified` blocker above is still not addressed by 2.1.198; the smoke test gating the workflow path remains required.

## CC 2.1.201–2.1.202 alignment (2026-07-07)

Dynamic workflow size setting (changelog 2.1.202). The release adds a `/config` control for how large Claude generally makes dynamic workflows (small/medium/large agent counts). It is explicitly an advisory guideline, **not an enforced cap**, so it does not change this ADR's hard limits: up to 16 concurrent agents and 1000 total per run still bound Step 5 fan-out. Effect on the chain: a Step-5 dispatch can be biased smaller or larger by default without touching the SKILL.md script, but the caps, the `step5-report.json` contract, and the Agent-tool fallback are unchanged. Source: `~/.claude/cache/changelog.md` (bundled 2.1.202).

Workflow script parse reliability (changelog 2.1.202). The release fixed workflow scripts with unicode quote escapes being corrupted before parsing, and made parse errors report the offending line instead of always blaming TypeScript. The Step-5 script is generated by Claude, so this narrows a latent script-corruption failure mode on the dispatch path. The existing fallback still holds: if the workflow does not produce `step5-report.json` (parse failure included), the orchestrator reverts to the Agent-tool batch dispatch. Additive; no contract change. Assumed-not-verified-live.

Workflow OpenTelemetry attributes (changelog 2.1.202). The release adds `workflow.run_id` and `workflow.name` attributes to telemetry emitted by workflow-spawned agents, so a Step-5 workflow run's activity can be reconstructed from OTel data. Observability-only, telemetry stays opt-in; no impact on the dispatch contract.

CC 2.1.201 (Sonnet 5 harness-reminder delivery) has no bearing on this ADR: it changes how harness reminders are delivered in Sonnet 5 sessions, not hook propagation or subagent behavior.

Still open, not resolved by this range: the `hook_verified` blocker. No 2.1.201/2.1.202 item addresses `PreToolUse`/`PostToolUse` hook propagation inside Workflow subagents, so the smoke test gating the workflow path (and the Agent-tool fallback when `hook_verified=false`) remains required exactly as before.

---

## References

- Dynamic Workflows docs: `https://code.claude.com/docs/en/workflows`
- Opus 4.8 announcement (Dynamic Workflows context): `https://www.anthropic.com/news/claude-opus-4-8`
- SPEC.md: `/Users/stefanoferri/developer/vibe-coding-system/SPEC.md`
- SKILL.md (Step 5 current): `~/.claude/skills/concept-to-code/SKILL.md` §4 Step 5
- ADR-0003: concept-to-code chain (original chain design)
- ADR-0009: db-backup-guardrail (hook safety pattern, 8-question template)
- ADR-0011: clean-public-repo + anonymize (fallback-safe deployment pattern, conditional dispatch)
- MEMORY.md: `feedback_subagent-truncation-transport` (documented truncation failure mode)
- MEMORY.md: `project_c2c-chain-hardening-2026-05-28` (Step 5 batching context)
