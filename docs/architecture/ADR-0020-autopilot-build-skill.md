# ADR-0020 — autopilot-build: standalone unattended-implementation skill

**Status:** Accepted (2026-06-26)
**Date:** 2026-06-18
**Author:** istefox
**Supersedes:** none
**Superseded by:** none
**Related:** ADR-0014 (test-cmd TOFU trust), ADR-0016 (Dynamic Workflows Step 5), ADR-0017 (Gate 0 chain-type routing)

---

## Context

### What "autopilot" means today

The `manifest.autopilot` flag exists as 21 inline directives scattered across
`concept-to-code/SKILL.md`. It is brownfield-only, lacks a dedicated entry point, has no
validator awareness, and is not enforced by any script — it is a prompt-level contract. The
closest wrapper is `project-conductor`, which flips the flag per-feature before invoking the
standard c2c chain. This design surfaces the flag's value only through the existing
interactive chain, where a human is still required to observe gate outcomes.

### The desired capability

There are features whose SPEC, ADR, plan, and project CLAUDE.md have already been reviewed and
approved by a human — the interactive c2c chain ran through Gates 1–3 and reached
`ready_for_implementation`. The implementation phase (Steps 5–7) is then fully mechanical:
dispatch coders, run tests, review, fix, commit. The human adds no value waiting for it.
The goal is a standalone system that runs this phase unattended and delivers a reviewed, locally
committed feature branch for the human to inspect in the morning.

### Why a standalone skill (not a flag, not a path)

The existing `manifest.autopilot` flag is scattered, hard to audit, and carries no hard safety
gate of its own. Embedding a new `autopilot` sub-graph in `concept-to-code` would require
modifying 21+ inline directive sites and re-validating the full 44-state machine. The cleaner
path is a separate skill that holds the complete unattended contract in one place, calls the
existing step scripts by absolute path, and leaves the interactive chain untouched.

### The scope-violation incident

A c2c resume with a manifest pointing to a different project caused agents to implement code in
the wrong repository from within the current session. This incident makes a hard, script-level
scope guard (not a prompt reminder) a first-class requirement for any unattended system.

---

## Decision

### D1: Package as `/skill autopilot-build <manifest-path>` — fully standalone

`autopilot-build` is a new skill at `~/.claude/skills/autopilot-build/SKILL.md`. It shares no
code with `concept-to-code/SKILL.md` except the helper scripts it calls by absolute path
(`manifest-validate.sh`, `manifest-transition.sh`, the Step 5/6 dispatch prompts, and the
`commit` skill). The entry contract mirrors Form B (`concept-to-code resume`) but removes
every `AskUserQuestion` call after Phase 0.

### D2: Autonomy boundary — local and reversible only

Autopilot may take unattended actions that are local and reversible. It must never take actions
that are shared-state or irreversible without a human in the loop.

| Unattended (allowed) | Never unattended |
|---|---|
| Code implementation (coder dispatch) | `git push` / `git push -u` |
| Run the approved test-cmd | Open PR, merge |
| Review + fix cycle | Force-push, branch deletion, file deletion |
| Local commit on a feature branch | DB schema changes, deploys |

v1 ends at a local commit. Push, PR, and merge remain human-initiated after reviewing the diff
and the morning report. A `--push` opt-in may be added in a future ADR, but it requires its own
safety analysis.

### D3: Phase 0 — eight hard pre-flight checks

All checks are read-only Bash. Any failure writes an `aborted` report and stops — the skill
never reaches dispatch on a partial pre-flight.

1. **Scope guard** (first, before any manifest read): resolve `project_root` from the manifest
   file. Resolve `$PWD`. If `project_root` is neither equal to CWD nor a subdirectory of CWD,
   emit a SCOPE ERROR and abort. This check is script-level, not prompt-level.
2. **Manifest state**: `manifest-validate.sh` passes and `current_step == ready_for_implementation`.
3. **Gates 1–3 approved**: each entry in `manifest.hitl_gates` for gates 1, 2, 3 has
   `status: approved` (brownfield "pre-existing spec" at gate 1 counts if approved).
