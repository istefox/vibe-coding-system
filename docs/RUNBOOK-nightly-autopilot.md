# RUNBOOK — nightly-autopilot (overnight roadmap-to-PR)

The evening recipe to run a roadmap unattended and wake up to PR-ready branches. Read ADR-0022 for
the why. This is the how.

**End state by morning:** each roadmap feature on its own `feat/*` branch, pushed, with an open PR to
`main` and CI green. Nothing merged. A morning report at `.claude/nightly-report.json`. On trouble,
the guard halts and the report says what blocked it.

---

## One-time setup per target repo

1. **Opt in.** Create `.claude/nightly-autopilot.yml` in the target repo:
   ```yaml
   publish: true
   ```
   Absent or `publish: false` means the run stops at a local commit (same as `autopilot-build`). This
   marker is committed to the repo, so the opt-in is auditable in its history.

2. **Trust the test command.** Run the interactive chain once so the TOFU `(hash, root)` pair for
   `.claude/test-cmd` is registered. `nightly-autopilot` never grants trust itself.

3. **Verify hooks fire once.** Confirm `hook_verified` is set (true or false, not null) in the
   roadmap's manifests. The smoke test in a fresh session establishes this.

4. **CI.** On first run the skill drops `.github/workflows/ci.yml` (parameterized by your
   `.claude/test-cmd`) and sets branch protection on `main` (require the `ci` check, require a PR).
   Nothing to do by hand if `gh` has admin on the repo.

---

## The evening launch (every night)

From inside the target repo, after the design gate is done and `PROJECT.md` holds the roadmap:

1. **Set a non-blocking permission mode** so no per-tool prompt fires overnight:
   ```
   /permissions        # choose acceptEdits (or bypass for a fully hands-off run)
   ```

2. **Set the outer loop.** Paste the `/goal` template (the skill also prints it). Fill in the turn
   budget:
   ```
   /goal "Every feature in PROJECT.md is [x], committed on feat/*, pushed, and a PR is open,
   as shown by a NIGHTLY-PUBLISH line for each feature and no NIGHTLY-GUARD HALT line.
   Or stop after 200 turns."
   ```

3. **Launch:**
   ```
   /skill nightly-autopilot
   ```

4. Walk away.

`/goal` is the keep-alive: it re-checks the condition after each turn and starts another if unmet. It
reads only what the run prints to the transcript, which is why the publish step emits a
`NIGHTLY-PUBLISH` line per feature and the guard emits `NIGHTLY-GUARD HALT` on a stop.

---

## Reading the morning report

`.claude/nightly-report.json` (schema v2.0). Look at:

- `status`: `success` (all features published), `partial` (some halted), `aborted` (pre-flight
  failed, nothing ran).
- `features[]`: per feature, the `pr_url`, `ci_status` (`green`/`pending`/`red`), and `guard_halt`.
- `guard_halts[]`: what stopped, and why.
- `spend`: tokens, turns, wall time.
- `next_action`: the one-line instruction.

Then open the green PRs and merge the ones you are happy with. One click each. Nothing was merged for
you.

---

## Aborting a run

- Clear the goal: `/goal clear`.
- Interrupt the session (Esc / stop) to end the current turn.
- The working tree and whatever was already committed and pushed are intact. No feature is left
  half-merged into `main`, because the run never merges.

---

## Hooks and `/goal`

`/goal` needs hooks enabled. Its evaluator is part of the hooks system. It is unavailable when
`disableAllHooks` is set at any level, or when `allowManagedHooksOnly` is set in managed settings, and
it tells you so. Keep hooks on. The guard and the safety hooks (`stop-gate`, `pattern-enforce`,
`protect-files`, `db-backup`) all run throughout.

---

## What the machine will never do

No auto-merge. No force-push. No `--no-verify`. No direct commit or push to `main`. The relaxation is
opt-in per repo (the marker), never global. A halt leaves the PR not-ready so nothing broken looks
mergeable.
