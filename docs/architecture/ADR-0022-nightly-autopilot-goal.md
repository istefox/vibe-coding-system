# ADR-0022 — nightly-autopilot: overnight autonomous roadmap-to-PR capability

**Status:** Proposed (2026-07-01)
**Date:** 2026-07-01
**Author:** istefox
**Supersedes:** none
**Amends:** ADR-0020 D2 (autonomy boundary — adds a per-repo opt-in for unattended push + open PR)
**Related:** ADR-0003 (concept-to-code chain), ADR-0014 (test-cmd TOFU trust), ADR-0016 (Dynamic Workflows Step 5), ADR-0020 (autopilot-build)

---

## Context

### The goal

Stefano decides a project, spec, and architecture in the evening. That stays human-in-the-loop.
He then launches one run and goes to sleep. By morning the roadmap is implemented, self-reviewed,
committed on `feat/*` branches, pushed, with CI-green PRs open against `main` and ready for a
one-click merge. Nothing is merged to `main` automatically. A guard halts the machine on real
trouble and leaves a morning report.

### What already exists (verified against the repo, 2026-07-01)

- `concept-to-code` has an autopilot mode (`manifest.autopilot=true`) that auto-resolves every gate
  and commits locally with `commit --autopilot`. It stops at a local commit. No push, no PR.
- `autopilot-build` (ADR-0020) is the standalone unattended implement-review-commit skill with an
  eight-check pre-flight and a `autopilot-report.json`. Its §4 lists two deferred items that this
  ADR takes up directly: a `--push` opt-in ("needs a separate ADR; crosses the autonomy boundary")
  and a multi-feature overnight queue ("extend project-conductor to call autopilot-build").
- `project-conductor` runs a `PROJECT.md` roadmap feature-by-feature. It already has a "Start in
  autopilot mode" option and auto-resumes across the c2c session boundary in autopilot. But its
  Step 3 is an `AskUserQuestion` gate that fires once per feature, and invariant line 303 states:
  "NEVER skip the Step 3 HITL gate — each feature requires explicit user confirmation."
- Safety hooks (`stop-gate.sh`, `pre-flight-pattern-enforce.sh`, `protect-files.sh`,
  `db-backup-guardrail.sh`) and the TOFU test-cmd trust model live in `~/.claude/`.

### The missing outer-loop primitive: `/goal`

`/goal` is a native Claude Code command, documented at `code.claude.com/docs/en/goal`, requiring
CC v2.1.139 or later (verified 2026-07-01). It sets a completion condition (up to 4,000 chars); a
small fast model re-checks the condition after every turn and starts another turn if it does not
hold. It works interactive, headless (`-p`), and via Remote Control, and supports an
`or stop after N turns` clause. It requires hooks enabled (the evaluator is part of the hooks
system) and reports clearly if `disableAllHooks` or `allowManagedHooksOnly` blocks it.

Two properties shape the whole design:

1. **`/goal` removes per-turn prompts, not per-tool prompts and not `AskUserQuestion` gates.** The
   docs are explicit: "auto mode removes per-tool prompts, and `/goal` removes per-turn prompts."
   So an `AskUserQuestion` (project-conductor Step 3) is neither, and it still blocks. `/goal` alone
   over a multi-feature roadmap would keep the session alive and then hang at the first per-feature
   gate. Removing that gate under an opt-in is a hard requirement, not a nicety.
2. **The evaluator does not call tools.** It "can only judge what Claude has already surfaced in the
   conversation." So a condition like "each PR is open and CI is green" cannot be checked by the
   evaluator querying `gh` or the CI API. The run must print PR URLs and CI status into the
   transcript for the evaluator to judge against.

### The gap

For "PR-ready by morning" the missing pieces are: an outer completion loop (`/goal`), a roadmap-level
pre-authorization so the per-feature gate does not stall the loop, a publish step (push + open PR),
a CI check, a guard hook, and a morning report that records PR URLs and spend.

---

## Decision

### D1: A thin `nightly-autopilot` skill plus a roadmap-autopilot mode in `project-conductor`

The capability is a thin new skill `nightly-autopilot` that owns the new concerns: the launch
recipe and `/goal` condition template, the publish step, the guard-hook wiring, the CI and
branch-protection templates, and the morning report. It delegates the roadmap loop to
`project-conductor`, which gains a new roadmap-autopilot mode. The per-feature implementation
mechanics stay in `concept-to-code` autopilot / `autopilot-build` unchanged.

Rejected alternatives are recorded below (pure conductor extension; monolithic self-contained skill).
This shape keeps `project-conductor` the single roadmap engine while isolating publish, CI, and
report concerns that do not belong in it.

