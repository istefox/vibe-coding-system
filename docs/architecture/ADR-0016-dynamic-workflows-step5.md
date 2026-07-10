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

## CC 2.1.203–2.1.204 alignment (2026-07-08)

Worktree-isolated subagent shell fix (changelog 2.1.203). The release fixed worktree-isolated subagents that sometimes ran Bash in the parent checkout instead of their own worktree. Step 5 dispatches `coder` with `isolation: worktree`, so before the fix a coder's shell steps — test runs and shell-driven edits — could have executed against the main tree, contaminating it and mis-populating the `files_modified` list in `step5-report.json`. This is a correctness fix on the dispatch path, closing the worktree-shell gap left after the 2.1.198 edit-block and 2.1.200 plugin-load fixes. The report contract and the Agent-tool fallback are unchanged. Assumed-not-verified-live. Source: `~/.claude/cache/changelog.md` (bundled 2.1.203).

Forked-session `effortLevel` fix (changelog 2.1.203). The release fixed background sessions ignoring `effortLevel` changes in settings.json when forked through the daemon. This complements the workflow model-pinning update: a Step-5/6 `agent()` call with an explicit `effort` (or the settings default) now has it honored on the forked background path, so per-agent reasoning effort holds regardless of how the subagent session is created. Additive; no contract change.

`TaskStop`/`TaskOutput` nested-agent fix (changelog 2.1.203). The release fixed these tools failing to find background agents spawned by another agent, and made their errors list running agents by id and description. This hardens the Workflow orchestrator's inspect and kill path when a dispatched agent itself spawns work; the `step5-report.json` handoff and the Agent-tool fallback are unchanged.

`SessionStart` headless-hook fix is not the `hook_verified` blocker (changelog 2.1.204). CC 2.1.204 fixed hook events not streaming during `SessionStart` hooks in headless sessions. This is a `SessionStart` event in a headless session, distinct from the `PreToolUse`/`PostToolUse` propagation inside Workflow subagents that `hook_verified` gates. It de-risks the headless overnight path (see ADR-0022) but does not touch, and must not be read as resolving, this ADR's blocker.

Still open, not resolved by this range: the `hook_verified` blocker. No 2.1.203/2.1.204 item addresses `PreToolUse`/`PostToolUse` hook propagation inside Workflow subagents, so the smoke test gating the workflow path (and the Agent-tool fallback when `hook_verified=false`) remains required exactly as before.

## CC 2.1.205 alignment (2026-07-09)

The `--json-schema` fix is not the Workflow structured-output path (changelog 2.1.205). The release fixed `--json-schema` silently producing unstructured output when the schema was invalid, and schemas using the `format` keyword being rejected. This is the headless CLI flag. Workflow structured output is a different mechanism: `agent(prompt, {schema})` validates at the tool-call layer and makes the subagent retry on mismatch, and Step 5 does not consume `--json-schema` at all — it hands off through `.claude/step5-report.json` precisely so the orchestrator never depends on an in-context or CLI-serialized result. Recorded here so the two are not conflated in a later reading. No contract change. Source: `~/.claude/cache/changelog.md` (bundled 2.1.205).

Fabricated in-transcript approvals (changelog 2.1.205). The release made background task notifications explicitly state that no human input has occurred, preventing fabricated in-transcript approvals from being acted on. Step-5 dispatch runs subagents that report back through the transcript, so this closes a path where a workflow or Agent-tool subagent could have read a synthesized notification as authorization. It does not touch the `hook_verified` question, which is about hook *events* firing inside a Workflow subagent, not about what a subagent believes it was told. See ADR-0020 and ADR-0022 for the unattended-path reading.

Still open, not resolved by this range: the `hook_verified` blocker. No 2.1.205 item addresses `PreToolUse`/`PostToolUse` hook propagation inside Workflow subagents, so the smoke test gating the workflow path (and the Agent-tool fallback when `hook_verified=false`) remains required exactly as before. The smoke test was deliberately not re-run for this range. Note that upstream published no changelog entry, tag, or release for 2.1.206 even though the binary ships; nothing in this ADR is reconciled against it.

## Loop-taxonomy alignment (2026-07-09)

Prompted by the @ClaudeDevs article "Getting started with loops" (2026-07-06); operational claims cross-checked against `code.claude.com/docs/en/goal` and `/en/scheduled-tasks`, both fetched 2026-07-09.

Dynamic workflows sit inside a proactive loop. The Claude Code team's own composition for unattended recurring work is a schedule trigger, `/goal` to define the done-condition, skills to encode verification, dynamic workflows to orchestrate the agents that do the work, and auto mode so the run does not stop for per-tool permission. That places workflow dispatch exactly where this ADR puts it: the orchestration layer inside a longer-running loop, not the loop itself. Convergent with the design; nothing to change.