4. **Artifacts on disk**: `test -f` for `artifacts.spec`, `artifacts.adr`, `artifacts.plan`.
5. **Plan has unchecked work**: `grep -c '- \[ \]' <plan>` is ≥ 1.
6. **test-cmd real and trusted** (the headline gate — see D4 below).
7. **Dispatch mode known**: `hook_verified` is `true` or `false`. If `null` or absent, abort
   with: "run the Step 5 smoke test in an interactive session first — the smoke test requires
   a human to read the terminal and cannot run unattended."
8. **Git repo present** at CWD (`git rev-parse --git-dir`), so worktree isolation is viable.

### D4: TOFU trust must pre-exist — never auto-granted in autopilot

The TOFU mechanism (ADR-0014) requires a SHA-pinned `(hash, normalized-root)` pair in
`~/.claude/state/stop-gate/trust`. In the interactive chain (Form B, Gate 2b), this trust can
be granted by the human at run time. In `autopilot-build`, the human is absent, so the trust
must already exist from a prior interactive session.

Pre-flight check 6 reads the trust file and aborts if the pair is not found. It never calls
`approve-test-cmd.sh` to create trust. The invariant from ADR-0014 stands: "Trust is born only
from explicit human SHA-pinned consent."

Rationale: the approved test-cmd is the only automated correctness signal during unattended
implementation. Without trusted tests, autopilot has no way to confirm its own output is correct.

### D5: Reuse c2c Step 5–7 mechanics — no reimplementation

`autopilot-build` Phase 1 invokes the same logic as `concept-to-code` Steps 5–7, with the
human-decision layer suppressed. Specifically:

- Step 5 dispatch prompt (§545–589 of `concept-to-code/SKILL.md`): the Workflow path when
  `hook_verified=true`, the Agent-tool batch fallback otherwise. `coder_model` is honoured.
- Step 6 review cycle (§710–787): Workflow path or `review-triage-fix` skill fallback.
- Step 7 commit: `Skill(commit, "<context-hint> --autopilot")`. The `commit` skill's
  `--autopilot` flag skips the HITL gate and skips push + PR. Local commit only.

All safety hooks (`stop-gate.sh`, `pre-flight-pattern-enforce.sh`, `protect-files.sh`,
`db-backup-guardrail.sh`) remain active throughout. Autopilot suppresses human prompts, not
safety mechanisms.

### D6: Circuit breaker on RED tests — halt without commit

After Step 5 dispatch, read `.claude/step5-report.json`. If `test_result` is RED, any task
failed, or the report is missing, stop immediately. Do not proceed to review or commit. Write
a `partial` morning report explaining what failed. The human inspects the partial work on the
feature branch and resumes interactively.

The same circuit breaker applies after Step 6's re-run: a second RED result halts without commit.

### D7: Morning report — `autopilot-report.json`

Written to `<project_root>/.claude/autopilot-report.json` on every exit path (success, partial,
aborted). Schema v1.0:

```json
{
  "schema": "1.0",
  "manifest": "<abs path>",
  "topic": "<topic-full-title>",
  "status": "success | partial | aborted",
  "abort_reason": "<string or null>",
  "started_at": "<ISO-8601, passed in from the launch environment>",
  "branch": "<type/topic-slug>",
  "steps": { "step5": "done | failed | not_run", "step6": "done | failed | not_run", "step7": "done | failed | not_run" },
  "tasks_completed": 0,
  "tasks_failed": 0,
  "test_result": "GREEN | RED | NOT_RUN",
  "files_modified": [],
  "commit_sha": "<sha or null>",
  "review_remaining": [],
  "next_action": "<human-facing instruction>"
}
```

The `started_at` field is populated from the invocation context (session start time or a
`--started-at <ISO>` argument), since scripts cannot call `Date.now()`.

---

## Alternatives considered

### Alt D1a: 4th `chain_path` in `concept-to-code`

Add `autopilot` to the state machine as a peer of Standard/Express/Hybrid, routable via Gate 0
`[auto]`. Rejected because: it requires modifying 21+ existing autopilot directive sites across
the 1700-line SKILL.md, re-validating the 44-state machine, and risks regressions in the
interactive chain. The standalone skill achieves the same behavior without touching the existing
code.

### Alt D1b: Enhance `project-conductor` as the autopilot runner