### D2: Amend the ADR-0020 autonomy boundary — opt-in per-repo push and open PR

ADR-0020 D2 set the boundary at a local commit: push, PR, and merge are never unattended. This ADR
amends that boundary for repos that explicitly opt in. The amended table:

| Unattended (allowed, opt-in repo only) | Never unattended, ever |
|---|---|
| Everything allowed in ADR-0020 D2 (implement, test, review, local commit) | Merge to `main` (no auto-merge) |
| `git push -u origin feat/<slug>` (feature branch only) | Force-push (`--force`, `-f`) |
| Open a PR to `main` via `gh pr create` (never `--merge`, never auto-merge) | Direct commit or push to `main` |
| Create the CI workflow and set branch protection on first run | `--no-verify`, disabling a test, DB schema change, deploy |

The boundary moves from "local and reversible only" to "local, reversible, plus reversible remote
publication that a human must still merge." A pushed feature branch and an open PR are recoverable
(delete branch, close PR); a merge to `main` is the irreversible act, and it stays human. The
per-tool deny list in `settings.json` already blocks force-push; this ADR keeps that and adds no
path that could merge or touch `main`.

### D3: Per-repo opt-in, never global

The relaxation is off by default and turned on per target repo by an explicit marker, not a global
setting. Proposed mechanism: a `.claude/nightly-autopilot.yml` (or a single sentinel file) in the
target repo holding `publish: true` plus the resolved CI/test command. Absent or `publish: false`
means the run stops at a local commit exactly as ADR-0020 autopilot does today. `nightly-autopilot`
reads this marker in pre-flight and refuses to push if it is missing. The marker is committed to the
target repo, so the opt-in is auditable in that repo's history.

### D4: `/goal` as the outer loop — condition template surfaces state

`nightly-autopilot` provides a `/goal` condition template that (a) states the terminal condition in
terms the evaluator can read from the transcript, and (b) carries a hard turn budget. Shape:

```
/goal "Every feature in PROJECT.md is [x], build green, review clean, committed on feat/*,
pushed, and a PR is open with CI green — as reported by the nightly-autopilot status line
printed after each feature. Or stop after <N> turns. Or stop if a NIGHTLY-GUARD HALT line
was printed."
```

Because the evaluator cannot call tools, the publish step and the guard MUST print a
machine-readable status line to the transcript after each feature (PR URL, CI state, or a
`NIGHTLY-GUARD HALT: <reason>` line). The `stop after N turns` clause is the turn-level hard stop;
a token budget is enforced separately in the guard (D7).

### D5: Roadmap-autopilot mode in `project-conductor` — pre-authorize the whole roadmap

`project-conductor` gains a mode (proposed: a `nightly` argument or a read of the D3 marker) that
pre-authorizes every pending feature as autopilot and skips the per-feature Step 3 `AskUserQuestion`.
Invariant line 303 is amended to: "In roadmap-autopilot mode, the per-feature Step 3 gate is skipped;
authorization comes from the D3 per-repo opt-in marker plus the single evening launch. In every other
mode the Step 3 gate is mandatory." The loop drives each feature through c2c autopilot to a local
commit, then hands off to the publish step (D6) before advancing to the next `[ ]` feature.

### D6: Publish step — idempotent, no auto-merge, surfaces the PR URL

After a feature's review cycle and local commit, and after the guard passes (D7), the publish helper:

1. Creates or switches to `feat/<slug>` (idempotent, reuse the branch if it exists).
2. `git push -u origin feat/<slug>` (never force).
3. Opens a PR to `main` via `gh pr create` if none is open for the branch (idempotent: detect an
   existing open PR by head branch and skip creation).
4. Never enables auto-merge; never passes `--merge`.
5. Prints a status line with the PR URL for the `/goal` evaluator and the morning report.

Re-runs must not duplicate branches or PRs. The helper is a Bash 3.2-clean script.

### D7: `nightly-guard` hook — PreToolUse on push/PR, fail-safe

`nightly-guard` is a `PreToolUse` hook matched on `Bash` calls to `git push` and `gh pr create`
(hooks are event-driven; "before publish" maps to the tool event that performs the publish, not to a
pipeline stage). It HALTS the publish and writes a morning report when any of:

- build still red after the fix cycle;
- a needs-human marker is present (unresolved placeholder, missing required asset, blocked TOFU);
- `review-triage-fix` raised a BLOCKER;
- the token budget is exceeded.

