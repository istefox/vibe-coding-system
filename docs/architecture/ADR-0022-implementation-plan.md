# ADR-0022 Implementation Plan — nightly-autopilot

**Companion to:** ADR-0022 (Proposed, 2026-07-01)
**Status:** Draft for review
**Author:** istefox

This plan turns ADR-0022 into an ordered, file-by-file task list with a definition of done per
artifact, the HITL gates, and the open risks carried from the ADR. Implementation starts only after
this plan is approved.

---

## Ground rules

- Blueprint lives in this repo (`staging/`, `docs/`). A final sync step copies artifacts into
  `~/.claude/`. Nothing under `~/.claude/` is overwritten without showing a diff first (global rule).
- All shell scripts are Bash 3.2-clean (macOS default). No `Date.now()` or `Math.random()` in any
  workflow script; timestamps come from `date -u` in Bash or are passed in.
- No path in the delivered system can force-push, auto-merge, or push/commit to `main`.
- Existing skills, hooks, tests, and the stop-gate/TOFU model must keep passing.

---

## Refinements to the ADR discovered during planning

1. **Guard invocation path (refines D7).** A `PreToolUse` hook matches the Bash tool's command
   string. If `git push` runs inside `publish-feature.sh`, the outer command is `bash
   publish-feature.sh ...` and the matcher never sees `git push`, so the hook would not fire. Fix:
   one script `nightly-guard.sh` invoked on two paths. (a) `publish-feature.sh` calls it as an
   authoritative pre-publish gate before it runs `git push`. (b) The same script is wired as a
   `PreToolUse` hook on direct `git push` / `gh pr create` Bash calls, as defense in depth. The
   in-script call is the belt; the hook is the suspenders.
2. **`/goal` is set by the human, not the skill.** A skill cannot type a slash command. The RUNBOOK
   recipe has the human paste the `/goal` template. `nightly-autopilot` prints the ready-to-paste
   template; it does not attempt to set the goal itself.
3. **Conductor source is not versioned in the repo today.** `project-conductor/SKILL.md` lives only
   in `~/.claude`. The plan backfills a copy into `staging/plugin/skills/project-conductor/` so the
   roadmap-autopilot patch is versioned here, then syncs. This closes the stale-staging gap for this
   one skill rather than leaving the patch untracked.

---

## Artifact inventory

| # | Path (repo blueprint) | Type | New/Mod |
|---|---|---|---|
| A1 | `staging/plugin/scripts/nightly-guard.sh` | hook script | new |
| A2 | `staging/plugin/scripts/publish-feature.sh` | helper script | new |
| A3 | `staging/project-templates/ci/ci.yml` | CI template | new |
| A4 | `staging/plugin/scripts/set-branch-protection.sh` | helper script | new |
| A5 | `staging/plugin/skills/nightly-autopilot/SKILL.md` | skill | new |
| A6 | `staging/plugin/skills/nightly-autopilot/tests/run-tests.sh` | test harness | new |
| A7 | `staging/plugin/skills/project-conductor/SKILL.md` | skill (backfill + patch) | new-in-repo |
| A8 | `staging/user/settings.json` + `staging/plugin/hooks/hooks.json` | hook wiring | mod |
| A9 | `docs/architecture/ADR-0022-morning-report-schema.md` | schema doc | new |
| A10 | `docs/RUNBOOK-nightly-autopilot.md` | runbook | new |
| A11 | `CLAUDE.md` | ADR summary block | mod |
| A12 | `staging/sync-to-claude.sh` (or documented steps) | sync | new |

---

## Phase 1 — Foundations (independent, no skill dependency)

### A1 · nightly-guard.sh

- Reads JSON on stdin (hook mode) or a `--check <root>` flag (in-script mode).
- Halt conditions: build red after fix cycle; needs-human marker present
  (`<root>/.claude/needs-human`); RTF BLOCKER marker; token budget exceeded (reads a budget-state
  file written by the run).
- On halt: print `NIGHTLY-GUARD HALT: <reason>` to stdout and, in hook mode, emit
  `{"decision":"block","reason":...}`.
- Fail-safe: on malformed input or internal error, BLOCK the publish (opposite of stop-gate's
  fail-open). Allowing an unchecked publish is the dangerous direction here.
- **DoD:** unit tests cover each halt condition, the clean-pass case, and the fail-safe-on-malformed
  case. Bash 3.2-clean (`shellcheck` clean).

### A2 · publish-feature.sh

- Args: `--slug`, `--base main`, `--root <repo>`, optional `--dry-run`.
- Refuses to run if the resolved branch equals `main`, or if the opt-in marker
  `.claude/nightly-autopilot.yml` is absent or `publish: false`.
- Calls `nightly-guard.sh --check <root>` first; aborts on HALT.
- Idempotent: reuse `feat/<slug>` if it exists; detect an open PR via `gh pr list --head feat/<slug>`
  and skip creation if one exists.
- `git push -u origin feat/<slug>` (never `--force`); `gh pr create --base main` (never `--merge`,
  never auto-merge).
