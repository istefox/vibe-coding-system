# ADR-0188 — Autopilot fork point when no prep branch is created

- **Status:** Accepted
- **Date:** 2026-09-02
- **Related:** ADR-0127 §D4 (the fork-point mechanism this closes a gap in, and Finding 2, which this
  ADR narrows rather than reverses), ADR-0022 (roadmap and specs must pre-exist without prep), issue
  #364 (the original stacking defect), issue #474, issue #401 (`TODO.md` `VCS-017`, closed into it).

## Context

ADR-0127 §D4 decided every autopilot feature branch forks from one run-scoped ref, recorded as
`$_prep_ref` by `autopilot/SKILL.md` §1.5 Phase P step 4 and handed to `project-conductor
--fork-from`. The mechanism assumes step 4 always runs and always records a ref. It does not.

`$_prep_ref` is assigned in exactly one place, and that place only executes when a prep branch is
actually created. Two conditions both skip it, by different routes, filed as two issues:

- **#474** — no `prep:` block in `.claude/autopilot.yml` at all: Phase P's steps are a no-op, and
  step 4 (bundled with the rest of the phase, textually) never runs.
- **#401** (`VCS-017`) — a `prep:` block present, but steps 1-3 all skip because their outputs
  already exist: nothing to commit, so whether step 4 creates a branch, pushes it, or defines
  `$_prep_ref` was unspecified.

Either way `§3.3` still interpolates `--fork-from <$_prep_ref>` unconditionally. `conductor-args.sh`
returns `fork_from=` empty (a deliberately preserved behaviour — `--fork-from` with nothing after it
has never crashed the parser). The fork-point fence's `INACTIVE` arm takes over: *"no --fork-from;
HEAD is used as-is (attended behaviour)"*, exit 0, run continues. In a roadmap-autopilot run the
conductor advances feature by feature in one checkout, so HEAD **is** the previous feature's tip —
the exact stacking §D4 exists to remove. Nothing downstream compares a branch's base to the intended
one, so the first evidence is a PR whose diff contains the previous feature.

### Measured before designing (rule 13)

The behaviour was reproduced, not inferred from reading the fences:

- `conductor-args.sh autopilot` (no `--fork-from`) prints `fork_from=` empty at rc 0; the fence body
  with an empty `_fork_from` printed `FORK-POINT: INACTIVE` and exited 0 — the composition #474
  describes is real, not hypothetical.
- **No run in this repository's history has ever had a `prep:`-absent marker.** All three tracked
  versions of the marker (2026-07-11 as `.claude/nightly-autopilot.yml`, 2026-08-05 rename, working
  tree) carry a `prep:` block, and no `autopilot/prep-*` branch has ever existed locally or on
  origin — #474's scenario, specifically, is unmeasured by an actual run.
- **Both recorded runs took #401's route, and both were resolved by hand at the console with the
  same answer.** The 2026-08-14 run report records `"prep_ref": "main"`, noting *"Phase P selected
  zero rows … so no prep branch was created and main is the fork point."*
  `docs/AUTOPILOT-RUN-AUDIT-2026-08-08.md` finding F8 records the same situation on 2026-08-07/08:
  *"The orchestrator used `main` as the fork point and recorded that; the skill does not sanction
  it."*

So this ADR does not invent a policy. It sanctions in the skill the answer two real runs already
reached by hand, and adds the mechanism that holds it when nobody is watching.

## Decision

### D1 — Phase P step 4 always yields a fork ref

`autopilot/SKILL.md` §1.5 step 4 now runs unconditionally — not skipped when there is no `prep:`
block, and not left undefined when steps 1-3 all skip. Both routes converge on one clause: **when no
prep branch is created, `$_prep_ref` resolves to the default branch**, via the same cascade
`commit/SKILL.md` Step 3.6 already defines (`git symbolic-ref refs/remotes/origin/HEAD` → `git
remote set-head` → `gh repo view` → local `main`/`master` → `"main"`) — never a second, hardcoded
copy. No prep branch is created in this case; `commit` is not invoked for step 4 at all, since an
empty staged set would only reach its own "Nothing to commit" stop.

**This narrows ADR-0127 Finding 2 rather than reversing it.** Finding 2 ruled out `main` as the fork
point in general because Phase P writes `PROJECT.md`, SPECs and `_issue-map.tsv` into the working
tree before any branch exists, stranding them on whichever feature commits first. That objection
requires Phase P to have generated something. **When no prep branch is created, steps 1-3 generated
nothing** — under ADR-0022, the prep-absent behaviour, or under the all-skipped condition, the
outputs already existed and are already committed on the default branch. There is nothing for a
later feature to miss, so the general prohibition does not extend to this specific, narrower case.

This closes #474 and #401 (`VCS-017`) with one change, because they are the same defect — an
undefined `$_prep_ref` — reached by two different reasons for step 4 not running.

**This deliberately contradicts #401's stated success criterion R-03** ("the `prep:`-absent no-op
path is untouched"), which rested on the premise that `INACTIVE` — HEAD-as-is — is a benign no-op
for that case. It is not: under an unattended roadmap run it is a silent wrong base, which is
exactly #474's finding. R-03's premise is superseded by measurement, not honoured.