Pilot before a large run. The article states plainly that a dynamic workflow "can spawn hundreds of agents" and that usage should be gauged "on a smaller slice of the work first." Adopted as operational guidance for Step-5 dispatch: on a plan with a large task list, dispatch one batch and read `.claude/step5-report.json` before fanning out over the rest. This complements, and does not replace, the concurrency cap the Workflow tool already imposes. Article-sourced, so treat it as guidance rather than a documented platform limit.

Inspecting a running workflow. `/workflows` surfaces each agent's token usage and allows stopping an agent mid-run; a bare `/goal` reports turns and tokens spent so far; `/usage` breaks spend down by skill, subagent, and MCP. Together these are the observability side of the inspect-and-kill path that the CC 2.1.203 `TaskStop`/`TaskOutput` note above describes from the tool side.

None of this touches the `hook_verified` blocker, which remains open. Hook propagation into Workflow subagents is unrelated to loop taxonomy, and the smoke test still gates the workflow path.

---

## `hook_verified` RESOLVED by live probe (2026-07-10)

**Status: the blocker is closed.** Measured, not inferred. Method: `hook-probe` (`docs/RUNBOOK-hook-probe.md`), an observational hook run across four contexts in a throwaway sandbox, cross-checked against `pre-flight-pattern-enforce.sh`'s own audit log at `~/.claude/state/pattern-enforce/audit.log`. Evidence preserved.

### What was measured

Hooks **do** propagate into Workflow subagents. A workflow-spawned agent produced `SubagentStart`, `PreToolUse` and `PostToolUse` around its `Edit`, and `SubagentStop`, every row carrying `agent_id`. The subagent transcript resolved through exactly the `<proj>/<sid>/subagents/workflows/` glob that `pre-flight-pattern-enforce.sh` v1.3 already searches. Nothing in the platform is broken and nothing in the guard needs rewriting.

The failure was one string. `pre-flight-pattern-enforce.sh` enforces only when `agent_type == "coder"`. Two rows from its audit log, same session, minutes apart:

```
Edit  bypass-noncoder  agent_type=workflow-subagent
Edit  allow            PATTERN found in window
```

The first is a **default** workflow subagent: the guard saw the edit, read `agent_type`, and stood down. The second is a workflow agent spawned with `agentType: 'coder'`: the guard resolved the transcript, searched the sliding window, found the `PATTERN:` header, and allowed on the merits. That is a real enforcement decision, not a fail-open.

### Consequence for Step 5 — already satisfied, verified

`hook_verified: true` is justified **only for a dispatch that passes `agentType: 'coder'`**. Step 5 already does. `~/.claude/skills/concept-to-code/SKILL.md` lines 585-586 instruct the workflow script to call `agent(prompt, { agentType: "coder", model: ... })` on every task group, for the unrelated reason that a subagent given `agentType` but no `model` inherits the CLI session's model rather than the agent frontmatter's. The model-pinning fix of 2026-06-23 incidentally satisfies the enforcement precondition found today.

So no patch is required and no risk window exists. Had Step 5 omitted the option, the workflow path would have run with `pre-flight-pattern-enforce` inert — strictly worse than the Agent-tool fallback, because the guard would appear installed. That is the failure this section exists to prevent, and the invariant is now explicit: **any dispatch that spawns editing agents through `agent()` must pass `agentType: 'coder'`, or the guard is off.**

Defence in depth is still worth adding. ADR-0004's matcher should accept a set of identifiers, or key off `agent_id` present plus a suffix match on `:coder`, so a future plugin-scoped `stefano-vibe-coding:coder` does not silently re-open the same hole. Not done here.

### Two findings that were not being looked for

**`Workflow`'s `agent()` does not inherit `isolation: worktree` from the agent definition.** The `coder` agent declares it (sec. 3 of the blueprint) and the Agent tool honours it: in the probe, an Agent-tool coder was worktree-isolated without anyone asking. A coder-typed *workflow* agent, same definition, ran with `cwd` set to the primary checkout.

This matters because the two Step-5 paths differ, and the SKILL only guards one. The pre-dispatch worktree check in `~/.claude/skills/concept-to-code/SKILL.md` lines 475-486 sets `isolation` explicitly, but its own text scopes it to "the `Agent` tool" — the fallback path. The Workflow dispatch prompt (lines 562-590) says nothing about isolation, so workflow coders share one checkout. Parallel coders in Step 5 therefore edit the same tree. Whether that is intended is not recorded anywhere; on the evidence below it may well be the only thing that makes the workflow path work at all.

