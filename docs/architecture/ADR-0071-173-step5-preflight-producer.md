# ADR-0071 — Gate 4.0: the chain commits its own planning artifacts

- **Status:** Accepted
- **Date:** 2026-07-29
- **Closes:** issue #173
- **Amends:** ADR-0050 (the recovery-readiness pre-flight, whose entry state now has a producer),
  ADR-0020 (`autopilot-build`'s documented entry contract)
- **Reported as:** a live chain failure on the first end-to-end run in an external project.

## Context

ADR-0050 added four assertions at the top of `concept-to-code` Step 5. The first two require a clean
working tree and a feature branch. Both are right. Neither had a producer.

`git checkout -b` appeared in `concept-to-code/SKILL.md` exactly once — inside 5.0.2's own error
message. No step between Gate 0 and Step 5 created a branch, and no step committed the planning
artifacts. Steps 1–3 always write `SPEC.md`, the ADR, the plan and the manifest, and the chain always
starts wherever the user happened to be, so **every first run of the chain failed the pre-flight**.
Structurally, not situationally.

The second half is worse than the first. 5.0.1 printed:

> Run `git stash push -u -m 'c2c-step5-preflight'` (or commit) and re-invoke Step 5.

`git stash push -u` would stash `SPEC.md`, the ADR and the plan — precisely what the coder and
tester dispatches read. Following the instruction produces a Step 5 that dispatches against missing
inputs. The parenthetical "(or commit)" was the correct action and the weaker half of the sentence.
On the unattended path there is no leniency branch (ADR-0050 §D6), so `autopilot-build` halts and
files an `aborted` report whose recommended action would break the run if taken.

The live run reached Step 5 only because the model overrode the printed instruction — branched,
committed behind a HITL gate, and continued. That was judgement, not something the skill directed.

## Decision

### D1 — The chain produces the state, at Gate 4, in a step named once

**Gate 4.0**, defined once and referenced by every path that proceeds past Gate 4: the autopilot
bypass, "Implement now (autopilot, this session)", and "Confirmed — I will /clear and resume".
**Not** by "Abort chain" — an aborted chain must not leave a commit behind.

Gate 4 is the right place because it is the last point at which the old session can act, and exactly
where the fresh session's assumptions begin. The `/clear` + `resume` handoff currently ends with a
dirty tree on whatever branch the user was on; the fresh session opens at Step 5 and asserts the
opposite. Committing here makes 5.0.1 and 5.0.2 satisfied by construction rather than by luck.

### D2 — It invokes the `commit` skill; it never hand-rolls git

`commit`'s Step 3.6 creates the feature branch and structurally refuses to commit to the default
branch. Its Step 4 is the HITL gate. Its `--autopilot` covers the unattended path. Step 7 of this
chain already invokes it. Writing a dedicated branch-and-commit here would create a second commit
path that drifts from the first — the defect ADR-0069 had just finished removing from the plan-task
predicate, reproduced in a new place.

Test `RH4b` forbids raw `git checkout -b` / `git commit` / `git add` inside the Gate 4.0 block, so
the delegation cannot be quietly replaced by an inline shortcut.

A local commit is inside ADR-0020's autonomy boundary already, so the unattended form changes no
boundary. Nothing is pushed.

### D3 — 5.0.1's remediation branches on WHAT is dirty

The two cases pull in opposite directions and the old text prescribed the wrong one for the only
case that ever occurred:

- **A chain artifact is uncommitted** → commit. Never stash: `-u` would take the coder's inputs.
- **Only unrelated files are dirty** → stash. This is ADR-0050 §D2 negative consequence 2, the
  deliberately-dirty resume, and it is preserved unchanged.
- **Both** → commit first, then stash, and say why: committing the artifacts is what makes the stash
  safe.

The decision is made by intersecting `git status --porcelain` with the manifest's own artifact
paths, so the skill can tell the cases apart rather than declaring that it cannot.

`RH11` asserts the unrelated-file case survives. A fix that narrows a behaviour must not delete it.

### D4 — `--no-pr` on the `commit` skill

Gate 4.0 has nothing to publish: implementation has not started. Without a flag, every chain run
would be asked to open a PR at the session boundary and every user would answer No.

`--no-pr` skips Steps 6, 6b, 6c and 7 — PR, CI watch, diagnosis, merge — and **leaves the Step 4
approval gate intact**. That is the whole difference from `--autopilot`, which skips the approval and
skips Step 6 as a side effect. The two are orthogonal and combine. Stated in the skill's Arguments
section *and* at Step 6 itself, because a reader following the numbered steps does not re-read the
header; `RH8`/`RH9` pin both.

Extending a skill that is not the subject of this issue was a deliberate call: the alternative is a
recurring prompt on every chain run, which is friction that compounds.

### D5 — `autopilot-build`'s entry contract is corrected, not just its behaviour

Its prerequisites said "SPEC.md, ADR, and plan exist on disk". Its Phase 0 hands off to a pre-flight
that requires them committed on a feature branch. The two disagreed and the contract was the wrong
one. It now names the committed state and points at Gate 4.0 as its producer.

## Alternatives considered

### A — An entry contract on Step 5: the caller creates the branch and commits

Rejected. It pushes the same rule onto three callers — `autopilot-build`, `nightly-autopilot`, and
the human — which is three implementations of one decision, the exact shape issue #172 had just been
filed about. It also leaves the attended first run with nothing producing the state, so the human
still has to invent the remediation the skill failed to prescribe: acceptance criterion 1 unmet.

### B — Relax the pre-flight to tolerate uncommitted chain artifacts

Rejected. ADR-0050's assertions are what make `recovery_baseline_sha` meaningful and what let
ADR-0068 §D5's merge-back protocol attribute each stage's output. Tolerating a dirty tree at Step 5
entry means every later "is this Step 5's own doing" question loses its baseline. The issue itself
says the pre-flight should stay strict, and it is right.

### C — Commit at Gate 3 approval instead of Gate 4

Rejected as too early by one gate. Gate 3 applies `CLAUDE.md`; Gate 4 is where the chain decides
whether it is crossing a session boundary at all, and where "Abort chain" still exists. Committing
at Gate 3 would leave a commit behind for a chain the user then aborts.

## Consequences

### Positive

- A chain run from Step 1 reaches dispatch without the human inventing a remediation.
- `recovery_baseline_sha` points at a commit that actually contains the planning artifacts. Before
  this it recorded a state that had never been committed — a baseline describing something that did
  not exist.
- One commit path in the system, not two.
- The unattended paths stop aborting on a correct chain.

### Negative

- **The feature branch's first commit is documentation-only**, and a chain abandoned during Step 5
  leaves a branch carrying a design commit and nothing else. Cheap and reversible, and the price of
  a baseline that means something.
- Gate 4.0 adds one HITL gate to the attended flow — the `commit` skill's own. It is an approval the
  chain previously took implicitly by leaving the artifacts uncommitted, so it is a gate appearing
  where a decision already existed, not a new decision.
- `--no-pr` widens a skill this issue does not otherwise touch. `commit/SKILL.md` still has no test
  harness of its own (noted in ADR-0046); `RH7`–`RH9` here are the first assertions that read it.

### Neutral

- No manifest field, no schema bump, no state-machine change. Gate 4.0 runs before the existing
  `step_4_session_boundary → ready_for_implementation` transition on every path that takes it.
- Inert until sync.

## References

- Issue #173, including the two candidate directions and the acceptance criteria
- `docs/architecture/ADR-0050-104-recovery-readiness-preflight.md` §D2, §D3, §D6
- `docs/architecture/ADR-0020-autopilot-build-skill.md` — the autonomy boundary that already
  contains a local commit
- `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` §D5 — the merge-back protocol that
  needs the feature branch Gate 4.0 creates
- `staging/plugin/scripts/tests/recovery-preflight.test.sh` section RH

## Clarification 2026-07-30 — §D2's scope includes STAGING, not only committing

Nothing here changes. This records where the answer already lives, because the answer was misread
by the one person who had just run the chain end to end, four hours after doing so.

**§D2 forbids `git add` inside the Gate 4.0 block, not merely `git commit`.** The prose says "it
never hand-rolls git", which reads to some as a prohibition on committing with staging left open.
It is not: `recovery-preflight.test.sh`'s **`RH4b`** greps the Gate 4.0 block for
`git (checkout -b|commit|add)` and fails on any of the three. The decision was made and enforced;
only its statement was easy to read narrowly.

**Why the strict reading is right on its merits, not only by precedent.** `commit`'s Step 1 owns
the file-scope decision — which paths are included, which are listed as excluded-untracked, and
what the secret scan's union covers. A caller that stages first hands `commit` a pre-staged set,
and Step 1's own rule ("Something already staged → included set = `staged` only") then defers to
it. That puts the scope decision in two places, which is exactly the "two implementations of one
decision" §D2 exists to prevent and the shape issue #172 was filed about. Under `--autopilot`,
where Step 4 never renders the set to a human, the divergence would also be invisible.

**Consequence for issue #234, which this determines.** Gate 4.0 cannot commit the planning
artifacts because they are untracked and `commit` never stages untracked outside its Step 4
"Stage additional files" path — which `--autopilot` skips entirely. Given the above, the fix
**must be a `commit`-side mechanism** (an explicit include-these-paths argument, honoured under
`--autopilot`), and **must not** be a `git add` in Gate 4.0. That alternative is closed here rather
than re-argued when #234 is picked up.

`RH4b`'s failure message is sharpened in the same change to name staging, since that message is
what a reader actually meets when they hit the rule.