A halt leaves the PR NOT-ready: the branch may be pushed but the PR is not opened, or is opened as a
draft, so nothing broken looks mergeable. The guard prints `NIGHTLY-GUARD HALT: <reason>` so the
`/goal` loop stops (D4). It fails safe: on internal error it blocks the publish rather than allowing
it (opposite of the stop-gate's fail-open posture, because here allowing an unchecked publish is the
dangerous direction).

### D8: CI and branch-protection templates, parameterized by `.claude/test-cmd`

`nightly-autopilot` drops a reusable `.github/workflows/ci.yml` into the target repo on first run,
parameterized by the project's real test/build command read from the TOFU `.claude/test-cmd` (fall
back to a documented default if absent). A helper uses `gh` to set branch protection on `main`
(require the CI check, require a PR). CI needs no secrets for a static build; any deploy credential
is documented as a GitHub Actions secret, never inlined.

### D9: Morning report — schema v2.0, extends `autopilot-report.json`

The per-run report extends the ADR-0020 `autopilot-report.json` v1.0 with publish and CI fields:
per-feature PR URLs, CI status, guard-hook halts with reasons, and token/time spend. It is written
on every exit path (success, partial, aborted). A run-level report aggregates the per-feature ones.

### D10: Permission posture and hooks-enabled requirement

The launch recipe sets a non-blocking permission mode (accept-edits or bypass) so no per-tool prompt
fires unattended, and keeps hooks enabled (or `/goal` cannot evaluate and the guard cannot fire). The
RUNBOOK documents the `allowManagedHooksOnly` / `disableAllHooks` interaction: either blocks `/goal`,
and `/goal` will say so. This composes with the ADR-0020 CC 2.1.186 note: an unattended dispatch is
only safe when the Step-5 allowlist covers every tool the subagents use, otherwise an out-of-allowlist
tool raises a prompt that stalls the run.

### D11: Blueprint in the repo, synced to `~/.claude`

Per the repo's established pattern (ADRs here, artifacts in `~/.claude/`), the ADR plus the source of
the new skill, hook, publish helper, and CI/branch-protection templates are authored under this repo
(`staging/` and `docs/`), then an explicit sync step copies them into `~/.claude/`. The skill is not
live until synced. No artifact is written outside the repo without that explicit step.

---

## Alternatives considered

### Alt A: auto-merge on green

Let the run merge each PR once CI is green. Rejected: a merge to `main` is the one irreversible act
in the pipeline and the whole point of "PR-ready by morning, one-click merge in the morning" is to
keep the human as the merge gate. Auto-merge also removes the last review checkpoint on a wrong-but-
green implementation (the ADR-0020 negative-consequence risk). Kept explicitly out of scope.

### Alt B: pure extension of `project-conductor` + `autopilot-build`, no new skill

Put publish, guard, CI, and report directly into the two existing skills. Rejected: it conflates the
roadmap engine with publication and CI concerns, and it forces an in-place rewrite of the
`autopilot-build` "no push, no PR" invariant, which is load-bearing for its standalone use. The thin
skill isolates the boundary-relaxing concerns behind the D3 opt-in.

### Alt C: monolithic self-contained `nightly-autopilot`