Evolve `project-conductor` to run a queue of features unattended, each via the existing
`manifest.autopilot` flag. Rejected for v1 because: it conflates single-feature and multi-feature
scopes; the `manifest.autopilot` flag still lacks a hard pre-flight; and the scope-guard
requirement cannot be added to the flag without modifying the same 21 directive sites. The
standalone skill provides a clean foundation that `project-conductor` can call in a future
multi-feature extension.

### Alt D2a: Allow `git push` as an unattended action

Pushing to a remote could be made conditional on `--push` being passed at invocation. Rejected
for v1 because: a push to a shared remote is not reversible and affects other team members.
The human reviewing the diff and report before pushing is a deliberate checkpoint. This can be
revisited in a future ADR once `autopilot-build` has proven reliable in field tests.

### Alt D4a: Auto-grant TOFU trust during Phase 0 pre-flight

If the trust entry is absent, call `approve-test-cmd.sh` automatically to register it. Rejected:
this violates the ADR-0014 invariant — trust is born only from explicit human consent. A
pre-flight that creates its own trust registration is self-approving, which undermines the
entire TOFU model. The human must have run the interactive chain at least once.

---

## Consequences

### Positive

- All safety hooks remain active; only the human-prompt layer is removed.
- The interactive chain is not modified. Existing workflows, tests, and muscle memory are intact.
- Pre-flight is script-level (not prompt-level), making the scope guard and TOFU check
  impossible to skip by prompt injection.
- The morning report is a machine-readable artifact — it can drive status dashboards or be
  consumed by `project-conductor` in a future multi-feature queue.
- `commit --autopilot` is already implemented; no new code is needed for local-only commit.

### Negative / risks

- Adds a third entry point for the implementation phase (interactive chain, `c2c resume`,
  `autopilot-build`). Users must know which to reach for.
- If the plan produced by the architect is ambiguous or incorrect, the circuit breaker may not
  catch it — a GREEN test suite on a wrong implementation still produces a committed result.
  Mitigation: Gate 3 (plan review) remains a human checkpoint and is enforced by the pre-flight.
- The `--push` boundary is opinionated. Teams with high trust in their test suites may want it.
  Documented as a future extension.

### Neutral

- CLAUDE.md for the blueprint repo gains an ADR-0020 summary block (matching the existing ADR
  summary pattern), keeping the file self-consistent without growing in proportion to complexity.
- Multi-feature queue (project-conductor extension), scheduling (CronCreate), and notification
  suppression (CLAUDE_CLIENT_PRESENCE_FILE) are out of scope for v1. Documented here for
  discoverability.

---

## Acceptance (2026-06-26)

Promoted from Proposed to Accepted. The skill is built and deployed: harness 14/14 green, wired into the chain as the Gate-4 in-session option, and the standalone entry point is live in `~/.claude/skills/autopilot-build/`. The architectural decision is adopted: a standalone skill holding the full unattended contract, a local-and-reversible autonomy boundary, eight pre-flight checks, TOFU pre-existing trust, and a circuit breaker on RED tests.

Open verification, not a blocker (same discipline as ADR-0016, which is Accepted while carrying assumed-not-verified addenda): the live smoke test of the permission-prompt path under autopilot from the CC 2.1.186 follow-up is still pending. The CC 2.1.186, 2.1.187, and 2.1.193 alignment items stay assumed-not-verified-live until that run. Acceptance records the adopted design; the smoke test promotes the runtime behavior from assumed to verified.

---

## CC 2.1.186 alignment (2026-06-23)

Two changes in this release touch the unattended guarantee. Both are assumed from the changelog text and are not yet verified live in this environment (see the verified-vs-assumed note).

Background subagent permission prompts (assumed, changelog 2.1.186). The release changed background subagents to surface permission prompts in the main session instead of auto-denying them. Before, a subagent that reached for a tool outside the allowlist was denied silently and deterministically, and autopilot kept going. Now that same case raises a prompt, and with no human at the keyboard the run stalls instead of failing closed. New pre-flight invariant: an unattended dispatch is only safe when the Step-5 allowlist covers every tool the subagents actually use, and the subagents run in `acceptEdits` (already true per ADR-0016). Any tool outside the allowlist now stalls the run instead of failing closed. Read the allowlist-completeness check together with pre-flight check 6 (test-cmd trust).