### D2 — The fork-point fence refuses an empty ref under autopilot

D1 is an instruction a model is asked to follow, and an instruction is not an enforcement (rule 16).
The `<!-- fence-contract: conductor-fork-point -->` fence in
`project-conductor/references/steps-4-7-chain-execution.md` is the backstop: it already receives
`_autopilot` from the same orchestrator-bound state every adjacent block in that file reads, so no
new binding was introduced — only a new arm.

- **`_autopilot=true` and `_fork_from` empty → `FORK-POINT: DID-NOT-RUN`, exit 3.** Run-level halt,
  same as every other exit-3 arm in this fence — `needs-human`, per the paragraph immediately below
  it, unchanged.
- **`_autopilot` unset or `false` and `_fork_from` empty → `FORK-POINT: INACTIVE`, exit 0,
  unchanged.** The attended path is byte-identical; this is what a human working in their own
  checkout legitimately wants, and it is the case the fence's own comment already named "attended
  behaviour."
- A resolvable `--fork-from` behaves identically regardless of `_autopilot`, in both directions —
  hand-probed live across all four combinations (below), not merely reasoned about.

A well-formed autopilot run never reaches the new arm, because D1 makes step 4 always produce a ref.
The arm exists for when D1's instruction is not followed — the gap that let #474 and #401 both stay
invisible for as long as they did, since `FORK-POINT: INACTIVE` is not an error and every feature
branch was still created successfully, simply from the wrong place.

### D3 — Out of scope, deliberately deferred

**A post-hoc check that each feature branch's merge-base actually is the intended ref** — #474's own
third open question — is not built here. It is a different mechanism, on the publish path rather
than the fork path, and needs its own producer/consumer decision. D1 and D2 together already close
the hole such a check would detect (an undefined ref can no longer reach `commit --branch` silently),
so a second, independent detector is not required to ship this. Recorded here as a decision, not an
omission — a future issue may still want it as defense in depth.

## Verification

- The composition described by #474 was reproduced directly, both before the fix (`INACTIVE`, exit
  0, on an empty ref) and after (all four `_autopilot` × `_fork_from` combinations hand-probed
  against a real fence extraction in a throwaway git repo — `DID-NOT-RUN`/3 only for
  `autopilot=true` + empty ref, every other combination unchanged).
- `staging/plugin/scripts/tests/conductor-entry-failure-split.test.sh`: four new assertions inside
  the existing `FK11`…`FK15` block — `FK16` (autopilot + empty ref refuses), `FK17` (attended + empty
  ref stays `INACTIVE`, asserted explicitly rather than only by omission), `FK18` (autopilot + a
  resolvable ref still forks correctly, guarding against the new arm swallowing the normal path),
  `FK19` (Phase P step 4's prose states the no-prep-branch fork ref). The `awk` extraction needle
  `fence-contract: conductor-fork-point -->` — the string `fence-contract-coverage.test.sh` F4 reads
  as this fence being executed — was left unchanged. `Z1` floor raised 64 → 68.
- Both new `# plant:` declarations (`FK16` on the new autopilot condition, `FK19` on the new prose
  clause) were hand-verified RED before being trusted, source files restored byte-identical
  afterward (`diff -q` against a pre-mutation backup).
- `bash staging/plugin/scripts/tests/conductor-entry-failure-split.test.sh` — 69/69 (68 + `Z1`).
- Regression, all green: `fence-contract-coverage.test.sh` (67/67, `F3`/`F4` unaffected for
  `conductor-fork-point`), `autopilot-run-scope.test.sh` (62/62),
  `skill-fence-positional-tokens.test.sh` (12/12), `recovery-preflight.test.sh` (88/88).
- Full repo-wide `plant-check.sh` sweep: **PASS=675 FAIL=0** — `PC1` 667/667 declared plants fired,
  `PC2`-`PC5b` clean. (First sweep caught a real defect in the `FK19` plant itself: the needle
  omitted the closing backtick present in the actual source line, so it matched zero times rather
  than the required one — fixed, re-verified RED by hand, re-swept clean.)
- No `.github/workflows/docs-ci.yml` or `sync-to-claude.sh` `PAIRS` edit needed: the harness and the
  script under test are both already registered, and plants are discovered by scanning.

## References

- `staging/plugin/skills/autopilot/SKILL.md` — §1.5 step 4, and its opening sentence
- `staging/plugin/skills/project-conductor/references/steps-4-7-chain-execution.md` — the
  `conductor-fork-point` fence
- `staging/plugin/skills/commit/SKILL.md` — Step 3.6, the default-branch detection cascade reused
- `staging/plugin/scripts/tests/conductor-entry-failure-split.test.sh` — `FK16`-`FK19`
- `docs/architecture/ADR-0127-363-364-365-autopilot-long-session-runner.md` — §D4, Finding 2
- `.claude/autopilot-report.json` (2026-08-14 run, gitignored) — the `prep_ref: "main"` record this
  ADR sanctions
- `docs/AUTOPILOT-RUN-AUDIT-2026-08-08.md` — finding F8, the un-sanctioned hand decision this ADR
  formalizes