One skill that reimplements the roadmap loop plus publish, guard, CI, and report. Rejected: it
duplicates the `project-conductor` roadmap logic (against the brief's "prefer extending over
duplicating"). Delegating the loop keeps one roadmap engine.

### Alt D: `/goal` alone, without removing the per-feature gate

Rely on `/goal` to carry the roadmap unattended. Rejected on verified behavior: `/goal` does not
bypass `AskUserQuestion`, so it would hang at project-conductor Step 3 on the first feature. The
roadmap-autopilot mode (D5) is required.

### Alt E: global opt-in for push

A single global setting enabling unattended push. Rejected: the relaxation must be scoped and
auditable per target repo (D3), so a throwaway or a sensitive repo is never publish-enabled by
accident.

---

## Consequences

### Positive

- One evening launch produces PR-ready branches by morning, with the merge decision preserved for a
  human.
- The autonomy boundary moves by the minimum needed (reversible publication) and stays off by default.
- Existing skills are reused, not duplicated; `autopilot-build`'s standalone "no push" contract is
  untouched (the relaxation lives in `nightly-autopilot` + the conductor mode, gated by the marker).
- The guard fails safe: a halt never leaves a misleading "ready" PR.

### Negative / risks

- The `/goal` evaluator's behavior around in-flight background shells and delegated subagents is not
  documented (the brief asserted it; the docs do not confirm it). If the evaluator judges mid-dispatch
  it could misread completion. Mitigation: the condition keys off an explicit status line printed only
  after a feature fully completes, and the guard's HALT line is authoritative; still, this is an
  assumed-not-verified item and gates the smoke test.
- A green test suite on a wrong implementation still produces a pushed, PR-open result (inherited from
  ADR-0020). The human's morning merge review is the checkpoint. Auto-merge is deliberately absent.
- Bypass permission mode overnight is a real surface. Mitigation: the deny list (force-push, `rm -rf`),
  the guard, hooks left enabled, and the per-repo opt-in bound the blast radius.
- A fourth unattended entry point now exists (interactive, c2c resume, autopilot-build, nightly).
  The RUNBOOK must make the choice unambiguous.

### Neutral

- The blueprint CLAUDE.md gains an ADR-0022 summary block, matching the existing pattern.
- Cron scheduling (`CronCreate`) is out of scope for v1; wrap once the smoke test passes.

---

## Open verification (not a blocker to accepting the design)

- Live smoke test on a throwaway repo: one-feature roadmap, opt-in marker present, launch `/goal` +
  conductor roadmap-autopilot, confirm the run implements, commits, pushes, opens a PR, prints the
  status line, and CI goes green, with nothing merged.
- Guard fail-safe: force a red build and a missing-input roadmap; confirm the guard halts, no
  "ready" PR exists, and the report names the blocker.
- `/goal` evaluator vs in-flight subagents: confirm the evaluator does not fire a false completion
  while a dispatch is still running.

These promote the runtime behavior from assumed to verified, same discipline as ADR-0016/0020.

---

## CC 2.1.198 alignment (2026-07-02): `claude agents` auto-push guardrail

CC 2.1.198 changed the `claude agents` background launcher: an agent that finishes code work in a
worktree now commits, pushes, and opens a draft PR on its own, instead of stopping to ask. Source:
`~/.claude/cache/changelog.md` (bundled 2.1.198; the online docs still end at 2.1.196).

This is a different launch path from nightly-autopilot. Nightly runs as a skill under `/goal`, with
work dispatched through the Agent tool or a Workflow script, and the `coder` sub-agent runs with
`isolation: worktree` inside that session. None of those paths adopt the launcher's auto-push
behavior, so the D2 boundary (push and open PR only on a per-repo opt-in; never merge, never
force-push, never write to `main`) is unaffected.

The residual risk is a human choosing to drive the roadmap through the `claude agents` launcher
directly. There the launcher's push may not route through the Bash tool, so the `nightly-guard`
PreToolUse Bash matcher would not see it. This is the same "wrapped push invisible to the hook
matcher" case this ADR already anticipated, which is why the publish helper carries an in-script
`--check` gate in addition to the hook. Guardrail: nightly-autopilot and autopilot-build must never
be driven through the `claude agents` background launcher. The in-script `--check` publish gate stays
the authoritative opt-in enforcement regardless of launch path.

## CC 2.1.203–2.1.204 alignment (2026-07-08): headless SessionStart-hook + overnight reliability

CC 2.1.204 fixed hook events not streaming during `SessionStart` hooks in headless sessions, which
could get a remote or background worker idle-reaped mid-hook. Source: `~/.claude/cache/changelog.md`
(bundled 2.1.204), cross-checked against upstream `CHANGELOG.md`.

This lands directly on the overnight path. Nightly runs headless under `/goal`, and the `SessionStart`
hook (session-context-inject, chain-memory surfacing) fires at the top of every session including the
unattended one. Before the fix, a `SessionStart` hook whose events did not stream could get the worker
idle-reaped in the middle of the hook — a run that dies before Feature 1 even starts. The fix removes
that failure mode with no config change. It is distinct from the ADR-0016 `hook_verified` blocker
(which concerns `PreToolUse`/`PostToolUse` inside Workflow subagents), which stays open.

CC 2.1.203 adds a warning before the login expires so a re-authentication can happen before background
sessions are interrupted. The RUNBOOK pre-flight already treats fresh auth as a launch precondition;
the warning is interactive and does not by itself keep an unattended run alive, so the pre-flight stays
the primary control. What changes is the failure signature: an expiring login is now flagged rather
than silently dropping the remaining features.

CC 2.1.203 also hardens the unattended runtime broadly: a background daemon auto-upgrade failure no
longer silently kills all running sessions, a background agent whose working directory is deleted or
replaced now fails once with a clear error instead of crash-looping, a stale daemon session token
auto-recovers instead of leaving the session unresponsive to attach/reply/stop, and `TaskStop`/`TaskOutput`
now resolve agents spawned by another agent. None of these change the D2 boundary (push and open PR
only on a per-repo opt-in; never merge, never force-push, never write to `main`); they reduce the
chance a nightly run dies for infrastructure reasons before it reaches a real stop condition.

---

## CC 2.1.205 alignment (2026-07-09): notification provenance + morning-report observability

CC 2.1.205 made background task notifications explicitly state that no human input has occurred,
preventing fabricated in-transcript approvals from being acted on. Source:
`~/.claude/cache/changelog.md` (bundled 2.1.205), cross-checked against upstream `CHANGELOG.md`.

This is the most directly relevant platform change to this ADR so far. The nightly run is the one
place in the system where an agent operates for hours with no human able to answer anything, while
holding the authority to push a branch and open a PR. The D2 boundary was written on the premise
that authorization can only come from two places: a committed `.claude/nightly-autopilot.yml` with
`publish: true`, checked by the in-script `--check` gate in the publish helper, and the `nightly-guard`
`PreToolUse` hook on `git push` / `gh pr create`. Neither reads the transcript. That premise is
unchanged, and the boundary is unchanged: push and open PR only on a per-repo opt-in; never merge,
never force-push, never `--no-verify`, never write to `main`. The fix means the enforcement is now
double-covered — a fabricated approval in the transcript was already inert against the `--check`
gate, and is now labeled as human-free at the source too.

The two new auto-mode rules (block tampering with session transcript files, ask before `rm -rf` on
an unresolved variable) apply to the overnight run as well. The transcript is what a `NIGHTLY-GUARD
HALT` sends the human back to in the morning, so protecting it protects the audit trail. `nightly-guard`
still blocks on internal error (fail-closed, the opposite of `stop-gate`'s fail-open) and stays the
authoritative control.

Morning-report observability improves without any contract change. Session-to-PR linking now catches
a PR created in a Bash call whose output exceeded the 30K inline limit — nightly opens every feature
PR with `gh pr create` in Bash, and a verbose invocation could cross that limit, so overnight PRs
previously risked not showing linked in `claude agents`. The agent list now shows a colored state word
and a classifier-written headline rather than raw tool-call text, and the peek opens with full status
including the exact ask for a blocked session, which makes a halted run faster to triage at breakfast.
The `NIGHTLY-PUBLISH` status line and `nightly-report.json` (schema v2.0) remain the authoritative
morning record; the agent view is a convenience on top of them.

Version note: the installed CLI reports 2.1.206, but upstream published no changelog entry, tag, or
release for it. Nothing in this ADR is reconciled against 2.1.206. All 2.1.205 items above are
assumed-not-verified-live.

---

## CC 2.1.206–2.1.209 alignment (2026-07-14): destructive-command stalls + overnight runtime hardening

This section resolves the version note above: Anthropic has published the 2.1.206 changelog
entries, and they are reconciled here together with 2.1.207–2.1.209. Source:
`~/.claude/cache/changelog.md` (bundled 2.1.209), cross-checked against upstream `CHANGELOG.md`
(fetched 2026-07-14).

CC 2.1.208 extends the catastrophic-removal guard (e.g. `rm -rf ~`) to commands wrapped in
`$(…)`, backticks, or `<(…)`, and makes it prompt even in auto mode and
`--dangerously-skip-permissions`, the two non-blocking modes the RUNBOOK names for the evening
launch. This adds a new failure shape to the overnight run: a substitution-wrapped destructive
command now **stalls on a permission prompt instead of executing silently**. The direction is
safe, the run halts rather than destroys, and the existing controls already surface it: the
`/goal` turn budget bounds a stalled run, the affected feature shows unpublished in the morning
report, and a `claude agents` peek shows the exact pending ask (CC 2.1.205 behavior). Nothing
answers the prompt overnight, by design. The D2 boundary is unchanged; `nightly-guard` and the
hook-deny rules stay the authoritative controls, and the native guard is a second, independent
barrier under them, the same layering the 2.1.205 section describes for notification provenance.

The runtime hardening in this range lands directly on the overnight path. The background daemon
no longer fails permanently after an update replaces the binary a running `claude agents` process
was launched from (2.1.208), and background agents now upgrade in the background right after a
CLI update (2.1.206). Together these close most of the mid-run auto-update hazard for a run that
spans an update window. Completed background agents stay listed in `/tasks` until cleanup,
transcripts shrink up to 79x in edit-heavy sessions with checkpoint disk usage bounded, several
long-session memory leaks are gone, and the false "100% context used" indicator after an
auto-update is fixed (all 2.1.208). No contract change: the `NIGHTLY-PUBLISH` line and
`nightly-report.json` remain the authoritative morning record.

All items above are assumed-not-verified-live.

## CC 2.1.210 note (2026-07-15): hook-timeout misreport fixed

CC 2.1.210 fixes a hook callback timeout being misreported to the model as a user rejection, which
previously made an unattended session stop and wait for input that would never arrive. This is the
silent-hang failure mode this ADR's D2 boundary and the `nightly-guard` design assume can happen
and must not leave a run stuck with no morning signal. The fix removes one concrete way it could:
a slow hook (for instance `pre-flight-pattern-enforce.sh` or `db-backup-guardrail.sh` under load)
no longer reads as a human "no" partway through a feature. No contract change: `nightly-guard`,
the `/goal` turn budget, and the morning report stay the authoritative controls regardless of this
fix; it removes one path to a hang they would otherwise have to catch after the fact.

Source: `anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched 2026-07-15). Assumed, not yet
verified live on an overnight run.

## CC 2.1.211 note (2026-07-17): background-agent respawn/fabrication fix + worktree-approval persistence

CC 2.1.211 closes two more gaps in the background-agent path this ADR's D2 boundary and
`nightly-guard` design assume can fail. First, a background agent killed by the user no longer
auto-respawns, and a revived agent no longer re-runs a stale prompt from an old session — this
extends the `claude stop`-is-honored fix from 2.1.199 (sec. "retry watchdog widened" in the main
doc) to the revive path specifically. Second, Claude Code's own status reporting for a
still-running background agent now waits for real completion instead of fabricating a result,
directly hardening the "don't race" discipline this ADR's morning-report design relies on:
`nightly-report.json` and the classifier-written headline (2.1.205) are the authoritative record,
but before this fix a premature or synthesized status could in principle have been surfaced to an
operator peeking mid-run.

Separately, "always allow" permission approvals now persist at the repository root instead of the
worktree they were granted in. A nightly run that walks several roadmap features overnight, each
through its own `feat/*` branch and (for Step-5 coder dispatch) its own isolated worktree, could
previously have re-prompted for the same TOFU-trust or tool-approval decision in each new
worktree — one more path to the exact stall `nightly-guard` exists to catch. No contract change:
`nightly-guard`, the `/goal` turn budget, and the morning report stay authoritative regardless of
this fix.

Source: `anthropics/claude-code` `CHANGELOG.md` (GitHub, fetched 2026-07-17). Assumed, not yet
verified live on an overnight run.

---

## `/goal` verified against official docs (2026-07-09)

Source: `code.claude.com/docs/en/goal`, fetched 2026-07-09. This section promotes several D4 premises
from assumed to **verified**, refutes a widely-circulated public claim that would invalidate the
design, and records one new risk that the design does not currently close.

### Verified — D4 holds as written

- **The evaluator cannot call tools.** The docs state it "does not call tools, so it can only judge
  what Claude has already surfaced in the conversation." D4's requirement that the publish step and
  the guard print a machine-readable status line (`NIGHTLY-PUBLISH`, `NIGHTLY-GUARD HALT`) to the
  transcript is therefore load-bearing and correct, not a defensive nicety.
- **A turn clause is the documented way to bound a run.** The docs: "To bound how long a goal runs,
  include a turn or time clause in the condition, such as `or stop after 20 turns`." D4's hard turn
  budget uses the sanctioned mechanism.
- **Headless `/goal` is supported.** The docs: "`/goal` works in non-interactive mode", with the
  example `claude -p "/goal ..."` running the loop to completion in a single invocation. The entire
  overnight path depends on this.
- **The evaluator is the small fast model** (Haiku by default), billed on the provider configured for
  the session, with negligible spend against main-turn tokens.

### Refuted — a public claim to the contrary

The `goal-loop` skill in `github.com/davidondrej/skills` (2k stars at time of writing) asserts two
things about `/goal` that are contradicted by the official documentation:

1. *"Launch the agent bare (opens the TUI). **Not** exec/headless mode — `/goal` is a TUI slash
   command only."* If true, this ADR's overnight design would be impossible. The docs explicitly
   support non-interactive mode.
2. *"Subscription auth — API-key auth does **not** work."* Stated three times in that skill. The docs
   list no auth or plan requirement; the evaluator "runs on whichever provider your session is
   configured for."

Recorded here so that a future reader who encounters that skill does not conclude the ADR's headless
premise is unsupported. The same skill documents `/goal pause` and `/goal resume` subcommands and a
`create_goal` tool, none of which appear in the Claude Code documentation; they most likely describe
a different agent's `/goal` implementation. Treat that skill as a methodology reference only. The
adapted, doc-checked version lives at `staging/plugin/skills/goal-loop/SKILL.md`.

### New constraint — `/goal` is a Stop hook

The docs describe `/goal` as "a wrapper around a session-scoped prompt-based Stop hook". Three
consequences for the nightly path, none of which change D2 or D4:

- `/goal` requires the workspace **trust dialog to have been accepted**, because the evaluator is part
  of the hooks system.
- `/goal` is **unavailable** when `disableAllHooks` is set at any settings level, or when
  `allowManagedHooksOnly` is set in managed settings. A nightly run launched into either state fails
  at the first turn, not silently.
- The system already installs a `stop-gate.sh` Stop hook. Both coexist by design, but the interaction
  between a fail-open safety Stop hook and the `/goal` evaluator's own Stop-hook wrapper has not been
  exercised live. Add to the open-verification list below.

These belong in the RUNBOOK pre-flight. Flagged here; the RUNBOOK is not modified in this pass.

### New open risk — the turn budget resets on resume

The docs state that when a session with an active goal is restored via `--resume` or `--continue`,
"the condition carries over, but the turn count, timer, and token-spend baseline all reset."

D4's `or stop after <N> turns` clause is therefore **not durable across a resume**. A nightly session
that is resumed — by a human in the morning, or by any recovery path that reattaches rather than
starting fresh — receives a fresh budget of N turns against the same condition. The evaluator judges
the turn clause from the conversation, and the count it reads has been zeroed.

This does not break the design, because the durable control is elsewhere: the guard's D7 token budget
is enforced in-script and does not reset. But the turn clause must not be described as a hard stop.
It is a soft cap that holds within one continuous session only.

Not fixed here. Recorded as an open risk to close, in keeping with the verified-vs-assumed discipline:
either the guard must persist a turn counter across resumes, or the RUNBOOK must state that a nightly
run is never to be resumed — it is restarted. Deciding between the two is a design change, out of
scope for a documentation reconcile.

---

## Routines / `/schedule` evaluated as an alternative outer loop (2026-07-09)

Prompted by the @ClaudeDevs article "Getting started with loops" (2026-07-06), which says you "move
the loop to the cloud by creating a routine with `/schedule`". Read quickly, that sounds like an
answer to every infrastructure problem this ADR has fought: the machine must stay awake, the login
must be fresh, the daemon must survive, the headless worker must not be idle-reaped. Verified against
`code.claude.com/docs/en/routines` and `/en/scheduled-tasks`, both fetched 2026-07-09.

**Verdict: not adopted.** Recorded as a live alternative with a real cost, not as a deferred task.
Adopting it would require its own ADR.

### What a routine would buy

A routine is a saved Claude Code configuration — prompt, repositories, connectors — executing on
Anthropic-managed cloud infrastructure, "so they keep working when your laptop is closed." Routines
are in **research preview**. The entire CC 2.1.203–2.1.205 background-reliability cluster this ADR has
been tracking (daemon auto-upgrade killing running sessions, stale session tokens, headless
`SessionStart` idle-reap, login expiry mid-run, and the machine-awake problem generally) becomes moot,
because none of it runs on this machine. A one-off schedule trigger fires at a chosen timestamp, which
is exactly the shape of the evening launch.

### What a routine would cost

Each item is a quote from `/en/routines`, or a direct consequence of one:

- **The safety apparatus does not exist.** A routine's session "can run shell commands, use skills
  committed to the cloned repository, and call any connectors you include." Every skill, agent, and
  hook this system depends on lives in `~/.claude/`. `nightly-guard`, `stop-gate.sh`,
  `protect-files.sh`, and `db-backup-guardrail.sh` would not be present. D2's publish boundary is
  enforced by an in-script `--check` gate **and** a `PreToolUse` hook on `git push` / `gh pr create`.
  A routine run has neither.
- **There is no permission model to layer against.** "Routines run autonomously as full Claude Code
  cloud sessions: there is no permission-mode picker and no approval prompts during a run." Included
  connectors may be used for writes "without asking for permission during a run." The layered-defense
  posture — hook-deny overrides any permission mode — has nothing left to override.
- **The branch convention collides.** "By default, Claude can only push to branches prefixed with
  `claude/`." This ADR pushes `feat/<slug>`. The escape hatch is a per-repo "Allow unrestricted branch
  pushes" toggle, which grants push to *existing* branches — strictly wider than the narrow grant D2
  was designed to be, and in the wrong direction.
- **Fresh clone from the default branch, every run.** State the nightly path carries across features
  (`PROJECT.md` checkboxes, manifests, `.claude/nightly-autopilot.yml`) survives only if committed.
  Some of it is. Not all of it.
- **Local MCP servers are absent.** Servers added with `claude mcp add` "are stored on your machine
  rather than your claude.ai account, so they do not appear in the connectors list." The workaround is
  a committed `.mcp.json` or a claude.ai connector.
- **One-hour minimum interval**, and a green run status "does not mean the task in your prompt
  succeeded" — so `nightly-report.json` stays load-bearing either way.

### Why the trade fails today

The exchange on offer is: surrender the in-repo safety apparatus, receive infrastructure reliability.

This ADR's amendment to the ADR-0020 autonomy boundary rests entirely on the claim that unattended
push and PR are acceptable *because* two independent mechanisms enforce the per-repo opt-in and halt
on trouble. Remove both and the amendment is no longer justified by its own reasoning. Infrastructure
reliability was never the binding constraint here. The boundary was.

### The path that could make it viable

Routines see skills committed to the cloned repository. This repo already authors skills and hooks
under `staging/` and syncs them into `~/.claude/`. A target repo could instead commit `.claude/skills/`
and `.claude/hooks/`, at which point a routine would see them and the guard could run inside the cloud
session. Whether hooks fire at all in a routine run is undocumented, and would need the same kind of
smoke test that gates `hook_verified` in ADR-0016. That is a design change and needs its own ADR. It
is not a follow-up task on this one.

### `/schedule` auth, and a correction to the public record

`/schedule` requires a claude.ai subscription login. The docs list a Console API key,
`ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `apiKeyHelper`, or a Bedrock / Vertex / Foundry provider
as reasons the command is hidden outright. Routines additionally require a Pro, Max, Team, or
Enterprise plan with Claude Code on the web enabled.

Worth stating precisely, because the `goal-loop` skill in `github.com/davidondrej/skills` attributes
the same subscription requirement to **`/goal`**, where the preceding section of this ADR establishes
it is false: `/en/goal` lists no auth or plan requirement, and states the evaluator "runs on whichever
provider your session is configured for." The requirement is real and attaches to `/schedule`. That is
the most likely origin of the error, and it does not rescue the claim as written.

---

## Stop-hook coexistence with `/goal` CONFIRMED by live probe (2026-07-10)

The "Open verification" list carried an item: `stop-gate.sh` is a `Stop` hook, `/goal`'s evaluator is
itself a session-scoped prompt-based `Stop` hook, and the two had never been exercised together.
**Closed, by measurement.** Method: `hook-probe` context C4 (`docs/RUNBOOK-hook-probe.md`).

A project-level `Stop` hook fired while `/goal` was active, and the evaluator independently judged the
condition met and cleared the goal on the first turn. Both ran. This matches `/en/hooks`: "All matching
hooks run in parallel, and identical handlers are deduplicated automatically." The transcript reported
five Stop hooks executing on a single turn end, and `stop-gate.sh` blocked normally on its own terms
earlier in the same session. Nothing in the design changes; the premise it rested on is now verified
rather than assumed.

Two operational facts fell out of the same run and belong in the RUNBOOK rather than here.

`stop-gate.sh` fires in any working directory, because it is registered at user level. A repo with a
dirty tree and no `.claude/test-cmd` gets blocked at the end of every turn until the hook's anti-loop
counter relents after three re-entries. Any scratch or sandbox directory used during a nightly
investigation needs `.claude/test-cmd` seeded, even when it holds no code.

`SubagentStop` fires spuriously. Across the probe run, 11 `SubagentStop` events corresponded to 2 real
subagents; the rest carried a fresh `agent_id`, an empty `agent_type`, and no matching `SubagentStart`,
one per main-loop turn. `nightly-guard` does not currently key on `SubagentStop`, and on this evidence
it should not start. See ADR-0016's probe section for the full data.

---

## References

- `code.claude.com/docs/en/goal` — `/goal` command, CC v2.1.139+ (verified 2026-07-01)
- ADR-0020 `docs/architecture/ADR-0020-autopilot-build-skill.md` — autonomy boundary (amended here), §4 deferred items
- ADR-0016 `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — Step 5 dispatch, `hook_verified`
- ADR-0014 `docs/architecture/ADR-0014-architect-proposes-test-cmd.md` — TOFU trust model
- `~/.claude/skills/project-conductor/SKILL.md` — roadmap engine, Step 3 gate (amended by D5)
- `~/.claude/skills/autopilot-build/SKILL.md` — unattended implement-review-commit, morning report v1.0