Retry watchdog (assumed, changelog 2.1.186). `CLAUDE_CODE_MAX_RETRIES` now caps at 15, and the changelog points unattended sessions at `CLAUDE_CODE_RETRY_WATCHDOG` instead. The autopilot session env should set `CLAUDE_CODE_RETRY_WATCHDOG` so a hung or looping dispatch stays bounded instead of open-ended. The changelog does not give the value format, so this stays a documented recommendation and is not pinned in `staging/user/settings.json`.

Follow-up: either item needs a live smoke test of the permission-prompt path under autopilot before it moves from assumed to verified, the same way `hook_verified` gates the workflow path.

---

## CC 2.1.187 alignment (2026-06-24)

Background-job hang on empty output (assumed, changelog 2.1.187). The release fixed background jobs in the agents view that got stuck in "working" indefinitely when a subagent ended its turn without producing structured output. For autopilot this closes one unattended hang mode: a dispatched subagent that finishes with no structured result now resolves instead of hanging the view. It does not close the permission-prompt stall from the 2.1.186 note, which is a separate path and still needs the allowlist-completeness pre-flight. Read the two together: 2.1.187 removes the empty-output hang, 2.1.186 leaves the out-of-allowlist prompt as the remaining stall risk under autopilot. See the ADR-0016 2.1.187 note for the workflow-side structured-output fix that pairs with this one.

---

## In-chain autopilot entry point (Gate 4, 2026-06-24)

The concept-to-code Standard path now offers unattended implementation from the planning session itself, not only via this standalone skill. At the session boundary (Gate 4, after Gate 3) the chain presents a third option, "Implement now (autopilot, this session)", which sets `manifest.autopilot = true` and continues into Steps 5-7 in the same session: implement, local commit via `commit --autopilot`, no push, no PR. This reuses the chain's built-in autopilot mode, where every gate auto-selects its safe default, so it stays inside the chain's skill allowlist and does not invoke this skill. TOFU is already approved at Gate 2b earlier in the same chain, so there is no trust stall.

Two entry points now coexist:
- This skill (`autopilot-build`): picks up a manifest already paused at `ready_for_implementation` from a fresh session. Adds an 8-check pre-flight and writes `autopilot-report.json`.
- Gate 4 "implement now": continues immediately from the planning session. No fresh session, no report; relies on the chain's normal output.

Two supporting fixes landed with it. The shared `manifest-init.sh` default for `hook_verified` was `true`, which silently disabled the Step-5 smoke-test gate (the gate only fires when the value is `false` or `null`); restored to `false` so the gate runs once per environment and the safe Agent-tool fallback is the default until hooks are verified. The Step-5 smoke-test gate also gained an autopilot default, so an unattended run resolves to the fallback instead of stalling on the smoke-test prompt. These live in `~/.claude`; the repo already documented `hook_verified` default false (ADR-0016), so this brought the deployment back in line.

---

## CC 2.1.193 alignment (2026-06-26)

Idle background-shell reaping (assumed, changelog 2.1.193). The release added automatic memory-pressure reaping of idle background shell commands, disabled with `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1`. This is most material for autopilot, which runs unattended for long stretches and can hold idle background shells across Steps 5-7. The autopilot session env should set `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` alongside the `CLAUDE_CODE_RETRY_WATCHDOG` recommendation from the 2.1.186 note, so a background shell is not reaped mid-run. Like the watchdog, the changelog gives no further detail, so this stays a documented session-env recommendation and is not pinned in `staging/user/settings.json`.

Background-agent dispatch fix (assumed, changelog 2.1.193). The release stopped the background-agent launch result from instructing Claude to "end your response", so the orchestrator keeps working while a dispatched agent runs. For unattended autopilot this reduces one stall surface during Step-5 dispatch, complementing the 2.1.187 empty-output hang fix. It does not close the 2.1.186 out-of-allowlist permission-prompt stall, which still needs the allowlist-completeness pre-flight.

---

## CC 2.1.195 alignment (2026-06-27)

Background-agent reliability fixes (assumed, changelog 2.1.195). The release fixed background jobs disappearing from `claude agents`, a crashed background task reopening to a blank screen, and background-agent daemons running unreachable when the control socket fails. These reduce failure modes for a long unattended autopilot run, which holds background agents across Steps 5-7 with no human in the loop. The daemon-reachability fix matters most here: an unattended run cannot recover a wedged daemon by hand, so a fix that keeps the control socket reachable directly protects the autopilot path. This lowers the risk on the still-pending smoke test from the Acceptance note above without removing the need for it. Assumed-not-verified-live.