- Prints a status line `NIGHTLY-PUBLISH <slug> PR=<url> CI=pending` for the `/goal` evaluator and
  the report.
- **DoD:** dry-run prints intended actions without mutating; a second run creates no duplicate branch
  or PR; refuses on `main`; no code path passes `--force`, `--merge`, or auto-merge.

### A3 · ci.yml + A4 · set-branch-protection.sh

- `ci.yml`: minimal GitHub Actions workflow, one job that runs the project test/build command. The
  command is a placeholder token substituted from the target repo's `.claude/test-cmd` at drop time
  (fallback documented if absent). No secrets for a static build.
- `set-branch-protection.sh`: uses `gh api` to require the CI check and require a PR on `main`.
  Idempotent (re-run leaves protection in the same state).
- **DoD:** `ci.yml` is valid workflow YAML (actionlint clean if available); branch-protection helper
  is idempotent and refuses to weaken existing stricter protection.

---

## Phase 2 — Orchestration

### A5 · nightly-autopilot/SKILL.md

- Pre-flight (read-only, script-level, mirrors autopilot-build's discipline): scope guard; opt-in
  marker present with `publish: true`; TOFU test-cmd trust exists; `hook_verified` known; git repo;
  `gh auth status` OK; CI workflow present or created via A3/A4.
- Prints the `/goal` condition template for the human to paste (D4).
- Invokes `project-conductor` in roadmap-autopilot mode (A7).
- After the roadmap loop, writes the run-level morning report v2.0 (A9) on every exit path.
- **DoD:** harness (A6) green; pre-flight aborts on each missing precondition with a clear reason and
  writes an `aborted` report; no `AskUserQuestion` after pre-flight.

### A7 · project-conductor roadmap-autopilot patch

- Backfill the current `~/.claude` SKILL.md into the repo, then add a `nightly` mode: pre-authorize
  every pending feature as autopilot, skip the per-feature Step 3 gate, amend invariant 303 to scope
  the skip to this mode only.
- After each feature reaches a local commit, call `publish-feature.sh` (A2); the guard (A1) fires;
  print the status line; advance to the next `[ ]`.
- **DoD:** existing conductor behavior unchanged in all other modes; a roadmap-autopilot dry-run over
  a 2-feature fixture skips both Step 3 gates and calls publish once per feature.

### A9 · morning report schema v2.0

- Extends `autopilot-report.json` v1.0 with `publish` (per-feature branch, PR URL, CI status),
  `guard_halts` (reason list), and `spend` (tokens, turns, wall time). Document the schema and a
  filled example.
- **DoD:** schema doc committed; the skill writes a v2.0 report that validates against it.

---

## Phase 3 — Docs

- **A10 · RUNBOOK-nightly-autopilot.md:** the evening recipe (permission mode, paste `/goal`
  template, launch), how to read the morning report, how to abort (`/goal clear` + interrupt), and
  the `allowManagedHooksOnly` / `disableAllHooks` interaction. Passed through `humanize-en`.
- **A11 · CLAUDE.md:** add an ADR-0022 summary block matching the existing pattern.

---

## Phase 4 — Verify

- Skill harness (A6) green.
- Guard fail-safe: force a red build and a missing-input roadmap; confirm HALT, no "ready" PR, report
  names the blocker.
- Smoke test on a throwaway repo: one-feature roadmap, opt-in marker present, run the full recipe;
  confirm implement, commit, push, PR open, status line printed, CI green, nothing merged.
- `/goal` evaluator vs in-flight subagents: confirm no false completion fires mid-dispatch (the one
  assumed-not-verified item from the ADR).

---

## Phase 5 — Sync (HITL-gated)

- **A12 · sync-to-claude.sh:** copies A1, A2, A4, A5, A6, A7 and the hook wiring into `~/.claude/`.
  For every existing target file, show a diff and require explicit approval before overwriting
  (global rule). The CI template and branch-protection helper are dropped into target repos at run
  time, not into `~/.claude`.

---

## HITL gates in this plan

1. Approve this plan before any code is written.
2. Mid-implementation: none required inside a phase; phases are reviewed at their boundary if you want.
3. Before overwriting any `~/.claude` file in Phase 5: show diff, approve.
4. Before the commit that lands this work: the standard `commit` skill HITL gate.
5. The smoke test needs a human to read the terminal, same discipline as the `hook_verified` gate.

---

## Order and dependencies

Phase 1 is independent and comes first. Phase 2 depends on A1/A2/A3/A4. Phase 4 depends on Phase 2.
Phase 5 is last and gated. A11 (CLAUDE.md) and A9 (schema) can land anytime after their referents
exist.

---

## Open risks carried from the ADR

- `/goal` evaluator behavior around in-flight background shells and delegated subagents is
  assumed-not-verified; isolated to the Phase 4 smoke test.
- A green test suite on a wrong implementation still produces a pushed, PR-open result; the human's
  morning merge review is the checkpoint (auto-merge is absent by design).
- Bypass permission mode overnight is a real surface, bounded by the deny list, the guard, hooks left
  enabled, and the per-repo opt-in.
