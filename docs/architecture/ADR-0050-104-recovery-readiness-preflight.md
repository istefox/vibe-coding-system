# ADR-0050 — Recovery-readiness pre-flight for concept-to-code Step 5

- **Status:** Accepted
- **Date:** 2026-07-26
- **Issue:** #104 (fifth feature of PROJECT.md Phase 2)
- **SPEC:** `SPEC.md` / `docs/specs/104-recovery-readiness-preflight.spec.md`
- **Builds on:** ADR-0049 (#103) — the two dirty-tree conditions introduced there and here are
  adjacent, opposite, and both correct. §D4 is the whole reason this ADR is not a one-liner.
- **Closes:** gap **G-13** of `docs/books/INTEGRATION-REPORT-agentic-spec.md` (PARTIAL, P2).

## Context

The external agentic spec puts recovery readiness **first** in its Prevent ordering (§1.4, §5.2 gate
G0): you must be able to get back to a known state before you take a risk, because a rollback target
you did not record in advance is not a rollback target.

Three skills in this system already do this. `deep-refactor/SKILL.md:118` records a baseline commit
hash at Step 0.3 and checks for a dirty tree at Step 0.7. `review-triage-fix/SKILL.md:158` has a
stale-worktree pre-check. `autopilot-build` runs eight pre-flight checks, git-repo presence among
them.

`concept-to-code` standard Step 5 — the path that dispatches the most agents, in parallel, with the
widest write scope in the system — has none of it. It dispatches coders with no assertion that the
tree is clean, that a recoverable checkpoint exists, or that a feature branch rather than `main` is
checked out. The most dangerous step has the weakest entry condition.

## Decision

### D1 — Three assertions, at the top of Step 5, before any dispatch

1. **Working tree clean.** `git status --porcelain` empty, or the changes explicitly stashed by the
   operator.
2. **A feature branch is checked out**, not the default branch. Resolved via
   `git symbolic-ref --short HEAD` against the remote's default, so a repo whose default is
   `master` or `trunk` is handled without a hardcoded name.
3. **HEAD sha recorded** as the recovery baseline.

### D2 — Failure refuses to dispatch and names the exact remediation command

Not a warning. Step 5 is where unattended agents get write access; a warning nobody reads on an
autopilot path is indistinguishable from no check. The refusal prints the literal command that
fixes it (`git stash push -u -m …`, `git checkout -b feat/<slug>`), because a gate that reports a
problem without naming its remedy converts an unattended run into a morning of archaeology.

### D3 — `recovery_baseline_sha` is an additive manifest field

No schema version bump — the fifth additive extension on the same terms as `step5_mode`,
`hook_verified`, `checkpoint_reviews` and `tests_written_by`. `manifest-validate.sh` treats it as
conditional-if-present, so every pre-ADR-0050 manifest stays valid with no migration.

It is written **once**, at pre-flight, and never rewritten by a later step. A baseline that moves is
not a baseline.

### D4 — The two dirty-tree conditions are sequential, not contradictory. Do not reconcile them.

ADR-0049 §D2 says: dirty tree → `isolation: "none"`, tolerate it. This ADR says: dirty tree →
refuse to dispatch. Read side by side they look like a direct contradiction, and a future reader
**will** try to collapse one into the other. They must not.

They guard different boundaries and run at different times:

- **This pre-flight guards entry to Step 5.** It runs before anything in Step 5 has executed. At
  that moment a dirty tree is uncommitted human work of unknown provenance, and forking agents over
  it risks losing it. Refuse.
- **ADR-0049's check guards each coder dispatch inside Step 5.** By then the tester has
  deliberately written failing tests, so the tree is dirty *by design and by this system's own
  hand*. A worktree coder would fork past exactly the tests it must make green. Tolerate, and drop
  to `isolation: "none"`.

The invariant that reconciles them: **at Step 5 entry the tree is clean; every dirty tree observed
after that point was produced by Step 5 itself.** The pre-flight is what makes ADR-0049's tolerance
safe — without it, `isolation: "none"` would be silently forking over a human's uncommitted work.
Removing either one breaks the other's premise.

### D5 — Copy `deep-refactor` Step 0.3/0.7, do not invent a second idiom

The issue asks for this explicitly and it is the right call: `git rev-parse HEAD` for the baseline,
`git status --porcelain` for the dirty check, same variable naming (`BASELINE_COMMIT`,
`DIRTY_TREE`). A second idiom for the same check is how `autopilot-build`'s restatement of c2c's
isolation rule went stale in the first place (ADR-0049 §D5).

### D6 — Autopilot paths refuse identically

No leniency for `autopilot: true`. An unattended run is the case where a lost tree is least likely
to be noticed, so the unattended path gets the same refusal, recorded in the report rather than
prompted.

## Alternatives rejected

- **A1 — Warn and continue.** Rejected under §D2: indistinguishable from no check on the unattended
  path, which is the path that needs it.
- **A2 — Auto-stash on the operator's behalf.** Rejected: this system does not silently move a
  human's uncommitted work, and an auto-stash that a later step forgets to pop is a new way to lose
  it. Name the command; let the human run it.
- **A3 — Reuse ADR-0049's dirty-tree condition instead of adding a second one.** Rejected; see
  §D4. This is the alternative most likely to be re-proposed, which is why §D4 is written at length.
- **A4 — Enforce in `manifest-transition.sh`.** Rejected on the blast-radius ground ADR-0047 §A2 and
  ADR-0048 established: a 48-pair state machine that touches no git today would gain a git failure
  mode on every transition.

## Consequences

### Positive

- The system's highest-risk step gains the entry condition its three lower-risk siblings already had.
- A named rollback target exists in the manifest for every Step 5 run, so a circuit breaker can say
  what to roll back to instead of leaving the operator to reconstruct it.
- ADR-0049's `isolation: "none"` tolerance becomes provably safe rather than merely usually safe.

### Negative

- **This is an instruction, not an enforcement** (ADR-0041/ADR-0045's distinction, applied again):
  it is prose in a SKILL.md that a model is asked to follow. The harness pins that the instruction
  exists; nothing pins that it is obeyed.
- A legitimate resume into a deliberately dirty tree now needs an explicit stash. Accepted: it is
  one command, and the alternative is silence.

## Correction 2026-07-28 (ADR-0068 retires §D4's reconciliation paragraph)

**ADR-0068 (issue #176) supersedes §D4's reconciliation paragraph**, the one that read: "at Step 5
entry the tree is clean; every dirty tree observed after that point was produced by Step 5 itself."
That paragraph reconciled this ADR's clean-tree pre-flight against ADR-0049 §D2's dirty-tree
`isolation: "none"` tolerance. ADR-0068 §D6 retires §D2 outright — the tester now commits and merges
its own worktree before the coder's worktree is created, so no dirty-tree-by-design condition
survives for §D4 to reconcile against. A paragraph that reconciles two conditions is moot once one
of them no longer exists.

This ADR's own pre-flight (the clean-tree entry check, D1–D3, D5, D6) is **untouched**: it guards
Step 5 entry, a boundary ADR-0068 does not touch, and it remains the condition that makes the
tester's subsequent worktree-and-merge protocol safe to run against.

See `docs/architecture/ADR-0068-176-worktree-isolation-contract.md` §D5, §D6 for the full account.
