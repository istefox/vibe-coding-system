# RUNBOOK — autopilot (overnight roadmap-to-PR)

The evening recipe to run a roadmap unattended and wake up to PR-ready branches. Read ADR-0022 for
the why. This is the how.

**End state by morning:** each roadmap feature on its own `feat/*` branch, pushed, with an open PR to
`main` and CI green. Nothing merged. A morning report at `.claude/autopilot-report.json`. On trouble,
the guard halts and the report says what blocked it.

---

## Two modes

- **Pre-designed roadmap** (ADR-0022): you already wrote `PROJECT.md` and each feature's SPEC/ADR.
- **Auto-design from issues** (ADR-0023): the run generates `PROJECT.md`, per-feature specs, and the
  design itself from a labeled GitHub backlog. Add a `prep:` block to the opt-in marker (below).

## One-time setup per target repo (the irreducible bootstrap)

Two of these cannot be automated by design invariant (a self-approving system is forbidden). After
this one-time bootstrap, every night is fully automatic.

0. **`/checkup` (optional, recommended).** From CC 2.1.205 `/doctor` is a full setup checkup that can
   diagnose and fix issues, with `/checkup` as its alias. Run it once before the bootstrap: a broken
   hook path or an unauthenticated `gh` surfaces here cheaply, rather than at 2 a.m. as a halted run.
   Not a launch precondition — the pre-flight checks below stay the primary control.

1. **`gh auth login`.** Once per machine (needed to push and open PRs).

2. **Opt in.** Create `.claude/autopilot.yml` in the target repo. For auto-design, add the
   prep source:
   ```yaml
   publish: true
   prep:
     source: issues
     issues_label: release-blocker
   ```
   Absent or `publish: false` means the run stops at a local commit (same as `autopilot-build`). No
   `prep:` block means the roadmap and specs must pre-exist. This marker is committed to the repo, so
   the opt-in is auditable in its history.

3. **Trust the test command.** In auto-design mode the run's Phase P writes `.claude/test-cmd` from
   stack detection, so you only review it and run the trust command once:
   ```
   bash ~/.claude/hooks/approve-test-cmd.sh "<repo>"
   ```
   `autopilot` never grants trust itself. Re-run this if you later edit `.claude/test-cmd`.

4. **Verify hooks fire once.** Confirm `hook_verified` is set (true or false, not null). The default
   `false` runs on the safe Agent-tool fallback; the Step-5 smoke test in a fresh session promotes it
   to `true` (optional, unlocks the faster Workflow dispatch).

5. **CI.** On first run the skill drops `.github/workflows/ci.yml` (parameterized by your
   `.claude/test-cmd`) and sets branch protection on `main` (require the `ci` check, require a PR).
   Nothing to do by hand if `gh` has admin on the repo.

### Auto-design flow (what Phase P does)

Reads the labeled issues, writes `PROJECT.md` (one feature per issue) + `docs/specs/_issue-map.tsv`,
and generates `docs/specs/<slug>.spec.md` per issue. A thin or vague issue is skipped (marked `[~]`
with a `needs-human` note in the report), never fabricated. Downstream the design chain runs headless:
architect writes the ADR + plan, the feature is implemented, and the generated SPEC + ADR are
committed inside the feature PR for you to review at merge.

---

## The evening launch (every night)

From inside the target repo. In pre-designed mode `PROJECT.md` already holds the roadmap; in
auto-design mode you only need the labeled issues and the `prep:` marker (Phase P builds the rest):