## CC 2.1.196 alignment (2026-06-30)

Background-session durability, crash recovery, and the conversation-deletion fix (assumed, changelog 2.1.196). The release made background sessions survive their process being stopped, restarted, or updated; daemon-killed workers auto-resume when the agents view opens; Remote sessions auto-resume after a server restart; and waking a background job no longer deletes its conversation and re-runs the original prompt. For an unattended autopilot run holding background agents across Steps 5-7 with no human to intervene, these are the most material fixes yet in the background-agent thread: a process restart or a transcript misread mid-run no longer destroys in-progress work. Taken together they lower the risk on the still-pending smoke test from the Acceptance note further, without removing the need for it. Assumed-not-verified-live.

Sonnet 5 default (changelog 2.1.197). Sonnet 5 is the new Claude Code default, and the autopilot dispatch reuses the c2c Step 5-7 model mapping, so unattended runs become cheaper at a small accuracy cost. Because autopilot has no human catching errors and agentic-coding accuracy still favors Opus 4.8 over Sonnet 5, the autopilot reviewer step is the place to consider pinning Opus: it is the unattended safety net, low-volume, and worth the accuracy there, while the coder/tester steps and all interactive runs stay on Sonnet 5. This is a recommendation recorded against the model mapping, not a change to the skill contract.

---

## CC 2.1.205 alignment (2026-07-09)

Fabricated in-transcript approvals are now blocked at the notification layer (assumed, changelog 2.1.205). The release made background task notifications explicitly state that no human input has occurred, so an agent cannot act on a synthesized notification as though a human had approved something. This is upstream hardening for precisely the failure mode this ADR's autonomy boundary was built to survive: an unattended run convincing itself that authorization arrived.

The boundary does not change. D1 stands — only local and reversible actions run unattended (implement, test, review, local commit); push, PR, merge, and DB changes are never taken unattended. TOFU trust must still pre-exist, and autopilot never auto-grants test-cmd trust. The skill has never treated in-transcript text as authorization, and it still does not. What the fix buys is redundancy: the structural defense (what autopilot is permitted to do at all) now sits behind a platform defense (what a notification is allowed to imply). A fabricated approval that somehow reached the transcript would previously have depended entirely on the skill's own discipline to be ignored; now it is labeled at the source. Assumed-not-verified-live.

Two auto-mode rules narrow the unattended blast radius (assumed, changelog 2.1.205). Auto mode now blocks tampering with session transcript files and asks before running `rm -rf` on a variable it cannot resolve from context. The transcript is the audit record an `aborted` or `partial` autopilot report points a human at, and the `rm -rf` rule mirrors the destructive-command guardrail the safety hooks already enforce. The hook-level deny (`protect-files.sh`, `db-backup-guardrail.sh`) stays authoritative and fires regardless of permission mode; these rules are an additional outer layer, not a replacement.

Neither item closes the 2.1.186 permission-prompt stall. An out-of-allowlist Bash command still stalls an unattended run waiting on a prompt no human will answer, so the allowlist-completeness pre-flight recorded in the 2.1.186 note remains necessary, and the live smoke test of the permission-prompt path under autopilot is still pending. Note also that upstream published no changelog entry, tag, or release for 2.1.206 despite the binary shipping; nothing here is reconciled against it. Source: `~/.claude/cache/changelog.md` (bundled 2.1.205), cross-checked against upstream `CHANGELOG.md`.

---

## References

- ADR-0014 `docs/architecture/ADR-0014-architect-proposes-test-cmd.md` — TOFU trust model and `approve-test-cmd.sh`
- ADR-0016 `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — Step 5 Workflow dispatch and fallback
- ADR-0017 `docs/architecture/ADR-0017-chain-type-routing-gate0.md` — Gate 0 routing, `[auto]` option, brownfield requirement
- `~/.claude/skills/concept-to-code/SKILL.md` §4 Steps 5–7, §5 Gate 2b — dispatch prompts and TOFU gate reused verbatim
- `~/.claude/skills/commit/SKILL.md` line 30 — `--autopilot` flag contract (skip HITL gate, skip push)
- `~/.claude/skills/autopilot-build/SKILL.md` — implementation of this ADR
