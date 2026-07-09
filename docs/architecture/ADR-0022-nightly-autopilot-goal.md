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

## References

- `code.claude.com/docs/en/goal` — `/goal` command, CC v2.1.139+ (verified 2026-07-01)
- ADR-0020 `docs/architecture/ADR-0020-autopilot-build-skill.md` — autonomy boundary (amended here), §4 deferred items
- ADR-0016 `docs/architecture/ADR-0016-dynamic-workflows-step5.md` — Step 5 dispatch, `hook_verified`
- ADR-0014 `docs/architecture/ADR-0014-architect-proposes-test-cmd.md` — TOFU trust model
- `~/.claude/skills/project-conductor/SKILL.md` — roadmap engine, Step 3 gate (amended by D5)
- `~/.claude/skills/autopilot-build/SKILL.md` — unattended implement-review-commit, morning report v1.0