In the same run, the Agent-tool coder under worktree isolation left its edit stranded inside `.claude/worktrees/agent-*/`, and it never reached the primary checkout. The `coder` agent is defined never to commit, so there was nothing for a merge to pick up. Whether the Agent tool normally merges dirty worktree state back was **not** established here, and it bears on the whole chain rather than only on Step 5. Assumed, not verified. It needs its own probe before anyone adds `isolation: 'worktree'` to the workflow path on the grounds of symmetry.

**`SubagentStop` is not a reliable "a subagent finished" signal.** Across the run: 11 `SubagentStop` events, 2 real. A bare one fires after nearly every main-loop turn with a fresh `agent_id`, an **empty-string** `agent_type`, and no matching `SubagentStart`. Any future hook keyed on `SubagentStop` must discriminate on a non-empty `agent_type` or pair against a preceding `SubagentStart`. The empty string is non-null, which is precisely the trap: it silently wins a naive `head -1`, and it did, inside the probe's own verifier on the first live run.

### The old smoke test was blind, and the guard was not silent

The procedure in this ADR told the operator to watch the terminal for a `PATTERN:` message. That cannot distinguish "the hook never fired" from "the hook fired and bypassed itself" — both show nothing. Meanwhile `pre-flight-pattern-enforce.sh` was writing `bypass-noncoder` to its audit log the whole time. The data existed; the procedure never looked at it. Retire the terminal-watching smoke test in favour of `hook-probe`, which reads the log.

---

## Smoke test replaced by `hook-verify-workflow` (2026-07-10)

The `hook_verified` gate in `~/.claude/skills/concept-to-code/SKILL.md` no longer asks a human to watch a terminal. It brackets a one-agent smoke workflow with a timestamp and then reads `pre-flight-pattern-enforce.sh`'s own audit log, at `${PATTERN_ENFORCE_DIR:-~/.claude/state/pattern-enforce}/audit.log`.

Source: `staging/plugin/scripts/hook-verify-workflow.sh`, tested offline by `tests/hook-verify-workflow.test.sh` (26 assertions) against fixture logs under an overridden `PATTERN_ENFORCE_DIR`.

### Why the audit log is the right evidence

The guard records one tab-separated row per `Edit`/`Write`/`MultiEdit` it sees: `ts, session_id, tool, decision, detail`. Across 4,639 real rows the decisions are exactly three:

| decision | detail | meaning |
|---|---|---|
| `allow` | `PATTERN found in window` | the guard resolved the transcript and permitted the edit |
| `block` | `PATTERN missing in window=20` | the guard resolved the transcript and refused the edit |
| `bypass-noncoder` | `agent_type=<value>` | the guard stood down without looking |

**`agent_type` is recorded only on a bypass.** No `allow` or `block` row carries it. The first draft of the checker matched `agent_type=coder` on allow rows and would have matched nothing, ever; the fixtures agreed with the code because both encoded the same wrong belief. Only running the checker against the real log exposed it. The invariant that actually holds is stronger: the guard returns early unless `agent_type == "coder"` (`pre-flight-pattern-enforce.sh` lines 91-94), so **reaching `allow` or `block` is itself proof that a coder was ruled on**. A `block` proves enforcement exactly as an `allow` does.

### The contract

```
MARK=$(hook-verify-workflow.sh --mark)          # ISO-8601 UTC; lexical order == chronological
… dispatch one workflow agent with agentType: 'coder' that Edits a scratch file …
hook-verify-workflow.sh --check "$MARK"
```

Exit `0` VERIFIED, record `hook_verified=true`. Exit `1` REFUTED, record `false`, and the reason names which of the two failures occurred: no decision at all after the marker (hooks disabled, or the workflow never dispatched), or every workflow agent reported `workflow-subagent` (the dispatch omitted `agentType`, which is a workflow-script bug and not a platform limitation).

Exit **`3` INCONCLUSIVE** when the audit log is missing or unreadable. **Record nothing.** A missing log means the guard is not installed; it does not mean hooks fail to fire. Collapsing exit 3 into exit 1 would repeat, in the opposite direction, the exact error the terminal-watching procedure made.

### What did not change, and why

`manifest-init.sh` still defaults `hook_verified: false`. ADR-0020 records a regression in which the deployed default silently drifted to `true` and disabled the gate. The checker raises the flag on evidence; it never lowers the bar.

The autopilot branch is unchanged: an unattended run still skips the smoke test and takes the Agent-tool fallback unless `hook_verified` is already `true`. The check is now scriptable, so an autopilot run *could* verify rather than defaulting to the fallback, but that is a change to ADR-0020's unattended contract and needs its own decision. Not taken here.

### Known limit

The audit log cannot distinguish a *workflow* coder from an Agent-tool coder, since neither records `agent_type` on an allow. The marker bounds the window to the smoke dispatch, so in practice the only coder running is the workflow's. Do not run the check while another coder agent is working in the same session.

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