1. **Set `bypassPermissions`** — the only mode under which no per-tool prompt can fire:
   ```
   claude --permission-mode bypassPermissions
   ```
   Or Shift+Tab to it and read the mode off the status line, or set `permissions.defaultMode` in
   `~/.claude/settings.json` for the durable default.

   **`/permissions` does NOT set the mode.** It manages allow/ask/deny rules; hooks are a third
   axis it does not touch. This step said otherwise until issue #339.

   **`acceptEdits` is accepted by the pre-flight but is not the same guarantee.** It auto-accepts
   *edits*; a Bash command outside `permissions.allow` still prompts, and the chain's Bash surface
   (`bash ~/.claude/skills/*/scripts/manifest-*.sh`, `sed`, `awk`, `mkdir`, `git push`,
   `gh pr create`, the project's test-cmd) is not in a default allowlist. Use it only if you have
   checked that yours covers all of it.

   The prompts go, the guardrails stay: `stop-gate`, `pre-flight-pattern-enforce`,
   `protect-files`, `db-backup-guardrail`, `write-scope-enforce`, `agent-write-scope`,
   `agent-command-scope` and `autopilot-guard` all still fire, and a hook deny overrides any
   permission mode (ADR-0022).

2. **Set the outer loop.** Paste the `/goal` template (the skill also prints it). Fill in the turn
   budget:
   ```
   /goal "Every feature in PROJECT.md is [x], committed on feat/*, pushed, and a PR is open,
   as shown by a AUTOPILOT-PUBLISH line for each feature and no AUTOPILOT-GUARD HALT line.
   Or stop after 200 turns."
   ```

3. **Launch:**
   ```
   /skill autopilot
   ```

4. Walk away.

`/goal` is the keep-alive: it re-checks the condition after each turn and starts another if unmet. It
reads only what the run prints to the transcript, which is why the publish step emits a
`AUTOPILOT-PUBLISH` line per feature and the guard emits `AUTOPILOT-GUARD HALT` on a stop.

**Auth freshness (CC 2.1.203+).** A long overnight run can outlive your Claude Code login. From CC
2.1.203 the CLI warns before the login expires, but that warning is interactive and does not keep an
unattended run alive on its own. Confirm your login is current right before you walk away — a recent
interactive `claude` session is enough. An expired login mid-run halts the remaining features, which
then show unpublished in the morning report.

**Destructive-command stalls (CC 2.1.208+).** Even in bypass mode, a catastrophic removal wrapped
in `$(…)`, backticks, or `<(…)` now raises a permission prompt instead of executing. Overnight
nothing answers it, so the run stalls there, which is the safe direction. The `/goal` turn budget
is the backstop, the affected feature shows unpublished in the morning report, and a
`claude agents` peek shows the exact pending ask. No pre-flight change needed.

---

## Reading the morning report

`.claude/autopilot-report.json` (schema v2.0). Look at:

- `status`: `success` (all features published), `partial` (some halted), `aborted` (pre-flight
  failed, nothing ran).
- `features[]`: per feature, the `pr_url`, `ci_status` (`green`/`pending`/`red`), and `guard_halt`.
- `guard_halts[]`: what stopped, and why.
- `spend`: tokens, turns, wall time.
- `next_action`: the one-line instruction.

Then open the green PRs and merge the ones you are happy with. One click each. Nothing was merged for
you.

**Cross-checking against `claude agents` (CC 2.1.205+).** The agent list is a useful second view on
the night. Each row now carries a colored state word and a short written headline instead of raw tool
call text, and opening a blocked session shows the exact ask. PRs opened by the run are linked there
too, including one created by a `gh pr create` whose Bash output ran past the 30K inline limit — that
case used to go unlinked. Treat this as convenience: `autopilot-report.json` and the `AUTOPILOT-PUBLISH`
lines in the transcript are the authoritative record.

---

## Aborting a run

- Clear the goal: `/goal clear`.
- Interrupt the session (Esc / stop) to end the current turn.
- The working tree and whatever was already committed and pushed are intact. No feature is left
  half-merged into `main`, because the run never merges.
- **There is one thing left to do: disarm the guard.** Stopping the session skips Phase 2, which is
  the only step that clears the run's state, so the guard stays armed and will keep refusing
  publishes in your own later sessions. See the next section.

  ```bash
  bash ~/.claude/hooks/autopilot-disarm.sh "$PWD"
  ```

---

## The guard is still armed and I cannot push

Symptom: `AUTOPILOT-GUARD HALT: ...` on a push, a PR, or a merge — in an ordinary session, with no
autopilot run going on. The guard keys off `.claude/autopilot-state/active`, and a run that was
interrupted, crashed, or ran out of context never reached the step that removes it.

The fix, from the repo root:

```bash
bash ~/.claude/hooks/autopilot-disarm.sh "$PWD"
```

It prints what it cleared. Exit codes: `0` cleared (or nothing was armed), `1` refused because the
marker belongs to *this* session — a run does not disarm itself through the recovery path — `2` bad
arguments, `3` it could not look, which is **not** the same as "nothing was armed" and means you are
still blocked.

**The bare form above is your command. `--completing` is not.** That flag is the mirror of this one:
it is how `autopilot` Phase 2 clears the state of the run it is itself ending, so it accepts
the owning session and refuses everyone else. Passing it by hand to clear somebody else's stale
marker will be refused, and correctly — you are not that run.

It clears the whole transient set, because the marker is only one of five ways to be stuck:

| file | what it does while present |
| --- | --- |
| `.claude/autopilot-state/active` | arms the guard; alone it blocks only merges, force-pushes, `--no-verify` and pushes to `main` |
| `.claude/autopilot-state/build-status` reading `RED` | halts every publish, marker or not |
| `.claude/needs-human` | halts every publish, and prints its first line as the reason |
| `.claude/autopilot-state/rtf-blocker` | halts every publish |
| `.claude/autopilot-state/token-budget` with `spent >= limit` | halts every publish |

When the marker was armed by another session, the halt message names the owner, the time, and this
command — so you should not need this page twice.

To check without changing anything: `cat .claude/autopilot-state/active`. An empty file is a marker
from before this was recorded; that is normal for old runs and the disarm handles it.

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
